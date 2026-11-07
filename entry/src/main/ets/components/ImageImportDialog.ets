/**
 * components/ImageImportDialog.ets — 图片转像素画对话框（1.6.0，功能需求 §5）。
 * 选图（系统选择器免权限：PhotoViewPicker 优先，DocumentViewPicker 兜底）→
 * 参数面板（尺寸/适配/采样/色彩模式/自动色数/抖动）→ 并排实时预览 →
 * 生成：mode='project' 落盘新工程回调 onCreated（列表页跳编辑器）；
 *       mode='layer' 回调 onPixels（编辑器 DocOps.importLayer 导入为图层）。
 * 隐私硬约束：原图只在内存（解码限边 2048，峰值 ≤16MB），不落盘、不进 .pxs、零网络；
 * 取消/失败零副作用（不建空工程、不留临时文件）；确认前不写任何工程。
 * 注意：@Builder 值传参在 V2 是快照不响应，可变状态一律在 Builder 体内读取。
 */

import { image } from '@kit.ImageKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ImageImport } from '../core/ImageImport';
import { Palette, Palettes } from '../core/Palettes';
import { PixelDoc } from '../core/PixelDoc';
import { ProjectStore } from '../viewmodel/ProjectStore';
import { Haptics } from '../viewmodel/Haptics';
import { PixelMaps } from '../viewmodel/PixelMaps';

/** 解码限边（源图最大边 >2048 时等比缩；内存峰值 ≤2048²×4≈16MB，功能需求 §9）。 */
const DECODE_MAX_SIDE = 2048;
/** 输出尺寸档（与列表页新建档一致，正方形）。 */
const IMPORT_SIZES: number[] = [16, 24, 32, 48, 64, 96, 128, 192, 256];
/** 自动色板色数档。 */
const AUTO_COLOR_STEPS: number[] = [4, 8, 16, 32, 64];

@ComponentV2
export struct ImageImportDialog {
  @Param open: boolean = false;
  /** 'project' = 生成新工程；'layer' = 导入为图层（输出尺寸固定为 fixedW×fixedH）。 */
  @Param mode: string = 'project';
  /** layer 模式固定输出尺寸（>0 时隐藏尺寸档）。 */
  @Param fixedW: number = 0;
  @Param fixedH: number = 0;
  @Param onClose: () => void = (): void => {};
  /** project 模式：新工程落盘成功（id）。 */
  @Param onCreated: (id: string) => void = (_id: string): void => {};
  /** layer 模式：转换结果 RGBA（长度 = fixedW×fixedH×4）。 */
  @Param onPixels: (rgba: Uint8Array) => void = (_rgba: Uint8Array): void => {};
  /** 原图（image.PixelMap）展示用；未选图为 undefined。 */
  @Local srcMap: image.PixelMap | undefined = undefined;
  /** 转换结果预览图。 */
  @Local outMap: image.PixelMap | undefined = undefined;
  @Local picked: boolean = false;
  @Local busy: boolean = false;
  /** 参数（重算即时生效，全程内存零副作用）。 */
  @Local outSize: number = 64;
  @Local fitCover: boolean = true;
  @Local boxSample: boolean = true;
  /** 色彩模式：0=不量化 1=按色板 2=自动色板。 */
  @Local colorMode: number = 1;
  @Local paletteId: string = 'pico8';
  @Local autoColors: number = 16;
  @Local dither: boolean = false;
  @Local projectName: string = '';
  private src: Uint8Array | undefined = undefined;
  private srcW: number = 0;
  private srcH: number = 0;
  /** 当前预览对应的转换结果（生成/导入直接消费，不再重算）。 */
  private result: Uint8Array | undefined = undefined;
  private store: ProjectStore = new ProjectStore();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      this.store.init(ctx);
    }
  }

  private isLayerMode(): boolean {
    return this.mode === 'layer';
  }

  private toast(res: Resource): void {
    this.getUIContext().getPromptAction().showToast({ message: res });
  }

  /** 资源字符串转 JS 字符串（默认工程名等参与逻辑的文案）。 */
  private str(res: Resource): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    try {
      return ctx.resourceManager.getStringSync(res.id);
    } catch (e) {
      return '';
    }
  }

  // ---------- 选图与解码 ----------

  private async pickImage(): Promise<void> {
    if (this.busy) {
      return;
    }
    let uri: string = '';
    // 相册选择器（免权限）优先；不可用回退文档选择器（与 BackupDialog 同链路）。
    try {
      const opt = new photoAccessHelper.PhotoSelectOptions();
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opt.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const res = await photoPicker.select(opt);
      if (res.photoUris.length > 0) {
        uri = res.photoUris[0];
      }
    } catch (e) {
      // 相册不可用 → 走文档选择器兜底。
    }
    if (uri.length === 0) {
      try {
        const ctx = this.getUIContext().getHostContext();
        if (ctx === undefined) {
          return;
        }
        const sopt = new picker.DocumentSelectOptions();
        sopt.fileSuffixFilters = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];
        const docPicker = new picker.DocumentViewPicker(ctx);
        const uris: string[] = await docPicker.select(sopt);
        if (uris.length > 0) {
          uri = uris[0];
        }
      } catch (e) {
        // 用户取消选择器按正常取消处理，不弹错误（功能需求 §8）。
      }
    }
    if (uri.length === 0) {
      return;
    }
    Haptics.tick();
    this.busy = true;
    const ok: boolean = await this.decode(uri);
    this.busy = false;
    if (!ok) {
      this.toast($r('app.string.import_failed'));
      return;
    }
    this.picked = true;
    this.rebuildPreview();
  }

  /** uri → 限边解码 → RGBA 缓冲（原图只在内存，用毕释放 PixelMap/ImageSource）。 */
  private async decode(uri: string): Promise<boolean> {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const source = image.createImageSource(file.fd);
        const info = await source.getImageInfo();
        const maxSide: number = Math.max(info.size.width, info.size.height);
        const scale: number = Math.min(1, DECODE_MAX_SIDE / Math.max(1, maxSide));
        const opts: image.DecodingOptions = {
          editable: false,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredSize: {
            width: Math.max(1, Math.round(info.size.width * scale)),
            height: Math.max(1, Math.round(info.size.height * scale))
          }
        };
        const pm = await source.createPixelMap(opts);
        const pinfo = await pm.getImageInfo();
        const w: number = pinfo.size.width;
        const h: number = pinfo.size.height;
        if (w < 1 || h < 1) {
          pm.release();
          source.release();
          return false;
        }
        const buf = new ArrayBuffer(w * h * 4);
        await pm.readPixelsToBuffer(buf);
        this.src = new Uint8Array(buf);
        this.srcW = w;
        this.srcH = h;
        // 原图展示副本（解码缓冲独占给转换管线）。
        if (this.srcMap !== undefined) {
          this.srcMap.release();
        }
        this.srcMap = PixelMaps.createSrgb(buf.slice(0), w, h);
        pm.release();
        source.release();
        return true;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return false;
    }
  }

  // ---------- 转换与预览 ----------

  private outW(): number {
    return this.isLayerMode() && this.fixedW > 0 ? this.fixedW : this.outSize;
  }

  private outH(): number {
    return this.isLayerMode() && this.fixedH > 0 ? this.fixedH : this.outSize;
  }

  private paletteById(id: string): Palette | undefined {
    for (const p of Palettes.builtinPalettes()) {
      if (p.id === id) {
        return p;
      }
    }
    return undefined;
  }

  /** 参数变化 → 重算预览（≤256² 纯本地毫秒级；结果缓存供生成/导入消费）。 */
  private rebuildPreview(): void {
    const src = this.src;
    if (src === undefined || !this.picked) {
      return;
    }
    const ow: number = this.outW();
    const oh: number = this.outH();
    let result: Uint8Array;
    try {
      result = ImageImport.resample(src, this.srcW, this.srcH, ow, oh, this.fitCover, this.boxSample);
      if (this.dither) {
        ImageImport.applyBayer(result, ow, oh);
      }
      if (this.colorMode === 1) {
        const pal = this.paletteById(this.paletteId);
        if (pal !== undefined && pal.colors.length > 0) {
          ImageImport.quantize(result, pal.colors);
        }
      } else if (this.colorMode === 2) {
        const auto = ImageImport.autoPalette(result, this.autoColors);
        if (auto.length > 0) {
          ImageImport.quantize(result, auto);
        }
      }
    } catch (e) {
      this.toast($r('app.string.import_failed'));
      return;
    }
    this.result = result;
    if (this.outMap !== undefined) {
      this.outMap.release();
    }
    this.outMap = PixelMaps.createSrgb(result.buffer.slice(0), ow, oh);
  }

  // ---------- 生成 / 导入 ----------

  private async generate(): Promise<void> {
    if (this.busy || this.result === undefined) {
      return;
    }
    const result = this.result;
    if (this.isLayerMode()) {
      Haptics.tick();
      this.onPixels(result);
      return;
    }
    this.busy = true;
    const doc = new PixelDoc(this.outW(), this.outH());
    doc.cells[0][0].data.set(result);
    const name = this.projectName.trim().length > 0
      ? this.projectName.trim()
      : this.str($r('app.string.import_name_default'));
    const paletteId = this.colorMode === 1 ? this.paletteId : 'pico8';
    const meta = ProjectStore.buildMeta(doc, name, 8, paletteId);
    const id = ProjectStore.newId();
    const ok = await this.store.saveDoc(id, meta, doc.cells);
    this.busy = false;
    if (!ok) {
      this.toast($r('app.string.import_failed'));
      return;
    }
    Haptics.tick();
    this.onCreated(id);
  }

  // ---------- 参数 UI（可变状态一律 Builder 体内读取） ----------

  /** 色板名本地化（palette_name_{id} 资源键；$r 需字面量，按 id 分发）。 */
  private paletteLabel(id: string): ResourceStr {
    if (id === 'gbdmg') {
      return $r('app.string.palette_name_gbdmg');
    }
    if (id === 'gray') {
      return $r('app.string.palette_name_gray');
    }
    if (id === 'cga') {
      return $r('app.string.palette_name_cga');
    }
    if (id === 'bead_perler') {
      return $r('app.string.palette_name_bead_perler');
    }
    if (id === 'bead_hama') {
      return $r('app.string.palette_name_bead_hama');
    }
    return $r('app.string.palette_name_pico8');
  }

  /** 参数组标签。 */
  @Builder
  paramLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.secondary_text'))
  }

  /** 适配方式（cover / contain）。 */
  @Builder
  fitRow() {
    Row({ space: 8 }) {
      Button($r('app.string.import_fit_cover'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(34)
        .layoutWeight(1)
        .fontSize(13)
        .backgroundColor(this.fitCover ? $r('app.color.brand') : $r('app.color.card_background'))
        .fontColor(this.fitCover ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
        .onClick(() => {
          this.fitCover = true;
          this.rebuildPreview();
        })
      Button($r('app.string.import_fit_contain'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(34)
        .layoutWeight(1)
        .fontSize(13)
        .backgroundColor(!this.fitCover ? $r('app.color.brand') : $r('app.color.card_background'))
        .fontColor(!this.fitCover ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
        .onClick(() => {
          this.fitCover = false;
          this.rebuildPreview();
        })
    }
    .width('100%')
  }

  /** 采样方式（面积平均 / 中心取样）。 */
  @Builder
  sampleRow() {
    Row({ space: 8 }) {
      Button($r('app.string.import_sample_box'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(34)
        .layoutWeight(1)
        .fontSize(13)
        .backgroundColor(this.boxSample ? $r('app.color.brand') : $r('app.color.card_background'))
        .fontColor(this.boxSample ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
        .onClick(() => {
          this.boxSample = true;
          this.rebuildPreview();
        })
      Button($r('app.string.import_sample_nearest'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(34)
        .layoutWeight(1)
        .fontSize(13)
        .backgroundColor(!this.boxSample ? $r('app.color.brand') : $r('app.color.card_background'))
        .fontColor(!this.boxSample ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
        .onClick(() => {
          this.boxSample = false;
          this.rebuildPreview();
        })
    }
    .width('100%')
  }

  @Builder
  sizeButtons() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(IMPORT_SIZES, (size: number) => {
        Button(size.toString())
          .type(ButtonType.Normal)
          .borderRadius(10)
          .width(46)
          .height(32)
          .fontSize(13)
          .backgroundColor(this.outSize === size
            ? $r('app.color.brand') : $r('app.color.page_background'))
          .fontColor(this.outSize === size
            ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
          .onClick(() => {
            this.outSize = size;
            this.rebuildPreview();
          })
      }, (size: number) => `s${size}`)
    }
    .width('100%')
  }

  /** 色板模式：内置调色板横滑条（选中高亮）。 */
  @Builder
  paletteChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(Palettes.builtinPalettes(), (p: Palette) => {
          Button(this.paletteLabel(p.id))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(32)
            .padding({ left: 12, right: 12 })
            .fontSize(12)
            .backgroundColor(this.paletteId === p.id
              ? $r('app.color.brand') : $r('app.color.page_background'))
            .fontColor(this.paletteId === p.id
              ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
            .onClick(() => {
              this.paletteId = p.id;
              this.rebuildPreview();
            })
        }, (p: Palette) => p.id)
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /** 自动色数档（仅自动色板模式可见）。 */
  @Builder
  autoColorChips() {
    Row({ space: 8 }) {
      ForEach(AUTO_COLOR_STEPS, (n: number) => {
        Button(n.toString())
          .type(ButtonType.Normal)
          .borderRadius(10)
          .width(44)
          .height(32)
          .fontSize(13)
          .backgroundColor(this.autoColors === n
            ? $r('app.color.brand') : $r('app.color.page_background'))
          .fontColor(this.autoColors === n
            ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
          .onClick(() => {
            this.autoColors = n;
            this.rebuildPreview();
          })
      }, (n: number) => `a${n}`)
    }
    .width('100%')
  }

  /** 三态色彩模式行 + 条件子面板。 */
  @Builder
  colorSection() {
    Row({ space: 8 }) {
      Button($r('app.string.import_color_none'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(34)
        .layoutWeight(1)
        .fontSize(13)
        .backgroundColor(this.colorMode === 0
          ? $r('app.color.brand') : $r('app.color.card_background'))
        .fontColor(this.colorMode === 0
          ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
        .onClick(() => {
          this.colorMode = 0;
          this.rebuildPreview();
        })
      Button($r('app.string.import_color_palette'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(34)
        .layoutWeight(1)
        .fontSize(13)
        .backgroundColor(this.colorMode === 1
          ? $r('app.color.brand') : $r('app.color.card_background'))
        .fontColor(this.colorMode === 1
          ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
        .onClick(() => {
          this.colorMode = 1;
          this.rebuildPreview();
        })
      Button($r('app.string.import_color_auto'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(34)
        .layoutWeight(1)
        .fontSize(13)
        .backgroundColor(this.colorMode === 2
          ? $r('app.color.brand') : $r('app.color.card_background'))
        .fontColor(this.colorMode === 2
          ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
        .onClick(() => {
          this.colorMode = 2;
          this.rebuildPreview();
        })
    }
    .width('100%')
  }

  /** 抖动开关行。 */
  @Builder
  ditherRow() {
    Row() {
      Text($r('app.string.import_dither'))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.dither })
        .onChange((on: boolean) => {
          this.dither = on;
          this.rebuildPreview();
        })
    }
    .width('100%')
  }

  /** 并排实时预览：原图 / 转换结果（最近邻，无插值糊边）。 */
  @Builder
  previewRow() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text($r('app.string.import_preview_src'))
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
        Image(this.srcMap)
          .width(104)
          .height(104)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.None)
          .backgroundColor($r('app.color.canvas_backdrop'))
          .borderRadius(8)
      }
      Column({ space: 4 }) {
        Text($r('app.string.import_preview_out'))
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
        Image(this.outMap)
          .width(104)
          .height(104)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.None)
          .backgroundColor($r('app.color.canvas_backdrop'))
          .borderRadius(8)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    if (this.open) {
      Column() {
        Scroll() {
          Column({ space: 12 }) {
            Text($r('app.string.import_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            if (!this.picked) {
              Text($r('app.string.import_hint'))
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
                .textAlign(TextAlign.Center)
                .width('100%')
            } else {
              this.previewRow()
            }
            Button($r('app.string.import_pick'))
              .type(ButtonType.Normal)
              .borderRadius(10)
              .height(40)
              .width('100%')
              .fontSize(14)
              .enabled(!this.busy)
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.primary_text'))
              .onClick(() => {
                this.pickImage();
              })
            if (this.picked) {
              if (!this.isLayerMode()) {
                TextInput({ placeholder: $r('app.string.project_name_hint'), text: this.projectName })
                  .onChange((v: string) => {
                    this.projectName = v;
                  })
                  .height(42)
                  .fontSize(13)
                  .backgroundColor($r('app.color.page_background'))
                this.paramLabel($r('app.string.import_size_label'))
                this.sizeButtons()
              }
              this.paramLabel($r('app.string.import_fit_label'))
              this.fitRow()
              this.paramLabel($r('app.string.import_sample_label'))
              this.sampleRow()
              this.paramLabel($r('app.string.import_color_label'))
              this.colorSection()
              if (this.colorMode === 1) {
                this.paletteChips()
              }
              if (this.colorMode === 2) {
                this.autoColorChips()
              }
              this.ditherRow()
              Button(this.isLayerMode()
                ? $r('app.string.import_import') : $r('app.string.import_generate'))
                .type(ButtonType.Normal)
                .borderRadius(10)
                .height(42)
                .width('100%')
                .fontSize(15)
                .enabled(!this.busy && this.result !== undefined)
                .backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.on_accent_text'))
                .onClick(() => {
                  this.generate();
                })
            }
            Button($r('app.string.common_cancel'))
              .type(ButtonType.Normal)
              .borderRadius(10)
              .height(38)
              .width('100%')
              .fontSize(14)
              .enabled(!this.busy)
              .backgroundColor($r('app.color.page_background'))
              .fontColor($r('app.color.secondary_text'))
              .onClick(() => {
                this.onClose();
              })
          }
          .width('100%')
          .padding(20)
        }
        .scrollBar(BarState.Off)
        .width('88%')
        .constraintSize({ maxHeight: '86%' })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(0,0,0,0.45)')
      .onClick(() => {
        if (!this.busy) {
          this.onClose();
        }
      })
    }
  }
}
