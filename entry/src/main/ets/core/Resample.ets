/**
 * core/Resample.ets — 最近邻整数倍放大（纯逻辑层，M4 导出管线）。
 * 像素复制式放大：k× 后每个源像素变为 k×k 色块（无插值、无半透明、确定）。
 * 用途：PNG/GIF 导出 1×/2×/4×/8× 档位（开发计划 §4.1）。
 */

export class Resample {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /** 整数倍最近邻放大；k 必须 ≥1 整数，源长度须等于 w*h*4。 */
  static scaleNearest(src: Uint8Array, w: number, h: number, k: number): Uint8Array {
    if (w <= 0 || h <= 0 || k < 1 || Math.floor(k) !== k || src.length !== w * h * 4) {
      throw new Error('Resample.scaleNearest: invalid arguments');
    }
    if (k === 1) {
      return src.slice();
    }
    const tw: number = w * k;
    const th: number = h * k;
    const out: Uint8Array = new Uint8Array(tw * th * 4);
    // 先把源行横向复制成一条目标行，再整行纵向复制 k 次（零乘法寻址）。
    const rowBuf: Uint8Array = new Uint8Array(tw * 4);
    for (let sy = 0; sy < h; sy++) {
      const srcRow: number = sy * w * 4;
      for (let sx = 0; sx < w; sx++) {
        const s: number = srcRow + sx * 4;
        for (let r = 0; r < k; r++) {
          const d: number = (sx * k + r) * 4;
          rowBuf[d] = src[s];
          rowBuf[d + 1] = src[s + 1];
          rowBuf[d + 2] = src[s + 2];
          rowBuf[d + 3] = src[s + 3];
        }
      }
      for (let r = 0; r < k; r++) {
        out.set(rowBuf, ((sy * k + r) * tw) * 4);
      }
    }
    return out;
  }
}
