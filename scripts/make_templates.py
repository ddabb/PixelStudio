# -*- coding: utf-8 -*-
"""
make_templates.py — 分类模板库生成器（长期任务第一批，章程 docs/模板库长期任务章程.md）。

单一事实源：本脚本登记全部模板（12 新原创 + 3 既有示例），运行后发射三类产物：
  1. entry/src/main/resources/rawfile/templates/{id}.pxs + {id}.thumb（12 个新模板；
     3 个示例沿用 rawfile 平铺既有文件，不复制）；
  2. entry/src/main/ets/viewmodel/TemplateDefs.ets —— 生成的 typed 清单（ArkTS 侧
     编译期类型安全，规避 JSON.parse 运行时类型断言）；
  3. scripts/templates_manifest.json —— 仅供 verify_templates.py 消费（应用不读）。

不侵权纪律（章程）：全部程序化原创绘制；题材取泛型原型；调色板用 PICO-8 公开色值
（色值不受版权保护）；命名避开商标词。

用法：py -3 scripts/make_templates.py（在仓库根运行；输出确定性，重跑字节一致）。
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_store_demo import Canvas, serialize_pxs, make_thumb  # noqa: E402

# ---------- PICO-8（复用 make_store_demo 的 12 色 + 补齐其余 4 色公共色值） ----------
K = (29, 43, 83)       # 暗蓝
B = (126, 37, 83)      # 暗紫
BLK = (0, 0, 0)        # 黑
W = (255, 241, 232)    # 米白
Y = (255, 236, 39)     # 黄
O = (255, 163, 0)      # 橙
BR = (171, 82, 54)     # 棕
PE = (255, 204, 170)   # 肤橙
RD = (255, 0, 77)      # 红
GN = (0, 228, 54)      # 绿
BL = (41, 173, 255)    # 亮蓝
PK = (255, 119, 168)   # 粉
DGN = (0, 135, 81)     # 深绿
GR = (194, 195, 199)   # 浅灰
DGR = (95, 87, 79)     # 深灰

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAWFILE_DIR = os.path.join(REPO_ROOT, 'entry', 'src', 'main', 'resources', 'rawfile')
TEMPLATES_DIR = os.path.join(RAWFILE_DIR, 'templates')
DEFS_ETS = os.path.join(REPO_ROOT, 'entry', 'src', 'main', 'ets', 'viewmodel',
                        'TemplateDefs.ets')
MANIFEST_JSON = os.path.join(REPO_ROOT, 'scripts', 'templates_manifest.json')

CATEGORIES = ['animals', 'scenery', 'food', 'creatures', 'items', 'glyphs']


# ---------- 公共绘制小件 ----------

def pine(c, cx, base_y, h, col):
    """锥形松树：顶点 (cx, base_y-h)，向下逐行加宽（步进 0.5 像/行）。"""
    c.set(cx, base_y - h - 1, col)
    for i in range(h):
        y = base_y - h + i
        half = i // 2
        c.rect(cx - half, y, cx + half, y, col)


def tri_fill(c, ax, ay, bx, by, cx, cy, col):
    """三角形扫描线填充（翅膀用）。"""
    lo = min(ay, by, cy)
    hi = max(ay, by, cy)
    for y in range(lo, hi + 1):
        xs = []
        for x0, y0, x1, y1 in [(ax, ay, bx, by), (bx, by, cx, cy), (cx, cy, ax, ay)]:
            if (y0 <= y <= y1) or (y1 <= y <= y0):
                t = 0.0 if y0 == y1 else (y - y0) / (y1 - y0)
                xs.append(round(x0 + (x1 - x0) * t))
        if xs:
            c.rect(min(xs), y, max(xs), y, col)


# ---------- tpl_puppy 柴犬幼犬（animals，32×32，2 帧摇尾） ----------

def puppy(frame):
    c = Canvas(32, 32)
    # 尾巴（帧 0 左卷 / 帧 1 右卷，奶白尾尖）
    if frame == 0:
        c.rect(4, 20, 6, 22, O)
        c.set(3, 21, O)
        c.set(4, 19, O)
        c.set(5, 19, O)
        c.set(4, 20, W)
        c.set(5, 20, W)
    else:
        c.rect(25, 20, 27, 22, O)
        c.set(28, 21, O)
        c.set(26, 19, O)
        c.set(27, 19, O)
        c.set(26, 20, W)
        c.set(27, 20, W)
    # 耳（左/右三角，内耳肤橙）
    c.line(9, 3, 7, 6, O)
    c.line(9, 3, 11, 6, O)
    c.rect(7, 7, 11, 7, O)
    c.set(9, 4, PE)
    c.set(9, 5, PE)
    c.set(9, 6, PE)
    c.line(22, 3, 20, 6, O)
    c.line(22, 3, 24, 6, O)
    c.rect(20, 7, 24, 7, O)
    c.set(22, 4, PE)
    c.set(22, 5, PE)
    c.set(22, 6, PE)
    # 头
    c.rect(8, 8, 23, 8, O)
    c.rect(6, 9, 25, 18, O)
    c.rect(7, 19, 24, 19, O)
    c.rect(9, 20, 22, 20, O)
    # 眉间奶白（柴犬特征）
    c.rect(9, 10, 12, 10, W)
    c.rect(19, 10, 22, 10, W)
    # 眼（黑 + 高光）
    c.rect(10, 12, 11, 13, BLK)
    c.rect(20, 12, 21, 13, BLK)
    c.set(10, 12, W)
    c.set(20, 12, W)
    # 口鼻（奶白）+ 鼻/嘴
    c.rect(12, 14, 19, 14, W)
    c.rect(11, 15, 20, 19, W)
    c.rect(15, 14, 16, 15, BLK)
    c.set(15, 17, BLK)
    c.set(16, 17, BLK)
    c.set(14, 18, BLK)
    c.set(17, 18, BLK)
    # 腮红
    c.set(8, 16, PK)
    c.set(9, 16, PK)
    c.set(22, 16, PK)
    c.set(23, 16, PK)
    # 身体（橙身 + 奶白胸腹）
    c.rect(9, 21, 22, 21, O)
    c.rect(8, 22, 23, 27, O)
    c.rect(9, 28, 22, 28, O)
    c.rect(11, 29, 20, 29, O)
    c.rect(12, 21, 19, 26, W)
    c.rect(13, 27, 18, 28, W)
    # 前腿 + 爪
    c.rect(10, 24, 12, 28, O)
    c.rect(19, 24, 21, 28, O)
    c.rect(10, 29, 12, 29, W)
    c.rect(19, 29, 21, 29, W)
    return c


def build_puppy():
    cells = []
    for f in range(2):
        cells.append([puppy(f)])
    return {
        'id': 'tpl_puppy', 'name': '柴犬幼犬',
        'w': 32, 'h': 32, 'fps': 6, 'palette': 'pico8',
        'layers': [('柴犬', 1)], 'cells': cells,
    }


# ---------- tpl_bird 蓝翅雀（animals，16×16，1 帧） ----------

def bird():
    c = Canvas(16, 16)
    # 头顶翘毛
    c.set(9, 2, BL)
    c.set(10, 1, BL)
    # 身体（亮蓝圆身）
    c.circle(8, 7, 4, BL)
    c.rect(4, 5, 11, 10, BL)
    c.circle(8, 8, 3, BL)
    # 翅膀（暗紫 B）
    c.rect(4, 6, 8, 9, B)
    c.set(5, 5, B)
    c.set(6, 5, B)
    c.set(3, 7, B)
    # 腹部奶白
    c.rect(7, 9, 10, 10, W)
    c.set(6, 10, W)
    c.set(11, 9, W)
    # 尾羽（左后三根）
    c.line(4, 6, 1, 5, BL)
    c.line(4, 7, 1, 7, BL)
    c.line(4, 8, 2, 9, BL)
    # 喙（右，黄）
    c.set(12, 6, Y)
    c.set(13, 6, Y)
    c.set(13, 7, Y)
    # 眼 + 腮红
    c.set(10, 5, BLK)
    c.set(9, 7, PK)
    # 腿脚（棕）
    c.set(7, 11, BR)
    c.set(7, 12, BR)
    c.set(6, 13, BR)
    c.set(9, 11, BR)
    c.set(9, 12, BR)
    c.set(8, 13, BR)
    c.set(10, 13, BR)
    return c


def build_bird():
    return {
        'id': 'tpl_bird', 'name': '蓝翅雀',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('小雀', 1)], 'cells': [[bird()]],
    }


# ---------- tpl_forest 晨雾森林（scenery，48×48，2 层 1 帧） ----------

def forest_bg():
    c = Canvas(48, 48)
    # 晨空渐变：桃粉 → 米白雾
    c.lerp_band([(0.0, PE), (0.55, W), (1.0, W)])
    # 淡日（泛白光晕）
    c.circle(37, 8, 4, Y)
    c.circle(37, 8, 2, W)
    # 远树（玫瑰晨霭剪影）
    for x0, h in [(3, 6), (9, 8), (15, 5), (21, 9), (27, 6), (34, 8), (40, 5), (46, 7)]:
        pine(c, x0, 26, h, PK)
    # 腰雾（横白带咬掉远树半腰）
    for x in range(48):
        if x % 3 != 2:
            c.set(x, 24, W)
        if x % 4 != 1:
            c.set(x, 25, W)
    # 雾下渐灰（地面过渡）
    for y in range(26, 48):
        for x in range(48):
            c.set(x, y, W if y < 32 else GR)
    return c


def forest_fg():
    c = Canvas(48, 48)
    # 地面（草绿 + 深绿影）
    c.rect(0, 36, 47, 47, GN)
    c.rect(0, 36, 47, 37, DGN)
    # 雾气留白（地面上沿几缕白）
    for x in range(0, 48, 3):
        c.set(x, 35, W)
        c.set(x + 1, 35, W)
    # 近处松树（绿冠 + 右半深影 + 棕干）
    for cx, h in [(6, 20), (18, 14), (31, 22), (43, 16)]:
        pine(c, cx, 44, h, GN)
        for i in range(h):
            y = 44 - h + i
            half = i // 2
            for x in range(cx + 1, cx + half + 1):
                c.set(x, y, DGN)
        c.rect(cx - 1, 45, cx, 47, BR)
    # 草地点缀
    for gx, gy in [(10, 43), (22, 46), (27, 42), (14, 41), (37, 45)]:
        c.set(gx, gy, DGN)
    return c


def build_forest():
    return {
        'id': 'tpl_forest', 'name': '晨雾森林',
        'w': 48, 'h': 48, 'fps': 8, 'palette': 'pico8',
        'layers': [('晨空', 1), ('松林', 2)],
        'cells': [[forest_bg(), forest_fg()]],
    }


# ---------- tpl_lake 暮色湖泊（scenery，32×32，2 层 2 帧涟漪） ----------

def lake_sky():
    c = Canvas(32, 32)
    # 暮空渐变：暗蓝 → 暗紫 → 粉 → 肤橙
    c.lerp_band([(0.0, K), (0.5, B), (0.8, PK), (1.0, PE)])
    # 晚霞云带
    for cx, w in [(5, 4), (17, 5), (25, 3), (11, 3)]:
        c.rect(cx, 4, cx + w, 4, PE)
        c.set(cx + 1, 3, PE)
    c.rect(20, 7, 24, 7, PE)
    # 星
    c.set(2, 1, W)
    c.set(29, 2, W)
    # 低垂夕日（两山之间）
    c.circle(16, 11, 2, Y)
    return c


def lake_lake(frame):
    c = Canvas(32, 32)
    # 远山剪影（暗蓝）+ 雪顶
    for x in range(0, 15):
        y_top = 7 + abs(x - 7)
        if y_top <= 14:
            c.rect(x, y_top, x, 14, K)
    c.set(7, 7, W)
    c.set(6, 8, W)
    c.set(8, 8, W)
    for x in range(17, 32):
        y_top = 9 + abs(x - 24)
        if y_top <= 14:
            c.rect(x, y_top, x, 14, K)
    c.set(24, 9, W)
    c.set(23, 10, W)
    c.set(25, 10, W)
    # 湖面（暗紫底）
    c.rect(0, 15, 31, 31, B)
    # 山倒影（半高模糊）
    for x in range(0, 15):
        y_top = 7 + abs(x - 7)
        if y_top < 14:
            h = (14 - y_top) // 2
            c.rect(x, 15, x, 14 + h, K)
    for x in range(17, 32):
        y_top = 9 + abs(x - 24)
        if y_top < 14:
            h = (14 - y_top) // 2
            c.rect(x, 15, x, 14 + h, K)
    # 夕照水面光斑
    c.rect(14, 15, 17, 15, Y)
    c.set(15, 16, Y)
    c.set(16, 16, Y)
    c.set(15, 19, Y)
    c.set(16, 22, Y)
    # 涟漪（帧间横移）
    rows = {17: [(3, 6), (12, 16), (22, 25)],
            20: [(6, 9), (18, 21), (27, 29)],
            24: [(2, 4), (10, 14), (20, 23)],
            28: [(5, 8), (16, 19), (25, 28)]}
    offset = 2 if frame == 1 else 0
    for y, segs in rows.items():
        for x0, x1 in segs:
            for x in range(x0, x1 + 1):
                c.set((x + offset) % 32, y, W)
    return c


def build_lake():
    cells = []
    for f in range(2):
        cells.append([lake_sky(), lake_lake(f)])
    return {
        'id': 'tpl_lake', 'name': '暮色湖泊',
        'w': 32, 'h': 32, 'fps': 4, 'palette': 'pico8',
        'layers': [('暮空', 1), ('湖面', 2)], 'cells': cells,
    }


# ---------- tpl_cake 草莓蛋糕（food，16×16，1 帧） ----------

def cake():
    c = Canvas(16, 16)
    # 盘子（浅灰双沿）
    c.rect(1, 13, 14, 13, GR)
    c.rect(2, 14, 13, 14, GR)
    # 蛋糕体（肤橙海绵 + 奶油夹层）
    c.rect(3, 8, 12, 12, PE)
    c.rect(3, 10, 12, 10, W)
    # 顶淋面（粉 + 挂滴）
    c.rect(3, 6, 12, 7, PK)
    c.set(4, 8, PK)
    c.set(7, 8, PK)
    c.set(10, 8, PK)
    # 侧面草莓点缀
    c.set(3, 11, RD)
    c.set(12, 11, RD)
    # 顶部草莓（红果 + 绿叶 + 高光）
    c.rect(7, 3, 8, 5, RD)
    c.set(7, 2, GN)
    c.set(8, 2, GN)
    c.set(7, 3, W)
    return c


def build_cake():
    return {
        'id': 'tpl_cake', 'name': '草莓蛋糕',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('蛋糕', 1)], 'cells': [[cake()]],
    }


# ---------- tpl_sushi 寿司拼盘（food，24×24，1 帧） ----------

def nigiri(c, x0, fish):
    # 白饭圆角团（4宽6高：中带满行 + 上下行缩进）
    c.rect(x0, 12, x0 + 3, 15, W)
    c.rect(x0 + 1, 11, x0 + 2, 16, W)
    # 中线鱼片盖饭（2宽4高）+ 脂纹高光
    c.rect(x0 + 1, 12, x0 + 2, 15, fish)
    c.set(x0 + 1, 13, PE)


def sushi():
    c = Canvas(24, 24)
    # 寿司木板（深棕缘 + 棕面 + 上缘木纹）
    c.rect(1, 7, 22, 20, DGR)
    c.rect(2, 8, 21, 19, BR)
    c.line(3, 9, 20, 9, DGR)
    # 三贯握寿司：三文鱼（橙）/ 金枪鱼（红）/ 玉子烧（黄）
    nigiri(c, 3, O)
    nigiri(c, 8, RD)
    nigiri(c, 13, Y)
    # 山葵（绿）与姜片（粉）堆在板右缘
    c.rect(18, 12, 19, 13, GN)
    c.rect(18, 15, 19, 16, PK)
    return c


def build_sushi():
    return {
        'id': 'tpl_sushi', 'name': '寿司拼盘',
        'w': 24, 'h': 24, 'fps': 8, 'palette': 'pico8',
        'layers': [('拼盘', 1)], 'cells': [[sushi()]],
    }


# ---------- tpl_knight 小骑士（creatures，24×24，2 帧行走） ----------

def knight(frame):
    c = Canvas(24, 24)
    dy = 1 if frame == 1 else 0
    # 红缨 + 银盔（面缝）
    c.set(9, 1 + dy, RD)
    c.set(9, 2 + dy, RD)
    c.set(10, 3 + dy, RD)
    c.rect(8, 3 + dy, 14, 8 + dy, GR)
    c.set(8, 9 + dy, GR)
    c.set(14, 9 + dy, GR)
    c.rect(12, 5 + dy, 14, 5 + dy, BLK)
    # 胸甲 + 腰带 + 裙甲
    c.rect(7, 10 + dy, 15, 15 + dy, GR)
    c.rect(7, 12 + dy, 15, 12 + dy, DGR)
    c.rect(8, 16, 14, 17, GR)
    # 腿与靴（帧 0 跨步 / 帧 1 并步，整体一沉一浮）
    if frame == 0:
        c.rect(10, 18, 11, 20, PE)
        c.rect(14, 18, 15, 20, PE)
        c.rect(9, 21, 12, 21, DGR)
        c.rect(14, 21, 17, 21, DGR)
    else:
        c.rect(11, 18, 12, 19, PE)
        c.rect(14, 18, 15, 19, PE)
        c.rect(10, 20, 12, 20, DGR)
        c.rect(14, 20, 16, 20, DGR)
    # 剑（白刃 + 棕护手柄）
    c.set(18, 3 + dy, W)
    c.rect(18, 4 + dy, 18, 10 + dy, W)
    c.rect(16, 11 + dy, 19, 11 + dy, BR)
    c.set(18, 12 + dy, BR)
    # 盾（身后棕圆盾 + 白星徽）
    c.rect(4, 10 + dy, 6, 14 + dy, BR)
    c.set(5, 12 + dy, W)
    return c


def build_knight():
    cells = []
    for f in range(2):
        cells.append([knight(f)])
    return {
        'id': 'tpl_knight', 'name': '小骑士',
        'w': 24, 'h': 24, 'fps': 8, 'palette': 'pico8',
        'layers': [('骑士', 1)], 'cells': cells,
    }


# ---------- tpl_dragon 幼龙（creatures，32×32，2 帧扇翅） ----------

def dragon(frame):
    c = Canvas(32, 32)
    # 翅膀（暗紫膜翅：帧 0 上举 / 帧 1 平展）
    if frame == 0:
        tri_fill(c, 8, 14, 3, 5, 3, 13, B)
        tri_fill(c, 23, 14, 28, 5, 28, 13, B)
    else:
        tri_fill(c, 8, 13, 2, 10, 3, 16, B)
        tri_fill(c, 23, 13, 29, 10, 28, 16, B)
    # 头（绿圆头 + 肤橙下吻）
    c.circle(16, 9, 5, GN)
    c.rect(12, 14, 20, 14, GN)
    c.rect(13, 15, 19, 15, GN)
    c.rect(13, 12, 19, 13, PE)
    c.rect(14, 14, 18, 14, PE)
    c.set(14, 12, DGN)
    c.set(17, 12, DGN)
    # 眼（白底黑瞳）
    c.rect(12, 8, 14, 9, W)
    c.rect(17, 8, 19, 9, W)
    c.set(13, 9, BLK)
    c.set(18, 9, BLK)
    # 角（黄）
    c.set(12, 3, Y)
    c.set(11, 4, Y)
    c.set(13, 4, Y)
    c.set(19, 3, Y)
    c.set(20, 4, Y)
    c.set(18, 4, Y)
    # 身体（绿椭圆 + 肤橙肚）
    c.rect(10, 16, 21, 16, GN)
    c.rect(8, 17, 23, 25, GN)
    c.rect(10, 26, 21, 27, GN)
    c.rect(12, 17, 19, 25, PE)
    c.rect(13, 26, 18, 27, PE)
    # 蛇腹纹
    for y in [19, 22, 25]:
        c.rect(13, y, 18, y, BR)
    # 尾（绿卷尾 + 黄火苗尖，帧间摆动）
    if frame == 0:
        c.line(23, 22, 27, 24, GN)
        c.line(23, 23, 27, 25, GN)
        c.set(28, 25, GN)
        c.set(28, 24, Y)
        c.set(29, 25, Y)
        c.set(28, 26, Y)
    else:
        c.line(23, 22, 26, 26, GN)
        c.line(23, 23, 26, 27, GN)
        c.set(27, 27, GN)
        c.set(27, 26, Y)
        c.set(28, 27, Y)
        c.set(27, 28, Y)
    # 爪（绿脚 + 白趾甲）
    c.rect(9, 26, 12, 28, GN)
    c.rect(19, 26, 22, 28, GN)
    c.set(9, 29, W)
    c.set(11, 29, W)
    c.set(19, 29, W)
    c.set(21, 29, W)
    return c


def build_dragon():
    cells = []
    for f in range(2):
        cells.append([dragon(f)])
    return {
        'id': 'tpl_dragon', 'name': '幼龙',
        'w': 32, 'h': 32, 'fps': 6, 'palette': 'pico8',
        'layers': [('幼龙', 1)], 'cells': cells,
    }


# ---------- tpl_chest 宝箱（items，16×16，2 帧开合） ----------

def chest(frame):
    c = Canvas(16, 16)
    if frame == 0:
        # 合盖（弧顶盖 + 箱体 + 金箍 + 锁）
        c.rect(3, 4, 12, 4, BR)
        c.rect(1, 5, 14, 7, BR)
        c.rect(1, 8, 14, 13, BR)
        c.rect(1, 5, 1, 13, Y)
        c.rect(14, 5, 14, 13, Y)
        c.rect(1, 7, 14, 8, Y)
        c.rect(7, 8, 8, 9, Y)
        c.set(7, 10, BLK)
        c.set(8, 10, BLK)
    else:
        # 开盖（掀顶 + 金币溢光 + 闪光粒）
        c.rect(1, 1, 14, 2, BR)
        c.rect(2, 3, 13, 3, K)
        c.rect(1, 4, 14, 4, Y)
        c.set(3, 3, Y)
        c.set(8, 3, Y)
        c.set(12, 3, Y)
        c.set(4, 4, W)
        c.set(10, 4, W)
        c.rect(1, 5, 14, 12, BR)
        c.rect(2, 5, 13, 5, K)
        c.rect(1, 5, 1, 12, Y)
        c.rect(14, 5, 14, 12, Y)
        c.set(2, 0, W)
        c.set(7, 0, W)
        c.set(13, 0, W)
    return c


def build_chest():
    cells = []
    for f in range(2):
        cells.append([chest(f)])
    return {
        'id': 'tpl_chest', 'name': '宝箱',
        'w': 16, 'h': 16, 'fps': 4, 'palette': 'pico8',
        'layers': [('宝箱', 1)], 'cells': cells,
    }


# ---------- tpl_potion 魔法药水（items，16×16，1 帧） ----------

def potion():
    c = Canvas(16, 16)
    # 木塞
    c.rect(6, 1, 9, 2, BR)
    # 瓶颈壁（浅灰玻璃）
    c.rect(6, 3, 6, 5, GR)
    c.rect(9, 3, 9, 5, GR)
    # 瓶身（浅灰轮廓圆 + 掏空内腔）
    c.circle(8, 10, 5, GR)
    c.circle_erase(8, 10, 4)
    # 药液（粉，半瓶 + 深粉液面）
    for y in range(8, 15):
        for x in range(4, 13):
            if (x - 8) ** 2 + (y - 10) ** 2 <= 16:
                c.set(x, y, PK)
    for x in range(5, 12):
        if (x - 8) ** 2 + (8 - 10) ** 2 <= 16:
            c.set(x, 8, RD)
    # 气泡（白）
    c.set(10, 11, W)
    c.set(6, 13, W)
    c.set(9, 12, W)
    # 玻璃高光（白竖条）
    c.set(5, 9, W)
    c.set(5, 10, W)
    return c


def build_potion():
    return {
        'id': 'tpl_potion', 'name': '魔法药水',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('药水', 1)], 'cells': [[potion()]],
    }


# ---------- tpl_heart 爱心（glyphs，16×16，1 帧） ----------

def heart():
    c = Canvas(16, 16)
    rows = [
        (4, 5, 10, 11),
        (3, 6, 9, 12),
        (2, 12),
        (2, 13),
        (2, 13),
        (2, 13),
        (3, 12),
        (4, 11),
        (5, 10),
        (6, 9),
        (7, 8),
    ]
    for i, span in enumerate(rows):
        y = 2 + i
        if len(span) == 4:
            c.rect(span[0], y, span[1], y, RD)
            c.rect(span[2], y, span[3], y, RD)
        else:
            c.rect(span[0], y, span[1], y, RD)
    # 左上高光
    c.set(4, 3, W)
    c.set(5, 4, W)
    c.set(4, 4, W)
    c.set(3, 5, W)
    return c


def build_heart():
    return {
        'id': 'tpl_heart', 'name': '爱心',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('爱心', 1)], 'cells': [[heart()]],
    }


# ---------- tpl_star 闪耀星徽（glyphs，16×16，1 帧） ----------

def star():
    c = Canvas(16, 16)
    # 竖臂（上/下，黄）
    for y in range(1, 6):
        half = 0 if y <= 2 else 1
        c.rect(7 - half, y, 8 + half, y, Y)
    for y in range(10, 15):
        half = 1 if y <= 12 else 0
        c.rect(7 - half, y, 8 + half, y, Y)
    # 横臂（左/右）
    for x in range(1, 6):
        half = 0 if x <= 2 else 1
        c.rect(x, 7 - half, x, 8 + half, Y)
    for x in range(10, 15):
        half = 1 if x <= 12 else 0
        c.rect(x, 7 - half, x, 8 + half, Y)
    # 中心块 + 白芯
    c.rect(6, 6, 9, 9, Y)
    c.rect(7, 7, 8, 8, W)
    # 臂尖
    c.set(7, 0, Y)
    c.set(8, 0, Y)
    c.set(7, 15, Y)
    c.set(8, 15, Y)
    c.set(0, 7, Y)
    c.set(0, 8, Y)
    c.set(15, 7, Y)
    c.set(15, 8, Y)
    # 对角微光
    c.set(2, 2, W)
    c.set(13, 13, W)
    return c


def build_star():
    return {
        'id': 'tpl_star', 'name': '闪耀星徽',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('星徽', 1)], 'cells': [[star()]],
    }


# ---------- 登记表（分类序 → 注册序；desc 单行短句） ----------

# 既有示例（file 指向 rawfile 平铺文件，不复制不重生成）。
DEMOS = [
    dict(id='demo_cat', cat='animals', file='demo_cat.pxs',
         nameZh='星夜小猫', nameEn='Starry Night Cat',
         descZh='星空下眨眼的小猫', descEn='A kitten blinking under the stars',
         w=32, h=32, frames=3, fps=8),
    dict(id='demo_sunset', cat='scenery', file='demo_sunset.pxs',
         nameZh='落日海岸', nameEn='Sunset Coast',
         descZh='棕榈剪影与金色海面', descEn='Palm silhouettes on a golden sea',
         w=48, h=48, frames=1, fps=8),
    dict(id='demo_slime', cat='creatures', file='demo_slime.pxs',
         nameZh='果冻史莱姆', nameEn='Jelly Slime',
         descZh='压扁弹跳的绿色果冻', descEn='A green jelly bouncing along',
         w=16, h=16, frames=2, fps=6),
]

# 新模板：build 函数产出工程 dict（name 取 nameZh）。
NEW_BUILDS = [build_puppy, build_bird, build_forest, build_lake, build_cake,
              build_sushi, build_knight, build_dragon, build_chest, build_potion,
              build_heart, build_star]
NEW_META = {
    'tpl_puppy': dict(cat='animals', nameEn='Shiba Puppy',
                      descZh='奶油胸的摇尾小柴犬',
                      descEn='A tail-wagging shiba with a cream chest'),
    'tpl_bird': dict(cat='animals', nameEn='Blue Finch',
                     descZh='圆滚滚的蓝色小雀',
                     descEn='A round little blue finch'),
    'tpl_forest': dict(cat='scenery', nameEn='Misty Forest',
                       descZh='晨光穿透雾气的松林',
                       descEn='Pines in the morning mist'),
    'tpl_lake': dict(cat='scenery', nameEn='Dusk Lake',
                     descZh='晚霞山影与水面涟漪',
                     descEn='Sunset hills over rippling water'),
    'tpl_cake': dict(cat='food', nameEn='Strawberry Cake',
                     descZh='淋面蛋糕顶着一颗草莓',
                     descEn='A frosted cake with a strawberry on top'),
    'tpl_sushi': dict(cat='food', nameEn='Sushi Platter',
                      descZh='卷物、握寿司与玉子烧',
                      descEn='Rolls, nigiri and tamago'),
    'tpl_knight': dict(cat='creatures', nameEn='Little Knight',
                       descZh='迈步前进的银甲小骑士',
                       descEn='A silver knight marching along'),
    'tpl_dragon': dict(cat='creatures', nameEn='Baby Dragon',
                       descZh='扇着翅膀的绿色幼龙',
                       descEn='A green dragonet flapping its wings'),
    'tpl_chest': dict(cat='items', nameEn='Treasure Chest',
                      descZh='装满金币的老宝箱',
                      descEn='An old chest full of gold'),
    'tpl_potion': dict(cat='items', nameEn='Magic Potion',
                       descZh='冒泡的粉色药水',
                       descEn='A bubbling pink potion'),
    'tpl_heart': dict(cat='glyphs', nameEn='Pixel Heart',
                      descZh='经典像素爱心',
                      descEn='A classic pixel heart'),
    'tpl_star': dict(cat='glyphs', nameEn='Sparkle Star',
                     descZh='四角闪亮像素星',
                     descEn='A four-pointed sparkle'),
}


def registry():
    """构建登记表：build 工程 dict → 统一 entry dict 列表（分类序 → 注册序）。"""
    entries = []
    for build in NEW_BUILDS:
        p = build()
        meta = NEW_META[p['id']]
        entries.append(dict(
            id=p['id'], cat=meta['cat'], file=f"templates/{p['id']}.pxs",
            nameZh=p['name'], nameEn=meta['nameEn'],
            descZh=meta['descZh'], descEn=meta['descEn'],
            w=p['w'], h=p['h'], frames=len(p['cells']), fps=p['fps'],
            _project=p))
    for d in DEMOS:
        e = dict(d)
        e['_project'] = None
        entries.append(e)
    # 排序：分类展示序 → 注册序稳定。
    order = {cat: i for i, cat in enumerate(CATEGORIES)}
    entries.sort(key=lambda e: (order[e['cat']],))
    return entries


# ---------- 发射 ----------

def emit_rawfiles(entries):
    os.makedirs(TEMPLATES_DIR, exist_ok=True)
    for e in entries:
        p = e['_project']
        if p is None:
            continue
        pxs = serialize_pxs(p)
        with open(os.path.join(TEMPLATES_DIR, f"{p['id']}.pxs"), 'wb') as f:
            f.write(pxs)
        with open(os.path.join(TEMPLATES_DIR, f"{p['id']}.thumb"), 'wb') as f:
            f.write(make_thumb(p))
        print(f"{p['id']}: {e['nameZh']} {e['w']}x{e['h']} frames={e['frames']} "
              f"pxs={len(pxs)}B")


def emit_defs_ets(entries):
    lines = []
    lines.append('/**')
    lines.append(' * viewmodel/TemplateDefs.ets — 分类模板库清单（长期任务，章程见')
    lines.append(' * docs/模板库长期任务章程.md）。')
    lines.append(' *')
    lines.append(' * !!! 本文件由 scripts/make_templates.py 生成，请勿手改：')
    lines.append(' *     调整模板请编辑 make_templates.py 后运行 py -3 scripts/make_templates.py')
    lines.append(' *     重新生成，并以 py -3 scripts/verify_templates.py 校验。')
    lines.append(' */')
    lines.append('')
    lines.append('/** 模板条目：rawfile 相对路径 + 双语名称/描述 + 规格。 */')
    lines.append('export class TemplateDef {')
    lines.append('  id: string = \'\';')
    lines.append('  /** 分类（TPL_CATEGORIES 之一；页签文案 app.string.tpl_cat_<cat>）。 */')
    lines.append('  cat: string = \'\';')
    lines.append('  /** .pxs rawfile 相对路径（如 \'templates/tpl_puppy.pxs\'、\'demo_cat.pxs\'）。 */')
    lines.append('  file: string = \'\';')
    lines.append('  nameZh: string = \'\';')
    lines.append('  nameEn: string = \'\';')
    lines.append('  descZh: string = \'\';')
    lines.append('  descEn: string = \'\';')
    lines.append('  w: number = 0;')
    lines.append('  h: number = 0;')
    lines.append('  frames: number = 0;')
    lines.append('  fps: number = 0;')
    lines.append('}')
    lines.append('')
    lines.append('/** 分类展示序（页签顺序；文案键 tpl_cat_<cat>）。 */')
    lines.append('export const TPL_CATEGORIES: string[] = [')
    for cat in CATEGORIES:
        lines.append(f"  '{cat}',")
    lines.append('];')
    lines.append('')
    lines.append(f"/** 全部模板（{len(entries)} 个 = 12 新原创 + 3 示例工程；分类序 → 注册序）。 */")
    lines.append('export const TEMPLATE_DEFS: TemplateDef[] = [')
    for e in entries:
        lines.append('  {')
        lines.append(f"    id: '{e['id']}', cat: '{e['cat']}', file: '{e['file']}',")
        lines.append(f"    nameZh: '{e['nameZh']}', nameEn: '{e['nameEn']}',")
        lines.append(f"    descZh: '{e['descZh']}', descEn: '{e['descEn']}',")
        lines.append(f"    w: {e['w']}, h: {e['h']}, frames: {e['frames']}, fps: {e['fps']}")
        lines.append('  },')
    lines.append('];')
    with open(DEFS_ETS, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'TemplateDefs.ets: {len(entries)} entries')


def emit_manifest(entries):
    out = {
        'categories': CATEGORIES,
        'entries': [{k: v for k, v in e.items() if not k.startswith('_')}
                    for e in entries],
    }
    with open(MANIFEST_JSON, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'templates_manifest.json: {len(entries)} entries')


def main():
    entries = registry()
    ids = [e['id'] for e in entries]
    assert len(ids) == len(set(ids)), 'duplicate id'
    for e in entries:
        assert e['cat'] in CATEGORIES, f"bad cat: {e['id']}"
    emit_rawfiles(entries)
    emit_defs_ets(entries)
    emit_manifest(entries)
    print(f'output root: {REPO_ROOT}')


if __name__ == '__main__':
    main()
