/**
 * core/Resample.ets — 最近邻整数倍放大 + 网格线（纯逻辑层，M4 导出管线）。
 * 像素复制式放大：k× 后每个源像素变为 k×k 色块（无插值、无半透明、确定）。
 * 用途：PNG/GIF 导出 1×/2×/4×/8× 档位（开发计划 §4.1）。
 * 网格线（PNG 导出带网格开关）：放大后块边界（右/下缘）画 1px 自适应对比灰线，
 * 亮底画深线、暗底画浅线；透明像素跳过（透明保留）；最外圈不画（画面保持出血）。
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

  /** 底色亮度阈值：> 此值画深色线，否则浅色线（与 ChartRender.luminance 同口径）。 */
  static readonly GRID_LUM_THRESHOLD = 140;
  /** 网格线灰：深/浅（不透明，画在 alpha>0 的像素上）。 */
  static readonly GRID_DARK = 0x40;
  static readonly GRID_LIGHT = 0xC0;

  /** 在已放大（块边长 k）的 RGBA 缓冲上原位画块边界网格线（PNG 导出带网格开关）。
   *  规则：块右/下缘 1px（x%k===k-1 且 x<w-1，行同理）；alpha=0 跳过；
   *  亮度 > GRID_LUM_THRESHOLD 画 GRID_DARK 否则 GRID_LIGHT（不透明覆盖）。
   *  k 必须 ≥2 整数（1× 每像素皆边界，无意义）；零分配（复用调用方缓冲）。 */
  static drawGridLines(buf: Uint8Array, w: number, h: number, k: number): void {
    if (w < 1 || h < 1 || k < 2 || Math.floor(k) !== k || buf.length !== w * h * 4) {
      throw new Error('Resample.drawGridLines: invalid arguments');
    }
    for (let y = 0; y < h; y++) {
      const onRow: boolean = y % k === k - 1 && y < h - 1;
      for (let x = 0; x < w; x++) {
        if (!onRow && !(x % k === k - 1 && x < w - 1)) {
          continue;
        }
        const i: number = (y * w + x) * 4;
        if (buf[i + 3] === 0) {
          continue;
        }
        const lum: number = 0.299 * buf[i] + 0.587 * buf[i + 1] + 0.114 * buf[i + 2];
        const c: number = lum > Resample.GRID_LUM_THRESHOLD ? Resample.GRID_DARK : Resample.GRID_LIGHT;
        buf[i] = c;
        buf[i + 1] = c;
        buf[i + 2] = c;
        buf[i + 3] = 255;
      }
    }
  }
}
