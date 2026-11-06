/**
 * imageImportTest — 图片转像素画纯函数套件（1.6.0，功能需求 §9）。
 * 覆盖：缩采样 box/nearest、cover/contain 对齐、alpha 二值化、最近色同距确定性、
 * 抖动确定性、自动色板、非法参数拒收、端到端同输入逐字节一致。
 * 运行协议（模拟器 class 过滤）：
 *   hdc shell aa test -b com.ddabb.pixelstudio -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class imageImportTest -s timeout 15000
 */

import { describe, it, expect } from '@ohos/hypium';
import { ImageImport } from '../../../main/ets/core/ImageImport';

/** 断言 buf 在 (x,y) 处的 RGBA 四通道值。 */
function assertPx(buf: Uint8Array, w: number, x: number, y: number,
  r: number, g: number, b: number, a: number): void {
  const i = (y * w + x) * 4;
  expect(buf[i]).assertEqual(r);
  expect(buf[i + 1]).assertEqual(g);
  expect(buf[i + 2]).assertEqual(b);
  expect(buf[i + 3]).assertEqual(a);
}

/** 纯色 RGBA 缓冲构造。 */
function solid(w: number, h: number, r: number, g: number, b: number, a: number): Uint8Array {
  const out = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  }
  return out;
}

/** 2×2 四色图：R/G/B/W（行优先）。 */
function quad(): Uint8Array {
  const out = new Uint8Array(16);
  const c: number[][] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]];
  for (let i = 0; i < 4; i++) {
    out[i * 4] = c[i][0];
    out[i * 4 + 1] = c[i][1];
    out[i * 4 + 2] = c[i][2];
    out[i * 4 + 3] = 255;
  }
  return out;
}

/** 4×4 四色象限图：R/G/B/W（行优先，用于缩采样几何验证）。 */
function quad4(): Uint8Array {
  const out = new Uint8Array(16 * 4);
  for (let y = 0; y < 4; y++) {
    for (let x = 0; x < 4; x++) {
      const i = (y * 4 + x) * 4;
      const c = y < 2 ? (x < 2 ? [255, 0, 0] : [0, 255, 0]) : (x < 2 ? [0, 0, 255] : [255, 255, 255]);
      out[i] = c[0];
      out[i + 1] = c[1];
      out[i + 2] = c[2];
      out[i + 3] = 255;
    }
  }
  return out;
}

export default function imageImportTest() {
  describe('imageImportTest', () => {
    // ---------- 缩采样：几何与采样 ----------

    it('resampleRejectsInvalidArgs', 0, () => {
      const src = solid(2, 2, 255, 0, 0, 255);
      let threw = false;
      try {
        ImageImport.resample(src, 2, 2, 0, 2, true, true);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        ImageImport.resample(src, 3, 2, 2, 2, true, true); // 长度不匹配
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        ImageImport.resample(src, 2, 2, 300, 300, true, true); // 超 65536 上限
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('resampleBoxCoverAveragesBlocks', 0, () => {
      // 4×4 四色象限 → 2×2 box：每输出格 = 对应 2×2 纯色区块均值 = 该象限色。
      const out = ImageImport.resample(quad4(), 4, 4, 2, 2, true, true);
      expect(out.length).assertEqual(16);
      assertPx(out, 2, 0, 0, 255, 0, 0, 255);
      assertPx(out, 2, 1, 0, 0, 255, 0, 255);
      assertPx(out, 2, 0, 1, 0, 0, 255, 255);
      assertPx(out, 2, 1, 1, 255, 255, 255, 255);
    });

    it('resampleContainPadsTransparent', 0, () => {
      // 2×2 → 4×2 contain：横向留边（scale=1，offX=1），x=0/3 全透明。
      const out = ImageImport.resample(quad(), 2, 2, 4, 2, false, true);
      assertPx(out, 4, 0, 0, 0, 0, 0, 0);
      assertPx(out, 4, 3, 0, 0, 0, 0, 0);
      assertPx(out, 4, 1, 0, 255, 0, 0, 255);
      assertPx(out, 4, 2, 0, 0, 255, 0, 255);
    });

    it('resampleCoverUpscaleReplicates', 0, () => {
      // 2×2 → 4×4 cover 放大（scale=2）：整数边界下 box = 像素复制，四象限对应。
      const out = ImageImport.resample(quad(), 2, 2, 4, 4, true, true);
      assertPx(out, 4, 0, 0, 255, 0, 0, 255);
      assertPx(out, 4, 3, 0, 0, 255, 0, 255);
      assertPx(out, 4, 0, 3, 0, 0, 255, 255);
      assertPx(out, 4, 3, 3, 255, 255, 255, 255);
    });

    it('resampleNearestCenterSample', 0, () => {
      // 4×4 四色象限 → 2×2 nearest：中心取样取区块中心源像素（象限左上）。
      const out = ImageImport.resample(quad4(), 4, 4, 2, 2, true, false);
      assertPx(out, 2, 0, 0, 255, 0, 0, 255);
      assertPx(out, 2, 1, 1, 255, 255, 255, 255);
    });

    it('resampleBinarizesAlpha', 0, () => {
      // alpha 均值 <128 → 全透明；≥128 → 不透明。
      const low = solid(1, 1, 255, 0, 0, 100);
      const outLow = ImageImport.resample(low, 1, 1, 1, 1, true, true);
      expect(outLow[3]).assertEqual(0);
      const high = solid(1, 1, 255, 0, 0, 200);
      const outHigh = ImageImport.resample(high, 1, 1, 1, 1, true, true);
      expect(outHigh[3]).assertEqual(255);
      // nearest 同口径：<128 透明。
      const outN = ImageImport.resample(low, 1, 1, 1, 1, true, false);
      expect(outN[3]).assertEqual(0);
    });

    it('resampleBoxAlphaWeightedRgb', 0, () => {
      // 2×2 → 1×1 box：1 个不透明红 + 3 个全透明 → 区块均值 alpha=63<128 → 整格透明。
      const src = new Uint8Array(16);
      src[0] = 255; // (0,0) 红
      src[3] = 255;
      const out = ImageImport.resample(src, 2, 2, 1, 1, true, true);
      expect(out[3]).assertEqual(0);
      // 3 个不透明红 + 1 透明：均值 alpha=765/4≈191 ≥128 → RGB 仍纯红（透明不拖黑）。
      const src2 = new Uint8Array(16);
      src2[0] = 255;
      src2[3] = 255;
      src2[4] = 255; // (1,0) 红
      src2[7] = 255;
      src2[8] = 255; // (0,1) 红
      src2[11] = 255;
      const out2 = ImageImport.resample(src2, 2, 2, 1, 1, true, true);
      expect(out2[0]).assertEqual(255);
      expect(out2[1]).assertEqual(0);
      expect(out2[2]).assertEqual(0);
      expect(out2[3]).assertEqual(255);
    });

    // ---------- 抖动 ----------

    it('applyBayerDeterministicBias', 0, () => {
      const buf = solid(2, 2, 128, 128, 128, 255);
      ImageImport.applyBayer(buf, 2, 2);
      // (0,0) 阈值 0 → bias=-32 → 96；(1,0) 阈值 8 → bias=0 → 128；(0,1) 阈值 12 → bias=+16 → 144。
      assertPx(buf, 2, 0, 0, 96, 96, 96, 255);
      assertPx(buf, 2, 1, 0, 128, 128, 128, 255);
      assertPx(buf, 2, 0, 1, 144, 144, 144, 255);
      // 透明像素 RGB 不动。
      const t = solid(1, 1, 10, 20, 30, 0);
      ImageImport.applyBayer(t, 1, 1);
      expect(t[0]).assertEqual(10);
      expect(t[3]).assertEqual(0);
      // 越界不夹爆：250-32=218。
      const hi = solid(1, 1, 250, 250, 250, 255);
      ImageImport.applyBayer(hi, 1, 1);
      expect(hi[0]).assertEqual(218);
      // 长度不符抛错。
      let threw = false;
      try {
        ImageImport.applyBayer(new Uint8Array(4), 2, 2);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    // ---------- 量化 ----------

    it('quantizeNearestAndTieStable', 0, () => {
      const buf = new Uint8Array(8);
      // 像素 0：(250,5,5) → 最近红；像素 1：(128,128,128) 黑白等距 → 取先者（黑）。
      buf[0] = 250;
      buf[1] = 5;
      buf[2] = 5;
      buf[3] = 255;
      buf[4] = 128;
      buf[5] = 128;
      buf[6] = 128;
      buf[7] = 255;
      ImageImport.quantize(buf, [0xFF000000, 0xFFFF0000, 0xFFFFFFFF]);
      expect(buf[0]).assertEqual(255);
      expect(buf[1]).assertEqual(0);
      expect(buf[2]).assertEqual(0);
      expect(buf[3]).assertEqual(255);
      // 等距构造单独验证（同距取小索引）：像素 (0,0,0) 到 A=(6,0,8) 与 B=(2,8,0)
      // 加权距离均为 2·36+3·64 = 2·4+4·64 = 264 → 取先者 A=(6,0,8)。
      const tie = solid(1, 1, 0, 0, 0, 255);
      ImageImport.quantize(tie, [0xFF060008, 0xFF020800]);
      expect(tie[0]).assertEqual(6);
      expect(tie[1]).assertEqual(0);
      expect(tie[2]).assertEqual(8);
      expect(tie[3]).assertEqual(255);
      // 半透明 → 二值化为全透明。
      const half = solid(1, 1, 200, 0, 0, 100);
      ImageImport.quantize(half, [0xFFFF0000]);
      expect(half[3]).assertEqual(0);
      // 空色板抛错。
      let threw = false;
      try {
        ImageImport.quantize(new Uint8Array(4), []);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('nearestColorMatchesBeadQuantizeFormula', 0, () => {
      // 加权距离 d²=2Δr²+4Δg²+3Δb²：
      // (100,120,100) 到 (100,100,0)：d=4·20²+3·100²=31600；
      // 到 (0,100,100)：d=2·100²+4·20²=21600 → 后者更近。
      const c = ImageImport.nearestColor(100, 120, 100, [0xFF646400, 0xFF006464]);
      expect(c).assertEqual(0xFF006464);
    });

    // ---------- 自动色板 ----------

    it('autoPaletteMedianCut', 0, () => {
      const buf = new Uint8Array(8);
      buf[0] = 255;
      buf[3] = 255; // 红
      buf[6] = 255;
      buf[7] = 255; // 蓝
      const pal = ImageImport.autoPalette(buf, 4);
      expect(pal.length).assertEqual(2);
      expect(pal.includes(0xFFFF0000)).assertTrue();
      expect(pal.includes(0xFF0000FF)).assertTrue();
      // 全透明 → 空。
      expect(ImageImport.autoPalette(new Uint8Array(8), 4).length).assertEqual(0);
      // 色数上限 1 → 单色加权均值。
      const pal1 = ImageImport.autoPalette(buf, 1);
      expect(pal1.length).assertEqual(1);
      // 非法色数抛错。
      let threw = false;
      try {
        ImageImport.autoPalette(buf, 0);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('autoPaletteIgnoresTransparent', 0, () => {
      // 透明像素不参与统计：红 + 透明 → 色板仅红。
      const buf = new Uint8Array(8);
      buf[0] = 255;
      buf[3] = 255;
      const pal = ImageImport.autoPalette(buf, 4);
      expect(pal.length).assertEqual(1);
      expect(pal[0]).assertEqual(0xFFFF0000);
    });

    // ---------- 端到端确定性 ----------

    it('convertPipelineByteIdentical', 0, () => {
      // 8×8 渐变 → 8×8 自动色板 + 抖动：同参数两次输出逐字节一致。
      const src = new Uint8Array(64 * 4);
      for (let i = 0; i < 64; i++) {
        src[i * 4] = (i * 7) % 256;
        src[i * 4 + 1] = (i * 13) % 256;
        src[i * 4 + 2] = (i * 29) % 256;
        src[i * 4 + 3] = i % 5 === 0 ? 0 : 255;
      }
      const a = ImageImport.convert(src, 8, 8, 8, 8, true, true, true, undefined, 8);
      const b = ImageImport.convert(src, 8, 8, 8, 8, true, true, true, undefined, 8);
      expect(a.length).assertEqual(8 * 8 * 4);
      let same = true;
      for (let i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) {
          same = false;
          break;
        }
      }
      expect(same).assertTrue();
      // 量化输出无半透明：alpha ∈ {0,255}。
      let binary = true;
      for (let i = 3; i < a.length; i += 4) {
        if (a[i] !== 0 && a[i] !== 255) {
          binary = false;
          break;
        }
      }
      expect(binary).assertTrue();
      // 按色板模式同样确定（PICO-8 前 4 色）。
      const pico = [0xFF000000, 0xFF1D2B53, 0xFF7E2553, 0xFF008751];
      const c1 = ImageImport.convert(src, 8, 8, 8, 8, false, false, false, pico, 0);
      const c2 = ImageImport.convert(src, 8, 8, 8, 8, false, false, false, pico, 0);
      let sameP = true;
      for (let i = 0; i < c1.length; i++) {
        if (c1[i] !== c2[i]) {
          sameP = false;
          break;
        }
      }
      expect(sameP).assertTrue();
      // 色板输出全部落在色板色内（透明除外）。
      const allowed: number[] = [];
      for (const c of pico) {
        allowed.push((c >>> 16) & 0xFF, (c >>> 8) & 0xFF, c & 0xFF);
      }
      let inPalette = true;
      for (let p = 0; p < c1.length; p += 4) {
        if (c1[p + 3] === 0) {
          continue;
        }
        let hit = false;
        for (let k = 0; k < allowed.length; k += 3) {
          if (c1[p] === allowed[k] && c1[p + 1] === allowed[k + 1] && c1[p + 2] === allowed[k + 2]) {
            hit = true;
            break;
          }
        }
        if (!hit) {
          inPalette = false;
          break;
        }
      }
      expect(inPalette).assertTrue();
    });

    it('convertDoesNotMutateInput', 0, () => {
      const src = solid(4, 4, 10, 20, 30, 255);
      const copy = src.slice();
      ImageImport.convert(src, 4, 4, 2, 2, true, true, true, [0xFF000000, 0xFFFFFFFF], 0);
      let same = true;
      for (let i = 0; i < src.length; i++) {
        if (src[i] !== copy[i]) {
          same = false;
          break;
        }
      }
      expect(same).assertTrue();
    });
  });
}
