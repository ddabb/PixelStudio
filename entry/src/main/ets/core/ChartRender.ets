/**
 * core/ChartRender.ets — 拼豆图纸渲染（开发计划 §5.3/§6.7/§13.5，M4 批）。
 * 十字绣式图纸：豆色真实 RGB 格子 + 1px 网格线 + 空钉位棋盘格 +
 * 29×29 分板 2px 品红分割线 + 分板序号 + 行/列每 10 格标尺 + 每色符号（跳 I/O/0/1）。
 * 输出 RGBA，经最近邻放大 + ImagePacker 落 PNG（复用渲染管线，§6.7）。
 * 不变量：只读输入；同一输入 + 同一选项 → 输出确定（分板序号无错位，测试锁定）。
 */

import { BeadColor } from './Palettes';
import { BeadStats, BEAD_BOARD_SIZE } from './BeadStats';
import { Font5x7 } from './Font5x7';

/** 图纸尺寸（像素）。 */
export class BeadChartSize {
  readonly w: number;
  readonly h: number;

  constructor(w: number, h: number) {
    this.w = w;
    this.h = h;
  }
}

export class BeadChartOptions {
  /** 每豆格边长（px，≥8）。 */
  cellSize: number = 16;
  /** 分板边长（格数）。 */
  boardSize: number = BEAD_BOARD_SIZE;
  /** 行/列表头边距（px）。 */
  margin: number = 20;
  showSymbols: boolean = true;
  showRulers: boolean = true;
  showBoardNumbers: boolean = true;
  /** 豆色符号表（按材料清单数量降序分配；跳过易混 I/O/0/1）。 */
  symbolChars: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
}

export class ChartRender {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /** 相对亮度（0-255）。 */
  static luminance(argb: number): number {
    const r: number = (argb >>> 16) & 0xFF;
    const g: number = (argb >>> 8) & 0xFF;
    const b: number = argb & 0xFF;
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }

  /** 图纸输出尺寸。 */
  static chartSize(w: number, h: number, opts: BeadChartOptions): BeadChartSize {
    ChartRender.validate(w, h, opts);
    return new BeadChartSize(opts.margin + w * opts.cellSize, opts.margin + h * opts.cellSize);
  }

  private static validate(w: number, h: number, opts: BeadChartOptions): void {
    if (w < 1 || h < 1 || opts.cellSize < 8 || Math.floor(opts.cellSize) !== opts.cellSize
      || opts.boardSize < 1 || opts.margin < 0 || opts.margin > 4096) {
      throw new Error('ChartRender: invalid arguments');
    }
  }

  /** 渲染图纸（RGBA）；indices 长度须 = w*h，-1 = 空钉位。 */
  static renderChart(indices: Int32Array, w: number, h: number, beads: BeadColor[],
    opts: BeadChartOptions): Uint8Array {
    ChartRender.validate(w, h, opts);
    if (indices.length !== w * h) {
      throw new Error('ChartRender: indices size mismatch');
    }
    const cell: number = opts.cellSize;
    const margin: number = opts.margin;
    const cw: number = margin + w * cell;
    const ch: number = margin + h * cell;
    const out: Uint8Array = new Uint8Array(cw * ch * 4);
    // 白底
    for (let i = 0; i < cw * ch; i++) {
      const d: number = i * 4;
      out[d] = 255;
      out[d + 1] = 255;
      out[d + 2] = 255;
      out[d + 3] = 255;
    }
    const setPx = (x: number, y: number, argb: number): void => {
      if (x < 0 || y < 0 || x >= cw || y >= ch) {
        return;
      }
      const d: number = (y * cw + x) * 4;
      out[d] = (argb >>> 16) & 0xFF;
      out[d + 1] = (argb >>> 8) & 0xFF;
      out[d + 2] = argb & 0xFF;
      out[d + 3] = 255;
    };
    // 符号分配：材料清单数量降序（确定性）。
    const symbolForBead: string[] = new Array<string>(beads.length);
    symbolForBead.fill('');
    const manifest = BeadStats.manifest(indices, beads);
    for (let i = 0; i < manifest.entries.length && i < opts.symbolChars.length; i++) {
      symbolForBead[manifest.entries[i].beadIndex] = opts.symbolChars.charAt(i);
    }
    const boardsX: number = BeadStats.boardsAcross(w, opts.boardSize);
    const boardsY: number = BeadStats.boardsAcross(h, opts.boardSize);
    // 豆色格 + 网格线（右/下 1px 浅灰）
    for (let cy = 0; cy < h; cy++) {
      for (let cx = 0; cx < w; cx++) {
        const x0: number = margin + cx * cell;
        const y0: number = margin + cy * cell;
        const bi: number = indices[cy * w + cx];
        const bead: BeadColor | undefined = bi >= 0 && bi < beads.length ? beads[bi] : undefined;
        for (let yy = 0; yy < cell; yy++) {
          for (let xx = 0; xx < cell; xx++) {
            const px: number = x0 + xx;
            const py: number = y0 + yy;
            if (bead === undefined) {
              // 空钉位棋盘格（2px）
              setPx(px, py, ((px >> 1) + (py >> 1)) % 2 === 0 ? 0xFFF4F4F4 : 0xFFE9E9E9);
            } else {
              setPx(px, py, bead.argb);
            }
          }
        }
        // 网格线：格右缘 + 下缘
        for (let yy = 0; yy < cell; yy++) {
          setPx(x0 + cell - 1, y0 + yy, 0xFFD9D9D9);
        }
        for (let xx = 0; xx < cell; xx++) {
          setPx(x0 + xx, y0 + cell - 1, 0xFFD9D9D9);
        }
      }
    }
    // 分板分割线：2px 品红（覆盖网格线）
    const gridBottom: number = margin + h * cell;
    const gridRight: number = margin + w * cell;
    for (let bx = 1; bx < boardsX; bx++) {
      const x: number = margin + bx * opts.boardSize * cell - 1;
      for (let yy = margin; yy < gridBottom; yy++) {
        setPx(x, yy, 0xFFFF00FF);
        setPx(x - 1, yy, 0xFFFF00FF);
      }
    }
    for (let by = 1; by < boardsY; by++) {
      const y: number = margin + by * opts.boardSize * cell - 1;
      for (let xx = margin; xx < gridRight; xx++) {
        setPx(xx, y, 0xFFFF00FF);
        setPx(xx, y - 1, 0xFFFF00FF);
      }
    }
    // 行/列标尺：每 10 格标注序号（1 起）
    if (opts.showRulers) {
      const rulerY: number = Math.max(0, (margin - Font5x7.GLYPH_H) >> 1);
      for (let c = 10; c <= w; c += 10) {
        const label: string = String(c);
        Font5x7.drawText(out, cw, ch, margin + c * cell - Font5x7.textWidth(label, 1) - 1,
          rulerY, label, 0xFF666666, 1);
      }
      for (let r = 10; r <= h; r += 10) {
        const label: string = String(r);
        Font5x7.drawText(out, cw, ch, margin - Font5x7.textWidth(label, 1) - 2,
          margin + r * cell - Font5x7.GLYPH_H - 2, label, 0xFF666666, 1);
      }
    }
    // 分板序号：板左上角格，对比色（可溢出到邻格，网格线为界）
    if (opts.showBoardNumbers) {
      for (let by = 0; by < boardsY; by++) {
        for (let bx = 0; bx < boardsX; bx++) {
          const firstCell: number = indices[Math.min(by * opts.boardSize, h - 1) * w
            + Math.min(bx * opts.boardSize, w - 1)];
          const firstBead: BeadColor | undefined =
            firstCell >= 0 && firstCell < beads.length ? beads[firstCell] : undefined;
          const lum: number = firstBead === undefined ? 255 : ChartRender.luminance(firstBead.argb);
          const label: string = String(by * boardsX + bx + 1);
          Font5x7.drawText(out, cw, ch, margin + bx * opts.boardSize * cell + 2,
            margin + by * opts.boardSize * cell + 2, label,
            lum > 140 ? 0xFF202020 : 0xFFF0F0F0, 1);
        }
      }
    }
    // 每色符号（板首格留给分板序号）
    if (opts.showSymbols) {
      for (let cy = 0; cy < h; cy++) {
        for (let cx = 0; cx < w; cx++) {
          const bi: number = indices[cy * w + cx];
          if (bi < 0 || bi >= beads.length || symbolForBead[bi].length === 0) {
            continue;
          }
          if (opts.showBoardNumbers && cx % opts.boardSize === 0 && cy % opts.boardSize === 0) {
            continue;
          }
          const bead: BeadColor = beads[bi];
          const color: number = ChartRender.luminance(bead.argb) > 140 ? 0xFF202020 : 0xFFF0F0F0;
          const x0: number = margin + cx * cell + ((cell - Font5x7.GLYPH_W) >> 1);
          const y0: number = margin + cy * cell + ((cell - Font5x7.GLYPH_H) >> 1);
          Font5x7.drawText(out, cw, ch, x0, y0, symbolForBead[bi], color, 1);
        }
      }
    }
    return out;
  }
}
