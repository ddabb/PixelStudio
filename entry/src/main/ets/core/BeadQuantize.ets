/**
 * core/BeadQuantize.ets — 拼豆量化纯函数（开发计划 §6.7，M3 批）。
 * 逐像素最近豆色匹配（加权 RGB 欧氏距离：d² = 2·Δr² + 4·Δg² + 3·Δb²）；
 * 输入为拍平后的合成帧（RGBA），alpha=0 = 空钉位不参与匹配；
 * 量化输出恒为纯色或空位（豆子不透明，无半透明）。
 * 不变量：只读映射（不修改输入缓冲）；同一输入 + 同一色号表 → 输出确定（单元测试锁定）。
 */

import { BeadColor } from './Palettes';

export class BeadQuantize {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /** 最近豆色索引（加权 RGB 欧氏距离，同距取小索引保证确定性）。 */
  static nearestIndex(r: number, g: number, b: number, beads: BeadColor[]): number {
    let best = 0;
    let bestD = Number.MAX_VALUE;
    for (let i = 0; i < beads.length; i++) {
      const a = beads[i].argb;
      const dr = r - ((a >>> 16) & 0xFF);
      const dg = g - ((a >>> 8) & 0xFF);
      const db = b - (a & 0xFF);
      const d = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /** 整帧量化：返回 w*h 色号索引表（Int32Array），-1 = 空钉位。 */
  static quantize(rgba: Uint8Array, w: number, h: number, beads: BeadColor[]): Int32Array {
    const out = new Int32Array(w * h);
    for (let p = 0; p < w * h; p++) {
      const i = p * 4;
      if (rgba[i + 3] === 0) {
        out[p] = -1;
        continue;
      }
      out[p] = BeadQuantize.nearestIndex(rgba[i], rgba[i + 1], rgba[i + 2], beads);
    }
    return out;
  }

  /** 量化预览渲染：豆色真实 RGB 填入 out（RGBA），空钉位保持透明（M4 图纸导出复用）。 */
  static renderPreview(indices: Int32Array, beads: BeadColor[], out: Uint8Array): void {
    for (let p = 0; p < indices.length; p++) {
      const i = p * 4;
      if (i + 3 >= out.length) {
        return;
      }
      const bi = indices[p];
      if (bi < 0 || bi >= beads.length) {
        out[i] = 0;
        out[i + 1] = 0;
        out[i + 2] = 0;
        out[i + 3] = 0;
        continue;
      }
      const a = beads[bi].argb;
      out[i] = (a >>> 16) & 0xFF;
      out[i + 1] = (a >>> 8) & 0xFF;
      out[i + 2] = a & 0xFF;
      out[i + 3] = 0xFF;
    }
  }
}
