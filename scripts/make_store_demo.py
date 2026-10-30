# -*- coding: utf-8 -*-
"""
make_store_demo.py — 应用市场截图种子工程生成器（AGC 三端截图任务）。

离线生成 3 个 .pxs 演示工程 + {id}.thumb 缩略图边车（复刻 ProjectStore/PxsFile
序列化协议：[8B 未压缩长度 LE][zlib(raw)]；raw = 'PXSP' + ver + metaLen + meta + 像素流），
推入应用沙箱后用于商店截图的列表/编辑/导出各页展示。

工程清单（列表按 mtime 倒序展示）：
  p1 星夜小猫   32×32  fps8  3帧2层（夜空/小猫，pico8）——眨眼动画
  p3 落日海岸   48×48  fps8  1帧2层（天空/剪影，pico8）——日落剪影
  p2 果冻史莱姆 16×16  fps6  2帧1层（gbdmg）——压扁弹跳

用法：py -3 scripts/make_store_demo.py <输出目录>
"""
import os
import struct
import sys
import zlib

# ---------- PICO-8 ----------
K = (29, 43, 83)      # 暗蓝
B = (126, 37, 83)     # 暗紫
BLK = (0, 0, 0)       # 黑
W = (255, 241, 232)   # 米白
Y = (255, 236, 39)    # 黄
O = (255, 163, 0)     # 橙
BR = (171, 82, 54)    # 棕
PE = (255, 204, 170)  # 肤橙
RD = (255, 0, 77)     # 红
GN = (0, 228, 54)     # 绿
BL = (41, 173, 255)   # 亮蓝
PK = (255, 119, 168)  # 粉
# ---------- GB-DMG ----------
G0 = (15, 56, 15)
G1 = (48, 98, 48)
G2 = (139, 172, 15)
G3 = (155, 188, 15)


class Canvas:
    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.px = [[None] * w for _ in range(h)]  # None = 透明

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def circle(self, cx, cy, r, c, ymax=None):
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    if ymax is None or y <= ymax:
                        self.set(x, y, c)

    def circle_erase(self, cx, cy, r):
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    if 0 <= x < self.w and 0 <= y < self.h:
                        self.px[y][x] = None

    def line(self, x0, y0, x1, y1, c):
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        x, y = x0, y0
        while True:
            self.set(x, y, c)
            if x == x1 and y == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x += sx
            if e2 < dx:
                err += dx
                y += sy

    def lerp_band(self, stops):
        """stops: [(t0..1, color), ...] 垂直渐变整幅。"""
        for y in range(self.h):
            t = y / max(1, self.h - 1)
            for i in range(len(stops) - 1):
                t0, c0 = stops[i]
                t1, c1 = stops[i + 1]
                if t0 <= t <= t1 or i == len(stops) - 2:
                    f = 0.0 if t1 == t0 else min(1.0, max(0.0, (t - t0) / (t1 - t0)))
                    c = tuple(round(c0[j] + (c1[j] - c0[j]) * f) for j in range(3))
                    for x in range(self.w):
                        self.set(x, y, c)
                    break

    def rgba(self):
        out = bytearray(self.w * self.h * 4)
        i = 0
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y][x]
                if c is None:
                    i += 4
                else:
                    out[i] = c[0]
                    out[i + 1] = c[1]
                    out[i + 2] = c[2]
                    out[i + 3] = 255
                    i += 4
        return bytes(out)

    def argb_at(self, x, y):
        c = self.px[y][x]
        return None if c is None else (255, c[0], c[1], c[2])


# ---------- P1 星夜小猫 ----------

def cat_night_sky(frame):
    c = Canvas(32, 32)
    c.lerp_band([(0.0, K), (1.0, B)])
    grad = [row[:] for row in c.px]
    # 月牙（右上，避开猫耳；内圆回填渐变色而非透明）
    c.circle(27, 5, 3, Y)
    for y in range(32):
        for x in range(32):
            if (x - 25) ** 2 + (y - 4) ** 2 <= 4:
                c.px[y][x] = grad[y][x]
    c.set(29, 4, W)
    # 星星（避开猫头 x7..24 y6..27、月区 x24..30 y2..8）
    for sx, sy in [(3, 3), (14, 4), (2, 10), (28, 15), (6, 19), (29, 24), (4, 27), (26, 29)]:
        c.set(sx, sy, W)
    # 闪烁十字星（帧间变色）
    tw = Y if frame == 1 else W
    for tx, ty in [(6, 6), (5, 7), (7, 7), (6, 8)]:
        c.set(tx, ty, tw)
    if frame == 2:
        c.set(26, 11, W)
    return c


def cat_face(frame):
    """frame 0/2 睁眼，1 闭眼吐舌。"""
    c = Canvas(32, 32)
    closed = frame == 1
    # 耳朵（左 + 镜像右）
    c.line(10, 6, 8, 9, O)
    c.line(10, 6, 12, 9, O)
    for x in range(8, 13):
        c.set(x, 9, O)
    c.set(10, 7, PE)
    for x in range(9, 12):
        c.set(x, 8, PE)
    c.line(21, 6, 19, 9, O)
    c.line(21, 6, 23, 9, O)
    for x in range(19, 24):
        c.set(x, 9, O)
    c.set(21, 7, PE)
    for x in range(20, 23):
        c.set(x, 8, PE)
    # 头
    c.rect(8, 10, 23, 10, O)
    c.rect(7, 11, 24, 25, O)
    c.rect(8, 26, 23, 26, O)
    c.rect(9, 27, 22, 27, O)
    # 额纹（tabby M）
    c.rect(11, 11, 12, 13, BR)
    c.rect(19, 11, 20, 13, BR)
    c.rect(15, 11, 16, 12, BR)
    c.set(11, 14, BR)
    c.set(20, 14, BR)
    # 眼睛
    if closed:
        c.rect(11, 17, 13, 17, BLK)
        c.rect(18, 17, 20, 17, BLK)
    else:
        c.rect(11, 16, 13, 18, GN)
        c.rect(18, 16, 20, 18, GN)
        c.set(12, 17, BLK)
        c.set(19, 17, BLK)
        c.set(12, 16, W)
        c.set(19, 16, W)
    # 腮红
    for bx, by in [(9, 20), (10, 21), (22, 20), (21, 21)]:
        c.set(bx, by, PK)
    # 口鼻区
    c.rect(12, 20, 19, 20, PE)
    c.rect(11, 21, 20, 23, PE)
    c.rect(12, 24, 19, 24, PE)
    # 鼻子
    c.rect(15, 20, 16, 21, RD)
    # 嘴
    if closed:
        c.rect(14, 22, 17, 23, BLK)
        c.rect(15, 23, 16, 23, RD)
    else:
        c.set(15, 22, BLK)
        c.set(16, 22, BLK)
        c.set(14, 23, BLK)
        c.set(17, 23, BLK)
    # 胡须
    for wx, wy in [(5, 17), (4, 17), (5, 20), (4, 20), (26, 17), (27, 17), (26, 20), (27, 20)]:
        c.set(wx, wy, W)
    return c


def build_cat():
    layers = [('夜空', 1), ('小猫', 2)]
    cells = []  # cells[f][l]
    for f in range(3):
        row = [cat_night_sky(f), cat_face(f if f < 2 else 0)]
        cells.append(row)
    return {
        'id': 'demo_cat',
        'name': '星夜小猫',
        'w': 32, 'h': 32, 'fps': 8,
        'palette': 'pico8',
        'layers': layers,
        'cells': cells,
        'mtime': 3,
    }


# ---------- P2 果冻史莱姆 ----------

def slime(frame):
    c = Canvas(16, 16)
    if frame == 0:
        c.rect(6, 5, 9, 5, G2)
        c.rect(5, 6, 10, 6, G2)
        c.rect(4, 7, 11, 11, G2)
        c.rect(5, 12, 10, 12, G2)
        c.rect(6, 13, 9, 13, G2)
        # 轮廓
        for x in range(6, 10):
            c.set(x, 4, G1)
        c.set(5, 5, G1)
        c.set(10, 5, G1)
        c.set(4, 6, G1)
        c.set(11, 6, G1)
        for y in range(7, 12):
            c.set(3, y, G1)
            c.set(12, y, G1)
        c.set(4, 12, G1)
        c.set(11, 12, G1)
        c.set(5, 13, G1)
        c.set(10, 13, G1)
        for x in range(6, 10):
            c.set(x, 14, G1)
        # 高光
        c.rect(6, 6, 8, 6, G3)
        c.set(5, 7, G3)
        # 眼睛
        c.rect(6, 8, 6, 9, G0)
        c.rect(9, 8, 9, 9, G0)
        # 嘴
        c.set(7, 11, G0)
        c.set(8, 11, G0)
    else:
        # 压扁帧
        c.rect(5, 7, 10, 7, G2)
        c.rect(3, 8, 12, 8, G2)
        c.rect(2, 9, 13, 11, G2)
        c.rect(3, 12, 12, 12, G2)
        c.rect(4, 13, 11, 13, G2)
        # 轮廓
        for x in range(5, 11):
            c.set(x, 6, G1)
        c.set(4, 7, G1)
        c.set(11, 7, G1)
        c.set(2, 8, G1)
        c.set(13, 8, G1)
        c.set(1, 9, G1)
        c.set(14, 9, G1)
        for y in range(10, 12):
            c.set(1, y, G1)
            c.set(14, y, G1)
        c.set(2, 12, G1)
        c.set(13, 12, G1)
        for x in range(4, 12):
            c.set(x, 14, G1)
        # 高光
        c.rect(3, 8, 6, 8, G3)
        # 眯眼
        c.rect(5, 9, 6, 9, G0)
        c.rect(9, 9, 10, 9, G0)
        # 嘴
        c.set(7, 11, G0)
        c.set(8, 11, G0)
    return c


def build_slime():
    cells = []
    for f in range(2):
        cells.append([slime(f)])
    return {
        'id': 'demo_slime',
        'name': '果冻史莱姆',
        'w': 16, 'h': 16, 'fps': 6,
        'palette': 'gbdmg',
        'layers': [('史莱姆', 1)],
        'cells': cells,
        'mtime': 1,
    }


# ---------- P3 落日海岸 ----------

def sunset_sky():
    c = Canvas(48, 48)
    c.lerp_band([(0.0, Y), (0.28, O), (0.55, RD), (1.0, B)])
    # 落日（半沉入海平线 y=30）
    c.circle(24, 27, 7, Y, ymax=29)
    c.circle(24, 27, 7, W, ymax=29)
    c.circle(24, 28, 6, Y, ymax=29)
    # 海平线亮边
    for x in range(0, 48):
        c.set(x, 29, Y)
    return c


def sunset_silhouette():
    c = Canvas(48, 48)
    # 海面
    c.rect(0, 30, 47, 47, K)
    # 太阳倒影
    for y, x0, x1 in [(30, 22, 26), (32, 23, 25), (34, 23, 25), (36, 24, 24),
                      (38, 22, 26), (40, 23, 25), (43, 24, 24)]:
        for x in range(x0, x1 + 1):
            c.set(x, y, Y)
    # 右侧海岛
    c.rect(39, 27, 43, 27, K)
    c.rect(37, 28, 45, 28, K)
    c.rect(36, 29, 46, 29, K)
    # 棕榈树（主干 + 冠叶）
    c.rect(41, 17, 41, 26, K)
    c.set(40, 25, K)
    for dx, dy in [(-1, -1), (-2, -1), (-3, 0), (-4, 1), (1, -1), (2, -1), (3, 0), (4, 1),
                   (-3, -2), (3, -2), (0, -2), (-1, -3), (1, -3)]:
        c.set(41 + dx, 16 + dy, K)
    # 海鸟
    for bx, by in [(10, 11), (16, 8)]:
        c.set(bx - 1, by + 1, K)
        c.set(bx, by, K)
        c.set(bx + 1, by + 1, K)
    # 前景海浪高光
    for x, y in [(5, 36), (6, 36), (12, 39), (13, 39), (20, 35), (21, 35), (30, 41), (31, 41),
                 (38, 37), (39, 37), (9, 44), (10, 44), (26, 45), (27, 45)]:
        c.set(x, y, B)
    return c


def build_sunset():
    cells = [[sunset_sky(), sunset_silhouette()]]
    return {
        'id': 'demo_sunset',
        'name': '落日海岸',
        'w': 48, 'h': 48, 'fps': 8,
        'palette': 'pico8',
        'layers': [('天空', 1), ('剪影', 2)],
        'cells': cells,
        'mtime': 2,
    }


# ---------- 序列化（复刻 PxsFile.serialize + ProjectStore.saveDoc 封包） ----------

def push_string(b, s):
    raw = s.encode('utf-8')
    return b + struct.pack('<H', len(raw)) + raw


def serialize_pxs(p):
    meta = b''
    meta = push_string(meta, p['name'])
    meta += struct.pack('<HHHHH', p['w'], p['h'], p['fps'], len(p['cells']), len(p['layers']))
    meta = push_string(meta, p['palette'])
    for lname, lid in p['layers']:
        meta += struct.pack('<HBB', lid, 1, 100)  # id, visible, opacity
        meta = push_string(meta, lname)
    raw = b'PXSP' + struct.pack('<HQ', 1, len(meta)) + meta
    for frame in p['cells']:
        for layer in frame:
            raw += layer.rgba()
    wrapped = struct.pack('<Q', len(raw)) + zlib.compress(raw, 9)
    return wrapped


def compose_first_frame(p):
    """帧 0 source-over 合成（自底向上；不透明度均 100）。"""
    w, h = p['w'], p['h']
    out = [[None] * w for _ in range(h)]
    for layer in p['cells'][0]:
        for y in range(h):
            for x in range(w):
                c = layer.argb_at(x, y)
                if c is not None:
                    out[y][x] = (c[1], c[2], c[3])
    return out


def make_thumb(p, max_side=64):
    grid = compose_first_frame(p)
    w, h = p['w'], p['h']
    scale = max(1, -(-max(max(w, h) // max_side, 1)))  # ceil
    tw = max(1, (w + scale - 1) // scale)
    th = max(1, (h + scale - 1) // scale)
    out = bytearray()
    out += struct.pack('<HH', tw, th)
    for y in range(th):
        sy = min(h - 1, y * scale)
        for x in range(tw):
            sx = min(w - 1, x * scale)
            c = grid[sy][sx]
            if c is None:
                out += b'\x00\x00\x00\x00'
            else:
                out += bytes((c[0], c[1], c[2], 255))
    return bytes(out)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'store_demo'
    os.makedirs(out_dir, exist_ok=True)
    projects = [build_cat(), build_sunset(), build_slime()]
    for p in projects:
        pxs = serialize_pxs(p)
        with open(os.path.join(out_dir, f"{p['id']}.pxs"), 'wb') as f:
            f.write(pxs)
        with open(os.path.join(out_dir, f"{p['id']}.thumb"), 'wb') as f:
            f.write(make_thumb(p))
        print(f"{p['id']}: {p['name']} {p['w']}x{p['h']} "
              f"frames={len(p['cells'])} layers={len(p['layers'])} "
              f"pxs={len(pxs)}B thumb={len(make_thumb(p))}B")
    print(f"output: {os.path.abspath(out_dir)}")


if __name__ == '__main__':
    main()
