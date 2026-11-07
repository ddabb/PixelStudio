/**
 * viewmodel/PixelMaps.ets — 显示用 PixelMap 工厂（色彩一致性修复）。
 * createPixelMapSync 生成的 PixelMap 未携带色彩空间信息，广色域（Display P3）屏上
 * 送显管线按当前屏幕色彩空间解释像素数据，画布/缩略图颜色相对 ArkUI 组件
 * （.backgroundColor，sRGB 渲染）的色卡/当前色块出现偏色——即「绘制颜色与画笔
 * 颜色不一致」；数据层（Raster/Compose）绘制颜色与所选色严格一致，偏色只发生在
 * 送显环节。统一经本工厂创建显示用 PixelMap 并钉 SRGB 色彩空间（仅标记属性，
 * 不改像素数据，API 12+ crossplatform），与 ArkUI 组件渲染同域，保证所见即所得。
 */

import { image } from '@kit.ImageKit';
import { colorSpaceManager } from '@kit.ArkGraphics2D';

export class PixelMaps {
  private static srgb: colorSpaceManager.ColorSpaceManager | undefined = undefined;

  /** 程序生成 RGBA 缓冲 → 显示用 PixelMap（RGBA_8888，钉 SRGB 色彩空间）。 */
  static createSrgb(buf: ArrayBuffer, w: number, h: number): image.PixelMap {
    const opts: image.InitializationOptions = {
      editable: false,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { width: w, height: h }
    };
    const pm = image.createPixelMapSync(buf, opts);
    try {
      if (PixelMaps.srgb === undefined) {
        PixelMaps.srgb = colorSpaceManager.create(colorSpaceManager.ColorSpace.SRGB);
      }
      pm.setColorSpace(PixelMaps.srgb);
    } catch (e) {
      // 色彩空间标记失败：退回默认行为（与修复前一致），像素数据不受影响。
    }
    return pm;
  }
}
