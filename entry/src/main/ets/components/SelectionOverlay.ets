/**
 * components/SelectionOverlay.ets — 选区蚂蚁线覆盖层（M2，§4.1 P0 静态虚线）。
 * 黑色实底描边 + 白色虚线双通道保证任意底色可见；Canvas 手绘虚线段（无平台
 * lineDash 依赖）。仅在存在选区时由 CanvasView 条件挂载；触摸穿透不挡笔触。
 * 坐标：Canvas 逻辑尺寸 = doc·zoom vp，选区矩形按 zoom 同比缩放。
 */

import { SelRect } from '../viewmodel/EditorSession';

const DASH_ON = 5;
const DASH_OFF = 4;
const OUTLINE_WIDTH = 3;
const DASH_WIDTH = 1.5;

@ComponentV2
export struct SelectionOverlay {
  @Require @Param sel: SelRect | undefined;
  @Require @Param zoom: number;
  @Require @Param docW: number;
  @Require @Param docH: number;

  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }

  @Monitor('sel', 'zoom')
  onSelChange(): void {
    this.draw();
  }

  private draw(): void {
    if (!this.ready || this.sel === undefined) {
      return;
    }
    const ctx = this.ctx;
    const cw = this.docW * this.zoom;
    const ch = this.docH * this.zoom;
    ctx.clearRect(0, 0, cw, ch);
    const x = this.sel.x * this.zoom;
    const y = this.sel.y * this.zoom;
    const w = this.sel.w * this.zoom;
    const h = this.sel.h * this.zoom;
    // 通道 1：黑色实底描边（对比底）。
    ctx.strokeStyle = '#FF000000';
    ctx.lineWidth = OUTLINE_WIDTH;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + w, y);
    ctx.lineTo(x + w, y + h);
    ctx.lineTo(x, y + h);
    ctx.closePath();
    ctx.stroke();
    // 通道 2：白色虚线（蚂蚁线）。
    ctx.strokeStyle = '#FFFFFFFF';
    ctx.lineWidth = DASH_WIDTH;
    ctx.beginPath();
    this.dashEdge(x, y, x + w, y);
    this.dashEdge(x + w, y, x + w, y + h);
    this.dashEdge(x + w, y + h, x, y + h);
    this.dashEdge(x, y + h, x, y);
    ctx.stroke();
  }

  /** 沿单条边按 on/off 交替添加虚线段（追加到当前路径，不单独 stroke）。 */
  private dashEdge(x0: number, y0: number, x1: number, y1: number): void {
    const ctx = this.ctx;
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len <= 0) {
      return;
    }
    const ux = dx / len;
    const uy = dy / len;
    let t = 0;
    let on = true;
    while (t < len) {
      const seg = Math.min(on ? DASH_ON : DASH_OFF, len - t);
      if (on) {
        ctx.moveTo(x0 + ux * t, y0 + uy * t);
        ctx.lineTo(x0 + ux * (t + seg), y0 + uy * (t + seg));
      }
      t += seg;
      on = !on;
    }
  }
}
