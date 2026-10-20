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
  });
}
