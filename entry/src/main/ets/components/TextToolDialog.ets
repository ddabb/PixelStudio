/**
 * components/TextToolDialog.ets — 文本插入对话框（1.1.0-D，开发计划 §15）。
 * 文本工具点击画布锚点后弹出：输入即大写化（A-Z / 0-9 / 标点，无字形字符跳绘，预览与落笔一致）
 * + 字号 1×/2×/3× + 宽度预览；锚点越界仅红提示不阻插入（Font5x7.drawText 自动裁剪）；
 * 确认走 DocOps.insertText（CelEntry 可撤销 + Haptics.confirm）；scrim/取消关闭均不落笔。
 * scrim 为 Stack 兄弟层（非根节点 onClick）：卡片内点击不冒泡误关（输入/选字号可交互）。
 * 组件自持 doc/session（仿 ExportPanel 先例）；卡片空 onClick 拦截穿透。
 */

import { PixelDoc } from '../core/PixelDoc';
import { Font5x7 } from '../core/Font5x7';
import { EditorSession } from '../viewmodel/EditorSession';
import { DocOps } from '../viewmodel/DocOps';
import { Haptics } from '../viewmodel/Haptics';

const TEXT_SCALES: number[] = [1, 2, 3];
const TEXT_MAX_CHARS = 40;

@ComponentV2
export struct TextToolDialog {
  @Require @Param doc: PixelDoc;
  @Require @Param session: EditorSession;
  /** 插入锚点（画布像素坐标，CanvasView onTextRequest 透传）。 */
  @Require @Param anchorX: number;
  @Require @Param anchorY: number;
  @Require @Param onClose: () => void;
  @Local input: string = '';
  @Local textScale: number = 1;

  // ---------- 本地化取串（getStringByNameSync 先例） ----------

  private msg(name: string): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    try {
      return ctx.resourceManager.getStringByNameSync(name);
    } catch (e) {
      return '';
    }
  }

  private msg1(name: string, v: number): string {
    return this.msg(name).replace('%d', v.toString());
  }

  // ---------- 宽度 / 越界（预览提示用，真正裁剪在 Font5x7.drawText） ----------

  private trimmed(): string {
    return this.input.trim();
  }

  private widthPx(): number {
    return Font5x7.textWidth(this.trimmed(), this.textScale);
  }

  /** 锚点 + 文本框超画布 → 红「越界」提示（不阻插入）。 */
  private overflow(): boolean {
    if (this.trimmed().length === 0) {
      return false;
    }
    return this.anchorX + this.widthPx() > this.doc.w
      || this.anchorY + Font5x7.GLYPH_H * this.textScale > this.doc.h;
  }

  /** 插入：DocOps 写点阵（CelEntry 可撤销）；成功与否均关对话框。 */
  private doInsert(): void {
    if (this.trimmed().length > 0
      && DocOps.insertText(this.doc, this.session, this.anchorX, this.anchorY,
        this.trimmed(), this.textScale)) {
      Haptics.confirm();
    }
    this.onClose();
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.onClose();
        })
      Column({ space: 14 }) {
        Text($r('app.string.text_dialog_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text($r('app.string.text_hint'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        TextInput({ text: this.input, placeholder: this.msg('text_hint') })
          .height(44)
          .fontSize(15)
          .maxLength(TEXT_MAX_CHARS)
          .defaultFocus(true)
          .backgroundColor($r('app.color.page_background'))
          .fontColor($r('app.color.primary_text'))
          .placeholderColor($r('app.color.secondary_text'))
          .onChange((v: string) => {
            this.input = v.toUpperCase();
          })
        Row({ space: 8 }) {
          Text($r('app.string.text_scale'))
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
          ForEach(TEXT_SCALES, (s: number) => {
            Button(s + '×')
              .type(ButtonType.Normal)
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .fontSize(13)
              .backgroundColor(this.textScale === s
                ? $r('app.color.brand') : $r('app.color.page_background'))
              .fontColor(this.textScale === s
                ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
              .onClick(() => {
                this.textScale = s;
              })
          }, (s: number) => s.toString())
        }
        .width('100%')
        Text(this.overflow() ? this.msg('text_overflow') : this.msg1('text_width_px', this.widthPx()))
          .fontSize(12)
          .fontColor(this.overflow() ? Color.Red : $r('app.color.secondary_text'))
          .width('100%')
        Button($r('app.string.text_insert'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(40)
          .width('100%')
          .fontSize(14)
          .enabled(this.trimmed().length > 0)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_accent_text'))
          .onClick(() => {
            this.doInsert();
          })
        Button($r('app.string.common_cancel'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(38)
          .width('100%')
          .fontSize(14)
          .backgroundColor($r('app.color.page_background'))
          .fontColor($r('app.color.secondary_text'))
          .onClick(() => {
            this.onClose();
          })
      }
      .width('86%')
      .padding(20)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
