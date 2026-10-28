/**
 * pixelCoreTest — 核心纯逻辑套件（M0 批次）：PixelBuffer / PixelDoc / Raster / Compose。
 * 运行协议（模拟器 class 过滤）：
 *   hdc shell aa test -b com.ddabb.pixelstudio -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class pixelCoreTest -s timeout 15000
 */

import { describe, it, expect } from '@ohos/hypium';
import { PixelBuffer } from '../../../main/ets/core/PixelBuffer';
import { PixelDoc } from '../../../main/ets/core/PixelDoc';
import { Raster } from '../../../main/ets/core/Raster';
import { Compose } from '../../../main/ets/core/Compose';
import { FloodFill } from '../../../main/ets/core/FloodFill';
import { UndoStack } from '../../../main/ets/core/UndoStack';
import { GestureTracker, GestureSink } from '../../../main/ets/core/GestureTracker';
import { ColorUtil } from '../../../main/ets/core/ColorUtil';
import { Palettes, BeadColor } from '../../../main/ets/core/Palettes';
import { BeadQuantize } from '../../../main/ets/core/BeadQuantize';

class RecordingSink implements GestureSink {
  log: string[] = [];

  onStrokeBegin(x: number, y: number): void {
    this.log.push(`b:${x},${y}`);
  }

  onStrokeMove(x: number, y: number): void {
    this.log.push(`m:${x},${y}`);
  }

  onStrokeEnd(x: number, y: number): void {
    this.log.push(`e:${x},${y}`);
  }

  onStrokeRollback(): void {
    this.log.push('rb');
  }

  onGestureStart(): void {
    this.log.push('gs');
  }

  onGestureMove(fx: number, fy: number, tx: number, ty: number, zf: number): void {
    this.log.push(`gm:${fx},${fy},${tx},${ty},${zf.toFixed(2)}`);
  }

  onGestureEnd(): void {
    this.log.push('ge');
  }
}

const BLACK = 0xFF000000;
const RED = 0xFFFF0000;
const GREEN = 0xFF00FF00;
const BLUE = 0xFF0000FF;
const WHITE = 0xFFFFFFFF;

function countOpaque(buf: PixelBuffer): number {
  let n = 0;
  for (let i = 3; i < buf.data.length; i += 4) {
    if (buf.data[i] > 0) {
      n++;
    }
  }
  return n;
}

export default function pixelCoreTest() {
  describe('pixelCoreTest', () => {
    // ---------- PixelBuffer ----------
    it('PixelBuffer_set_get_roundtrip', 0, () => {
      const buf = new PixelBuffer(4, 4);
      buf.setPx(1, 2, GREEN);
      expect(buf.getPx(1, 2)).assertEqual(GREEN);
      buf.setPx(0, 0, WHITE);
      expect(buf.getPx(0, 0)).assertEqual(WHITE);
      expect(buf.getPx(3, 3)).assertEqual(0);
    });

    it('PixelBuffer_out_of_bounds_safety', 0, () => {
      const buf = new PixelBuffer(4, 4);
      buf.setPx(-1, 0, RED);
      buf.setPx(0, -1, RED);
      buf.setPx(4, 0, RED);
      buf.setPx(0, 4, RED);
      expect(countOpaque(buf)).assertEqual(0);
      expect(buf.getPx(-1, 0)).assertEqual(0);
      expect(buf.getPx(4, 4)).assertEqual(0);
    });

    it('PixelBuffer_clone_independent', 0, () => {
      const buf = new PixelBuffer(4, 4);
      buf.setPx(2, 2, RED);
      const copy = buf.clone();
      copy.setPx(0, 0, BLUE);
      expect(buf.getPx(0, 0)).assertEqual(0);
      expect(buf.getPx(2, 2)).assertEqual(RED);
      expect(copy.getPx(2, 2)).assertEqual(RED);
      expect(copy.getPx(0, 0)).assertEqual(BLUE);
    });

    it('PixelBuffer_clear', 0, () => {
      const buf = new PixelBuffer(4, 4);
      buf.setPx(1, 1, RED);
      buf.setPx(2, 2, GREEN);
      buf.clear();
      expect(countOpaque(buf)).assertEqual(0);
    });

    it('PixelBuffer_copy_region_clip', 0, () => {
      const buf = new PixelBuffer(4, 4);
      buf.setPx(2, 2, RED);
      buf.setPx(3, 2, GREEN);
      // 请求 (2,2) 起 4x2 区域，右缘越界裁剪。
      const region = buf.copyRegion(2, 2, 4, 2);
      expect(region.w).assertEqual(4);
      expect(region.h).assertEqual(2);
      expect(region.getPx(0, 0)).assertEqual(RED);
      expect(region.getPx(1, 0)).assertEqual(GREEN);
      expect(region.getPx(2, 0)).assertEqual(0);
      expect(region.getPx(3, 0)).assertEqual(0);
    });

    it('PixelBuffer_blit_clip', 0, () => {
      const src = new PixelBuffer(2, 2);
      src.setPx(0, 0, RED);
      src.setPx(1, 1, GREEN);
      const dst = new PixelBuffer(4, 4);
      // 落在 (3,3)，src 1x1 处越界 → 只剩 (0,0) 一个像素可见。
      dst.blit(src, 3, 3);
      expect(dst.getPx(3, 3)).assertEqual(RED);
      expect(countOpaque(dst)).assertEqual(1);
    });

    it('PixelBuffer_fromData_size_guard', 0, () => {
      let thrown = false;
      try {
        PixelBuffer.fromData(4, 4, new Uint8Array(8));
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });

    // ---------- PixelDoc ----------
    it('PixelDoc_init_shape', 0, () => {
      const doc = new PixelDoc(8, 8);
      expect(doc.w).assertEqual(8);
      expect(doc.h).assertEqual(8);
      expect(doc.layers.length).assertEqual(1);
      expect(doc.frameCount).assertEqual(1);
      expect(doc.cells[0].length).assertEqual(1);
      expect(doc.cells[0][0].w).assertEqual(8);
      expect(doc.cells[0][0].h).assertEqual(8);
      expect(doc.activeCell() !== undefined).assertTrue();
    });

    it('PixelDoc_add_layer', 0, () => {
      const doc = new PixelDoc(8, 8);
      doc.addLayer('Layer 2');
      expect(doc.layers.length).assertEqual(2);
      expect(doc.layers[1].name).assertEqual('Layer 2');
      expect(doc.layers[1].visible).assertTrue();
      expect(doc.layers[1].opacity).assertEqual(100);
      expect(doc.cells[0].length).assertEqual(2);
      expect(doc.getCell(0, 1) !== undefined).assertTrue();
    });

    it('PixelDoc_add_frame', 0, () => {
      const doc = new PixelDoc(8, 8);
      doc.addLayer('Layer 2');
      doc.addFrame();
      expect(doc.frameCount).assertEqual(2);
      expect(doc.cells[1].length).assertEqual(2);
      expect(doc.getCell(1, 0) !== undefined).assertTrue();
      expect(doc.getCell(1, 1) !== undefined).assertTrue();
    });

    it('PixelDoc_get_cell_bounds', 0, () => {
      const doc = new PixelDoc(8, 8);
      expect(doc.getCell(-1, 0)).assertUndefined();
      expect(doc.getCell(0, -1)).assertUndefined();
      expect(doc.getCell(1, 0)).assertUndefined();
      expect(doc.getCell(0, 1)).assertUndefined();
    });

    // ---------- Raster ----------
    it('Raster_stamp_size1', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.stamp(buf, 3, 4, 1, RED, false);
      expect(countOpaque(buf)).assertEqual(1);
      expect(buf.getPx(3, 4)).assertEqual(RED);
    });

    it('Raster_stamp_size2', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.stamp(buf, 2, 2, 2, RED, false);
      expect(buf.getPx(2, 2)).assertEqual(RED);
      expect(buf.getPx(3, 2)).assertEqual(RED);
      expect(buf.getPx(2, 3)).assertEqual(RED);
      expect(buf.getPx(3, 3)).assertEqual(RED);
      expect(countOpaque(buf)).assertEqual(4);
    });

    it('Raster_stamp_size3_centered', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.stamp(buf, 2, 2, 3, RED, false);
      expect(buf.getPx(1, 1)).assertEqual(RED);
      expect(buf.getPx(3, 3)).assertEqual(RED);
      expect(buf.getPx(2, 2)).assertEqual(RED);
      expect(buf.getPx(0, 2)).assertEqual(0);
      expect(buf.getPx(4, 2)).assertEqual(0);
      expect(countOpaque(buf)).assertEqual(9);
    });

    it('Raster_stamp_mirror_x', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.stamp(buf, 1, 1, 1, RED, true);
      expect(buf.getPx(1, 1)).assertEqual(RED);
      expect(buf.getPx(6, 1)).assertEqual(RED);
      expect(countOpaque(buf)).assertEqual(2);
    });

    it('Raster_line_horizontal', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.drawLine(buf, 1, 2, 4, 2, 1, BLACK, false);
      for (let x = 1; x <= 4; x++) {
        expect(buf.getPx(x, 2)).assertEqual(BLACK);
      }
      expect(countOpaque(buf)).assertEqual(4);
    });

    it('Raster_line_vertical', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.drawLine(buf, 3, 1, 3, 5, 1, BLACK, false);
      for (let y = 1; y <= 5; y++) {
        expect(buf.getPx(3, y)).assertEqual(BLACK);
      }
      expect(countOpaque(buf)).assertEqual(5);
    });

    it('Raster_line_diagonal_golden', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.drawLine(buf, 0, 0, 3, 3, 1, BLACK, false);
      for (let i = 0; i <= 3; i++) {
        expect(buf.getPx(i, i)).assertEqual(BLACK);
      }
      expect(countOpaque(buf)).assertEqual(4);
    });

    it('Raster_line_l_shape_golden', 0, () => {
      // Bresenham (0,0)->(3,1)：期望点集 (0,0)(1,0)(2,1)(3,1)，非对角点不着色。
      const buf = new PixelBuffer(8, 8);
      Raster.drawLine(buf, 0, 0, 3, 1, 1, BLACK, false);
      expect(buf.getPx(0, 0)).assertEqual(BLACK);
      expect(buf.getPx(1, 0)).assertEqual(BLACK);
      expect(buf.getPx(2, 1)).assertEqual(BLACK);
      expect(buf.getPx(3, 1)).assertEqual(BLACK);
      expect(buf.getPx(1, 1)).assertEqual(0);
      expect(buf.getPx(2, 0)).assertEqual(0);
      expect(countOpaque(buf)).assertEqual(4);
    });

    it('Raster_line_mirror_x', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.drawLine(buf, 0, 0, 3, 3, 1, RED, true);
      expect(buf.getPx(7, 0)).assertEqual(RED);
      expect(buf.getPx(4, 3)).assertEqual(RED);
      expect(countOpaque(buf)).assertEqual(8);
    });

    // ---------- Compose ----------
    it('Compose_single_layer_opaque', 0, () => {
      const doc = new PixelDoc(4, 4);
      const cell = doc.cells[0][0];
      cell.setPx(1, 1, RED);
      const out = new Uint8Array(4 * 4 * 4);
      Compose.composeFrame(doc, 0, out);
      const view = new PixelBuffer(4, 4);
      for (let i = 0; i < out.length; i++) {
        view.data[i] = out[i];
      }
      expect(view.getPx(1, 1)).assertEqual(RED);
      expect(view.getPx(0, 0)).assertEqual(0);
    });

    it('Compose_layer_opacity_50', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.layers[0].opacity = 50;
      const cell = doc.cells[0][0];
      cell.setPx(0, 0, RED);
      const out = new Uint8Array(4 * 4 * 4);
      Compose.composeFrame(doc, 0, out);
      // 红色 50% 落在透明底上：RGB 不变，alpha≈128。
      expect(out[0]).assertEqual(255);
      expect(out[1]).assertEqual(0);
      expect(out[2]).assertEqual(0);
      expect(out[3]).assertEqual(128);
    });

    it('Compose_invisible_layer_skipped', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.layers[0].visible = false;
      doc.cells[0][0].setPx(0, 0, RED);
      const out = new Uint8Array(4 * 4 * 4);
      Compose.composeFrame(doc, 0, out);
      expect(out[3]).assertEqual(0);
    });

    it('Compose_two_layer_blend', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.cells[0][0].setPx(0, 0, RED);
      doc.addLayer('Layer 2');
      doc.layers[1].opacity = 50;
      doc.cells[0][1].setPx(0, 0, BLUE);
      const out = new Uint8Array(4 * 4 * 4);
      Compose.composeFrame(doc, 0, out);
      // 50% 蓝叠在不透明红上：(127, 0, 128, 255)。
      expect(out[0]).assertEqual(127);
      expect(out[1]).assertEqual(0);
      expect(out[2]).assertEqual(128);
      expect(out[3]).assertEqual(255);
    });

    it('Compose_buffer_reuse_second_pass', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.cells[0][0].setPx(0, 0, RED);
      const out = new Uint8Array(4 * 4 * 4);
      Compose.composeFrame(doc, 0, out);
      expect(out[3]).assertEqual(255);
      // 第二遍复用同一缓冲：残留被清零，仅新内容存在。
      doc.cells[0][0].clear();
      doc.cells[0][0].setPx(2, 2, GREEN);
      Compose.composeFrame(doc, 0, out);
      expect(out[3]).assertEqual(0);
      expect(out[(2 * 4 + 2) * 4 + 1]).assertEqual(255);
      expect(out[(2 * 4 + 2) * 4 + 3]).assertEqual(255);
    });

    // ---------- Raster：矩形/椭圆（M1） ----------
    it('Raster_rect_outline_golden', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.strokeRect(buf, 0, 0, 3, 2, 1, BLACK, false, false);
      for (let x = 0; x <= 3; x++) {
        expect(buf.getPx(x, 0)).assertEqual(BLACK);
        expect(buf.getPx(x, 2)).assertEqual(BLACK);
      }
      expect(buf.getPx(0, 1)).assertEqual(BLACK);
      expect(buf.getPx(3, 1)).assertEqual(BLACK);
      expect(buf.getPx(1, 1)).assertEqual(0);
      expect(buf.getPx(2, 1)).assertEqual(0);
      expect(countOpaque(buf)).assertEqual(10);
    });

    it('Raster_rect_filled_golden', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.strokeRect(buf, 1, 1, 3, 2, 1, RED, false, true);
      for (let y = 1; y <= 2; y++) {
        for (let x = 1; x <= 3; x++) {
          expect(buf.getPx(x, y)).assertEqual(RED);
        }
      }
      expect(countOpaque(buf)).assertEqual(6);
    });

    it('Raster_rect_coords_normalized', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.strokeRect(buf, 3, 2, 0, 0, 1, BLACK, false, false);
      expect(buf.getPx(0, 0)).assertEqual(BLACK);
      expect(buf.getPx(3, 2)).assertEqual(BLACK);
      expect(countOpaque(buf)).assertEqual(10);
    });

    it('Raster_rect_filled_mirror', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.strokeRect(buf, 1, 1, 2, 2, 1, RED, true, true);
      for (let y = 1; y <= 2; y++) {
        for (let x = 1; x <= 2; x++) {
          expect(buf.getPx(x, y)).assertEqual(RED);
          expect(buf.getPx(7 - x, y)).assertEqual(RED);
        }
      }
      expect(countOpaque(buf)).assertEqual(8);
    });

    it('Raster_ellipse_outline_golden', 0, () => {
      // bbox (0,0)-(4,2)：cx=2 cy=1 rx=2 ry=1 → 弧点 8 个。
      const buf = new PixelBuffer(8, 8);
      Raster.strokeEllipse(buf, 0, 0, 4, 2, 1, BLACK, false, false);
      const arc: number[] = [2, 0, 1, 0, 3, 0, 0, 1, 4, 1, 1, 2, 2, 2, 3, 2];
      for (let i = 0; i < arc.length; i += 2) {
        expect(buf.getPx(arc[i], arc[i + 1])).assertEqual(BLACK);
      }
      expect(countOpaque(buf)).assertEqual(8);
    });

    it('Raster_ellipse_filled_golden', 0, () => {
      const buf = new PixelBuffer(8, 8);
      Raster.strokeEllipse(buf, 0, 0, 4, 2, 1, BLACK, false, true);
      for (let x = 1; x <= 3; x++) {
        expect(buf.getPx(x, 0)).assertEqual(BLACK);
        expect(buf.getPx(x, 2)).assertEqual(BLACK);
      }
      for (let x = 0; x <= 4; x++) {
        expect(buf.getPx(x, 1)).assertEqual(BLACK);
      }
      expect(countOpaque(buf)).assertEqual(11);
    });

    it('Raster_ellipse_degenerate_line', 0, () => {
      // rx=0（宽 1）→ 退化为竖线。
      const buf = new PixelBuffer(8, 8);
      Raster.strokeEllipse(buf, 2, 0, 2, 3, 1, BLACK, false, false);
      for (let y = 0; y <= 3; y++) {
        expect(buf.getPx(2, y)).assertEqual(BLACK);
      }
      expect(countOpaque(buf)).assertEqual(4);
    });

    it('Raster_ellipse_center_symmetry', 0, () => {
      const buf = new PixelBuffer(9, 9);
      Raster.strokeEllipse(buf, 0, 0, 8, 8, 1, BLACK, false, false);
      let n = 0;
      for (let y = 0; y < 9; y++) {
        for (let x = 0; x < 9; x++) {
          if (buf.getPx(x, y) === BLACK) {
            expect(buf.getPx(8 - x, 8 - y)).assertEqual(BLACK);
            n++;
          }
        }
      }
      expect(n > 0).assertTrue();
    });

    // ---------- FloodFill（M1） ----------
    it('FloodFill_full_canvas', 0, () => {
      const buf = new PixelBuffer(6, 4);
      expect(FloodFill.fill(buf, 0, 0, RED)).assertTrue();
      expect(countOpaque(buf)).assertEqual(24);
      expect(buf.getPx(5, 3)).assertEqual(RED);
    });

    it('FloodFill_ring_unreachable', 0, () => {
      const buf = new PixelBuffer(7, 7);
      for (let a = -2; a <= 2; a++) {
        buf.setPx(3 + a, 1, BLACK);
        buf.setPx(3 + a, 5, BLACK);
        buf.setPx(1, 3 + a, BLACK);
        buf.setPx(5, 3 + a, BLACK);
      }
      expect(FloodFill.fill(buf, 0, 0, RED)).assertTrue();
      expect(buf.getPx(0, 0)).assertEqual(RED);
      expect(buf.getPx(6, 6)).assertEqual(RED);
      expect(buf.getPx(3, 1)).assertEqual(BLACK);
      expect(buf.getPx(3, 3)).assertEqual(0);
    });

    it('FloodFill_diagonal_not_connected', 0, () => {
      // 仅对角相邻不算连通（4 连通）。
      const buf = new PixelBuffer(2, 2);
      buf.setPx(1, 0, BLACK);
      buf.setPx(0, 1, BLACK);
      FloodFill.fill(buf, 0, 0, RED);
      expect(buf.getPx(0, 0)).assertEqual(RED);
      expect(buf.getPx(1, 1)).assertEqual(0);
    });

    it('FloodFill_same_color_noop', 0, () => {
      const buf = new PixelBuffer(4, 4);
      expect(FloodFill.fill(buf, 0, 0, 0x00000000)).assertFalse();
      expect(countOpaque(buf)).assertEqual(0);
    });

    it('FloodFill_out_of_bounds', 0, () => {
      const buf = new PixelBuffer(4, 4);
      expect(FloodFill.fill(buf, -1, 0, RED)).assertFalse();
      expect(FloodFill.fill(buf, 0, 4, RED)).assertFalse();
    });

    it('FloodFill_exact_alpha_match', 0, () => {
      const buf = new PixelBuffer(4, 2);
      buf.setPx(0, 0, 0x80FF0000);
      buf.setPx(1, 0, 0x80FF0000);
      buf.setPx(2, 0, 0xFFFF0000);
      FloodFill.fill(buf, 0, 0, GREEN);
      expect(buf.getPx(0, 0)).assertEqual(GREEN);
      expect(buf.getPx(1, 0)).assertEqual(GREEN);
      expect(buf.getPx(2, 0)).assertEqual(0xFFFF0000);
      expect(buf.getPx(0, 1)).assertEqual(0);
    });

    it('FloodFill_large_canvas_no_recursion', 0, () => {
      const buf = new PixelBuffer(64, 64);
      expect(FloodFill.fill(buf, 0, 0, RED)).assertTrue();
      expect(buf.getPx(63, 63)).assertEqual(RED);
    });

    // ---------- UndoStack（M1） ----------
    it('UndoStack_push_undo_redo', 0, () => {
      const cell = new Uint8Array(16);
      const stack = new UndoStack(10);
      const before = cell.slice();
      cell[0] = 2;
      cell[1] = 2;
      const entry = UndoStack.entryIfChanged(cell, before);
      if (entry === undefined) {
        expect(false).assertTrue();
        return;
      }
      stack.push(entry);
      expect(stack.canUndo()).assertTrue();
      expect(stack.canRedo()).assertFalse();
      stack.undo();
      expect(cell[0]).assertEqual(0);
      expect(cell[1]).assertEqual(0);
      expect(stack.canUndo()).assertFalse();
      expect(stack.canRedo()).assertTrue();
      stack.redo();
      expect(cell[0]).assertEqual(2);
      expect(cell[1]).assertEqual(2);
    });

    it('UndoStack_unchanged_not_pushed', 0, () => {
      const cell = new Uint8Array(16);
      cell[3] = 7;
      expect(UndoStack.entryIfChanged(cell, cell.slice())).assertUndefined();
    });

    it('UndoStack_redo_cleared_on_push', 0, () => {
      const cell = new Uint8Array(16);
      const stack = new UndoStack(10);
      let before = cell.slice();
      cell[0] = 1;
      let e = UndoStack.entryIfChanged(cell, before);
      if (e !== undefined) {
        stack.push(e);
      }
      before = cell.slice();
      cell[1] = 1;
      e = UndoStack.entryIfChanged(cell, before);
      if (e !== undefined) {
        stack.push(e);
      }
      stack.undo();
      expect(cell[1]).assertEqual(0);
      expect(stack.canRedo()).assertTrue();
      before = cell.slice();
      cell[2] = 1;
      e = UndoStack.entryIfChanged(cell, before);
      if (e !== undefined) {
        stack.push(e);
      }
      expect(stack.canRedo()).assertFalse();
      expect(cell[1]).assertEqual(0);
    });

    it('UndoStack_capacity_lru', 0, () => {
      const stack = new UndoStack(3);
      const cell = new Uint8Array(4);
      for (let i = 0; i < 4; i++) {
        const before = cell.slice();
        cell[0] = i + 1;
        const e = UndoStack.entryIfChanged(cell, before);
        if (e !== undefined) {
          stack.push(e);
        }
      }
      stack.undo();
      expect(cell[0]).assertEqual(3);
      stack.undo();
      expect(cell[0]).assertEqual(2);
      stack.undo();
      expect(cell[0]).assertEqual(1);
      expect(stack.canUndo()).assertFalse();
    });

    it('UndoStack_default_capacity_100', 0, () => {
      const stack = new UndoStack();
      const cell = new Uint8Array(4);
      for (let i = 0; i < 100; i++) {
        const before = cell.slice();
        cell[0] = i + 1;
        const e = UndoStack.entryIfChanged(cell, before);
        if (e !== undefined) {
          stack.push(e);
        }
      }
      expect(stack.canUndo()).assertTrue();
      stack.undo();
      expect(cell[0]).assertEqual(99);
    });

    it('UndoStack_snapshot_independence', 0, () => {
      const cell = new Uint8Array(8);
      const before = cell.slice();
      cell[0] = 9;
      const e = UndoStack.entryIfChanged(cell, before);
      if (e === undefined) {
        expect(false).assertTrue();
        return;
      }
      cell[0] = 5;
      e.cellData.set(e.before);
      expect(cell[0]).assertEqual(0);
      e.cellData.set(e.after);
      expect(cell[0]).assertEqual(9);
    });

    // ---------- GestureTracker（M1） ----------
    it('Gesture_single_stroke_flow', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.move(1, 20, 10);
      t.move(1, 30, 10);
      t.lift(1, 35, 10);
      expect(JSON.stringify(sink.log)).assertEqual(
        JSON.stringify(['b:10,10', 'm:20,10', 'm:30,10', 'e:35,10']));
    });

    it('Gesture_dismiss_threshold_8px', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      expect(t.isDismissed()).assertFalse();
      t.move(1, 15, 10);
      expect(t.isDismissed()).assertFalse();
      t.move(1, 19, 10);
      expect(t.isDismissed()).assertTrue();
    });

    it('Gesture_second_finger_before_dismiss_to_gesture', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.press(2, 50, 10, false);
      expect(JSON.stringify(sink.log)).assertEqual(
        JSON.stringify(['b:10,10', 'rb', 'gs']));
      t.move(2, 90, 10);
      expect(sink.log[3]).assertEqual('gm:30,10,50,10,2.00');
      t.lift(1, 10, 10);
      expect(sink.log[4]).assertEqual('ge');
      t.move(2, 100, 10);
      expect(sink.log.length).assertEqual(5);
    });

    it('Gesture_second_finger_after_dismiss_ignored', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.move(1, 40, 10);
      expect(t.isDismissed()).assertTrue();
      t.press(2, 50, 50, false);
      expect(sink.log.length).assertEqual(2);
      t.move(2, 60, 60);
      expect(sink.log.length).assertEqual(2);
      t.move(1, 45, 10);
      expect(sink.log[2]).assertEqual('m:45,10');
      t.lift(1, 50, 10);
      expect(sink.log[3]).assertEqual('e:50,10');
    });

    it('Gesture_instant_press_no_rollback', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, true);
      t.press(2, 50, 50, true);
      expect(JSON.stringify(sink.log)).assertEqual(JSON.stringify(['b:10,10']));
      t.lift(1, 12, 10);
      expect(JSON.stringify(sink.log)).assertEqual(
        JSON.stringify(['b:10,10', 'e:12,10']));
    });

    it('Gesture_lift_untracked_id_ignored', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.lift(2, 99, 99);
      expect(t.isStrokeActive()).assertTrue();
      t.lift(1, 11, 11);
      expect(JSON.stringify(sink.log)).assertEqual(
        JSON.stringify(['b:10,10', 'e:11,11']));
    });

    it('Gesture_force_rollback_before_dismiss', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.move(1, 12, 10);
      expect(t.forceRollback()).assertTrue();
      expect(sink.log[2]).assertEqual('rb');
      expect(t.isStrokeActive()).assertFalse();
      t.move(1, 30, 30);
      t.lift(1, 30, 30);
      expect(sink.log.length).assertEqual(3);
    });

    it('Gesture_force_rollback_denied_after_dismiss', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.move(1, 40, 10);
      expect(t.forceRollback()).assertFalse();
      expect(sink.log.includes('rb')).assertFalse();
      expect(t.isStrokeActive()).assertTrue();
    });

    it('Gesture_force_end_out_of_canvas', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.move(1, 20, 10);
      t.forceEnd();
      expect(JSON.stringify(sink.log)).assertEqual(
        JSON.stringify(['b:10,10', 'm:20,10', 'e:20,10']));
      expect(t.isStrokeActive()).assertFalse();
    });

    it('Gesture_third_finger_ignored_in_gesture', 0, () => {
      const sink = new RecordingSink();
      const t = new GestureTracker(sink);
      t.press(1, 10, 10, false);
      t.press(2, 50, 10, false);
      t.press(3, 30, 30, false);
      t.move(3, 40, 40);
      t.lift(3, 40, 40);
      expect(sink.log.length).assertEqual(3);
      t.move(1, 10, 20);
      expect(sink.log[3]).assertEqual('gm:30,10,30,15,1.03');
    });

    // ---------- ColorUtil（M3） ----------
    it('ColorUtil_fromHsb_primary_rgb', 0, () => {
      expect(ColorUtil.fromHsb(0, 100, 100)).assertEqual(RED);
      expect(ColorUtil.fromHsb(120, 100, 100)).assertEqual(GREEN);
      expect(ColorUtil.fromHsb(240, 100, 100)).assertEqual(BLUE);
    });

    it('ColorUtil_toHsb_primary_rgb', 0, () => {
      const r = ColorUtil.toHsb(RED);
      expect(r.h).assertEqual(0);
      expect(r.s).assertEqual(100);
      expect(r.b).assertEqual(100);
      const g = ColorUtil.toHsb(GREEN);
      expect(g.h).assertEqual(120);
      expect(g.s).assertEqual(100);
      const b = ColorUtil.toHsb(BLUE);
      expect(b.h).assertEqual(240);
      expect(b.b).assertEqual(100);
    });

    it('ColorUtil_hsb_gray_sat_zero', 0, () => {
      const hsb = ColorUtil.toHsb(0xFF808080);
      expect(hsb.s).assertEqual(0);
      expect(hsb.b).assertEqual(50);
      const black = ColorUtil.toHsb(BLACK);
      expect(black.s).assertEqual(0);
      expect(black.b).assertEqual(0);
    });

    it('ColorUtil_parseHex_valid', 0, () => {
      expect(ColorUtil.parseHex('#FF0000')).assertEqual(RED);
      expect(ColorUtil.parseHex('ff0000')).assertEqual(RED);
      expect(ColorUtil.parseHex('#00ff00')).assertEqual(GREEN);
      expect(ColorUtil.parseHex(' #FFFFFF ')).assertEqual(WHITE);
    });

    it('ColorUtil_parseHex_invalid', 0, () => {
      expect(ColorUtil.parseHex('#FFF')).assertUndefined();
      expect(ColorUtil.parseHex('#GG0000')).assertUndefined();
      expect(ColorUtil.parseHex('')).assertUndefined();
      expect(ColorUtil.parseHex('#12345')).assertUndefined();
    });

    it('ColorUtil_toHex_format', 0, () => {
      expect(ColorUtil.toHex(RED)).assertEqual('#FF0000');
      expect(ColorUtil.toHex(0xFF0A0B0C)).assertEqual('#0A0B0C');
      expect(ColorUtil.toHex(BLACK)).assertEqual('#000000');
    });

    // ---------- Palettes（M3） ----------
    it('Palettes_builtin_counts', 0, () => {
      const list = Palettes.builtinPalettes();
      expect(list.length).assertEqual(6);
      expect(list[0].colors.length).assertEqual(16);
      expect(list[1].colors.length).assertEqual(4);
      expect(list[2].colors.length).assertEqual(8);
      expect(list[3].colors.length).assertEqual(16);
      expect(list[4].colors.length).assertEqual(Palettes.PERLER.colors.length);
      expect(list[5].colors.length).assertEqual(Palettes.HAMA.colors.length);
    });

    it('Palettes_builtin_ids_unique', 0, () => {
      const list = Palettes.builtinPalettes();
      const ids: string[] = [];
      for (const p of list) {
        ids.push(p.id);
      }
      for (let i = 0; i < ids.length; i++) {
        for (let j = i + 1; j < ids.length; j++) {
          expect(ids[i] === ids[j]).assertFalse();
        }
      }
    });

    it('Palettes_bead_brand_tables', 0, () => {
      expect(Palettes.PERLER.colors.length <= 128).assertTrue();
      expect(Palettes.HAMA.colors.length <= 128).assertTrue();
      expect(Palettes.PERLER.colors.length).assertEqual(36);
      expect(Palettes.HAMA.colors.length).assertEqual(32);
      const codes: string[] = [];
      for (const c of Palettes.PERLER.colors) {
        codes.push(c.code);
      }
      for (const c of Palettes.HAMA.colors) {
        codes.push(c.code);
      }
      for (let i = 0; i < codes.length; i++) {
        for (let j = i + 1; j < codes.length; j++) {
          expect(codes[i] === codes[j]).assertFalse();
        }
      }
      expect(Palettes.beadBrand('perler') !== undefined).assertTrue();
      expect(Palettes.beadBrand('hama') !== undefined).assertTrue();
      expect(Palettes.beadBrand('nope')).assertUndefined();
    });

    // ---------- BeadQuantize（M3，§6.7） ----------
    it('BeadQuantize_exact_match', 0, () => {
      const beads = Palettes.PERLER.colors;
      // P09 红 (ED,1C,24)。
      expect(BeadQuantize.nearestIndex(0xED, 0x1C, 0x24, beads)).assertEqual(8);
    });

    it('BeadQuantize_weighted_g_dominates', 0, () => {
      const beads: BeadColor[] = [
        new BeadColor('A', 'red-ish', 'FF8080'),
        new BeadColor('B', 'green-ish', '80FF80')
      ];
      // (230,230,128) 到两色未加权等距；加权 d²=2Δr²+4Δg²+3Δb² → g 通道主导 → 选 B。
      expect(BeadQuantize.nearestIndex(230, 230, 128, beads)).assertEqual(1);
    });

    it('BeadQuantize_tie_smaller_index', 0, () => {
      const beads: BeadColor[] = [
        new BeadColor('A', 'a', 'FF0000'),
        new BeadColor('B', 'b', 'FF0000')
      ];
      expect(BeadQuantize.nearestIndex(250, 0, 0, beads)).assertEqual(0);
    });

    it('BeadQuantize_alpha_empty_peg', 0, () => {
      const beads = Palettes.PERLER.colors;
      const rgba = new Uint8Array(8);
      rgba[4] = 0xED;
      rgba[5] = 0x1C;
      rgba[6] = 0x24;
      rgba[7] = 255;
      const out = BeadQuantize.quantize(rgba, 2, 1, beads);
      expect(out[0]).assertEqual(-1);
      expect(out[1]).assertEqual(8);
    });

    it('BeadQuantize_render_preview', 0, () => {
      const beads = Palettes.PERLER.colors;
      const indices = new Int32Array([-1, 8]);
      const out = new Uint8Array(8);
      BeadQuantize.renderPreview(indices, beads, out);
      expect(out[0]).assertEqual(0);
      expect(out[3]).assertEqual(0);
      expect(out[4]).assertEqual(0xED);
      expect(out[5]).assertEqual(0x1C);
      expect(out[6]).assertEqual(0x24);
      expect(out[7]).assertEqual(255);
    });

    it('BeadQuantize_deterministic_and_readonly', 0, () => {
      const beads = Palettes.HAMA.colors;
      const rgba = new Uint8Array(64 * 4);
      for (let i = 0; i < 64; i++) {
        rgba[i * 4] = (i * 7) % 256;
        rgba[i * 4 + 1] = (i * 13) % 256;
        rgba[i * 4 + 2] = (i * 29) % 256;
        rgba[i * 4 + 3] = i % 3 === 0 ? 0 : 255;
      }
      const a = BeadQuantize.quantize(rgba, 8, 8, beads);
      const b = BeadQuantize.quantize(rgba, 8, 8, beads);
      for (let i = 0; i < a.length; i++) {
        expect(a[i]).assertEqual(b[i]);
      }
      expect(rgba[3]).assertEqual(0);
      expect(rgba[7]).assertEqual(255);
    });

    // ---------- Compose.blendOver：洋葱皮（M3） ----------
    it('Compose_blendOver_30_on_transparent', 0, () => {
      const base = new Uint8Array(4);
      const overlay = new Uint8Array([0, 0, 0, 255]);
      Compose.blendOver(base, overlay, 30);
      expect(base[0]).assertEqual(0);
      expect(base[1]).assertEqual(0);
      expect(base[2]).assertEqual(0);
      expect(base[3]).assertEqual(77);
    });

    it('Compose_blendOver_30_on_opaque', 0, () => {
      const base = new Uint8Array([255, 255, 255, 255]);
      const overlay = new Uint8Array([0, 0, 0, 255]);
      Compose.blendOver(base, overlay, 30);
      expect(base[0]).assertEqual(178);
      expect(base[1]).assertEqual(178);
      expect(base[2]).assertEqual(178);
      expect(base[3]).assertEqual(255);
    });

    it('Compose_blendOver_full_strength_equals_overlay', 0, () => {
      const base = new Uint8Array([255, 0, 0, 255]);
      const overlay = new Uint8Array([0, 0, 255, 255]);
      Compose.blendOver(base, overlay, 100);
      expect(base[0]).assertEqual(0);
      expect(base[1]).assertEqual(0);
      expect(base[2]).assertEqual(255);
      expect(base[3]).assertEqual(255);
    });

    it('Compose_blendOver_transparent_overlay_noop', 0, () => {
      const base = new Uint8Array([255, 0, 0, 255]);
      const overlay = new Uint8Array([0, 255, 0, 0]);
      Compose.blendOver(base, overlay, 30);
      expect(base[0]).assertEqual(255);
      expect(base[1]).assertEqual(0);
      expect(base[2]).assertEqual(0);
      expect(base[3]).assertEqual(255);
    });
  });
}
