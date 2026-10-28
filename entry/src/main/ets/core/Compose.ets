/**
 * core/Compose.ets — 图层合成（纯逻辑层，不依赖 ArkUI）。
 * 自下而上遍历可见层，正常模式（source-over，直 alpha）混合到 out。
 * 零分配：复用调用方传入的目标缓冲（渲染管线整帧写回，见开发计划 §6.2/§6.5）。
 */

import { PixelDoc } from './PixelDoc';

export class Compose {
  /** 合成第 frameIndex 帧全部可见图层到 out（RGBA，长度 = w*h*4）。 */
  static composeFrame(doc: PixelDoc, frameIndex: number, out: Uint8Array): void {
    out.fill(0);
    const n = doc.w * doc.h;
    for (let li = 0; li < doc.layers.length; li++) {
      const layer = doc.layers[li];
      if (!layer.visible || layer.opacity <= 0) {
        continue;
      }
      const cell = doc.getCell(frameIndex, li);
      if (cell === undefined) {
        continue;
      }
      const src = cell.data;
      const full = layer.opacity >= 100;
      for (let p = 0; p < n; p++) {
        const i = p * 4;
        const sa = full ? src[i + 3] : Math.round(src[i + 3] * layer.opacity / 100);
        if (sa === 0) {
          continue;
        }
        const da = out[i + 3];
        // 快路径：源不透明（覆盖）或目标全透明（直通）。
        if (sa >= 255 || da === 0) {
          out[i] = src[i];
          out[i + 1] = src[i + 1];
          out[i + 2] = src[i + 2];
          out[i + 3] = sa;
          continue;
        }
        // source-over（直 alpha，整数近似）：
        // oa = sa + da*(255-sa)/255；C = (Cs*sa + Cd*da*(255-sa)/255) / oa。
        const wa = Math.round(da * (255 - sa) / 255);
        const oa = sa + wa;
        if (oa <= 0) {
          continue;
        }
        out[i] = Math.round((src[i] * sa + out[i] * wa) / oa);
        out[i + 1] = Math.round((src[i + 1] * sa + out[i + 1] * wa) / oa);
        out[i + 2] = Math.round((src[i + 2] * sa + out[i + 2] * wa) / oa);
        out[i + 3] = oa;
      }
    }
  }

  /** 洋葱皮叠加（M3）：overlay 以 strengthPct% 强度 source-over 混到 base 上（原位改 base）。
   *  上一帧 30% 透明叠加用 blendOver(base, prev, 30)；零分配（复用调用方缓冲）。 */
  static blendOver(base: Uint8Array, overlay: Uint8Array, strengthPct: number): void {
    const k = Math.max(0, Math.min(100, strengthPct));
    if (k <= 0) {
      return;
    }
    for (let i = 0; i < base.length; i += 4) {
      const oa = overlay[i + 3];
      if (oa === 0) {
        continue;
      }
      const ga = k >= 100 ? oa : Math.round(oa * k / 100);
      if (ga <= 0) {
        continue;
      }
      const ba = base[i + 3];
      if (ga >= 255) {
        base[i] = overlay[i];
        base[i + 1] = overlay[i + 1];
        base[i + 2] = overlay[i + 2];
        base[i + 3] = 255;
        continue;
      }
      if (ba === 0) {
        base[i] = overlay[i];
        base[i + 1] = overlay[i + 1];
        base[i + 2] = overlay[i + 2];
        base[i + 3] = ga;
        continue;
      }
      const wa = Math.round(ba * (255 - ga) / 255);
      const na = ga + wa;
      if (na <= 0) {
        continue;
      }
      base[i] = Math.round((overlay[i] * ga + base[i] * wa) / na);
      base[i + 1] = Math.round((overlay[i + 1] * ga + base[i + 1] * wa) / na);
      base[i + 2] = Math.round((overlay[i + 2] * ga + base[i + 2] * wa) / na);
      base[i + 3] = na;
    }
  }
}
