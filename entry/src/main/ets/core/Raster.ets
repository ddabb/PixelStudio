/**
 * core/Raster.ets — 图元光栅（纯逻辑层，不依赖 ArkUI）。
 * Bresenham 直线 + NxN 笔刷 stamp + X 轴镜像映射。
 * 约定：笔刷 offset = -floor((size-1)/2)（size=1 单像素；size=2 覆盖 [x, x+1]；
 * size=3 以落点为中心 3×3）。
 */

import { PixelBuffer } from './PixelBuffer';

export class Raster {
  /** NxN 笔刷落点；mirrorX 时同时落 (w-1-x) 的对称点。 */
  static stamp(buf: PixelBuffer, x: number, y: number, size: number, argb: number, mirrorX: boolean): void {
    Raster.stampOnce(buf, x, y, size, argb);
    if (mirrorX) {
      Raster.stampOnce(buf, buf.w - 1 - x, y, size, argb);
    }
  }

  private static stampOnce(buf: PixelBuffer, x: number, y: number, size: number, argb: number): void {
    const base = -Math.floor((size - 1) / 2);
    for (let dy = 0; dy < size; dy++) {
      for (let dx = 0; dx < size; dx++) {
        buf.setPx(x + base + dx, y + base + dy, argb);
      }
    }
  }

  /** Bresenham 直线（stroke 插值与直线工具共用），逐点 stamp（含镜像）。 */
  static drawLine(buf: PixelBuffer, x0: number, y0: number, x1: number, y1: number,
    size: number, argb: number, mirrorX: boolean): void {
    let x = x0;
    let y = y0;
    const dx = Math.abs(x1 - x0);
    const dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1;
    const sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    while (true) {
      Raster.stamp(buf, x, y, size, argb, mirrorX);
      if (x === x1 && y === y1) {
        break;
      }
      const e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y += sy;
      }
    }
  }
}
