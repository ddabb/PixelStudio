/**
 * components/PaletteBar.ets — 调色板横滑行（开发计划 §5.1：
 * 横滑行 = 当前色 │ 调色板色卡… │ ＋）。
 * 当前色块与 ＋ 打开调色板面板（PalettePanel：预设/自定义/HSB/HEX/最近使用）。
 */

import { EditorSession, Tool } from '../viewmodel/EditorSession';
import { PaletteStore } from '../viewmodel/PaletteStore';

@ComponentV2
export struct PaletteBar {
  @Require @Param session: EditorSession;
  @Require @Param store: PaletteStore;
  @Param onOpenPanel: () => void = (): void => {};

  @Builder
  swatch(color: number) {
    Column()
      .width(30)
      .height(30)
      .borderRadius(6)
      .backgroundColor(color)
      .border({
        width: this.session.color === color ? 3 : 1,
        color: this.session.color === color
          ? $r('app.color.brand') : $r('app.color.border_color')
      })
      .onClick(() => {
        this.session.color = color;
        if (this.session.currentTool === Tool.Eraser) {
          this.session.currentTool = Tool.Pencil;
        }
      })
  }

  build() {
    Row({ space: 8 }) {
      Column()
        .width(34)
        .height(34)
        .borderRadius(8)
        .backgroundColor(this.session.color)
        .border({ width: 1, color: $r('app.color.border_color') })
        .accessibilityText($r('app.string.palette_current_color'))
        .onClick(() => {
          this.onOpenPanel();
        })
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.store.activePalette()?.colors ?? [], (color: number) => {
            this.swatch(color)
          }, (color: number) => color.toString())
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      Button($r('app.string.palette_open_btn'))
        .type(ButtonType.Normal)
        .borderRadius(8)
        .width(36)
        .height(36)
        .fontSize(18)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.primary_text'))
        .accessibilityText($r('app.string.palette_title'))
        .onClick(() => {
          this.onOpenPanel();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
  }
}
