/**
 * pixelExportTest — 导出核心套件（M4 批）：GifCodec / Resample / BeadStats / PxsFile / Font5x7 / ChartRender / SheetRender。
 * 运行协议（模拟器 class 过滤）：
 *   hdc shell aa test -b com.ddabb.pixelstudio -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class pixelExportTest -s timeout 15000
 * 验收对应（开发计划 §13.3/§13.4/§13.5）：GIF 字节级校验 + .pxs 往返 1000 次 + 拼豆清单计数/分板序号。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  GifFrameData,
  GifEncodeOptions,
  encodeGif,
  lzwEncode,
  quantizeToPalette
} from '../../../main/ets/core/GifCodec/GifEncoder';
import { Resample } from '../../../main/ets/core/Resample';
import { BeadColor } from '../../../main/ets/core/Palettes';
import { BeadStats, BEADS_PER_PACK } from '../../../main/ets/core/BeadStats';
import { PixelBuffer } from '../../../main/ets/core/PixelBuffer';
import { PxsFile, PxsMeta, PxsLayerMeta } from '../../../main/ets/core/PxsFile';
import { Font5x7 } from '../../../main/ets/core/Font5x7';
import { ChartRender, BeadChartOptions } from '../../../main/ets/core/ChartRender';
import { PixelDoc } from '../../../main/ets/core/PixelDoc';
import { SheetRender } from '../../../main/ets/core/SheetRender';

// ---------- 测试辅助：迷你 GIF 解析器（独立于编码器实现，作字节级交叉验证） ----------

class TestGifFrame {
  indices: Uint8Array = new Uint8Array(0);
  delayCs: number = 0;
  transparentIdx: number = -1;
}

class TestGifResult {
  width: number = 0;
  height: number = 0;
  loopCount: number = 1;
  palette: Uint8Array = new Uint8Array(0);
  frames: TestGifFrame[] = [];
}

function testLzwDecode(data: Uint8Array, minCodeSize: number, maxPixels: number): Uint8Array {
  const clearCode: number = 1 << minCodeSize;
  const eoiCode: number = clearCode + 1;
  let codeSize: number = minCodeSize + 1;
  let nextCode: number = eoiCode + 1;
  const prefix: Int32Array = new Int32Array(4096);
  const suffix: Int32Array = new Int32Array(4096);
  const stack: Int32Array = new Int32Array(4096);
  const output: Uint8Array = new Uint8Array(maxPixels);
  let outLen: number = 0;
  let bitBuf: number = 0;
  let bitCnt: number = 0;
  let pos: number = 0;
  let prev: number = -1;
  while (outLen < maxPixels) {
    while (bitCnt < codeSize) {
      if (pos >= data.length) {
        return output.subarray(0, outLen);
      }
      bitBuf |= data[pos] << bitCnt;
      pos++;
      bitCnt += 8;
    }
    const code: number = bitBuf & ((1 << codeSize) - 1);
    bitBuf >>>= codeSize;
    bitCnt -= codeSize;
    if (code === eoiCode) {
      break;
    }
    if (code === clearCode) {
      codeSize = minCodeSize + 1;
      nextCode = eoiCode + 1;
      prev = -1;
      continue;
    }
    if (prev < 0) {
      if (code >= clearCode) {
        throw new Error('test lzw: invalid first code');
      }
      output[outLen] = code;
      outLen++;
      prev = code;
      continue;
    }
    let first: number = -1;
    if (code < nextCode) {
      let depth: number = 0;
      let c: number = code;
      while (c >= clearCode + 2) {
        stack[depth] = suffix[c];
        depth++;
        c = prefix[c];
      }
      first = c;
      stack[depth] = c;
      depth++;
      for (let i = depth - 1; i >= 0; i--) {
        output[outLen] = stack[i];
        outLen++;
      }
    } else if (code === nextCode) {
      let depth: number = 0;
      let c: number = prev;
      while (c >= clearCode + 2) {
        stack[depth] = suffix[c];
        depth++;
        c = prefix[c];
      }
      first = c;
      stack[depth] = c;
      depth++;
      stack[depth] = c;
      depth++;
      for (let i = depth - 1; i >= 0; i--) {
        output[outLen] = stack[i];
        outLen++;
      }
    } else {
      throw new Error('test lzw: invalid code');
    }
    prefix[nextCode] = prev;
    suffix[nextCode] = first;
    nextCode++;
    prev = code;
    if (nextCode === (1 << codeSize) && codeSize < 12) {
      codeSize++;
    }
  }
  return output.subarray(0, outLen);
}

function testParseGif(data: Uint8Array): TestGifResult {
  const result: TestGifResult = new TestGifResult();
  if (data.length < 13 || data[0] !== 0x47 || data[1] !== 0x49 || data[2] !== 0x46) {
    throw new Error('test parse: not gif');
  }
  result.width = data[6] | (data[7] << 8);
  result.height = data[8] | (data[9] << 8);
  const packed: number = data[10];
  let pos: number = 13;
  if ((packed & 0x80) !== 0) {
    const n: number = 2 << (packed & 0x07);
    result.palette = data.slice(pos, pos + n * 3);
    pos += n * 3;
  }
  let delayCs: number = 0;
  let transparentIdx: number = -1;
  while (pos < data.length) {
    const blockType: number = data[pos];
    pos++;
    if (blockType === 0x3B) {
      return result;
    }
    if (blockType === 0x21) {
      const label: number = data[pos];
      pos++;
      if (label === 0xF9) {
        const blockSize: number = data[pos];
        const gcePacked: number = data[pos + 1];
        delayCs = data[pos + 2] | (data[pos + 3] << 8);
        transparentIdx = (gcePacked & 0x01) !== 0 ? data[pos + 4] : -1;
        pos += blockSize + 2;
      } else if (label === 0xFF) {
        const idSize: number = data[pos];
        pos++;
        let appId = '';
        for (let i = 0; i < idSize; i++) {
          appId += String.fromCharCode(data[pos + i]);
        }
        pos += idSize;
        if (appId === 'NETSCAPE2.0') {
          while (pos < data.length && data[pos] !== 0) {
            const len: number = data[pos];
            pos++;
            if (len >= 3 && data[pos] === 0x01) {
              const v: number = data[pos + 1] | (data[pos + 2] << 8);
              result.loopCount = v === 0 ? 0 : v + 1;
            }
            pos += len;
          }
          pos++;
        } else {
          while (pos < data.length && data[pos] !== 0) {
            pos += data[pos] + 1;
          }
          pos++;
        }
      } else {
        while (pos < data.length && data[pos] !== 0) {
          pos += data[pos] + 1;
        }
        pos++;
      }
      continue;
    }
    if (blockType === 0x2C) {
      const fw: number = data[pos + 4] | (data[pos + 5] << 8);
      const fh: number = data[pos + 6] | (data[pos + 7] << 8);
      pos += 9;
      const minCodeSize: number = data[pos];
      pos++;
      const chunks: Uint8Array[] = [];
      let total: number = 0;
      while (pos < data.length && data[pos] !== 0) {
        const len: number = data[pos];
        pos++;
        chunks.push(data.slice(pos, pos + len));
        total += len;
        pos += len;
      }
      pos++;
      const raw: Uint8Array = new Uint8Array(total);
      let off: number = 0;
      for (const c of chunks) {
        raw.set(c, off);
        off += c.length;
      }
      const frame: TestGifFrame = new TestGifFrame();
      frame.indices = testLzwDecode(raw, minCodeSize, fw * fh);
      frame.delayCs = delayCs;
      frame.transparentIdx = transparentIdx;
      result.frames.push(frame);
      delayCs = 0;
      transparentIdx = -1;
      continue;
    }
    throw new Error('test parse: unknown block');
  }
  throw new Error('test parse: no trailer');
}

function makeFrame(w: number, h: number, delayCs: number, pixels: Uint8Array): GifFrameData {
  const f: GifFrameData = new GifFrameData();
  f.width = w;
  f.height = h;
  f.delayCs = delayCs;
  f.pixels = pixels;
  return f;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

/** 确定性伪随机（LCG），供 LZW 长序列测试。 */
function lcgNext(seed: number): number {
  return (seed * 1103515245 + 12345) & 0x7FFFFFFF;
}

const TEST_BEADS: BeadColor[] = [
  new BeadColor('T1', '红', 'FF0000'),
  new BeadColor('T2', '蓝', '0000FF'),
  new BeadColor('T3', '白', 'FFFFFF')
];

export default function pixelExportTest() {
  describe('pixelExportTest', () => {
    // ---------- GifCodec：字节级 ----------
    it('GifCodec_header_bytes', 0, () => {
      const px: Uint8Array = new Uint8Array(16);
      px.set([255, 0, 0, 255], 0);
      px.set([0, 255, 0, 255], 4);
      px.set([0, 0, 255, 255], 8);
      const fixed: Uint8Array = new Uint8Array([255, 0, 0, 0, 255, 0, 0, 0, 255]);
      const opts: GifEncodeOptions = new GifEncodeOptions();
      opts.fixedPalette = fixed;
      opts.transparent = true;
      const data: Uint8Array = encodeGif([makeFrame(2, 2, 5, px)], opts);
      expect(data[0]).assertEqual(0x47); // 'G'
      expect(data[1]).assertEqual(0x49); // 'I'
      expect(data[2]).assertEqual(0x46); // 'F'
      expect(data[3]).assertEqual(0x38); // '8'
      expect(data[4]).assertEqual(0x39); // '9'
      expect(data[5]).assertEqual(0x61); // 'a'
      expect(data[6] | (data[7] << 8)).assertEqual(2);
      expect(data[8] | (data[9] << 8)).assertEqual(2);
      // 全局表 + 2 位色（bits=2 → (bits-1)<<4 | (bits-1)）
      expect(data[10]).assertEqual(0x80 | (1 << 4) | 1);
      expect(data[11]).assertEqual(0);
      expect(data[12]).assertEqual(0);
      // 调色板 4 色顺序（GCT 13..24）：红/绿/蓝 + 透明哨兵黑
      expect(data[13]).assertEqual(255);
      expect(data[14]).assertEqual(0);
      expect(data[15]).assertEqual(0);
      expect(data[17]).assertEqual(255); // 绿 G
      expect(data[21]).assertEqual(255); // 蓝 B
      expect(data[22]).assertEqual(0); // 哨兵黑
      expect(data[24]).assertEqual(0);
      // NETSCAPE2.0 无限循环块（25 起）
      expect(data[25]).assertEqual(0x21);
      expect(data[26]).assertEqual(0xFF);
      expect(data[27]).assertEqual(0x0B);
      expect(data[28]).assertEqual(0x4E); // 'N'
      expect(data[39]).assertEqual(0x03);
      expect(data[40]).assertEqual(0x01);
      expect(data[41]).assertEqual(0);
      expect(data[42]).assertEqual(0);
      expect(data[data.length - 1]).assertEqual(0x3B);
    });

    it('GifCodec_loop_count_variants', 0, () => {
      const px: Uint8Array = new Uint8Array(4);
      px.set([255, 0, 0, 255], 0);
      const fixed: Uint8Array = new Uint8Array([255, 0, 0]);
      const once: GifEncodeOptions = new GifEncodeOptions();
      once.fixedPalette = fixed;
      once.loopCount = 1;
      const dataOnce: Uint8Array = encodeGif([makeFrame(1, 1, 2, px)], once);
      expect(testParseGif(dataOnce).loopCount).assertEqual(1);
      const thrice: GifEncodeOptions = new GifEncodeOptions();
      thrice.fixedPalette = fixed;
      thrice.loopCount = 3;
      expect(testParseGif(encodeGif([makeFrame(1, 1, 2, px)], thrice)).loopCount).assertEqual(3);
      const forever: GifEncodeOptions = new GifEncodeOptions();
      forever.fixedPalette = fixed;
      forever.loopCount = 0;
      expect(testParseGif(encodeGif([makeFrame(1, 1, 2, px)], forever)).loopCount).assertEqual(0);
    });

    it('GifCodec_fixed_palette_transparent_mapping', 0, () => {
      const px: Uint8Array = new Uint8Array(16);
      px.set([255, 0, 0, 255], 0);
      px.set([0, 255, 0, 255], 4);
      px.set([0, 0, 255, 255], 8);
      // (1,1) 全透明 → 透明索引
      const fixed: Uint8Array = new Uint8Array([255, 0, 0, 0, 255, 0, 0, 0, 255]);
      const opts: GifEncodeOptions = new GifEncodeOptions();
      opts.fixedPalette = fixed;
      opts.transparent = true;
      const parsed: TestGifResult = testParseGif(encodeGif([makeFrame(2, 2, 4, px)], opts));
      expect(parsed.frames.length).assertEqual(1);
      expect(parsed.frames[0].indices.length).assertEqual(4);
      expect(parsed.frames[0].indices[0]).assertEqual(0);
      expect(parsed.frames[0].indices[1]).assertEqual(1);
      expect(parsed.frames[0].indices[2]).assertEqual(2);
      expect(parsed.frames[0].indices[3]).assertEqual(3);
      expect(parsed.frames[0].transparentIdx).assertEqual(3);
      // 调色板 4 色 = 3 固定 + 1 透明哨兵
      expect(parsed.palette.length).assertEqual(12);
    });

    it('GifCodec_no_transparent_maps_to_zero', 0, () => {
      const px: Uint8Array = new Uint8Array(8);
      px.set([0, 0, 255, 255], 0); // (0,0) 蓝
      // (1,0) 透明
      const fixed: Uint8Array = new Uint8Array([255, 0, 0, 0, 0, 255]);
      const opts: GifEncodeOptions = new GifEncodeOptions();
      opts.fixedPalette = fixed;
      const parsed: TestGifResult = testParseGif(encodeGif([makeFrame(2, 1, 1, px)], opts));
      expect(parsed.frames[0].indices[0]).assertEqual(1);
      expect(parsed.frames[0].indices[1]).assertEqual(0);
      expect(parsed.frames[0].transparentIdx).assertEqual(-1);
    });

    it('GifCodec_lzw_roundtrip_basic', 0, () => {
      // 空序列
      const empty: Uint8Array = lzwEncode(new Uint8Array(0), 2);
      expect(testLzwDecode(empty, 2, 0).length).assertEqual(0);
      // 16 符号模式序列
      const indices: Uint8Array = new Uint8Array(100);
      let seed = 7;
      for (let i = 0; i < indices.length; i++) {
        seed = lcgNext(seed);
        indices[i] = (seed >> 16) % 16;
      }
      const enc: Uint8Array = lzwEncode(indices, 4);
      const dec: Uint8Array = testLzwDecode(enc, 4, indices.length);
      expect(bytesEqual(dec, indices)).assertTrue();
    });

    it('GifCodec_lzw_dict_full_reset', 0, () => {
      // 10000 长度 250 符号序列：字典必然填满触发 Clear 重置
      const indices: Uint8Array = new Uint8Array(10000);
      let seed = 99;
      for (let i = 0; i < indices.length; i++) {
        seed = lcgNext(seed);
        indices[i] = (seed >> 16) % 250;
      }
      const enc: Uint8Array = lzwEncode(indices, 8);
      const dec: Uint8Array = testLzwDecode(enc, 8, indices.length);
      expect(dec.length).assertEqual(indices.length);
      expect(bytesEqual(dec, indices)).assertTrue();
    });

    it('GifCodec_quantize_deterministic', 0, () => {
      const f1: Uint8Array = new Uint8Array(8 * 8 * 4);
      const f2: Uint8Array = new Uint8Array(8 * 8 * 4);
      for (let p = 0; p < 64; p++) {
        f1[p * 4] = p * 4;
        f1[p * 4 + 1] = 255 - p * 3;
        f1[p * 4 + 2] = p * 2;
        f1[p * 4 + 3] = 255;
        f2[p * 4] = 255 - p * 4;
        f2[p * 4 + 1] = p;
        f2[p * 4 + 2] = 128;
        f2[p * 4 + 3] = 255;
      }
      const opts: GifEncodeOptions = new GifEncodeOptions();
      const a: Uint8Array = encodeGif([makeFrame(8, 8, 6, f1), makeFrame(8, 8, 6, f2)], opts);
      const b: Uint8Array = encodeGif([makeFrame(8, 8, 6, f1.slice()), makeFrame(8, 8, 6, f2.slice())], opts);
      expect(bytesEqual(a, b)).assertTrue();
      const parsed: TestGifResult = testParseGif(a);
      expect(parsed.frames.length).assertEqual(2);
      expect(parsed.palette.length % 3).assertEqual(0);
      expect(parsed.palette.length <= 256 * 3).assertTrue();
      expect(parsed.frames[0].indices.length).assertEqual(64);
    });

    it('GifCodec_multi_frame_delays', 0, () => {
      const mk = (v: number): Uint8Array => {
        const px: Uint8Array = new Uint8Array(4);
        px.set([v, 0, 0, 255], 0);
        return px;
      };
      const opts: GifEncodeOptions = new GifEncodeOptions();
      const parsed: TestGifResult = testParseGif(encodeGif([
        makeFrame(1, 1, 5, mk(255)),
        makeFrame(1, 1, 10, mk(128)),
        makeFrame(1, 1, 15, mk(0))
      ], opts));
      expect(parsed.frames.length).assertEqual(3);
      expect(parsed.frames[0].delayCs).assertEqual(5);
      expect(parsed.frames[1].delayCs).assertEqual(10);
      expect(parsed.frames[2].delayCs).assertEqual(15);
    });

    it('GifCodec_dither_deterministic', 0, () => {
      const px: Uint8Array = new Uint8Array(16 * 8 * 4);
      for (let p = 0; p < 128; p++) {
        px[p * 4] = p * 2;
        px[p * 4 + 1] = 255 - p;
        px[p * 4 + 2] = 64;
        px[p * 4 + 3] = 255;
      }
      const opts: GifEncodeOptions = new GifEncodeOptions();
      opts.dither = true;
      const a: Uint8Array = encodeGif([makeFrame(16, 8, 4, px)], opts);
      const b: Uint8Array = encodeGif([makeFrame(16, 8, 4, px.slice())], opts);
      expect(bytesEqual(a, b)).assertTrue();
      expect(testParseGif(a).frames.length).assertEqual(1);
    });

    it('GifCodec_validation_throws', 0, () => {
      const opts: GifEncodeOptions = new GifEncodeOptions();
      let threw = false;
      try {
        encodeGif([], opts);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        encodeGif([makeFrame(2, 2, 1, new Uint8Array(16)), makeFrame(3, 2, 1, new Uint8Array(24))], opts);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        encodeGif([makeFrame(2, 2, 1, new Uint8Array(8))], opts);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      const badPalette: GifEncodeOptions = new GifEncodeOptions();
      badPalette.fixedPalette = new Uint8Array([1, 2, 3, 4]);
      try {
        encodeGif([makeFrame(1, 1, 1, new Uint8Array([0, 0, 0, 255]))], badPalette);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('GifCodec_quantize_palette_only_opaque', 0, () => {
      // 全透明帧 → 量化回退单黑色板
      const px: Uint8Array = new Uint8Array(4);
      const palette: Uint8Array = quantizeToPalette([makeFrame(1, 1, 1, px)], 256);
      expect(palette.length).assertEqual(3);
    });

    // ---------- Resample ----------
    it('Resample_scale_2x_replication', 0, () => {
      const src: Uint8Array = new Uint8Array(16);
      src.set([255, 0, 0, 255], 0);
      src.set([0, 255, 0, 255], 4);
      src.set([0, 0, 255, 255], 8);
      src.set([255, 255, 0, 255], 12);
      const out: Uint8Array = Resample.scaleNearest(src, 2, 2, 2);
      expect(out.length).assertEqual(64);
      const at = (x: number, y: number): number => (y * 4 + x) * 4;
      expect(out[at(0, 0)]).assertEqual(255); // 红 R
      expect(out[at(1, 1)]).assertEqual(255); // 红块内 R
      expect(out[at(3, 0) + 1]).assertEqual(255); // 绿 G
      expect(out[at(2, 1) + 1]).assertEqual(255); // 绿块内 G
      expect(out[at(0, 3) + 2]).assertEqual(255); // 蓝 B
      expect(out[at(3, 3)]).assertEqual(255); // 黄 R
      expect(out[at(3, 3) + 1]).assertEqual(255); // 黄 G
    });

    it('Resample_scale_1x_copy', 0, () => {
      const src: Uint8Array = new Uint8Array([9, 9, 9, 9]);
      const out: Uint8Array = Resample.scaleNearest(src, 1, 1, 1);
      out[0] = 1;
      expect(src[0]).assertEqual(9);
      expect(out.length).assertEqual(4);
    });

    it('Resample_invalid_args_throw', 0, () => {
      let threw = false;
      try {
        Resample.scaleNearest(new Uint8Array(4), 1, 1, 0);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        // 非整数倍
        Resample.scaleNearest(new Uint8Array(4), 1, 1, 1.5);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        // 源长度与 w*h*4 不符
        Resample.scaleNearest(new Uint8Array(4), 2, 2, 1);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    // ---------- BeadStats ----------
    it('BeadStats_manifest_counts', 0, () => {
      // 6 格：3×T1 + 1×T2 + 2 空位
      const indices: Int32Array = new Int32Array([0, -1, 0, 1, 0, -1]);
      const m = BeadStats.manifest(indices, TEST_BEADS);
      expect(m.total).assertEqual(4);
      expect(m.entries.length).assertEqual(2);
      expect(m.entries[0].beadIndex).assertEqual(0);
      expect(m.entries[0].count).assertEqual(3);
      expect(m.entries[0].ratio).assertEqual(0.75);
      expect(m.entries[0].code).assertEqual('T1');
      expect(m.entries[0].packs).assertEqual(1);
      expect(m.entries[1].beadIndex).assertEqual(1);
      expect(m.entries[1].count).assertEqual(1);
      expect(m.entries[1].ratio).assertEqual(0.25);
    });

    it('BeadStats_manifest_empty', 0, () => {
      const indices: Int32Array = new Int32Array([-1, -1, -1, -1]);
      const m = BeadStats.manifest(indices, TEST_BEADS);
      expect(m.total).assertEqual(0);
      expect(m.entries.length).assertEqual(0);
    });

    it('BeadStats_manifest_sort_deterministic', 0, () => {
      // 同数量 → beadIndex 升序；两次运行结果一致
      const indices: Int32Array = new Int32Array([2, 1, 2, 1]);
      const a = BeadStats.manifest(indices, TEST_BEADS);
      const b = BeadStats.manifest(new Int32Array(indices), TEST_BEADS);
      expect(a.entries[0].beadIndex).assertEqual(1);
      expect(a.entries[1].beadIndex).assertEqual(2);
      expect(a.entries[0].count).assertEqual(b.entries[0].count);
      expect(a.entries[0].ratio).assertEqual(b.entries[0].ratio);
      expect(a.entries[0].packs).assertEqual(b.entries[0].packs);
    });

    it('BeadStats_boards_29', 0, () => {
      expect(BeadStats.boardsAcross(64)).assertEqual(3);
      expect(BeadStats.boardsAcross(29)).assertEqual(1);
      expect(BeadStats.boardsAcross(30)).assertEqual(2);
      expect(BeadStats.boardCount(64, 64)).assertEqual(9);
      expect(BeadStats.boardIndex(0, 0, 64)).assertEqual(0);
      expect(BeadStats.boardIndex(28, 28, 64)).assertEqual(0);
      expect(BeadStats.boardIndex(29, 0, 64)).assertEqual(1);
      expect(BeadStats.boardIndex(58, 0, 64)).assertEqual(2);
      expect(BeadStats.boardIndex(0, 29, 64)).assertEqual(3);
      expect(BeadStats.boardIndex(29, 29, 64)).assertEqual(4);
      expect(BeadStats.boardIndex(63, 63, 64)).assertEqual(8);
    });

    it('BeadStats_packs_suggestion', 0, () => {
      expect(Math.ceil(1000 / BEADS_PER_PACK)).assertEqual(1);
      expect(Math.ceil(1001 / BEADS_PER_PACK)).assertEqual(2);
      expect(Math.ceil(2500 / BEADS_PER_PACK)).assertEqual(3);
      const indices: Int32Array = new Int32Array(1001);
      indices.fill(0);
      const m = BeadStats.manifest(indices, TEST_BEADS);
      expect(m.entries[0].packs).assertEqual(2);
    });

    // ---------- PxsFile ----------
    it('PxsFile_roundtrip_fields', 0, () => {
      const meta: PxsMeta = new PxsMeta();
      meta.name = '我的像素画';
      meta.w = 16;
      meta.h = 16;
      meta.fps = 12;
      meta.frameCount = 2;
      meta.paletteId = 'bead_perler';
      const l0: PxsLayerMeta = new PxsLayerMeta();
      l0.id = 1;
      l0.name = '背景层';
      l0.visible = true;
      l0.opacity = 100;
      const l1: PxsLayerMeta = new PxsLayerMeta();
      l1.id = 2;
      l1.name = '前景层';
      l1.visible = false;
      l1.opacity = 70;
      meta.layers.push(l0);
      meta.layers.push(l1);
      const cells: PixelBuffer[][] = [];
      for (let f = 0; f < 2; f++) {
        const row: PixelBuffer[] = [];
        for (let l = 0; l < 2; l++) {
          const cell: PixelBuffer = new PixelBuffer(16, 16);
          cell.setPx(3, 4, 0xFF00FF00 + f * 0x100 + l);
          row.push(cell);
        }
        cells.push(row);
      }
      const data: Uint8Array = PxsFile.serialize(meta, cells);
      const doc = PxsFile.parse(data);
      expect(doc !== undefined).assertTrue();
      if (doc === undefined) {
        return;
      }
      expect(doc.meta.name).assertEqual('我的像素画');
      expect(doc.meta.w).assertEqual(16);
      expect(doc.meta.h).assertEqual(16);
      expect(doc.meta.fps).assertEqual(12);
      expect(doc.meta.frameCount).assertEqual(2);
      expect(doc.meta.paletteId).assertEqual('bead_perler');
      expect(doc.meta.layers.length).assertEqual(2);
      expect(doc.meta.layers[0].name).assertEqual('背景层');
      expect(doc.meta.layers[0].visible).assertTrue();
      expect(doc.meta.layers[0].opacity).assertEqual(100);
      expect(doc.meta.layers[1].name).assertEqual('前景层');
      expect(doc.meta.layers[1].visible).assertFalse();
      expect(doc.meta.layers[1].opacity).assertEqual(70);
      expect(doc.cells.length).assertEqual(2);
      expect(doc.cells[1][1].getPx(3, 4)).assertEqual(0xFF00FF00 + 1 * 0x100 + 1);
    });

    it('PxsFile_roundtrip_1000x', 0, () => {
      const meta: PxsMeta = new PxsMeta();
      meta.name = '压测';
      meta.w = 8;
      meta.h = 8;
      meta.fps = 8;
      meta.frameCount = 2;
      meta.paletteId = 'pico8';
      meta.layers.push(new PxsLayerMeta());
      const l1: PxsLayerMeta = new PxsLayerMeta();
      l1.id = 5;
      l1.opacity = 40;
      meta.layers.push(l1);
      const cells: PixelBuffer[][] = [];
      for (let f = 0; f < 2; f++) {
        const row: PixelBuffer[] = [];
        for (let l = 0; l < 2; l++) {
          const cell: PixelBuffer = new PixelBuffer(8, 8);
          cell.setPx(0, 0, 0xFF112233);
          cell.setPx(7, 7, 0xFF445566);
          row.push(cell);
        }
        cells.push(row);
      }
      const first: Uint8Array = PxsFile.serialize(meta, cells);
      for (let i = 0; i < 1000; i++) {
        const doc = PxsFile.parse(first);
        expect(doc !== undefined).assertTrue();
        if (doc === undefined) {
          return;
        }
        const again: Uint8Array = PxsFile.serialize(doc.meta, doc.cells);
        expect(bytesEqual(first, again)).assertTrue();
      }
    });

    it('PxsFile_parseMeta_only', 0, () => {
      const meta: PxsMeta = new PxsMeta();
      meta.name = '列表';
      meta.w = 4;
      meta.h = 4;
      meta.frameCount = 1;
      meta.layers.push(new PxsLayerMeta());
      const cells: PixelBuffer[][] = [[new PixelBuffer(4, 4)]];
      const data: Uint8Array = PxsFile.serialize(meta, cells);
      const onlyMeta = PxsFile.parseMeta(data);
      expect(onlyMeta !== undefined).assertTrue();
      if (onlyMeta === undefined) {
        return;
      }
      expect(onlyMeta.name).assertEqual('列表');
      expect(onlyMeta.w).assertEqual(4);
      expect(onlyMeta.layers.length).assertEqual(1);
    });

    it('PxsFile_corrupt_tolerance', 0, () => {
      const meta: PxsMeta = new PxsMeta();
      meta.name = 'ab';
      meta.w = 2;
      meta.h = 2;
      meta.frameCount = 1;
      meta.layers.push(new PxsLayerMeta());
      const cells: PixelBuffer[][] = [[new PixelBuffer(2, 2)]];
      const data: Uint8Array = PxsFile.serialize(meta, cells);
      // 原始可解析
      expect(PxsFile.parse(data) !== undefined).assertTrue();
      // 魔数损坏
      const badMagic: Uint8Array = data.slice();
      badMagic[0] = 0x51;
      expect(PxsFile.parse(badMagic) === undefined).assertTrue();
      // 版本不符
      const badVersion: Uint8Array = data.slice();
      badVersion[4] = 9;
      expect(PxsFile.parse(badVersion) === undefined).assertTrue();
      // 截断
      expect(PxsFile.parse(data.subarray(0, data.length - 1)) === undefined).assertTrue();
      // 尾部多余字节（像素流长度不匹配）
      const trailing: Uint8Array = new Uint8Array(data.length + 1);
      trailing.set(data);
      expect(PxsFile.parse(trailing) === undefined).assertTrue();
      // 帧数被篡改（meta 偏移：14 + 2 nameLen + 2 name + 2 w + 2 h + 2 fps = 24）
      const badFrames: Uint8Array = data.slice();
      badFrames[24] = 2;
      expect(PxsFile.parse(badFrames) === undefined).assertTrue();
      // 过短输入
      expect(PxsFile.parse(new Uint8Array(4)) === undefined).assertTrue();
    });

    it('PxsFile_utf8_roundtrip_and_tolerant_decode', 0, () => {
      const enc: number[] = [];
      PxsFile.utf8Encode('你好🎬A', enc);
      const bytes: Uint8Array = new Uint8Array(enc);
      expect(PxsFile.utf8Decode(bytes, 0, bytes.length)).assertEqual('你好🎬A');
      // 坏序列 → U+FFFD 替换，不崩溃
      const bad: Uint8Array = new Uint8Array([0xFF, 0xFE, 0xC0, 0x80, 0x41]);
      const s: string = PxsFile.utf8Decode(bad, 0, bad.length);
      expect(s.length >= 3).assertTrue();
      expect(s.charAt(s.length - 1)).assertEqual('A');
      // 空串
      const empty: number[] = [];
      PxsFile.utf8Encode('', empty);
      expect(empty.length).assertEqual(0);
    });

    it('PxsFile_serialize_validation', 0, () => {
      const meta: PxsMeta = new PxsMeta();
      meta.w = 2;
      meta.h = 2;
      meta.frameCount = 2;
      meta.layers.push(new PxsLayerMeta());
      let threw = false;
      try {
        // cells 只有 1 帧 ≠ frameCount 2
        PxsFile.serialize(meta, [[new PixelBuffer(2, 2)]]);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      const noLayers: PxsMeta = new PxsMeta();
      noLayers.w = 2;
      noLayers.h = 2;
      noLayers.frameCount = 1;
      try {
        PxsFile.serialize(noLayers, [[new PixelBuffer(2, 2)]]);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    // ---------- Font5x7 ----------
    it('Font5x7_glyph_patterns', 0, () => {
      const a = Font5x7.glyphBytes('A');
      expect(a !== undefined).assertTrue();
      if (a === undefined) {
        return;
      }
      expect(a[0]).assertEqual(0x0E);
      expect(a[3]).assertEqual(0x1F);
      expect(a[6]).assertEqual(0x11);
      const space = Font5x7.glyphBytes(' ');
      expect(space !== undefined).assertTrue();
      if (space !== undefined) {
        expect(space[0]).assertEqual(0);
        expect(space[6]).assertEqual(0);
      }
      expect(Font5x7.has('Z')).assertTrue();
      expect(Font5x7.has('a')).assertFalse();
      expect(Font5x7.has('9')).assertTrue();
      expect(Font5x7.glyphBytes('#') === undefined).assertTrue();
    });

    it('Font5x7_text_width', 0, () => {
      expect(Font5x7.textWidth('ABC', 1)).assertEqual(17);
      expect(Font5x7.textWidth('A', 2)).assertEqual(10);
      expect(Font5x7.textWidth('', 3)).assertEqual(0);
    });

    it('Font5x7_draw_text_pixels_and_clip', 0, () => {
      const pw = 13;
      const ph = 9;
      const px: Uint8Array = new Uint8Array(pw * ph * 4);
      px.fill(255);
      Font5x7.drawText(px, pw, ph, 0, 0, 'I', 0xFF000000, 1);
      const at = (x: number, y: number): number => (y * pw + x) * 4;
      // 'I' 首行 0x0E = 列 1/2/3
      expect(px[at(0, 0)]).assertEqual(255);
      expect(px[at(1, 0)]).assertEqual(0);
      expect(px[at(2, 0)]).assertEqual(0);
      expect(px[at(4, 0)]).assertEqual(255);
      // 第二行 0x04 = 仅列 2
      expect(px[at(1, 1)]).assertEqual(255);
      expect(px[at(2, 1)]).assertEqual(0);
      // 末行 0x0E（字形高 7 行：0..6）
      expect(px[at(3, 6)]).assertEqual(0);
      // 第 8 行（y=7）在字形之外 → 未落笔
      expect(px[at(2, 7)]).assertEqual(255);
      // 越界裁剪不崩溃（大 scale 出界）
      Font5x7.drawText(px, pw, ph, pw - 2, ph - 2, 'W', 0xFF000000, 4);
      Font5x7.drawText(px, pw, ph, -5, -5, 'M', 0xFF000000, 2);
      expect(px.length).assertEqual(pw * ph * 4);
    });

    it('Font5x7_punctuation_glyphs', 0, () => {
      // 1.1.0-D：8 个标点字形入集（文本工具输入域）。
      expect(Font5x7.has('.')).assertTrue();
      expect(Font5x7.has(',')).assertTrue();
      expect(Font5x7.has(':')).assertTrue();
      expect(Font5x7.has('!')).assertTrue();
      expect(Font5x7.has('?')).assertTrue();
      expect(Font5x7.has('\'')).assertTrue();
      expect(Font5x7.has('(')).assertTrue();
      expect(Font5x7.has(')')).assertTrue();
      expect(Font5x7.has('#')).assertFalse();
      expect(Font5x7.textWidth('A!', 1)).assertEqual(11);
    });

    it('Font5x7_draw_period_pixels', 0, () => {
      // '.' = 行 5/6 列 2/3 四点：锚点 (1,1) → 落 (3,6)(4,6)(3,7)(4,7)。
      const pw = 8;
      const ph = 8;
      const px: Uint8Array = new Uint8Array(pw * ph * 4);
      px.fill(255);
      Font5x7.drawText(px, pw, ph, 1, 1, '.', 0xFF000000, 1);
      const at = (x: number, y: number): number => (y * pw + x) * 4;
      expect(px[at(3, 6)]).assertEqual(0);
      expect(px[at(4, 6)]).assertEqual(0);
      expect(px[at(3, 7)]).assertEqual(0);
      expect(px[at(4, 7)]).assertEqual(0);
      expect(px[at(2, 6)]).assertEqual(255);
      expect(px[at(5, 6)]).assertEqual(255);
      expect(px[at(3, 5)]).assertEqual(255);
    });

    // ---------- ChartRender ----------
    it('Chart_size_and_white_bg', 0, () => {
      const opts: BeadChartOptions = new BeadChartOptions();
      const size = ChartRender.chartSize(4, 4, opts);
      expect(size.w).assertEqual(20 + 4 * 16);
      expect(size.h).assertEqual(20 + 4 * 16);
      const indices: Int32Array = new Int32Array(16);
      indices.fill(-1);
      const px: Uint8Array = ChartRender.renderChart(indices, 4, 4, TEST_BEADS, opts);
      expect(px.length).assertEqual(size.w * size.h * 4);
      // 表头角落 = 白底
      const corner: number = (0 * size.w + 0) * 4;
      expect(px[corner]).assertEqual(255);
      expect(px[corner + 3]).assertEqual(255);
    });

    it('Chart_bead_colors_and_grid', 0, () => {
      const opts: BeadChartOptions = new BeadChartOptions();
      // 2×2：红/蓝/蓝/空位
      const indices: Int32Array = new Int32Array([0, 1, 1, -1]);
      const size = ChartRender.chartSize(2, 2, opts);
      const px: Uint8Array = ChartRender.renderChart(indices, 2, 2, TEST_BEADS, opts);
      const at = (x: number, y: number): number => (y * size.w + x) * 4;
      // 格 (0,0) 中心 = 红
      expect(px[at(28, 28)]).assertEqual(255);
      expect(px[at(28, 28) + 1]).assertEqual(0);
      // 格 (1,0) 蓝（x=48 在符号 'B' 位图之外）
      expect(px[at(48, 28) + 2]).assertEqual(255);
      // 格 (1,1) 空钉位 = 浅色棋盘
      expect(px[at(44, 44)] > 225).assertTrue();
      expect(px[at(44, 44) + 1] > 225).assertTrue();
      // 普通网格线（格 (0,0) 右缘 x = 20+16-1 = 35）= 浅灰
      expect(px[at(35, 24)]).assertEqual(0xD9);
    });

    it('Chart_board_separator_and_numbers', 0, () => {
      const opts: BeadChartOptions = new BeadChartOptions();
      opts.cellSize = 8;
      opts.showSymbols = false;
      // 64×64 全白豆 → 3×3 板
      const indices: Int32Array = new Int32Array(64 * 64);
      indices.fill(2);
      const size = ChartRender.chartSize(64, 64, opts);
      const px: Uint8Array = ChartRender.renderChart(indices, 64, 64, TEST_BEADS, opts);
      const at = (x: number, y: number): number => (y * size.w + x) * 4;
      // 竖分割线 x = 20 + 29*8 - 1 = 251（2px 品红）
      expect(px[at(251, 100)]).assertEqual(255);
      expect(px[at(251, 100) + 1]).assertEqual(0);
      expect(px[at(251, 100) + 2]).assertEqual(255);
      expect(px[at(250, 100) + 2]).assertEqual(255);
      // 横分割线 y = 251
      expect(px[at(100, 251) + 2]).assertEqual(255);
      // 板 1 左上角格 (20,20) 有深色序号像素（白底 → 深色字）
      let darkCount = 0;
      for (let y = 20; y < 28; y++) {
        for (let x = 20; x < 28; x++) {
          if (px[at(x, y)] < 80) {
            darkCount++;
          }
        }
      }
      expect(darkCount > 0).assertTrue();
      // 板 4（by=1,bx=0 → 序号 4）左上角格 y = 20+29*8 = 252
      let dark4 = 0;
      for (let y = 252; y < 260; y++) {
        for (let x = 20; x < 28; x++) {
          if (px[at(x, y)] < 80) {
            dark4++;
          }
        }
      }
      expect(dark4 > 0).assertTrue();
    });

    it('Chart_symbols_by_manifest_order', 0, () => {
      const opts: BeadChartOptions = new BeadChartOptions();
      opts.cellSize = 16;
      // 2×2：红×3 + 蓝×1 → 红='A'（数量第一），蓝='B'
      const indices: Int32Array = new Int32Array([0, 0, 0, 1]);
      const size = ChartRender.chartSize(2, 2, opts);
      const px: Uint8Array = ChartRender.renderChart(indices, 2, 2, TEST_BEADS, opts);
      const at = (x: number, y: number): number => (y * size.w + x) * 4;
      // 格 (0,0) 是板首格 → 画分板序号 '1'（红底 → 浅色字）
      let lightCount = 0;
      for (let y = 20; y < 36; y++) {
        for (let x = 20; x < 36; x++) {
          if (px[at(x, y)] > 200 && px[at(x, y) + 1] > 200 && px[at(x, y) + 2] > 200) {
            lightCount++;
          }
        }
      }
      expect(lightCount > 3).assertTrue();
      // 格 (1,0) 蓝 'B'（蓝底 → 浅色符号）
      let symbolPixels = 0;
      for (let y = 20; y < 36; y++) {
        for (let x = 36; x < 52; x++) {
          if (px[at(x, y)] > 200 && px[at(x, y) + 1] > 200 && px[at(x, y) + 2] > 200) {
            symbolPixels++;
          }
        }
      }
      expect(symbolPixels > 3).assertTrue();
    });

    it('Chart_deterministic', 0, () => {
      const opts: BeadChartOptions = new BeadChartOptions();
      opts.cellSize = 8;
      const indices: Int32Array = new Int32Array(64 * 64);
      let seed = 3;
      for (let i = 0; i < indices.length; i++) {
        seed = lcgNext(seed);
        indices[i] = (seed >> 16) % 5 - 1; // -1..3
      }
      const a: Uint8Array = ChartRender.renderChart(indices, 64, 64, TEST_BEADS, opts);
      const b: Uint8Array = ChartRender.renderChart(new Int32Array(indices), 64, 64, TEST_BEADS, opts);
      expect(bytesEqual(a, b)).assertTrue();
    });

    // ---------- SheetRender（1.1.0-D） ----------
    it('SheetRender_strip_layout', 0, () => {
      // 4×4 三帧：f0 红(0,0)、f1 绿(1,1)、f2 蓝(2,2) → 12×4 水平条图，透明保留。
      const doc = new PixelDoc(4, 4);
      doc.addFrame();
      doc.addFrame();
      doc.cells[0][0].setPx(0, 0, 0xFFFF0000);
      doc.cells[1][0].setPx(1, 1, 0xFF00FF00);
      doc.cells[2][0].setPx(2, 2, 0xFF0000FF);
      const strip = SheetRender.renderStrip(doc);
      expect(strip.w).assertEqual(12);
      expect(strip.h).assertEqual(4);
      expect(strip.buf.length).assertEqual(12 * 4 * 4);
      const at = (x: number, y: number): number => (y * strip.w + x) * 4;
      expect(strip.buf[at(0, 0)]).assertEqual(255);
      expect(strip.buf[at(0, 0) + 3]).assertEqual(255);
      expect(strip.buf[at(5, 1) + 1]).assertEqual(255);
      expect(strip.buf[at(5, 1) + 3]).assertEqual(255);
      expect(strip.buf[at(10, 2) + 2]).assertEqual(255);
      expect(strip.buf[at(10, 2) + 3]).assertEqual(255);
      // f0 (1,1) 未画 → 条图对应位 alpha 0（透明不丢）。
      expect(strip.buf[at(1, 1) + 3]).assertEqual(0);
    });

    it('SheetRender_atlas_json_fields', 0, () => {
      const doc = new PixelDoc(4, 4);
      doc.addFrame();
      const json = SheetRender.atlasJson(doc, 'demo_sheet.png', 12);
      expect(json.includes('"frames":2')).assertTrue();
      expect(json.includes('"frameW":4')).assertTrue();
      expect(json.includes('"frameH":4')).assertTrue();
      expect(json.includes('"sheetW":8')).assertTrue();
      expect(json.includes('"sheetH":4')).assertTrue();
      expect(json.includes('"fps":12')).assertTrue();
      expect(json.includes('"sheet":"demo_sheet.png"')).assertTrue();
      expect(json.includes('"xs":[0,4]')).assertTrue();
    });
  });
}
