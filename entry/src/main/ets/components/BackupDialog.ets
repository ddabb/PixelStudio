/**
 * components/BackupDialog.ets — 备份/恢复对话框（1.1.0-C 批，开发计划 §15）。
 * scrim 全屏遮罩仿 ProjectListPage 对话框先例；.pxba 旁路容器经 DocumentViewPicker
 * 落用户目录（save/select 免权限，无需 module 声明）；恢复 = 不存在才写（非破坏性），
 * 结果播报「已导入 N 个 · 跳过 M 个」；用户取消选择器静默返回；失败统一文案不崩。
 */

import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BackupCodec, BackupEntry } from '../core/BackupCodec';
import { ProjectStore } from '../viewmodel/ProjectStore';
import { PaletteStore } from '../viewmodel/PaletteStore';
import { Haptics } from '../viewmodel/Haptics';

/** 备份容器内调色板档名（恢复路由按名分发）。 */
const PALETTES_FILE_NAME = 'palettes.txt';

@ComponentV2
export struct BackupDialog {
  @Param open: boolean = false;
  @Param onClose: () => void = (): void => {};
  /** 恢复有新增时回调（列表页刷新）。 */
  @Param onRestored: () => void = (): void => {};
  @Local busy: boolean = false;
  /** 结果文案（本地化格式化后）。 */
  @Local result: string = '';
  private store: ProjectStore = new ProjectStore();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      this.store.init(ctx);
    }
  }

  /** 打开即清结果（上次播报不残留）。 */
  @Monitor('open')
  onOpenChange(): void {
    if (this.open) {
      this.result = '';
      this.busy = false;
    }
  }

  // ---------- 本地化取串（getStringByNameSync + '%d' 顺序替换，仿 LayerPanel 先例） ----------

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

  private msg2(name: string, v1: number, v2: number): string {
    return this.msg(name).replace('%d', v1.toString()).replace('%d', v2.toString());
  }

  // ---------- 备份 / 恢复 ----------

  /** 备份：工程目录全部文件 + palettes.txt → .pxba → save 选择器落用户目录。 */
  private async doBackup(): Promise<void> {
    if (this.busy) {
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    Haptics.tick();
    const entries: BackupEntry[] = [];
    for (const name of this.store.listProjectFileNames()) {
      // .tmp 临时残料不入档（瞬态文件）。
      if (name.endsWith('.tmp')) {
        continue;
      }
      const data = this.store.readProjectFileBytes(name);
      if (data === undefined) {
        continue;
      }
      const e = new BackupEntry();
      e.name = name;
      e.data = data;
      entries.push(e);
    }
    const pal = PaletteStore.readBackupBytes(ctx);
    if (pal !== undefined) {
      const e = new BackupEntry();
      e.name = PALETTES_FILE_NAME;
      e.data = pal;
      entries.push(e);
    }
    if (entries.length === 0) {
      this.result = this.msg('backup_none');
      return;
    }
    const pxba = await BackupCodec.serialize(entries);
    if (pxba === undefined) {
      this.result = this.msg('backup_open_fail');
      return;
    }
    try {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = ['pixelstudio-backup.pxba'];
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await documentPicker.save(saveOptions);
      if (uris.length === 0) {
        return;
      }
      this.busy = true;
      if (BackupDialog.writeBytesToUri(uris[0], pxba)) {
        this.result = this.msg1('backup_done', entries.length);
      } else {
        this.result = this.msg('backup_open_fail');
      }
    } catch (e) {
      this.result = this.msg('backup_open_fail');
    }
    this.busy = false;
  }

  /** 恢复：select 选择器读 .pxba → parse → 逐条目不存在才写；播报导入/跳过数。 */
  private async doRestore(): Promise<void> {
    if (this.busy) {
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    Haptics.tick();
    try {
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.fileSuffixFilters = ['.pxba'];
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await documentPicker.select(selectOptions);
      if (uris.length === 0) {
        return;
      }
      this.busy = true;
      const bytes = BackupDialog.readBytesFromUri(uris[0]);
      const map = bytes === undefined ? undefined : await BackupCodec.parse(bytes);
      if (map === undefined) {
        this.result = this.msg('backup_open_fail');
      } else {
        let added = 0;
        let skipped = 0;
        map.forEach((data: Uint8Array, name: string): void => {
          const ok = name === PALETTES_FILE_NAME
            ? PaletteStore.writeBackupBytesIfAbsent(ctx, data)
            : this.store.writeProjectFileIfAbsent(name, data);
          if (ok) {
            added++;
          } else {
            skipped++;
          }
        });
        this.result = this.msg2('backup_imported', added, skipped);
        if (added > 0) {
          this.onRestored();
        }
      }
    } catch (e) {
      this.result = this.msg('backup_open_fail');
    }
    this.busy = false;
  }

  // ---------- uri 读写（picker 返回 uri → fd；整化缓冲沿 ProjectStore 先例） ----------

  private static readBytesFromUri(uri: string): Uint8Array | undefined {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const size = fs.statSync(file.fd).size;
        if (size <= 0) {
          return undefined;
        }
        const buf = new ArrayBuffer(size);
        const n = fs.readSync(file.fd, buf, { length: size });
        if (n !== size) {
          return undefined;
        }
        return new Uint8Array(buf);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return undefined;
    }
  }

  private static writeBytesToUri(uri: string, bytes: Uint8Array): boolean {
    try {
      let body = bytes;
      if (bytes.byteOffset !== 0 || bytes.buffer.byteLength !== bytes.length) {
        const exact = new Uint8Array(bytes.length);
        exact.set(bytes);
        body = exact;
      }
      const file = fs.openSync(uri, fs.OpenMode.READ_WRITE);
      try {
        const n = fs.writeSync(file.fd, body.buffer, { length: body.length });
        return n === body.length;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return false;
    }
  }

  build() {
    if (this.open) {
      Column() {
        Column({ space: 14 }) {
          Text($r('app.string.backup_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          if (this.result.length > 0) {
            Text(this.result)
              .fontSize(13)
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          Row({ space: 10 }) {
            Button($r('app.string.backup_action'))
              .type(ButtonType.Normal)
              .borderRadius(10)
              .height(40)
              .layoutWeight(1)
              .fontSize(14)
              .enabled(!this.busy)
              .backgroundColor($r('app.color.brand'))
              .fontColor($r('app.color.on_accent_text'))
              .onClick(() => {
                this.doBackup();
              })
            Button($r('app.string.backup_restore'))
              .type(ButtonType.Normal)
              .borderRadius(10)
              .height(40)
              .layoutWeight(1)
              .fontSize(14)
              .enabled(!this.busy)
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.primary_text'))
              .onClick(() => {
                this.doRestore();
              })
          }
          .width('100%')
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
              this.result = '';
              this.onClose();
            })
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
          this.result = '';
          this.onClose();
        }
      })
    }
  }
}
