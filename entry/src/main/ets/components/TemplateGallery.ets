/**
 * components/TemplateGallery.ets — 分类模板库画廊（1.3.0 批，长期任务，
 * 章程见 docs/模板库长期任务章程.md）。
 * 近全屏遮罩：分类页签（全部 + 六类）→ 卡片网格（thumb 解码 Map 缓存）→
 * 点击卡片预览确认（大图 + 描述 + 规格）→「使用模板」回调 onUse(def, 本地化名)；
 * 落地（rawfile → 沙箱新工程）由宿主页 ProjectStore.instantiateTemplate 完成。
 * 模板名/描述内嵌清单 zh/en 字段，按系统语言前缀 zh 选取（泛型题材不侵权，
 * 章程三原则见上）。
 */

import { image } from '@kit.ImageKit';
import { i18n } from '@kit.LocalizationKit';
import { ProjectStore, THUMB_MAX } from '../viewmodel/ProjectStore';
import { PixelMaps } from '../viewmodel/PixelMaps';
import { TemplateDef, TEMPLATE_DEFS, TPL_CATEGORIES } from '../viewmodel/TemplateDefs';

@ComponentV2
export struct TemplateGallery {
  @Param open: boolean = false;
  @Param onClose: () => void = (): void => {};
  /** 使用模板：def + 本地化名（宿主页 instantiateTemplate → 打开编辑器）。 */
  @Param onUse: (def: TemplateDef, name: string) => void =
    (_def: TemplateDef, _name: string): void => {};
  /** 当前分类页签（'all' = 全部；其余为 TPL_CATEGORIES 之一）。 */
  @Local activeCat: string = 'all';
  /** 预览中的模板（undefined = 无预览）。 */
  @Local previewDef: TemplateDef | undefined = undefined;
  /** 使用中（防重复回调）。 */
  @Local busy: boolean = false;
  /** 缩略图解码完成（挂载后异步预解码，完成前显示加载态）。 */
  @Local thumbsReady: boolean = false;
  /** 模板 id → 已解码缩略图。 */
  private thumbs: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();

  aboutToAppear(): void {
    this.loadThumbs();
  }

  /** 打开即复位页签/预览/防抖（上次会话状态不残留）。 */
  @Monitor('open')
  onOpenChange(): void {
    if (this.open) {
      this.activeCat = 'all';
      this.previewDef = undefined;
      this.busy = false;
    }
  }

  /** 挂载后一次性预解码全部模板缩略图（15 个小图，边车缺失/损坏跳过不阻断）。 */
  private async loadThumbs(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    for (const def of TEMPLATE_DEFS) {
      const thumbPath = `${def.file.substring(0, def.file.length - 4)}.thumb`;
      try {
        const bytes = await ctx.resourceManager.getRawFileContent(thumbPath);
        if (ProjectStore.checkThumbBytes(bytes)) {
          const pm = TemplateGallery.decodeThumb(bytes);
          if (pm !== undefined) {
            this.thumbs.set(def.id, pm);
          }
        }
      } catch (e) {
      }
    }
    this.thumbsReady = true;
  }

  /** 缩略图字节 → PixelMap（[w][h][RGBA]；字节已由 checkThumbBytes 校验）。 */
  private static decodeThumb(bytes: Uint8Array): image.PixelMap | undefined {
    const tw: number = bytes[0] | (bytes[1] << 8);
    const th: number = bytes[2] | (bytes[3] << 8);
    if (tw < 1 || th < 1 || tw > THUMB_MAX || th > THUMB_MAX) {
      return undefined;
    }
    return PixelMaps.createSrgb(bytes.buffer.slice(4), tw, th);
  }

  /** 中文环境（zh-CN/zh-Hans 等前缀 zh）；其余走英文字段。 */
  private isZh(): boolean {
    return i18n.System.getSystemLanguage().startsWith('zh');
  }

  private tplName(def: TemplateDef): string {
    return this.isZh() ? def.nameZh : def.nameEn;
  }

  private tplDesc(def: TemplateDef): string {
    return this.isZh() ? def.descZh : def.descEn;
  }

  /** 页签序列：全部 + 六类。 */
  private tabs(): string[] {
    const out: string[] = ['all'];
    for (const c of TPL_CATEGORIES) {
      out.push(c);
    }
    return out;
  }

  /** 页签文案（tpl_cat_all / tpl_cat_<cat>）。 */
  private tabLabel(cat: string): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return cat;
    }
    try {
      return ctx.resourceManager.getStringByNameSync(
        cat === 'all' ? 'tpl_cat_all' : `tpl_cat_${cat}`);
    } catch (e) {
      return cat;
    }
  }

  /** 当前分类的模板清单。 */
  private visibleDefs(): TemplateDef[] {
    if (this.activeCat === 'all') {
      return TEMPLATE_DEFS;
    }
    const out: TemplateDef[] = [];
    for (const d of TEMPLATE_DEFS) {
      if (d.cat === this.activeCat) {
        out.push(d);
      }
    }
    return out;
  }

  private thumbOf(id: string): image.PixelMap | undefined {
    return this.thumbs.get(id);
  }

  /** 使用模板：回调宿主页（防重复）；宿主页落地成功后关闭画廊。 */
  private useTemplate(): void {
    const def = this.previewDef;
    if (def === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.onUse(def, this.tplName(def));
  }

  /** 缩略图（缺失/损坏显示占位底色）。 */
  @Builder
  tplThumb(def: TemplateDef, side: number) {
    if (this.thumbOf(def.id) !== undefined) {
      Image(this.thumbOf(def.id))
        .width(side)
        .height(side)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.None)
    }
  }

  /** 模板卡片：缩略图 + 名称 + 规格；点击进预览。 */
  @Builder
  tplCard(def: TemplateDef) {
    Column({ space: 8 }) {
      Column() {
        this.tplThumb(def, 92)
      }
      .width('100%')
      .height(100)
      .borderRadius(10)
      .backgroundColor($r('app.color.canvas_backdrop'))
      .border({ width: 1, color: $r('app.color.border_color') })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Text(this.tplName(def))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)

      Text($r('app.string.tpl_spec', def.w, def.h, def.frames, def.fps))
        .fontSize(11)
        .fontColor($r('app.color.hint_text'))
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(14)
    .onClick(() => {
      this.previewDef = def;
    })
  }

  /** 预览确认层：大图 + 名称 + 描述 + 规格 + 使用/取消。 */
  @Builder
  tplPreview(def: TemplateDef) {
    Column() {
      Column({ space: 14 }) {
        Column() {
          this.tplThumb(def, 216)
        }
        .width(216)
        .height(216)
        .borderRadius(12)
        .backgroundColor($r('app.color.canvas_backdrop'))
        .border({ width: 1, color: $r('app.color.border_color') })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)

        Text(this.tplName(def))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text(this.tplDesc(def))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Text($r('app.string.tpl_spec', def.w, def.h, def.frames, def.fps))
          .fontSize(12)
          .fontColor($r('app.color.hint_text'))

        Row({ space: 10 }) {
          Button($r('app.string.common_cancel'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .enabled(!this.busy)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.secondary_text'))
            .onClick(() => {
              this.previewDef = undefined;
            })
          Button($r('app.string.tpl_use'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .enabled(!this.busy)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_accent_text'))
            .onClick(() => {
              this.useTemplate();
            })
        }
        .width('100%')

        if (this.busy) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color($r('app.color.brand'))
        }
      }
      .width('86%')
      .padding(20)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.45)')
    .onClick(() => {
      if (!this.busy) {
        this.previewDef = undefined;
      }
    })
  }

  build() {
    if (this.open) {
      Stack() {
        // 遮罩（点击关闭）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => {
            if (!this.busy) {
              this.onClose();
            }
          })

        // 画廊主体（近全屏，贴底上圆角）
        Column() {
          Row({ space: 10 }) {
            Text($r('app.string.tpl_gallery_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Blank()
            Button($r('app.string.common_cancel'))
              .type(ButtonType.Normal)
              .borderRadius(10)
              .height(34)
              .padding({ left: 14, right: 14 })
              .fontSize(13)
              .enabled(!this.busy)
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.secondary_text'))
              .onClick(() => {
                if (!this.busy) {
                  this.onClose();
                }
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 8 })

          // 分类页签（横向滚动）
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.tabs(), (cat: string) => {
                Button(this.tabLabel(cat))
                  .type(ButtonType.Normal)
                  .borderRadius(14)
                  .height(30)
                  .padding({ left: 14, right: 14 })
                  .fontSize(12)
                  .backgroundColor(this.activeCat === cat
                    ? $r('app.color.brand') : $r('app.color.card_background'))
                  .fontColor(this.activeCat === cat
                    ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
                  .onClick(() => {
                    this.activeCat = cat;
                  })
              }, (cat: string) => cat)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          // 卡片网格（两列；解码未完显示加载态）
          if (this.thumbsReady) {
            Grid() {
              ForEach(this.visibleDefs(), (def: TemplateDef) => {
                GridItem() {
                  this.tplCard(def)
                }
              }, (def: TemplateDef) => `${def.cat}/${def.id}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .layoutWeight(1)
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 14 })
          } else {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(40)
                .height(40)
                .color($r('app.color.brand'))
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .width('100%')
          }
        }
        .width('100%')
        .height('94%')
        .backgroundColor($r('app.color.page_background'))
        .borderRadius({ topLeft: 16, topRight: 16 })
        .alignItems(HorizontalAlign.Start)

        // 预览确认层（最上层）
        if (this.previewDef !== undefined) {
          this.tplPreview(this.previewDef)
        }
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Bottom)
    }
  }
}
