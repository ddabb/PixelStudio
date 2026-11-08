/**
 * core/ImageImport.ets — 用户图片转像素画纯函数管线（1.6.0，功能需求 §6）。
 * 全离线确定性算法（非 AI / 非云端推理，§12 非目标重申）：
 * ① 缩采样 resample：几何适配（cover 居中裁切 / contain 完整留边）+ 区块采样
 *    （box alpha 加权面积平均 / nearest 中心取样），alpha 二值化（<128 全透明）；
 * ② 抖动 applyBayer：量化前固定 Bayer 4×4 有序偏置（确定性阈值表）；
 * ③ 量化 quantize：按调色板（0xAARRGGBB 数组）加权最近色（d²=2Δr²+4Δg²+3Δb²，
 *    同距取小索引，与 BeadQuantize 同口径）；
 * ④ 自动色板 autoPalette：15-bit 分桶中位切分（与 GifEncoder.quantizeToPalette
 *    同内核口径，单帧版；透明像素不参与统计）。
 * 不变量：纯函数不改输入缓冲；同输入 + 同参数 → 输出逐字节一致（单测锁定）；
 * 非法参数直接抛错（沿用 Resample 校验风格）。
 */

/** 输出网格上限（与 PXS_MAX_CELLS=65536 口径一致，上限 256²）。 */
const MAX_OUT_CELLS = 65536;

/** Bayer 4×4 有序抖动阈值表（固定，0..15，确定性）。 */
const BAYER_4X4: number[] = [
  0, 8, 2, 10,
  12, 4, 14, 6,
  3, 11, 1, 9,
  15, 7, 13, 5
];
/** 抖动偏置幅度（±32 内；过大产生噪点、过小抖动不可见）。 */
const BAYER_AMPLITUDE = 64;

export class ImageImport {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /**
   * 等比输出尺寸（project 模式画布贴合原图宽高比，杜绝留白/裁切）：
   * longSide 档位 = 长边；短边等比换算四舍五入，最小 1。
   * 返回 [w, h]（方向与源图一致）；非法参数抛错。
   */
  static fitOutSize(sw: number, sh: number, longSide: number): number[] {
    if (sw < 1 || sh < 1 || longSide < 1) {
      throw new Error('ImageImport.fitOutSize: invalid arguments');
    }
    const long = Math.max(sw, sh);
    const short = Math.min(sw, sh);
    const shortOut = Math.max(1, Math.round(longSide * short / long));
    return sw >= sh ? [longSide, shortOut] : [shortOut, longSide];
  }

  /**
   * 缩采样：src（RGBA，sw×sh）→ outW×outH RGBA。
   * cover：等比缩放至铺满后居中裁切；contain：等比内接 + 透明留边并居中。
   * box=true 按 alpha 加权面积平均（避免透明边缘发黑）；false 取区块中心像素。
   * 输出 alpha 二值化：区块平均 alpha <128 → 全透明，否则不透明。
   */
  static resample(src: Uint8Array, sw: number, sh: number,
    outW: number, outH: number, cover: boolean, box: boolean): Uint8Array {
    if (sw < 1 || sh < 1 || outW < 1 || outH < 1
      || outW * outH > MAX_OUT_CELLS || src.length !== sw * sh * 4) {
      throw new Error('ImageImport.resample: invalid arguments');
    }
    // 输出空间中的虚拟缩放尺寸与窗口偏移（cover 窗口居中裁切；contain 图像居中放置）。
    const scale: number = cover
      ? Math.max(outW / sw, outH / sh)
      : Math.min(outW / sw, outH / sh);
    const dw: number = sw * scale;
    const dh: number = sh * scale;
    const offX: number = cover ? (dw - outW) / 2 : (outW - dw) / 2;
    const offY: number = cover ? (dh - outH) / 2 : (outH - dh) / 2;
    const out: Uint8Array = new Uint8Array(outW * outH * 4);
    for (let oy = 0; oy < outH; oy++) {
      // 输出像素对应的源区块（源坐标系，浮点边界；contain 越界即留边）。
      const fy0: number = (oy - offY) / scale;
      const fy1: number = (oy + 1 - offY) / scale;
      for (let ox = 0; ox < outW; ox++) {
        const fx0: number = (ox - offX) / scale;
        const fx1: number = (ox + 1 - offX) / scale;
        const oi: number = (oy * outW + ox) * 4;
        if (fx1 <= 0 || fx0 >= sw || fy1 <= 0 || fy0 >= sh) {
          continue; // contain 透明留边
        }
        if (box) {
          ImageImport.boxSample(src, sw, sh, fx0, fx1, fy0, fy1, out, oi);
        } else {
          ImageImport.centerSample(src, sw, sh,
            (fx0 + fx1) / 2, (fy0 + fy1) / 2, out, oi);
        }
      }
    }
    return out;
  }

  /** 区块 alpha 加权面积平均 → 写单个输出像素（alpha 二值化）。 */
  private static boxSample(src: Uint8Array, sw: number, sh: number,
    fx0: number, fx1: number, fy0: number, fy1: number, out: Uint8Array, oi: number): void {
    let ix0: number = Math.floor(fx0);
    let ix1: number = Math.max(ix0 + 1, Math.ceil(fx1));
    let iy0: number = Math.floor(fy0);
    let iy1: number = Math.max(iy0 + 1, Math.ceil(fy1));
    ix0 = Math.max(0, ix0);
    ix1 = Math.min(sw, ix1);
    iy0 = Math.max(0, iy0);
    iy1 = Math.min(sh, iy1);
    const area: number = (ix1 - ix0) * (iy1 - iy0);
    if (area <= 0) {
      return;
    }
    let wSum = 0;
    let rSum = 0;
    let gSum = 0;
    let bSum = 0;
    let aSum = 0;
    for (let y = iy0; y < iy1; y++) {
      const row: number = y * sw * 4;
      for (let x = ix0; x < ix1; x++) {
        const i: number = row + x * 4;
        const a: number = src[i + 3];
        aSum += a;
        if (a === 0) {
          continue;
        }
        wSum += a;
        rSum += src[i] * a;
        gSum += src[i + 1] * a;
        bSum += src[i + 2] * a;
      }
    }
    if (aSum / area < 128 || wSum === 0) {
      return;
    }
    out[oi] = Math.round(rSum / wSum);
    out[oi + 1] = Math.round(gSum / wSum);
    out[oi + 2] = Math.round(bSum / wSum);
    out[oi + 3] = 0xFF;
  }

  /** 中心取样（最近邻）：越界中心夹取到边缘；alpha 二值化。 */
  private static centerSample(src: Uint8Array, sw: number, sh: number,
    cx: number, cy: number, out: Uint8Array, oi: number): void {
    const x: number = Math.min(sw - 1, Math.max(0, Math.floor(cx)));
    const y: number = Math.min(sh - 1, Math.max(0, Math.floor(cy)));
    const i: number = (y * sw + x) * 4;
    if (src[i + 3] < 128) {
      return;
    }
    out[oi] = src[i];
    out[oi + 1] = src[i + 1];
    out[oi + 2] = src[i + 2];
    out[oi + 3] = 0xFF;
  }

  /** Bayer 4×4 有序抖动（原位）：量化前对不透明像素 RGB 加固定偏置并夹取。 */
  static applyBayer(rgba: Uint8Array, w: number, h: number): void {
    if (w < 1 || h < 1 || rgba.length !== w * h * 4) {
      throw new Error('ImageImport.applyBayer: invalid arguments');
    }
    for (let y = 0; y < h; y++) {
      const by: number = (y & 3) * 4;
      for (let x = 0; x < w; x++) {
        const i: number = (y * w + x) * 4;
        if (rgba[i + 3] < 128) {
          continue;
        }
        const bias: number = (BAYER_4X4[by + (x & 3)] / 16 - 0.5) * BAYER_AMPLITUDE;
        rgba[i] = Math.min(255, Math.max(0, Math.round(rgba[i] + bias)));
        rgba[i + 1] = Math.min(255, Math.max(0, Math.round(rgba[i + 1] + bias)));
        rgba[i + 2] = Math.min(255, Math.max(0, Math.round(rgba[i + 2] + bias)));
      }
    }
  }

  /**
   * 按调色板量化（原位）：不透明像素映射到最近色（加权距离，同距取小索引）；
   * 输出恒不透明纯色，透明像素保持透明（无半透明脏色）。
   * colors 为 0xAARRGGBB 数组；空色板抛错。
   */
  static quantize(rgba: Uint8Array, colors: number[]): void {
    if (colors.length === 0) {
      throw new Error('ImageImport.quantize: empty palette');
    }
    for (let i = 0; i < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) {
        rgba[i + 3] = 0;
        continue;
      }
      const best: number = ImageImport.nearestColor(rgba[i], rgba[i + 1], rgba[i + 2], colors);
      rgba[i] = (best >>> 16) & 0xFF;
      rgba[i + 1] = (best >>> 8) & 0xFF;
      rgba[i + 2] = best & 0xFF;
      rgba[i + 3] = 0xFF;
    }
  }

  /** 加权最近色（d²=2Δr²+4Δg²+3Δb²，同距取小索引；BeadQuantize 同口径）。 */
  static nearestColor(r: number, g: number, b: number, colors: number[]): number {
    let best: number = colors[0];
    let bestD: number = Number.MAX_VALUE;
    for (let i = 0; i < colors.length; i++) {
      const c: number = colors[i];
      const dr: number = r - ((c >>> 16) & 0xFF);
      const dg: number = g - ((c >>> 8) & 0xFF);
      const db: number = b - (c & 0xFF);
      const d: number = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  /**
   * 自动色板：15-bit 分桶直方图 + 中位切分（与 GifEncoder.quantizeToPalette 同内核口径）。
   * 输入单帧 RGBA；透明像素（alpha<128）不参与统计；全透明输入返回空数组。
   * 输出 ≤maxColors 个 0xFFRRGGBB 色（按盒序确定）。
   */
  static autoPalette(rgba: Uint8Array, maxColors: number): number[] {
    if (maxColors < 1 || maxColors > 256) {
      throw new Error('ImageImport.autoPalette: invalid maxColors');
    }
    const counts: Uint32Array = new Uint32Array(32768);
    const sumR: Uint32Array = new Uint32Array(32768);
    const sumG: Uint32Array = new Uint32Array(32768);
    const sumB: Uint32Array = new Uint32Array(32768);
    const pixelCount: number = rgba.length >> 2;
    // 采样上限约 26 万像素（超大输出防拖慢；256²=65536 全量不触发）。
    const step: number = Math.max(1, Math.floor(pixelCount / 262144));
    let opaque = 0;
    for (let p = 0; p < pixelCount; p += step) {
      const i: number = p * 4;
      if (rgba[i + 3] < 128) {
        continue;
      }
      opaque++;
      const key: number = ((rgba[i] >> 3) << 10) | ((rgba[i + 1] >> 3) << 5) | (rgba[i + 2] >> 3);
      counts[key]++;
      sumR[key] += rgba[i];
      sumG[key] += rgba[i + 1];
      sumB[key] += rgba[i + 2];
    }
    if (opaque === 0) {
      return [];
    }
    // 分桶色（精确均值），进入盒子分裂。
    const buckets: number[][] = [];
    for (let key = 0; key < 32768; key++) {
      const c: number = counts[key];
      if (c === 0) {
        continue;
      }
      buckets.push([
        (Math.round(sumR[key] / c) << 16) | (Math.round(sumG[key] / c) << 8) | Math.round(sumB[key] / c),
        c
      ]);
    }
    const boxes: number[][][] = [buckets];
    while (boxes.length < maxColors) {
      let bestBox = -1;
      let bestRange = 0;
      let bestChannel = 0;
      for (let b = 0; b < boxes.length; b++) {
        const box: number[][] = boxes[b];
        if (box.length < 2) {
          continue;
        }
        for (let ch = 0; ch < 3; ch++) {
          let minV = 255;
          let maxV = 0;
          for (let i = 0; i < box.length; i++) {
            const v: number = (box[i][0] >> ((2 - ch) * 8)) & 0xFF;
            if (v < minV) {
              minV = v;
            }
            if (v > maxV) {
              maxV = v;
            }
          }
          if (maxV - minV > bestRange) {
            bestRange = maxV - minV;
            bestBox = b;
            bestChannel = ch;
          }
        }
      }
      if (bestBox < 0 || bestRange <= 0) {
        break;
      }
      const box: number[][] = boxes[bestBox];
      boxes.splice(bestBox, 1);
      const shift: number = (2 - bestChannel) * 8;
      box.sort((a: number[], b: number[]): number => {
        return ((a[0] >> shift) & 0xFF) - ((b[0] >> shift) & 0xFF);
      });
      let totalCount = 0;
      for (let i = 0; i < box.length; i++) {
        totalCount += box[i][1];
      }
      let acc = 0;
      let splitAt = 1;
      for (let i = 0; i < box.length - 1; i++) {
        acc += box[i][1];
        if (acc * 2 >= totalCount) {
          splitAt = i + 1;
          break;
        }
      }
      boxes.push(box.slice(0, splitAt));
      boxes.push(box.slice(splitAt));
    }
    // 每盒计数加权平均色 → 0xFFRRGGBB。
    const out: number[] = [];
    for (let b = 0; b < boxes.length; b++) {
      const box: number[][] = boxes[b];
      let sR = 0;
      let sG = 0;
      let sB = 0;
      let sW = 0;
      for (let i = 0; i < box.length; i++) {
        const w: number = box[i][1];
        const c: number = box[i][0];
        sR += ((c >> 16) & 0xFF) * w;
        sG += ((c >> 8) & 0xFF) * w;
        sB += (c & 0xFF) * w;
        sW += w;
      }
      // >>> 0 无符号化：位或结果默认有符号 int32，统一为 0xFFRRGGBB 正数口径。
      out.push((0xFF000000 | (Math.round(sR / sW) << 16) | (Math.round(sG / sW) << 8)
        | Math.round(sB / sW)) >>> 0);
    }
    return out;
  }

  /** 端到端管线（对话框/预览共用）：缩采样 → 抖动 → 量化（确定性）。 */
  static convert(src: Uint8Array, sw: number, sh: number, outW: number, outH: number,
    cover: boolean, box: boolean, dither: boolean,
    palette: number[] | undefined, autoColors: number): Uint8Array {
    const out: Uint8Array = ImageImport.resample(src, sw, sh, outW, outH, cover, box);
    if (dither) {
      ImageImport.applyBayer(out, outW, outH);
    }
    if (palette !== undefined && palette.length > 0) {
      ImageImport.quantize(out, palette);
    } else if (autoColors > 0) {
      const auto: number[] = ImageImport.autoPalette(out, autoColors);
      if (auto.length > 0) {
        ImageImport.quantize(out, auto);
      }
    }
    return out;
  }
}
