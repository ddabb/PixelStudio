/**
 * viewmodel/DocOps.ets — 图层/选区文档操作（M2，开发计划 §4.1/§6.3）。
 * 统一流程：校验 → 变更文档 → 推撤销条目（结构类 DocEntry / 像素类 CelEntry）
 * → 同步 session（activeLayer/sel）→ bump（dirty + 标志 + tick）驱动重渲染。
 * 不变量：cel 缓冲对象永不替换只原位写入 → DocEntry 闭包引用跨撤销始终有效。
 */

import { PixelDoc, PixelLayer, MAX_LAYERS } from '../core/PixelDoc';
import { PixelBuffer } from '../core/PixelBuffer';
import { UndoStack, DocEntry } from '../core/UndoStack';
import { EditorSession } from './EditorSession';

export class DocOps {
  /** 纯静态工具类，禁止实例化。 */
  private constructor() {
  }

  /** 文档变更收口：脏标记 + 撤销标志同步 + tick 驱动画布/面板重渲染。 */
  private static bump(session: EditorSession): void {
    session.dirty = true;
    session.syncUndoFlags();
    session.tick++;
  }

  private static syncActive(doc: PixelDoc, session: EditorSession, li: number): void {
    doc.activeLayer = li;
    session.activeLayer = li;
  }

  // ---------- 图层：结构操作 ----------

  static setActiveLayer(doc: PixelDoc, session: EditorSession, li: number): void {
    if (li < 0 || li >= doc.layers.length) {
      return;
    }
    DocOps.syncActive(doc, session, li);
  }

  /** 在 li 处插入（insert=true）/移除（false）图层及其各帧 cel。 */
  private static spliceLayer(doc: PixelDoc, li: number, layer: PixelLayer,
    cels: PixelBuffer[], insert: boolean): void {
    if (insert) {
      doc.layers.splice(li, 0, layer);
      for (let f = 0; f < doc.cells.length; f++) {
        doc.cells[f].splice(li, 0, cels[f]);
      }
    } else {
      doc.layers.splice(li, 1);
      for (let f = 0; f < doc.cells.length; f++) {
        doc.cells[f].splice(li, 1);
      }
    }
  }

  static addLayer(doc: PixelDoc, session: EditorSession, name: string): boolean {
    if (doc.layers.length >= MAX_LAYERS) {
      return false;
    }
    const activeBefore = doc.activeLayer;
    const layer = doc.addLayer(name);
    if (layer === undefined) {
      return false;
    }
    const li = doc.layers.length - 1;
    const cels: PixelBuffer[] = [];
    for (let f = 0; f < doc.cells.length; f++) {
      cels.push(doc.cells[f][li]);
    }
    DocOps.syncActive(doc, session, li);
    session.undoStack.push(new DocEntry(
      (): void => {
        DocOps.spliceLayer(doc, li, layer, cels, false);
        DocOps.syncActive(doc, session, activeBefore);
      },
      (): void => {
        DocOps.spliceLayer(doc, li, layer, cels, true);
        DocOps.syncActive(doc, session, li);
      }
    ));
    DocOps.bump(session);
    return true;
  }

  static deleteLayer(doc: PixelDoc, session: EditorSession, li: number): boolean {
    if (doc.layers.length <= 1 || li < 0 || li >= doc.layers.length) {
      return false;
    }
    const activeBefore = doc.activeLayer;
    const layer = doc.layers[li];
    const cels: PixelBuffer[] = [];
    for (let f = 0; f < doc.cells.length; f++) {
      cels.push(doc.cells[f][li]);
    }
    if (!doc.deleteLayer(li)) {
      return false;
    }
    const activeAfter = doc.activeLayer;
    session.activeLayer = activeAfter;
    session.undoStack.push(new DocEntry(
      (): void => {
        DocOps.spliceLayer(doc, li, layer, cels, true);
        DocOps.syncActive(doc, session, activeBefore);
      },
      (): void => {
        DocOps.spliceLayer(doc, li, layer, cels, false);
        DocOps.syncActive(doc, session, activeAfter);
      }
    ));
    DocOps.bump(session);
    return true;
  }

  /** dir=+1 向堆顶移动（视觉上移），-1 向堆底。 */
  static moveLayer(doc: PixelDoc, session: EditorSession, li: number, dir: number): boolean {
    const to = li + dir;
    if (li < 0 || li >= doc.layers.length || to < 0 || to >= doc.layers.length) {
      return false;
    }
    const activeBefore = doc.activeLayer;
    if (!doc.moveLayer(li, dir)) {
      return false;
    }
    const activeAfter = doc.activeLayer;
    session.activeLayer = activeAfter;
    session.undoStack.push(new DocEntry(
      (): void => {
        doc.moveLayer(to, -dir);
        DocOps.syncActive(doc, session, activeBefore);
      },
      (): void => {
        doc.moveLayer(li, dir);
        DocOps.syncActive(doc, session, activeAfter);
      }
    ));
    DocOps.bump(session);
    return true;
  }

  // ---------- 图层：元数据操作 ----------

  private static layerAt(doc: PixelDoc, li: number): PixelLayer | undefined {
    if (li < 0 || li >= doc.layers.length) {
      return undefined;
    }
    return doc.layers[li];
  }

  static setLayerVisible(doc: PixelDoc, session: EditorSession, li: number, visible: boolean): boolean {
    const layer = DocOps.layerAt(doc, li);
    if (layer === undefined || layer.visible === visible) {
      return false;
    }
    const before = layer.visible;
    layer.visible = visible;
    session.undoStack.push(new DocEntry(
      (): void => {
        layer.visible = before;
      },
      (): void => {
        layer.visible = visible;
      }
    ));
    DocOps.bump(session);
    return true;
  }

  /** 不透明度 0-100（UI 步进 10）。 */
  static setLayerOpacity(doc: PixelDoc, session: EditorSession, li: number, value: number): boolean {
    const layer = DocOps.layerAt(doc, li);
    if (layer === undefined) {
      return false;
    }
    const v = Math.max(0, Math.min(100, Math.round(value)));
    if (layer.opacity === v) {
      return false;
    }
    const before = layer.opacity;
    layer.opacity = v;
    session.undoStack.push(new DocEntry(
      (): void => {
        layer.opacity = before;
      },
      (): void => {
        layer.opacity = v;
      }
    ));
    DocOps.bump(session);
    return true;
  }

  static renameLayer(doc: PixelDoc, session: EditorSession, li: number, name: string): boolean {
    const layer = DocOps.layerAt(doc, li);
    if (layer === undefined) {
      return false;
    }
    const n = name.trim();
    if (n.length === 0 || layer.name === n) {
      return false;
    }
    const before = layer.name;
    layer.name = n;
    session.undoStack.push(new DocEntry(
      (): void => {
        layer.name = before;
      },
      (): void => {
        layer.name = n;
      }
    ));
    DocOps.bump(session);
    return true;
  }

  // ---------- 帧：结构操作（M3，开发计划 §4.1 帧模块） ----------

  private static syncFrameActive(doc: PixelDoc, session: EditorSession, fi: number): void {
    doc.activeFrame = fi;
    session.activeFrame = fi;
  }

  private static stopPlay(session: EditorSession): void {
    if (session.playing) {
      session.playing = false;
    }
  }

  /** 切换活动帧（不入撤销栈、不置脏）；触发 tick 驱动画布重渲染（洋葱皮跟随）。 */
  static setActiveFrame(doc: PixelDoc, session: EditorSession, fi: number): boolean {
    if (fi < 0 || fi >= doc.frameCount) {
      return false;
    }
    DocOps.stopPlay(session);
    DocOps.syncFrameActive(doc, session, fi);
    session.tick++;
    return true;
  }

  /** 末尾新增空白帧并激活。 */
  static addFrame(doc: PixelDoc, session: EditorSession): boolean {
    DocOps.stopPlay(session);
    const activeBefore = doc.activeFrame;
    const fi = doc.frameCount;
    doc.addFrame();
    const row = doc.cells[fi];
    DocOps.syncFrameActive(doc, session, fi);
    session.undoStack.push(new DocEntry(
      (): void => {
        doc.removeFrame(fi);
        DocOps.syncFrameActive(doc, session, activeBefore);
      },
      (): void => {
        doc.insertFrame(fi, row);
        DocOps.syncFrameActive(doc, session, fi);
      }
    ));
    DocOps.bump(session);
    return true;
  }

  /** 复制 fi 帧全部图层 cel，插入到 fi+1 并激活。 */
  static duplicateFrame(doc: PixelDoc, session: EditorSession, fi: number): boolean {
    if (fi < 0 || fi >= doc.frameCount) {
      return false;
    }
    DocOps.stopPlay(session);
    const activeBefore = doc.activeFrame;
    const src = doc.cells[fi];
    const row: PixelBuffer[] = [];
    for (let li = 0; li < doc.layers.length; li++) {
      row.push(src[li].clone());
    }
    doc.insertFrame(fi + 1, row);
    DocOps.syncFrameActive(doc, session, fi + 1);
    session.undoStack.push(new DocEntry(
      (): void => {
        doc.removeFrame(fi + 1);
        DocOps.syncFrameActive(doc, session, activeBefore);
      },
      (): void => {
        doc.insertFrame(fi + 1, row);
        DocOps.syncFrameActive(doc, session, fi + 1);
      }
    ));
    DocOps.bump(session);
    return true;
  }

  /** 删除帧（至少保留 1 帧）；内容随行移除，撤销原位恢复。 */
  static deleteFrame(doc: PixelDoc, session: EditorSession, fi: number): boolean {
    if (doc.frameCount <= 1 || fi < 0 || fi >= doc.frameCount) {
      return false;
    }
    DocOps.stopPlay(session);
    const row = doc.cells[fi];
    const activeBefore = doc.activeFrame;
    doc.removeFrame(fi);
    const activeAfter = doc.activeFrame;
    session.activeFrame = activeAfter;
    session.undoStack.push(new DocEntry(
      (): void => {
        doc.insertFrame(fi, row);
        DocOps.syncFrameActive(doc, session, activeBefore);
      },
      (): void => {
        doc.removeFrame(fi);
        DocOps.syncFrameActive(doc, session, activeAfter);
      }
    ));
    DocOps.bump(session);
    return true;
  }

  /** dir=+1 与后一帧交换（时间轴右移），-1 左移。 */
  static moveFrame(doc: PixelDoc, session: EditorSession, fi: number, dir: number): boolean {
    const to = fi + dir;
    if (fi < 0 || fi >= doc.frameCount || to < 0 || to >= doc.frameCount) {
      return false;
    }
    DocOps.stopPlay(session);
    const activeBefore = doc.activeFrame;
    doc.swapFrame(fi, dir);
    const activeAfter = doc.activeFrame;
    session.activeFrame = activeAfter;
    session.undoStack.push(new DocEntry(
      (): void => {
        doc.swapFrame(to, -dir);
        DocOps.syncFrameActive(doc, session, activeBefore);
      },
      (): void => {
        doc.swapFrame(fi, dir);
        DocOps.syncFrameActive(doc, session, activeAfter);
      }
    ));
    DocOps.bump(session);
    return true;
  }

  // ---------- 选区：内容操作（单 cel 像素快照撤销） ----------

  /** 复制选区：标记浮动副本（不写像素、不入撤销栈）；随后拖动选区移出副本，原件保留。 */
  static copySelection(doc: PixelDoc, session: EditorSession): boolean {
    const sel = session.sel;
    const cell = doc.activeCell();
    if (sel === undefined || cell === undefined) {
      return false;
    }
    let hasContent = false;
    for (let y = sel.y; y < sel.y + sel.h && !hasContent; y++) {
      for (let x = sel.x; x < sel.x + sel.w; x++) {
        if ((cell.getPx(x, y) >>> 24) > 0) {
          hasContent = true;
          break;
        }
      }
    }
    if (!hasContent) {
      return false;
    }
    session.selCopied = true;
    return true;
  }

  /** 清空选区区域像素并取消选区。 */
  static deleteSelection(doc: PixelDoc, session: EditorSession): boolean {
    const sel = session.sel;
    const cell = doc.activeCell();
    if (sel === undefined || cell === undefined) {
      return false;
    }
    const before = cell.data.slice();
    cell.blit(new PixelBuffer(sel.w, sel.h), sel.x, sel.y);
    session.sel = undefined;
    session.selCopied = false;
    const entry = UndoStack.entryIfChanged(cell.data, before);
    if (entry === undefined) {
      return false;
    }
    session.undoStack.push(entry);
    DocOps.bump(session);
    return true;
  }

  /** 取消选区（不改像素，不入撤销栈）。 */
  static cancelSelection(session: EditorSession): void {
    session.sel = undefined;
    session.selCopied = false;
  }
}
