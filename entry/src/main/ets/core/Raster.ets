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

  /** 轴对齐矩形：filled=false 四边描线（笔宽生效），true 整域填充；坐标自动归一化。 */
  static strokeRect(buf: PixelBuffer, x0: number, y0: number, x1: number, y1: number,
    size: number, argb: number, mirrorX: boolean, filled: boolean): void {
    const xa = Math.min(x0, x1);
    const xb = Math.max(x0, x1);
    const ya = Math.min(y0, y1);
    const yb = Math.max(y0, y1);
    if (filled) {
      for (let y = ya; y <= yb; y++) {
        Raster.fillSpan(buf, xa, xb, y, argb, mirrorX);
      }
      return;
    }
    Raster.drawLine(buf, xa, ya, xb, ya, size, argb, mirrorX);
    Raster.drawLine(buf, xa, yb, xb, yb, size, argb, mirrorX);
    Raster.drawLine(buf, xa, ya, xa, yb, size, argb, mirrorX);
    Raster.drawLine(buf, xb, ya, xb, yb, size, argb, mirrorX);
  }

  /** 中点椭圆（双区域迭代，4 路对称）：bbox (x0,y0)-(x1,y1)，中心取左上+半径（偶边长向下取整）；
   * filled=true 时按弧点行跨度填充。退化（rx/ry=0）回退为直线。 */
  static strokeEllipse(buf: PixelBuffer, x0: number, y0: number, x1: number, y1: number,
    size: number, argb: number, mirrorX: boolean, filled: boolean): void {
    const xa = Math.min(x0, x1);
    const xb = Math.max(x0, x1);
    const ya = Math.min(y0, y1);
    const yb = Math.max(y0, y1);
    const rx = Math.floor((xb - xa) / 2);
    const ry = Math.floor((yb - ya) / 2);
    const cx = xa + rx;
    const cy = ya + ry;
    if (rx === 0 || ry === 0) {
      Raster.drawLine(buf, xa, ya, xb, yb, size, argb, mirrorX);
      return;
    }
    let x = 0;
    let y = ry;
    const rx2 = rx * rx;
    const ry2 = ry * ry;
    let d1 = ry2 - rx2 * ry + 0.25 * rx2;
    let dx = 2 * ry2 * x;
    let dy = 2 * rx2 * y;
    while (dx < dy) {
      Raster.ellipsePlot(buf, cx, cy, x, y, size, argb, mirrorX, filled);
      if (d1 < 0) {
        x++;
        dx += 2 * ry2;
        d1 += dx + ry2;
      } else {
        x++;
        y--;
        dx += 2 * ry2;
        dy -= 2 * rx2;
        d1 += dx - dy + ry2;
      }
    }
    let d2 = ry2 * (x + 0.5) * (x + 0.5) + rx2 * (y - 1) * (y - 1) - rx2 * ry2;
    while (y >= 0) {
      Raster.ellipsePlot(buf, cx, cy, x, y, size, argb, mirrorX, filled);
      if (d2 > 0) {
        y--;
        dy -= 2 * rx2;
        d2 += rx2 - dy;
      } else {
        y--;
        x++;
        dx += 2 * ry2;
        dy -= 2 * rx2;
        d2 += dx - dy + rx2;
      }
    }
  }

  private static ellipsePlot(buf: PixelBuffer, cx: number, cy: number, x: number, y: number,
    size: number, argb: number, mirrorX: boolean, filled: boolean): void {
    if (filled) {
      Raster.fillSpan(buf, cx - x, cx + x, cy - y, argb, mirrorX);
      Raster.fillSpan(buf, cx - x, cx + x, cy + y, argb, mirrorX);
      return;
    }
    Raster.stamp(buf, cx + x, cy + y, size, argb, mirrorX);
    Raster.stamp(buf, cx - x, cy + y, size, argb, mirrorX);
    Raster.stamp(buf, cx + x, cy - y, size, argb, mirrorX);
    Raster.stamp(buf, cx - x, cy - y, size, argb, mirrorX);
  }

  /** 行填充（含镜像行）；x0/x1 任意顺序。 */
  private static fillSpan(buf: PixelBuffer, x0: number, x1: number, y: number,
    argb: number, mirrorX: boolean): void {
    const xa = Math.min(x0, x1);
    const xb = Math.max(x0, x1);
    for (let x = xa; x <= xb; x++) {
      buf.setPx(x, y, argb);
    }
    if (mirrorX) {
      const mx = buf.w - 1;
      for (let x = xa; x <= xb; x++) {
        buf.setPx(mx - x, y, argb);
      }
    }
  }
}
