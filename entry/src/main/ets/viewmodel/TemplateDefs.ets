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

/** 全部模板（51 个 = 48 新原创 + 3 示例工程；分类序 → 注册序）。 */
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
    id: 'tpl_rabbit', cat: 'animals', file: 'templates/tpl_rabbit.pxs',
    nameZh: '白玉兔', nameEn: 'Snow Rabbit',
    descZh: '竖着长耳朵的白兔', descEn: 'A white rabbit with tall ears',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_penguin', cat: 'animals', file: 'templates/tpl_penguin.pxs',
    nameZh: '小企鹅', nameEn: 'Little Penguin',
    descZh: '挺着白肚的小企鹅', descEn: 'A penguin with a white belly',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_turtle', cat: 'animals', file: 'templates/tpl_turtle.pxs',
    nameZh: '小海龟', nameEn: 'Little Turtle',
    descZh: '沙滩上慢步的小海龟', descEn: 'A little turtle on the sand',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_fish', cat: 'animals', file: 'templates/tpl_fish.pxs',
    nameZh: '热带鱼', nameEn: 'Tropical Fish',
    descZh: '红条纹的小热带鱼', descEn: 'A striped tropical fish',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_hedgehog', cat: 'animals', file: 'templates/tpl_hedgehog.pxs',
    nameZh: '小刺猬', nameEn: 'Little Hedgehog',
    descZh: '背着尖刺的小刺猬', descEn: 'A little hedgehog with spikes',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_owl', cat: 'animals', file: 'templates/tpl_owl.pxs',
    nameZh: '猫头鹰', nameEn: 'Little Owl',
    descZh: '栖在枝上的大眼猫头鹰', descEn: 'A big-eyed owl on a branch',
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
    id: 'tpl_volcano', cat: 'scenery', file: 'templates/tpl_volcano.pxs',
    nameZh: '喷发火山', nameEn: 'Erupting Volcano',
    descZh: '夜色中喷发的火山', descEn: 'A volcano blazing in the night',
    w: 48, h: 48, frames: 1, fps: 8
  },
  {
    id: 'tpl_igloo', cat: 'scenery', file: 'templates/tpl_igloo.pxs',
    nameZh: '极光雪屋', nameEn: 'Aurora Igloo',
    descZh: '极光下的小雪屋', descEn: 'An igloo under the aurora',
    w: 32, h: 32, frames: 1, fps: 8
  },
  {
    id: 'tpl_waterfall', cat: 'scenery', file: 'templates/tpl_waterfall.pxs',
    nameZh: '林间瀑布', nameEn: 'Forest Waterfall',
    descZh: '崖壁间垂落的白瀑', descEn: 'A white fall between cliffs',
    w: 48, h: 48, frames: 1, fps: 8
  },
  {
    id: 'tpl_terrace', cat: 'scenery', file: 'templates/tpl_terrace.pxs',
    nameZh: '黄昏梯田', nameEn: 'Dusk Terraces',
    descZh: '夕照下层叠的梯田', descEn: 'Terraced fields at dusk',
    w: 32, h: 32, frames: 1, fps: 8
  },
  {
    id: 'tpl_lighthouse', cat: 'scenery', file: 'templates/tpl_lighthouse.pxs',
    nameZh: '海边灯塔', nameEn: 'Seaside Lighthouse',
    descZh: '星夜下发光的海边灯塔', descEn: 'A lighthouse beaming at night',
    w: 24, h: 24, frames: 1, fps: 8
  },
  {
    id: 'tpl_pyramid', cat: 'scenery', file: 'templates/tpl_pyramid.pxs',
    nameZh: '金字塔落日', nameEn: 'Pyramid Sunset',
    descZh: '落日余晖中的金字塔', descEn: 'Pyramids in the setting sun',
    w: 24, h: 24, frames: 1, fps: 8
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
    id: 'tpl_ramen', cat: 'food', file: 'templates/tpl_ramen.pxs',
    nameZh: '拉面碗', nameEn: 'Ramen Bowl',
    descZh: '叉烧溏心蛋热汤拉面', descEn: 'Hot ramen with pork and egg',
    w: 24, h: 24, frames: 1, fps: 8
  },
  {
    id: 'tpl_icecream', cat: 'food', file: 'templates/tpl_icecream.pxs',
    nameZh: '双色甜筒', nameEn: 'Swirl Cone',
    descZh: '粉白漩涡冰淇淋甜筒', descEn: 'A pink-and-white swirl cone',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_burger', cat: 'food', file: 'templates/tpl_burger.pxs',
    nameZh: '芝士汉堡', nameEn: 'Cheese Burger',
    descZh: '层层分明的芝士汉堡', descEn: 'A stacked cheeseburger',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_cocoa', cat: 'food', file: 'templates/tpl_cocoa.pxs',
    nameZh: '热可可', nameEn: 'Hot Cocoa',
    descZh: '冒着热气的热可可', descEn: 'A steaming cup of cocoa',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_donut', cat: 'food', file: 'templates/tpl_donut.pxs',
    nameZh: '甜甜圈', nameEn: 'Sprinkle Donut',
    descZh: '撒着糖粒的粉色甜甜圈', descEn: 'A pink-frosted sprinkle donut',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_pizza', cat: 'food', file: 'templates/tpl_pizza.pxs',
    nameZh: '披萨', nameEn: 'Pepperoni Pizza',
    descZh: '铺满辣肠的芝士披萨', descEn: 'A cheese pizza with pepperoni',
    w: 16, h: 16, frames: 1, fps: 8
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
    id: 'tpl_ghost', cat: 'creatures', file: 'templates/tpl_ghost.pxs',
    nameZh: '小幽灵', nameEn: 'Little Ghost',
    descZh: '一沉一浮眨眼的小幽灵', descEn: 'A tiny ghost bobbing along',
    w: 16, h: 16, frames: 2, fps: 6
  },
  {
    id: 'tpl_mushroom', cat: 'creatures', file: 'templates/tpl_mushroom.pxs',
    nameZh: '蘑菇小人', nameEn: 'Mushroom Folk',
    descZh: '红帽白点的蘑菇小人', descEn: 'A red-capped mushroom fellow',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_bat', cat: 'creatures', file: 'templates/tpl_bat.pxs',
    nameZh: '小蝙蝠', nameEn: 'Little Bat',
    descZh: '扇动翅膀的小蝙蝠', descEn: 'A bat flapping its wings',
    w: 16, h: 16, frames: 2, fps: 6
  },
  {
    id: 'tpl_wizard', cat: 'creatures', file: 'templates/tpl_wizard.pxs',
    nameZh: '小巫师', nameEn: 'Little Wizard',
    descZh: '尖帽白须的小巫师', descEn: 'A wizard with a starry hat',
    w: 24, h: 24, frames: 1, fps: 8
  },
  {
    id: 'tpl_robot', cat: 'creatures', file: 'templates/tpl_robot.pxs',
    nameZh: '小机器人', nameEn: 'Little Robot',
    descZh: '天线闪灯的小机器人', descEn: 'A robot with a blinking antenna',
    w: 16, h: 16, frames: 2, fps: 4
  },
  {
    id: 'tpl_mummy', cat: 'creatures', file: 'templates/tpl_mummy.pxs',
    nameZh: '小木乃伊', nameEn: 'Little Mummy',
    descZh: '蹦蹦跳跳的绷带木乃伊', descEn: 'A hopping bandaged mummy',
    w: 16, h: 16, frames: 2, fps: 6
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
    id: 'tpl_sword', cat: 'items', file: 'templates/tpl_sword.pxs',
    nameZh: '宝剑', nameEn: 'Treasure Sword',
    descZh: '镶金柄嵌红石的宝剑', descEn: 'A gold-hilted sword with a ruby',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_lantern', cat: 'items', file: 'templates/tpl_lantern.pxs',
    nameZh: '纸提灯', nameEn: 'Paper Lantern',
    descZh: '烛光摇曳的圆纸提灯', descEn: 'A round lantern with a flickering flame',
    w: 16, h: 16, frames: 2, fps: 6
  },
  {
    id: 'tpl_key', cat: 'items', file: 'templates/tpl_key.pxs',
    nameZh: '黄铜钥匙', nameEn: 'Brass Key',
    descZh: '黄铜环头旧钥匙', descEn: 'An old brass key',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_scroll', cat: 'items', file: 'templates/tpl_scroll.pxs',
    nameZh: '魔法卷轴', nameEn: 'Magic Scroll',
    descZh: '红蜡封印的卷轴', descEn: 'A scroll sealed with red wax',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_crown', cat: 'items', file: 'templates/tpl_crown.pxs',
    nameZh: '皇冠', nameEn: 'Gold Crown',
    descZh: '镶着红珠的金皇冠', descEn: 'A gold crown with ruby orbs',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_hourglass', cat: 'items', file: 'templates/tpl_hourglass.pxs',
    nameZh: '沙漏', nameEn: 'Hourglass',
    descZh: '沙粒流动的计时沙漏', descEn: 'An hourglass with flowing sand',
    w: 16, h: 16, frames: 2, fps: 4
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
  {
    id: 'tpl_skull', cat: 'glyphs', file: 'templates/tpl_skull.pxs',
    nameZh: '骷髅头', nameEn: 'Pixel Skull',
    descZh: '经典像素骷髅图标', descEn: 'A classic pixel skull icon',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_moon', cat: 'glyphs', file: 'templates/tpl_moon.pxs',
    nameZh: '弯月', nameEn: 'Crescent Moon',
    descZh: '带陨坑的黄弯月与星', descEn: 'A cratered crescent with stars',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_gem', cat: 'glyphs', file: 'templates/tpl_gem.pxs',
    nameZh: '蓝宝石', nameEn: 'Sapphire Gem',
    descZh: '切面闪亮的蓝宝石', descEn: 'A faceted blue gem',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_note', cat: 'glyphs', file: 'templates/tpl_note.pxs',
    nameZh: '音符', nameEn: 'Music Note',
    descZh: '跳动的蓝色音符', descEn: 'A blue note bouncing along',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_rainbow', cat: 'glyphs', file: 'templates/tpl_rainbow.pxs',
    nameZh: '彩虹', nameEn: 'Pixel Rainbow',
    descZh: '云端架起的五色彩虹', descEn: 'A rainbow between the clouds',
    w: 16, h: 16, frames: 1, fps: 8
  },
  {
    id: 'tpl_snowflake', cat: 'glyphs', file: 'templates/tpl_snowflake.pxs',
    nameZh: '雪花', nameEn: 'Snowflake',
    descZh: '六瓣对称的蓝色雪花', descEn: 'A six-armed blue snowflake',
    w: 16, h: 16, frames: 1, fps: 8
  },
];
