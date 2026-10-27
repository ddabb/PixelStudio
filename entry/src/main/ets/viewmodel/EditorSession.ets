/**
 * viewmodel/EditorSession.ets — 编辑器会话状态（@ObservedV2，V2 状态树根）。
 * 工具 / 颜色 / 笔宽 / 镜像 / 形状实心 / 网格模式 / 视口变换（缩放平移）/
 * 撤销标志 / 脏标记；tick 供画布外操作（清空/撤销/重做等）触发重渲染。
 */

import { UndoStack } from '../core/UndoStack';

export enum Tool {
  Pencil = 0,
  Eraser = 1,
  Fill = 2,
  Line = 3,
  Rect = 4,
  Ellipse = 5,
  Eyedropper = 6,
  Selection = 7
}

/** 选区矩形（像素坐标；x/y 为左上角，w/h ≥ 1）。 */
export class SelRect {
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;

  constructor(x: number, y: number, w: number, h: number) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
}

export enum GridMode {
  Auto = 0,
  On = 1,
  Off = 2
}

@ObservedV2
export class EditorSession {
  @Trace currentTool: Tool = Tool.Pencil;
  @Trace color: number = 0xFF000000;
  @Trace brushSize: number = 1;
  @Trace mirrorX: boolean = false;
  @Trace shapeFilled: boolean = false;
  @Trace gridMode: GridMode = GridMode.Auto;
  /** 视口变换：zoom 为浮点（捏合连续），fitZoom 初始化为整倍数；pan 单位 vp。 */
  @Trace zoom: number = 1;
  @Trace panX: number = 0;
  @Trace panY: number = 0;
  @Trace dirty: boolean = false;
  /** 画布外修改文档时自增，CanvasView @Monitor 后重渲染。 */
  @Trace tick: number = 0;
  @Trace strokeCount: number = 0;
  @Trace canUndo: boolean = false;
  @Trace canRedo: boolean = false;
  /** 活动图层索引（与 doc.activeLayer 同步，供图层面板/CanvasView 响应）。 */
  @Trace activeLayer: number = 0;
  /** 矩形选区（Selection 工具）；undefined = 无选区。 */
  @Trace sel: SelRect | undefined = undefined;
  /** 选区浮动副本标记：复制后拖动选区 = 移出副本（原件保留），提交或取消后复位。 */
  @Trace selCopied: boolean = false;
  readonly undoStack: UndoStack = new UndoStack(100);

  syncUndoFlags(): void {
    this.canUndo = this.undoStack.canUndo();
    this.canRedo = this.undoStack.canRedo();
  }

  /** 撤销/重做后由 CanvasView 监听 tick 重渲染；栈内快照直接写回 cellData。 */
  undo(): void {
    if (this.undoStack.undo() !== undefined) {
      this.dirty = true;
      this.tick++;
      this.syncUndoFlags();
    }
  }

  redo(): void {
    if (this.undoStack.redo() !== undefined) {
      this.dirty = true;
      this.tick++;
      this.syncUndoFlags();
    }
  }
}
