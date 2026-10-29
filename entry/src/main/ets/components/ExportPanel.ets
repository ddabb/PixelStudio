/**
 * components/ExportPanel.ets — 导出面板（M4 批，开发计划 §5.1 第 4 Tab / §6.5 / §6.7）。
 * PNG：当前帧合成 + 1/2/4/8× 最近邻放大（透明保留）。
 * GIF：全帧合成 + 循环（帧率沿用帧面板）+ 量化模式（中位切分 / 按当前调色板直映射）+
 *       透明背景（GCE 透明索引）+ Floyd-Steinberg 抖动。
 * 拼豆图纸：品牌（Perler/Hama）量化 + 材料清单（色号/名称/数量/包数）+ 29×29 分板 +
 *       十字绣式符号图纸 PNG（§13.5 计数实测）。
 * 保存相册 = SaveButton 安全组件免授权（photoAccessHelper.createAsset，§4.1）；
 * 分享 = ShareKit ShareController（utd 精确类型 + 沙箱缓存文件 file:// uri）。
 */

import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { PixelDoc } from '../core/PixelDoc';
import { EditorSession } from '../viewmodel/EditorSession';
import { PaletteStore } from '../viewmodel/PaletteStore';
import { AppCtx } from '../viewmodel/AppCtx';
import { Compose } from '../core/Compose';
import { Resample } from '../core/Resample';
import { GifFrameData, GifEncodeOptions, encodeGif } from '../core/GifCodec/GifEncoder';
import { BeadQuantize } from '../core/BeadQuantize';
import { BeadStats, BeadManifest, BeadEntry } from '../core/BeadStats';
import { ChartRender, BeadChartOptions } from '../core/ChartRender';
import { Palettes, BeadBrand, BeadColor } from '../core/Palettes';

const SCALES: number[] = [1, 2, 4, 8];

/** 导出产物：字节 + 扩展名 + 展示文件名。 */
class ExportPayload {
  bytes: Uint8Array = new Uint8Array(0);
  ext: string = 'png';
  fileName: string = '';
}

@ComponentV2
export struct ExportPanel {
  @Require @Param doc: PixelDoc;
  @Require @Param session: EditorSession;
  @Require @Param paletteStore: PaletteStore;
  @Require @Param projectName: string;
  /** 格式：0=PNG 1=GIF 2=拼豆图纸。 */
  @Local fmt: number = 0;
  /** PNG 整数放大倍率（1/2/4/8；避开组件内置 scale 属性名）。 */
  @Local pngScale: number = 1;
  /** GIF 量化模式：true=中位切分自动；false=按当前调色板直映射。 */
  @Local gifAuto: boolean = true;
  @Local gifTransparent: boolean = true;
  @Local gifDither: boolean = true;
  @Local brandId: string = Palettes.PERLER.id;
  @Local busy: boolean = false;
  @Local manifest: BeadManifest | undefined = undefined;
  @Local chartBoards: number = 1;
  /** 豆色量化预览图（当前帧，空钉位棋盘格）。 */
  @Local previewMap: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    this.refreshBeadStats();
  }

  @Monitor('brandId')
  onBrandChange(): void {
    this.refreshBeadStats();
  }

  private brand(): BeadBrand {
    return Palettes.beadBrand(this.brandId) ?? Palettes.PERLER;
  }

  /** 材料清单、分板数与量化预览（基于当前帧；品牌切换时重算）。 */
  private refreshBeadStats(): void {
    const brand = this.brand();
    const frame = new Uint8Array(this.doc.w * this.doc.h * 4);
    Compose.composeFrame(this.doc, this.doc.activeFrame, frame);
    const indices = BeadQuantize.quantize(frame, this.doc.w, this.doc.h, brand.colors);
    this.manifest = BeadStats.manifest(indices, brand.colors);
    this.chartBoards = BeadStats.boardCount(this.doc.w, this.doc.h);
    this.previewMap = this.buildPreviewMap(indices, brand.colors);
  }

  /** 豆色量化预览 PixelMap：豆色真实 RGB；空钉位浅色棋盘格（§5.3）。 */
  private buildPreviewMap(indices: Int32Array, beads: BeadColor[]): image.PixelMap | undefined {
    const w = this.doc.w;
    const h = this.doc.h;
    const buf = new Uint8Array(w * h * 4);
    BeadQuantize.renderPreview(indices, beads, buf);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4;
        if (buf[i + 3] === 0) {
          const c = ((x + y) & 1) === 0 ? 0xEE : 0xE2;
          buf[i] = c;
          buf[i + 1] = c;
          buf[i + 2] = c;
          buf[i + 3] = 0xFF;
        }
      }
    }
    const opts: image.InitializationOptions = {
      editable: false,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { width: w, height: h }
    };
    return image.createPixelMapSync(buf.buffer, opts);
  }

  /** 预估导出文件大小（启发式，标注“约”）：PNG≈raw×0.35；GIF≈帧像素×0.45+表头；图纸≈拼板像素×0.1。 */
  private estimateBytes(): number {
    const w = this.doc.w;
    const h = this.doc.h;
    if (this.fmt === 0) {
      return Math.ceil(w * h * this.pngScale * this.pngScale * 4 * 0.35);
    }
    if (this.fmt === 1) {
      return Math.ceil(w * h * this.doc.frameCount * 0.45) + 2048;
    }
    // 拼豆图纸：cellSize 16 → 每像素位 16² 图纸像素 ×4B ×0.1 + 符号图例表头。
    return Math.ceil(w * h * 256 * 4 * 0.1) + 2048;
  }

  /** 字节数人性化（B/KB/MB，单位符号双语通用）。 */
  private fmtBytes(n: number): string {
    if (n < 1024) {
      return `${n} B`;
    }
    if (n < 1024 * 1024) {
      return `${(n / 1024).toFixed(1)} KB`;
    }
    return `${(n / (1024 * 1024)).toFixed(1)} MB`;
  }

  private canUsePalette(): boolean {
    const pal = this.paletteStore.activePalette();
    return pal !== undefined && pal.colors.length >= 1 && pal.colors.length <= 256;
  }

  /** 当前调色板 → RGB 三元组表（GIF fixedPalette 直映射）。 */
  private fixedPalette(): Uint8Array | null {
    if (!this.canUsePalette()) {
      return null;
    }
    const pal = this.paletteStore.activePalette();
    if (pal === undefined) {
      return null;
    }
    const out = new Uint8Array(pal.colors.length * 3);
    for (let i = 0; i < pal.colors.length; i++) {
      const c: number = pal.colors[i];
      out[i * 3] = (c >>> 16) & 0xFF;
      out[i * 3 + 1] = (c >>> 8) & 0xFF;
      out[i * 3 + 2] = c & 0xFF;
    }
    return out;
  }

  private fileSafe(name: string): string {
    const s = name.replace(/[\\/:*?"<>|#\n]/g, '_').trim().substring(0, 40);
    return s.length === 0 ? 'pixel' : s;
  }

  private async packPng(rgba: Uint8Array, w: number, h: number): Promise<ArrayBuffer> {
    const opts: image.InitializationOptions = {
      size: { width: w, height: h },
      pixelFormat: image.PixelMapFormat.RGBA_8888
    };
    const pm = image.createPixelMapSync(rgba.buffer.slice(0), opts);
    const packer = image.createImagePacker();
    try {
      return await packer.packToData(pm, { format: 'image/png', quality: 100 });
    } finally {
      pm.release();
      packer.release();
    }
  }

  /** 按当前面板状态导出字节（主线程执行，64×64×32 帧在 2s 预算内，§6.5）。 */
  private async exportBytes(): Promise<ExportPayload | undefined> {
    const base = this.fileSafe(this.projectName);
    if (this.fmt === 0) {
      // PNG：当前帧 + 整数倍放大
      const frame = new Uint8Array(this.doc.w * this.doc.h * 4);
      Compose.composeFrame(this.doc, this.doc.activeFrame, frame);
      const scaled = Resample.scaleNearest(frame, this.doc.w, this.doc.h, this.pngScale);
      const ab = await this.packPng(scaled, this.doc.w * this.pngScale, this.doc.h * this.pngScale);
      const p = new ExportPayload();
      p.bytes = new Uint8Array(ab);
      p.ext = 'png';
      p.fileName = `${base}_${this.doc.w * this.pngScale}x${this.doc.h * this.pngScale}.png`;
      return p;
    }
    if (this.fmt === 1) {
      // GIF：全帧 + 循环 + 量化选项
      const frames: GifFrameData[] = [];
      const delayCs = Math.max(1, Math.round(100 / this.session.fps));
      const buf = new Uint8Array(this.doc.w * this.doc.h * 4);
      for (let f = 0; f < this.doc.frameCount; f++) {
        Compose.composeFrame(this.doc, f, buf);
        const fd = new GifFrameData();
        fd.width = this.doc.w;
        fd.height = this.doc.h;
        fd.delayCs = delayCs;
        fd.pixels = buf.slice();
        frames.push(fd);
      }
      const o = new GifEncodeOptions();
      o.loopCount = 0;
      o.dither = this.gifDither;
      o.transparent = this.gifTransparent;
      o.fixedPalette = this.gifAuto ? null : this.fixedPalette();
      const p = new ExportPayload();
      p.bytes = encodeGif(frames, o);
      p.ext = 'gif';
      p.fileName = `${base}.gif`;
      return p;
    }
    // 拼豆图纸：品牌量化 + 十字绣式渲染（cellSize 16px，§6.7）
    const brand = this.brand();
    const frame = new Uint8Array(this.doc.w * this.doc.h * 4);
    Compose.composeFrame(this.doc, this.doc.activeFrame, frame);
    const indices = BeadQuantize.quantize(frame, this.doc.w, this.doc.h, brand.colors);
    const chartOpts = new BeadChartOptions();
    const rgba = ChartRender.renderChart(indices, this.doc.w, this.doc.h, brand.colors, chartOpts);
    const size = ChartRender.chartSize(this.doc.w, this.doc.h, chartOpts);
    const ab = await this.packPng(rgba, size.w, size.h);
    const p = new ExportPayload();
    p.bytes = new Uint8Array(ab);
    p.ext = 'png';
    p.fileName = `${base}_bead.png`;
    return p;
  }

  private toast(msg: Resource | string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  /** 保存到相册（SaveButton 临时授权内完成；失败仅提示不抛出）。 */
  private async saveToAlbum(p: ExportPayload): Promise<void> {
    const ctx = AppCtx.uiContext;
    if (ctx === undefined) {
      this.toast($r('app.string.export_failed_toast'));
      return;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, p.ext);
      const file = fs.openSync(uri, fs.OpenMode.READ_WRITE);
      try {
        const n = fs.writeSync(file.fd, p.bytes.buffer, { length: p.bytes.length });
        if (n !== p.bytes.length) {
          throw new Error('short write');
        }
      } finally {
        fs.closeSync(file);
      }
      this.toast($r('app.string.export_saved_toast'));
    } catch (e) {
      this.toast($r('app.string.export_failed_toast'));
    }
  }

  /** 系统分享（沙箱缓存文件 + file:// uri + utd 精确类型；面板失败仅提示）。 */
  private async sharePayload(p: ExportPayload): Promise<void> {
    const ctx = AppCtx.uiContext;
    if (ctx === undefined) {
      this.toast($r('app.string.export_share_failed_toast'));
      return;
    }
    try {
      const dir = `${ctx.cacheDir}/export`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const path = `${dir}/${p.fileName}`;
      const file = fs.openSync(path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const n = fs.writeSync(file.fd, p.bytes.buffer, { length: p.bytes.length });
        if (n !== p.bytes.length) {
          throw new Error('short write');
        }
      } finally {
        fs.closeSync(file);
      }
      const utdId = utd.getUniformDataTypeByFilenameExtension(`.${p.ext}`, utd.UniformDataType.IMAGE);
      const record: systemShare.SharedRecord = {
        utd: utdId,
        uri: fileUri.getUriFromPath(path),
        title: p.fileName
      };
      const data = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(data);
      await controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (e) {
      this.toast($r('app.string.export_share_failed_toast'));
    }
  }

  /** 导出入口：toAlbum=true 走 SaveButton 授权保存，否则系统分享。 */
  private runExport(toAlbum: boolean): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.exportBytes().then((p: ExportPayload | undefined): void => {
      if (p === undefined) {
        this.toast($r('app.string.export_failed_toast'));
        return;
      }
      if (toAlbum) {
        this.saveToAlbum(p);
      } else {
        this.sharePayload(p);
      }
    }).catch(() => {
      this.toast($r('app.string.export_failed_toast'));
    }).finally(() => {
      this.busy = false;
    });
  }

  // ---------- UI ----------

  @Builder
  fmtButton(mode: number, label: ResourceStr) {
    Button(label)
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(34)
      .layoutWeight(1)
      .fontSize(13)
      .backgroundColor(this.fmt === mode
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.fmt === mode
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.fmt = mode;
      })
  }

  @Builder
  scaleButton(k: number) {
    Button(`${k}×`)
      .type(ButtonType.Normal)
      .borderRadius(10)
      .width(48)
      .height(34)
      .fontSize(13)
      .backgroundColor(this.pngScale === k
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.pngScale === k
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.pngScale = k;
      })
  }

  @Builder
  toggleRow(label: ResourceStr, isOn: boolean, onToggle: (v: boolean) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((v: boolean) => {
          onToggle(v);
        })
    }
    .width('100%')
  }

  @Builder
  brandButton(id: string, label: ResourceStr) {
    Button(label)
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(34)
      .layoutWeight(1)
      .fontSize(13)
      .backgroundColor(this.brandId === id
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.brandId === id
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.brandId = id;
      })
  }

  @Builder
  manifestRow(code: string, name: string, argb: number, count: number, packs: number) {
    Row({ space: 10 }) {
      Circle()
        .width(22)
        .height(22)
        .fill(argb)
        .stroke($r('app.color.hint_text'))
        .strokeWidth(0.5)
      Text(`${code} ${name}`)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text($r('app.string.export_chart_count', count))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      Text($r('app.string.export_chart_packs', packs))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  beadSection() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        this.brandButton(Palettes.PERLER.id, $r('app.string.palette_name_bead_perler'))
        this.brandButton(Palettes.HAMA.id, $r('app.string.palette_name_bead_hama'))
      }
      .width('100%')
      // 豆色量化预览（豆色真实 RGB，空钉位棋盘格）
      Column({ space: 6 }) {
        Text($r('app.string.export_bead_preview'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        if (this.previewMap !== undefined) {
          Image(this.previewMap)
            .width('100%')
            .height(110)
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.None)
            .draggable(false)
            .borderRadius(8)
            .backgroundColor($r('app.color.canvas_backdrop'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      if (this.manifest !== undefined) {
        Text($r('app.string.export_chart_summary', this.manifest.total,
          this.manifest.entries.length, this.chartBoards))
          .fontSize(13)
          .fontColor($r('app.color.primary_text'))
        Text($r('app.string.export_estimated_size', this.fmtBytes(this.estimateBytes())))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        Row({ space: 6 }) {
          Text($r('app.string.export_chart_materials'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
          Text($r('app.string.export_chart_note'))
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
        }
        .width('100%')
        Scroll() {
          Column() {
            ForEach(this.manifest.entries, (e: BeadEntry) => {
              this.manifestRow(e.code, e.name, e.argb, e.count, e.packs)
            }, (e: BeadEntry) => e.code)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 10 }) {
      // 格式切换
      Row({ space: 8 }) {
        this.fmtButton(0, $r('app.string.export_format_png'))
        this.fmtButton(1, $r('app.string.export_format_gif'))
        this.fmtButton(2, $r('app.string.export_format_chart'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10 })

      // 参数区
      Scroll() {
        Column({ space: 10 }) {
          if (this.fmt === 0) {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text($r('app.string.export_scale_label'))
                  .fontSize(13)
                  .fontColor($r('app.color.secondary_text'))
                ForEach(SCALES, (k: number) => {
                  this.scaleButton(k)
                }, (k: number) => `k${k}`)
                Blank()
              }
              .width('100%')
              Text($r('app.string.export_output_size', this.doc.w * this.pngScale, this.doc.h * this.pngScale))
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
              Text($r('app.string.export_estimated_size', this.fmtBytes(this.estimateBytes())))
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          } else if (this.fmt === 1) {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text($r('app.string.export_gif_palette_mode'))
                  .fontSize(13)
                  .fontColor($r('app.color.secondary_text'))
                Button($r('app.string.export_gif_auto'))
                  .type(ButtonType.Normal)
                  .borderRadius(10)
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .fontSize(12)
                  .backgroundColor(this.gifAuto
                    ? $r('app.color.brand') : $r('app.color.card_background'))
                  .fontColor(this.gifAuto
                    ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
                  .onClick(() => {
                    this.gifAuto = true;
                  })
                Button($r('app.string.export_gif_use_palette'))
                  .type(ButtonType.Normal)
                  .borderRadius(10)
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .fontSize(12)
                  .enabled(this.canUsePalette())
                  .backgroundColor(!this.gifAuto
                    ? $r('app.color.brand') : $r('app.color.card_background'))
                  .fontColor(!this.gifAuto
                    ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
                  .onClick(() => {
                    if (this.canUsePalette()) {
                      this.gifAuto = false;
                    }
                  })
                Blank()
              }
              .width('100%')
              Text(`${this.doc.w}×${this.doc.h} · ${this.doc.frameCount}f · ${this.session.fps}FPS`)
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
              Text($r('app.string.export_estimated_size', this.fmtBytes(this.estimateBytes())))
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
              this.toggleRow($r('app.string.export_transparent'), this.gifTransparent,
                (v: boolean): void => {
                  this.gifTransparent = v;
                })
              this.toggleRow($r('app.string.export_dither'), this.gifDither,
                (v: boolean): void => {
                  this.gifDither = v;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          } else {
            this.beadSection()
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 10 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      // 底部：保存相册（安全控件免授权）+ 系统分享
      if (this.busy) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.brand'))
          Text($r('app.string.export_busy'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }
      }
      Row({ space: 10 }) {
        SaveButton({ text: SaveDescription.SAVE_IMAGE, icon: SaveIconStyle.FULL_FILLED,
          buttonType: ButtonType.Capsule })
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            if (result === SaveButtonOnClickResult.SUCCESS) {
              this.runExport(true);
            }
          })
        Button($r('app.string.export_share'))
          .type(ButtonType.Normal)
          .borderRadius(24)
          .height(40)
          .layoutWeight(1)
          .fontSize(14)
          .enabled(!this.busy)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.runExport(false);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
