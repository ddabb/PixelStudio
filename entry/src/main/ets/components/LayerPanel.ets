/**
 * components/LayerPanel.ets — 图层面板（M2，开发计划 §4.1 P0：≤8 层全操作）。
 * 列表自堆顶向下显示（layers[len-1] → layers[0]）；行 = 可见性 + 缩略图 +
 * 名称（点击激活）+ 上移/下移；活动行展开：不透明度滑杆（0-100 步进 10）+
 * 重命名（内联输入）+ 删除（内联二次确认）。
 * 缩略图 = 单层 cel 原始像素；tick（结构/元数据变更）与 strokeCount（笔触）
 * 变化时整体重建。layerCount 为 @Local 镜像，供计数/按钮态响应。
 */

import { image } from '@kit.ImageKit';
import { PixelDoc, MAX_LAYERS } from '../core/PixelDoc';
import { EditorSession } from '../viewmodel/EditorSession';
import { DocOps } from '../viewmodel/DocOps';

@ComponentV2
export struct LayerPanel {
  @Require @Param doc: PixelDoc;
  @Require @Param session: EditorSession;

  @Local thumbs: image.PixelMap[] = [];
  @Local layerCount: number = 0;
  @Local renaming: boolean = false;
  @Local renameText: string = '';
  @Local deleting: boolean = false;

  aboutToAppear(): void {
    this.refresh();
  }

  @Monitor('session.tick')
  onTick(): void {
    this.refresh();
  }

  @Monitor('session.strokeCount')
  onStroke(): void {
    // 笔触只改内容不改结构：仅重建缩略图。
    this.rebuildThumbs();
  }

  private refresh(): void {
    this.localizeInitialLayer();
    this.layerCount = this.doc.layers.length;
    this.rebuildThumbs();
  }

  private localizeInitialLayer(): void {
    if (this.doc.layers.length !== 1 || this.doc.layers[0].name !== 'Layer 1') {
      return;
    }
    let raw = 'Layer 1';
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined && context !== null) {
        raw = context.resourceManager.getStringByNameSync('layer_name_default').replace('%d', '1');
      }
    } catch (e) {
      raw = 'Layer 1';
    }
    this.doc.layers[0].name = raw;
  }

  private rebuildThumbs(): void {
    const out: image.PixelMap[] = [];
    const opts: image.InitializationOptions = {
      editable: false,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { width: this.doc.w, height: this.doc.h }
    };
    for (let li = 0; li < this.doc.layers.length; li++) {
      const cel = this.doc.getCell(this.doc.activeFrame, li);
      if (cel !== undefined) {
        out.push(image.createPixelMapSync(cel.data.buffer.slice(0), opts));
      }
    }
    this.thumbs = out;
  }

  /** 新建图层默认名：本地化模板“图层 %d”，手动替换占位符（%d 计数 = 现有+1）。 */
  private defaultLayerName(): string {
    let raw = 'Layer %d';
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined && context !== null) {
        raw = context.resourceManager.getStringByNameSync('layer_name_default');
      }
    } catch (e) {
      raw = 'Layer %d';
    }
    return raw.replace('%d', (this.doc.layers.length + 1).toString());
  }

  /** 显示顺序：堆顶（layers 末位）在前。 */
  private displayIndices(): number[] {
    const out: number[] = [];
    for (let li = this.doc.layers.length - 1; li >= 0; li--) {
      out.push(li);
    }
    return out;
  }

  @Builder
  layerRow(li: number) {
    Column() {
      Row({ space: 8 }) {
        Button(this.doc.layers[li].visible ? $r('app.string.layer_hide') : $r('app.string.layer_show'))
          .type(ButtonType.Normal)
          .borderRadius(8)
          .height(30)
          .padding({ left: 8, right: 8 })
          .fontSize(12)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            DocOps.setLayerVisible(this.doc, this.session, li, !this.doc.layers[li].visible);
          })
        Row({ space: 8 }) {
          if (this.thumbs[li] !== undefined) {
            Image(this.thumbs[li])
              .width(32)
              .height(32)
              .borderRadius(4)
              .objectFit(ImageFit.Fill)
              .interpolation(ImageInterpolation.None)
              .backgroundColor($r('app.color.canvas_backdrop'))
              .border({ width: 1, color: $r('app.color.border_color') })
          } else {
            Column()
              .width(32)
              .height(32)
              .borderRadius(4)
              .backgroundColor($r('app.color.canvas_backdrop'))
          }
          Text(this.doc.layers[li].name)
            .fontSize(14)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .onClick(() => {
          DocOps.setActiveLayer(this.doc, this.session, li);
          this.renaming = false;
          this.deleting = false;
        })
        Button($r('app.string.layer_move_up'))
          .type(ButtonType.Normal)
          .borderRadius(8)
          .height(30)
          .padding({ left: 8, right: 8 })
          .fontSize(12)
          .enabled(li < this.doc.layers.length - 1)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            DocOps.moveLayer(this.doc, this.session, li, 1);
          })
        Button($r('app.string.layer_move_down'))
          .type(ButtonType.Normal)
          .borderRadius(8)
          .height(30)
          .padding({ left: 8, right: 8 })
          .fontSize(12)
          .enabled(li > 0)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            DocOps.moveLayer(this.doc, this.session, li, -1);
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor(this.session.activeLayer === li
            ? $r('app.color.brand_tint') : $r('app.color.card_background'))
      if (this.session.activeLayer === li) {
        this.activeControls(li)
      }
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  activeControls(li: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text($r('app.string.layer_opacity'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
        Slider({
          value: this.doc.layers[li].opacity,
          min: 0,
          max: 100,
          step: 10,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .trackColor($r('app.color.border_color'))
          .selectedColor($r('app.color.brand'))
          .onChange((v: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              DocOps.setLayerOpacity(this.doc, this.session, li, v);
            }
          })
        Text(`${this.doc.layers[li].opacity}%`)
          .fontSize(12)
          .fontColor($r('app.color.primary_text'))
          .width(40)
      }
      .width('100%')

      if (this.renaming) {
        Row({ space: 8 }) {
          TextInput({ text: this.renameText })
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .backgroundColor($r('app.color.card_background'))
            .onChange((v: string) => {
              this.renameText = v;
            })
          Button($r('app.string.common_confirm'))
            .type(ButtonType.Normal)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .fontSize(12)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_accent_text'))
            .onClick(() => {
              DocOps.renameLayer(this.doc, this.session, li, this.renameText);
              this.renaming = false;
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
              this.renaming = false;
            })
        }
        .width('100%')
      } else if (this.deleting) {
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
              DocOps.deleteLayer(this.doc, this.session, li);
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
      } else {
        Row({ space: 8 }) {
          Button($r('app.string.layer_rename'))
            .type(ButtonType.Normal)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .fontSize(12)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              this.renameText = this.doc.layers[li].name;
              this.renaming = true;
              this.deleting = false;
            })
          Button($r('app.string.layer_delete'))
            .type(ButtonType.Normal)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .fontSize(12)
            .enabled(this.doc.layers.length > 1)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.danger_red'))
            .onClick(() => {
              this.deleting = true;
              this.renaming = false;
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, bottom: 8 })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.tab_layers'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text(`${this.layerCount}/${MAX_LAYERS}`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        Blank()
        Button($r('app.string.layer_new'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(34)
          .padding({ left: 12, right: 12 })
          .fontSize(13)
          .enabled(this.layerCount < MAX_LAYERS)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_accent_text'))
          .onClick(() => {
            this.renaming = false;
            this.deleting = false;
            DocOps.addLayer(this.doc, this.session, this.defaultLayerName());
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })

      Scroll() {
        Column() {
          ForEach(this.displayIndices(), (li: number) => {
            this.layerRow(li)
          }, (li: number) => `${li}_${this.doc.layers[li].id}_${this.session.activeLayer}_${this.session.tick}`)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
