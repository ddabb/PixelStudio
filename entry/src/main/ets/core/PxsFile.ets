/**
 * core/PxsFile.ets — .pxs 工程文件序列化（开发计划 §6.4，M4 批）。
 * 未压缩体布局（小端）：
 *   [0..3]   魔数 'PXSP'
 *   [4..5]   格式版本 u16（当前 = 1）
 *   [6..13]  元数据长度 u64
 *   [14..]   元数据（二进制记录，含长度前缀字符串；不落 JSON，规避 ArkTS 反序列化类型断言）
 *   [尾段]   像素流：帧序 × 层序 × w*h*4 RGBA 顺序拼接
 * 落盘时由 ProjectStore 做 zlib 压缩 + 临时文件原子改名（§6.4）。
 * 加载容错：任何结构不一致（魔数/版本/长度/截断/计数）→ 返回 undefined，不抛错不崩溃。
 * 不变量：serialize→parse 往返字段逐一相等（单元测试 1000 次循环锁定，§13.4）。
 */

import { PixelBuffer } from './PixelBuffer';

const PXS_VERSION = 1;
/** 单 cel 像素上限（防损坏文件超大分配；应用实际上限 256×256 = 64K，1.2 大画布）。 */
const PXS_MAX_CELL_PIXELS = 1 << 24;
/** 帧数 × 层数上限（防损坏文件超大乘积）。 */
const PXS_MAX_CELLS = 65536;

export class PxsLayerMeta {
  id: number = 0;
  name: string = '';
  visible: boolean = true;
  opacity: number = 100;
}

export class PxsMeta {
  name: string = '';
  w: number = 0;
  h: number = 0;
  fps: number = 8;
  frameCount: number = 0;
  paletteId: string = '';
  layers: PxsLayerMeta[] = [];
}

export class PxsDoc {
  meta: PxsMeta = new PxsMeta();
  /** cells[帧][层]；parseMeta 通道下为空数组。 */
  cells: PixelBuffer[][] = [];
}

class MetaReader {
  readonly data: Uint8Array;
  pos: number = 0;
  readonly end: number;

  constructor(data: Uint8Array, from: number, end: number) {
    this.data = data;
    this.pos = from;
    this.end = end;
  }

  private need(size: number): boolean {
    return this.pos + size <= this.end;
  }

  readU8(): number {
    if (!this.need(1)) {
      throw new Error('pxs: truncated meta');
    }
    return this.data[this.pos++];
  }

  readU16(): number {
    if (!this.need(2)) {
      throw new Error('pxs: truncated meta');
    }
    const v: number = this.data[this.pos] | (this.data[this.pos + 1] << 8);
    this.pos += 2;
    return v;
  }

  /** 读长度前缀 UTF-8 字符串（容错解码：坏序列替换 U+FFFD）。 */
  readString(): string {
    const len: number = this.readU16();
    if (!this.need(len)) {
      throw new Error('pxs: truncated string');
    }
    const from: number = this.pos;
    this.pos += len;
    return PxsFile.utf8Decode(this.data, from, from + len);
  }
}

export class PxsFile {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /** UTF-8 编码（代理对 → 4 字节；孤立代理 → U+FFFD），字节追加到 out。 */
  static utf8Encode(s: string, out: number[]): void {
    for (let i = 0; i < s.length; i++) {
      const c: number = s.charCodeAt(i);
      if (c < 0x80) {
        out.push(c);
        continue;
      }
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        const lo: number = s.charCodeAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          i++;
          const cp: number = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
          out.push(0xF0 | (cp >> 18));
          out.push(0x80 | ((cp >> 12) & 0x3F));
          out.push(0x80 | ((cp >> 6) & 0x3F));
          out.push(0x80 | (cp & 0x3F));
          continue;
        }
      }
      if (c < 0x800) {
        out.push(0xC0 | (c >> 6));
        out.push(0x80 | (c & 0x3F));
      } else if (c >= 0xD800 && c <= 0xDFFF) {
        // 孤立代理 → U+FFFD
        out.push(0xEF, 0xBF, 0xBD);
      } else {
        out.push(0xE0 | (c >> 12));
        out.push(0x80 | ((c >> 6) & 0x3F));
        out.push(0x80 | (c & 0x3F));
      }
    }
  }

  /** UTF-8 解码（[from, to) 区间；坏序列以 U+FFFD 替换并前进 1 字节，不抛错）。 */
  static utf8Decode(bytes: Uint8Array, from: number, to: number): string {
    let s = '';
    let i = from;
    while (i < to) {
      const b0: number = bytes[i];
      if (b0 < 0x80) {
        s += String.fromCharCode(b0);
        i++;
        continue;
      }
      let cp: number = -1;
      let len: number = 0;
      if ((b0 & 0xE0) === 0xC0) {
        cp = b0 & 0x1F;
        len = 1;
      } else if ((b0 & 0xF0) === 0xE0) {
        cp = b0 & 0x0F;
        len = 2;
      } else if ((b0 & 0xF8) === 0xF0) {
        cp = b0 & 0x07;
        len = 3;
      }
      let ok: boolean = cp >= 0 && i + len < to;
      for (let k = 1; ok && k <= len; k++) {
        const b: number = bytes[i + k];
        if ((b & 0xC0) !== 0x80) {
          ok = false;
        } else {
          cp = (cp << 6) | (b & 0x3F);
        }
      }
      if (!ok || (len === 1 && cp < 0x80) || (len === 2 && cp < 0x800)
        || (len === 3 && cp < 0x10000) || cp > 0x10FFFF) {
        s += '\uFFFD';
        i++;
        continue;
      }
      if (cp >= 0x10000) {
        const v: number = cp - 0x10000;
        s += String.fromCharCode(0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
      } else {
        s += String.fromCharCode(cp);
      }
      i += len + 1;
    }
    return s;
  }

  /** 序列化（编程错误抛 Error；cells[f].length 必须等于层数，cel 尺寸必须等于 w×h）。 */
  static serialize(meta: PxsMeta, cells: PixelBuffer[][]): Uint8Array {
    if (meta.w < 1 || meta.w > 65535 || meta.h < 1 || meta.h > 65535) {
      throw new Error('pxs: invalid size');
    }
    if (meta.fps < 1 || meta.fps > 65535) {
      throw new Error('pxs: invalid fps');
    }
    if (meta.frameCount < 1 || meta.frameCount > 65535 || cells.length !== meta.frameCount) {
      throw new Error('pxs: frame count mismatch');
    }
    const layerCount: number = meta.layers.length;
    if (layerCount < 1 || layerCount > 255) {
      throw new Error('pxs: invalid layer count');
    }
    const metaBytes: number[] = [];
    PxsFile.pushString(metaBytes, meta.name);
    PxsFile.pushU16(metaBytes, meta.w);
    PxsFile.pushU16(metaBytes, meta.h);
    PxsFile.pushU16(metaBytes, meta.fps);
    PxsFile.pushU16(metaBytes, meta.frameCount);
    PxsFile.pushU16(metaBytes, layerCount);
    PxsFile.pushString(metaBytes, meta.paletteId);
    for (const layer of meta.layers) {
      if (layer.id < 0 || layer.id > 65535) {
        throw new Error('pxs: invalid layer id');
      }
      const opacity: number = Math.max(0, Math.min(100, Math.round(layer.opacity)));
      metaBytes.push(layer.id & 0xFF);
      metaBytes.push((layer.id >> 8) & 0xFF);
      metaBytes.push(layer.visible ? 1 : 0);
      metaBytes.push(opacity);
      PxsFile.pushString(metaBytes, layer.name);
    }
    const metaLen: number = metaBytes.length;
    const cellBytes: number = meta.w * meta.h * 4;
    const total: number = 14 + metaLen + cellBytes * meta.frameCount * layerCount;
    const out: Uint8Array = new Uint8Array(total);
    // 文件头
    out[0] = 0x50; // 'P'
    out[1] = 0x58; // 'X'
    out[2] = 0x53; // 'S'
    out[3] = 0x50; // 'P'
    out[4] = PXS_VERSION & 0xFF;
    out[5] = (PXS_VERSION >> 8) & 0xFF;
    // 8B 元数据长度（u64 LE）
    let v: number = metaLen;
    for (let i = 0; i < 8; i++) {
      out[6 + i] = v % 256;
      v = Math.floor(v / 256);
    }
    for (let i = 0; i < metaLen; i++) {
      out[14 + i] = metaBytes[i];
    }
    // 像素流：帧序 × 层序
    let pos: number = 14 + metaLen;
    for (let f = 0; f < meta.frameCount; f++) {
      const row: PixelBuffer[] = cells[f];
      if (row === undefined || row.length !== layerCount) {
        throw new Error('pxs: cell row mismatch');
      }
      for (let l = 0; l < layerCount; l++) {
        const cell: PixelBuffer = row[l];
        if (cell === undefined || cell.w !== meta.w || cell.h !== meta.h || cell.data.length !== cellBytes) {
          throw new Error('pxs: cell size mismatch');
        }
        out.set(cell.data, pos);
        pos += cellBytes;
      }
    }
    return out;
  }

  /** 完整解析（含像素分配）；结构损坏返回 undefined。 */
  static parse(data: Uint8Array): PxsDoc | undefined {
    return PxsFile.parseImpl(data, true);
  }

  /** 仅解析元数据（工程列表用，不分配像素）；同样做全量结构校验。 */
  static parseMeta(data: Uint8Array): PxsMeta | undefined {
    const doc: PxsDoc | undefined = PxsFile.parseImpl(data, false);
    return doc === undefined ? undefined : doc.meta;
  }

  private static parseImpl(data: Uint8Array, withPixels: boolean): PxsDoc | undefined {
    if (data.length < 14) {
      return undefined;
    }
    if (data[0] !== 0x50 || data[1] !== 0x58 || data[2] !== 0x53 || data[3] !== 0x50) {
      return undefined;
    }
    if ((data[4] | (data[5] << 8)) !== PXS_VERSION) {
      return undefined;
    }
    let metaLen = 0;
    for (let i = 7; i >= 0; i--) {
      metaLen = metaLen * 256 + data[6 + i];
    }
    if (metaLen < 8 || 14 + metaLen > data.length) {
      return undefined;
    }
    const reader: MetaReader = new MetaReader(data, 14, 14 + metaLen);
    const meta: PxsMeta = new PxsMeta();
    try {
      meta.name = reader.readString();
      meta.w = reader.readU16();
      meta.h = reader.readU16();
      meta.fps = reader.readU16();
      meta.frameCount = reader.readU16();
      const layerCount: number = reader.readU16();
      meta.paletteId = reader.readString();
      if (meta.w < 1 || meta.h < 1 || meta.w * meta.h > PXS_MAX_CELL_PIXELS) {
        return undefined;
      }
      if (meta.frameCount < 1 || layerCount < 1 || meta.frameCount * layerCount > PXS_MAX_CELLS) {
        return undefined;
      }
      for (let l = 0; l < layerCount; l++) {
        const id: number = reader.readU8() | (reader.readU8() << 8);
        const visible: boolean = reader.readU8() !== 0;
        const opacity: number = Math.min(100, reader.readU8());
        const name: string = reader.readString();
        const layerMeta: PxsLayerMeta = new PxsLayerMeta();
        layerMeta.id = id;
        layerMeta.visible = visible;
        layerMeta.opacity = opacity;
        layerMeta.name = name;
        meta.layers.push(layerMeta);
      }
      if (reader.pos !== 14 + metaLen) {
        return undefined;
      }
    } catch (e) {
      return undefined;
    }
    // 像素流长度必须严丝合缝（损坏文件宁可拒绝不可误读）。
    const cellBytes: number = meta.w * meta.h * 4;
    const pixelBytes: number = cellBytes * meta.frameCount * meta.layers.length;
    if (data.length - (14 + metaLen) !== pixelBytes) {
      return undefined;
    }
    const doc: PxsDoc = new PxsDoc();
    doc.meta = meta;
    if (!withPixels) {
      return doc;
    }
    let pos: number = 14 + metaLen;
    for (let f = 0; f < meta.frameCount; f++) {
      const row: PixelBuffer[] = [];
      for (let l = 0; l < meta.layers.length; l++) {
        const cell: PixelBuffer = new PixelBuffer(meta.w, meta.h);
        cell.data.set(data.subarray(pos, pos + cellBytes));
        pos += cellBytes;
        row.push(cell);
      }
      doc.cells.push(row);
    }
    return doc;
  }

  private static pushU16(out: number[], v: number): void {
    out.push(v & 0xFF);
    out.push((v >> 8) & 0xFF);
  }

  private static pushString(out: number[], s: string): void {
    const bytes: number[] = [];
    PxsFile.utf8Encode(s, bytes);
    if (bytes.length > 65535) {
      throw new Error('pxs: string too long');
    }
    PxsFile.pushU16(out, bytes.length);
    for (const b of bytes) {
      out.push(b);
    }
  }
}
