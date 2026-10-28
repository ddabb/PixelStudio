/**
 * components/PalettePanel.ets — 调色板面板（M3，开发计划 §4.1 调色板 / §5.3）。
 * 预置（PICO-8/GB DMG/灰阶/CGA）+ 拼豆品牌色板 + 自定义调色板（新建/重命名/删除/
 * 添加/移除当前色）+ 当前色 + 最近使用 8 色 + HSB 取色器 + HEX 输入。
 * 内置调色板显示名经资源键 palette_name_{id} 本地化，缺键回退代码名。
 */

import { Palette, PaletteKind } from '../core/Palettes';
import { ColorUtil } from '../core/ColorUtil';
import { EditorSession, Tool } from '../viewmodel/EditorSession';
import { PaletteStore } from '../viewmodel/PaletteStore';

const SWATCH_SIZE = 36;

@ComponentV2
export struct PalettePanel {
  @Require @Param session: EditorSession;
  @Require @Param store: PaletteStore;
  @Param onClose: () => void = (): void => {};

  @Local hue: number = 0;
  @Local sat: number = 0;
  @Local bri: number = 100;
  @Local hexText: string = '#FF0000';
  @Local creating: boolean = false;
  @Local createText: string = '';
  @Local renaming: boolean = false;
  @Local renameText: string = '';
  @Local deleting: boolean = false;

  aboutToAppear(): void {
    this.syncPicker();
  }

  @Monitor('session.color')
  onColorChange(): void {
    this.syncPicker();
  }

  private syncPicker(): void {
    const hsb = ColorUtil.toHsb(this.session.color);
    this.hue = hsb.h;
    this.sat = hsb.s;
    this.bri = hsb.b;
    this.hexText = ColorUtil.toHex(this.session.color);
  }

  private pickingColor(): number {
    return ColorUtil.fromHsb(this.hue, this.sat, this.bri);
  }

  private applyPicker(): void {
    this.session.color = this.pickingColor();
    if (this.session.currentTool === Tool.Eraser) {
      this.session.currentTool = Tool.Pencil;
    }
  }

  private applyColor(color: number): void {
    this.session.color = color;
    if (this.session.currentTool === Tool.Eraser) {
      this.session.currentTool = Tool.Pencil;
    }
  }

  /** 调色板显示名：内置经资源键 palette_name_{id} 本地化，缺键/自定义回退 name 字段。 */
  private chipName(p: Palette): string {
    if (p.kind !== PaletteKind.Custom) {
      try {
        const context = this.getUIContext().getHostContext();
        if (context !== undefined && context !== null) {
          return context.resourceManager.getStringByNameSync(`palette_name_${p.id}`);
        }
      } catch (e) {
        // 资源缺键：回退代码名。
      }
    }
    return p.name;
  }

  private allPalettes(): Palette[] {
    const out: Palette[] = [];
    for (const p of this.store.builtins) {
      out.push(p);
    }
    for (const p of this.store.customPalettes) {
      out.push(p);
    }
    return out;
  }

  @Builder
  paletteChip(p: Palette) {
    Button(this.chipName(p))
      .type(ButtonType.Normal)
      .borderRadius(10)
      .height(32)
      .padding({ left: 10, right: 10 })
      .fontSize(12)
      .backgroundColor(this.store.activeId === p.id
        ? $r('app.color.brand') : $r('app.color.card_background'))
      .fontColor(this.store.activeId === p.id
        ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .onClick(() => {
        this.store.setActive(p.id);
        this.creating = false;
        this.renaming = false;
        this.deleting = false;
      })
  }

  @Builder
  swatch(color: number) {
    Column()
      .width(SWATCH_SIZE)
      .height(SWATCH_SIZE)
      .borderRadius(8)
      .backgroundColor(color)
      .border({
        width: this.session.color === color ? 3 : 1,
        color: this.session.color === color
          ? $r('app.color.brand') : $r('app.color.border_color')
      })
      .margin(3)
      .onClick(() => {
        this.applyColor(color);
      })
  }

  @Builder
  smallButton(label: ResourceStr, danger: boolean, onTap: () => void) {
    Button(label)
      .type(ButtonType.Normal)
      .borderRadius(8)
      .height(32)
      .padding({ left: 10, right: 10 })
      .fontSize(12)
      .backgroundColor($r('app.color.card_background'))
      .fontColor(danger ? $r('app.color.danger_red') : $r('app.color.primary_text'))
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  hsbSlider(label: ResourceStr, value: number, min: number, max: number,
    onSlide: (v: number) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .width(48)
      Slider({ value: value, min: min, max: max, step: 1, style: SliderStyle.OutSet })
        .layoutWeight(1)
        .trackColor($r('app.color.border_color'))
        .selectedColor($r('app.color.brand'))
        .onChange((v: number) => {
          onSlide(Math.round(v));
        })
      Text(`${value}`)
        .fontSize(12)
        .fontColor($r('app.color.primary_text'))
        .width(36)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  build() {
    Column() {
      // 头部：标题 + 关闭
      Row({ space: 8 }) {
        Text($r('app.string.palette_title'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Button($r('app.string.palette_close'))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .height(32)
          .padding({ left: 12, right: 12 })
          .fontSize(13)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })

      Scroll() {
        Column() {
          // 调色板芯片行：内置 + 自定义 + 新建
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.allPalettes(), (p: Palette) => {
                this.paletteChip(p)
              }, (p: Palette) => `${p.id}_${p.name}`)
              Button($r('app.string.palette_new'))
                .type(ButtonType.Normal)
                .borderRadius(10)
                .height(32)
                .padding({ left: 10, right: 10 })
                .fontSize(12)
                .backgroundColor($r('app.color.brand_tint'))
                .fontColor($r('app.color.brand'))
                .onClick(() => {
                  this.creating = !this.creating;
                  this.createText = '';
                  this.renaming = false;
                  this.deleting = false;
                })
            }
            .padding({ left: 12, right: 12 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          // 新建调色板（内联输入）
          if (this.creating) {
            Row({ space: 8 }) {
              TextInput({ placeholder: $r('app.string.palette_name_hint'), text: this.createText })
                .layoutWeight(1)
                .height(36)
                .fontSize(13)
                .backgroundColor($r('app.color.card_background'))
                .onChange((v: string) => {
                  this.createText = v;
                })
              this.smallButton($r('app.string.common_confirm'), false, (): void => {
                const p = this.store.createCustom(this.createText);
                if (p !== undefined) {
                  this.store.setActive(p.id);
                }
                this.creating = false;
              })
              this.smallButton($r('app.string.common_cancel'), false, (): void => {
                this.creating = false;
              })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8 })
          }

          // 自定义调色板操作行：加色 / 减色 / 重命名 / 删除
          if (this.store.isCustom(this.store.activeId)) {
            if (this.renaming) {
              Row({ space: 8 }) {
                TextInput({ text: this.renameText })
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(13)
                  .backgroundColor($r('app.color.card_background'))
                  .onChange((v: string) => {
                    this.renameText = v;
                  })
                this.smallButton($r('app.string.common_confirm'), false, (): void => {
                  this.store.renameCustom(this.store.activeId, this.renameText);
                  this.renaming = false;
                })
                this.smallButton($r('app.string.common_cancel'), false, (): void => {
                  this.renaming = false;
                })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8 })
            } else if (this.deleting) {
              Row({ space: 8 }) {
                Text($r('app.string.delete_confirm'))
                  .fontSize(13)
                  .fontColor($r('app.color.danger_red'))
                  .layoutWeight(1)
                this.smallButton($r('app.string.common_confirm'), true, (): void => {
                  this.store.deleteCustom(this.store.activeId);
                  this.deleting = false;
                })
                this.smallButton($r('app.string.common_cancel'), false, (): void => {
                  this.deleting = false;
                })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8 })
            } else {
              Row({ space: 8 }) {
                this.smallButton($r('app.string.palette_add_color'), false, (): void => {
                  this.store.addColorToCustom(this.store.activeId, this.session.color);
                })
                this.smallButton($r('app.string.palette_remove_color'), false, (): void => {
                  this.store.removeColorFromCustom(this.store.activeId, this.session.color);
                })
                this.smallButton($r('app.string.layer_rename'), false, (): void => {
                  const p = this.store.activePalette();
                  this.renameText = p === undefined ? '' : p.name;
                  this.renaming = true;
                })
                this.smallButton($r('app.string.palette_delete'), true, (): void => {
                  this.deleting = true;
                })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8 })
            }
          }

          // 活动调色板色卡网格
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.store.activePalette()?.colors ?? [], (color: number) => {
              this.swatch(color)
            }, (color: number) => color.toString())
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10 })

          // 最近使用 8 色
          if (this.store.recents.length > 0) {
            Text($r('app.string.palette_recents'))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
              .padding({ left: 12, right: 12, top: 10 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.store.recents, (color: number) => {
                this.swatch(color)
              }, (color: number) => `r${color.toString(16)}`)
            }
            .width('100%')
            .padding({ left: 12, right: 12 })
          }

          // HSB 取色器 + HEX 输入
          Text($r('app.string.palette_picker'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 12 })
          Row({ space: 8 }) {
            Column()
              .width(SWATCH_SIZE)
              .height(SWATCH_SIZE)
              .borderRadius(8)
              .backgroundColor(this.pickingColor())
              .border({ width: 1, color: $r('app.color.border_color') })
            TextInput({ text: this.hexText })
              .layoutWeight(1)
              .height(36)
              .fontSize(13)
              .backgroundColor($r('app.color.card_background'))
              .onChange((v: string) => {
                this.hexText = v;
                const c = ColorUtil.parseHex(v);
                if (c !== undefined) {
                  const hsb = ColorUtil.toHsb(c);
                  this.hue = hsb.h;
                  this.sat = hsb.s;
                  this.bri = hsb.b;
                }
              })
            Button($r('app.string.palette_apply'))
              .type(ButtonType.Normal)
              .borderRadius(8)
              .height(36)
              .padding({ left: 12, right: 12 })
              .fontSize(13)
              .backgroundColor($r('app.color.brand'))
              .fontColor($r('app.color.on_accent_text'))
              .onClick(() => {
                this.applyPicker();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 6 })

          this.hsbSlider($r('app.string.palette_hue'), this.hue, 0, 360, (v: number): void => {
            this.hue = v;
            this.hexText = ColorUtil.toHex(this.pickingColor());
          })
          this.hsbSlider($r('app.string.palette_saturation'), this.sat, 0, 100, (v: number): void => {
            this.sat = v;
            this.hexText = ColorUtil.toHex(this.pickingColor());
          })
          this.hsbSlider($r('app.string.palette_brightness'), this.bri, 0, 100, (v: number): void => {
            this.bri = v;
            this.hexText = ColorUtil.toHex(this.pickingColor());
          })
        }
        .width('100%')
        .padding({ bottom: 16 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
