/**
 * components/BrushCursorOverlay.ets — 悬停像素光标覆盖层（1.1.0 手感层，鼠标/2in1）。
 * 画笔覆盖块 = 锚点像素按 Raster.stamp 偏移规则（-floor((size-1)/2)）展开的
 * size×size 品牌色半透明高亮 + 描边；镜像开启时叠加对称 ghost 块。
 * hoverPx/hoverPy = -1 时隐藏；hitTestBehavior 透明不挡笔触与悬停。
 */

const BRAND_FALLBACK = 0xFF818CF8;
const FILL_ALPHA = 0.3;
const STROKE_WIDTH = 1;

@ComponentV2
export struct BrushCursorOverlay {
  /** 锚点像素坐标（vp→px 换算后）；-1 = 光标隐藏。 */
  @Require @Param hoverPx: number;
  @Require @Param hoverPy: number;
  @Require @Param brushSize: number;
  @Require @Param zoom: number;
  @Require @Param docW: number;
  @Require @Param docH: number;
  /** 对称 ghost：镜像开启时同时高亮 (docW-1-px, py) 块。 */
  @Require @Param mirrorX: boolean;

  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }

  @Monitor('hoverPx', 'hoverPy', 'brushSize', 'zoom', 'mirrorX')
  onCursorChange(): void {
    this.draw();
  }

  private draw(): void {
    if (!this.ready) {
      return;
    }
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.docW * this.zoom, this.docH * this.zoom);
    if (this.hoverPx < 0 || this.hoverPy < 0) {
      return;
    }
    const color = this.brandColor();
    ctx.fillStyle = color;
    ctx.strokeStyle = color;
    ctx.lineWidth = STROKE_WIDTH;
    this.drawBlock(this.hoverPx, this.hoverPy);
    if (this.mirrorX) {
      this.drawBlock(this.docW - 1 - this.hoverPx, this.hoverPy);
    }
  }

  /** 单个覆盖块：锚点像素按 stamp 偏移展开，浅填充 + 描边。 */
  private drawBlock(px: number, py: number): void {
    const ctx = this.ctx;
    const base = -Math.floor((this.brushSize - 1) / 2);
    const x = (px + base) * this.zoom;
    const y = (py + base) * this.zoom;
    const s = this.brushSize * this.zoom;
    ctx.globalAlpha = FILL_ALPHA;
    ctx.fillRect(x, y, s, s);
    ctx.globalAlpha = 1;
    ctx.strokeRect(x, y, s, s);
  }

  /** 品牌色 token（深浅主题跟随），资源读取失败回退浅色品牌值。 */
  private brandColor(): string {
    let color = BRAND_FALLBACK;
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined && context !== null) {
        color = context.resourceManager.getColorByNameSync('brand') >>> 0;
      }
    } catch (e) {
      // 资源读取失败：回退默认品牌色。
    }
    return `#${(color & 0xFFFFFF).toString(16).padStart(6, '0')}`;
  }
}
