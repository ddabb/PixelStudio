/**
 * viewmodel/ProjectStore.ets — 工程持久化（M4 批，开发计划 §6.4）。
 * 目录：{filesDir}/pixel/projects/{id}.pxs。
 * 文件布局：[8B 未压缩长度 u64 LE][zlib 缓冲区压缩流]；
 * 落盘 = 临时文件 + 原子 rename（防半写损坏，§6.4 容错纪律）。
 * 容错：解压/解析任何失败 → undefined / corrupt 标记，不崩溃；
 * 恢复 = 工程列表读取最近存档（自动保存周期 30s，§4.1 杀进程恢复 ≤30s）。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { PixelDoc, PixelLayer } from '../core/PixelDoc';
import { PixelBuffer } from '../core/PixelBuffer';
import { Compose } from '../core/Compose';
import { PxsFile, PxsDoc, PxsMeta, PxsLayerMeta } from '../core/PxsFile';
import { BackupCodec } from '../core/BackupCodec';

/** 单工程未压缩体上限（防损坏文件超大分配）。 */
const PXS_RAW_MAX = 1 << 26;
/** 缩略图边长上限（像素）；首帧合成后最近邻降采样。 */
export const THUMB_MAX = 64;
/** 随包示例工程 id（rawfile 内 {id}.pxs / {id}.thumb 边车；星夜小猫 / 落日海岸 / 果冻史莱姆）。 */
export const DEMO_IDS: string[] = ['demo_cat', 'demo_sunset', 'demo_slime'];

/** 工程列表条目（列表页展示；corrupt = 解压/解析失败的灰显项）。 */
export class ProjectRecord {
  id: string = '';
  name: string = '';
  w: number = 0;
  h: number = 0;
  fps: number = 8;
  frameCount: number = 0;
  layerCount: number = 0;
  updatedAt: number = 0;
  corrupt: boolean = false;
  /** 缩略图原始字节（[w LE16][h LE16][RGBA]，边长 ≤ THUMB_MAX）；无 = undefined。 */
  thumb: Uint8Array | undefined = undefined;
}

/** 示例工程恢复结果（restored = 本次新落盘数；failed = 缺失但恢复失败数）。 */
export class DemoRestoreResult {
  restored: number = 0;
  failed: number = 0;
}

export class ProjectStore {
  private context: common.Context | undefined = undefined;

  init(context: common.Context): void {
    this.context = context;
  }

  /** 新工程 id：时间基 36 进制 + 随机尾，同毫秒不撞。 */
  static newId(): string {
    const rand: number = Math.floor(Math.random() * 46656); // 36^3
    return `p${Date.now().toString(36)}${rand.toString(36).padStart(3, '0')}`;
  }

  /** 工程名清洗：去分隔符/井号/换行（防 .pxs 元数据被破坏），限 64 字符。 */
  static sanitizeName(name: string): string {
    return name.replace('|', '/').replace('#', '').replace('\n', ' ').trim().substring(0, 64);
  }

  /** 示例工程确定性排序秩（DEMO_IDS 序，星夜小猫最前）；非示例 = DEMO_IDS.length（mtime 并列时靠后）。 */
  static demoRank(id: string): number {
    const rank = DEMO_IDS.indexOf(id);
    return rank < 0 ? DEMO_IDS.length : rank;
  }

  // ---------- 路径 ----------

  private dir(): string {
    const ctx = this.context;
    if (ctx === undefined) {
      return '';
    }
    return `${ctx.filesDir}/pixel/projects`;
  }

  private pathFor(id: string): string {
    return `${this.dir()}/${id}.pxs`;
  }

  private thumbPathFor(id: string): string {
    return `${this.dir()}/${id}.thumb`;
  }

  private ensureDir(): boolean {
    const dir = this.dir();
    if (dir.length === 0) {
      return false;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // ---------- 文件 IO（小工具） ----------

  private static readFileBytes(path: string): Uint8Array | undefined {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const size = fs.statSync(file.fd).size;
        if (size <= 0) {
          return undefined;
        }
        const buf = new ArrayBuffer(size);
        // 常规文件单次 read 即读满；读不满视为截断损坏。
        const n = fs.readSync(file.fd, buf, { length: size });
        if (n !== size) {
          return undefined;
        }
        return new Uint8Array(buf);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return undefined;
    }
  }

  private static writeFileBytes(path: string, bytes: Uint8Array): boolean {
    try {
      // 写入体必须是精确缓冲（view 偏移/超长时先拷贝整化）。
      let body = bytes;
      if (bytes.byteOffset !== 0 || bytes.buffer.byteLength !== bytes.length) {
        const exact = new Uint8Array(bytes.length);
        exact.set(bytes);
        body = exact;
      }
      const file = fs.openSync(path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const n = fs.writeSync(file.fd, body.buffer, { length: body.length });
        return n === body.length;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return false;
    }
  }

  // ---------- 缩略图边车（{id}.thumb：[w LE16][h LE16][RGBA]，边长 ≤ THUMB_MAX） ----------

  /** 首帧合成 + 最近邻降采样 → 缩略图字节；结构异常返回 undefined。 */
  static composeThumbBytes(meta: PxsMeta, cells: PixelBuffer[][]): Uint8Array | undefined {
    if (meta.w < 1 || meta.h < 1 || cells.length < 1 || cells[0].length < 1) {
      return undefined;
    }
    const td: PixelDoc = new PixelDoc(meta.w, meta.h);
    td.layers.length = 0;
    td.cells.length = 0;
    td.frameCount = 0;
    for (const lm of meta.layers) {
      const layer: PixelLayer = new PixelLayer(lm.id, lm.name);
      layer.visible = lm.visible;
      layer.opacity = lm.opacity;
      td.layers.push(layer);
    }
    if (td.layers.length === 0) {
      return undefined;
    }
    td.addFrame();
    const row: PixelBuffer[] = cells[0];
    for (let l = 0; l < td.layers.length && l < row.length; l++) {
      td.cells[0][l].data.set(row[l].data);
    }
    const full: Uint8Array = new Uint8Array(meta.w * meta.h * 4);
    Compose.composeFrame(td, 0, full);
    const scale: number = Math.max(1, Math.ceil(Math.max(meta.w, meta.h) / THUMB_MAX));
    const tw: number = Math.max(1, Math.ceil(meta.w / scale));
    const th: number = Math.max(1, Math.ceil(meta.h / scale));
    const out: Uint8Array = new Uint8Array(4 + tw * th * 4);
    out[0] = tw & 0xFF;
    out[1] = (tw >> 8) & 0xFF;
    out[2] = th & 0xFF;
    out[3] = (th >> 8) & 0xFF;
    for (let y = 0; y < th; y++) {
      const sy: number = Math.min(meta.h - 1, y * scale);
      for (let x = 0; x < tw; x++) {
        const sx: number = Math.min(meta.w - 1, x * scale);
        const si: number = (sy * meta.w + sx) * 4;
        const di: number = 4 + (y * tw + x) * 4;
        out[di] = full[si];
        out[di + 1] = full[si + 1];
        out[di + 2] = full[si + 2];
        out[di + 3] = full[si + 3];
      }
    }
    return out;
  }

  /** 写缩略图边车（尽力而为：失败不影响主存档）。 */
  private writeThumb(id: string, meta: PxsMeta, cells: PixelBuffer[][]): void {
    const bytes = ProjectStore.composeThumbBytes(meta, cells);
    if (bytes === undefined) {
      return;
    }
    ProjectStore.writeFileBytes(this.thumbPathFor(id), bytes);
  }

  /** 缩略图字节合法性（[w LE16][h LE16][RGBA]，边长 1..THUMB_MAX，长度精确匹配）。 */
  static checkThumbBytes(bytes: Uint8Array): boolean {
    if (bytes.length < 4) {
      return false;
    }
    const tw: number = bytes[0] | (bytes[1] << 8);
    const th: number = bytes[2] | (bytes[3] << 8);
    return tw >= 1 && th >= 1 && tw <= THUMB_MAX && th <= THUMB_MAX
      && bytes.length === 4 + tw * th * 4;
  }

  /** 读缩略图边车；缺失/损坏返回 undefined。 */
  readThumb(id: string): Uint8Array | undefined {
    if (id.length === 0) {
      return undefined;
    }
    const bytes = ProjectStore.readFileBytes(this.thumbPathFor(id));
    if (bytes === undefined || !ProjectStore.checkThumbBytes(bytes)) {
      return undefined;
    }
    return bytes;
  }

  /** 读 {id}.pxs → 解压出未压缩体；任何环节失败返回 undefined。 */
  private async readRaw(id: string): Promise<Uint8Array | undefined> {
    const path = this.pathFor(id);
    if (id.length === 0 || path.length === 0) {
      return undefined;
    }
    try {
      if (!fs.accessSync(path)) {
        return undefined;
      }
    } catch (e) {
      return undefined;
    }
    const fileBytes = ProjectStore.readFileBytes(path);
    if (fileBytes === undefined) {
      return undefined;
    }
    return ProjectStore.unwrapBytes(fileBytes);
  }

  /** 包装字节（[8B 未压缩长度 LE][zlib 流]）→ 未压缩体；任何环节失败返回 undefined。 */  private static async unwrapBytes(wrapped: Uint8Array): Promise<Uint8Array | undefined> {
    if (wrapped.length < 9) {
      return undefined;
    }
    let rawLen = 0;
    for (let i = 7; i >= 0; i--) {
      rawLen = rawLen * 256 + wrapped[i];
    }
    if (rawLen <= 0 || rawLen > PXS_RAW_MAX) {
      return undefined;
    }
    // zlib 接口要求整化缓冲（view 偏移/超长时先拷贝）。
    let src = wrapped;
    if (src.byteOffset !== 0 || src.buffer.byteLength !== src.length) {
      const exact = new Uint8Array(src.length);
      exact.set(src);
      src = exact;
    }
    const dest = new ArrayBuffer(rawLen);
    const source = src.buffer.slice(8);
    try {
      const zip = zlib.createZipSync();
      const info = await zip.uncompress(dest, source);
      if (info.destLen !== rawLen) {
        return undefined;
      }
    } catch (e) {
      return undefined;
    }
    return new Uint8Array(dest);
  }

  // ---------- 对外 API ----------

  /** 工程列表（updatedAt 降序；并列时示例工程按 DEMO_IDS 序在前；损坏文件以 corrupt 条目出现，不吞不崩）。 */
  async list(): Promise<ProjectRecord[]> {
    if (!this.ensureDir()) {
      return [];
    }
    const out: ProjectRecord[] = [];
    let names: string[] = [];
    try {
      names = fs.listFileSync(this.dir());
    } catch (e) {
      return out;
    }
    for (const name of names) {
      if (!name.endsWith('.pxs')) {
        continue;
      }
      const id = name.substring(0, name.length - 4);
      const rec = new ProjectRecord();
      rec.id = id;
      let mtime = 0;
      try {
        mtime = fs.statSync(this.pathFor(id)).mtime;
      } catch (e) {
        mtime = 0;
      }
      rec.updatedAt = mtime;
      const raw = await this.readRaw(id);
      if (raw === undefined) {
        rec.corrupt = true;
        rec.name = id;
        out.push(rec);
        continue;
      }
      const meta = PxsFile.parseMeta(raw);
      if (meta === undefined) {
        rec.corrupt = true;
        rec.name = id;
        out.push(rec);
        continue;
      }
      rec.name = meta.name;
      rec.w = meta.w;
      rec.h = meta.h;
      rec.fps = meta.fps;
      rec.frameCount = meta.frameCount;
      rec.layerCount = meta.layers.length;
      rec.thumb = this.readThumb(id);
      out.push(rec);
    }
    out.sort((a: ProjectRecord, b: ProjectRecord): number =>
      (b.updatedAt - a.updatedAt) || (ProjectStore.demoRank(a.id) - ProjectStore.demoRank(b.id)));
    return out;
  }

  /** 完整加载（解压 + 解析像素）。 */
  async loadDoc(id: string): Promise<PxsDoc | undefined> {
    const raw = await this.readRaw(id);
    if (raw === undefined) {
      return undefined;
    }
    return PxsFile.parse(raw);
  }

  /**
   * 保存：serialize → zlib 压缩 → 写临时文件 → 原子 rename。
   * rename 失败时回退“删目标再改名”（仅在非常规文件系统行为下触发的兜底路径）。
   */
  async saveDoc(id: string, meta: PxsMeta, cells: PixelBuffer[][]): Promise<boolean> {
    if (id.length === 0 || !this.ensureDir()) {
      return false;
    }
    let raw: Uint8Array;
    try {
      raw = PxsFile.serialize(meta, cells);
    } catch (e) {
      return false;
    }
    let dest: ArrayBuffer;
    let compLen = 0;
    try {
      const zip = zlib.createZipSync();
      const bound = await zip.compressBound(raw.length);
      dest = new ArrayBuffer(bound);
      const info = await zip.compress(dest, raw.buffer);
      compLen = info.destLen;
    } catch (e) {
      return false;
    }
    if (compLen <= 0) {
      return false;
    }
    const out = new Uint8Array(8 + compLen);
    let v = raw.length;
    for (let i = 0; i < 8; i++) {
      out[i] = v % 256;
      v = Math.floor(v / 256);
    }
    out.set(new Uint8Array(dest, 0, compLen), 8);
    const finalPath = this.pathFor(id);
    const tmpPath = `${finalPath}.tmp`;
    if (!ProjectStore.writeFileBytes(tmpPath, out)) {
      return false;
    }
    try {
      fs.renameSync(tmpPath, finalPath);
      this.writeThumb(id, meta, cells);
      return true;
    } catch (e) {
      try {
        fs.unlinkSync(finalPath);
        fs.renameSync(tmpPath, finalPath);
        this.writeThumb(id, meta, cells);
        return true;
      } catch (e2) {
        return false;
      }
    }
  }

  /** 复制工程（读改写全量副本 + 缩略图随存）；名称追加后缀；失败返回 undefined。 */
  async duplicate(id: string, nameSuffix: string): Promise<string | undefined> {
    const pxs = await this.loadDoc(id);
    if (pxs === undefined) {
      return undefined;
    }
    const composed = `${pxs.meta.name} ${nameSuffix}`.trim();
    const name = ProjectStore.sanitizeName(composed);
    if (name.length > 0) {
      pxs.meta.name = name;
    }
    const newId = ProjectStore.newId();
    const ok = await this.saveDoc(newId, pxs.meta, pxs.cells);
    return ok ? newId : undefined;
  }

  /** 重命名（读改写全量落盘）；损坏/缺失工程返回 false。 */
  async rename(id: string, name: string): Promise<boolean> {
    const n = ProjectStore.sanitizeName(name);
    if (n.length === 0) {
      return false;
    }
    const pxs = await this.loadDoc(id);
    if (pxs === undefined) {
      return false;
    }
    pxs.meta.name = n;
    return this.saveDoc(id, pxs.meta, pxs.cells);
  }

  /** 删除工程文件；不存在/失败返回 false。 */
  remove(id: string): boolean {
    const path = this.pathFor(id);
    if (id.length === 0 || path.length === 0) {
      return false;
    }
    try {
      if (!fs.accessSync(path)) {
        return false;
      }
    } catch (e) {
      return false;
    }
    try {
      fs.unlinkSync(path);
    } catch (e) {
      return false;
    }
    // 缩略图边车随主档清理（尽力而为）。
    try {
      if (fs.accessSync(this.thumbPathFor(id))) {
        fs.unlinkSync(this.thumbPathFor(id));
      }
    } catch (e) {
    }
    return true;
  }

  // ---------- 备份/恢复（.pxba 旁路容器，1.1.0-C；恢复 = 不存在才写，非破坏） ----------

  /** 备份：工程目录全部文件名（.pxs + .thumb；.tmp 残料/非常规名由调用方滤除）。 */
  listProjectFileNames(): string[] {
    if (!this.ensureDir()) {
      return [];
    }
    try {
      return fs.listFileSync(this.dir());
    } catch (e) {
      return [];
    }
  }

  /** 备份：按名读工程目录文件字节；坏名/缺失/IO 失败 → undefined。 */
  readProjectFileBytes(name: string): Uint8Array | undefined {
    if (!BackupCodec.validName(name)) {
      return undefined;
    }
    return ProjectStore.readFileBytes(`${this.dir()}/${name}`);
  }

  /** 恢复：不存在才写（非破坏性；已存在/坏名/失败 → false 不覆盖）。 */
  writeProjectFileIfAbsent(name: string, bytes: Uint8Array): boolean {
    if (!BackupCodec.validName(name) || !this.ensureDir()) {
      return false;
    }
    const path = `${this.dir()}/${name}`;
    try {
      if (fs.accessSync(path)) {
        return false;
      }
    } catch (e) {
      // 查询异常按缺失处理；落盘失败兜底 false。
    }
    return ProjectStore.writeFileBytes(path, bytes);
  }

  // ---------- 示例工程（rawfile 随包演示；商店素材与新用户引导共用） ----------

  /**
   * 恢复缺失的示例工程（幂等：已存在跳过不覆盖用户数据）。
   * 校验：.pxs 解包 + 完整解析通过才落盘（防打包异常文件污染列表通道）；
   * .thumb 边车合法才随存（缺失/损坏不阻断主档）。
   * 排序：按优先级反序写入（星夜小猫末位落盘 = mtime 最新）；mtime 并列（同秒/时钟粒度粗）
   * 时由 list() 以示例秩决胜——两种时间精度下展示顺序一致（星夜小猫置顶）。
   */
  async restoreDemos(): Promise<DemoRestoreResult> {
    const out = new DemoRestoreResult();
    if (this.context === undefined || !this.ensureDir()) {
      out.failed = DEMO_IDS.length;
      return out;
    }
    const missing: string[] = [];
    for (const id of DEMO_IDS) {
      try {
        if (!fs.accessSync(this.pathFor(id))) {
          missing.push(id);
        }
      } catch (e) {
        missing.push(id);
      }
    }
    for (let i = missing.length - 1; i >= 0; i--) {
      if (await this.restoreOneDemo(missing[i])) {
        out.restored++;
      } else {
        out.failed++;
      }
    }
    return out;
  }

  /** 单个示例工程 rawfile → 沙箱（写原包装字节，免二次压缩）。 */
  private async restoreOneDemo(id: string): Promise<boolean> {
    const ctx = this.context;
    if (ctx === undefined) {
      return false;
    }
    let wrapped: Uint8Array;
    try {
      wrapped = await ctx.resourceManager.getRawFileContent(`${id}.pxs`);
    } catch (e) {
      return false;
    }
    const raw = await ProjectStore.unwrapBytes(wrapped);
    if (raw === undefined) {
      return false;
    }
    // 完整解析校验（元数据 + 像素流长度）。
    const pxs = PxsFile.parse(raw);
    if (pxs === undefined) {
      return false;
    }
    if (!ProjectStore.writeFileBytes(this.pathFor(id), wrapped)) {
      return false;
    }
    // 缩略图边车尽力而为。
    try {
      const thumb = await ctx.resourceManager.getRawFileContent(`${id}.thumb`);
      if (ProjectStore.checkThumbBytes(thumb)) {
        ProjectStore.writeFileBytes(this.thumbPathFor(id), thumb);
      }
    } catch (e) {
    }
    return true;
  }

  /** 首次启动播种：工程目录不存在时恢复全部示例工程；返回是否执行了播种。 */
  async seedDemosIfFresh(): Promise<boolean> {
    const dir = this.dir();
    if (dir.length === 0) {
      return false;
    }
    try {
      if (fs.accessSync(dir)) {
        return false;
      }
    } catch (e) {
      return false;
    }
    await this.restoreDemos();
    return true;
  }

  // ---------- 模型转换 ----------

  /** PxsDoc → 可编辑 PixelDoc（保留图层 id/可见性/不透明度，抬防撞 nextLayerId）。 */
  static toDoc(pxs: PxsDoc): PixelDoc {
    const meta = pxs.meta;
    const doc = new PixelDoc(meta.w, meta.h);
    doc.layers.length = 0;
    doc.cells.length = 0;
    doc.frameCount = 0;
    for (const lm of meta.layers) {
      const layer = new PixelLayer(lm.id, lm.name);
      layer.visible = lm.visible;
      layer.opacity = lm.opacity;
      doc.layers.push(layer);
      doc.ensureLayerIdAbove(lm.id);
    }
    if (doc.layers.length === 0) {
      // 空层表防御（正常 .pxs 不会出现）：补一层。
      doc.addLayer('Layer 1');
    }
    for (let f = 0; f < meta.frameCount; f++) {
      doc.addFrame();
    }
    for (let f = 0; f < doc.frameCount && f < pxs.cells.length; f++) {
      for (let l = 0; l < doc.layers.length && l < pxs.cells[f].length; l++) {
        doc.cells[f][l].data.set(pxs.cells[f][l].data);
      }
    }
    doc.activeFrame = 0;
    doc.activeLayer = 0;
    return doc;
  }

  /** 编辑器现场 → PxsMeta（序列化输入）。 */
  static buildMeta(doc: PixelDoc, name: string, fps: number, paletteId: string): PxsMeta {
    const meta = new PxsMeta();
    meta.name = ProjectStore.sanitizeName(name);
    meta.w = doc.w;
    meta.h = doc.h;
    meta.fps = Math.max(1, Math.min(30, Math.round(fps)));
    meta.frameCount = doc.frameCount;
    meta.paletteId = paletteId;
    for (const layer of doc.layers) {
      const lm = new PxsLayerMeta();
      lm.id = layer.id;
      lm.name = layer.name;
      lm.visible = layer.visible;
      lm.opacity = layer.opacity;
      meta.layers.push(lm);
    }
    return meta;
  }
}
