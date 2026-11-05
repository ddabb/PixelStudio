/**
 * viewmodel/TemplateDefs.ets — 分类模板库清单（长期任务，章程见
 * docs/模板库长期任务章程.md）。
 *
 * !!! 本文件由 scripts/make_templates.py 生成，请勿手改：
 *     调整模板请编辑 make_templates.py 后运行 py -3 scripts/make_templates.py
 *     重新生成，并以 py -3 scripts/verify_templates.py 校验。
 */

/** 模板条目：rawfile 相对路径 + 双语名称/描述 + 规格。 */
export class TemplateDef {
  id: string = '';
  /** 分类（TPL_CATEGORIES 之一；页签文案 app.string.tpl_cat_<cat>）。 */
  cat: string = '';
  /** .pxs rawfile 相对路径（如 'templates/tpl_puppy.pxs'、'demo_cat.pxs'）。 */
  file: string = '';
  nameZh: string = '';
  nameEn: string = '';
  descZh: string = '';
  descEn: string = '';
  w: number = 0;
  h: number = 0;
  frames: number = 0;
  fps: number = 0;
}

/** 分类展示序（页签顺序；文案键 tpl_cat_<cat>）。 */
export const TPL_CATEGORIES: string[] = [
  'animals',
  'scenery',
  'food',
  'creatures',
  'items',
  'glyphs',
];

/** 全部模板（15 个 = 12 新原创 + 3 示例工程；分类序 → 注册序）。 */
export const TEMPLATE_DEFS: TemplateDef[] = [
  {
    id: 'tpl_puppy', cat: 'animals', file: 'templates/tpl_puppy.pxs',
    nameZh: '柴犬幼犬', nameEn: 'Shiba Puppy',
    descZh: '奶油胸的摇尾小柴犬', descEn: 'A tail-wagging shiba with a cream chest',
    w: 32, h: 32, frames: 2, fps: 6
  },
  {
    id: 'tpl_bird', cat: 'animals', file: 'templates/tpl_bird.pxs',
    nameZh: '蓝翅雀', nameEn: 'Blue Finch',
    descZh: '圆滚滚的蓝色小雀', descEn: 'A round little blue finch',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'demo_cat', cat: 'animals', file: 'demo_cat.pxs',
    nameZh: '星夜小猫', nameEn: 'Starry Night Cat',
    descZh: '星空下眨眼的小猫', descEn: 'A kitten blinking under the stars',
    w: 32, h: 32, frames: 3, fps: 8
  },
  {
    id: 'tpl_forest', cat: 'scenery', file: 'templates/tpl_forest.pxs',
    nameZh: '晨雾森林', nameEn: 'Misty Forest',
    descZh: '晨光穿透雾气的松林', descEn: 'Pines in the morning mist',
    w: 48, h: 48, frames: 1, fps: 8
  },
  {
    id: 'tpl_lake', cat: 'scenery', file: 'templates/tpl_lake.pxs',
    nameZh: '暮色湖泊', nameEn: 'Dusk Lake',
    descZh: '晚霞山影与水面涟漪', descEn: 'Sunset hills over rippling water',
    w: 32, h: 32, frames: 2, fps: 4
  },
  {
    id: 'demo_sunset', cat: 'scenery', file: 'demo_sunset.pxs',
    nameZh: '落日海岸', nameEn: 'Sunset Coast',
    descZh: '棕榈剪影与金色海面', descEn: 'Palm silhouettes on a golden sea',
    w: 48, h: 48, frames: 1, fps: 8
  },
  {
    id: 'tpl_cake', cat: 'food', file: 'templates/tpl_cake.pxs',
    nameZh: '草莓蛋糕', nameEn: 'Strawberry Cake',
    descZh: '淋面蛋糕顶着一颗草莓', descEn: 'A frosted cake with a strawberry on top',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_sushi', cat: 'food', file: 'templates/tpl_sushi.pxs',
    nameZh: '寿司拼盘', nameEn: 'Sushi Platter',
    descZh: '卷物、握寿司与玉子烧', descEn: 'Rolls, nigiri and tamago',
    w: 24, h: 24, frames: 1, fps: 8
  },
  {
    id: 'tpl_knight', cat: 'creatures', file: 'templates/tpl_knight.pxs',
    nameZh: '小骑士', nameEn: 'Little Knight',
    descZh: '迈步前进的银甲小骑士', descEn: 'A silver knight marching along',
    w: 24, h: 24, frames: 2, fps: 8
  },
  {
    id: 'tpl_dragon', cat: 'creatures', file: 'templates/tpl_dragon.pxs',
    nameZh: '幼龙', nameEn: 'Baby Dragon',
    descZh: '扇着翅膀的绿色幼龙', descEn: 'A green dragonet flapping its wings',
    w: 32, h: 32, frames: 2, fps: 6
  },
  {
    id: 'demo_slime', cat: 'creatures', file: 'demo_slime.pxs',
    nameZh: '果冻史莱姆', nameEn: 'Jelly Slime',
    descZh: '压扁弹跳的绿色果冻', descEn: 'A green jelly bouncing along',
    w: 16, h: 16, frames: 2, fps: 6
  },
  {
    id: 'tpl_chest', cat: 'items', file: 'templates/tpl_chest.pxs',
    nameZh: '宝箱', nameEn: 'Treasure Chest',
    descZh: '装满金币的老宝箱', descEn: 'An old chest full of gold',
    w: 16, h: 16, frames: 2, fps: 4
  },
  {
    id: 'tpl_potion', cat: 'items', file: 'templates/tpl_potion.pxs',
    nameZh: '魔法药水', nameEn: 'Magic Potion',
    descZh: '冒泡的粉色药水', descEn: 'A bubbling pink potion',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_heart', cat: 'glyphs', file: 'templates/tpl_heart.pxs',
    nameZh: '爱心', nameEn: 'Pixel Heart',
    descZh: '经典像素爱心', descEn: 'A classic pixel heart',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_star', cat: 'glyphs', file: 'templates/tpl_star.pxs',
    nameZh: '闪耀星徽', nameEn: 'Sparkle Star',
    descZh: '四角闪亮像素星', descEn: 'A four-pointed sparkle',
    w: 16, h: 16, frames: 1, fps: 8
  },
];
