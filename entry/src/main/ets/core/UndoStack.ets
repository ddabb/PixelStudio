/**
 * core/UndoStack.ets — 混合撤销栈（开发计划 §6.3）。
 * 像素类（CelEntry）：受影响层帧像素快照（before/after 独立拷贝），apply = cellData.set。
 * 结构类（DocEntry）：图层增删/排序/元数据/选区内容操作闭包；内容缓冲对象永不替换，
 * 仅原位 .set()，故闭包捕获的引用在撤销/重做后始终有效。
 * 栈深默认 100，LRU 淘汰最旧；新操作入栈截断 redo 尾巴。
 */

/** 撤销条目基类：apply 后由调用方负责重新合成 + tick。 */
export abstract class BaseEntry {
  abstract applyUndo(): void;

  abstract applyRedo(): void;
}

/** 笔刷/选区内容类：单 cel 像素快照。 */
export class CelEntry extends BaseEntry {
  readonly cellData: Uint8Array;
  readonly before: Uint8Array;
  readonly after: Uint8Array;

  constructor(cellData: Uint8Array, before: Uint8Array, after: Uint8Array) {
    super();
    this.cellData = cellData;
    this.before = before;
    this.after = after;
  }

  applyUndo(): void {
    this.cellData.set(this.before);
  }

  applyRedo(): void {
    this.cellData.set(this.after);
  }
}

/** 结构类：undo/redo 操作闭包（捕获需恢复的结构/元数据状态）。 */
export class DocEntry extends BaseEntry {
  readonly undoFn: () => void;
  readonly redoFn: () => void;

  constructor(undoFn: () => void, redoFn: () => void) {
    super();
    this.undoFn = undoFn;
    this.redoFn = redoFn;
  }

  applyUndo(): void {
    this.undoFn();
  }

  applyRedo(): void {
    this.redoFn();
  }
}

export class UndoStack {
  private readonly capacity: number;
  private undoList: BaseEntry[] = [];
  private redoList: BaseEntry[] = [];

  constructor(capacity: number = 100) {
    this.capacity = capacity > 0 ? capacity : 1;
  }

  /** after 取当前 cellData 快照；before/after 相同则返回 undefined（无变更不入栈）。 */
  static entryIfChanged(cellData: Uint8Array, before: Uint8Array): CelEntry | undefined {
    const after = cellData.slice();
    for (let i = 0; i < after.length; i++) {
      if (after[i] !== before[i]) {
        return new CelEntry(cellData, before, after);
      }
    }
    return undefined;
  }

  push(entry: BaseEntry): void {
    this.undoList.push(entry);
    if (this.undoList.length > this.capacity) {
      this.undoList.shift();
    }
    this.redoList = [];
  }

  canUndo(): boolean {
    return this.undoList.length > 0;
  }

  canRedo(): boolean {
    return this.redoList.length > 0;
  }

  undo(): BaseEntry | undefined {
    const e = this.undoList.pop();
    if (e === undefined) {
      return undefined;
    }
    e.applyUndo();
    this.redoList.push(e);
    return e;
  }

  redo(): BaseEntry | undefined {
    const e = this.redoList.pop();
    if (e === undefined) {
      return undefined;
    }
    e.applyRedo();
    this.undoList.push(e);
    return e;
  }
}
