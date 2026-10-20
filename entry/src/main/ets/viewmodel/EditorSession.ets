/**
 * viewmodel/EditorSession.ets — 编辑器会话状态（@ObservedV2，V2 状态树根）。
 * 工具 / 颜色 / 笔宽 / 镜像 / 脏标记；tick 供画布外操作（清空等）触发重渲染。
 */

export enum Tool {
  Pencil = 0,
  Eraser = 1
}

@ObservedV2
export class EditorSession {
  @Trace currentTool: Tool = Tool.Pencil;
  @Trace color: number = 0xFF000000;
  @Trace brushSize: number = 1;
  @Trace mirrorX: boolean = false;
  @Trace dirty: boolean = false;
  /** 画布外修改文档时自增，CanvasView @Monitor 后重渲染。 */
  @Trace tick: number = 0;
  @Trace strokeCount: number = 0;
}
