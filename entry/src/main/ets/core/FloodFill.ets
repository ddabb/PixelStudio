/**
 * core/FloodFill.ets — 泛洪填充（纯逻辑层，不依赖 ArkUI）。
 * 精确颜色匹配（packed ARGB 全等，含 alpha）；4 连通；visited 标记 + Int32Array
 * 种子栈无递归，每像素至多入栈一次（1.1.0：四向对称种子 + 棋盘格抖动）。
 * 返回是否发生变更（false = 越界 / 目标色与替换色相同 / 抖动下无着色点）。
 */

import { PixelBuffer } from './PixelBuffer';
import { MirrorMode } from './Raster';

export class FloodFill {
  /**
   * @param mode 对称模式：镜像种子点去重后各自独立泛洪（Y/XY 时对称区域同步填）。
   * @param dither 棋盘格抖动：连通域判定不变，仅 (x+y) 偶数像素着色。
   */
  static fill(buf: PixelBuffer, x: number, y: number, argb: number,
    mode: MirrorMode = MirrorMode.None, dither: boolean = false): boolean {
    const sx: number[] = [x];
    const sy: number[] = [y];
    if (mode === MirrorMode.X || mode === MirrorMode.XY) {
      sx.push(buf.w - 1 - x);
      sy.push(y);
    }
    if (mode === MirrorMode.Y || mode === MirrorMode.XY) {
      sx.push(x);
      sy.push(buf.h - 1 - y);
    }
    if (mode === MirrorMode.XY) {
      sx.push(buf.w - 1 - x);
      sy.push(buf.h - 1 - y);
    }
    let changed = false;
    for (let i = 0; i < sx.length; i++) {
      if (FloodFill.fillOnce(buf, sx[i], sy[i], argb, dither)) {
        changed = true;
      }
    }
    return changed;
  }

  /** 单种子泛洪：BFS + visited（入栈即标记，每像素至多一次）。 */
  private static fillOnce(buf: PixelBuffer, x: number, y: number,
    argb: number, dither: boolean): boolean {
    if (!buf.inBounds(x, y)) {
      return false;
    }
    const target = buf.getPx(x, y);
    if (target === argb) {
      return false;
    }
    const w = buf.w;
    const h = buf.h;
    const visited = new Uint8Array(w * h);
    const stack = new Int32Array(w * h);
    let sp = 0;
    stack[sp++] = y * w + x;
    visited[y * w + x] = 1;
    let changed = false;
    while (sp > 0) {
      const p = stack[--sp];
      const px = p % w;
      const py = (p - px) / w;
      if (!dither || (px + py) % 2 === 0) {
        buf.setPx(px, py, argb);
        changed = true;
      }
      sp = FloodFill.seed(buf, visited, stack, sp, px - 1, py, target);
      sp = FloodFill.seed(buf, visited, stack, sp, px + 1, py, target);
      sp = FloodFill.seed(buf, visited, stack, sp, px, py - 1, target);
      sp = FloodFill.seed(buf, visited, stack, sp, px, py + 1, target);
    }
    return changed;
  }

  /** 4 邻域入栈：界内 + 未访问 + 仍为目标色（visited 入栈即标，栈容量恒够）。 */
  private static seed(buf: PixelBuffer, visited: Uint8Array, stack: Int32Array,
    sp: number, x: number, y: number, target: number): number {
    if (x < 0 || y < 0 || x >= buf.w || y >= buf.h) {
      return sp;
    }
    const idx = y * buf.w + x;
    if (visited[idx] !== 0 || buf.getPx(x, y) !== target) {
      return sp;
    }
    visited[idx] = 1;
    stack[sp++] = idx;
    return sp;
  }
}
