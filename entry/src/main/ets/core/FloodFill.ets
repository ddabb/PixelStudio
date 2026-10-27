/**
 * core/FloodFill.ets — 扫描线泛洪填充（纯逻辑层，不依赖 ArkUI）。
 * 精确颜色匹配（packed ARGB 全等，含 alpha）；4 连通；Int32Array 种子栈无递归。
 * 返回是否发生变更（false = 越界 / 目标色与替换色相同）。
 */

import { PixelBuffer } from './PixelBuffer';

export class FloodFill {
  static fill(buf: PixelBuffer, x: number, y: number, argb: number): boolean {
    if (!buf.inBounds(x, y)) {
      return false;
    }
    const target = buf.getPx(x, y);
    if (target === argb) {
      return false;
    }
    const w = buf.w;
    const h = buf.h;
    let stack = new Int32Array(w * h);
    let sp = 0;
    stack[sp++] = y * w + x;
    while (sp > 0) {
      const p = stack[--sp];
      let px = p % w;
      let py = (p - px) / w;
      while (py >= 0 && buf.getPx(px, py) === target) {
        py--;
      }
      py++;
      let spanLeft = false;
      let spanRight = false;
      while (py < h && buf.getPx(px, py) === target) {
        buf.setPx(px, py, argb);
        if (px > 0) {
          if (buf.getPx(px - 1, py) === target) {
            if (!spanLeft) {
              if (sp === stack.length) {
                const grown = new Int32Array(stack.length * 2);
                grown.set(stack);
                stack = grown;
              }
              stack[sp++] = py * w + px - 1;
              spanLeft = true;
            }
          } else {
            spanLeft = false;
          }
        }
        if (px < w - 1) {
          if (buf.getPx(px + 1, py) === target) {
            if (!spanRight) {
              if (sp === stack.length) {
                const grown = new Int32Array(stack.length * 2);
                grown.set(stack);
                stack = grown;
              }
              stack[sp++] = py * w + px + 1;
              spanRight = true;
            }
          } else {
            spanRight = false;
          }
        }
        py++;
      }
    }
    return true;
  }
}
