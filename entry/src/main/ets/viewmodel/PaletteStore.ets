/**
 * viewmodel/PaletteStore.ets — 调色板会话状态（M3，开发计划 §4.1 调色板模块）。
 * 活动调色板 / 自定义调色板（新建/保存/重命名/删除）/ 最近使用 8 色。
 * 持久化：沙箱纯文本 files/pixel/palettes.txt（行格式 `id|名称|#HEX,…`，首行标记 +
 * `@recents|#HEX,…`），避免 JSON 反序列化类型断言（ArkTS 约束）；
 * 结构变更即写盘，最近色随页退出落盘；损坏文件静默回退空自定义（不崩溃，§6.4 容错纪律）。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Palette, PaletteKind, Palettes } from '../core/Palettes';
import { ColorUtil } from '../core/ColorUtil';

const FILE_HEADER = '#ps_palette v1';
const RECENTS_KEY = '@recents';
const RECENTS_CAP = 8;

@ObservedV2
export class PaletteStore {
  /** 内置调色板（预置 + 拼豆品牌）。 */
  readonly builtins: Palette[] = Palettes.builtinPalettes();
  @Trace activeId: string = 'pico8';
  @Trace customPalettes: Palette[] = [];
  /** 最近使用 8 色（最新在前，去重）。 */
  @Trace recents: number[] = [];
  @Trace loaded: boolean = false;

  private context: common.Context | undefined = undefined;

  activePalette(): Palette | undefined {
    for (const p of this.builtins) {
      if (p.id === this.activeId) {
        return p;
      }
    }
    for (const p of this.customPalettes) {
      if (p.id === this.activeId) {
        return p;
      }
    }
    return undefined;
  }

  isCustom(id: string): boolean {
    for (const p of this.customPalettes) {
      if (p.id === id) {
        return true;
      }
    }
    return false;
  }

  setActive(id: string): void {
    if (this.activePaletteById(id) !== undefined) {
      this.activeId = id;
    }
  }

  private activePaletteById(id: string): Palette | undefined {
    for (const p of this.builtins) {
      if (p.id === id) {
        return p;
      }
    }
    for (const p of this.customPalettes) {
      if (p.id === id) {
        return p;
      }
    }
    return undefined;
  }

  /** 当前色入最近使用（去重置顶，容量 8）。 */
  pushRecent(color: number): void {
    const next: number[] = [color];
    for (const c of this.recents) {
      if (next.length >= RECENTS_CAP) {
        break;
      }
      if (c !== color) {
        next.push(c);
      }
    }
    this.recents = next;
  }

  /** 名称清洗：去首尾空白与行内分隔符/井号（防持久化行格式被破坏）。 */
  private static sanitizeName(name: string): string {
    return name.replace('|', '/').replace('#', '').replace('\n', ' ').trim();
  }

  createCustom(name: string): Palette | undefined {
    const n = PaletteStore.sanitizeName(name);
    if (n.length === 0) {
      return undefined;
    }
    const palette = new Palette(`c${Date.now().toString(36)}`, n, PaletteKind.Custom, []);
    this.customPalettes.push(palette);
    this.saveNow();
    return palette;
  }

  renameCustom(id: string, name: string): boolean {
    const n = PaletteStore.sanitizeName(name);
    if (n.length === 0) {
      return false;
    }
    for (const p of this.customPalettes) {
      if (p.id === id) {
        if (p.name === n) {
          return false;
        }
        p.name = n;
        this.saveNow();
        return true;
      }
    }
    return false;
  }

  deleteCustom(id: string): boolean {
    for (let i = 0; i < this.customPalettes.length; i++) {
      if (this.customPalettes[i].id === id) {
        this.customPalettes.splice(i, 1);
        if (this.activeId === id) {
          this.activeId = this.builtins[0].id;
        }
        this.saveNow();
        return true;
      }
    }
    return false;
  }

  addColorToCustom(id: string, color: number): boolean {
    for (const p of this.customPalettes) {
      if (p.id === id) {
        if (p.colors.includes(color)) {
          return false;
        }
        p.colors.push(color);
        this.saveNow();
        return true;
      }
    }
    return false;
  }

  /** 从自定义调色板移除指定色（存在才移除）。 */
  removeColorFromCustom(id: string, color: number): boolean {
    for (const p of this.customPalettes) {
      if (p.id === id) {
        const idx = p.colors.indexOf(color);
        if (idx < 0) {
          return false;
        }
        p.colors.splice(idx, 1);
        this.saveNow();
        return true;
      }
    }
    return false;
  }

  // ---------- 持久化（files/pixel/palettes.txt） ----------

  private filePath(): string {
    const ctx = this.context;
    if (ctx === undefined) {
      return '';
    }
    return `${ctx.filesDir}/pixel/palettes.txt`;
  }

  load(context: common.Context): void {
    this.context = context;
    try {
      const path = this.filePath();
      if (path.length > 0 && fs.accessSync(path)) {
        this.parse(fs.readTextSync(path));
      }
    } catch (e) {
      // 文件损坏/IO 异常：回退空自定义调色板，不崩溃。
    }
    this.loaded = true;
  }

  private parse(text: string): void {
    const customs: Palette[] = [];
    const lines = text.split('\n');
    for (const line of lines) {
      const t = line.trim();
      if (t.length === 0 || t.startsWith('#')) {
        continue;
      }
      const parts = t.split('|');
      if (parts[0] === RECENTS_KEY && parts.length >= 2) {
        this.recents = PaletteStore.parseHexList(parts[1], RECENTS_CAP);
        continue;
      }
      if (parts.length >= 3 && parts[0].startsWith('c')) {
        const name = parts[1].trim();
        if (name.length > 0) {
          customs.push(new Palette(parts[0], name, PaletteKind.Custom,
            PaletteStore.parseHexList(parts[2], 1024)));
        }
      }
    }
    this.customPalettes = customs;
  }

  private static parseHexList(text: string, cap: number): number[] {
    const out: number[] = [];
    for (const token of text.split(',')) {
      if (out.length >= cap) {
        break;
      }
      const c = ColorUtil.parseHex(token);
      if (c !== undefined) {
        out.push(c);
      }
    }
    return out;
  }

  saveNow(): void {
    const ctx = this.context;
    if (ctx === undefined) {
      return;
    }
    try {
      const dir = `${ctx.filesDir}/pixel`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const lines: string[] = [FILE_HEADER];
      const recents: string[] = [];
      for (const c of this.recents) {
        recents.push(ColorUtil.toHex(c));
      }
      lines.push(`${RECENTS_KEY}|${recents.join(',')}`);
      for (const p of this.customPalettes) {
        const hexes: string[] = [];
        for (const c of p.colors) {
          hexes.push(ColorUtil.toHex(c));
        }
        lines.push(`${p.id}|${p.name}|${hexes.join(',')}`);
      }
      const file = fs.openSync(this.filePath(),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, lines.join('\n'));
      fs.closeSync(file);
    } catch (e) {
      // 落盘失败静默（内存态仍可用；下次结构变更重试）。
    }
  }
}
