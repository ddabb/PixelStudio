/**
 * core/Font5x7.ets — 5×7 点阵字体（纯逻辑层，M4 拼豆图纸文字渲染）。
 * 字符集：空格 / '-' / 0-9 / A-Z（图纸行列表头、分板序号、豆色符号够用）。
 * 位图布局：每字形 7 行，每行 5 位（bit4 = 最左列），与经典 LCD 字库一致。
 * 不变量：只写目标缓冲（字形像素，背景不落笔）；越界裁剪；输出确定。
 */

const FONT_CHARS = ' -0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
/** 每字形 7 字节 × 2 个十六进制字符，顺序与 FONT_CHARS 一致（38 形）。 */
const FONT_DATA: string[] = [
  '00000000000000', // (空格)
  '0000001F000000', // -
  '0E11131519110E', // 0
  '040C040404040E', // 1
  '0E11010204081F', // 2
  '1F02040201110E', // 3
  '02060A121F0202', // 4
  '1F101E0101110E', // 5
  '0608101E11110E', // 6
  '1F010204080808', // 7
  '0E11110E11110E', // 8
  '0E11110F01020C', // 9
  '0E11111F111111', // A
  '1E11111E11111E', // B
  '0E11101010110E', // C
  '1C12111111121C', // D
  '1F10101E10101F', // E
  '1F10101E101010', // F
  '0E11101711110F', // G
  '1111111F111111', // H
  '0E04040404040E', // I
  '0702020202120C', // J
  '11121418141211', // K
  '1010101010101F', // L
  '111B1515111111', // M
  '11191513111111', // N
  '0E11111111110E', // O
  '1E11111E101010', // P
  '0E11111115120D', // Q
  '1E11111E141211', // R
  '0F10100E01011E', // S
  '1F040404040404', // T
  '1111111111110E', // U
  '11111111110A04', // V
  '1111111515150A', // W
  '11110A040A1111', // X
  '1111110A040404', // Y
  '1F01020408101F' // Z
];

export class Font5x7 {
  static readonly GLYPH_W = 5;
  static readonly GLYPH_H = 7;
  /** 字间距（像素，含在 advance 中）。 */
  static readonly ADVANCE = 6;

  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  private static hexVal(c: number): number {
    if (c >= 48 && c <= 57) {
      return c - 48;
    }
    if (c >= 65 && c <= 70) {
      return c - 55;
    }
    return 0;
  }

  /** 是否有该字形。 */
  static has(ch: string): boolean {
    return ch.length === 1 && FONT_CHARS.indexOf(ch) >= 0;
  }

  /** 取字形 7 字节；无该字符返回 undefined。 */
  static glyphBytes(ch: string): Uint8Array | undefined {
    const index: number = FONT_CHARS.indexOf(ch);
    if (index < 0) {
      return undefined;
    }
    const hex: string = FONT_DATA[index];
    const out: Uint8Array = new Uint8Array(Font5x7.GLYPH_H);
    for (let b = 0; b < Font5x7.GLYPH_H; b++) {
      const hi: number = Font5x7.hexVal(hex.charCodeAt(b * 2));
      const lo: number = Font5x7.hexVal(hex.charCodeAt(b * 2 + 1));
      out[b] = (hi << 4) | lo;
    }
    return out;
  }

  /** 文本渲染宽度（未知字符按空格计宽）。 */
  static textWidth(text: string, scale: number): number {
    if (text.length === 0) {
      return 0;
    }
    return text.length * Font5x7.ADVANCE * scale - scale;
  }

  /** 画文本（只写字形像素，背景不落笔；越界裁剪；scale ≥1 整数）。 */
  static drawText(px: Uint8Array, pw: number, ph: number, x: number, y: number,
    text: string, argb: number, scale: number): void {
    if (scale < 1 || Math.floor(scale) !== scale) {
      throw new Error('Font5x7.drawText: invalid scale');
    }
    const r: number = (argb >>> 16) & 0xFF;
    const g: number = (argb >>> 8) & 0xFF;
    const b: number = argb & 0xFF;
    const a: number = (argb >>> 24) & 0xFF;
    for (let i = 0; i < text.length; i++) {
      const glyph: Uint8Array | undefined = Font5x7.glyphBytes(text.charAt(i));
      if (glyph !== undefined) {
        for (let row = 0; row < Font5x7.GLYPH_H; row++) {
          const bits: number = glyph[row];
          for (let col = 0; col < Font5x7.GLYPH_W; col++) {
            if (((bits >> (Font5x7.GLYPH_W - 1 - col)) & 1) === 0) {
              continue;
            }
            for (let sy = 0; sy < scale; sy++) {
              const yy: number = y + row * scale + sy;
              if (yy < 0 || yy >= ph) {
                continue;
              }
              for (let sx = 0; sx < scale; sx++) {
                const xx: number = x + i * Font5x7.ADVANCE * scale + col * scale + sx;
                if (xx < 0 || xx >= pw) {
                  continue;
                }
                const d: number = (yy * pw + xx) * 4;
                px[d] = r;
                px[d + 1] = g;
                px[d + 2] = b;
                px[d + 3] = a;
              }
            }
          }
        }
      }
    }
  }
}
