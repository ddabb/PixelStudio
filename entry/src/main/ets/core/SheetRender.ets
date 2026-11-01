/**
 * core/SheetRender.ets — 精灵图集渲染（纯逻辑层，1.1.0-D 导出扩展，开发计划 §15）。
 * 全帧 Compose 合成后水平拼接单条 PNG（透明保留，帧间无间距）+ 坐标 JSON
 * （帧数/单帧尺寸/条图尺寸/fps/各帧 x 偏移，游戏引擎读图即用）。
 */

import { PixelDoc } from './PixelDoc';
import { Compose } from './Compose';

/** 精灵条图（RGBA，长度 = w*h*4，全帧水平拼接）。 */
export class SheetStrip {
  buf: Uint8Array;
  w: number;
  h: number;

  constructor(w: number, h: number) {
    this.w = w;
    this.h = h;
    this.buf = new Uint8Array(w * h * 4);
  }
}

/** 图集坐标元数据（JSON.stringify 字段序即类声明序）。 */
export class AtlasMeta {
  frames: number = 0;
  frameW: number = 0;
  frameH: number = 0;
  sheetW: number = 0;
  sheetH: number = 0;
  fps: number = 8;
  /** 条图文件名（与 PNG 配套分发）。 */
  sheet: string = '';
  /** 各帧在条图中的 x 偏移。 */
  xs: number[] = [];
}

export class SheetRender {
  /** 全帧合成 + 列块拷贝水平拼接；复用单帧缓冲（零额外帧分配）。 */
  static renderStrip(doc: PixelDoc): SheetStrip {
    const fw = doc.w;
    const fh = doc.h;
    const n = doc.frameCount;
    const strip = new SheetStrip(fw * n, fh);
    const frameBuf = new Uint8Array(fw * fh * 4);
    for (let f = 0; f < n; f++) {
      Compose.composeFrame(doc, f, frameBuf);
      for (let y = 0; y < fh; y++) {
        const srcOff = y * fw * 4;
        strip.buf.set(frameBuf.subarray(srcOff, srcOff + fw * 4), (y * strip.w + f * fw) * 4);
      }
    }
    return strip;
  }

  /** 坐标 JSON（与条图 PNG 同名 .json，供引擎/下游工具解析）。 */
  static atlasJson(doc: PixelDoc, sheetFileName: string, fps: number): string {
    const meta = new AtlasMeta();
    meta.frames = doc.frameCount;
    meta.frameW = doc.w;
    meta.frameH = doc.h;
    meta.sheetW = doc.w * doc.frameCount;
    meta.sheetH = doc.h;
    meta.fps = Math.max(1, Math.round(fps));
    meta.sheet = sheetFileName;
    for (let f = 0; f < doc.frameCount; f++) {
      meta.xs.push(f * doc.w);
    }
    return JSON.stringify(meta);
  }
}
