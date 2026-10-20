/**
 * core/PixelBuffer.ets — RGBA 像素缓冲封装（纯逻辑层，不依赖 ArkUI）。
 * 字节序：RGBA（R 在低址），与 image.PixelMapFormat.RGBA_8888 缓冲一致，
 * 可零拷贝喂给 createPixelMap / writeBufferToPixels。
 * 颜色 packed 表示：0xAARRGGBB（与 ArkUI Color 数值一致）。
 */

export class PixelBuffer {
  readonly w: number;
  readonly h: number;
  readonly data: Uint8Array;

  constructor(w: number, h: number) {
    this.w = w;
    this.h = h;
    this.data = new Uint8Array(w * h * 4);
  }

  static fromData(w: number, h: number, data: Uint8Array): PixelBuffer {
    if (data.length !== w * h * 4) {
      throw new Error('PixelBuffer.fromData size mismatch');
    }
    const buf = new PixelBuffer(w, h);
    buf.data.set(data);
    return buf;
  }

  inBounds(x: number, y: number): boolean {
    return x >= 0 && y >= 0 && x < this.w && y < this.h;
  }

  private idx(x: number, y: number): number {
    return (y * this.w + x) * 4;
  }

  /** 取 packed ARGB；越界返回 0（全透明）。 */
  getPx(x: number, y: number): number {
    if (!this.inBounds(x, y)) {
      return 0;
    }
    const i = this.idx(x, y);
    const d = this.data;
    return (((d[i + 3] << 24) | (d[i] << 16) | (d[i + 1] << 8) | d[i + 2]) >>> 0);
  }

  /** 写 packed ARGB；越界忽略（画布边缘安全落笔）。 */
  setPx(x: number, y: number, argb: number): void {
    if (!this.inBounds(x, y)) {
      return;
    }
    const i = this.idx(x, y);
    const d = this.data;
    d[i] = (argb >>> 16) & 0xFF;
    d[i + 1] = (argb >>> 8) & 0xFF;
    d[i + 2] = argb & 0xFF;
    d[i + 3] = (argb >>> 24) & 0xFF;
  }

  clear(): void {
    this.data.fill(0);
  }

  clone(): PixelBuffer {
    const buf = new PixelBuffer(this.w, this.h);
    buf.data.set(this.data);
    return buf;
  }

  /** 复制矩形子区域（越界自动裁剪），返回新缓冲（浅尺寸 = 请求尺寸，裁掉区域为透明）。 */
  copyRegion(x: number, y: number, rw: number, rh: number): PixelBuffer {
    const out = new PixelBuffer(Math.max(0, rw), Math.max(0, rh));
    for (let oy = 0; oy < out.h; oy++) {
      const sy = y + oy;
      if (sy < 0 || sy >= this.h) {
        continue;
      }
      for (let ox = 0; ox < out.w; ox++) {
        const sx = x + ox;
        if (sx < 0 || sx >= this.w) {
          continue;
        }
        const si = this.idx(sx, sy);
        const ti = out.idx(ox, oy);
        out.data[ti] = this.data[si];
        out.data[ti + 1] = this.data[si + 1];
        out.data[ti + 2] = this.data[si + 2];
        out.data[ti + 3] = this.data[si + 3];
      }
    }
    return out;
  }

  /** 将 src 整块像素拷贝到 (dx, dy)（越界自动裁剪；覆盖式，含透明像素整体替换）。 */
  blit(src: PixelBuffer, dx: number, dy: number): void {
    for (let sy = 0; sy < src.h; sy++) {
      const ty = dy + sy;
      if (ty < 0 || ty >= this.h) {
        continue;
      }
      for (let sx = 0; sx < src.w; sx++) {
        const tx = dx + sx;
        if (tx < 0 || tx >= this.w) {
          continue;
        }
        const si = (sy * src.w + sx) * 4;
        const ti = this.idx(tx, ty);
        this.data[ti] = src.data[si];
        this.data[ti + 1] = src.data[si + 1];
        this.data[ti + 2] = src.data[si + 2];
        this.data[ti + 3] = src.data[si + 3];
      }
    }
  }
}
