/**
 * core/Raster.ets — 图元光栅（纯逻辑层，不依赖 ArkUI）。
 * Bresenham 直线 + NxN 笔刷 stamp + 四向对称映射（MirrorMode，1.1.0）。
 * 约定：笔刷 offset = -floor((size-1)/2)（size=1 单像素；size=2 覆盖 [x, x+1]；
 * size=3 以落点为中心 3×3）。
 */

import { PixelBuffer } from './PixelBuffer';

/** 四向对称（1.1.0）：X=左右镜像；Y=上下镜像；XY=中心对称（四点同落）。 */
export enum MirrorMode {
  None = 0,
  X = 1,
  Y = 2,
  XY = 3
}

export class Raster {
  /** NxN 笔刷落点；按 MirrorMode 同时落 1~4 个对称点（画布中线自重合）。 */
  static stamp(buf: PixelBuffer, x: number, y: number, size: number, argb: number,
    mode: MirrorMode): void {
    Raster.stampOnce(buf, x, y, size, argb);
    if (mode === MirrorMode.X || mode === MirrorMode.XY) {
      Raster.stampOnce(buf, buf.w - 1 - x, y, size, argb);
    }
    if (mode === MirrorMode.Y || mode === MirrorMode.XY) {
      Raster.stampOnce(buf, x, buf.h - 1 - y, size, argb);
    }
    if (mode === MirrorMode.XY) {
      Raster.stampOnce(buf, buf.w - 1 - x, buf.h - 1 - y, size, argb);
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

  /** Bresenham 直线（stroke 插值与直线工具共用），逐点 stamp（含对称）。 */
  static drawLine(buf: PixelBuffer, x0: number, y0: number, x1: number, y1: number,
    size: number, argb: number, mode: MirrorMode): void {
    let x = x0;
    let y = y0;
    const dx = Math.abs(x1 - x0);
    const dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1;
    const sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    while (true) {
      Raster.stamp(buf, x, y, size, argb, mode);
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
    size: number, argb: number, mode: MirrorMode, filled: boolean): void {
    const xa = Math.min(x0, x1);
    const xb = Math.max(x0, x1);
    const ya = Math.min(y0, y1);
    const yb = Math.max(y0, y1);
    if (filled) {
      for (let y = ya; y <= yb; y++) {
        Raster.fillSpan(buf, xa, xb, y, argb, mode);
      }
      return;
    }
    Raster.drawLine(buf, xa, ya, xb, ya, size, argb, mode);
    Raster.drawLine(buf, xa, yb, xb, yb, size, argb, mode);
    Raster.drawLine(buf, xa, ya, xa, yb, size, argb, mode);
    Raster.drawLine(buf, xb, ya, xb, yb, size, argb, mode);
  }

  /** 中点椭圆（双区域迭代，4 路对称）：bbox (x0,y0)-(x1,y1)，中心取左上+半径（偶边长向下取整）；
   * filled=true 时按弧点行跨度填充。退化（rx/ry=0）回退为直线。 */
  static strokeEllipse(buf: PixelBuffer, x0: number, y0: number, x1: number, y1: number,
    size: number, argb: number, mode: MirrorMode, filled: boolean): void {
    const xa = Math.min(x0, x1);
    const xb = Math.max(x0, x1);
    const ya = Math.min(y0, y1);
    const yb = Math.max(y0, y1);
    const rx = Math.floor((xb - xa) / 2);
    const ry = Math.floor((yb - ya) / 2);
    const cx = xa + rx;
    const cy = ya + ry;
    if (rx === 0 || ry === 0) {
      Raster.drawLine(buf, xa, ya, xb, yb, size, argb, mode);
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
      Raster.ellipsePlot(buf, cx, cy, x, y, size, argb, mode, filled);
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
      Raster.ellipsePlot(buf, cx, cy, x, y, size, argb, mode, filled);
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
    size: number, argb: number, mode: MirrorMode, filled: boolean): void {
    if (filled) {
      Raster.fillSpan(buf, cx - x, cx + x, cy - y, argb, mode);
      Raster.fillSpan(buf, cx - x, cx + x, cy + y, argb, mode);
      return;
    }
    Raster.stamp(buf, cx + x, cy + y, size, argb, mode);
    Raster.stamp(buf, cx - x, cy + y, size, argb, mode);
    Raster.stamp(buf, cx + x, cy - y, size, argb, mode);
    Raster.stamp(buf, cx - x, cy - y, size, argb, mode);
  }

  /** 行填充（含对称行/列）；x0/x1 任意顺序。 */
  private static fillSpan(buf: PixelBuffer, x0: number, x1: number, y: number,
    argb: number, mode: MirrorMode): void {
    const xa = Math.min(x0, x1);
    const xb = Math.max(x0, x1);
    Raster.fillSpanOnce(buf, xa, xb, y, argb);
    if (mode === MirrorMode.X || mode === MirrorMode.XY) {
      const mx = buf.w - 1;
      Raster.fillSpanOnce(buf, mx - xb, mx - xa, y, argb);
    }
    if (mode === MirrorMode.Y || mode === MirrorMode.XY) {
      Raster.fillSpanOnce(buf, xa, xb, buf.h - 1 - y, argb);
    }
    if (mode === MirrorMode.XY) {
      const mx = buf.w - 1;
      Raster.fillSpanOnce(buf, mx - xb, mx - xa, buf.h - 1 - y, argb);
    }
  }

  private static fillSpanOnce(buf: PixelBuffer, xa: number, xb: number,
    y: number, argb: number): void {
    for (let x = xa; x <= xb; x++) {
      buf.setPx(x, y, argb);
    }
  }
}
