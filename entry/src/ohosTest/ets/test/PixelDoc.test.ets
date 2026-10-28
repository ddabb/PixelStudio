/**
 * pixelDocTest — M2/M3 套件：PixelDoc 层与帧操作 / DocOps 结构撤销（DocEntry）/
 * 选区内容操作（CelEntry）/ 播放态联动。运行协议（模拟器 class 过滤）：
 *   hdc shell aa test -b com.ddabb.pixelstudio -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class pixelDocTest -s timeout 15000
 */

import { describe, it, expect } from '@ohos/hypium';
import { PixelBuffer } from '../../../main/ets/core/PixelBuffer';
import { PixelDoc, MAX_LAYERS } from '../../../main/ets/core/PixelDoc';
import { Compose } from '../../../main/ets/core/Compose';
import { Raster } from '../../../main/ets/core/Raster';
import { UndoStack } from '../../../main/ets/core/UndoStack';
import { EditorSession, SelRect } from '../../../main/ets/viewmodel/EditorSession';
import { DocOps } from '../../../main/ets/viewmodel/DocOps';

const BLACK = 0xFF000000;
const RED = 0xFFFF0000;
const GREEN = 0xFF00FF00;
const BLUE = 0xFF0000FF;

function countOpaque(buf: PixelBuffer): number {
  let n = 0;
  for (let i = 3; i < buf.data.length; i += 4) {
    if (buf.data[i] > 0) {
      n++;
    }
  }
  return n;
}

function composeTo(doc: PixelDoc): Uint8Array {
  const out = new Uint8Array(doc.w * doc.h * 4);
  Compose.composeFrame(doc, doc.activeFrame, out);
  return out;
}

function argbAt(out: Uint8Array, w: number, x: number, y: number): number {
  const i = (y * w + x) * 4;
  return (((out[i + 3] << 24) | (out[i] << 16) | (out[i + 1] << 8) | out[i + 2]) >>> 0);
}

function opaqueCountComposed(out: Uint8Array): number {
  let n = 0;
  for (let i = 3; i < out.length; i += 4) {
    if (out[i] > 0) {
      n++;
    }
  }
  return n;
}

export default function pixelDocTest() {
  describe('pixelDocTest', () => {
    // ---------- PixelDoc 层模型 ----------

    it('PixelDoc_layer_cap_eight', 0, () => {
      const doc = new PixelDoc(4, 4);
      for (let i = 1; i < MAX_LAYERS; i++) {
        expect(doc.addLayer(`L${i}`) !== undefined).assertTrue();
      }
      expect(doc.layers.length).assertEqual(MAX_LAYERS);
      expect(doc.addLayer('L9')).assertUndefined();
      expect(doc.layers.length).assertEqual(MAX_LAYERS);
      expect(doc.cells[0].length).assertEqual(MAX_LAYERS);
    });

    it('PixelDoc_delete_layer_basic', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.addLayer('Layer 2');
      doc.getCell(0, 0)!.setPx(1, 1, RED);
      doc.getCell(0, 1)!.setPx(2, 2, BLUE);
      expect(doc.deleteLayer(0)).assertTrue();
      expect(doc.layers.length).assertEqual(1);
      expect(doc.cells[0].length).assertEqual(1);
      expect(doc.getCell(0, 0)!.getPx(2, 2)).assertEqual(BLUE);
      expect(doc.getCell(0, 1)).assertUndefined();
    });

    it('PixelDoc_delete_last_layer_refused', 0, () => {
      const doc = new PixelDoc(4, 4);
      expect(doc.deleteLayer(0)).assertFalse();
      expect(doc.layers.length).assertEqual(1);
    });

    it('PixelDoc_delete_clamps_active', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.addLayer('Layer 2');
      doc.addLayer('Layer 3');
      doc.activeLayer = 2;
      expect(doc.deleteLayer(2)).assertTrue();
      expect(doc.activeLayer).assertEqual(1);
    });

    it('PixelDoc_move_layer_swap_and_active', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.addLayer('B');
      doc.addLayer('C');
      doc.activeLayer = 0;
      expect(doc.moveLayer(0, 1)).assertTrue();
      expect(doc.layers[0].name).assertEqual('B');
      // 初始 [A,B,C] → 交换 0/1 → [B,A,C]
      expect(doc.layers[1].name).assertEqual('Layer 1');
      expect(doc.layers[2].name).assertEqual('C');
      expect(doc.activeLayer).assertEqual(1);
      expect(doc.moveLayer(0, -1)).assertFalse();
      expect(doc.moveLayer(2, 1)).assertFalse();
    });

    // ---------- DocOps：结构撤销（DocEntry） ----------

    it('DocOps_add_layer_undo_redo', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      expect(DocOps.addLayer(doc, session, 'Layer 2')).assertTrue();
      expect(doc.layers.length).assertEqual(2);
      expect(doc.activeLayer).assertEqual(1);
      expect(session.activeLayer).assertEqual(1);
      const celRef = doc.cells[0][1];
      session.undo();
      expect(doc.layers.length).assertEqual(1);
      expect(doc.activeLayer).assertEqual(0);
      expect(session.canRedo).assertTrue();
      session.redo();
      expect(doc.layers.length).assertEqual(2);
      expect(doc.activeLayer).assertEqual(1);
      // 结构撤销不替换 cel 缓冲对象（引用稳定）。
      expect(doc.cells[0][1] === celRef).assertTrue();
    });

    it('DocOps_add_layer_cap_returns_false', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      for (let i = 1; i < MAX_LAYERS; i++) {
        DocOps.addLayer(doc, session, `L${i}`);
      }
      expect(DocOps.addLayer(doc, session, 'L9')).assertFalse();
      expect(doc.layers.length).assertEqual(MAX_LAYERS);
      expect(session.canUndo).assertTrue();
    });

    it('DocOps_delete_layer_content_preserved', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      DocOps.addLayer(doc, session, 'Layer 2');
      doc.getCell(0, 0)!.setPx(1, 1, RED);
      doc.getCell(0, 1)!.setPx(2, 2, BLUE);
      const topCel = doc.cells[0][1];
      expect(DocOps.deleteLayer(doc, session, 1)).assertTrue();
      expect(doc.layers.length).assertEqual(1);
      session.undo();
      expect(doc.layers.length).assertEqual(2);
      expect(doc.cells[0][1] === topCel).assertTrue();
      expect(doc.cells[0][1].getPx(2, 2)).assertEqual(BLUE);
      expect(doc.cells[0][0].getPx(1, 1)).assertEqual(RED);
    });

    it('DocOps_delete_last_layer_refused', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      expect(DocOps.deleteLayer(doc, session, 0)).assertFalse();
      expect(session.canUndo).assertFalse();
    });

    it('DocOps_move_layer_compose_roundtrip', 0, () => {
      const doc = new PixelDoc(2, 2);
      const session = new EditorSession();
      DocOps.addLayer(doc, session, 'Layer 2');
      const bottom = doc.getCell(0, 0)!;
      const top = doc.getCell(0, 1)!;
      for (let y = 0; y < 2; y++) {
        for (let x = 0; x < 2; x++) {
          bottom.setPx(x, y, RED);
        }
      }
      top.setPx(0, 0, BLUE);
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(BLUE);
      // 顶层下移到底 → 红色覆盖蓝色。
      expect(DocOps.moveLayer(doc, session, 1, -1)).assertTrue();
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(RED);
      session.undo();
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(BLUE);
      session.redo();
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(RED);
    });

    it('DocOps_visibility_undo_redo', 0, () => {
      const doc = new PixelDoc(2, 2);
      const session = new EditorSession();
      DocOps.addLayer(doc, session, 'Layer 2');
      doc.getCell(0, 1)!.setPx(0, 0, BLUE);
      expect(DocOps.setLayerVisible(doc, session, 1, false)).assertTrue();
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(0);
      session.undo();
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(BLUE);
      session.redo();
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(0);
    });

    it('DocOps_opacity_set_and_undo', 0, () => {
      const doc = new PixelDoc(2, 2);
      const session = new EditorSession();
      DocOps.addLayer(doc, session, 'Layer 2');
      for (let y = 0; y < 2; y++) {
        for (let x = 0; x < 2; x++) {
          doc.getCell(0, 0)!.setPx(x, y, RED);
        }
      }
      doc.getCell(0, 1)!.setPx(0, 0, BLUE);
      expect(DocOps.setLayerOpacity(doc, session, 1, 50)).assertTrue();
      const blended = argbAt(composeTo(doc), 2, 0, 0);
      expect(blended !== BLUE).assertTrue();
      expect(blended !== RED).assertTrue();
      expect((blended >>> 24) & 0xFF).assertEqual(255);
      session.undo();
      expect(argbAt(composeTo(doc), 2, 0, 0)).assertEqual(BLUE);
    });

    it('DocOps_opacity_clamped', 0, () => {
      const doc = new PixelDoc(2, 2);
      const session = new EditorSession();
      DocOps.setLayerOpacity(doc, session, 0, 150);
      expect(doc.layers[0].opacity).assertEqual(100);
      DocOps.setLayerOpacity(doc, session, 0, -5);
      expect(doc.layers[0].opacity).assertEqual(0);
    });

    it('DocOps_rename_undo_redo', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      expect(DocOps.renameLayer(doc, session, 0, '背景')).assertTrue();
      expect(doc.layers[0].name).assertEqual('背景');
      session.undo();
      expect(doc.layers[0].name).assertEqual('Layer 1');
      session.redo();
      expect(doc.layers[0].name).assertEqual('背景');
      expect(DocOps.renameLayer(doc, session, 0, '   ')).assertFalse();
      expect(doc.layers[0].name).assertEqual('背景');
    });

    it('DocOps_active_layer_sync', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      DocOps.addLayer(doc, session, 'Layer 2');
      DocOps.setActiveLayer(doc, session, 0);
      expect(doc.activeLayer).assertEqual(0);
      expect(session.activeLayer).assertEqual(0);
      DocOps.setActiveLayer(doc, session, 1);
      expect(doc.activeLayer).assertEqual(1);
      expect(session.activeLayer).assertEqual(1);
    });

    it('DocOps_mixed_stack_lifo_order', 0, () => {
      const doc = new PixelDoc(2, 2);
      const session = new EditorSession();
      DocOps.addLayer(doc, session, 'Layer 2');
      doc.getCell(0, 1)!.setPx(0, 0, BLUE);
      // ① 像素类：底层画红点。
      const cel = doc.getCell(0, 0)!;
      const before = cel.data.slice();
      Raster.stamp(cel, 1, 1, 1, RED, false);
      const entry = UndoStack.entryIfChanged(cel.data, before);
      expect(entry !== undefined).assertTrue();
      session.undoStack.push(entry!);
      session.syncUndoFlags();
      // ② 结构类：隐藏顶层。
      DocOps.setLayerVisible(doc, session, 1, false);
      // LIFO：先撤销②（顶层恢复可见，红点仍在），再撤销①（红点消失）。
      session.undo();
      let out = composeTo(doc);
      expect(argbAt(out, 2, 0, 0)).assertEqual(BLUE);
      expect(argbAt(out, 2, 1, 1)).assertEqual(RED);
      session.undo();
      out = composeTo(doc);
      expect(argbAt(out, 2, 0, 0)).assertEqual(BLUE);
      expect(argbAt(out, 2, 1, 1)).assertEqual(0);
    });

    // ---------- 选区：内容操作 ----------

    it('Selection_copy_flags_floating_duplicate', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      const cel = doc.activeCell()!;
      for (let y = 1; y <= 2; y++) {
        for (let x = 1; x <= 2; x++) {
          cel.setPx(x, y, RED);
        }
      }
      session.sel = new SelRect(1, 1, 2, 2);
      expect(DocOps.copySelection(doc, session)).assertTrue();
      expect(session.selCopied).assertTrue();
      // 重复复制幂等；复制本身不写像素、不入撤销栈。
      expect(DocOps.copySelection(doc, session)).assertTrue();
      expect(countOpaque(cel)).assertEqual(4);
      expect(session.canUndo).assertFalse();
      DocOps.cancelSelection(session);
      expect(session.selCopied).assertFalse();
    });

    it('Selection_copy_empty_region_noop', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      session.sel = new SelRect(0, 0, 2, 2);
      expect(DocOps.copySelection(doc, session)).assertFalse();
      expect(session.selCopied).assertFalse();
      expect(session.canUndo).assertFalse();
      expect(session.sel !== undefined).assertTrue();
    });

    it('Selection_delete_clears_region', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      const cel = doc.activeCell()!;
      for (let y = 1; y <= 2; y++) {
        for (let x = 1; x <= 2; x++) {
          cel.setPx(x, y, GREEN);
        }
      }
      session.sel = new SelRect(1, 1, 2, 2);
      expect(DocOps.deleteSelection(doc, session)).assertTrue();
      expect(countOpaque(cel)).assertEqual(0);
      expect(session.sel).assertUndefined();
      session.undo();
      expect(countOpaque(cel)).assertEqual(4);
    });

    it('Selection_delete_partial_region', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      const cel = doc.activeCell()!;
      for (let y = 1; y <= 2; y++) {
        for (let x = 1; x <= 2; x++) {
          cel.setPx(x, y, BLACK);
        }
      }
      session.sel = new SelRect(1, 1, 1, 1);
      expect(DocOps.deleteSelection(doc, session)).assertTrue();
      expect(cel.getPx(1, 1)).assertEqual(0);
      expect(countOpaque(cel)).assertEqual(3);
    });

    it('Selection_cancel_no_stack_change', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      const tickBefore = session.tick;
      session.sel = new SelRect(0, 0, 2, 2);
      DocOps.cancelSelection(session);
      expect(session.sel).assertUndefined();
      expect(session.canUndo).assertFalse();
      expect(session.tick).assertEqual(tickBefore);
    });

    it('Selection_delete_sets_dirty_and_tick', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      const cel = doc.activeCell()!;
      for (let y = 1; y <= 2; y++) {
        for (let x = 1; x <= 2; x++) {
          cel.setPx(x, y, GREEN);
        }
      }
      session.sel = new SelRect(1, 1, 2, 2);
      const tickBefore = session.tick;
      expect(DocOps.deleteSelection(doc, session)).assertTrue();
      expect(session.dirty).assertTrue();
      expect(session.tick > tickBefore).assertTrue();
      expect(countOpaque(cel)).assertEqual(0);
    });

    // ---------- PixelDoc 帧模型（M3） ----------

    it('PixelDoc_insert_frame_row_validation', 0, () => {
      const doc = new PixelDoc(4, 4);
      const row: PixelBuffer[] = [new PixelBuffer(4, 4)];
      expect(doc.insertFrame(1, row)).assertTrue();
      expect(doc.frameCount).assertEqual(2);
      // 行长度必须等于层数；index 越界拒绝。
      expect(doc.insertFrame(0, [])).assertFalse();
      expect(doc.insertFrame(-1, row)).assertFalse();
      expect(doc.insertFrame(3, row)).assertFalse();
      expect(doc.frameCount).assertEqual(2);
    });

    it('PixelDoc_remove_frame_refused_single', 0, () => {
      const doc = new PixelDoc(4, 4);
      expect(doc.removeFrame(0)).assertFalse();
      expect(doc.frameCount).assertEqual(1);
    });

    it('PixelDoc_remove_frame_clamps_active', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.addFrame();
      doc.addFrame();
      doc.activeFrame = 2;
      expect(doc.removeFrame(1)).assertTrue();
      expect(doc.frameCount).assertEqual(2);
      expect(doc.activeFrame).assertEqual(1);
    });

    it('PixelDoc_swap_frame_active_follows', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.addFrame();
      doc.addFrame();
      doc.activeFrame = 1;
      const mid = doc.cells[1];
      expect(doc.swapFrame(1, 1)).assertTrue();
      expect(doc.cells[2] === mid).assertTrue();
      expect(doc.activeFrame).assertEqual(2);
      expect(doc.swapFrame(2, 1)).assertFalse();
      expect(doc.swapFrame(0, -1)).assertFalse();
    });

    // ---------- DocOps：帧操作与撤销（M3） ----------

    it('DocOps_add_frame_undo_redo', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      expect(DocOps.addFrame(doc, session)).assertTrue();
      const row = doc.cells[1];
      expect(doc.frameCount).assertEqual(2);
      expect(doc.activeFrame).assertEqual(1);
      expect(session.activeFrame).assertEqual(1);
      session.undo();
      expect(doc.frameCount).assertEqual(1);
      expect(doc.activeFrame).assertEqual(0);
      expect(session.activeFrame).assertEqual(0);
      session.redo();
      expect(doc.frameCount).assertEqual(2);
      // 帧撤销闭包捕获行引用：cel 缓冲只原位写入，引用跨撤销稳定。
      expect(doc.cells[1] === row).assertTrue();
    });

    it('DocOps_duplicate_frame_content_independent', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      doc.getCell(0, 0)!.setPx(0, 0, RED);
      expect(DocOps.duplicateFrame(doc, session, 0)).assertTrue();
      expect(doc.frameCount).assertEqual(2);
      expect(doc.activeFrame).assertEqual(1);
      // 副本内容与原件一致但缓冲独立：改原件不影响副本。
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(RED);
      doc.cells[0][0].setPx(0, 0, BLUE);
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(RED);
      session.undo();
      expect(doc.frameCount).assertEqual(1);
      session.redo();
      expect(doc.frameCount).assertEqual(2);
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(RED);
    });

    it('DocOps_delete_frame_undo_restores_order', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      DocOps.addFrame(doc, session);
      DocOps.addFrame(doc, session);
      DocOps.setActiveFrame(doc, session, 0);
      doc.getCell(0, 0)!.setPx(0, 0, RED);
      DocOps.setActiveFrame(doc, session, 1);
      doc.getCell(1, 0)!.setPx(0, 0, GREEN);
      DocOps.setActiveFrame(doc, session, 2);
      doc.getCell(2, 0)!.setPx(0, 0, BLUE);
      // 删除中间帧（GREEN）。
      expect(DocOps.deleteFrame(doc, session, 1)).assertTrue();
      expect(doc.frameCount).assertEqual(2);
      expect(doc.cells[0][0].getPx(0, 0)).assertEqual(RED);
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(BLUE);
      session.undo();
      expect(doc.frameCount).assertEqual(3);
      expect(doc.cells[0][0].getPx(0, 0)).assertEqual(RED);
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(GREEN);
      expect(doc.cells[2][0].getPx(0, 0)).assertEqual(BLUE);
      session.redo();
      expect(doc.frameCount).assertEqual(2);
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(BLUE);
    });

    it('DocOps_delete_frame_refused_single', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      expect(DocOps.deleteFrame(doc, session, 0)).assertFalse();
      expect(session.canUndo).assertFalse();
    });

    it('DocOps_move_frame_undo_redo', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      DocOps.addFrame(doc, session);
      DocOps.addFrame(doc, session);
      DocOps.setActiveFrame(doc, session, 0);
      doc.getCell(0, 0)!.setPx(0, 0, RED);
      DocOps.setActiveFrame(doc, session, 1);
      doc.getCell(1, 0)!.setPx(0, 0, GREEN);
      DocOps.setActiveFrame(doc, session, 2);
      doc.getCell(2, 0)!.setPx(0, 0, BLUE);
      // [R,G,B] → 帧 1 右移 → [R,B,G]；活动帧（原 2=BLUE）随内容跟到 1。
      expect(DocOps.moveFrame(doc, session, 1, 1)).assertTrue();
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(BLUE);
      expect(doc.cells[2][0].getPx(0, 0)).assertEqual(GREEN);
      expect(doc.activeFrame).assertEqual(1);
      expect(session.activeFrame).assertEqual(1);
      session.undo();
      expect(doc.cells[0][0].getPx(0, 0)).assertEqual(RED);
      expect(doc.cells[1][0].getPx(0, 0)).assertEqual(GREEN);
      expect(doc.cells[2][0].getPx(0, 0)).assertEqual(BLUE);
      // 撤销后活动帧恢复到操作前（2=BLUE）。
      expect(doc.activeFrame).assertEqual(2);
      // 越界移动拒绝。
      expect(DocOps.moveFrame(doc, session, 0, -1)).assertFalse();
      expect(DocOps.moveFrame(doc, session, 2, 1)).assertFalse();
    });

    it('DocOps_set_active_frame_no_undo', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      DocOps.addFrame(doc, session);
      // 切帧成功且不入撤销栈、不置脏：仅 tick 驱动重渲染。
      const tickBefore = session.tick;
      expect(DocOps.setActiveFrame(doc, session, 1)).assertTrue();
      expect(doc.activeFrame).assertEqual(1);
      expect(session.activeFrame).assertEqual(1);
      expect(session.tick).assertEqual(tickBefore + 1);
      expect(DocOps.setActiveFrame(doc, session, 0)).assertTrue();
      // 撤销栈中仅 addFrame 一条：一次 undo 即回单帧。
      session.undo();
      expect(doc.frameCount).assertEqual(1);
      expect(doc.activeFrame).assertEqual(0);
      expect(session.canUndo).assertFalse();
      expect(DocOps.setActiveFrame(doc, session, 5)).assertFalse();
    });

    it('DocOps_frame_ops_stop_playing', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      session.playing = true;
      expect(DocOps.addFrame(doc, session)).assertTrue();
      expect(session.playing).assertFalse();
      session.playing = true;
      expect(DocOps.duplicateFrame(doc, session, 0)).assertTrue();
      expect(session.playing).assertFalse();
      session.playing = true;
      expect(DocOps.deleteFrame(doc, session, 1)).assertTrue();
      expect(session.playing).assertFalse();
      session.playing = true;
      expect(DocOps.moveFrame(doc, session, 0, 1)).assertTrue();
      expect(session.playing).assertFalse();
      session.playing = true;
      expect(DocOps.setActiveFrame(doc, session, 0)).assertTrue();
      expect(session.playing).assertFalse();
    });

    it('DocOps_session_undo_redo_stop_playing', 0, () => {
      const doc = new PixelDoc(4, 4);
      const session = new EditorSession();
      DocOps.addFrame(doc, session);
      session.playing = true;
      session.undo();
      expect(session.playing).assertFalse();
      session.playing = true;
      session.redo();
      expect(session.playing).assertFalse();
    });
  });
}
