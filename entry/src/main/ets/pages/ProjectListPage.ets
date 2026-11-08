/**
 * pages/ProjectListPage.ets — 工程列表首页（开发计划 §5.3/§6.4，M4 批）。
 * 列表（缩略图/名称/尺寸/帧数/层/更新时间/损坏灰显）+ 新建（名称 + 16-256 尺寸档）+
 * 打开 / 复制 / 重命名 / 二次点击删除；杀进程恢复 = 打开即读最近存档（自动保存 ≤30s）。
 * 新建/重命名/关于为遮罩对话框；空态与加载态兜底；时间倒序排列。
 */

import { image } from '@kit.ImageKit';
import { EditorLaunch } from '../viewmodel/EditorLaunch';
import { PixelMaps } from '../viewmodel/PixelMaps';
import { ProjectStore, ProjectRecord, THUMB_MAX } from '../viewmodel/ProjectStore';
import { TemplateDef } from '../viewmodel/TemplateDefs';
import { BackupDialog } from '../components/BackupDialog';
import { TemplateGallery } from '../components/TemplateGallery';
import { ImageImportDialog } from '../components/ImageImportDialog';

/** 新建尺寸档（开发计划 §4.1：16/24/32/48/64/96/128；1.2 大画布扩展 192/256，
 *  搭配 CanvasView 局部渲染 + 撤销栈深自适应，见开发计划 §6.5 P1 手段）。 */
const NEW_SIZES: number[] = [16, 24, 32, 48, 64, 96, 128, 192, 256];

/** 列表行 UI 记录：工程元数据 + 已解码缩略图。 */
class UIProject {
  rec: ProjectRecord = new ProjectRecord();
  thumb: image.PixelMap | undefined = undefined;
}

@Entry
@ComponentV2
struct ProjectListPage {
  @Local records: UIProject[] = [];
  @Local loading: boolean = true;
  /** 新建对话框。 */
  @Local newOpen: boolean = false;
  @Local newName: string = '';
  @Local newSize: number = 64;
  /** 重命名对话框（renameId 非空即打开）。 */
  @Local renameId: string = '';
  @Local renameText: string = '';
  /** 二次点击删除确认。 */
  @Local deletingId: string = '';
  /** 关于对话框（买断说明）。 */
  @Local aboutOpen: boolean = false;
  /** 备份/恢复对话框（1.1.0-C）。 */
  @Local backupOpen: boolean = false;
  /** 模板库画廊（1.3.0）。 */
  @Local galleryOpen: boolean = false;
  /** 图片转像素画对话框（1.6.0）。 */
  @Local importOpen: boolean = false;
  private store: ProjectStore = new ProjectStore();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      this.store.init(ctx);
    }
  }

  /** 每次页面显示都重查列表：编辑器 router.back() 返回时 aboutToAppear 不会重跑。 */
  onPageShow(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    // 首次启动播种示例工程（工程目录已存在时零成本跳过）。
    await this.store.seedDemosIfFresh();
    const recs = await this.store.list();
    const out: UIProject[] = [];
    for (const rec of recs) {
      const ui = new UIProject();
      ui.rec = rec;
      if (rec.thumb !== undefined) {
        ui.thumb = ProjectListPage.decodeThumb(rec.thumb);
      }
      out.push(ui);
    }
    this.records = out;
    this.loading = false;
  }

  /** 缩略图字节 → PixelMap（[w][h][RGBA]）；字节已由 readThumb 校验。 */
  private static decodeThumb(bytes: Uint8Array): image.PixelMap | undefined {
    const tw: number = bytes[0] | (bytes[1] << 8);
    const th: number = bytes[2] | (bytes[3] << 8);
    if (tw < 1 || th < 1 || tw > THUMB_MAX || th > THUMB_MAX) {
      return undefined;
    }
    return PixelMaps.createSrgb(bytes.buffer.slice(4), tw, th);
  }

  /** 资源字符串转 JS 字符串（默认工程名等需要参与逻辑的文案）。 */
  private str(res: Resource): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    try {
      // getStringSync(Resource) 已废弃（API 20），走 resId 重载。
      return ctx.resourceManager.getStringSync(res.id);
    } catch (e) {
      return '';
    }
  }

  private toast(msg: Resource | string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private fmtTime(seconds: number): string {
    const d = new Date(seconds * 1000);
    const p = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  private openProject(rec: ProjectRecord): void {
    if (rec.corrupt) {
      this.toast($r('app.string.project_corrupt'));
      return;
    }
    EditorLaunch.openExisting(rec.id);
    this.getUIContext().getRouter().pushUrl({ url: 'pages/EditorPage' });
  }

  /** 新建对话框尺寸档行（9 档换行排布，窄屏不溢出）。 */
  @Builder
  sizeButtons() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(NEW_SIZES, (size: number) => {
        this.sizeButton(size)
      }, (size: number) => `s${size}`)
    }
    .width('100%')
  }

  private createProject(): void {
    const name = this.newName.trim().length > 0
      ? this.newName.trim()
      : this.str($r('app.string.project_name_default'));
    this.newOpen = false;
    this.newName = '';
    EditorLaunch.openNew(name, this.newSize, this.newSize);
    this.getUIContext().getRouter().pushUrl({ url: 'pages/EditorPage' });
  }

  private async applyRename(): Promise<void> {
    const id = this.renameId;
    const text = this.renameText.trim();
    this.renameId = '';
    if (id.length === 0 || text.length === 0) {
      return;
    }
    const ok = await this.store.rename(id, text);
    if (!ok) {
      this.toast($r('app.string.project_rename_failed'));
    }
    this.refresh();
  }

  private async deleteProject(id: string): Promise<void> {
    this.deletingId = '';
    this.store.remove(id);
    this.refresh();
  }

  /** 复制工程（.pxs + 缩略图全量副本，名称追加“副本”）。 */
  private async copyProject(id: string): Promise<void> {
    const suffix = this.str($r('app.string.project_copy_suffix'));
    const newId = await this.store.duplicate(id, suffix);
    if (newId === undefined) {
      this.toast($r('app.string.project_copy_failed'));
    }
    this.refresh();
  }

  /** 恢复示例工程：缺失的从随包 rawfile 落盘，已存在跳过；结果三态播报。 */
  private async restoreDemos(): Promise<void> {
    const r = await this.store.restoreDemos();
    if (r.failed > 0) {
      this.toast($r('app.string.demo_restore_failed'));
    } else if (r.restored > 0) {
      this.toast($r('app.string.demo_restored_toast', r.restored));
    } else {
      this.toast($r('app.string.demo_present_toast'));
    }
    this.refresh();
  }

  /** 模板库「使用模板」：rawfile 模板 → 沙箱新工程（本地化名）→ 打开编辑器。 */
  private async useTemplate(def: TemplateDef, name: string): Promise<void> {
    this.galleryOpen = false;
    const id = await this.store.instantiateTemplate(def, name);
    if (id === undefined) {
      this.toast($r('app.string.tpl_use_failed'));
      this.refresh();
      return;
    }
    EditorLaunch.openExisting(id);
    this.getUIContext().getRouter().pushUrl({ url: 'pages/EditorPage' });
  }

  /** 图片转像素「生成工程」：已落盘 → 打开既有工程链路进编辑器（复用模板通道）。 */
  private openImported(id: string): void {
    this.importOpen = false;
    EditorLaunch.openExisting(id);
    this.getUIContext().getRouter().pushUrl({ url: 'pages/EditorPage' });
  }

  @Builder
  sizeButton(size: number) {
    Button(size.toString())
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      // 自适应宽 + 最小宽：128/192/256 三位数字不被固定宽截成省略号（96 档同理留余量）。
      .padding({ left: 12, right: 12 })
      .constraintSize({ minWidth: 52 })
      .fontSize(14)
      .backgroundColor(this.newSize === size
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.newSize === size
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.newSize = size;
      })
  }

  @Builder
  newDialog() {
    Column({ space: 14 }) {
      Text($r('app.string.project_new'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
      TextInput({ placeholder: $r('app.string.project_name_hint'), text: this.newName })
        .onChange((v: string) => {
          this.newName = v;
        })
        .height(44)
        .fontSize(14)
        .backgroundColor($r('app.color.page_background'))
      Column({ space: 8 }) {
        Text($r('app.string.project_size_label'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        this.sizeButtons()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Row({ space: 10 }) {
        Blank()
        Button($r('app.string.common_cancel'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(38)
          .fontSize(14)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.secondary_text'))
          .onClick(() => {
            this.newOpen = false;
            this.newName = '';
          })
        Button($r('app.string.project_create'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(38)
          .padding({ left: 18, right: 18 })
          .fontSize(14)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_accent_text'))
          .onClick(() => {
            this.createProject();
          })
      }
      .width('100%')
    }
    .width('86%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  renameDialog() {
    Column({ space: 14 }) {
      Text($r('app.string.project_rename'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
      TextInput({ placeholder: $r('app.string.project_rename_hint'), text: this.renameText })
        .onChange((v: string) => {
          this.renameText = v;
        })
        .height(44)
        .fontSize(14)
        .backgroundColor($r('app.color.page_background'))
      Row({ space: 10 }) {
        Blank()
        Button($r('app.string.common_cancel'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(38)
          .fontSize(14)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.secondary_text'))
          .onClick(() => {
            this.renameId = '';
          })
        Button($r('app.string.common_confirm'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(38)
          .padding({ left: 18, right: 18 })
          .fontSize(14)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_accent_text'))
          .onClick(() => {
            this.applyRename();
          })
      }
      .width('100%')
    }
    .width('86%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  /** 缩略图块：有边车显图，缺失/损坏显占位底。 */
  @Builder
  thumbBox(ui: UIProject) {
    Column() {
      if (ui.thumb !== undefined) {
        Image(ui.thumb)
          .width(48)
          .height(48)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.None)
      }
    }
    .width(48)
    .height(48)
    .borderRadius(8)
    .backgroundColor($r('app.color.canvas_backdrop'))
    .border({ width: 1, color: $r('app.color.border_color') })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /** 关于对话框：应用说明 + 买断制说明（购买凭证=华为账号，卸载重装免费恢复）。 */
  @Builder
  aboutDialog() {
    Column({ space: 12 }) {
      Text($r('app.string.about_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
      Text($r('app.string.app_name'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
      Text($r('app.string.app_tagline'))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      Text($r('app.string.about_buyout'))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(18)
      Text($r('app.string.offline_note'))
        .fontSize(12)
        .fontColor($r('app.color.hint_text'))
        .lineHeight(16)
      Row({ space: 6 }) {
        Text($r('app.string.version_label'))
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
        Text($r('app.string.version_value'))
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
      }
      Button($r('app.string.common_confirm'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(38)
        .padding({ left: 18, right: 18 })
        .fontSize(14)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.on_accent_text'))
        .onClick(() => {
          this.aboutOpen = false;
        })
    }
    .width('86%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  projectRow(ui: UIProject) {
    Row({ space: 8 }) {
      this.thumbBox(ui)
      // 左侧信息区：点击打开
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(ui.rec.corrupt ? ui.rec.id : ui.rec.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ui.rec.corrupt ? $r('app.color.hint_text') : $r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (ui.rec.corrupt) {
            Text($r('app.string.project_corrupt'))
              .fontSize(10)
              .fontColor($r('app.color.danger_red'))
              .backgroundColor($r('app.color.page_background'))
              .borderRadius(8)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          }
        }
        .width('100%')
        Text(ui.rec.corrupt ? this.fmtTime(ui.rec.updatedAt)
          : $r('app.string.project_record_meta', ui.rec.w, ui.rec.h, ui.rec.frameCount,
            ui.rec.layerCount, this.fmtTime(ui.rec.updatedAt)))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.openProject(ui.rec);
      })

      Button($r('app.string.project_copy'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(32)
        .padding({ left: 10, right: 10 })
        .fontSize(12)
        .enabled(!ui.rec.corrupt)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick(() => {
          this.deletingId = '';
          this.copyProject(ui.rec.id);
        })
      Button($r('app.string.project_rename'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(32)
        .padding({ left: 10, right: 10 })
        .fontSize(12)
        .enabled(!ui.rec.corrupt)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick(() => {
          this.deletingId = '';
          this.renameText = ui.rec.name;
          this.renameId = ui.rec.id;
        })
      Button(this.deletingId === ui.rec.id
        ? $r('app.string.project_delete_confirm') : $r('app.string.project_delete'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(32)
        .padding({ left: 10, right: 10 })
        .fontSize(12)
        .backgroundColor($r('app.color.card_background'))
        .fontColor(this.deletingId === ui.rec.id
          ? $r('app.color.danger_red') : $r('app.color.secondary_text'))
        .onClick(() => {
          if (this.deletingId === ui.rec.id) {
            this.deleteProject(ui.rec.id);
          } else {
            this.deletingId = ui.rec.id;
          }
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(14)
  }

  build() {
    Stack() {
      Column() {
        // 顶栏：应用名 + 新建
        Row({ space: 8 }) {
          Text($r('app.string.app_name'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Blank()
          Button($r('app.string.tpl_gallery_title'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(38)
            .padding({ left: 14, right: 14 })
            .fontSize(14)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              this.deletingId = '';
              this.galleryOpen = true;
            })
          Button($r('app.string.import_entry'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(38)
            .padding({ left: 14, right: 14 })
            .fontSize(14)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              this.deletingId = '';
              this.importOpen = true;
            })
          Button($r('app.string.project_new'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(38)
            .padding({ left: 16, right: 16 })
            .fontSize(14)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_accent_text'))
            .onClick(() => {
              this.deletingId = '';
              this.newName = '';
              this.newSize = 64;
              this.newOpen = true;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color($r('app.color.brand'))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.records.length === 0) {
            Column({ space: 10 }) {
              Text($r('app.string.project_empty'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.secondary_text'))
              Text($r('app.string.project_empty_hint'))
                .fontSize(13)
                .fontColor($r('app.color.hint_text'))
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column({ space: 10 }) {
                ForEach(this.records, (ui: UIProject) => {
                  this.projectRow(ui)
                }, (ui: UIProject) => ui.rec.id)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 4, bottom: 8 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .width('100%')
          }
        }

        // 页脚：关于入口 + 版本
        Row({ space: 6 }) {
          Text($r('app.string.version_label'))
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
          Text($r('app.string.version_value'))
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
          Blank()
          Button($r('app.string.demo_restore'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(30)
            .padding({ left: 14, right: 14 })
            .fontSize(12)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.secondary_text'))
            .onClick(() => {
              this.restoreDemos();
            })
          Button($r('app.string.backup_action'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(30)
            .padding({ left: 14, right: 14 })
            .fontSize(12)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.secondary_text'))
            .onClick(() => {
              this.backupOpen = true;
            })
          Button($r('app.string.about_title'))
            .type(ButtonType.Normal)
            .borderRadius(10)
            .height(30)
            .padding({ left: 14, right: 14 })
            .fontSize(12)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.secondary_text'))
            .onClick(() => {
              this.aboutOpen = true;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 10 })
      }
      .width('100%')
      .height('100%')

      // 遮罩对话框（新建 / 重命名 / 关于）
      if (this.newOpen || this.renameId.length > 0 || this.aboutOpen) {
        Column() {
          if (this.newOpen) {
            this.newDialog()
          } else if (this.renameId.length > 0) {
            this.renameDialog()
          } else {
            this.aboutDialog()
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.newOpen = false;
          this.renameId = '';
          this.aboutOpen = false;
        })
      }

      // 备份/恢复对话框（1.1.0-C；scrim 自含，恢复有新增时刷新列表）
      BackupDialog({
        open: this.backupOpen,
        onClose: (): void => {
          this.backupOpen = false;
        },
        onRestored: (): void => {
          this.refresh();
        }
      })

      // 模板库画廊（1.3.0；scrim 自含，「使用模板」落地成功后进编辑器）
      TemplateGallery({
        open: this.galleryOpen,
        onClose: (): void => {
          this.galleryOpen = false;
        },
        onUse: (def: TemplateDef, name: string): void => {
          this.useTemplate(def, name);
        }
      })

      // 图片转像素画（1.6.0；scrim 自含，「生成工程」走先落盘再打开链路）
      ImageImportDialog({
        open: this.importOpen,
        mode: 'project',
        onClose: (): void => {
          this.importOpen = false;
        },
        onCreated: (id: string): void => {
          this.openImported(id);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
