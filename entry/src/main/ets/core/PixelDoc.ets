/**
 * core/PixelDoc.ets — 文档模型（纯逻辑层，不依赖 ArkUI）。
 * Doc = 尺寸 + 图层表 + 帧数 + cells[帧][层] 像素缓冲；
 * 像素真源 = 每层每帧一个 RGBA Uint8Array（渲染管线直接消费）。
 */

import { PixelBuffer } from './PixelBuffer';

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

  addLayer(name: string): PixelLayer {
    const layer = new PixelLayer(this.nextLayerId, name);
    this.nextLayerId++;
    this.layers.push(layer);
    for (let f = 0; f < this.frameCount; f++) {
      this.cells[f].push(new PixelBuffer(this.w, this.h));
    }
    return layer;
  }

  addFrame(): void {
    const row: PixelBuffer[] = [];
    for (let li = 0; li < this.layers.length; li++) {
      row.push(new PixelBuffer(this.w, this.h));
    }
    this.cells.push(row);
    this.frameCount = this.cells.length;
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
