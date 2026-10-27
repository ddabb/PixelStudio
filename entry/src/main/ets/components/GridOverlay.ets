/**
 * components/GridOverlay.ets — 像素网格覆盖层（开发计划 §6.2）。
 * Canvas 逐像素画线；show=false 或 zoom<2 不绘制（过密不可读）。
 * 颜色取资源 grid_line（亮/暗双主题），取失败回退半透明灰。
 */

const GRID_MIN_ZOOM = 2;
const FALLBACK_GRID_COLOR = '#59808080';

@ComponentV2
export struct GridOverlay {
  @Param docW: number = 64;
  @Param docH: number = 64;
  @Param zoom: number = 1;
  @Param show: boolean = false;

  private gridColor: string = FALLBACK_GRID_COLOR;
  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined && context !== null) {
        const c = context.resourceManager.getColorByNameSync('grid_line') >>> 0;
        const hex = c.toString(16).padStart(8, '0');
        this.gridColor = `#${hex}`;
      }
    } catch (e) {
      this.gridColor = FALLBACK_GRID_COLOR;
    }
  }

  @Monitor('zoom', 'show')
  onViewportChange(): void {
    this.drawGrid();
  }

  private drawGrid(): void {
    const c = this.ctx;
    const w = this.docW * this.zoom;
    const h = this.docH * this.zoom;
    c.clearRect(0, 0, w, h);
    if (!this.show || this.zoom < GRID_MIN_ZOOM) {
      return;
    }
    c.strokeStyle = this.gridColor;
    c.lineWidth = 1;
    c.beginPath();
    for (let x = 1; x < this.docW; x++) {
      const vx = x * this.zoom;
      c.moveTo(vx, 0);
      c.lineTo(vx, h);
    }
    for (let y = 1; y < this.docH; y++) {
      const vy = y * this.zoom;
      c.moveTo(0, vy);
      c.lineTo(w, vy);
    }
    c.stroke();
  }

  build() {
    Canvas(this.ctx)
      .width(this.docW * this.zoom)
      .height(this.docH * this.zoom)
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.drawGrid();
      })
  }
}
