/**
 * components/CanvasView.ets — 画布渲染管线 + 指针手势（M1）。
 * 管线（开发计划 §6.2/§6.6）：Compose 合成活动帧 → createPixelMapSync 整帧重建 →
 * Image{ interpolation: None } 最近邻放大；棋盘格透明底 + 像素网格覆盖层。
 * 手势协议（§5.2）：单指 = 工具笔触；第二指落下未成笔（位移≤8vp）→ 回滚转双指
 * 手势（捏合缩放/平移）；已成笔 → 忽略防误触；instant 工具（填充/吸管）不回滚。
 * 坐标空间：外层画布区组件相对 vp；origin = (area − doc·zoom)/2 + pan。
 */

import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PixelDoc } from '../core/PixelDoc';
import { PixelBuffer } from '../core/PixelBuffer';
import { Compose } from '../core/Compose';
import { Raster } from '../core/Raster';
import { FloodFill } from '../core/FloodFill';
import { UndoStack } from '../core/UndoStack';
import { GestureTracker, GestureSink } from '../core/GestureTracker';
import { EditorSession, Tool, GridMode, SelRect } from '../viewmodel/EditorSession';
import { GridOverlay } from './GridOverlay';
import { SelectionOverlay } from './SelectionOverlay';

const DOMAIN = 0x0001;
const TAG = 'CanvasView';
const FRAME_MS = 16;
const MIN_ZOOM = 1;
const MAX_ZOOM = 32;
const EYEDROP_LONG_PRESS_MS = 500;
const FALLBACK_CHECKER_A = 0xFFFFFFFF;
const FALLBACK_CHECKER_B = 0xFFC9C9D6;

@ComponentV2
export struct CanvasView {
  @Require @Param doc: PixelDoc;
  @Require @Param session: EditorSession;

  @Local pixelMap: image.PixelMap | undefined = undefined;
  @Local checkerMap: image.PixelMap | undefined = undefined;

  private composeBuf: Uint8Array = new Uint8Array(0);
  private tracker: GestureTracker | undefined = undefined;
  private areaW: number = 0;
  private areaH: number = 0;
  private fitted: boolean = false;
  private strokeBefore: Uint8Array | undefined = undefined;
  private anchorPx: number = 0;
  private anchorPy: number = 0;
  private lastPx: number = 0;
  private lastPy: number = 0;
  private downSample: number = 0;
  private strokeVoid: boolean = false;
  private strokeChanged: boolean = false;
  private longPressTimer: number = -1;
  private maxRenderMs: number = 0;
  private renderScheduled: boolean = false;
  private lastRenderAt: number = 0;
  /** 选区拖动模式：0=无 1=移动选区内容 2=框选新选区。 */
  private selMode: number = 0;
  private selFloating: PixelBuffer | undefined = undefined;
  private selOrig: SelRect | undefined = undefined;
  /** 本笔是否为"复制后拖动"（移出副本，原件保留）。 */
  private selCopiedMode: boolean = false;
  /** 选区内容全透明：拖动仅移动选区框，不改动像素（防止空浮动覆写擦除目标区）。 */
  private selRectOnly: boolean = false;
  private selEmpty: PixelBuffer | undefined = undefined;

  aboutToAppear(): void {
    this.composeBuf = new Uint8Array(this.doc.w * this.doc.h * 4);
    this.tracker = new GestureTracker(new CanvasSink(this));
    this.buildChecker();
    this.render();
    hilog.info(DOMAIN, TAG, 'aboutToAppear w=%{public}d h=%{public}d zoom=%{public}s',
      this.doc.w, this.doc.h, this.session.zoom.toFixed(1));
  }

  /** 画布外操作（撤销/重做/清空等）经 session.tick 触发整帧重渲染。 */
  @Monitor('session.tick')
  onSessionTick(): void {
    hilog.info(DOMAIN, TAG, 'session tick=%{public}d render', this.session.tick);
    this.render();
  }

  /** Move 事件渲染节流：合并到至多每帧一次；落笔/终笔走同步 render()。 */
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

  /** 整帧渲染（§6.2/§6.6）：实测对已挂载 Image 的 PixelMap 调 writeBufferToPixels
   * 不会触发显示刷新，故每帧 createPixelMapSync 生成新对象驱动重绘。 */
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

  /** 棋盘格透明底：doc 尺寸 PixelMap，2×2 像素格，随缩放由 Image 最近邻放大。 */
  private buildChecker(): void {
    let ca = FALLBACK_CHECKER_A;
    let cb = FALLBACK_CHECKER_B;
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined && context !== null) {
        ca = context.resourceManager.getColorByNameSync('checker_a') >>> 0;
        cb = context.resourceManager.getColorByNameSync('checker_b') >>> 0;
      }
    } catch (e) {
      ca = FALLBACK_CHECKER_A;
      cb = FALLBACK_CHECKER_B;
    }
    const w = this.doc.w;
    const h = this.doc.h;
    const data = new Uint8Array(w * h * 4);
    const colors: number[] = [ca, cb];
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const c = colors[(((x >> 1) + (y >> 1)) % 2 + 2) % 2];
        const i = (y * w + x) * 4;
        data[i] = (c >>> 16) & 0xFF;
        data[i + 1] = (c >>> 8) & 0xFF;
        data[i + 2] = c & 0xFF;
        data[i + 3] = (c >>> 24) & 0xFF;
      }
    }
    const opts: image.InitializationOptions = {
      editable: false,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { width: w, height: h }
    };
    this.checkerMap = image.createPixelMapSync(data.buffer.slice(0), opts);
  }

  // ---------- 坐标变换（vp ⇄ 像素） ----------

  private originX(): number {
    return (this.areaW - this.doc.w * this.session.zoom) / 2 + this.session.panX;
  }

  private originY(): number {
    return (this.areaH - this.doc.h * this.session.zoom) / 2 + this.session.panY;
  }

  private vToPxX(vx: number): number {
    return Math.floor((vx - this.originX()) / this.session.zoom);
  }

  private vToPxY(vy: number): number {
    return Math.floor((vy - this.originY()) / this.session.zoom);
  }

  // ---------- 工具分发 ----------

  private toolInstant(): boolean {
    const t = this.session.currentTool;
    return t === Tool.Fill || t === Tool.Eyedropper;
  }

  private strokeArgb(): number {
    return this.session.currentTool === Tool.Eraser ? 0x00000000 : this.session.color;
  }

  private isShapeTool(): boolean {
    const t = this.session.currentTool;
    return t === Tool.Line || t === Tool.Rect || t === Tool.Ellipse;
  }

  private drawShape(cell: PixelBuffer, x0: number, y0: number, x1: number, y1: number): void {
    const argb = this.session.color;
    const filled = this.session.shapeFilled;
    switch (this.session.currentTool) {
      case Tool.Line:
        Raster.drawLine(cell, x0, y0, x1, y1, this.session.brushSize, argb, this.session.mirrorX);
        break;
      case Tool.Rect:
        Raster.strokeRect(cell, x0, y0, x1, y1, this.session.brushSize, argb, this.session.mirrorX, filled);
        break;
      case Tool.Ellipse:
        Raster.strokeEllipse(cell, x0, y0, x1, y1, this.session.brushSize, argb, this.session.mirrorX, filled);
        break;
      default:
        break;
    }
  }

  /** 合成缓冲取色（RGBA 字节序 → packed ARGB）。 */
  private readComposed(px: number, py: number): number {
    const i = (py * this.doc.w + px) * 4;
    const r = this.composeBuf[i];
    const g = this.composeBuf[i + 1];
    const b = this.composeBuf[i + 2];
    const a = this.composeBuf[i + 3];
    return ((a << 24) | (r << 16) | (g << 8) | b) >>> 0;
  }

  private applyPick(sample: number): void {
    const a = (sample >>> 24) & 0xFF;
    if (a > 0) {
      this.session.color = sample;
      if (this.session.currentTool === Tool.Eraser) {
        this.session.currentTool = Tool.Pencil;
      }
      hilog.info(DOMAIN, TAG, 'eyedrop picked 0x%{public}s', sample.toString(16));
    }
  }

  // ---------- 选区工具（§4.1：框选 / 选区内拖动移动） ----------

  /** 选区内起手 → 移动模式（复用笔触快照+撤销管道）；否则 → 框选模式。 */
  private selectionBegin(px: number, py: number): void {
    const cell = this.doc.activeCell();
    const sel = this.session.sel;
    if (cell !== undefined && sel !== undefined && px >= sel.x && px < sel.x + sel.w
      && py >= sel.y && py < sel.y + sel.h) {
      this.selMode = 1;
      this.selOrig = sel;
      this.selCopiedMode = this.session.selCopied;
      this.selFloating = cell.copyRegion(sel.x, sel.y, sel.w, sel.h);
      this.selEmpty = new PixelBuffer(sel.w, sel.h);
      this.selRectOnly = this.isBufferTransparent(this.selFloating);
      this.strokeChanged = true;
      hilog.info(DOMAIN, TAG,
        'sel move begin px=(%{public}d,%{public}d) rect=(%{public}d,%{public}d,%{public}d,%{public}d) copied=%{public}d rectOnly=%{public}d',
        px, py, sel.x, sel.y, sel.w, sel.h, this.selCopiedMode ? 1 : 0, this.selRectOnly ? 1 : 0);
      return;
    }
    this.selMode = 2;
    this.session.sel = undefined;
    this.session.selCopied = false;
    hilog.info(DOMAIN, TAG, 'sel marquee begin px=(%{public}d,%{public}d)', px, py);
  }

  /** 判断缓冲是否全透明（alpha 全 0）。 */
  private isBufferTransparent(buf: PixelBuffer): boolean {
    const d = buf.data;
    for (let i = 3; i < d.length; i += 4) {
      if (d[i] !== 0) {
        return false;
      }
    }
    return true;
  }

  private selectionMove(px: number, py: number): void {
    const cell = this.doc.activeCell();
    if (cell === undefined) {
      return;
    }
    if (this.selMode === 1) {
      const sel = this.selOrig;
      if (sel === undefined) {
        return;
      }
      const dx = px - this.anchorPx;
      const dy = py - this.anchorPy;
      const nx = Math.max(0, Math.min(this.doc.w - sel.w, sel.x + dx));
      const ny = Math.max(0, Math.min(this.doc.h - sel.h, sel.y + dy));
      if (this.selRectOnly) {
        // 空选区：仅移动选区框，不写像素（无撤销条目）。
        this.session.sel = new SelRect(nx, ny, sel.w, sel.h);
        return;
      }
      // 移动模式：恢复快照；非复制拖动先清空原区域（剪切），再贴浮动内容（贴边钳制）。
      const floating = this.selFloating;
      const empty = this.selEmpty;
      if (floating === undefined || this.strokeBefore === undefined) {
        return;
      }
      cell.data.set(this.strokeBefore);
      if (!this.selCopiedMode && empty !== undefined) {
        cell.blit(empty, sel.x, sel.y);
      }
      cell.blit(floating, nx, ny);
      this.session.sel = new SelRect(nx, ny, sel.w, sel.h);
      this.strokeChanged = true;
      this.scheduleRender();
      return;
    }
    if (this.selMode === 2) {
      // 框选模式：实时更新选区矩形（含起/终点像素，越界向画布内夹取）。
      const cx = Math.max(0, Math.min(this.doc.w - 1, px));
      const cy = Math.max(0, Math.min(this.doc.h - 1, py));
      const x0 = Math.min(this.anchorPx, cx);
      const y0 = Math.min(this.anchorPy, cy);
      const w = Math.abs(cx - this.anchorPx) + 1;
      const h = Math.abs(cy - this.anchorPy) + 1;
      this.session.sel = new SelRect(x0, y0, w, h);
    }
  }

  // ---------- GestureSink 实现（由 CanvasSink 委托） ----------

  onStrokeBegin(vx: number, vy: number): void {
    const cell = this.doc.activeCell();
    if (cell === undefined) {
      return;
    }
    const px = this.vToPxX(vx);
    const py = this.vToPxY(vy);
    this.anchorPx = px;
    this.anchorPy = py;
    this.lastPx = px;
    this.lastPy = py;
    this.strokeVoid = !cell.inBounds(px, py);
    this.strokeChanged = false;
    this.strokeBefore = cell.data.slice();
    this.downSample = this.strokeVoid ? 0 : this.readComposed(px, py);
    hilog.info(DOMAIN, TAG,
      'strokeBegin v=(%{public}d,%{public}d) px=(%{public}d,%{public}d) zoom=%{public}s tool=%{public}d void=%{public}d',
      Math.round(vx), Math.round(vy), px, py, this.session.zoom.toFixed(1),
      this.session.currentTool, this.strokeVoid ? 1 : 0);
    switch (this.session.currentTool) {
      case Tool.Pencil:
      case Tool.Eraser:
        if (!this.strokeVoid) {
          Raster.stamp(cell, px, py, this.session.brushSize, this.strokeArgb(), this.session.mirrorX);
          this.strokeChanged = true;
          this.armLongPress();
          this.render();
        }
        break;
      case Tool.Fill:
        if (!this.strokeVoid && FloodFill.fill(cell, px, py, this.session.color)) {
          this.strokeChanged = true;
          this.render();
        }
        break;
      case Tool.Eyedropper:
        if (!this.strokeVoid) {
          this.applyPick(this.downSample);
        }
        break;
      case Tool.Selection:
        if (!this.strokeVoid) {
          this.selectionBegin(px, py);
        }
        break;
      default:
        break;
    }
  }

  onStrokeMove(vx: number, vy: number): void {
    const cell = this.doc.activeCell();
    if (cell === undefined || this.strokeBefore === undefined || this.strokeVoid) {
      return;
    }
    // 已成笔（位移>8vp）→ 取消待决长按吸管，防慢速起笔误触。
    if (this.longPressTimer >= 0 && this.tracker !== undefined && this.tracker.isDismissed()) {
      this.disarmLongPress();
      hilog.info(DOMAIN, TAG, 'longpress cancelled by movement');
    }
    const px = this.vToPxX(vx);
    const py = this.vToPxY(vy);
    // 选区拖动：允许滑出画布边缘（框选贴边/移动到边），不触发边缘停笔。
    if (this.session.currentTool === Tool.Selection) {
      this.selectionMove(px, py);
      return;
    }
    if (!cell.inBounds(px, py)) {
      // 滑出画布边缘 → 停笔（已绘像素保留），undo 入栈。
      this.tracker?.forceEnd();
      return;
    }
    if (this.isShapeTool()) {
      // 破坏性预览：恢复快照后按锚点重画。
      cell.data.set(this.strokeBefore);
      this.drawShape(cell, this.anchorPx, this.anchorPy, px, py);
      this.strokeChanged = true;
      this.scheduleRender();
      return;
    }
    if (px === this.lastPx && py === this.lastPy) {
      return;
    }
    Raster.drawLine(cell, this.lastPx, this.lastPy, px, py,
      this.session.brushSize, this.strokeArgb(), this.session.mirrorX);
    this.lastPx = px;
    this.lastPy = py;
    this.strokeChanged = true;
    this.scheduleRender();
  }

  onStrokeEnd(vx: number, vy: number): void {
    this.disarmLongPress();
    const cell = this.doc.activeCell();
    if (cell === undefined || this.strokeBefore === undefined) {
      this.resetStrokeState();
      return;
    }
    if (!this.strokeVoid) {
      const px = this.vToPxX(vx);
      const py = this.vToPxY(vy);
      if (this.isShapeTool() && cell.inBounds(px, py)) {
        cell.data.set(this.strokeBefore);
        this.drawShape(cell, this.anchorPx, this.anchorPy, px, py);
        this.strokeChanged = true;
      } else if ((this.session.currentTool === Tool.Pencil || this.session.currentTool === Tool.Eraser)
        && cell.inBounds(px, py) && (px !== this.lastPx || py !== this.lastPy)) {
        Raster.drawLine(cell, this.lastPx, this.lastPy, px, py,
          this.session.brushSize, this.strokeArgb(), this.session.mirrorX);
        this.strokeChanged = true;
      }
    }
    let pushed = false;
    if (this.strokeChanged) {
      const entry = UndoStack.entryIfChanged(cell.data, this.strokeBefore);
      if (entry !== undefined) {
        pushed = true;
        this.session.dirty = true;
        this.session.undoStack.push(entry);
        this.session.syncUndoFlags();
      }
      this.render();
    }
    if (this.selMode === 1 && pushed) {
      // 移动/复制拖动已提交 → 复位浮动副本标记。
      this.session.selCopied = false;
    }
    this.session.strokeCount++;
    hilog.info(DOMAIN, TAG, 'stroke end, count=%{public}d, maxRenderMs=%{public}d, pushed=%{public}d',
      this.session.strokeCount, this.maxRenderMs, pushed ? 1 : 0);
    this.resetStrokeState();
  }

  onStrokeRollback(): void {
    this.disarmLongPress();
    hilog.info(DOMAIN, TAG, 'stroke rollback, changed=%{public}d', this.strokeChanged ? 1 : 0);
    const cell = this.doc.activeCell();
    if (cell !== undefined && this.strokeBefore !== undefined && this.strokeChanged) {
      cell.data.set(this.strokeBefore);
      this.render();
    }
    if (this.selMode === 1 && this.selOrig !== undefined) {
      // 回滚移动 → 选区复位到原位置。
      this.session.sel = this.selOrig;
    } else if (this.selMode === 2) {
      // 回滚框选 → 取消选区。
      this.session.sel = undefined;
    }
    this.resetStrokeState();
  }

  private resetStrokeState(): void {
    this.strokeBefore = undefined;
    this.strokeChanged = false;
    this.strokeVoid = false;
    this.maxRenderMs = 0;
    this.selMode = 0;
    this.selFloating = undefined;
    this.selOrig = undefined;
    this.selCopiedMode = false;
    this.selRectOnly = false;
    this.selEmpty = undefined;
  }

  // ---------- 长按吸管（铅笔/橡皮，未成笔 500ms） ----------

  private armLongPress(): void {
    this.disarmLongPress();
    this.longPressTimer = setTimeout(() => {
      this.longPressTimer = -1;
      hilog.info(DOMAIN, TAG, 'longpress timer fired');
      if (this.tracker !== undefined && this.tracker.forceRollback()) {
        this.applyPick(this.downSample);
      }
    }, EYEDROP_LONG_PRESS_MS);
  }

  private disarmLongPress(): void {
    if (this.longPressTimer >= 0) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  // ---------- 双指手势：捏合缩放 + 平移 ----------

  onGestureMove(fromMidX: number, fromMidY: number, toMidX: number, toMidY: number,
    zoomFactor: number): void {
    if (this.areaW <= 0 || this.areaH <= 0) {
      return;
    }
    const oldZoom = this.session.zoom;
    const newZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, oldZoom * zoomFactor));
    const fz = newZoom / oldZoom;
    const ox = this.originX();
    const oy = this.originY();
    const newOx = toMidX - (fromMidX - ox) * fz;
    const newOy = toMidY - (fromMidY - oy) * fz;
    this.session.zoom = newZoom;
    this.session.panX = newOx - (this.areaW - this.doc.w * newZoom) / 2;
    this.session.panY = newOy - (this.areaH - this.doc.h * newZoom) / 2;
    hilog.info(DOMAIN, TAG, 'gesture zoom=%{public}s pan=(%{public}d,%{public}d)',
      newZoom.toFixed(2), Math.round(this.session.panX), Math.round(this.session.panY));
  }

  // ---------- 触摸事件 ----------

  private handleTouch(event: TouchEvent): void {
    if (this.tracker === undefined) {
      return;
    }
    if (event.type === TouchType.Down) {
      hilog.info(DOMAIN, TAG, 'touch down, touches=%{public}d, tool=%{public}d',
        event.touches.length, this.session.currentTool);
      const instant = this.toolInstant();
      for (const t of event.changedTouches) {
        this.tracker.press(t.id, t.x, t.y, instant);
      }
      return;
    }
    if (event.type === TouchType.Move) {
      for (const t of event.changedTouches) {
        this.tracker.move(t.id, t.x, t.y);
      }
      return;
    }
    if (event.type === TouchType.Up) {
      for (const t of event.changedTouches) {
        this.tracker.lift(t.id, t.x, t.y);
      }
      return;
    }
    // Cancel：系统抢占触摸 → 停笔/终结手势。
    this.tracker.forceEnd();
  }

  private gridVisible(): boolean {
    if (this.session.gridMode === GridMode.On) {
      return true;
    }
    if (this.session.gridMode === GridMode.Off) {
      return false;
    }
    return this.session.zoom >= 8;
  }

  private onCanvasArea(newArea: Area): void {
    const w = Number(newArea.width);
    const h = Number(newArea.height);
    if (w <= 0 || h <= 0) {
      return;
    }
    this.areaW = w;
    this.areaH = h;
    if (!this.fitted) {
      this.fitted = true;
      const z = Math.floor(Math.min(w / this.doc.w, h / this.doc.h));
      this.session.zoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, z));
      this.session.panX = 0;
      this.session.panY = 0;
      hilog.info(DOMAIN, TAG, 'fit zoom=%{public}f area=(%{public}d,%{public}d)',
        this.session.zoom, Math.round(w), Math.round(h));
    }
  }

  build() {
    Stack() {
      Stack() {
        if (this.checkerMap !== undefined) {
          Image(this.checkerMap)
            .width(this.doc.w * this.session.zoom)
            .height(this.doc.h * this.session.zoom)
            .objectFit(ImageFit.Fill)
            .interpolation(ImageInterpolation.None)
            .draggable(false)
        }
        if (this.pixelMap !== undefined) {
          Image(this.pixelMap)
            .width(this.doc.w * this.session.zoom)
            .height(this.doc.h * this.session.zoom)
            .objectFit(ImageFit.Fill)
            .interpolation(ImageInterpolation.None)
            .draggable(false)
        }
        GridOverlay({
          docW: this.doc.w,
          docH: this.doc.h,
          zoom: this.session.zoom,
          show: this.gridVisible()
        })
        if (this.session.sel !== undefined) {
          SelectionOverlay({
            sel: this.session.sel,
            zoom: this.session.zoom,
            docW: this.doc.w,
            docH: this.doc.h
          })
        }
      }
      .width(this.doc.w * this.session.zoom)
      .height(this.doc.h * this.session.zoom)
      .translate({ x: this.session.panX, y: this.session.panY })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.canvas_backdrop'))
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event);
    })
    .onAreaChange((_old: Area, newArea: Area) => {
      this.onCanvasArea(newArea);
    })
  }
}

/** GestureSink → CanvasView 委托（struct 不能直接实现接口）。 */
class CanvasSink implements GestureSink {
  private readonly view: CanvasView;

  constructor(view: CanvasView) {
    this.view = view;
  }

  onStrokeBegin(x: number, y: number): void {
    this.view.onStrokeBegin(x, y);
  }

  onStrokeMove(x: number, y: number): void {
    this.view.onStrokeMove(x, y);
  }

  onStrokeEnd(x: number, y: number): void {
    this.view.onStrokeEnd(x, y);
  }

  onStrokeRollback(): void {
    this.view.onStrokeRollback();
  }

  onGestureStart(): void {
  }

  onGestureMove(fromMidX: number, fromMidY: number, toMidX: number, toMidY: number,
    zoomFactor: number): void {
    this.view.onGestureMove(fromMidX, fromMidY, toMidX, toMidY, zoomFactor);
  }

  onGestureEnd(): void {
  }
}
