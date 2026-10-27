/**
 * core/GestureTracker.ets — 指针手势状态机（开发计划 §5.2，纯逻辑层可测）。
 * 规则（P0 锁定）：
 *  - 单指 = 工具笔触；位移超 DISMISS_RADIUS(8vp) 视为成笔；
 *  - 第二指落下时若未成笔（仅一点/未成线）→ 回滚笔触转入双指手势（捏合/平移起步）；
 *  - 第二指落下时已成笔 → 忽略之（防误触，当前笔触不中断、不取消）；
 *  - instant 笔触（填充/吸管等即完成操作）不参与回滚，第二指直接忽略；
 *  - 双指手势中任一指抬起 → 手势结束，余指事件全部忽略直至全部抬起。
 * 坐标空间：全部为画布区组件相对 vp，由 UI 层换算像素。
 */

export const STROKE_DISMISS_RADIUS = 8;

export interface GestureSink {
  onStrokeBegin(x: number, y: number): void;
  onStrokeMove(x: number, y: number): void;
  onStrokeEnd(x: number, y: number): void;
  onStrokeRollback(): void;
  onGestureStart(): void;
  onGestureMove(fromMidX: number, fromMidY: number, toMidX: number, toMidY: number,
    zoomFactor: number): void;
  onGestureEnd(): void;
}

export class GestureTracker {
  private static readonly MODE_IDLE = 0;
  private static readonly MODE_STROKE = 1;
  private static readonly MODE_GESTURE = 2;

  private readonly sink: GestureSink;
  private mode: number = GestureTracker.MODE_IDLE;
  private strokePtr: number = -1;
  private instantStroke: boolean = false;
  private strokeDismissed: boolean = false;
  private anchorX: number = 0;
  private anchorY: number = 0;
  private curX: number = 0;
  private curY: number = 0;
  private g0: number = -1;
  private g1: number = -1;
  private gx0: number = 0;
  private gy0: number = 0;
  private gx1: number = 0;
  private gy1: number = 0;
  private hasBoth: boolean = false;
  private lastMidX: number = 0;
  private lastMidY: number = 0;
  private lastDist: number = 0;

  constructor(sink: GestureSink) {
    this.sink = sink;
  }

  isStrokeActive(): boolean {
    return this.mode === GestureTracker.MODE_STROKE;
  }

  isDismissed(): boolean {
    return this.strokeDismissed;
  }

  press(id: number, x: number, y: number, instant: boolean): void {
    if (this.mode === GestureTracker.MODE_GESTURE) {
      return;
    }
    if (this.mode === GestureTracker.MODE_STROKE) {
      if (!this.strokeDismissed && !this.instantStroke) {
        this.sink.onStrokeRollback();
        this.enterGesture(this.strokePtr, this.curX, this.curY, id, x, y);
        this.sink.onGestureStart();
      }
      return;
    }
    this.mode = GestureTracker.MODE_STROKE;
    this.strokePtr = id;
    this.instantStroke = instant;
    this.strokeDismissed = instant;
    this.anchorX = x;
    this.anchorY = y;
    this.curX = x;
    this.curY = y;
    this.sink.onStrokeBegin(x, y);
  }

  move(id: number, x: number, y: number): void {
    if (this.mode === GestureTracker.MODE_STROKE) {
      if (id !== this.strokePtr) {
        return;
      }
      this.curX = x;
      this.curY = y;
      if (!this.strokeDismissed) {
        const dx = x - this.anchorX;
        const dy = y - this.anchorY;
        if (Math.sqrt(dx * dx + dy * dy) > STROKE_DISMISS_RADIUS) {
          this.strokeDismissed = true;
        }
      }
      this.sink.onStrokeMove(x, y);
      return;
    }
    if (this.mode === GestureTracker.MODE_GESTURE && this.hasBoth) {
      if (id !== this.g0 && id !== this.g1) {
        return;
      }
      const fromMidX = (this.gx0 + this.gx1) / 2;
      const fromMidY = (this.gy0 + this.gy1) / 2;
      const fdx = this.gx1 - this.gx0;
      const fdy = this.gy1 - this.gy0;
      const fromDist = Math.sqrt(fdx * fdx + fdy * fdy);
      if (id === this.g0) {
        this.gx0 = x;
        this.gy0 = y;
      } else {
        this.gx1 = x;
        this.gy1 = y;
      }
      const toMidX = (this.gx0 + this.gx1) / 2;
      const toMidY = (this.gy0 + this.gy1) / 2;
      const tdx = this.gx1 - this.gx0;
      const tdy = this.gy1 - this.gy0;
      const toDist = Math.sqrt(tdx * tdx + tdy * tdy);
      const factor = fromDist > 0 ? toDist / fromDist : 1;
      this.sink.onGestureMove(fromMidX, fromMidY, toMidX, toMidY, factor);
    }
  }

  lift(id: number, x: number, y: number): void {
    if (this.mode === GestureTracker.MODE_STROKE) {
      if (id !== this.strokePtr) {
        return;
      }
      this.curX = x;
      this.curY = y;
      this.mode = GestureTracker.MODE_IDLE;
      this.sink.onStrokeEnd(x, y);
      return;
    }
    if (this.mode === GestureTracker.MODE_GESTURE && (id === this.g0 || id === this.g1)) {
      this.mode = GestureTracker.MODE_IDLE;
      this.hasBoth = false;
      this.sink.onGestureEnd();
    }
  }

  /** 触摸取消/工具滑出画布边缘：笔触停笔（已绘内容保留），双指手势一并终结。 */
  forceEnd(): void {
    if (this.mode === GestureTracker.MODE_STROKE) {
      this.mode = GestureTracker.MODE_IDLE;
      this.sink.onStrokeEnd(this.curX, this.curY);
    } else if (this.mode === GestureTracker.MODE_GESTURE) {
      this.mode = GestureTracker.MODE_IDLE;
      this.hasBoth = false;
      this.sink.onGestureEnd();
    }
  }

  /** 长按吸管：未成笔回滚（true = 已回滚，可执行吸色）。 */
  forceRollback(): boolean {
    if (this.mode === GestureTracker.MODE_STROKE && !this.strokeDismissed && !this.instantStroke) {
      this.mode = GestureTracker.MODE_IDLE;
      this.sink.onStrokeRollback();
      return true;
    }
    return false;
  }

  private enterGesture(a: number, ax: number, ay: number, b: number, bx: number, by: number): void {
    this.mode = GestureTracker.MODE_GESTURE;
    this.g0 = a;
    this.gx0 = ax;
    this.gy0 = ay;
    this.g1 = b;
    this.gx1 = bx;
    this.gy1 = by;
    this.hasBoth = true;
    this.lastMidX = (ax + bx) / 2;
    this.lastMidY = (ay + by) / 2;
    const dx = bx - ax;
    const dy = by - ay;
    this.lastDist = Math.sqrt(dx * dx + dy * dy);
  }
}
