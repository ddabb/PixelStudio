/**
 * components/CanvasView.ets — 画布渲染管线 + 手势（M0）。
 * 管线（开发计划 §6.2）：Compose 合成活动帧 → writeBufferToPixels 整帧写回 →
 * Image{ interpolation: None } 最近邻放大（缩放由渲染引擎完成）。
 * 手势协议（§5.2，M0 子集）：单指 = 当前工具执行；按下瞬间指针数 ≥2 挂起工具；
 * 落笔后第二指按下不取消当前笔触。
 */

import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PixelDoc } from '../core/PixelDoc';
import { Compose } from '../core/Compose';
import { Raster } from '../core/Raster';
import { EditorSession, Tool } from '../viewmodel/EditorSession';

const DOMAIN = 0x0001;
const TAG = 'CanvasView';
const FRAME_MS = 16;

@ComponentV2
export struct CanvasView {
  @Require @Param doc: PixelDoc;
  @Require @Param session: EditorSession;

  @Local pixelMap: image.PixelMap | undefined = undefined;
  @Local zoom: number = 1;
  private composeBuf: Uint8Array = new Uint8Array(0);
  private strokeActive: boolean = false;
  private fingerId: number = -1;
  private lastPx: number = 0;
  private lastPy: number = 0;
  private maxRenderMs: number = 0;
  private renderScheduled: boolean = false;
  private lastRenderAt: number = 0;

  aboutToAppear(): void {
    this.composeBuf = new Uint8Array(this.doc.w * this.doc.h * 4);
    this.render();
    hilog.info(DOMAIN, TAG, 'aboutToAppear w=%{public}d h=%{public}d zoom=%{public}d',
      this.doc.w, this.doc.h, this.zoom);
  }

  /** 画布外操作（清空等）触发整帧重渲染。 */
  @Monitor('session.tick')
  onSessionTick(): void {
    hilog.info(DOMAIN, TAG, 'session tick=%{public}d render', this.session.tick);
    this.render();
  }

  /**
   * Move 事件渲染节流：合并到至多每帧一次（FRAME_MS），
   * 避免高频 move 下的重建排队拥塞；落笔/清空走同步 render()。
   */
  private scheduleRender(): void {
    if (this.renderScheduled) {
      return;
    }
    this.renderScheduled = true;
    const elapsed = Date.now() - this.lastRenderAt;
    const delay = elapsed >= FRAME_MS ? 0 : FRAME_MS - elapsed;
    setTimeout(() => {
      this.renderScheduled = false;
      this.render();
    }, delay);
  }

  /**
   * 整帧渲染（开发计划 §6.2/§6.6）：Compose 合成 → 重建 PixelMap。
   * 实测（API 20 模拟器）：对已挂载 Image 的 PixelMap 调 writeBufferToPixels 不会触发
   * 显示刷新，故采用兜底方案——每帧 createPixelMapSync 生成新对象，@Local 引用变化
   * 驱动 Image 重绘。重建为同步调用，直接计入 maxRenderMs。
   */
  private render(): void {
    const t0 = Date.now();
    this.lastRenderAt = t0;
    Compose.composeFrame(this.doc, this.doc.activeFrame, this.composeBuf);
    const opts: image.InitializationOptions = {
      editable: false,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { width: this.doc.w, height: this.doc.h }
    };
    this.pixelMap = image.createPixelMapSync(this.composeBuf.buffer.slice(0), opts);
    const dt = Date.now() - t0;
    if (dt > this.maxRenderMs) {
      this.maxRenderMs = dt;
    }
  }

  private toPixel(v: number): number {
    return Math.floor(v / this.zoom);
  }

  private strokeArgb(): number {
    return this.session.currentTool === Tool.Eraser ? 0x00000000 : this.session.color;
  }

  private strokeBegin(vx: number, vy: number): void {
    const cell = this.doc.activeCell();
    if (cell === undefined) {
      return;
    }
    const px = this.toPixel(vx);
    const py = this.toPixel(vy);
    hilog.info(DOMAIN, TAG, 'strokeBegin v=(%{public}d,%{public}d) px=(%{public}d,%{public}d) zoom=%{public}d',
      Math.round(vx), Math.round(vy), px, py, this.zoom);
    this.lastPx = px;
    this.lastPy = py;
    Raster.stamp(cell, px, py, this.session.brushSize, this.strokeArgb(), this.session.mirrorX);
    this.session.dirty = true;
    this.render();
  }

  private strokeMove(vx: number, vy: number): void {
    const cell = this.doc.activeCell();
    if (cell === undefined) {
      return;
    }
    const px = this.toPixel(vx);
    const py = this.toPixel(vy);
    if (px === this.lastPx && py === this.lastPy) {
      return;
    }
    Raster.drawLine(cell, this.lastPx, this.lastPy, px, py,
      this.session.brushSize, this.strokeArgb(), this.session.mirrorX);
    this.lastPx = px;
    this.lastPy = py;
    this.scheduleRender();
  }

  private endStroke(): void {
    this.strokeActive = false;
    this.fingerId = -1;
    this.session.strokeCount++;
    hilog.info(DOMAIN, TAG, 'stroke end, count=%{public}d, maxRenderMs=%{public}d',
      this.session.strokeCount, this.maxRenderMs);
    this.maxRenderMs = 0;
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      hilog.info(DOMAIN, TAG, 'touch down, touches=%{public}d, active=%{public}d',
        event.touches.length, this.strokeActive ? 1 : 0);
      // 判定时机 = 按下瞬间指针计数：≥2 挂起工具且不产生笔触；
      // 已落笔后第二指按下不取消当前笔触（防误触）。
      if (event.touches.length >= 2 || this.strokeActive) {
        return;
      }
      const t = event.changedTouches[0];
      this.fingerId = t.id;
      this.strokeActive = true;
      this.strokeBegin(t.x, t.y);
      return;
    }
    if (event.type === TouchType.Move) {
      if (!this.strokeActive) {
        return;
      }
      for (const t of event.changedTouches) {
        if (t.id === this.fingerId) {
          this.strokeMove(t.x, t.y);
        }
      }
      return;
    }
    // Up / Cancel：仅活动指收笔。
    if (this.strokeActive) {
      for (const t of event.changedTouches) {
        if (t.id === this.fingerId) {
          if (event.type === TouchType.Up) {
            this.strokeMove(t.x, t.y);
          }
          this.endStroke();
          break;
        }
      }
    }
  }

  private fitZoom(areaW: number, areaH: number): void {
    if (areaW <= 0 || areaH <= 0) {
      return;
    }
    const z = Math.floor(Math.min(areaW / this.doc.w, areaH / this.doc.h));
    const next = Math.max(1, Math.min(32, z));
    if (next !== this.zoom) {
      this.zoom = next;
    }
  }

  build() {
    Stack() {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .width(this.doc.w * this.zoom)
          .height(this.doc.h * this.zoom)
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.None)
          .draggable(false)
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.canvas_backdrop'))
    .onAreaChange((_old: Area, newArea: Area) => {
      this.fitZoom(Number(newArea.width), Number(newArea.height));
    })
  }
}
