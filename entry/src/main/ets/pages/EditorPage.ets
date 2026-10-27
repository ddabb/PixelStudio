/**
 * pages/EditorPage.ets — 编辑器主页（开发计划 §5.1，M1）：
 * 顶栏（返回 + 工程名 + 尺寸 + 脏标记 + 撤销/重做） / 画布区 /
 * 工具行（7 工具 + 镜像 + 实心 + 网格三态） / 笔宽行 / 颜色行。
 * 注意：@Builder 值传参在 V2 是快照不响应，所有会变的状态一律在 Builder 体内读取。
 */

import { PixelDoc } from '../core/PixelDoc';
import { UndoStack } from '../core/UndoStack';
import { EditorSession, Tool, GridMode } from '../viewmodel/EditorSession';
import { DocOps } from '../viewmodel/DocOps';
import { CanvasView } from '../components/CanvasView';
import { LayerPanel } from '../components/LayerPanel';

const SWATCH_COLORS: number[] = [
  0xFF000000, 0xFFFFFFFF, 0xFFE23636, 0xFFF7B32B,
  0xFF43B76A, 0xFF2D7DD2, 0xFF7C4DBC, 0xFF8A6B3D
];

@Entry
@ComponentV2
struct EditorPage {
  doc: PixelDoc = new PixelDoc(64, 64);
  @Local session: EditorSession = new EditorSession();
  /** 底部面板模式：0=画布 1=图层。 */
  @Local panelMode: number = 0;

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

  @Builder
  swatch(color: number) {
    Column()
      .width(32)
      .height(32)
      .borderRadius(8)
      .backgroundColor(color)
      .border({
        width: this.session.color === color ? 3 : 1,
        color: this.session.color === color ? $r('app.color.brand') : $r('app.color.border_color')
      })
      .onClick(() => {
        this.session.color = color;
        if (this.session.currentTool === Tool.Eraser) {
          this.session.currentTool = Tool.Pencil;
        }
      })
  }

  /** 底部 Tab：mode 0=画布 1=图层；激活态在体内读取 panelMode。 */
  @Builder
  tabButton(mode: number) {
    Button(mode === 0 ? $r('app.string.tab_canvas') : $r('app.string.tab_layers'))
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

      // 内容区：画布常驻 + 图层面板 Stack 叠放（Tab 切换，画布不重挂载）
      Stack() {
        CanvasView({ doc: this.doc, session: this.session })
        if (this.panelMode === 1) {
          LayerPanel({ doc: this.doc, session: this.session })
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

        // 颜色行
        Row({ space: 8 }) {
          ForEach(SWATCH_COLORS, (color: number) => {
            this.swatch(color)
          }, (color: number) => color.toString())
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))
      }

      // 底部 Tab：画布 / 图层
      Row({ space: 8 }) {
        this.tabButton(0)
        this.tabButton(1)
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
