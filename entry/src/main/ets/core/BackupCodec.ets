/**
 * core/BackupCodec.ets — 备份容器 .pxba 编解码（1.1.0-C 批，开发计划 §15）。
 * 布局：['PXBA' 4B][ver u16 LE = 1][count u32 LE][rawLen u64 LE][zlib 条目流]；
 * 条目（未压缩 rawLen 字节）= count × ([nameLen u16 LE][name ASCII][dataLen u32 LE][data])。
 * rawLen 前置系 zlib.createZipSync 解压需预知目标长度（沿 .pxs 同款包装，ProjectStore 先例）。
 * 安全校验：条目名白名单 [A-Za-z0-9._-]（禁路径分隔/非 ASCII，防恢复写越界沙箱）；
 * 魔数/版本/条目数/长度/截断/重复名全查，坏档返回 undefined 永不崩（§6.4 容错纪律）。
 */

import { zlib } from '@kit.BasicServicesKit';

/** 条目数上限（防损坏文件超大分配）。 */
const BACKUP_MAX_ENTRIES = 4096;
/** 解压后条目流上限（对齐 PXS_RAW_MAX 量级）。 */
const BACKUP_RAW_MAX = 1 << 26;
/** 条目名长度上限（ASCII 字符）。 */
const BACKUP_NAME_MAX = 128;
/** 文件头长度：magic 4 + ver 2 + count 4 + rawLen 8。 */
const BACKUP_HEADER_LEN = 18;
/** 单条目最小长度：nameLen 2 + name 1 + dataLen 4。 */
const BACKUP_ENTRY_MIN = 7;

/** 备份条目：文件名（工程目录内文件名或 palettes.txt）+ 原始字节。 */
export class BackupEntry {
  name: string = '';
  data: Uint8Array = new Uint8Array(0);
}

export class BackupCodec {
  /** 条目名白名单：[A-Za-z0-9._-]，1..128 字符，禁 '.'/'..'（防恢复路径穿越）。 */
  static validName(name: string): boolean {
    if (name.length < 1 || name.length > BACKUP_NAME_MAX) {
      return false;
    }
    if (name === '.' || name === '..') {
      return false;
    }
    for (let i = 0; i < name.length; i++) {
      const c = name.charCodeAt(i);
      const ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A)
        || (c >= 0x61 && c <= 0x7A) || c === 0x2E || c === 0x5F || c === 0x2D;
      if (!ok) {
        return false;
      }
    }
    return true;
  }

  /** 序列化：条目表 → zlib 压缩 → .pxba 字节；坏名/超限/压缩失败 → undefined。 */
  static async serialize(entries: BackupEntry[]): Promise<Uint8Array | undefined> {
    if (entries.length > BACKUP_MAX_ENTRIES) {
      return undefined;
    }
    const seen = new Set<string>();
    let blobLen = 0;
    for (const e of entries) {
      if (!BackupCodec.validName(e.name) || seen.has(e.name)) {
        return undefined;
      }
      seen.add(e.name);
      blobLen += 6 + e.name.length + e.data.length;
    }
    if (blobLen === 0) {
      return BackupCodec.emptyContainer();
    }
    const blob = new Uint8Array(blobLen);
    let p = 0;
    for (const e of entries) {
      blob[p] = e.name.length & 0xFF;
      blob[p + 1] = (e.name.length >> 8) & 0xFF;
      p += 2;
      for (let i = 0; i < e.name.length; i++) {
        blob[p + i] = e.name.charCodeAt(i);
      }
      p += e.name.length;
      blob[p] = e.data.length & 0xFF;
      blob[p + 1] = (e.data.length >> 8) & 0xFF;
      blob[p + 2] = (e.data.length >> 16) & 0xFF;
      blob[p + 3] = (e.data.length >> 24) & 0xFF;
      p += 4;
      blob.set(e.data, p);
      p += e.data.length;
    }
    let dest: ArrayBuffer;
    let compLen = 0;
    try {
      const zip = zlib.createZipSync();
      const bound = await zip.compressBound(blobLen);
      dest = new ArrayBuffer(bound);
      const info = await zip.compress(dest, blob.buffer);
      compLen = info.destLen;
    } catch (e) {
      return undefined;
    }
    if (compLen <= 0) {
      return undefined;
    }
    const out = new Uint8Array(BACKUP_HEADER_LEN + compLen);
    BackupCodec.writeHeader(out, entries.length, blobLen);
    out.set(new Uint8Array(dest, 0, compLen), BACKUP_HEADER_LEN);
    return out;
  }

  /** 解析：.pxba 字节 → 名→字节表；魔数/版本/长度/截断/坏流/坏名/重名任一不过 → undefined。 */
  static async parse(bytes: Uint8Array): Promise<Map<string, Uint8Array> | undefined> {
    if (bytes.length < BACKUP_HEADER_LEN) {
      return undefined;
    }
    if (bytes[0] !== 0x50 || bytes[1] !== 0x58 || bytes[2] !== 0x42 || bytes[3] !== 0x41) {
      return undefined;
    }
    const ver = bytes[4] | (bytes[5] << 8);
    if (ver !== 1) {
      return undefined;
    }
    const count = (bytes[6] | (bytes[7] << 8) | (bytes[8] << 16) | (bytes[9] << 24)) >>> 0;
    if (count > BACKUP_MAX_ENTRIES) {
      return undefined;
    }
    let rawLen = 0;
    for (let i = 17; i >= 10; i--) {
      rawLen = rawLen * 256 + bytes[i];
    }
    if (rawLen > BACKUP_RAW_MAX) {
      return undefined;
    }
    const out = new Map<string, Uint8Array>();
    if (count === 0) {
      if (rawLen !== 0) {
        return undefined;
      }
      return out;
    }
    if (rawLen === 0 || rawLen < count * BACKUP_ENTRY_MIN) {
      return undefined;
    }
    // zlib 接口要求整化缓冲（view 偏移/超长时先拷贝）。
    let src = bytes;
    if (src.byteOffset !== 0 || src.buffer.byteLength !== src.length) {
      const exact = new Uint8Array(src.length);
      exact.set(src);
      src = exact;
    }
    const source = src.buffer.slice(BACKUP_HEADER_LEN);
    const dest = new ArrayBuffer(rawLen);
    try {
      const zip = zlib.createZipSync();
      const info = await zip.uncompress(dest, source);
      if (info.destLen !== rawLen) {
        return undefined;
      }
    } catch (e) {
      return undefined;
    }
    const blob = new Uint8Array(dest);
    let p = 0;
    for (let i = 0; i < count; i++) {
      if (p + 6 > blob.length) {
        return undefined;
      }
      const nameLen = blob[p] | (blob[p + 1] << 8);
      p += 2;
      if (nameLen < 1 || nameLen > BACKUP_NAME_MAX || p + nameLen + 4 > blob.length) {
        return undefined;
      }
      let name = '';
      for (let j = 0; j < nameLen; j++) {
        const c = blob[p + j];
        if (c < 0x21 || c > 0x7E) {
          return undefined;
        }
        name += String.fromCharCode(c);
      }
      p += nameLen;
      const dataLen = (blob[p] | (blob[p + 1] << 8) | (blob[p + 2] << 16) | (blob[p + 3] << 24)) >>> 0;
      p += 4;
      if (p + dataLen > blob.length) {
        return undefined;
      }
      if (!BackupCodec.validName(name) || out.has(name)) {
        return undefined;
      }
      out.set(name, blob.slice(p, p + dataLen));
      p += dataLen;
    }
    if (p !== blob.length) {
      return undefined;
    }
    return out;
  }

  /** 空容器（count = 0 / rawLen = 0，仅 18B 头；空备份往返对称）。 */
  private static emptyContainer(): Uint8Array {
    const out = new Uint8Array(BACKUP_HEADER_LEN);
    BackupCodec.writeHeader(out, 0, 0);
    return out;
  }

  private static writeHeader(out: Uint8Array, count: number, rawLen: number): void {
    out[0] = 0x50;
    out[1] = 0x58;
    out[2] = 0x42;
    out[3] = 0x41;
    out[4] = 1;
    out[5] = 0;
    out[6] = count & 0xFF;
    out[7] = (count >> 8) & 0xFF;
    out[8] = (count >> 16) & 0xFF;
    out[9] = (count >> 24) & 0xFF;
    let v = rawLen;
    for (let i = 0; i < 8; i++) {
      out[10 + i] = v % 256;
      v = Math.floor(v / 256);
    }
  }
}
