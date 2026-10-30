/**
 * pages/EditorPage.ets — 编辑器主页（开发计划 §5.1，M1/M3/M4）：
 * 顶栏（返回 + 工程名 + 尺寸 + 脏标记 + 撤销/重做） / 画布区 /
 * 工具行（8 工具 + 镜像 + 实心 + 网格三态） / 笔宽行 / 调色板横滑行。
 * 底部 Tab：画布 / 图层 / 帧（缩略条 + 播放 + FPS + 洋葱皮）/ 导出（M4）。
 * 播放 = setInterval 循环推进 activeFrame + tick 驱动重渲染；任意触屏/撤销/帧操作即停。
 * 工程（M4）：EditorLaunch 静态参数进入（新建/打开 .pxs）；30s 自动保存 +
 * onBackPress/onPageHide 即存（杀进程恢复损失 ≤30s）；ready 门控异步加载。
 * 注意：@Builder 值传参在 V2 是快照不响应，所有会变的状态一律在 Builder 体内读取。
 */

import { PixelDoc } from '../core/PixelDoc';
import { PxsDoc } from '../core/PxsFile';
import { UndoStack } from '../core/UndoStack';
import { EditorSession, Tool, GridMode } from '../viewmodel/EditorSession';
import { DocOps } from '../viewmodel/DocOps';
import { PaletteStore } from '../viewmodel/PaletteStore';
import { ProjectStore } from '../viewmodel/ProjectStore';
import { EditorLaunch } from '../viewmodel/EditorLaunch';
import { CanvasView } from '../components/CanvasView';
import { LayerPanel } from '../components/LayerPanel';
import { FrameStrip } from '../components/FrameStrip';
import { PaletteBar } from '../components/PaletteBar';
import { PalettePanel } from '../components/PalettePanel';
import { ExportPanel } from '../components/ExportPanel';

/** 播放定时器最小间隔（ms）：对齐 60Hz 帧节流，防高 FPS 空转。 */
const PLAY_TICK_MS = 16;
/** 自动保存周期（ms）：杀进程恢复损失 ≤30s（开发计划 §4.1/§6.4）。 */
const AUTOSAVE_MS = 30000;
/** 平板双栏阈值（vp）：宽度 ≥ 此值启用 画布+图层/帧 常驻双栏（开发计划 §5.1）。 */
const WIDE_MIN_VP = 840;

@Entry
@ComponentV2
struct EditorPage {
  @Local doc: PixelDoc = new PixelDoc(64, 64);
  @Local session: EditorSession = new EditorSession();
  /** 底部面板模式：0=画布 1=图层 2=帧 3=导出（平板双栏时收敛为 0/3）。 */
  @Local panelMode: number = 0;
  /** 调色板面板覆盖层（覆盖内容区，不影响底部工具行）。 */
  @Local paletteOpen: boolean = false;
  @Local paletteStore: PaletteStore = new PaletteStore();
  /** 平板双栏（根区宽度 ≥840vp）：图层/帧常驻右列，页签收敛为画布/导出。 */
  @Local isWide: boolean = false;
  /** 工程加载/新建完成门控：异步打开期间显示加载态，防挂载旧 doc。 */
  @Local ready: boolean = false;
  @Local projectName: string = '';
  private projectId: string = '';
  private projectStore: ProjectStore = new ProjectStore();
  private autosaveTimerId: number = -1;
  private saving: boolean = false;
  private playTimerId: number = -1;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined && ctx !== null) {
      this.paletteStore.load(ctx);
      this.projectStore.init(ctx);
    }
    this.projectName = EditorLaunch.projectName;
    if (EditorLaunch.fresh) {
      // 新建：EditorLaunch 携带名称与尺寸，立即进入。
      this.projectId = ProjectStore.newId();
      this.doc = new PixelDoc(EditorLaunch.newWidth, EditorLaunch.newHeight);
      this.ready = true;
      this.startAutosave();
      return;
    }
    // 打开：异步加载 .pxs；失败回退空白工程（不崩溃）。
    const id = EditorLaunch.projectId;
    this.projectStore.loadDoc(id).then((pxs: PxsDoc | undefined) => {
      if (pxs !== undefined) {
        this.projectId = id;
        this.doc = ProjectStore.toDoc(pxs);
        this.projectName = pxs.meta.name;
        this.session.fps = Math.max(1, Math.min(30, pxs.meta.fps));
        if (pxs.meta.paletteId.length > 0) {
          this.paletteStore.setActive(pxs.meta.paletteId);
        }
      } else {
        this.projectId = ProjectStore.newId();
        this.doc = new PixelDoc(64, 64);
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.project_load_failed') });
      }
      this.ready = true;
      this.startAutosave();
    }).catch(() => {
      this.projectId = ProjectStore.newId();
      this.doc = new PixelDoc(64, 64);
      this.ready = true;
      this.startAutosave();
    });
  }

  aboutToDisappear(): void {
    this.stopPlayback();
    this.stopAutosave();
    this.saveNow();
    this.paletteStore.saveNow();
  }

  /** 系统返回：先落盘再退出（返回键/侧滑统一入口）。 */
  onBackPress(): boolean {
    this.saveNow();
    return false;
  }

  /** 页面隐藏（后台/跳转）即保存：进程被杀损失 ≤ 自动保存周期。 */
  onPageHide(): void {
    this.saveNow();
  }

  // ---------- 工程持久化（§6.4：30s 自动保存 + 原子落盘） ----------

  private startAutosave(): void {
    this.stopAutosave();
    this.autosaveTimerId = setInterval(() => {
      if (this.session.dirty) {
        this.saveNow();
      }
    }, AUTOSAVE_MS);
  }

  private stopAutosave(): void {
    if (this.autosaveTimerId !== -1) {
      clearInterval(this.autosaveTimerId);
      this.autosaveTimerId = -1;
    }
  }

  private saveNow(): void {
    if (!this.ready || this.saving) {
      return;
    }
    this.saving = true;
    // 保存期间若有新编辑（tick/笔触变化），保存成功后仍保持脏标记。
    const markBefore = this.session.tick * 2 + this.session.strokeCount;
    const meta = ProjectStore.buildMeta(this.doc, this.projectName,
      this.session.fps, this.paletteStore.activeId);
    this.projectStore.saveDoc(this.projectId, meta, this.doc.cells)
      .then((ok: boolean) => {
        this.saving = false;
        if (!ok) {
          this.getUIContext().getPromptAction()
            .showToast({ message: $r('app.string.project_save_failed') });
          return;
        }
        if (markBefore === this.session.tick * 2 + this.session.strokeCount) {
          this.session.dirty = false;
        }
      })
      .catch(() => {
        this.saving = false;
      });
  }

  // ---------- 播放（§4.1：循环预览，触屏/撤销/帧操作即停） ----------

  private startPlayback(): void {
    this.stopPlayback();
    const interval = Math.max(PLAY_TICK_MS, Math.round(1000 / this.session.fps));
    this.playTimerId = setInterval(() => {
      this.doc.activeFrame = (this.doc.activeFrame + 1) % this.doc.frameCount;
      this.session.activeFrame = this.doc.activeFrame;
      this.session.tick++;
    }, interval);
  }

  private stopPlayback(): void {
    if (this.playTimerId !== -1) {
      clearInterval(this.playTimerId);
      this.playTimerId = -1;
    }
  }

  @Monitor('session.playing')
  onPlayingChange(): void {
    if (this.session.playing) {
      if (this.doc.frameCount > 1) {
        this.startPlayback();
      } else {
        this.session.playing = false;
      }
    } else {
      this.stopPlayback();
    }
  }

  @Monitor('session.fps')
  onFpsChange(): void {
    if (this.session.playing) {
      this.startPlayback();
    }
  }

  /** 当前色变化 → 记入最近使用（PaletteBar/取色器/吸管统一入口）。 */
  @Monitor('session.color')
  onColorChange(): void {
    this.paletteStore.pushRecent(this.session.color);
  }

  /** 双栏切换：窄栏独占页签（图层/帧）回到画布态，避免无高亮页签。 */
  @Monitor('isWide')
  onWideChange(): void {
    if (this.isWide && (this.panelMode === 1 || this.panelMode === 2)) {
      this.panelMode = 0;
    }
  }

  private clearCanvas(): void {
    const cell = this.doc.activeCell();
    if (cell === undefined) {
      return;
    }
    const before = cell.data.slice();
    cell.clear();
    const entry = UndoStack.entryIfChanged(cell.data, before);
    if (entry !== undefined) {
      this.session.undoStack.push(entry);
      this.session.syncUndoFlags();
      this.session.dirty = true;
      this.session.tick++;
    }
  }

  private cycleGrid(): void {
    const g = this.session.gridMode;
    this.session.gridMode =
      g === GridMode.Auto ? GridMode.On : (g === GridMode.On ? GridMode.Off : GridMode.Auto);
  }

  private gridLabel(): ResourceStr {
    if (this.session.gridMode === GridMode.On) {
      return $r('app.string.grid_on');
    }
    if (this.session.gridMode === GridMode.Off) {
      return $r('app.string.grid_off');
    }
    return $r('app.string.grid_auto');
  }

  /** 工具切换按钮（7 工具）：active 状态在体内读取 session.currentTool。 */
  @Builder
  toolButton(label: ResourceStr, tool: Tool) {
    Button(label)
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.currentTool === tool
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.currentTool === tool
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        if (this.session.currentTool === Tool.Selection && tool !== Tool.Selection) {
          DocOps.cancelSelection(this.session);
        }
        this.session.currentTool = tool;
      })
  }

  /** 顶栏撤销/重做：kind 0=撤销 1=重做，可用态在体内读取 session。 */
  @Builder
  barButton(kind: number) {
    Button(kind === 0 ? $r('app.string.undo') : $r('app.string.redo'))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(32)
      .padding({ left: 12, right: 12 })
      .fontSize(13)
      .enabled(kind === 0 ? this.session.canUndo : this.session.canRedo)
      .backgroundColor($r('app.color.card_background'))
      .fontColor(kind === 0
        ? (this.session.canUndo ? $r('app.color.primary_text') : $r('app.color.hint_text'))
        : (this.session.canRedo ? $r('app.color.primary_text') : $r('app.color.hint_text')))
      .onClick(() => {
        if (kind === 0) {
          this.session.undo();
        } else {
          this.session.redo();
        }
      })
  }

  @Builder
  mirrorButton() {
    Button($r('app.string.mirror_x'))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.mirrorX
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.mirrorX
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.session.mirrorX = !this.session.mirrorX;
      })
  }

  @Builder
  filledButton() {
    Button($r('app.string.shape_filled'))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.shapeFilled
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.shapeFilled
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.session.shapeFilled = !this.session.shapeFilled;
      })
  }

  @Builder
  gridButton() {
    Button(this.gridLabel())
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .backgroundColor(this.session.gridMode === GridMode.On
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.gridMode === GridMode.On
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.cycleGrid();
      })
  }

  @Builder
  sizeButton(size: number) {
    Button(size.toString())
      .type(ButtonType.Normal)
      .borderRadius(10)
      .width(36)
      .height(36)
      .fontSize(14)
      .backgroundColor(this.session.brushSize === size
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.session.brushSize === size
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.session.brushSize = size;
      })
  }

  /** 底部 Tab：mode 0=画布 1=图层 2=帧 3=导出；激活态在体内读取 panelMode。 */
  @Builder
  tabButton(mode: number) {
    Button(mode === 0 ? $r('app.string.tab_canvas')
      : (mode === 1 ? $r('app.string.tab_layers')
        : (mode === 2 ? $r('app.string.tab_frames') : $r('app.string.tab_export'))))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(36)
      .layoutWeight(1)
      .fontSize(14)
      .backgroundColor(this.panelMode === mode
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.panelMode === mode
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.panelMode = mode;
        if (mode !== 0 && this.session.playing) {
          // 画布不可见时终止循环预览，避免空转定时器。
          this.session.playing = false;
        }
      })
  }

  /** 工具行：8 工具 + 镜像 + 实心 + 网格三态（横向可滚动）。 */
  @Builder
  toolRow() {
    Scroll() {
      Row({ space: 8 }) {
        this.toolButton($r('app.string.tool_pencil'), Tool.Pencil)
        this.toolButton($r('app.string.tool_eraser'), Tool.Eraser)
        this.toolButton($r('app.string.tool_fill'), Tool.Fill)
        this.toolButton($r('app.string.tool_line'), Tool.Line)
        this.toolButton($r('app.string.tool_rect'), Tool.Rect)
        this.toolButton($r('app.string.tool_ellipse'), Tool.Ellipse)
        this.toolButton($r('app.string.tool_eyedropper'), Tool.Eyedropper)
        this.toolButton($r('app.string.tool_selection'), Tool.Selection)
        this.mirrorButton()
        if (this.session.currentTool === Tool.Rect || this.session.currentTool === Tool.Ellipse) {
          this.filledButton()
        }
        this.gridButton()
      }
      .padding({ left: 12, right: 12 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
  }

  /** 笔宽行（非选区工具时）。 */
  @Builder
  brushRow() {
    Row({ space: 8 }) {
      Text($r('app.string.brush_size'))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      this.sizeButton(1)
      this.sizeButton(2)
      this.sizeButton(3)
      Blank()
      Button($r('app.string.clear_canvas'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.danger_red'))
        .onClick(() => {
          this.clearCanvas();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
  }

  /** 画布工具组：工具行 + 笔宽/选区行 + 调色板横滑行（窄屏仅画布 Tab；平板常驻左列）。 */
  @Builder
  canvasTools() {
    Column() {
      this.toolRow()
      if (this.session.currentTool === Tool.Selection) {
        this.selectionBar()
      } else {
        this.brushRow()
      }
      PaletteBar({
        session: this.session,
        store: this.paletteStore,
        onOpenPanel: (): void => {
          if (this.session.playing) {
            this.session.playing = false;
          }
          this.paletteOpen = true;
        }
      })
    }
    .width('100%')
  }

  /** 底部页签行：窄屏 4 页签；平板双栏收敛为 画布/导出（图层/帧常驻）。 */
  @Builder
  tabRow() {
    Row({ space: 8 }) {
      this.tabButton(0)
      if (!this.isWide) {
        this.tabButton(1)
        this.tabButton(2)
      }
      this.tabButton(3)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 10 })
    .backgroundColor($r('app.color.card_background'))
  }

  /** 窄屏（<840vp）：画布常驻 Stack + 面板叠放 + 画布工具组 + 4 页签。 */
  @Builder
  compactBody() {
    Column() {
      Stack() {
        CanvasView({ doc: this.doc, session: this.session })
        if (this.panelMode === 1) {
          LayerPanel({ doc: this.doc, session: this.session })
        }
        if (this.panelMode === 2) {
          FrameStrip({
            doc: this.doc,
            session: this.session,
            onPlay: (): void => {
              // 循环预览需画布可见：播放启动即切回画布 Tab。
              this.panelMode = 0;
            }
          })
        }
        if (this.panelMode === 3) {
          ExportPanel({
            doc: this.doc,
            session: this.session,
            paletteStore: this.paletteStore,
            projectName: this.projectName
          })
        }
        if (this.paletteOpen) {
          PalettePanel({
            session: this.session,
            store: this.paletteStore,
            onClose: (): void => {
              this.paletteOpen = false;
            }
          })
        }
      }
      .layoutWeight(1)
      .width('100%')

      if (this.panelMode === 0) {
        this.canvasTools()
      }

      this.tabRow()
    }
    .layoutWeight(1)
    .width('100%')
  }

  /** 平板双栏（≥840vp，§5.1）：左列=画布+工具+调色板；右列=图层/帧常驻（导出 Tab 替换）。 */
  @Builder
  wideBody() {
    Column() {
      Row({ space: 8 }) {
        // 左列：画布常驻 + 工具组；调色板面板覆盖左列。
        Stack() {
          Column() {
            CanvasView({ doc: this.doc, session: this.session })
              .layoutWeight(1)
            this.canvasTools()
          }
          .width('100%')
          .height('100%')
          if (this.paletteOpen) {
            PalettePanel({
              session: this.session,
              store: this.paletteStore,
              onClose: (): void => {
                this.paletteOpen = false;
              }
            })
          }
        }
        .layoutWeight(1)
        .height('100%')

        // 右列（320vp）：图层 + 帧常驻各半；导出 Tab 时整列替换为导出面板。
        Column() {
          if (this.panelMode === 3) {
            ExportPanel({
              doc: this.doc,
              session: this.session,
              paletteStore: this.paletteStore,
              projectName: this.projectName
            })
            .layoutWeight(1)
          } else {
            LayerPanel({ doc: this.doc, session: this.session })
              .layoutWeight(1)
            Divider()
              .strokeWidth(1)
              .color($r('app.color.border_color'))
            FrameStrip({
              doc: this.doc,
              session: this.session,
              onPlay: (): void => {
                if (this.panelMode !== 0) {
                  this.panelMode = 0;
                }
              }
            })
              .layoutWeight(1)
          }
        }
        .width(320)
        .height('100%')
      }
      .layoutWeight(1)
      .width('100%')

      this.tabRow()
    }
    .layoutWeight(1)
    .width('100%')
  }

  /** 选区操作行（Selection 工具时替代笔宽行）：复制/删除/取消。 */
  @Builder
  selectionBar() {
    Row({ space: 8 }) {
      Button($r('app.string.sel_copy'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .enabled(this.session.sel !== undefined)
        .backgroundColor($r('app.color.card_background'))
        .fontColor(this.session.sel !== undefined
          ? $r('app.color.primary_text') : $r('app.color.hint_text'))
        .onClick(() => {
          DocOps.copySelection(this.doc, this.session);
        })
      Button($r('app.string.sel_delete'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .enabled(this.session.sel !== undefined)
        .backgroundColor($r('app.color.card_background'))
        .fontColor(this.session.sel !== undefined
          ? $r('app.color.danger_red') : $r('app.color.hint_text'))
        .onClick(() => {
          DocOps.deleteSelection(this.doc, this.session);
        })
      Button($r('app.string.sel_cancel'))
        .type(ButtonType.Normal)
        .borderRadius(10)
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .enabled(this.session.sel !== undefined)
        .backgroundColor($r('app.color.card_background'))
        .fontColor(this.session.sel !== undefined
          ? $r('app.color.primary_text') : $r('app.color.hint_text'))
        .onClick(() => {
          DocOps.cancelSelection(this.session);
        })
      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
  }

  build() {
    Column() {
      // 顶栏：返回 + 工程名 + 尺寸 + 脏标记 + 撤销/重做
      Row({ space: 8 }) {
        Button($r('app.string.back'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(32)
          .padding({ left: 12, right: 12 })
          .fontSize(13)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.saveNow();
            this.getUIContext().getRouter().back();
          })
        Text(this.projectName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`${this.doc.w}×${this.doc.h}`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        if (this.session.dirty) {
          Circle()
            .width(8)
            .height(8)
            .fill($r('app.color.accent'))
        }
        this.barButton(0)
        this.barButton(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      if (!this.ready) {
        // 工程打开中（异步 .pxs 加载）
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.brand'))
          Text($r('app.string.editor_loading'))
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 平板双栏（≥840vp）/ 窄屏单栏自适应（§5.1）。
        if (this.isWide) {
          this.wideBody()
        } else {
          this.compactBody()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .onAreaChange((_old: Area, newArea: Area) => {
      this.isWide = Number(newArea.width) >= WIDE_MIN_VP;
    })
  }
}
