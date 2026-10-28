/**
 * core/ColorUtil.ets — 颜色空间转换纯函数（M3，开发计划 §4.1 调色板：HSB 取色器 + HEX 输入）。
 * packed ARGB（0xAARRGGBB，与 ArkUI Color 一致）⇄ HSB（h 0-360 / s 0-100 / b 0-100）⇄ HEX（#RRGGBB）。
 */

/** HSB 颜色值（色相 0-360，饱和度 0-100，明度 0-100）。 */
export class HsbColor {
  readonly h: number;
  readonly s: number;
  readonly b: number;

  constructor(h: number, s: number, b: number) {
    this.h = h;
    this.s = s;
    this.b = b;
  }
}

export class ColorUtil {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /** packed ARGB → HSB（四舍五入取整）。 */
  static toHsb(argb: number): HsbColor {
    const r = ((argb >>> 16) & 0xFF) / 255;
    const g = ((argb >>> 8) & 0xFF) / 255;
    const b = (argb & 0xFF) / 255;
    const max = Math.max(r, Math.max(g, b));
    const min = Math.min(r, Math.min(g, b));
    const d = max - min;
    let h = 0;
    if (d > 0) {
      if (max === r) {
        h = 60 * (((g - b) / d) % 6);
      } else if (max === g) {
        h = 60 * ((b - r) / d + 2);
      } else {
        h = 60 * ((r - g) / d + 4);
      }
    }
    if (h < 0) {
      h += 360;
    }
    const s = max <= 0 ? 0 : (d / max) * 100;
    return new HsbColor(Math.round(h), Math.round(s), Math.round(max * 100));
  }

  /** HSB → packed ARGB（alpha 恒 255）；入参越界自动钳制。 */
  static fromHsb(h: number, s: number, b: number): number {
    const hh = ((h % 360) + 360) % 360;
    const ss = Math.max(0, Math.min(100, s)) / 100;
    const vv = Math.max(0, Math.min(100, b)) / 100;
    const c = vv * ss;
    const hp = hh / 60;
    const x = c * (1 - Math.abs((hp % 2) - 1));
    let r = 0;
    let g = 0;
    let bl = 0;
    if (hp < 1) {
      r = c;
      g = x;
    } else if (hp < 2) {
      r = x;
      g = c;
    } else if (hp < 3) {
      g = c;
      bl = x;
    } else if (hp < 4) {
      g = x;
      bl = c;
    } else if (hp < 5) {
      r = x;
      bl = c;
    } else {
      r = c;
      bl = x;
    }
    const m = vv - c;
    const ri = Math.round((r + m) * 255);
    const gi = Math.round((g + m) * 255);
    const bi = Math.round((bl + m) * 255);
    return ((0xFF << 24) | (ri << 16) | (gi << 8) | bi) >>> 0;
  }

  /** 解析 "#RRGGBB" / "RRGGBB"（大小写不限）；非法输入返回 undefined。 */
  static parseHex(text: string): number | undefined {
    let t = text.trim();
    if (t.startsWith('#')) {
      t = t.substring(1);
    }
    if (t.length !== 6) {
      return undefined;
    }
    const r = ColorUtil.hexPair(t, 0);
    const g = ColorUtil.hexPair(t, 2);
    const b = ColorUtil.hexPair(t, 4);
    if (r < 0 || g < 0 || b < 0) {
      return undefined;
    }
    return ((0xFF << 24) | (r << 16) | (g << 8) | b) >>> 0;
  }

  /** 格式化为 "#RRGGBB"（大写）。 */
  static toHex(argb: number): string {
    const hex = (argb & 0xFFFFFF).toString(16).toUpperCase();
    return '#'.concat('000000'.substring(hex.length)).concat(hex);
  }

  private static hexPair(t: string, start: number): number {
    const hi = ColorUtil.hexDigit(t.charCodeAt(start));
    const lo = ColorUtil.hexDigit(t.charCodeAt(start + 1));
    if (hi < 0 || lo < 0) {
      return -1;
    }
    return hi * 16 + lo;
  }

  private static hexDigit(c: number): number {
    if (c >= 48 && c <= 57) {
      return c - 48;
    }
    if (c >= 97 && c <= 102) {
      return c - 87;
    }
    if (c >= 65 && c <= 70) {
      return c - 55;
    }
    return -1;
  }
}
