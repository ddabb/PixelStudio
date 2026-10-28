/**
 * pages/EditorPage.ets — 编辑器主页（开发计划 §5.1，M1/M3）：
 * 顶栏（返回 + 工程名 + 尺寸 + 脏标记 + 撤销/重做） / 画布区 /
 * 工具行（8 工具 + 镜像 + 实心 + 网格三态） / 笔宽行 / 调色板横滑行。
 * 底部 Tab：画布 / 图层 / 帧（帧面板：缩略条 + 播放 + FPS + 洋葱皮）。
 * 播放 = setInterval 循环推进 activeFrame + tick 驱动重渲染；任意触屏/撤销/帧操作即停。
 * 注意：@Builder 值传参在 V2 是快照不响应，所有会变的状态一律在 Builder 体内读取。
 */

import { PixelDoc } from '../core/PixelDoc';
import { UndoStack } from '../core/UndoStack';
import { EditorSession, Tool, GridMode } from '../viewmodel/EditorSession';
import { DocOps } from '../viewmodel/DocOps';
import { PaletteStore } from '../viewmodel/PaletteStore';
import { CanvasView } from '../components/CanvasView';
import { LayerPanel } from '../components/LayerPanel';
import { FrameStrip } from '../components/FrameStrip';
import { PaletteBar } from '../components/PaletteBar';
import { PalettePanel } from '../components/PalettePanel';

/** 播放定时器最小间隔（ms）：对齐 60Hz 帧节流，防高 FPS 空转。 */
const PLAY_TICK_MS = 16;

@Entry
@ComponentV2
struct EditorPage {
  doc: PixelDoc = new PixelDoc(64, 64);
  @Local session: EditorSession = new EditorSession();
  /** 底部面板模式：0=画布 1=图层 2=帧。 */
  @Local panelMode: number = 0;
  /** 调色板面板覆盖层（覆盖内容区，不影响底部工具行）。 */
  @Local paletteOpen: boolean = false;
  @Local paletteStore: PaletteStore = new PaletteStore();
  private playTimerId: number = -1;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined && ctx !== null) {
      this.paletteStore.load(ctx);
    }
  }

  aboutToDisappear(): void {
    this.stopPlayback();
    this.paletteStore.saveNow();
  }

  // ---------- 播放（§4.1：循环预览，触屏/撤销/帧操作即停） ----------

  private startPlayback(): void {
    this.stopPlayback();
    const interval = Math.max(PLAY_TICK_MS, Math.round(1000 / this.session.fps));
    this.playTimerId = setInterval(() => {
      this.doc.activeFrame = (this.doc.activeFrame + 1) % this.doc.frameCount;
      this.session.activeFrame = this.doc.activeFrame;
      this.session.tick++;
    }, interval);
  }

  private stopPlayback(): void {
    if (this.playTimerId !== -1) {
      clearInterval(this.playTimerId);
      this.playTimerId = -1;
    }
  }

  @Monitor('session.playing')
  onPlayingChange(): void {
    if (this.session.playing) {
      if (this.doc.frameCount > 1) {
        this.startPlayback();
      } else {
        this.session.playing = false;
      }
    } else {
      this.stopPlayback();
    }
  }

  @Monitor('session.fps')
  onFpsChange(): void {
    if (this.session.playing) {
      this.startPlayback();
    }
  }

  /** 当前色变化 → 记入最近使用（PaletteBar/取色器/吸管统一入口）。 */
  @Monitor('session.color')
  onColorChange(): void {
    this.paletteStore.pushRecent(this.session.color);
  }

  private clearCanvas(): void {
    const cell = this.doc.activeCell();
    if (cell === undefined) {
      return;
    }
    const before = cell.data.slice();
    cell.clear();
    const entry = UndoStack.entryIfChanged(cell.data, before);
    if (entry !== undefined) {
      this.session.undoStack.push(entry);
      this.session.syncUndoFlags();
      this.session.dirty = true;
      this.session.tick++;
    }
  }

  private cycleGrid(): void {
    const g = this.session.gridMode;
    this.session.gridMode =
      g === GridMode.Auto ? GridMode.On : (g === GridMode.On ? GridMode.Off : GridMode.Auto);
  }

  private gridLabel(): ResourceStr {
    if (this.session.gridMode === GridMode.On) {
      return $r('app.string.grid_on');
    }
    if (this.session.gridMode === GridMode.Off) {
      return $r('app.string.grid_off');
    }
    return $r('app.string.grid_auto');
  }

  /** 工具切换按钮（7 工具）：active 状态在体内读取 session.currentTool。 */
  @Builder
  toolButton(label: ResourceStr, tool: Tool) {
    Button(label)
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.currentTool === tool
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.currentTool === tool
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        if (this.session.currentTool === Tool.Selection && tool !== Tool.Selection) {
          DocOps.cancelSelection(this.session);
        }
        this.session.currentTool = tool;
      })
  }

  /** 顶栏撤销/重做：kind 0=撤销 1=重做，可用态在体内读取 session。 */
  @Builder
  barButton(kind: number) {
    Button(kind === 0 ? $r('app.string.undo') : $r('app.string.redo'))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(32)
      .padding({ left: 12, right: 12 })
      .fontSize(13)
      .enabled(kind === 0 ? this.session.canUndo : this.session.canRedo)
      .backgroundColor($r('app.color.card_background'))
      .fontColor(kind === 0
        ? (this.session.canUndo ? $r('app.color.primary_text') : $r('app.color.hint_text'))
        : (this.session.canRedo ? $r('app.color.primary_text') : $r('app.color.hint_text')))
      .onClick(() => {
        if (kind === 0) {
          this.session.undo();
        } else {
          this.session.redo();
        }
      })
  }

  @Builder
  mirrorButton() {
    Button($r('app.string.mirror_x'))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.mirrorX
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.mirrorX
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.session.mirrorX = !this.session.mirrorX;
      })
  }

  @Builder
  filledButton() {
    Button($r('app.string.shape_filled'))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.shapeFilled
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.shapeFilled
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.session.shapeFilled = !this.session.shapeFilled;
      })
  }

  @Builder
  gridButton() {
    Button(this.gridLabel())
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.gridMode === GridMode.On
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.gridMode === GridMode.On
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.cycleGrid();
      })
  }

  @Builder
  sizeButton(size: number) {
    Button(size.toString())
      .type(ButtonType.Normal)
      .borderRadius(10)
      .width(36)
      .height(36)
      .fontSize(14)
      .backgroundColor(this.session.brushSize === size
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.brushSize === size
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.session.brushSize = size;
      })
  }

  /** 底部 Tab：mode 0=画布 1=图层 2=帧；激活态在体内读取 panelMode。 */
  @Builder
  tabButton(mode: number) {
    Button(mode === 0 ? $r('app.string.tab_canvas')
      : (mode === 1 ? $r('app.string.tab_layers') : $r('app.string.tab_frames')))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .layoutWeight(1)
      .fontSize(14)
      .backgroundColor(this.panelMode === mode
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.panelMode === mode
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.panelMode = mode;
        if (mode !== 0 && this.session.playing) {
          // 画布不可见时终止循环预览，避免空转定时器。
          this.session.playing = false;
        }
      })
  }

  /** 选区操作行（Selection 工具时替代笔宽行）：复制/删除/取消。 */
  @Builder
  selectionBar() {
    Row({ space: 8 }) {
      Button($r('app.string.sel_copy'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .enabled(this.session.sel !== undefined)
        .backgroundColor($r('app.color.card_background'))
        .fontColor(this.session.sel !== undefined
          ? $r('app.color.primary_text') : $r('app.color.hint_text'))
        .onClick(() => {
          DocOps.copySelection(this.doc, this.session);
        })
      Button($r('app.string.sel_delete'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .enabled(this.session.sel !== undefined)
        .backgroundColor($r('app.color.card_background'))
        .fontColor(this.session.sel !== undefined
          ? $r('app.color.danger_red') : $r('app.color.hint_text'))
        .onClick(() => {
          DocOps.deleteSelection(this.doc, this.session);
        })
      Button($r('app.string.sel_cancel'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .enabled(this.session.sel !== undefined)
        .backgroundColor($r('app.color.card_background'))
        .fontColor(this.session.sel !== undefined
          ? $r('app.color.primary_text') : $r('app.color.hint_text'))
        .onClick(() => {
          DocOps.cancelSelection(this.session);
        })
      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
  }

  build() {
    Column() {
      // 顶栏：返回 + 标题 + 尺寸 + 脏标记 + 撤销/重做
      Row({ space: 8 }) {
        Button($r('app.string.back'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(32)
          .padding({ left: 12, right: 12 })
          .fontSize(13)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text($r('app.string.editor_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text(`${this.doc.w}×${this.doc.h}`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        if (this.session.dirty) {
          Circle()
            .width(8)
            .height(8)
            .fill($r('app.color.accent'))
        }
        Blank()
        this.barButton(0)
        this.barButton(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      // 内容区：画布常驻 + 面板 Stack 叠放（Tab 切换，画布不重挂载）
      Stack() {
        CanvasView({ doc: this.doc, session: this.session })
        if (this.panelMode === 1) {
          LayerPanel({ doc: this.doc, session: this.session })
        }
        if (this.panelMode === 2) {
          FrameStrip({
            doc: this.doc,
            session: this.session,
            onPlay: (): void => {
              // 循环预览需画布可见：播放启动即切回画布 Tab。
              this.panelMode = 0;
            }
          })
        }
        if (this.paletteOpen) {
          PalettePanel({
            session: this.session,
            store: this.paletteStore,
            onClose: (): void => {
              this.paletteOpen = false;
            }
          })
        }
      }
      .layoutWeight(1)
      .width('100%')

      if (this.panelMode === 0) {
        // 工具行：8 工具 + 镜像 + 实心 + 网格三态（横向可滚动）
        Scroll() {
          Row({ space: 8 }) {
            this.toolButton($r('app.string.tool_pencil'), Tool.Pencil)
            this.toolButton($r('app.string.tool_eraser'), Tool.Eraser)
            this.toolButton($r('app.string.tool_fill'), Tool.Fill)
            this.toolButton($r('app.string.tool_line'), Tool.Line)
            this.toolButton($r('app.string.tool_rect'), Tool.Rect)
            this.toolButton($r('app.string.tool_ellipse'), Tool.Ellipse)
            this.toolButton($r('app.string.tool_eyedropper'), Tool.Eyedropper)
            this.toolButton($r('app.string.tool_selection'), Tool.Selection)
            this.mirrorButton()
            if (this.session.currentTool === Tool.Rect || this.session.currentTool === Tool.Ellipse) {
              this.filledButton()
            }
            this.gridButton()
          }
          .padding({ left: 12, right: 12 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        if (this.session.currentTool === Tool.Selection) {
          this.selectionBar()
        } else {
          // 笔宽行
          Row({ space: 8 }) {
            Text($r('app.string.brush_size'))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
            this.sizeButton(1)
            this.sizeButton(2)
            this.sizeButton(3)
            Blank()
            Button($r('app.string.clear_canvas'))
              .type(ButtonType.Normal)
              .borderRadius(10)
              .height(36)
              .padding({ left: 14, right: 14 })
              .fontSize(14)
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.danger_red'))
              .onClick(() => {
                this.clearCanvas();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.card_background'))
        }

        // 调色板横滑行（当前色 + 活动调色板色卡 + ＋面板）
        PaletteBar({
          session: this.session,
          store: this.paletteStore,
          onOpenPanel: (): void => {
            if (this.session.playing) {
              this.session.playing = false;
            }
            this.paletteOpen = true;
          }
        })
      }

      // 底部 Tab：画布 / 图层 / 帧
      Row({ space: 8 }) {
        this.tabButton(0)
        this.tabButton(1)
        this.tabButton(2)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 10 })
      .backgroundColor($r('app.color.card_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
