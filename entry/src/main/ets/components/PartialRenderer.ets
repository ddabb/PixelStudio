/**
 * components/PartialRenderer.ets — 笔触局部渲染辅助（1.2 大画布，开发计划 §6.5 P1 手段）。
 * 从 CanvasView 渲染管线拆出：diff 活动 cel vs 基线得脏矩形，仅重合成该区域（含
 * 洋葱皮与吸色副本同步），区域外像素沿用 composeBuf 既有内容；无变化零成本跳过。
 * 场景签名（帧/播放/洋葱/图层可见性与不透明度）变化即不可局部，调用方回退整帧渲染。
 * PixelMap 重建留在 CanvasView（@Local 状态驱动已挂载 Image 刷新，§6.6）。
 */

import { PixelDoc } from '../core/PixelDoc';
import { Compose } from '../core/Compose';
import { EditorSession } from '../viewmodel/EditorSession';

/** 洋葱皮：上一帧 30% 透明叠加（开发计划 §4.1；与 CanvasView 渲染管线同值）。 */
const ONION_STRENGTH_PCT = 30;

export class PartialRenderer {
  private readonly doc: PixelDoc;
  private readonly session: EditorSession;
  private readonly composeBuf: Uint8Array;
  private readonly onionBuf: Uint8Array;
  private readonly pickBuf: Uint8Array;
  /** 笔触期间基线：上次渲染时活动 cel 快照（diff 出脏矩形；整帧渲染后同步刷新）。 */
  private strokeShown: Uint8Array | undefined = undefined;
  /** 上次整帧渲染的场景签名。 */
  private lastSig: number = -1;

  constructor(doc: PixelDoc, session: EditorSession, composeBuf: Uint8Array,
    onionBuf: Uint8Array, pickBuf: Uint8Array) {
    this.doc = doc;
    this.session = session;
    this.composeBuf = composeBuf;
    this.onionBuf = onionBuf;
    this.pickBuf = pickBuf;
  }

  /** 合成场景签名：帧/播放/洋葱/图层可见性与不透明度；变化必须整帧渲染。 */
  sig(): number {
    let s: number = (this.doc.activeFrame * 4 + (this.session.playing ? 2 : 0)
      + (this.session.onionSkin ? 1 : 0)) % 1000003;
    for (let li = 0; li < this.doc.layers.length; li++) {
      const layer = this.doc.layers[li];
      s = (s * 7 + (layer.visible ? 1 : 0)) % 1000003;
      s = (s * 13 + layer.opacity) % 1000003;
    }
    return s;
  }

  /** 局部通道可用：基线就绪 + 缓冲尺寸匹配 + 场景签名未变。 */
  canPartial(): boolean {
    const cell = this.doc.activeCell();
    return this.strokeShown !== undefined
      && cell !== undefined
      && this.strokeShown.length === cell.data.length
      && this.composeBuf.length === cell.data.length
      && this.lastSig === this.sig();
  }

  /** 落笔：重建基线（形状/选区工具落笔不整帧渲染，从此快照出发做局部 diff）。 */
  beginStroke(cellData: Uint8Array): void {
    this.strokeShown = cellData.slice();
  }

  /** 收笔/回滚：丢弃基线（下笔重建）。 */
  endStroke(): void {
    this.strokeShown = undefined;
  }

  /** 整帧渲染完成后调用：记录场景签名 + 同步基线（笔触中的整帧渲染保持 diff 连续）。 */
  afterFullRender(): void {
    this.lastSig = this.sig();
    const cell = this.doc.activeCell();
    if (cell === undefined) {
      return;
    }
    if (this.strokeShown !== undefined && this.strokeShown.length === cell.data.length) {
      this.strokeShown.set(cell.data);
    }
  }

  /** 局部渲染（canPartial 为真时调用）：diff 活动 cel vs 基线得脏矩形，仅重合成该
   *  区域（含洋葱皮与吸色副本）并同步基线脏区域；返回 true = composeBuf 已更新
   *  需重建 PixelMap，false = 无变化（吸管滑过/空框选）零成本跳过。 */
  renderPartial(): boolean {
    const cell = this.doc.activeCell();
    const shown = this.strokeShown;
    if (cell === undefined || shown === undefined || shown.length !== cell.data.length) {
      return false;
    }
    const dw = this.doc.w;
    const dh = this.doc.h;
    const data = cell.data;
    // 1) diff 脏矩形包围盒（笔触/形状预览/选区拖动/镜像章全兼容）。
    let minX = dw;
    let minY = dh;
    let maxX = -1;
    let maxY = -1;
    for (let py = 0; py < dh; py++) {
      const row = py * dw;
      for (let px = 0; px < dw; px++) {
        const i = (row + px) * 4;
        if (data[i] !== shown[i] || data[i + 1] !== shown[i + 1]
          || data[i + 2] !== shown[i + 2] || data[i + 3] !== shown[i + 3]) {
          if (px < minX) {
            minX = px;
          }
          if (px > maxX) {
            maxX = px;
          }
          if (py < minY) {
            minY = py;
          }
          if (py > maxY) {
            maxY = py;
          }
        }
      }
    }
    if (maxX < 0) {
      return false;
    }
    const x = minX;
    const y = minY;
    const w = maxX - minX + 1;
    const h = maxY - minY + 1;
    // 2) 区域重合成 + 吸色副本同步区域（pickBuf = 洋葱 blend 前的当前帧合成）。
    Compose.composeRegion(this.doc, this.doc.activeFrame, x, y, w, h, this.composeBuf);
    for (let yy = y; yy < y + h; yy++) {
      const rowStart = (yy * dw + x) * 4;
      this.pickBuf.set(this.composeBuf.subarray(rowStart, rowStart + w * 4), rowStart);
    }
    // 3) 洋葱皮区域叠加（onionBuf = 上一帧合成，笔触期间不变）。
    if (this.session.onionSkin && !this.session.playing
      && this.doc.activeFrame > 0 && this.onionBuf.length === this.composeBuf.length) {
      Compose.blendOverRegion(this.composeBuf, this.onionBuf, ONION_STRENGTH_PCT,
        dw, x, y, w, h);
    }
    // 4) 基线同步脏区域。
    for (let yy = y; yy < y + h; yy++) {
      const rowStart = (yy * dw + x) * 4;
      shown.set(data.subarray(rowStart, rowStart + w * 4), rowStart);
    }
    return true;
  }
}
