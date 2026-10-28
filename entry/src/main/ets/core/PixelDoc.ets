/**
 * core/PixelDoc.ets — 文档模型（纯逻辑层，不依赖 ArkUI）。
 * Doc = 尺寸 + 图层表 + 帧数 + cells[帧][层] 像素缓冲；
 * 像素真源 = 每层每帧一个 RGBA Uint8Array（渲染管线直接消费）。
 */

import { PixelBuffer } from './PixelBuffer';

/** 图层数量上限（开发计划 §4.1 P0：≤8 层）。 */
export const MAX_LAYERS = 8;

export class PixelLayer {
  id: number;
  name: string;
  visible: boolean = true;
  opacity: number = 100; // 0-100，步进 10

  constructor(id: number, name: string) {
    this.id = id;
    this.name = name;
  }
}

export class PixelDoc {
  readonly w: number;
  readonly h: number;
  /** layers[0] 为最底层（合成自下而上）。 */
  layers: PixelLayer[] = [];
  frameCount: number = 0;
  /** cells[帧索引][层索引]。 */
  cells: PixelBuffer[][] = [];
  activeLayer: number = 0;
  activeFrame: number = 0;
  private nextLayerId: number = 1;

  constructor(w: number, h: number) {
    this.w = w;
    this.h = h;
    this.addFrame();
    this.addLayer('Layer 1');
  }

  addLayer(name: string): PixelLayer | undefined {
    if (this.layers.length >= MAX_LAYERS) {
      return undefined;
    }
    const layer = new PixelLayer(this.nextLayerId, name);
    this.nextLayerId++;
    this.layers.push(layer);
    for (let f = 0; f < this.frameCount; f++) {
      this.cells[f].push(new PixelBuffer(this.w, this.h));
    }
    return layer;
  }

  /** 删除图层（结构操作）：至少保留 1 层；活动层越界回夹。 */
  deleteLayer(layerIndex: number): boolean {
    if (layerIndex < 0 || layerIndex >= this.layers.length || this.layers.length <= 1) {
      return false;
    }
    this.layers.splice(layerIndex, 1);
    for (let f = 0; f < this.cells.length; f++) {
      this.cells[f].splice(layerIndex, 1);
    }
    if (this.activeLayer >= this.layers.length) {
      this.activeLayer = this.layers.length - 1;
    }
    return true;
  }

  /** 相邻交换图层（含各帧 cel）；dir=+1 向堆顶（合成在上），-1 向堆底。 */
  moveLayer(layerIndex: number, dir: number): boolean {
    const to = layerIndex + dir;
    if (layerIndex < 0 || layerIndex >= this.layers.length || to < 0 || to >= this.layers.length) {
      return false;
    }
    const layer = this.layers[layerIndex];
    this.layers[layerIndex] = this.layers[to];
    this.layers[to] = layer;
    for (let f = 0; f < this.cells.length; f++) {
      const row = this.cells[f];
      const cel = row[layerIndex];
      row[layerIndex] = row[to];
      row[to] = cel;
    }
    if (this.activeLayer === layerIndex) {
      this.activeLayer = to;
    } else if (this.activeLayer === to) {
      this.activeLayer = layerIndex;
    }
    return true;
  }

  addFrame(): void {
    const row: PixelBuffer[] = [];
    for (let li = 0; li < this.layers.length; li++) {
      row.push(new PixelBuffer(this.w, this.h));
    }
    this.cells.push(row);
    this.frameCount = this.cells.length;
  }

  /** 结构性插入帧行（撤销重放通道）：行长度须等于层数，index 允许 0..frameCount。 */
  insertFrame(index: number, row: PixelBuffer[]): boolean {
    if (index < 0 || index > this.cells.length || row.length !== this.layers.length) {
      return false;
    }
    this.cells.splice(index, 0, row);
    this.frameCount = this.cells.length;
    return true;
  }

  /** 删除帧（至少保留 1 帧）；活动帧越界回夹。 */
  removeFrame(index: number): boolean {
    if (index < 0 || index >= this.cells.length || this.cells.length <= 1) {
      return false;
    }
    this.cells.splice(index, 1);
    this.frameCount = this.cells.length;
    if (this.activeFrame >= this.frameCount) {
      this.activeFrame = this.frameCount - 1;
    }
    return true;
  }

  /** 相邻交换帧（含各层 cel）；活动帧随行移动。 */
  swapFrame(index: number, dir: number): boolean {
    const to = index + dir;
    if (index < 0 || index >= this.cells.length || to < 0 || to >= this.cells.length) {
      return false;
    }
    const row = this.cells[index];
    this.cells[index] = this.cells[to];
    this.cells[to] = row;
    if (this.activeFrame === index) {
      this.activeFrame = to;
    } else if (this.activeFrame === to) {
      this.activeFrame = index;
    }
    return true;
  }

  getCell(frameIndex: number, layerIndex: number): PixelBuffer | undefined {
    if (frameIndex < 0 || frameIndex >= this.frameCount) {
      return undefined;
    }
    if (layerIndex < 0 || layerIndex >= this.layers.length) {
      return undefined;
    }
    return this.cells[frameIndex][layerIndex];
  }

  activeCell(): PixelBuffer | undefined {
    return this.getCell(this.activeFrame, this.activeLayer);
  }
}
