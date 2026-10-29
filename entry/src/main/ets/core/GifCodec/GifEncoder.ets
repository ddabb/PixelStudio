/**
 * core/GifCodec/GifEncoder.ets — GIF89a 编码器（开发计划 §6.1/§14，M4 批）。
 * 源码移植自 PocketToolbox（自有代码，LZW + 中位切分量化），本工程扩展：
 *  1. 透明色索引（GIF89a 图形控制扩展透明标志 + 保留调色板槽位）；
 *  2. fixedPalette 固定调色板直接映射模式（导出页"按当前调色板映射"，§4.1）。
 * 纯逻辑层：无 UI / 无 @ohos 依赖，hypium 直测（编码产物字节级校验，§8）。
 * 不变量：同一输入 + 同一选项 → 输出字节确定（单元测试锁定）。
 */

export class GifFrameData {
  width: number = 0;
  height: number = 0;
  /** 帧延迟，单位 1/100 秒。 */
  delayCs: number = 0;
  /** RGBA 像素，长度 = width * height * 4。 */
  pixels: Uint8Array = new Uint8Array(0);
}

export class GifEncodeOptions {
  /** 0 = 无限循环；1 = 播放一次（不写 Netscape 块）；N(>1) = 播放 N 次。 */
  loopCount: number = 0;
  /** 高清档：启用 Floyd-Steinberg 抖动。 */
  dither: boolean = false;
  /** 保留透明：alpha<128 像素映射到透明索引（GCE 透明标志）。 */
  transparent: boolean = false;
  /** 固定调色板直接映射模式（RGB 三元组，≤256 色）；null = 中位切分量化。 */
  fixedPalette: Uint8Array | null = null;
}

class ByteWriter {
  private buf: Uint8Array;
  private len: number = 0;

  constructor(capacity: number) {
    if (capacity < 64) {
      capacity = 64;
    }
    this.buf = new Uint8Array(capacity);
  }

  private ensure(extra: number): void {
    if (this.len + extra <= this.buf.length) {
      return;
    }
    let newCap: number = this.buf.length * 2;
    while (newCap < this.len + extra) {
      newCap *= 2;
    }
    const next: Uint8Array = new Uint8Array(newCap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
  }

  writeByte(value: number): void {
    this.ensure(1);
    this.buf[this.len] = value & 0xFF;
    this.len++;
  }

  writeBytes(bytes: Uint8Array): void {
    this.ensure(bytes.length);
    this.buf.set(bytes, this.len);
    this.len += bytes.length;
  }

  writeAscii(text: string): void {
    this.ensure(text.length);
    for (let i = 0; i < text.length; i++) {
      this.buf[this.len] = text.charCodeAt(i) & 0xFF;
      this.len++;
    }
  }

  writeU16LE(value: number): void {
    this.writeByte(value & 0xFF);
    this.writeByte((value >> 8) & 0xFF);
  }

  getLength(): number {
    return this.len;
  }

  toUint8Array(): Uint8Array {
    return this.buf.slice(0, this.len);
  }
}

class ColorCount {
  color: number = 0; // 0xRRGGBB
  count: number = 0;
}

function channelValue(packed: number, channel: number): number {
  if (channel === 0) {
    return (packed >> 16) & 0xFF;
  }
  if (channel === 1) {
    return (packed >> 8) & 0xFF;
  }
  return packed & 0xFF;
}

/**
 * 中位切分颜色量化：跨帧采样建立直方图（15-bit 分桶，桶内保存精确色均值），
 * 输出不超过 maxColors 色的调色板（RGB 三元组）。
 * alpha<128 像素不参与调色板（透明由保留槽位承担）。
 */
export function quantizeToPalette(frames: GifFrameData[], maxColors: number): Uint8Array {
  const counts: Uint32Array = new Uint32Array(32768);
  const sumR: Uint32Array = new Uint32Array(32768);
  const sumG: Uint32Array = new Uint32Array(32768);
  const sumB: Uint32Array = new Uint32Array(32768);
  for (let f = 0; f < frames.length; f++) {
    const frame: GifFrameData = frames[f];
    const pixelCount: number = frame.pixels.length >> 2;
    // 采样上限约 26 万像素，防止超大图拖慢量化
    const step: number = Math.max(1, Math.floor(pixelCount / 262144));
    for (let i = 0; i < pixelCount; i += step) {
      const p: number = i * 4;
      if (frame.pixels[p + 3] < 128) {
        continue;
      }
      const r: number = frame.pixels[p];
      const g: number = frame.pixels[p + 1];
      const b: number = frame.pixels[p + 2];
      const key: number = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      counts[key]++;
      sumR[key] += r;
      sumG[key] += g;
      sumB[key] += b;
    }
  }
  const colors: ColorCount[] = [];
  for (let key = 0; key < 32768; key++) {
    const c: number = counts[key];
    if (c === 0) {
      continue;
    }
    const cc: ColorCount = new ColorCount();
    cc.color =
      (Math.round(sumR[key] / c) << 16) | (Math.round(sumG[key] / c) << 8) | Math.round(sumB[key] / c);
    cc.count = c;
    colors.push(cc);
  }
  if (colors.length === 0) {
    return new Uint8Array(3);
  }
  const boxes: ColorCount[][] = [colors];
  while (boxes.length < maxColors) {
    // 选通道跨度最大的盒子分裂
    let bestBox: number = -1;
    let bestRange: number = 0;
    let bestChannel: number = 0;
    for (let b = 0; b < boxes.length; b++) {
      const box: ColorCount[] = boxes[b];
      if (box.length < 2) {
        continue;
      }
      for (let ch = 0; ch < 3; ch++) {
        let minV: number = 255;
        let maxV: number = 0;
        for (let i = 0; i < box.length; i++) {
          const v: number = channelValue(box[i].color, ch);
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
    const box: ColorCount[] = boxes[bestBox];
    boxes.splice(bestBox, 1);
    const channel: number = bestChannel;
    box.sort((a: ColorCount, b: ColorCount): number => {
      return channelValue(a.color, channel) - channelValue(b.color, channel);
    });
    let totalCount: number = 0;
    for (let i = 0; i < box.length; i++) {
      totalCount += box[i].count;
    }
    let acc: number = 0;
    let splitAt: number = 1;
    for (let i = 0; i < box.length - 1; i++) {
      acc += box[i].count;
      if (acc * 2 >= totalCount) {
        splitAt = i + 1;
        break;
      }
    }
    boxes.push(box.slice(0, splitAt));
    boxes.push(box.slice(splitAt));
  }
  // 每盒输出计数加权平均色
  const palette: Uint8Array = new Uint8Array(boxes.length * 3);
  for (let b = 0; b < boxes.length; b++) {
    const box: ColorCount[] = boxes[b];
    let sR: number = 0;
    let sG: number = 0;
    let sB: number = 0;
    let sW: number = 0;
    for (let i = 0; i < box.length; i++) {
      const w: number = box[i].count;
      const c: number = box[i].color;
      sR += ((c >> 16) & 0xFF) * w;
      sG += ((c >> 8) & 0xFF) * w;
      sB += (c & 0xFF) * w;
      sW += w;
    }
    palette[b * 3] = Math.round(sR / sW);
    palette[b * 3 + 1] = Math.round(sG / sW);
    palette[b * 3 + 2] = Math.round(sB / sW);
  }
  return palette;
}

function nearestPaletteIndex(r: number, g: number, b: number, palette: Uint8Array): number {
  let best: number = 0;
  let bestDist: number = Number.MAX_VALUE;
  const count: number = palette.length / 3;
  for (let i = 0; i < count; i++) {
    const dr: number = palette[i * 3] - r;
    const dg: number = palette[i * 3 + 1] - g;
    const db: number = palette[i * 3 + 2] - b;
    const dist: number = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
      if (dist === 0) {
        break;
      }
    }
  }
  return best;
}

function clampChannel(v: number): number {
  if (v < 0) {
    return 0;
  }
  if (v > 255) {
    return 255;
  }
  return Math.round(v);
}

/**
 * 将 RGBA 帧映射为调色板索引。近邻搜索使用 15-bit 量化缓存（建议由调用方跨帧共享）。
 * transparentIndex >= 0 时 alpha<128 像素映射到透明索引；否则透明像素映射到 0 号色。
 */
export function mapFrameToIndices(
  frame: GifFrameData,
  palette: Uint8Array,
  dither: boolean,
  ditherCache: Int16Array,
  transparentIndex: number
): Uint8Array {
  const w: number = frame.width;
  const h: number = frame.height;
  const n: number = w * h;
  const indices: Uint8Array = new Uint8Array(n);
  const pixels: Uint8Array = frame.pixels;
  const cache: Int16Array = ditherCache !== undefined ? ditherCache : new Int16Array(32768).fill(-1);
  if (!dither) {
    for (let i = 0; i < n; i++) {
      const p: number = i * 4;
      if (pixels[p + 3] < 128) {
        indices[i] = transparentIndex >= 0 ? transparentIndex : 0;
        continue;
      }
      const r: number = pixels[p];
      const g: number = pixels[p + 1];
      const b: number = pixels[p + 2];
      const cacheKey: number = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      let idx: number = cache[cacheKey];
      if (idx < 0) {
        idx = nearestPaletteIndex(r, g, b, palette);
        cache[cacheKey] = idx;
      }
      indices[i] = idx;
    }
    return indices;
  }
  // Floyd-Steinberg 抖动（透明像素不参与误差扩散）
  const errR: Float32Array = new Float32Array(n);
  const errG: Float32Array = new Float32Array(n);
  const errB: Float32Array = new Float32Array(n);
  for (let y: number = 0; y < h; y++) {
    for (let x: number = 0; x < w; x++) {
      const i: number = y * w + x;
      const p: number = i * 4;
      if (pixels[p + 3] < 128) {
        indices[i] = transparentIndex >= 0 ? transparentIndex : 0;
        continue;
      }
      const r: number = clampChannel(pixels[p] + errR[i]);
      const g: number = clampChannel(pixels[p + 1] + errG[i]);
      const b: number = clampChannel(pixels[p + 2] + errB[i]);
      const cacheKey: number = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      let idx: number = cache[cacheKey];
      if (idx < 0) {
        idx = nearestPaletteIndex(r, g, b, palette);
        cache[cacheKey] = idx;
      }
      indices[i] = idx;
      const er: number = r - palette[idx * 3];
      const eg: number = g - palette[idx * 3 + 1];
      const eb: number = b - palette[idx * 3 + 2];
      if (x + 1 < w) {
        errR[i + 1] += er * 7 / 16;
        errG[i + 1] += eg * 7 / 16;
        errB[i + 1] += eb * 7 / 16;
      }
      if (y + 1 < h) {
        const below: number = i + w;
        if (x > 0) {
          errR[below - 1] += er * 3 / 16;
          errG[below - 1] += eg * 3 / 16;
          errB[below - 1] += eb * 3 / 16;
        }
        errR[below] += er * 5 / 16;
        errG[below] += eg * 5 / 16;
        errB[below] += eb * 5 / 16;
        if (x + 1 < w) {
          errR[below + 1] += er * 1 / 16;
          errG[below + 1] += eg * 1 / 16;
          errB[below + 1] += eb * 1 / 16;
        }
      }
    }
  }
  return indices;
}

/**
 * GIF LZW 压缩：输出裸比特流（不含子块切分）。
 * 事实标准约定：解码器建表比编码器晚一个条目，编码器在 nextCode 达到
 * (1<<codeSize)+1 时才加宽码宽；表满（4095）前发出 Clear 重置。
 */
export function lzwEncode(indices: Uint8Array, minCodeSize: number): Uint8Array {
  const clearCode: number = 1 << minCodeSize;
  const eoiCode: number = clearCode + 1;
  const writer: ByteWriter = new ByteWriter(1024);
  let codeSize: number = minCodeSize + 1;
  const dict: Map<number, number> = new Map<number, number>();
  let bitBuf: number = 0;
  let bitCnt: number = 0;
  let nextCode: number = eoiCode + 1;

  const emit = (code: number): void => {
    bitBuf |= code << bitCnt;
    bitCnt += codeSize;
    while (bitCnt >= 8) {
      writer.writeByte(bitBuf & 0xFF);
      bitBuf >>= 8;
      bitCnt -= 8;
    }
  };

  emit(clearCode);
  if (indices.length === 0) {
    emit(eoiCode);
    if (bitCnt > 0) {
      writer.writeByte(bitBuf & 0xFF);
    }
    return writer.toUint8Array();
  }
  let prefix: number = indices[0];
  for (let i = 1; i < indices.length; i++) {
    const k: number = indices[i];
    const key: number = (prefix << 8) | k;
    const found: number = dict.get(key) ?? -1;
    if (found >= 0) {
      prefix = found;
      continue;
    }
    emit(prefix);
    dict.set(key, nextCode);
    if (nextCode === 4095) {
      // 表满前最后一步：发出 Clear 并重置字典
      nextCode++;
      emit(clearCode);
      dict.clear();
      codeSize = minCodeSize + 1;
      nextCode = eoiCode + 1;
    } else {
      nextCode++;
      if (nextCode === (1 << codeSize) + 1 && codeSize < 12) {
        codeSize++;
      }
    }
    prefix = k;
  }
  emit(prefix);
  emit(eoiCode);
  if (bitCnt > 0) {
    writer.writeByte(bitBuf & 0xFF);
  }
  return writer.toUint8Array();
}

function paletteBitsFor(colorCount: number): number {
  let bits: number = 1;
  while ((1 << bits) < colorCount) {
    bits++;
  }
  if (bits < 2) {
    bits = 2;
  }
  if (bits > 8) {
    bits = 8;
  }
  return bits;
}

/**
 * 编码多帧 GIF89a。所有帧必须同尺寸（由调用方归一化）。
 * transparent = true 时调色板末尾保留一个透明槽位（GCE 透明标志指向该索引）。
 */
export function encodeGif(frames: GifFrameData[], options: GifEncodeOptions): Uint8Array {
  if (frames.length === 0) {
    throw new Error('GifEncoder: frames is empty');
  }
  const width: number = frames[0].width;
  const height: number = frames[0].height;
  if (width <= 0 || height <= 0 || width > 65535 || height > 65535) {
    throw new Error('GifEncoder: invalid frame size');
  }
  for (let i = 0; i < frames.length; i++) {
    if (frames[i].width !== width || frames[i].height !== height) {
      throw new Error('GifEncoder: frame size mismatch');
    }
    if (frames[i].pixels.length !== width * height * 4) {
      throw new Error('GifEncoder: pixel buffer size mismatch');
    }
  }
  // 调色板：固定映射模式直接采用，否则中位切分量化（透明模式预留 1 槽）。
  let palette: Uint8Array;
  if (options.fixedPalette !== null) {
    const fp: Uint8Array = options.fixedPalette;
    if (fp.length === 0 || fp.length % 3 !== 0) {
      throw new Error('GifEncoder: invalid fixed palette');
    }
    palette = fp.slice();
  } else {
    palette = quantizeToPalette(frames, options.transparent ? 255 : 256);
  }
  let colorCount: number = palette.length / 3;
  const transparentIndex: number = options.transparent ? colorCount : -1;
  if (options.transparent) {
    if (colorCount + 1 > 256) {
      throw new Error('GifEncoder: too many colors with transparent slot');
    }
    const grown: Uint8Array = new Uint8Array(palette.length + 3);
    grown.set(palette);
    grown[palette.length] = 0;
    grown[palette.length + 1] = 0;
    grown[palette.length + 2] = 0;
    palette = grown;
    colorCount++;
  }
  const bits: number = paletteBitsFor(colorCount);
  const tableSize: number = 1 << bits;
  const minCodeSize: number = bits;

  const writer: ByteWriter = new ByteWriter(4096);
  writer.writeAscii('GIF89a');
  writer.writeU16LE(width);
  writer.writeU16LE(height);
  writer.writeByte(0x80 | ((bits - 1) << 4) | (bits - 1));
  writer.writeByte(0); // 背景色索引
  writer.writeByte(0); // 像素宽高比
  // 全局调色板（不足 2^bits 补零）
  writer.writeBytes(palette);
  for (let i = colorCount; i < tableSize; i++) {
    writer.writeByte(0);
    writer.writeByte(0);
    writer.writeByte(0);
  }
  // Netscape 循环块：loopCount=1(播放一次)时不写；0=无限；N=播放 N 次(值 N-1)
  if (options.loopCount !== 1) {
    const loopValue: number = options.loopCount <= 0 ? 0 : options.loopCount - 1;
    writer.writeByte(0x21);
    writer.writeByte(0xFF);
    writer.writeByte(0x0B);
    writer.writeAscii('NETSCAPE2.0');
    writer.writeByte(0x03);
    writer.writeByte(0x01);
    writer.writeU16LE(loopValue);
    writer.writeByte(0);
  }
  const ditherCache: Int16Array = new Int16Array(32768);
  ditherCache.fill(-1);
  for (let f = 0; f < frames.length; f++) {
    const frame: GifFrameData = frames[f];
    const indices: Uint8Array = mapFrameToIndices(frame, palette, options.dither, ditherCache, transparentIndex);
    // 图形控制扩展（bit0 = 透明标志）
    writer.writeByte(0x21);
    writer.writeByte(0xF9);
    writer.writeByte(0x04);
    writer.writeByte(options.transparent ? 0x01 : 0x00);
    writer.writeU16LE(frame.delayCs);
    writer.writeByte(options.transparent ? transparentIndex : 0x00);
    writer.writeByte(0x00);
    // 图像描述符
    writer.writeByte(0x2C);
    writer.writeU16LE(0);
    writer.writeU16LE(0);
    writer.writeU16LE(width);
    writer.writeU16LE(height);
    writer.writeByte(0x00);
    // LZW 图像数据（子块切分，每块最大 255 字节）
    writer.writeByte(minCodeSize);
    const raw: Uint8Array = lzwEncode(indices, minCodeSize);
    let pos: number = 0;
    while (pos < raw.length) {
      const chunk: number = Math.min(255, raw.length - pos);
      writer.writeByte(chunk);
      writer.writeBytes(raw.subarray(pos, pos + chunk));
      pos += chunk;
    }
    writer.writeByte(0);
  }
  writer.writeByte(0x3B);
  return writer.toUint8Array();
}
