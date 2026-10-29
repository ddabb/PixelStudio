/**
 * core/BeadStats.ets — 拼豆统计与分板（开发计划 §6.7/§13.5，M4 批）。
 * 量化直方图 = 材料清单（色号/名称/数量/占比/建议包数）；
 * 分板 = 29×29 标准方板切块 + 行优先拼接序号。
 * 不变量：只读输入；同一输入 → 清单与序号确定（单元测试锁定，Pillow 独立比对）。
 */

import { BeadColor } from './Palettes';

/** 建议包数基准：主流品牌零售包约 1000 颗（提示值，实物以包装为准）。 */
export const BEADS_PER_PACK = 1000;
/** 标准方板钉位边长（29×29）。 */
export const BEAD_BOARD_SIZE = 29;

/** 材料清单条目：一个豆色一行。 */
export class BeadEntry {
  readonly beadIndex: number;
  readonly code: string;
  readonly name: string;
  readonly argb: number;
  /** 使用数量（颗）。 */
  readonly count: number;
  /** 占比（0-1，分母 = 非空位总豆数）。 */
  readonly ratio: number;
  /** 建议包数 = ceil(count / BEADS_PER_PACK)。 */
  readonly packs: number;

  constructor(beadIndex: number, code: string, name: string, argb: number, count: number, ratio: number, packs: number) {
    this.beadIndex = beadIndex;
    this.code = code;
    this.name = name;
    this.argb = argb;
    this.count = count;
    this.ratio = ratio;
    this.packs = packs;
  }
}

/** 材料清单：按数量降序（同数量按豆色索引升序，保证确定性）。 */
export class BeadManifest {
  /** 非空位总豆数。 */
  readonly total: number;
  readonly entries: BeadEntry[];

  constructor(total: number, entries: BeadEntry[]) {
    this.total = total;
    this.entries = entries;
  }

  entryForBead(beadIndex: number): BeadEntry | undefined {
    for (const e of this.entries) {
      if (e.beadIndex === beadIndex) {
        return e;
      }
    }
    return undefined;
  }
}

export class BeadStats {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /** 量化索引表 → 材料清单（-1 = 空钉位不计）。 */
  static manifest(indices: Int32Array, beads: BeadColor[]): BeadManifest {
    const counts: Int32Array = new Int32Array(beads.length);
    let total = 0;
    for (let i = 0; i < indices.length; i++) {
      const bi = indices[i];
      if (bi < 0 || bi >= beads.length) {
        continue;
      }
      counts[bi]++;
      total++;
    }
    const entries: BeadEntry[] = [];
    for (let bi = 0; bi < beads.length; bi++) {
      if (counts[bi] <= 0) {
        continue;
      }
      const bead = beads[bi];
      const ratio = total > 0 ? counts[bi] / total : 0;
      const packs = Math.ceil(counts[bi] / BEADS_PER_PACK);
      entries.push(new BeadEntry(bi, bead.code, bead.name, bead.argb, counts[bi], ratio, packs));
    }
    entries.sort((a: BeadEntry, b: BeadEntry): number => {
      if (a.count !== b.count) {
        return b.count - a.count;
      }
      return a.beadIndex - b.beadIndex;
    });
    return new BeadManifest(total, entries);
  }

  /** 横向板数 = ceil(w / 板宽)。 */
  static boardsAcross(w: number, boardSize: number = BEAD_BOARD_SIZE): number {
    if (boardSize <= 0) {
      throw new Error('BeadStats: invalid board size');
    }
    return Math.max(1, Math.ceil(w / boardSize));
  }

  /** 总板数（行优先编号总数）。 */
  static boardCount(w: number, h: number, boardSize: number = BEAD_BOARD_SIZE): number {
    return BeadStats.boardsAcross(w, boardSize) * BeadStats.boardsAcross(h, boardSize);
  }

  /** 像素 → 所在板序号（行优先拼接序号，0 起）。 */
  static boardIndex(x: number, y: number, w: number, boardSize: number = BEAD_BOARD_SIZE): number {
    const boardsX = BeadStats.boardsAcross(w, boardSize);
    const bx = Math.floor(x / boardSize);
    const by = Math.floor(y / boardSize);
    return by * boardsX + bx;
  }
}
