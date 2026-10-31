/**
 * backupTest — 备份/恢复套件（1.1.0-C 批）：BackupCodec（.pxba 编解码 / 坏档容错）+
 * ProjectStore 备份读写（不存在才写）+ PaletteStore 备份读写 + 备份→删→恢复全链路。
 * 运行协议（模拟器 class 过滤）：
 *   hdc shell aa test -b com.ddabb.pixelstudio -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class backupTest -s timeout 15000
 * 验收对应（开发计划 §15 1.1.0-C）：备份文件逐字节等；恢复非破坏（已存在跳过）；坏档 undefined 不崩。
 * 测试工程统一 test_ 前缀，afterAll 清理，不污染目录。
 */

import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BackupCodec, BackupEntry } from '../../../main/ets/core/BackupCodec';
import { ProjectStore } from '../../../main/ets/viewmodel/ProjectStore';
import { PaletteStore } from '../../../main/ets/viewmodel/PaletteStore';
import { PixelDoc } from '../../../main/ets/core/PixelDoc';
import { PxsDoc } from '../../../main/ets/core/PxsFile';

export default function backupTest() {
  describe('backupTest', () => {
    const context: common.Context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    let store: ProjectStore = new ProjectStore();

    beforeAll(() => {
      store.init(context);
    })

    afterAll(() => {
      // 清理全部测试工程（test_ 前缀），目录保留。
      const dir = `${context.filesDir}/pixel/projects`;
      try {
        if (!fs.accessSync(dir)) {
          return;
        }
        for (const name of fs.listFileSync(dir)) {
          if (name.startsWith('test_')) {
            try {
              fs.unlinkSync(`${dir}/${name}`);
            } catch (e) {
            }
          }
        }
      } catch (e) {
      }
    })

    const mkEntry = (name: string, data: Uint8Array): BackupEntry => {
      const e = new BackupEntry();
      e.name = name;
      e.data = data;
      return e;
    }

    const expectBytesEqual = (a: Uint8Array, b: Uint8Array): void => {
      expect(a.length).assertEqual(b.length);
      for (let i = 0; i < a.length; i++) {
        expect(a[i]).assertEqual(b[i]);
      }
    }

    it('codecRoundTrip', 0, async () => {
      const d1 = new Uint8Array([0x50, 0x58, 0x42, 0x41, 0x00, 0xFF, 0x7F, 0x00]);
      const d2 = new Uint8Array(300);
      for (let i = 0; i < d2.length; i++) {
        d2[i] = (i * 7) & 0xFF;
      }
      const d3 = new Uint8Array(12);
      const text = '#ps_palette';
      for (let i = 0; i < text.length; i++) {
        d3[i] = text.charCodeAt(i);
      }
      const out = await BackupCodec.serialize([
        mkEntry('test_a.pxs', d1),
        mkEntry('test_b.thumb', d2),
        mkEntry('palettes.txt', d3)
      ]);
      expect(out !== undefined).assertTrue();
      if (out === undefined) {
        return;
      }
      // 魔数 + 版本头
      expect(out[0]).assertEqual(0x50);
      expect(out[1]).assertEqual(0x58);
      expect(out[2]).assertEqual(0x42);
      expect(out[3]).assertEqual(0x41);
      expect(out[4]).assertEqual(1);
      // 往返：名集合一致 + 数据逐字节等
      const map = await BackupCodec.parse(out);
      expect(map !== undefined).assertTrue();
      if (map === undefined) {
        return;
      }
      expect(map.size).assertEqual(3);
      const e1 = map.get('test_a.pxs');
      const e2 = map.get('test_b.thumb');
      const e3 = map.get('palettes.txt');
      expect(e1 !== undefined).assertTrue();
      expect(e2 !== undefined).assertTrue();
      expect(e3 !== undefined).assertTrue();
      if (e1 === undefined || e2 === undefined || e3 === undefined) {
        return;
      }
      expectBytesEqual(e1, d1);
      expectBytesEqual(e2, d2);
      expectBytesEqual(e3, d3);
    })

    it('codecRejectsBad', 0, async () => {
      // 空输入 / 短于头
      expect(await BackupCodec.parse(new Uint8Array(0)) === undefined).assertTrue();
      expect(await BackupCodec.parse(new Uint8Array(5)) === undefined).assertTrue();
      const out = await BackupCodec.serialize([mkEntry('test_x.pxs', new Uint8Array([1, 2, 3]))]);
      expect(out !== undefined).assertTrue();
      if (out === undefined) {
        return;
      }
      // 坏魔数
      const badMagic = new Uint8Array(out);
      badMagic[0] = 0x51;
      expect(await BackupCodec.parse(badMagic) === undefined).assertTrue();
      // 坏版本
      const badVer = new Uint8Array(out);
      badVer[4] = 2;
      expect(await BackupCodec.parse(badVer) === undefined).assertTrue();
      // 截断流
      const trunc = out.slice(0, out.length - 3);
      expect(await BackupCodec.parse(trunc) === undefined).assertTrue();
      // 垃圾字节
      expect(await BackupCodec.parse(new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])) === undefined).assertTrue();
      // 坏条目名（路径穿越 / 空名）序列化即拒
      expect(await BackupCodec.serialize([mkEntry('../evil.pxs', new Uint8Array(1))]) === undefined).assertTrue();
      expect(await BackupCodec.serialize([mkEntry('sub/dir.pxs', new Uint8Array(1))]) === undefined).assertTrue();
      expect(await BackupCodec.serialize([mkEntry('', new Uint8Array(1))]) === undefined).assertTrue();
    })

    it('writeIfAbsentNoOverwrite', 0, async () => {
      const a = new Uint8Array([0xAA, 0x11, 0x22]);
      const b = new Uint8Array([0xBB, 0x33, 0x44]);
      // 首写成功 + 回读一致
      expect(store.writeProjectFileIfAbsent('test_bk1.pxs', a)).assertTrue();
      const r1 = store.readProjectFileBytes('test_bk1.pxs');
      expect(r1 !== undefined).assertTrue();
      if (r1 !== undefined) {
        expectBytesEqual(r1, a);
      }
      // 已存在不覆盖
      expect(store.writeProjectFileIfAbsent('test_bk1.pxs', b)).assertFalse();
      const r2 = store.readProjectFileBytes('test_bk1.pxs');
      expect(r2 !== undefined).assertTrue();
      if (r2 !== undefined) {
        expectBytesEqual(r2, a);
      }
      // 坏名拒写（路径穿越 / 分隔符 / 非白名单字符）
      expect(store.writeProjectFileIfAbsent('../evil.pxs', a)).assertFalse();
      expect(store.writeProjectFileIfAbsent('sub/dir.pxs', a)).assertFalse();
      expect(store.writeProjectFileIfAbsent('名.pxs', a)).assertFalse();
      expect(store.readProjectFileBytes('../evil.pxs') === undefined).assertTrue();
    })

    it('backupCoversProjectAndPaletteFiles', 0, async () => {
      const doc = new PixelDoc(6, 4);
      doc.cells[0][0].data[0] = 0x77;
      const meta = ProjectStore.buildMeta(doc, '备份覆盖', 8, 'pico8');
      const ok = await store.saveDoc('test_bk2', meta, doc.cells);
      expect(ok).assertTrue();
      // 目录清单含主档 + 缩略图边车
      const names = store.listProjectFileNames();
      expect(names.includes('test_bk2.pxs')).assertTrue();
      expect(names.includes('test_bk2.thumb')).assertTrue();
      // 主档字节可读且非空（8B 长度头 + zlib 流）
      const bytes = store.readProjectFileBytes('test_bk2.pxs');
      expect(bytes !== undefined).assertTrue();
      if (bytes !== undefined) {
        expect(bytes.length > 9).assertTrue();
      }
      // 调色板备份读写（不存在才写；二写必拒）
      const probe = new Uint8Array([0x23, 0x70, 0x73]);
      const first = PaletteStore.writeBackupBytesIfAbsent(context, probe);
      const second = PaletteStore.writeBackupBytesIfAbsent(context, probe);
      expect(second).assertFalse();
      if (first) {
        const read = PaletteStore.readBackupBytes(context);
        expect(read !== undefined).assertTrue();
        if (read !== undefined) {
          expect(read.length).assertEqual(3);
          expect(read[0]).assertEqual(0x23);
        }
        // 本用例创建的文件复原（删除），不残留测试数据
        try {
          fs.unlinkSync(`${context.filesDir}/pixel/palettes.txt`);
        } catch (e) {
        }
      } else {
        // 原本已存在：非破坏，读路径仍可用
        expect(PaletteStore.readBackupBytes(context) !== undefined).assertTrue();
      }
    })

    it('fullBackupRestoreFlow', 0, async () => {
      // 落一个带标记像素的工程
      const doc = new PixelDoc(5, 5);
      doc.cells[0][0].data[0] = 0x5A;
      doc.cells[0][0].data[3] = 0xFF;
      const meta = ProjectStore.buildMeta(doc, '全链路', 9, 'gray');
      const ok = await store.saveDoc('test_bk4', meta, doc.cells);
      expect(ok).assertTrue();
      // 备份采集（主档 + 缩略图）
      const entries: BackupEntry[] = [];
      for (const name of store.listProjectFileNames()) {
        if (name !== 'test_bk4.pxs' && name !== 'test_bk4.thumb') {
          continue;
        }
        const data = store.readProjectFileBytes(name);
        if (data !== undefined) {
          entries.push(mkEntry(name, data));
        }
      }
      expect(entries.length).assertEqual(2);
      const pxba = await BackupCodec.serialize(entries);
      expect(pxba !== undefined).assertTrue();
      if (pxba === undefined) {
        return;
      }
      // 删除工程 → 备份恢复 → 内容回归
      expect(store.remove('test_bk4')).assertTrue();
      const gone = await store.loadDoc('test_bk4');
      expect(gone === undefined).assertTrue();
      const map = await BackupCodec.parse(pxba);
      expect(map !== undefined).assertTrue();
      if (map === undefined) {
        return;
      }
      let restored = 0;
      map.forEach((data: Uint8Array, name: string): void => {
        if (store.writeProjectFileIfAbsent(name, data)) {
          restored++;
        }
      });
      expect(restored).assertEqual(2);
      const back: PxsDoc | undefined = await store.loadDoc('test_bk4');
      expect(back !== undefined).assertTrue();
      if (back !== undefined) {
        expect(back.meta.name).assertEqual('全链路');
        expect(back.meta.fps).assertEqual(9);
        expect(back.cells[0][0].data[0]).assertEqual(0x5A);
        expect(back.cells[0][0].data[3]).assertEqual(0xFF);
      }
      // 恢复幂等：再写同批 → 全部跳过
      let again = 0;
      map.forEach((data: Uint8Array, name: string): void => {
        if (store.writeProjectFileIfAbsent(name, data)) {
          again++;
        }
      });
      expect(again).assertEqual(0);
    })

    it('emptyContainerAndTolerance', 0, async () => {
      // 空容器往返对称：18B 头 + 0 条目
      const empty = await BackupCodec.serialize([]);
      expect(empty !== undefined).assertTrue();
      if (empty === undefined) {
        return;
      }
      expect(empty.length).assertEqual(18);
      const map = await BackupCodec.parse(empty);
      expect(map !== undefined).assertTrue();
      if (map !== undefined) {
        expect(map.size).assertEqual(0);
      }
      // 目录清单调用不崩（目录缺失时 ensureDir 兜底建目录）
      const names = store.listProjectFileNames();
      expect(names.length >= 0).assertTrue();
      // 重复条目名 → 拒收
      const dup = await BackupCodec.serialize([
        mkEntry('test_dup.pxs', new Uint8Array([1])),
        mkEntry('test_dup.pxs', new Uint8Array([2]))
      ]);
      expect(dup === undefined).assertTrue();
    })
  })
}
