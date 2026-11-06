# -*- coding: utf-8 -*-
"""
make_templates.py — 分类模板库生成器（长期任务，章程 docs/模板库长期任务章程.md）。

单一事实源：本脚本登记全部模板（第一批 12 + 第二批 12 新原创 + 3 既有示例），
运行后发射三类产物：
  1. entry/src/main/resources/rawfile/templates/{id}.pxs + {id}.thumb（新模板；
     3 个示例沿用 rawfile 平铺既有文件，不复制）；
  2. entry/src/main/ets/viewmodel/TemplateDefs.ets —— 生成的 typed 清单（ArkTS 侧
     编译期类型安全，规避 JSON.parse 运行时类型断言）；
  3. scripts/templates_manifest.json —— 仅供 verify_templates.py 消费（应用不读）。

不侵权纪律（章程）：全部程序化原创绘制；题材取泛型原型；调色板用 PICO-8 公开色值
（色值不受版权保护）；命名避开商标词。

用法：py -3 scripts/make_templates.py（在仓库根运行；输出确定性，重跑字节一致）。
"""
import json
import math
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


# ====================================================================
# 第二批（1.4.0）：12 个新原创模板，每类 2 个
# ====================================================================

# ---------- tpl_rabbit 白玉兔（animals，16×16，1 帧） ----------

def rabbit():
    c = Canvas(16, 16)
    # 双长耳（白外粉内，耳尖圆）
    c.rect(4, 0, 5, 1, W)
    c.rect(4, 2, 5, 4, W)
    c.rect(4, 2, 4, 4, PK)
    c.rect(10, 0, 11, 1, W)
    c.rect(10, 2, 11, 4, W)
    c.rect(11, 2, 11, 4, PK)
    # 头身（白蛋形坐姿）
    c.rect(4, 5, 11, 5, W)
    c.rect(3, 6, 12, 11, W)
    c.rect(4, 12, 11, 13, W)
    # 眼（黑）+ 眉间
    c.set(5, 8, BLK)
    c.set(10, 8, BLK)
    # 鼻与嘴（粉）
    c.set(7, 10, PK)
    c.set(8, 10, PK)
    c.set(6, 11, PK)
    c.set(9, 11, PK)
    # 腮红
    c.set(3, 10, PK)
    c.set(12, 10, PK)
    # 前脚
    c.rect(5, 14, 6, 14, W)
    c.rect(9, 14, 10, 14, W)
    # 草地点缀
    c.set(0, 15, GN)
    c.set(2, 15, GN)
    c.set(13, 15, GN)
    c.set(15, 15, GN)
    return c


def build_rabbit():
    return {
        'id': 'tpl_rabbit', 'name': '白玉兔',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('白兔', 1)], 'cells': [[rabbit()]],
    }


# ---------- tpl_penguin 小企鹅（animals，16×16，1 帧） ----------

def penguin():
    c = Canvas(16, 16)
    # 体外轮廓（黑）
    c.rect(5, 1, 10, 1, BLK)
    c.rect(4, 2, 11, 3, BLK)
    c.rect(3, 4, 12, 11, BLK)
    c.rect(4, 12, 11, 12, BLK)
    c.rect(5, 13, 10, 13, BLK)
    # 白脸白腹（连成一片）
    c.rect(5, 2, 10, 2, W)
    c.rect(5, 3, 10, 4, W)
    c.rect(4, 5, 11, 5, W)
    c.rect(4, 6, 11, 10, W)
    c.rect(5, 11, 10, 12, W)
    # 眼（黑，白脸上）
    c.set(6, 4, BLK)
    c.set(9, 4, BLK)
    # 喙（橙，脸下缘中央）
    c.rect(7, 5, 8, 6, O)
    # 翅膀（黑侧鳍）
    c.rect(3, 6, 3, 10, BLK)
    c.rect(12, 6, 12, 10, BLK)
    c.set(2, 7, BLK)
    c.set(13, 7, BLK)
    # 脚（橙）
    c.rect(5, 14, 7, 14, O)
    c.rect(8, 14, 10, 14, O)
    # 冰晶与雪点
    c.set(0, 12, BL)
    c.set(15, 10, BL)
    c.set(1, 2, W)
    return c


def build_penguin():
    return {
        'id': 'tpl_penguin', 'name': '小企鹅',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('企鹅', 1)], 'cells': [[penguin()]],
    }


# ---------- tpl_volcano 喷发火山（scenery，48×48，2 层 1 帧） ----------

def volcano_sky():
    c = Canvas(48, 48)
    # 夜空渐变（暗蓝 → 暗紫）
    c.lerp_band([(0.0, K), (0.7, B), (1.0, K)])
    # 星
    for x, y in [(4, 3), (9, 7), (14, 2), (20, 5), (27, 3), (33, 6),
                 (40, 2), (45, 5), (6, 12), (42, 11), (18, 10)]:
        c.set(x, y, W)
    # 满月（黄 + 陨坑）
    c.circle(39, 9, 3, Y)
    c.set(38, 8, PE)
    c.set(40, 10, PE)
    return c


def volcano_fg():
    c = Canvas(48, 48)
    # 上升烟柱（暗灰）
    c.rect(23, 1, 25, 5, DGR)
    c.set(21, 3, DGR)
    c.set(27, 4, DGR)
    # 喷发冠（红橙蘑菇团 + 亮黄芯）
    c.circle(24, 6, 4, RD)
    c.circle(19, 9, 3, RD)
    c.circle(29, 9, 3, RD)
    c.circle(24, 10, 5, O)
    c.circle(24, 12, 3, Y)
    # 火花四溅
    for x, y in [(15, 4), (33, 5), (12, 10), (36, 12), (18, 2), (30, 2)]:
        c.set(x, y, Y)
    # 火山锥（深灰梯形：口宽 8 → 底宽 30）
    for y in range(12, 44):
        t = (y - 12) / 31
        half = 4 + round(t * 11)
        c.rect(24 - half, y, 24 + half, y, DGR)
    # 火山口缘（暗）
    c.rect(19, 12, 29, 13, BLK)
    # 熔岩流（红橙分叉沿锥面而下）
    c.line(24, 13, 22, 20, RD)
    c.line(22, 20, 20, 28, O)
    c.line(20, 28, 19, 36, RD)
    c.line(24, 13, 27, 19, RD)
    c.line(27, 19, 28, 27, O)
    c.rect(24, 13, 24, 16, Y)
    # 山脚熔岩池（红面 + 亮入水斑）
    c.rect(8, 44, 39, 47, BR)
    c.rect(8, 44, 39, 44, RD)
    c.set(19, 45, O)
    c.set(20, 45, Y)
    c.set(28, 45, O)
    return c


def build_volcano():
    return {
        'id': 'tpl_volcano', 'name': '喷发火山',
        'w': 48, 'h': 48, 'fps': 8, 'palette': 'pico8',
        'layers': [('夜空', 1), ('火山', 2)],
        'cells': [[volcano_sky(), volcano_fg()]],
    }


# ---------- tpl_igloo 极光雪屋（scenery，32×32，1 帧） ----------

def igloo():
    c = Canvas(32, 32)
    # 夜空渐变（暗蓝 → 暗紫）
    c.lerp_band([(0.0, K), (1.0, B)])
    # 星
    for x, y in [(3, 2), (8, 5), (14, 1), (22, 3), (28, 6), (26, 1), (18, 6)]:
        c.set(x, y, W)
    # 极光带（绿主带 + 粉缘，正弦波动竖排）
    for x in range(2, 30):
        y0 = 4 + int(2 * math.sin(x * 0.55))
        c.set(x, y0, W)
        for dy in range(1, 4):
            c.set(x, y0 + dy, GN)
        c.set(x, y0 + 4, PK)
    # 冰屋（浅灰圆拱 + 深灰砖缝）
    c.circle(10, 22, 7, GR)
    c.rect(3, 22, 17, 22, GR)
    c.line(4, 18, 16, 18, DGR)
    for bx in (6, 10, 14):
        c.set(bx, 16, DGR)
    c.set(5, 20, DGR)
    c.set(15, 20, DGR)
    # 雪地（重铺盖掉冰屋下半）+ 雪线
    c.rect(0, 22, 31, 31, W)
    c.rect(0, 22, 31, 22, GR)
    for x in range(0, 32, 4):
        c.set(x, 26, GR)
        c.set(x + 1, 29, GR)
    # 门洞（暗蓝内腔 + 门口暖光雪反）
    c.rect(8, 16, 12, 22, K)
    c.set(8, 15, K)
    c.set(12, 15, K)
    c.set(7, 23, Y)
    c.set(8, 23, PE)
    c.set(13, 23, PE)
    # 小雪人（白两球 + 橙鼻黑眼扣）
    c.circle(25, 26, 2, W)
    c.circle(25, 22, 1, W)
    c.set(24, 22, BLK)
    c.set(26, 22, O)
    c.set(25, 25, BLK)
    c.set(25, 27, BLK)
    return c


def build_igloo():
    return {
        'id': 'tpl_igloo', 'name': '极光雪屋',
        'w': 32, 'h': 32, 'fps': 8, 'palette': 'pico8',
        'layers': [('极光雪原', 1)], 'cells': [[igloo()]],
    }


# ---------- tpl_ramen 拉面碗（food，24×24，1 帧） ----------

def ramen():
    c = Canvas(24, 24)
    # 汤面（碗口上方可见部分）
    c.rect(3, 4, 20, 7, PE)
    # 面条（黄波浪沉在汤里）
    c.line(4, 6, 8, 5, Y)
    c.line(8, 5, 12, 6, Y)
    c.line(12, 6, 16, 5, Y)
    c.line(16, 5, 19, 6, Y)
    # 溏心蛋（白蛋白 + 橙黄蛋心）
    c.rect(4, 4, 8, 6, W)
    c.rect(6, 5, 7, 5, O)
    # 鱼板（白圆 + 粉螺旋纹）
    c.circle(17, 5, 2, W)
    c.set(17, 4, PK)
    c.set(16, 5, PK)
    c.set(18, 6, PK)
    # 撒葱花（绿点）
    c.set(10, 4, GN)
    c.set(12, 7, GN)
    c.set(14, 4, DGN)
    c.set(9, 7, GN)
    # 筷子（棕，斜搭右上）
    c.line(13, 1, 22, 7, BR)
    c.line(15, 1, 22, 9, BR)
    # 热气（浅灰缕）
    c.set(6, 1, GR)
    c.set(9, 2, GR)
    c.set(12, 1, GR)
    # 碗沿（白）
    c.rect(2, 8, 21, 9, W)
    # 碗身（红，上宽下收）+ 左缘粉高光
    c.rect(3, 10, 20, 16, RD)
    c.rect(4, 17, 19, 18, RD)
    c.rect(3, 10, 3, 16, PK)
    # 碗身白纹带（波浪三点）
    c.rect(5, 13, 8, 13, W)
    c.rect(10, 15, 13, 15, W)
    c.rect(15, 13, 18, 13, W)
    # 碗足（暗紫）
    c.rect(7, 19, 16, 19, B)
    c.rect(8, 20, 15, 20, B)
    return c


def build_ramen():
    return {
        'id': 'tpl_ramen', 'name': '拉面碗',
        'w': 24, 'h': 24, 'fps': 8, 'palette': 'pico8',
        'layers': [('拉面', 1)], 'cells': [[ramen()]],
    }


# ---------- tpl_icecream 双色甜筒（food，16×16，1 帧） ----------

def icecream():
    c = Canvas(16, 16)
    # 甜筒（棕锥体）
    c.rect(4, 9, 11, 9, BR)
    c.rect(5, 10, 10, 10, BR)
    c.rect(5, 11, 10, 11, BR)
    c.rect(6, 12, 9, 12, BR)
    c.rect(7, 13, 8, 13, BR)
    c.set(7, 14, BR)
    c.set(8, 14, BR)
    # 华夫格纹（深灰斜点）
    c.set(5, 9, DGR)
    c.set(7, 9, DGR)
    c.set(10, 9, DGR)
    c.set(6, 11, DGR)
    c.set(9, 11, DGR)
    c.set(8, 13, DGR)
    # 粉球主体（草莓味）
    c.circle(8, 5, 4, PK)
    # 白漩涡纹（香草旋纹）
    c.rect(5, 3, 6, 4, W)
    c.set(4, 5, W)
    c.set(5, 6, W)
    c.rect(9, 6, 10, 7, W)
    c.set(10, 5, W)
    c.set(11, 4, W)
    # 顶尖（粉 + 白高光）
    c.set(8, 1, PK)
    c.set(7, 2, PK)
    c.set(9, 2, PK)
    c.set(8, 2, W)
    return c


def build_icecream():
    return {
        'id': 'tpl_icecream', 'name': '双色甜筒',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('甜筒', 1)], 'cells': [[icecream()]],
    }


# ---------- tpl_ghost 小幽灵（creatures，16×16，2 帧漂浮） ----------

def ghost(frame):
    c = Canvas(16, 16)
    dy = 1 if frame == 1 else 0
    # 头（圆 + 肩补齐）
    c.circle(7, 4 + dy, 3, W)
    c.rect(5, 4 + dy, 11, 4 + dy, W)
    c.set(11, 5 + dy, W)
    # 身体（8 宽矩形）
    c.rect(4, 5 + dy, 11, 12 + dy, W)
    if frame == 0:
        # 波浪下摆：齿 x4-5 / x8-9，谷 x6-7 / x10-11
        c.rect(4, 13, 5, 13, W)
        c.rect(8, 13, 9, 13, W)
        c.set(4, 14, W)
        c.set(9, 14, W)
    else:
        # 平摆（下压贴地感）
        c.rect(4, 13 + dy, 11, 13 + dy, W)
    # 眼（黑瞳 + 白高光；帧间眼神微移）
    ex = 1 if frame == 1 else 0
    c.rect(5, 6 + dy, 6, 8 + dy, BLK)
    c.rect(9, 6 + dy, 10, 8 + dy, BLK)
    c.set(5 + ex, 6 + dy, W)
    c.set(9 + ex, 6 + dy, W)
    # 腮红 + 小口
    c.set(4, 9 + dy, PK)
    c.set(11, 9 + dy, PK)
    c.set(7, 10 + dy, BLK)
    c.set(8, 10 + dy, BLK)
    return c


def build_ghost():
    cells = []
    for f in range(2):
        cells.append([ghost(f)])
    return {
        'id': 'tpl_ghost', 'name': '小幽灵',
        'w': 16, 'h': 16, 'fps': 6, 'palette': 'pico8',
        'layers': [('幽灵', 1)], 'cells': cells,
    }


# ---------- tpl_mushroom 蘑菇小人（creatures，16×16，1 帧） ----------

def mushroom():
    c = Canvas(16, 16)
    # 菌盖（红半圆伞 + 白点）
    c.circle(7, 6, 6, RD, ymax=7)
    c.rect(1, 6, 13, 7, RD)
    c.set(4, 3, W)
    c.set(5, 3, W)
    c.set(4, 4, W)
    c.set(9, 3, W)
    c.set(10, 4, W)
    c.set(7, 2, W)
    c.set(2, 6, W)
    c.set(12, 6, W)
    # 盖底缘（暗紫收边）
    c.rect(1, 7, 13, 7, B)
    # 茎身脸（米白）
    c.rect(4, 8, 10, 13, W)
    c.rect(5, 14, 9, 14, W)
    # 眼 + 腮红 + 微笑
    c.set(6, 10, BLK)
    c.set(9, 10, BLK)
    c.set(5, 11, PK)
    c.set(10, 11, PK)
    c.set(7, 12, BLK)
    c.set(8, 12, BLK)
    # 小侧手
    c.set(3, 10, W)
    c.set(3, 11, W)
    c.set(11, 10, W)
    c.set(11, 11, W)
    return c


def build_mushroom():
    return {
        'id': 'tpl_mushroom', 'name': '蘑菇小人',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('蘑菇', 1)], 'cells': [[mushroom()]],
    }


# ---------- tpl_sword 宝剑（items，16×16，1 帧） ----------

def sword():
    c = Canvas(16, 16)
    # 剑尖 + 剑刃（银白 + 中脊阴影线）
    c.set(7, 0, W)
    c.set(8, 0, W)
    c.rect(7, 1, 8, 1, W)
    c.rect(6, 2, 9, 2, W)
    c.rect(6, 3, 9, 8, W)
    c.rect(7, 3, 7, 8, GR)
    # 护手（金横条 + 端头圆饰 + 橙暗缘）
    c.rect(3, 9, 12, 10, Y)
    c.set(2, 9, Y)
    c.set(2, 10, Y)
    c.set(13, 9, Y)
    c.set(13, 10, Y)
    c.set(3, 9, O)
    c.set(12, 10, O)
    # 柄（棕缠绳 + 深灰缠纹）
    c.rect(7, 11, 8, 13, BR)
    c.set(7, 12, DGR)
    c.set(8, 11, DGR)
    c.set(8, 13, DGR)
    # 柄头圆饰（金框 + 红宝石心）
    c.rect(6, 14, 9, 15, Y)
    c.set(6, 14, O)
    c.set(9, 15, O)
    c.set(7, 14, RD)
    c.set(8, 15, RD)
    return c


def build_sword():
    return {
        'id': 'tpl_sword', 'name': '宝剑',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('宝剑', 1)], 'cells': [[sword()]],
    }


# ---------- tpl_lantern 纸提灯（items，16×16，2 帧烛光闪动） ----------

def lantern(frame):
    c = Canvas(16, 16)
    # 吊环 + 顶盖
    c.set(7, 0, DGR)
    c.set(8, 0, DGR)
    c.rect(5, 1, 10, 2, DGR)
    # 灯身（帧 0 亮黄 / 帧 1 暗橙，烛光强弱）
    body = Y if frame == 0 else O
    c.rect(4, 3, 11, 11, body)
    c.set(3, 5, body)
    c.set(3, 9, body)
    c.set(12, 5, body)
    c.set(12, 9, body)
    # 竖棱骨架（红）
    c.rect(5, 3, 5, 11, RD)
    c.rect(10, 3, 10, 11, RD)
    # 上下收边（红）
    c.rect(5, 3, 10, 3, RD)
    c.rect(5, 11, 10, 11, RD)
    # 腔心火苗（帧 0 双白芯 / 帧 1 单白芯）
    if frame == 0:
        c.set(7, 5, W)
        c.set(8, 5, W)
        c.set(7, 6, Y)
        c.set(8, 6, Y)
        c.set(7, 7, O)
        c.set(8, 7, O)
    else:
        c.set(7, 5, W)
        c.set(7, 6, Y)
        c.set(8, 6, Y)
        c.set(8, 7, O)
    # 底盖（深灰）+ 黄流苏
    c.rect(5, 12, 10, 13, DGR)
    c.set(7, 14, Y)
    c.set(8, 14, Y)
    c.set(7, 15, Y)
    c.set(8, 15, Y)
    return c


def build_lantern():
    cells = []
    for f in range(2):
        cells.append([lantern(f)])
    return {
        'id': 'tpl_lantern', 'name': '纸提灯',
        'w': 16, 'h': 16, 'fps': 6, 'palette': 'pico8',
        'layers': [('提灯', 1)], 'cells': cells,
    }


# ---------- tpl_skull 骷髅头（glyphs，16×16，1 帧） ----------

def skull():
    c = Canvas(16, 16)
    # 颅顶（白圆）+ 面部下颌（白）
    c.circle(7, 6, 5, W)
    c.rect(4, 10, 11, 12, W)
    c.rect(5, 13, 10, 13, W)
    c.set(7, 14, W)
    c.set(8, 14, W)
    # 眼窝（黑大双圆）
    c.circle(5, 7, 2, BLK)
    c.circle(10, 7, 2, BLK)
    # 鼻洞（黑倒三角）
    c.set(7, 10, BLK)
    c.set(8, 10, BLK)
    c.set(7, 11, BLK)
    # 牙缝（深灰竖缝分齿）
    c.set(6, 13, DGR)
    c.set(9, 13, DGR)
    # 颅侧阴影 + 顶高光
    c.set(3, 9, GR)
    c.set(12, 9, GR)
    c.set(6, 2, GR)
    c.set(7, 2, GR)
    return c


def build_skull():
    return {
        'id': 'tpl_skull', 'name': '骷髅头',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('骷髅', 1)], 'cells': [[skull()]],
    }


# ---------- tpl_moon 弯月（glyphs，16×16，1 帧） ----------

def moon():
    c = Canvas(16, 16)
    # 弯月（外圆减去偏移咬圆，留下左下弯钩）
    for y in range(16):
        for x in range(16):
            d1 = (x - 7) ** 2 + (y - 8) ** 2
            d2 = (x - 11) ** 2 + (y - 5) ** 2
            if d1 <= 30 and d2 > 27:
                c.set(x, y, Y)
    # 月面陨坑（肤橙暗斑）
    c.set(5, 6, PE)
    c.set(6, 6, PE)
    c.set(4, 10, PE)
    c.set(6, 11, PE)
    # 环星（四芒白星 + 散点）
    c.set(12, 3, W)
    c.set(11, 4, W)
    c.set(13, 4, W)
    c.set(12, 5, W)
    c.set(3, 2, W)
    c.set(10, 13, W)
    return c


def build_moon():
    return {
        'id': 'tpl_moon', 'name': '弯月',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('弯月', 1)], 'cells': [[moon()]],
    }


# ====================================================================
# 第三批（1.5.0）：12 个新原创模板，每类 2 个
# ====================================================================

# ---------- tpl_turtle 小海龟（animals，16×16，1 帧） ----------

def turtle():
    c = Canvas(16, 16)
    # 壳（深绿外圈 + 绿壳面）
    c.circle(7, 7, 5, DGN)
    c.circle(7, 7, 4, GN)
    c.rect(4, 6, 11, 9, GN)
    # 壳纹（深绿裂纹）
    c.set(6, 5, DGN)
    c.set(8, 5, DGN)
    c.set(5, 8, DGN)
    c.set(9, 8, DGN)
    c.set(7, 7, DGN)
    # 头（右侧伸出）
    c.rect(12, 6, 14, 8, GN)
    c.set(15, 7, GN)
    # 眼（黑）
    c.set(13, 6, BLK)
    # 腿（绿短腿）
    c.rect(4, 11, 5, 12, GN)
    c.rect(10, 11, 11, 12, GN)
    # 尾
    c.set(2, 10, GN)
    # 沙地点缀
    c.set(1, 14, Y)
    c.set(6, 14, Y)
    c.set(11, 14, Y)
    return c


def build_turtle():
    return {
        'id': 'tpl_turtle', 'name': '小海龟',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('海龟', 1)], 'cells': [[turtle()]],
    }


# ---------- tpl_fish 热带鱼（animals，16×16，1 帧） ----------

def fish():
    c = Canvas(16, 16)
    # 身体（橙椭圆）
    c.circle(7, 7, 4, O)
    c.rect(3, 5, 12, 9, O)
    # 尾鳍（黄三角）
    tri_fill(c, 4, 7, 1, 4, 1, 10, Y)
    # 背鳍/腹鳍（黄）
    c.rect(6, 2, 8, 3, Y)
    c.set(5, 3, Y)
    c.rect(6, 11, 8, 12, Y)
    c.set(5, 12, Y)
    # 红条纹
    c.rect(6, 4, 6, 10, RD)
    c.rect(9, 4, 9, 10, RD)
    # 眼（白底黑瞳）
    c.set(11, 5, W)
    c.set(11, 6, BLK)
    # 嘴（红）
    c.set(13, 8, RD)
    # 气泡（亮蓝）
    c.set(13, 3, BL)
    c.set(14, 1, BL)
    return c


def build_fish():
    return {
        'id': 'tpl_fish', 'name': '热带鱼',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('小鱼', 1)], 'cells': [[fish()]],
    }


# ---------- tpl_waterfall 林间瀑布（scenery，48×48，2 层 1 帧） ----------

def waterfall_bg():
    c = Canvas(48, 48)
    # 晨空渐变（亮蓝 → 米白）
    c.lerp_band([(0.0, BL), (1.0, W)])
    # 云
    c.rect(20, 4, 26, 4, W)
    c.set(19, 5, W)
    c.set(25, 5, W)
    # 远山松（深绿剪影）
    for x0, h in [(4, 9), (13, 12), (35, 11), (44, 8)]:
        pine(c, x0, 20, h, DGN)
    return c


def waterfall_fg():
    c = Canvas(48, 48)
    # 崖壁（两侧绿壁 + 深绿顶缘）
    c.rect(0, 12, 15, 47, GN)
    c.rect(32, 12, 47, 47, GN)
    c.rect(0, 12, 47, 14, DGN)
    # 崖壁暗纹
    for y in range(16, 47, 4):
        c.rect(2, y, 4, y, DGN)
        c.rect(42, y + 2, 44, y + 2, DGN)
    # 崖顶树
    pine(c, 5, 12, 6, GN)
    pine(c, 11, 12, 5, GN)
    pine(c, 39, 12, 6, GN)
    pine(c, 44, 12, 5, GN)
    # 瀑布（白柱 + 浅灰流纹 + 亮蓝顶缘）
    c.rect(16, 12, 31, 40, W)
    for y in range(13, 40, 3):
        c.rect(18, y, 20, y, GR)
        c.rect(26, y + 1, 28, y + 1, GR)
    c.rect(16, 12, 31, 12, BL)
    # 水潭（亮蓝 + 白水花）
    c.rect(12, 41, 35, 47, BL)
    c.rect(12, 41, 35, 41, W)
    for x, y in [(14, 43), (20, 45), (28, 43), (33, 45), (24, 46)]:
        c.set(x, y, W)
    # 潭边草
    c.set(10, 42, GN)
    c.set(9, 44, DGN)
    c.set(37, 42, GN)
    c.set(38, 44, DGN)
    return c


def build_waterfall():
    return {
        'id': 'tpl_waterfall', 'name': '林间瀑布',
        'w': 48, 'h': 48, 'fps': 8, 'palette': 'pico8',
        'layers': [('晨空', 1), ('瀑布', 2)],
        'cells': [[waterfall_bg(), waterfall_fg()]],
    }


# ---------- tpl_terrace 黄昏梯田（scenery，32×32，1 帧） ----------

def terrace():
    c = Canvas(32, 32)
    # 暮空渐变（暗紫 → 粉 → 肤橙）
    c.lerp_band([(0.0, B), (0.4, PK), (1.0, PE)])
    # 夕阳（黄圆 + 白心）
    c.circle(22, 6, 3, Y)
    c.set(22, 5, W)
    # 飞鸟（人字）
    c.set(8, 6, BLK)
    c.set(9, 5, BLK)
    c.set(10, 6, BLK)
    c.set(13, 8, BLK)
    c.set(14, 7, BLK)
    c.set(15, 8, BLK)
    # 梯田层带（自上而下逐层整片填充，后层被前层盖出层叠）
    layers = [(11, GN), (14, DGN), (17, GN), (20, DGN),
              (23, GN), (26, DGN), (29, Y)]
    for y0, col in layers:
        for x in range(32):
            yy = y0 + (1 if x % 6 < 2 else 0)
            for y in range(yy, 32):
                c.set(x, y, col)
    # 田埂暗纹（绿层沿点缀）
    for y0 in (11, 17, 23):
        for x in range(0, 32, 6):
            c.set(x, y0, DGN)
    return c


def build_terrace():
    return {
        'id': 'tpl_terrace', 'name': '黄昏梯田',
        'w': 32, 'h': 32, 'fps': 8, 'palette': 'pico8',
        'layers': [('梯田', 1)], 'cells': [[terrace()]],
    }


# ---------- tpl_burger 芝士汉堡（food，16×16，1 帧） ----------

def burger():
    c = Canvas(16, 16)
    # 顶包（肤橙圆顶 + 白芝麻）
    c.circle(7, 5, 5, PE, ymax=5)
    c.rect(2, 5, 12, 5, PE)
    c.set(4, 2, W)
    c.set(7, 1, W)
    c.set(10, 3, W)
    # 生菜（绿满行 + 波浪垂缘）
    c.rect(2, 6, 13, 6, GN)
    for x in range(2, 14, 3):
        c.set(x, 7, GN)
    # 肉饼（棕 + 深灰烤纹）
    c.rect(2, 8, 13, 9, BR)
    c.set(4, 8, DGR)
    c.set(8, 8, DGR)
    c.set(11, 9, DGR)
    # 芝士（黄滴沿）
    c.rect(3, 10, 12, 10, Y)
    c.set(3, 11, Y)
    c.set(12, 11, Y)
    # 底包（肤橙）
    c.rect(2, 11, 13, 12, PE)
    c.rect(3, 13, 12, 13, PE)
    return c


def build_burger():
    return {
        'id': 'tpl_burger', 'name': '芝士汉堡',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('汉堡', 1)], 'cells': [[burger()]],
    }


# ---------- tpl_cocoa 热可可（food，16×16，1 帧） ----------

def cocoa():
    c = Canvas(16, 16)
    # 热气（浅灰缕 + 白顶）
    c.set(5, 3, GR)
    c.set(5, 2, W)
    c.set(8, 2, GR)
    c.set(8, 1, W)
    c.set(11, 3, GR)
    c.set(11, 2, W)
    # 杯沿（白）
    c.rect(3, 6, 12, 6, W)
    # 可可液面近沿（棕）
    c.rect(4, 7, 11, 7, BR)
    # 杯身（红）
    c.rect(4, 8, 11, 11, RD)
    c.rect(5, 12, 10, 12, RD)
    c.rect(6, 13, 9, 13, RD)
    # 杯身白点纹
    c.set(6, 9, W)
    c.set(9, 9, W)
    c.set(7, 10, W)
    # 把手（右侧红环）
    c.rect(12, 8, 13, 10, RD)
    c.set(13, 7, RD)
    c.set(13, 11, RD)
    # 碟（浅灰）
    c.rect(2, 14, 13, 14, GR)
    return c


def build_cocoa():
    return {
        'id': 'tpl_cocoa', 'name': '热可可',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('热饮', 1)], 'cells': [[cocoa()]],
    }


# ---------- tpl_bat 小蝙蝠（creatures，16×16，2 帧扇翅） ----------

def bat(frame):
    c = Canvas(16, 16)
    dy = 1 if frame == 1 else 0
    # 翅膀（暗紫膜翅：帧 0 上举 / 帧 1 平展下压）
    if frame == 0:
        tri_fill(c, 5, 5 + dy, 1, 2, 1, 7 + dy, B)
        tri_fill(c, 10, 5 + dy, 14, 2, 14, 7 + dy, B)
    else:
        tri_fill(c, 5, 7, 0, 7, 1, 11, B)
        tri_fill(c, 10, 7, 15, 7, 14, 11, B)
    # 身体（暗紫圆 + 矩形）
    c.circle(7, 7 + dy, 2, B)
    c.rect(5, 6 + dy, 9, 9 + dy, B)
    # 耳尖
    c.set(5, 4 + dy, B)
    c.set(4, 3 + dy, B)
    c.set(9, 4 + dy, B)
    c.set(10, 3 + dy, B)
    # 眼（黄）
    c.set(6, 7 + dy, Y)
    c.set(8, 7 + dy, Y)
    # 獠牙（白）
    c.set(6, 9 + dy, W)
    c.set(8, 9 + dy, W)
    return c


def build_bat():
    cells = []
    for f in range(2):
        cells.append([bat(f)])
    return {
        'id': 'tpl_bat', 'name': '小蝙蝠',
        'w': 16, 'h': 16, 'fps': 6, 'palette': 'pico8',
        'layers': [('蝙蝠', 1)], 'cells': cells,
    }


# ---------- tpl_wizard 小巫师（creatures，24×24，1 帧） ----------

def wizard():
    c = Canvas(24, 24)
    # 袍（暗紫 + 黄扣）
    c.rect(7, 12, 17, 20, B)
    c.rect(8, 21, 16, 22, B)
    c.set(12, 17, Y)
    c.set(12, 19, Y)
    # 白胡子（弧形垂胸）
    c.rect(9, 12, 15, 13, W)
    c.rect(10, 14, 14, 14, W)
    c.rect(11, 15, 13, 15, W)
    c.set(12, 16, W)
    # 脸（肤橙）
    c.rect(9, 8, 15, 11, PE)
    # 眼（黑）
    c.set(11, 9, BLK)
    c.set(14, 9, BLK)
    # 尖帽（暗紫 + 帽檐 + 黄星）
    c.set(12, 0, B)
    c.rect(11, 1, 13, 1, B)
    c.rect(10, 2, 13, 2, B)
    c.rect(9, 3, 14, 3, B)
    c.rect(8, 4, 15, 5, B)
    c.rect(6, 6, 17, 7, B)
    c.set(12, 2, Y)
    c.set(10, 5, Y)
    # 法杖（棕杆 + 黄星顶）
    c.rect(19, 4, 19, 18, BR)
    c.set(18, 3, Y)
    c.set(19, 2, Y)
    c.set(20, 3, Y)
    c.set(19, 4, Y)
    # 持杖手（肤橙）
    c.set(18, 10, PE)
    c.set(19, 10, PE)
    return c


def build_wizard():
    return {
        'id': 'tpl_wizard', 'name': '小巫师',
        'w': 24, 'h': 24, 'fps': 8, 'palette': 'pico8',
        'layers': [('巫师', 1)], 'cells': [[wizard()]],
    }


# ---------- tpl_key 黄铜钥匙（items，16×16，1 帧） ----------

def key():
    c = Canvas(16, 16)
    # 环头（黄圆环：实心圆 + 中空）
    c.circle(5, 5, 3, Y)
    c.circle_erase(5, 5, 2)
    # 杆（黄横杆）
    c.rect(6, 5, 14, 6, Y)
    # 齿（下垂）
    c.rect(12, 7, 13, 7, Y)
    c.set(12, 8, Y)
    c.set(14, 7, Y)
    # 高光（白）
    c.set(7, 5, W)
    return c


def build_key():
    return {
        'id': 'tpl_key', 'name': '黄铜钥匙',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('钥匙', 1)], 'cells': [[key()]],
    }


# ---------- tpl_scroll 魔法卷轴（items，16×16，1 帧） ----------

def scroll():
    c = Canvas(16, 16)
    # 纸卷（米白）
    c.rect(2, 5, 13, 11, W)
    # 上下卷杆（棕 + 深灰端头）
    c.rect(1, 3, 14, 4, BR)
    c.rect(1, 12, 14, 13, BR)
    for y in (3, 4, 12, 13):
        c.set(0, y, DGR)
        c.set(15, y, DGR)
    # 字迹（暗蓝横线）
    c.rect(4, 6, 11, 6, K)
    c.rect(4, 8, 11, 8, K)
    c.rect(4, 10, 9, 10, K)
    # 蜡封（红圆）
    c.circle(11, 10, 1, RD)
    return c


def build_scroll():
    return {
        'id': 'tpl_scroll', 'name': '魔法卷轴',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('卷轴', 1)], 'cells': [[scroll()]],
    }


# ---------- tpl_gem 蓝宝石（glyphs，16×16，1 帧） ----------

def gem():
    c = Canvas(16, 16)
    # 台面（顶平面，亮蓝）
    c.rect(5, 3, 10, 4, BL)
    # 冠部斜面（亮蓝外扩）
    c.rect(3, 5, 12, 6, BL)
    # 腰线（白高光）
    c.rect(3, 6, 12, 6, W)
    # 亭部（亮蓝收尖，逐行变窄）
    widths = [11, 11, 9, 9, 7, 5, 3]
    for i, w in enumerate(widths):
        y = 7 + i
        x0 = 8 - w // 2
        c.rect(x0, y, x0 + w - 1, y, BL)
    # 亭部左暗面（暗蓝两列）
    for i, w in enumerate(widths):
        y = 7 + i
        x0 = 8 - w // 2
        if w > 2:
            c.rect(x0, y, x0 + 1, y, K)
    # 台面高光（白）
    c.set(5, 3, W)
    c.set(6, 3, W)
    c.set(5, 4, W)
    # 闪光点（黄）
    c.set(13, 2, Y)
    c.set(2, 9, Y)
    return c


def build_gem():
    return {
        'id': 'tpl_gem', 'name': '蓝宝石',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('宝石', 1)], 'cells': [[gem()]],
    }


# ---------- tpl_note 音符（glyphs，16×16，1 帧） ----------

def note():
    c = Canvas(16, 16)
    # 符头（亮蓝实心椭圆）
    c.circle(5, 11, 2, BL)
    c.rect(4, 10, 7, 12, BL)
    c.set(4, 13, BL)
    c.set(7, 13, BL)
    # 符干（右上竖线）
    c.rect(8, 2, 8, 12, BL)
    # 符旗（右斜弯）
    c.rect(9, 2, 11, 2, BL)
    c.rect(10, 3, 11, 4, BL)
    c.rect(11, 5, 11, 6, BL)
    # 符头高光（白）
    c.set(5, 10, W)
    return c


def build_note():
    return {
        'id': 'tpl_note', 'name': '音符',
        'w': 16, 'h': 16, 'fps': 8, 'palette': 'pico8',
        'layers': [('音符', 1)], 'cells': [[note()]],
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
              build_heart, build_star,
              # 第二批（1.4.0）：每类 2 个
              build_rabbit, build_penguin,
              build_volcano, build_igloo,
              build_ramen, build_icecream,
              build_ghost, build_mushroom,
              build_sword, build_lantern,
              build_skull, build_moon,
              # 第三批（1.5.0）：每类 2 个
              build_turtle, build_fish,
              build_waterfall, build_terrace,
              build_burger, build_cocoa,
              build_bat, build_wizard,
              build_key, build_scroll,
              build_gem, build_note]
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
    # 第二批（1.4.0）
    'tpl_rabbit': dict(cat='animals', nameEn='Snow Rabbit',
                       descZh='竖着长耳朵的白兔',
                       descEn='A white rabbit with tall ears'),
    'tpl_penguin': dict(cat='animals', nameEn='Little Penguin',
                        descZh='挺着白肚的小企鹅',
                        descEn='A penguin with a white belly'),
    'tpl_volcano': dict(cat='scenery', nameEn='Erupting Volcano',
                        descZh='夜色中喷发的火山',
                        descEn='A volcano blazing in the night'),
    'tpl_igloo': dict(cat='scenery', nameEn='Aurora Igloo',
                      descZh='极光下的小雪屋',
                      descEn='An igloo under the aurora'),
    'tpl_ramen': dict(cat='food', nameEn='Ramen Bowl',
                      descZh='叉烧溏心蛋热汤拉面',
                      descEn='Hot ramen with pork and egg'),
    'tpl_icecream': dict(cat='food', nameEn='Swirl Cone',
                         descZh='粉白漩涡冰淇淋甜筒',
                         descEn='A pink-and-white swirl cone'),
    'tpl_ghost': dict(cat='creatures', nameEn='Little Ghost',
                      descZh='一沉一浮眨眼的小幽灵',
                      descEn='A tiny ghost bobbing along'),
    'tpl_mushroom': dict(cat='creatures', nameEn='Mushroom Folk',
                         descZh='红帽白点的蘑菇小人',
                         descEn='A red-capped mushroom fellow'),
    'tpl_sword': dict(cat='items', nameEn='Treasure Sword',
                      descZh='镶金柄嵌红石的宝剑',
                      descEn='A gold-hilted sword with a ruby'),
    'tpl_lantern': dict(cat='items', nameEn='Paper Lantern',
                        descZh='烛光摇曳的圆纸提灯',
                        descEn='A round lantern with a flickering flame'),
    'tpl_skull': dict(cat='glyphs', nameEn='Pixel Skull',
                      descZh='经典像素骷髅图标',
                      descEn='A classic pixel skull icon'),
    'tpl_moon': dict(cat='glyphs', nameEn='Crescent Moon',
                     descZh='带陨坑的黄弯月与星',
                     descEn='A cratered crescent with stars'),
    # 第三批（1.5.0）
    'tpl_turtle': dict(cat='animals', nameEn='Little Turtle',
                       descZh='沙滩上慢步的小海龟',
                       descEn='A little turtle on the sand'),
    'tpl_fish': dict(cat='animals', nameEn='Tropical Fish',
                     descZh='红条纹的小热带鱼',
                     descEn='A striped tropical fish'),
    'tpl_waterfall': dict(cat='scenery', nameEn='Forest Waterfall',
                          descZh='崖壁间垂落的白瀑',
                          descEn='A white fall between cliffs'),
    'tpl_terrace': dict(cat='scenery', nameEn='Dusk Terraces',
                        descZh='夕照下层叠的梯田',
                        descEn='Terraced fields at dusk'),
    'tpl_burger': dict(cat='food', nameEn='Cheese Burger',
                       descZh='层层分明的芝士汉堡',
                       descEn='A stacked cheeseburger'),
    'tpl_cocoa': dict(cat='food', nameEn='Hot Cocoa',
                      descZh='冒着热气的热可可',
                      descEn='A steaming cup of cocoa'),
    'tpl_bat': dict(cat='creatures', nameEn='Little Bat',
                    descZh='扇动翅膀的小蝙蝠',
                    descEn='A bat flapping its wings'),
    'tpl_wizard': dict(cat='creatures', nameEn='Little Wizard',
                       descZh='尖帽白须的小巫师',
                       descEn='A wizard with a starry hat'),
    'tpl_key': dict(cat='items', nameEn='Brass Key',
                    descZh='黄铜环头旧钥匙',
                    descEn='An old brass key'),
    'tpl_scroll': dict(cat='items', nameEn='Magic Scroll',
                       descZh='红蜡封印的卷轴',
                       descEn='A scroll sealed with red wax'),
    'tpl_gem': dict(cat='glyphs', nameEn='Sapphire Gem',
                    descZh='切面闪亮的蓝宝石',
                    descEn='A faceted blue gem'),
    'tpl_note': dict(cat='glyphs', nameEn='Music Note',
                     descZh='跳动的蓝色音符',
                     descEn='A blue note bouncing along'),
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
    lines.append(f"/** 全部模板（{len(entries)} 个 = {len(NEW_BUILDS)} 新原创 + {len(DEMOS)} 示例工程；分类序 → 注册序）。 */")
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
