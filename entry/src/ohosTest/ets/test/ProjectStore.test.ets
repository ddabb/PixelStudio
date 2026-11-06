/**
 * projectStoreTest — 工程持久化套件（M4 批）：ProjectStore（.pxs 落盘 / 列表 / 重命名 / 删除 / 损坏容错）。
 * 运行协议（模拟器 class 过滤）：
 *   hdc shell aa test -b com.ddabb.pixelstudio -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class projectStoreTest -s timeout 15000
 * 验收对应（开发计划 §13.4）：保存/加载往返像素逐一相等；损坏文件 corrupt 标记不崩溃。
 * 测试工程统一 test_ 前缀，afterAll 清理，不污染目录。
 */

import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ProjectStore, ProjectRecord, DEMO_IDS } from '../../../main/ets/viewmodel/ProjectStore';
import { TemplateDef, TEMPLATE_DEFS, TPL_CATEGORIES } from '../../../main/ets/viewmodel/TemplateDefs';
import { PixelDoc } from '../../../main/ets/core/PixelDoc';
import { PxsDoc } from '../../../main/ets/core/PxsFile';

export default function projectStoreTest() {
  describe('projectStoreTest', () => {
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

    it('newIdUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < 200; i++) {
        const id = ProjectStore.newId();
        expect(id.startsWith('p')).assertTrue();
        expect(id.length >= 8).assertTrue();
        expect(seen.has(id)).assertFalse();
        seen.add(id);
      }
    })

    it('newTemplateIdPrefix', 0, () => {
      // 模板实例 id：tpl_ 前缀 + 唯一（同秒多次使用不撞）。
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < 200; i++) {
        const id = ProjectStore.newTemplateId();
        expect(id.startsWith('tpl_')).assertTrue();
        expect(id.length >= 8).assertTrue();
        expect(seen.has(id)).assertFalse();
        seen.add(id);
      }
    })

    it('sanitizeName', 0, () => {
      expect(ProjectStore.sanitizeName('往返|A#B')).assertEqual('往返/AB');
      expect(ProjectStore.sanitizeName('  a\nb  ')).assertEqual('a b');
      expect(ProjectStore.sanitizeName('')).assertEqual('');
      let long = '';
      for (let i = 0; i < 100; i++) {
        long += 'x';
      }
      expect(ProjectStore.sanitizeName(long).length).assertEqual(64);
      // buildMeta 的 fps 收口（1-30）。
      const doc = new PixelDoc(4, 4);
      const meta = ProjectStore.buildMeta(doc, 'n', 99, 'pico8');
      expect(meta.fps).assertEqual(30);
      const meta2 = ProjectStore.buildMeta(doc, 'n', 0, 'pico8');
      expect(meta2.fps).assertEqual(1);
    })

    it('saveLoadRoundTrip', 0, async () => {
      const doc = new PixelDoc(4, 5);
      doc.addLayer('L2');
      doc.addFrame();
      doc.cells[0][0].data[0] = 0x11;
      doc.cells[0][0].data[3] = 0xFF;
      doc.cells[0][1].data[7] = 0x22;
      doc.cells[1][0].data[11] = 0x33;
      doc.cells[1][1].data[15] = 0x44;
      doc.layers[1].visible = false;
      doc.layers[1].opacity = 40;
      const meta = ProjectStore.buildMeta(doc, '往返|A#B', 12, 'pico8');
      const ok = await store.saveDoc('test_rt1', meta, doc.cells);
      expect(ok).assertTrue();
      const pxs: PxsDoc | undefined = await store.loadDoc('test_rt1');
      expect(pxs !== undefined).assertTrue();
      if (pxs === undefined) {
        return;
      }
      expect(pxs.meta.name).assertEqual('往返/AB');
      expect(pxs.meta.w).assertEqual(4);
      expect(pxs.meta.h).assertEqual(5);
      expect(pxs.meta.fps).assertEqual(12);
      expect(pxs.meta.frameCount).assertEqual(2);
      expect(pxs.meta.paletteId).assertEqual('pico8');
      expect(pxs.meta.layers.length).assertEqual(2);
      // 像素逐字节相等（全 cel）
      for (let f = 0; f < 2; f++) {
        for (let l = 0; l < 2; l++) {
          expect(pxs.cells[f][l].data.length).assertEqual(doc.cells[f][l].data.length);
          for (let i = 0; i < doc.cells[f][l].data.length; i++) {
            expect(pxs.cells[f][l].data[i]).assertEqual(doc.cells[f][l].data[i]);
          }
        }
      }
      // toDoc：图层 id/可见性/不透明度保留
      const back = ProjectStore.toDoc(pxs);
      expect(back.w).assertEqual(4);
      expect(back.h).assertEqual(5);
      expect(back.frameCount).assertEqual(2);
      expect(back.layers.length).assertEqual(2);
      expect(back.layers[0].id).assertEqual(1);
      expect(back.layers[1].id).assertEqual(2);
      expect(back.layers[1].visible).assertFalse();
      expect(back.layers[1].opacity).assertEqual(40);
      expect(back.cells[1][1].data[15]).assertEqual(0x44);
    })

    it('toDocActivatesTopVisibleLayer', 0, async () => {
      // 多层工程打开默认激活顶层可见层：笔触落在呈现层，不被上层不透明像素遮挡。
      const doc = new PixelDoc(4, 4);
      doc.addLayer('L2');
      const meta = ProjectStore.buildMeta(doc, '顶层可见', 8, 'pico8');
      expect(await store.saveDoc('test_tv1', meta, doc.cells)).assertTrue();
      const pxs1: PxsDoc | undefined = await store.loadDoc('test_tv1');
      expect(pxs1 !== undefined).assertTrue();
      if (pxs1 !== undefined) {
        expect(ProjectStore.toDoc(pxs1).activeLayer).assertEqual(1);
      }
      // 顶层隐藏 → 回退其下首个可见层（隐藏层上落笔视觉无反馈）。
      doc.layers[1].visible = false;
      const meta2 = ProjectStore.buildMeta(doc, '顶层隐藏', 8, 'pico8');
      expect(await store.saveDoc('test_tv2', meta2, doc.cells)).assertTrue();
      const pxs2: PxsDoc | undefined = await store.loadDoc('test_tv2');
      expect(pxs2 !== undefined).assertTrue();
      if (pxs2 !== undefined) {
        expect(ProjectStore.toDoc(pxs2).activeLayer).assertEqual(0);
      }
    })

    it('listRecords', 0, async () => {
      const docA = new PixelDoc(8, 6);
      const metaA = ProjectStore.buildMeta(docA, '工程甲', 8, 'pico8');
      const okA = await store.saveDoc('test_li1', metaA, docA.cells);
      expect(okA).assertTrue();
      const docB = new PixelDoc(16, 16);
      docB.addFrame();
      const metaB = ProjectStore.buildMeta(docB, '工程乙', 12, 'gray');
      const okB = await store.saveDoc('test_li2', metaB, docB.cells);
      expect(okB).assertTrue();
      const recs = await store.list();
      let a: ProjectRecord | undefined = undefined;
      let b: ProjectRecord | undefined = undefined;
      for (const r of recs) {
        if (r.id === 'test_li1') {
          a = r;
        } else if (r.id === 'test_li2') {
          b = r;
        }
      }
      expect(a !== undefined).assertTrue();
      expect(b !== undefined).assertTrue();
      if (a === undefined || b === undefined) {
        return;
      }
      expect(a.corrupt).assertFalse();
      expect(a.name).assertEqual('工程甲');
      expect(a.w).assertEqual(8);
      expect(a.h).assertEqual(6);
      expect(a.frameCount).assertEqual(1);
      expect(a.layerCount).assertEqual(1);
      expect(a.updatedAt > 0).assertTrue();
      expect(b.corrupt).assertFalse();
      expect(b.name).assertEqual('工程乙');
      expect(b.frameCount).assertEqual(2);
    })

    it('loadMissingReturnsUndefined', 0, async () => {
      const pxs = await store.loadDoc('test_no_such_project');
      expect(pxs === undefined).assertTrue();
    })

    it('overwriteUpdate', 0, async () => {
      const docA = new PixelDoc(4, 4);
      docA.cells[0][0].data[0] = 0xAA;
      const metaA = ProjectStore.buildMeta(docA, '旧内容', 8, 'pico8');
      const okA = await store.saveDoc('test_ov1', metaA, docA.cells);
      expect(okA).assertTrue();
      const docB = new PixelDoc(4, 4);
      docB.cells[0][0].data[0] = 0xBB;
      const metaB = ProjectStore.buildMeta(docB, '新内容', 10, 'cga');
      const okB = await store.saveDoc('test_ov1', metaB, docB.cells);
      expect(okB).assertTrue();
      const pxs: PxsDoc | undefined = await store.loadDoc('test_ov1');
      expect(pxs !== undefined).assertTrue();
      if (pxs === undefined) {
        return;
      }
      expect(pxs.meta.name).assertEqual('新内容');
      expect(pxs.meta.fps).assertEqual(10);
      expect(pxs.cells[0][0].data[0]).assertEqual(0xBB);
      // 临时文件不留残骸
      expect(fs.accessSync(`${context.filesDir}/pixel/projects/test_ov1.pxs.tmp`)).assertFalse();
    })

    it('corruptFileFlaggedNotCrash', 0, async () => {
      const dir = `${context.filesDir}/pixel/projects`;
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, true);
        }
      } catch (e) {
      }
      // 垃圾字节（≥9 触发解压路径失败）
      const file = fs.openSync(`${dir}/test_co1.pxs`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, 'this is definitely not a pxs file!!!');
      } finally {
        fs.closeSync(file);
      }
      const recs = await store.list();
      let co: ProjectRecord | undefined = undefined;
      for (const r of recs) {
        if (r.id === 'test_co1') {
          co = r;
        }
      }
      expect(co !== undefined).assertTrue();
      if (co !== undefined) {
        expect(co.corrupt).assertTrue();
        expect(co.name).assertEqual('test_co1');
      }
      const pxs = await store.loadDoc('test_co1');
      expect(pxs === undefined).assertTrue();
    })

    it('renameAndRemove', 0, async () => {
      const doc = new PixelDoc(4, 4);
      const meta = ProjectStore.buildMeta(doc, '原名', 8, 'pico8');
      const okSave = await store.saveDoc('test_rn1', meta, doc.cells);
      expect(okSave).assertTrue();
      const okRename = await store.rename('test_rn1', '新名字');
      expect(okRename).assertTrue();
      const pxs: PxsDoc | undefined = await store.loadDoc('test_rn1');
      expect(pxs !== undefined).assertTrue();
      if (pxs !== undefined) {
        expect(pxs.meta.name).assertEqual('新名字');
      }
      const recs = await store.list();
      for (const r of recs) {
        if (r.id === 'test_rn1') {
          expect(r.name).assertEqual('新名字');
        }
      }
      // 空名/缺失工程重命名失败
      const badRename = await store.rename('test_rn1', '   ');
      expect(badRename).assertFalse();
      const missRename = await store.rename('test_missing_rn', 'x');
      expect(missRename).assertFalse();
      // 删除：成功 → 再删失败 → 加载失败
      expect(store.remove('test_rn1')).assertTrue();
      expect(store.remove('test_rn1')).assertFalse();
      const gone = await store.loadDoc('test_rn1');
      expect(gone === undefined).assertTrue();
    })

    it('thumbWriteReadCompose', 0, async () => {
      // 8×6 不触发降采样：缩略图原尺寸；首帧合成红色像素进缩略图。
      const doc = new PixelDoc(8, 6);
      doc.layers[0].visible = true;
      const px = doc.cells[0][0].data;
      for (let y = 0; y < 6; y++) {
        for (let x = 0; x < 8; x++) {
          const i = (y * 8 + x) * 4;
          if (x < 4) {
            px[i] = 0xFF;
            px[i + 3] = 0xFF;
          }
        }
      }
      const meta = ProjectStore.buildMeta(doc, '缩略', 8, 'pico8');
      const ok = await store.saveDoc('test_th1', meta, doc.cells);
      expect(ok).assertTrue();
      const thumb = store.readThumb('test_th1');
      expect(thumb !== undefined).assertTrue();
      if (thumb === undefined) {
        return;
      }
      const tw = thumb[0] | (thumb[1] << 8);
      const th = thumb[2] | (thumb[3] << 8);
      expect(tw).assertEqual(8);
      expect(th).assertEqual(6);
      expect(thumb.length).assertEqual(4 + 8 * 6 * 4);
      // 左半红：R=255、A=255（首帧合成 + 边车往返）
      const i0 = 4 + (2 * 8 + 1) * 4;
      expect(thumb[i0]).assertEqual(0xFF);
      expect(thumb[i0 + 3]).assertEqual(0xFF);
      // 缺失工程 → 无缩略图
      expect(store.readThumb('test_no_such_thumb') === undefined).assertTrue();
    })

    it('thumbDownsampleMax64', 0, async () => {
      // 128×128 → 边长收敛 ≤64（最近邻降采样）。
      const doc = new PixelDoc(128, 128);
      const px = doc.cells[0][0].data;
      px[0] = 0x00;
      px[1] = 0xFF;
      px[2] = 0x00;
      px[3] = 0xFF;
      const meta = ProjectStore.buildMeta(doc, '大图', 8, 'pico8');
      const ok = await store.saveDoc('test_th2', meta, doc.cells);
      expect(ok).assertTrue();
      const thumb = store.readThumb('test_th2');
      expect(thumb !== undefined).assertTrue();
      if (thumb === undefined) {
        return;
      }
      const tw = thumb[0] | (thumb[1] << 8);
      const th = thumb[2] | (thumb[3] << 8);
      expect(tw > 0).assertTrue();
      expect(th > 0).assertTrue();
      expect(tw <= 64).assertTrue();
      expect(th <= 64).assertTrue();
      expect(thumb.length).assertEqual(4 + tw * th * 4);
      // 左上角绿色保留（(0,0) 采样自源 (0,0)）
      expect(thumb[4]).assertEqual(0x00);
      expect(thumb[5]).assertEqual(0xFF);
      expect(thumb[6]).assertEqual(0x00);
      expect(thumb[7]).assertEqual(0xFF);
    })

    it('duplicateRoundTrip', 0, async () => {
      const doc = new PixelDoc(6, 4);
      doc.addFrame();
      doc.cells[0][0].data[0] = 0x12;
      doc.cells[0][0].data[3] = 0xFF;
      doc.cells[1][0].data[4] = 0x34;
      const meta = ProjectStore.buildMeta(doc, '原件', 10, 'gray');
      const ok = await store.saveDoc('test_dp1', meta, doc.cells);
      expect(ok).assertTrue();
      // 复制：名称追加后缀；新工程独立成档
      const newId = await store.duplicate('test_dp1', '副本');
      expect(newId !== undefined).assertTrue();
      expect(newId === 'test_dp1').assertFalse();
      if (newId === undefined) {
        return;
      }
      expect(newId.startsWith('p')).assertTrue();
      const pxs: PxsDoc | undefined = await store.loadDoc(newId);
      expect(pxs !== undefined).assertTrue();
      if (pxs === undefined) {
        return;
      }
      expect(pxs.meta.name).assertEqual('原件 副本');
      expect(pxs.meta.w).assertEqual(6);
      expect(pxs.meta.h).assertEqual(4);
      expect(pxs.meta.frameCount).assertEqual(2);
      expect(pxs.meta.fps).assertEqual(10);
      expect(pxs.cells[0][0].data[0]).assertEqual(0x12);
      expect(pxs.cells[1][0].data[4]).assertEqual(0x34);
      // 副本缩略图边车随存
      expect(store.readThumb(newId) !== undefined).assertTrue();
      // 列表两者并存
      const recs = await store.list();
      let src = false;
      let copy = false;
      for (const r of recs) {
        if (r.id === 'test_dp1') {
          src = true;
        } else if (r.id === newId) {
          copy = true;
        }
      }
      expect(src && copy).assertTrue();
      // 缺失工程复制失败
      const miss = await store.duplicate('test_no_such_dup', 'x');
      expect(miss === undefined).assertTrue();
      // 新 id 为 p 前缀（afterAll 只清 test_ 前缀），显式清理副本
      expect(store.remove(newId)).assertTrue();
    })

    // ---------- 模板库（1.3.0；生成物回归锁 + 实例化往返） ----------

    it('templateDefsValid', 0, () => {
      // 39 条 = 三批 36 原创模板 + 3 示例工程入库；六类页签。
      expect(TEMPLATE_DEFS.length).assertEqual(39);
      expect(TPL_CATEGORIES.length).assertEqual(6);
      const cats: Set<string> = new Set<string>();
      for (const c of TPL_CATEGORIES) {
        cats.add(c);
      }
      const seen: Set<string> = new Set<string>();
      for (const def of TEMPLATE_DEFS) {
        expect(def.id.length > 0).assertTrue();
        expect(seen.has(def.id)).assertFalse();
        seen.add(def.id);
        expect(cats.has(def.cat)).assertTrue();
        expect(def.file.length > 0).assertTrue();
        expect(def.file.endsWith('.pxs')).assertTrue();
        expect(def.nameZh.length > 0).assertTrue();
        expect(def.nameEn.length > 0).assertTrue();
        expect(def.descZh.length > 0).assertTrue();
        expect(def.descEn.length > 0).assertTrue();
        expect(def.w > 0 && def.h > 0).assertTrue();
        expect(def.frames > 0).assertTrue();
        expect(def.fps > 0).assertTrue();
      }
      // 每类至少 1 个模板（页签不空）
      for (const c of TPL_CATEGORIES) {
        let has = false;
        for (const def of TEMPLATE_DEFS) {
          if (def.cat === c) {
            has = true;
            break;
          }
        }
        expect(has).assertTrue();
      }
    })

    it('instantiateTemplateRoundTrip', 0, async () => {
      // 首个模板（tpl_puppy 32×32 2帧）实例化：本地化名 + 规格一致 + 边车随存。
      const def = TEMPLATE_DEFS[0];
      const id1 = await store.instantiateTemplate(def, '测试模板甲');
      expect(id1 !== undefined).assertTrue();
      if (id1 === undefined) {
        return;
      }
      expect(id1.startsWith('tpl_')).assertTrue();
      const pxs: PxsDoc | undefined = await store.loadDoc(id1);
      expect(pxs !== undefined).assertTrue();
      if (pxs !== undefined) {
        expect(pxs.meta.name).assertEqual('测试模板甲');
        expect(pxs.meta.w).assertEqual(def.w);
        expect(pxs.meta.h).assertEqual(def.h);
        expect(pxs.meta.frameCount).assertEqual(def.frames);
        expect(pxs.meta.fps).assertEqual(def.fps);
        expect(pxs.cells.length).assertEqual(def.frames);
        expect(pxs.cells[0].length > 0).assertTrue();
      }
      expect(store.readThumb(id1) !== undefined).assertTrue();
      // 重复实例：新 id 不同（同秒不撞）、名独立，模板源不被污染。
      const id2 = await store.instantiateTemplate(def, '测试模板乙');
      expect(id2 !== undefined).assertTrue();
      expect(id2 === id1).assertFalse();
      if (id2 !== undefined) {
        const pxs2: PxsDoc | undefined = await store.loadDoc(id2);
        expect(pxs2 !== undefined).assertTrue();
        if (pxs2 !== undefined) {
          expect(pxs2.meta.name).assertEqual('测试模板乙');
        }
      }
      // 示例工程入库条目（demo_cat.pxs 无 templates/ 前缀路径）同样可实例化。
      let demoDef: TemplateDef | undefined = undefined;
      for (const d of TEMPLATE_DEFS) {
        if (d.id === 'demo_cat') {
          demoDef = d;
          break;
        }
      }
      expect(demoDef !== undefined).assertTrue();
      if (demoDef !== undefined) {
        const id3 = await store.instantiateTemplate(demoDef, '示例入库');
        expect(id3 !== undefined).assertTrue();
        if (id3 !== undefined) {
          expect(store.remove(id3)).assertTrue();
        }
      }
      // 坏 def（file 空）失败返回 undefined，不落半成品。
      const bad = new TemplateDef();
      const badId = await store.instantiateTemplate(bad, '坏模板');
      expect(badId === undefined).assertTrue();
      // 显式清理（tpl_ 前缀非 test_ 前缀，afterAll 不覆盖）。
      expect(store.remove(id1)).assertTrue();
      if (id2 !== undefined) {
        expect(store.remove(id2)).assertTrue();
      }
    })

    it('removeCleansThumbSidecar', 0, async () => {
      const doc = new PixelDoc(4, 4);
      const meta = ProjectStore.buildMeta(doc, '边车', 8, 'pico8');
      const ok = await store.saveDoc('test_rm1', meta, doc.cells);
      expect(ok).assertTrue();
      const dir = `${context.filesDir}/pixel/projects`;
      expect(fs.accessSync(`${dir}/test_rm1.thumb`)).assertTrue();
      expect(store.remove('test_rm1')).assertTrue();
      expect(fs.accessSync(`${dir}/test_rm1.pxs`)).assertFalse();
      expect(fs.accessSync(`${dir}/test_rm1.thumb`)).assertFalse();
    })

    // ---------- 示例工程（rawfile 随包演示 → 沙箱；末位执行，demo_ 文件随测随清） ----------

    const cleanupDemos = (): void => {
      const dir = `${context.filesDir}/pixel/projects`;
      try {
        if (!fs.accessSync(dir)) {
          return;
        }
        for (const name of fs.listFileSync(dir)) {
          if (name.startsWith('demo_')) {
            try {
              fs.unlinkSync(`${dir}/${name}`);
            } catch (e) {
            }
          }
        }
      } catch (e) {
      }
    }

    it('demoRestoreAndIdempotent', 0, async () => {
      cleanupDemos();
      // 首次恢复：全部落盘（应用上下文聚合 entry HAP 资源，rawfile 可达）。
      const r1 = await store.restoreDemos();
      expect(r1.failed).assertEqual(0);
      expect(r1.restored).assertEqual(DEMO_IDS.length);
      // 落盘工程可完整解析（协议与元数据逐项校验，以 demo_cat 为代表）。
      const cat: PxsDoc | undefined = await store.loadDoc('demo_cat');
      expect(cat !== undefined).assertTrue();
      if (cat !== undefined) {
        expect(cat.meta.name).assertEqual('星夜小猫');
        expect(cat.meta.w).assertEqual(32);
        expect(cat.meta.h).assertEqual(32);
        expect(cat.meta.fps).assertEqual(8);
        expect(cat.meta.frameCount).assertEqual(3);
        expect(cat.meta.layers.length).assertEqual(2);
        expect(cat.meta.layers[1].name).assertEqual('小猫');
        expect(cat.meta.paletteId).assertEqual('pico8');
        expect(cat.cells.length).assertEqual(3);
        expect(cat.cells[0].length).assertEqual(2);
        expect(cat.cells[0][0].data.length).assertEqual(32 * 32 * 4);
        // 打开即默认激活顶层可见层（小猫）：画脸部笔触不被顶层遮挡（回归锁）。
        const catDoc = ProjectStore.toDoc(cat);
        expect(catDoc.activeLayer).assertEqual(1);
      }
      // 缩略图边车随存且尺寸合法。
      const th = store.readThumb('demo_cat');
      expect(th !== undefined).assertTrue();
      if (th !== undefined) {
        const tw = th[0] | (th[1] << 8);
        expect(tw).assertEqual(32);
      }
      // 幂等：全部已存在 → 再恢复既不重复也不报错。
      const r2 = await store.restoreDemos();
      expect(r2.restored).assertEqual(0);
      expect(r2.failed).assertEqual(0);
      // 列表可见全部示例（无损坏、带缩略图）。
      const recs = await store.list();
      let demoCount = 0;
      for (const rec of recs) {
        if (DEMO_IDS.indexOf(rec.id) >= 0) {
          demoCount++;
          expect(rec.corrupt).assertFalse();
          expect(rec.thumb !== undefined).assertTrue();
        }
      }
      expect(demoCount).assertEqual(DEMO_IDS.length);
      cleanupDemos();
    })

    it('demoListOrderCanonical', 0, async () => {
      cleanupDemos();
      // 恢复全部 → 列表内示例顺序恒为 DEMO_IDS 序（mtime 并列走示例秩决胜，
      // 亚秒精度走反序写入的 mtime 序），两种时间精度下断言一致。
      const r = await store.restoreDemos();
      expect(r.failed).assertEqual(0);
      expect(r.restored).assertEqual(DEMO_IDS.length);
      const recs = await store.list();
      const ids: string[] = [];
      for (const rec of recs) {
        if (DEMO_IDS.indexOf(rec.id) >= 0) {
          ids.push(rec.id);
        }
      }
      expect(ids.length).assertEqual(DEMO_IDS.length);
      for (let i = 0; i < ids.length; i++) {
        expect(ids[i]).assertEqual(DEMO_IDS[i]);
      }
      cleanupDemos();
    })

    it('demoRestoreSkipsExisting', 0, async () => {
      cleanupDemos();
      // 预置用户自建的同 id 工程：恢复入口只补缺，不得覆盖。
      const doc = new PixelDoc(4, 4);
      const meta = ProjectStore.buildMeta(doc, '用户自建', 8, 'pico8');
      const ok = await store.saveDoc('demo_cat', meta, doc.cells);
      expect(ok).assertTrue();
      const r = await store.restoreDemos();
      expect(r.failed).assertEqual(0);
      const pxs: PxsDoc | undefined = await store.loadDoc('demo_cat');
      expect(pxs !== undefined).assertTrue();
      if (pxs !== undefined) {
        expect(pxs.meta.name).assertEqual('用户自建');
        expect(pxs.meta.w).assertEqual(4);
      }
      cleanupDemos();
    })

    it('demoSeedSkipsWhenDirExists', 0, async () => {
      // 目录已被套件前序用例创建 → 非首次启动，播种入口不动作。
      const dir = `${context.filesDir}/pixel/projects`;
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, true);
        }
      } catch (e) {
      }
      const seeded = await store.seedDemosIfFresh();
      expect(seeded).assertFalse();
    })

    it('demoSeedWhenFreshRestoresAll', 0, async () => {
      // 末位执行：清空并移除工程目录，模拟出厂首启 → 播种全部示例。
      const dir = `${context.filesDir}/pixel/projects`;
      try {
        if (fs.accessSync(dir)) {
          for (const name of fs.listFileSync(dir)) {
            try {
              fs.unlinkSync(`${dir}/${name}`);
            } catch (e) {
            }
          }
          fs.rmdirSync(dir);
        }
      } catch (e) {
      }
      const seeded = await store.seedDemosIfFresh();
      expect(seeded).assertTrue();
      const recs = await store.list();
      expect(recs.length).assertEqual(DEMO_IDS.length);
      for (const rec of recs) {
        expect(rec.corrupt).assertFalse();
        expect(DEMO_IDS.indexOf(rec.id) >= 0).assertTrue();
      }
    })
  })
}
