/**
 * components/FrameStrip.ets — 帧面板（M3，开发计划 §4.1 帧 / §5.3 帧面板）。
 * 横向帧缩略条（合成预览）+ 当前帧描边高亮 + ＋/复制/删除/左右移 +
 * 播放 ▶（切回画布循环预览，任意触屏即停）+ FPS 滑杆（1-30 默认 8）+ 洋葱皮 Toggle。
 * 缩略图 = 逐帧 Compose 合成（tick / strokeCount 变化时整体重建）。
 */

import { image } from '@kit.ImageKit';
import { PixelDoc } from '../core/PixelDoc';
import { Compose } from '../core/Compose';
import { EditorSession } from '../viewmodel/EditorSession';
import { DocOps } from '../viewmodel/DocOps';

@ComponentV2
export struct FrameStrip {
  @Require @Param doc: PixelDoc;
  @Require @Param session: EditorSession;
  /** 播放启动回调（切回画布 Tab 使循环预览可见）。 */
  @Param onPlay: () => void = (): void => {};

  @Local thumbs: image.PixelMap[] = [];
  @Local frameCount: number = 0;
  @Local deleting: boolean = false;
  private composeBuf: Uint8Array = new Uint8Array(0);

  aboutToAppear(): void {
    this.composeBuf = new Uint8Array(this.doc.w * this.doc.h * 4);
    this.rebuild();
  }

  @Monitor('session.tick', 'session.strokeCount')
  onDocChange(): void {
    this.rebuild();
  }

  private rebuild(): void {
    const out: image.PixelMap[] = [];
    const opts: image.InitializationOptions = {
      editable: false,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { width: this.doc.w, height: this.doc.h }
    };
    for (let f = 0; f < this.doc.frameCount; f++) {
      Compose.composeFrame(this.doc, f, this.composeBuf);
      out.push(image.createPixelMapSync(this.composeBuf.buffer.slice(0), opts));
    }
    this.thumbs = out;
    this.frameCount = this.doc.frameCount;
  }

  private togglePlay(): void {
    if (this.frameCount <= 1) {
      return;
    }
    if (this.session.playing) {
      this.session.playing = false;
      return;
    }
    this.session.playing = true;
    this.onPlay();
  }

  @Builder
  playButton() {
    Button(this.session.playing ? $r('app.string.frame_stop') : $r('app.string.frame_play'))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(34)
      .padding({ left: 14, right: 14 })
      .fontSize(13)
      .enabled(this.frameCount > 1)
      .backgroundColor(this.session.playing
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.playing
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.togglePlay();
      })
  }

  @Builder
  thumbItem(thumb: image.PixelMap, index: number) {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(thumb)
          .width(48)
          .height(48)
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.None)
          .backgroundColor($r('app.color.canvas_backdrop'))
        Text(`${index + 1}`)
          .fontSize(9)
          .fontColor($r('app.color.on_accent_text'))
          .backgroundColor($r('app.color.brand'))
          .borderRadius(4)
          .padding({ left: 3, right: 3 })
          .margin(2)
      }
      .border({
        width: this.session.activeFrame === index ? 3 : 1,
        color: this.session.activeFrame === index
          ? $r('app.color.brand') : $r('app.color.border_color')
      })
      .borderRadius(6)
    }
    .onClick(() => {
      DocOps.setActiveFrame(this.doc, this.session, index);
    })
  }

  @Builder
  opButton(label: ResourceStr, enabledCond: boolean, danger: boolean, onTap: () => void) {
    Button(label)
      .type(ButtonType.Normal)
      .borderRadius(8)
      .height(32)
      .padding({ left: 10, right: 10 })
      .fontSize(12)
      .enabled(enabledCond)
      .backgroundColor($r('app.color.card_background'))
      .fontColor(danger ? $r('app.color.danger_red') : $r('app.color.primary_text'))
      .onClick(() => {
        onTap();
      })
  }

  build() {
    Column() {
      // 头部：标题 + 帧位 + 播放
      Row({ space: 8 }) {
        Text($r('app.string.tab_frames'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text(`${this.session.activeFrame + 1}/${this.frameCount}`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        Blank()
        this.playButton()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })

      // FPS 滑杆 + 洋葱皮
      Row({ space: 8 }) {
        Text($r('app.string.frame_fps'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
        Slider({ value: this.session.fps, min: 1, max: 30, step: 1, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .trackColor($r('app.color.border_color'))
          .selectedColor($r('app.color.brand'))
          .onChange((v: number) => {
            this.session.fps = Math.round(v);
          })
        Text(`${this.session.fps}`)
          .fontSize(12)
          .fontColor($r('app.color.primary_text'))
          .width(24)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })

      Row({ space: 8 }) {
        Text($r('app.string.frame_onion'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
        Toggle({ type: ToggleType.Switch, isOn: this.session.onionSkin })
          .selectedColor($r('app.color.brand'))
          .onChange((isOn: boolean) => {
            this.session.onionSkin = isOn;
            this.session.tick++;
          })
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 8 })

      // 帧缩略条（横向滚动，末端 ＋ 新增）
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.thumbs, (thumb: image.PixelMap, index: number) => {
            this.thumbItem(thumb, index)
          }, (thumb: image.PixelMap, index: number) => `f${index}`)
          Button($r('app.string.frame_add'))
            .type(ButtonType.Normal)
            .borderRadius(6)
            .width(48)
            .height(48)
            .fontSize(18)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.primary_text'))
            .accessibilityText($r('app.string.frame_add_full'))
            .onClick(() => {
              DocOps.addFrame(this.doc, this.session);
            })
        }
        .padding({ left: 12, right: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Start)

      // 活动帧操作：复制 / 左移 / 右移 / 删除（内联确认）
      if (this.deleting) {
        Row({ space: 8 }) {
          Text($r('app.string.delete_confirm'))
            .fontSize(13)
            .fontColor($r('app.color.danger_red'))
            .layoutWeight(1)
          Button($r('app.string.common_confirm'))
            .type(ButtonType.Normal)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .fontSize(12)
            .backgroundColor($r('app.color.danger_red'))
            .fontColor($r('app.color.on_accent_text'))
            .onClick(() => {
              this.deleting = false;
              DocOps.deleteFrame(this.doc, this.session, this.session.activeFrame);
            })
          Button($r('app.string.common_cancel'))
            .type(ButtonType.Normal)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .fontSize(12)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              this.deleting = false;
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      } else {
        Row({ space: 8 }) {
          this.opButton($r('app.string.frame_duplicate'), true, false, (): void => {
            DocOps.duplicateFrame(this.doc, this.session, this.session.activeFrame);
          })
          this.opButton($r('app.string.frame_move_left'),
            this.session.activeFrame > 0, false, (): void => {
              DocOps.moveFrame(this.doc, this.session, this.session.activeFrame, -1);
            })
          this.opButton($r('app.string.frame_move_right'),
            this.session.activeFrame < this.frameCount - 1, false, (): void => {
              DocOps.moveFrame(this.doc, this.session, this.session.activeFrame, 1);
            })
          Blank()
          this.opButton($r('app.string.frame_delete'),
            this.frameCount > 1, true, (): void => {
              this.deleting = true;
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
