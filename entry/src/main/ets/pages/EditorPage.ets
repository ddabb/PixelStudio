/**
 * pages/EditorPage.ets — 编辑器主页（M0 布局子集，开发计划 §5.1）：
 * 顶栏（工程名 + 尺寸 + 脏标记） / 画布区 / 工具行 / 颜色行。
 */

import { PixelDoc } from '../core/PixelDoc';
import { EditorSession, Tool } from '../viewmodel/EditorSession';
import { CanvasView } from '../components/CanvasView';

const SWATCH_COLORS: number[] = [
  0xFF000000, 0xFFFFFFFF, 0xFFE23636, 0xFFF7B32B,
  0xFF43B76A, 0xFF2D7DD2, 0xFF7C4DBC, 0xFF8A6B3D
];

@Entry
@ComponentV2
struct EditorPage {
  doc: PixelDoc = new PixelDoc(64, 64);
  @Local session: EditorSession = new EditorSession();

  private selectTool(tool: Tool): void {
    this.session.currentTool = tool;
  }

  private clearCanvas(): void {
    const cell = this.doc.activeCell();
    if (cell !== undefined) {
      cell.clear();
      this.session.tick++;
    }
  }

  @Builder
  toolButton(label: ResourceStr, active: boolean, onTap: () => void) {
    Button(label)
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(active ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(active ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        onTap();
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
      .backgroundColor(this.session.brushSize === size ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.brushSize === size ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
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

  build() {
    Column() {
      // 顶栏
      Row({ space: 8 }) {
        Text($r('app.string.editor_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text(`${this.doc.w}×${this.doc.h}`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        Blank()
        if (this.session.dirty) {
          Circle()
            .width(8)
            .height(8)
            .fill($r('app.color.accent'))
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      // 画布区
      Column() {
        CanvasView({ doc: this.doc, session: this.session })
      }
      .layoutWeight(1)
      .width('100%')

      // 工具行
      Row({ space: 8 }) {
        this.toolButton($r('app.string.tool_pencil'), this.session.currentTool === Tool.Pencil, () => {
          this.selectTool(Tool.Pencil);
        })
        this.toolButton($r('app.string.tool_eraser'), this.session.currentTool === Tool.Eraser, () => {
          this.selectTool(Tool.Eraser);
        })
        this.toolButton($r('app.string.mirror_x'), this.session.mirrorX, () => {
          this.session.mirrorX = !this.session.mirrorX;
        })
        Blank()
        Text($r('app.string.brush_size'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
        this.sizeButton(1)
        this.sizeButton(2)
        this.sizeButton(3)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      // 颜色行
      Row({ space: 8 }) {
        ForEach(SWATCH_COLORS, (color: number) => {
          this.swatch(color)
        }, (color: number) => color.toString())
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
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .backgroundColor($r('app.color.card_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
