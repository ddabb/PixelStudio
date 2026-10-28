/**
 * core/Palettes.ets — 调色板模型与内置色表（M3，开发计划 §4.1/§6.7）。
 * 预置：PICO-8（16 色）/ GameBoy DMG（4 色）/ 灰阶（8 级）/ CGA（16 色）——公开色彩表。
 * 拼豆品牌：豆色常量表（色号/名称/RGB，每品牌 ≤128 色，随包只增不改，§6.7）；
 * 屏幕预览以豆色 RGB 渲染兜底，实物以批次为准。
 * 注意：内置调色板显示名经资源键 palette_name_{id} 本地化（zh/en），自定义调色板用 name 字段。
 */

import { ColorUtil } from './ColorUtil';

export enum PaletteKind {
  Preset = 0,
  Bead = 1,
  Custom = 2
}

export class Palette {
  readonly id: string;
  name: string;
  readonly kind: PaletteKind;
  readonly colors: number[];

  constructor(id: string, name: string, kind: PaletteKind, colors: number[]) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.colors = colors;
  }
}

/** 拼豆豆色条目：色号 + 名称 + RGB（hex 构造，非法回退纯黑）。 */
export class BeadColor {
  readonly code: string;
  readonly name: string;
  readonly argb: number;

  constructor(code: string, name: string, hex: string) {
    this.code = code;
    this.name = name;
    const c = ColorUtil.parseHex(hex);
    this.argb = c === undefined ? 0xFF000000 : c;
  }
}

/** 拼豆品牌：豆色常量表；可导出为调色板（供色卡展示与选色）。 */
export class BeadBrand {
  readonly id: string;
  readonly name: string;
  readonly colors: BeadColor[];

  constructor(id: string, name: string, colors: BeadColor[]) {
    this.id = id;
    this.name = name;
    this.colors = colors;
  }

  toPalette(): Palette {
    const list: number[] = [];
    for (const c of this.colors) {
      list.push(c.argb);
    }
    return new Palette(`bead_${this.id}`, this.name, PaletteKind.Bead, list);
  }
}

export class Palettes {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  static readonly PICO8: Palette = new Palette('pico8', 'PICO-8', PaletteKind.Preset, [
    0xFF000000, 0xFF1D2B53, 0xFF7E2553, 0xFF008751,
    0xFFAB5236, 0xFF5F574F, 0xFFC2C3C7, 0xFFFFF1E8,
    0xFFFF004D, 0xFFFFA300, 0xFFFFEC27, 0xFF00E436,
    0xFF29ADFF, 0xFF83769C, 0xFFFF77A8, 0xFFFFCCAA
  ]);

  static readonly GB_DMG: Palette = new Palette('gbdmg', 'GameBoy DMG', PaletteKind.Preset, [
    0xFF0F380F, 0xFF306230, 0xFF8BAC0F, 0xFF9BBC0F
  ]);

  static readonly GRAYSCALE: Palette = new Palette('gray', '灰阶', PaletteKind.Preset, [
    0xFF000000, 0xFF242424, 0xFF484848, 0xFF6D6D6D,
    0xFF919191, 0xFFB6B6B6, 0xFFDADADA, 0xFFFFFFFF
  ]);

  static readonly CGA: Palette = new Palette('cga', 'CGA', PaletteKind.Preset, [
    0xFF000000, 0xFF0000AA, 0xFF00AA00, 0xFF00AAAA,
    0xFFAA0000, 0xFFAA00AA, 0xFFAA5500, 0xFFAAAAAA,
    0xFF555555, 0xFF5555FF, 0xFF55FF55, 0xFF55FFFF,
    0xFFFF5555, 0xFFFF55FF, 0xFFFFFF55, 0xFFFFFFFF
  ]);

  static readonly PERLER: BeadBrand = new BeadBrand('perler', 'Perler 拼豆', [
    new BeadColor('P01', '白色', 'FFFFFF'),
    new BeadColor('P02', '黑色', '1A1A1A'),
    new BeadColor('P03', '灰色', '9E9E9E'),
    new BeadColor('P04', '深灰', '4A4A4A'),
    new BeadColor('P05', '棕色', '6B4326'),
    new BeadColor('P06', '浅棕', 'B97A56'),
    new BeadColor('P07', '棕褐', 'D2B48C'),
    new BeadColor('P08', '奶油', 'FFF3D6'),
    new BeadColor('P09', '红色', 'ED1C24'),
    new BeadColor('P10', '深红', '8B0000'),
    new BeadColor('P11', '覆盆子', 'E30B5C'),
    new BeadColor('P12', '粉色', 'FFC0CB'),
    new BeadColor('P13', '玫红', 'FF69B4'),
    new BeadColor('P14', '橙色', 'FF8000'),
    new BeadColor('P15', '铁锈红', 'C1440E'),
    new BeadColor('P16', '三文鱼', 'FA8072'),
    new BeadColor('P17', '蜜桃', 'FFCBA4'),
    new BeadColor('P18', '黄色', 'FFD700'),
    new BeadColor('P19', '金色', 'DAA520'),
    new BeadColor('P20', '浅黄', 'FFFACD'),
    new BeadColor('P21', '绿色', '00A651'),
    new BeadColor('P22', '深绿', '006400'),
    new BeadColor('P23', '浅绿', '90EE90'),
    new BeadColor('P24', '青柠', '32CD32'),
    new BeadColor('P25', '橄榄', '808000'),
    new BeadColor('P26', '水鸭', '008080'),
    new BeadColor('P27', '青色', '00E5FF'),
    new BeadColor('P28', '天蓝', '87CEEB'),
    new BeadColor('P29', '蓝色', '0057B8'),
    new BeadColor('P30', '深蓝', '00008B'),
    new BeadColor('P31', '藏青', '000080'),
    new BeadColor('P32', '紫色', '800080'),
    new BeadColor('P33', '浅紫', 'C3B1E1'),
    new BeadColor('P34', '薰衣草', 'E6E6FA'),
    new BeadColor('P35', '梅紫', '8E4585'),
    new BeadColor('P36', '洋红', 'FF00FF')
  ]);

  static readonly HAMA: BeadBrand = new BeadBrand('hama', 'Hama 拼豆', [
    new BeadColor('H01', '白色', 'FFFFFF'),
    new BeadColor('H02', '黑色', '111111'),
    new BeadColor('H03', '灰色', '999999'),
    new BeadColor('H04', '深灰', '555555'),
    new BeadColor('H05', '棕色', '7B4B2A'),
    new BeadColor('H06', '浅棕', 'C49A6C'),
    new BeadColor('H07', '米色', 'F5DEB3'),
    new BeadColor('H08', '奶油', 'FFF8DC'),
    new BeadColor('H09', '红色', 'E02020'),
    new BeadColor('H10', '暗红', '9B1B1B'),
    new BeadColor('H11', '粉色', 'FFB6C1'),
    new BeadColor('H12', '玫瑰', 'FF8FA3'),
    new BeadColor('H13', '橙色', 'FF7F27'),
    new BeadColor('H14', '深橙', 'CC5500'),
    new BeadColor('H15', '沙色', 'EAD8A6'),
    new BeadColor('H16', '黄色', 'FFD800'),
    new BeadColor('H17', '金色', 'C9A227'),
    new BeadColor('H18', '浅黄', 'FFF9B0'),
    new BeadColor('H19', '海绿', '2E8B57'),
    new BeadColor('H20', '墨绿', '14532D'),
    new BeadColor('H21', '开心果', '93C572'),
    new BeadColor('H22', '柠檬绿', '9ACD32'),
    new BeadColor('H23', '绿松', '40E0D0'),
    new BeadColor('H24', '深青', '00CED1'),
    new BeadColor('H25', '天蓝', '7EC8E3'),
    new BeadColor('H26', '蓝色', '1E6FD9'),
    new BeadColor('H27', '深蓝', '153E90'),
    new BeadColor('H28', '藏青', '14213D'),
    new BeadColor('H29', '紫色', '6A3D9A'),
    new BeadColor('H30', '丁香', 'C8A2C8'),
    new BeadColor('H31', '绛紫', 'C2185B'),
    new BeadColor('H32', '荧光粉', 'FF1493')
  ]);

  /** 全部内置调色板（预置 + 拼豆品牌导出）。 */
  static builtinPalettes(): Palette[] {
    return [
      Palettes.PICO8,
      Palettes.GB_DMG,
      Palettes.GRAYSCALE,
      Palettes.CGA,
      Palettes.PERLER.toPalette(),
      Palettes.HAMA.toPalette()
    ];
  }

  static beadBrand(id: string): BeadBrand | undefined {
    if (id === Palettes.PERLER.id) {
      return Palettes.PERLER;
    }
    if (id === Palettes.HAMA.id) {
      return Palettes.HAMA;
    }
    return undefined;
  }
}
