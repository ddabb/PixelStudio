# -*- coding: utf-8 -*-
"""verify_store_demo.py — 回读 .pxs/.thumb 校验协议 + PIL 渲染 PNG 预览。"""
import os
import struct
import sys
import zlib
from PIL import Image


def read_pxs(path):
    data = open(path, 'rb').read()
    raw_len = struct.unpack('<Q', data[:8])[0]
    raw = zlib.decompress(data[8:])
    assert len(raw) == raw_len, f"rawLen mismatch {len(raw)} != {raw_len}"
    assert raw[:4] == b'PXSP', 'magic'
    ver, meta_len = struct.unpack('<HQ', raw[4:14])
    assert ver == 1
    pos = 14
    meta = raw[pos:pos + meta_len]
    m = 0

    def take_str(buf, p):
        n = struct.unpack('<H', buf[p:p + 2])[0]
        return buf[p + 2:p + 2 + n].decode('utf-8'), p + 2 + n

    name, m = take_str(meta, m)
    w, h, fps, frames, layers = struct.unpack('<HHHHH', meta[m:m + 10])
    m += 10
    palette, m = take_str(meta, m)
    layer_meta = []
    for _ in range(layers):
        lid, vis, op = struct.unpack('<HBB', meta[m:m + 4])
        m += 4
        lname, m = take_str(meta, m)
        layer_meta.append((lname, lid, vis, op))
    assert m == len(meta), f"meta not fully consumed: {m} != {len(meta)}"
    px = raw[pos + meta_len:]
    assert len(px) == frames * layers * w * h * 4, \
        f"pixel bytes {len(px)} != {frames * layers * w * h * 4}"
    cells = []
    off = 0
    for f in range(frames):
        row = []
        for l in range(layers):
            img = Image.new('RGBA', (w, h))
            img.putdata([(px[off + i * 4], px[off + i * 4 + 1],
                          px[off + i * 4 + 2], px[off + i * 4 + 3])
                         for i in range(w * h)])
            off += w * h * 4
            row.append(img)
        cells.append(row)
    return {'name': name, 'w': w, 'h': h, 'fps': fps, 'frames': frames,
            'layers': layers, 'palette': palette, 'layer_meta': layer_meta, 'cells': cells}


def read_thumb(path):
    data = open(path, 'rb').read()
    tw, th = struct.unpack('<HH', data[:4])
    assert len(data) == 4 + tw * th * 4, f"thumb size {len(data)} != {4 + tw * th * 4}"
    img = Image.new('RGBA', (tw, th))
    img.putdata([(data[4 + i * 4], data[4 + i * 4 + 1],
                  data[4 + i * 4 + 2], data[4 + i * 4 + 3]) for i in range(tw * th)])
    return img


def main():
    src = sys.argv[1]
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for pid in ['demo_cat', 'demo_sunset', 'demo_slime']:
        p = read_pxs(os.path.join(src, f'{pid}.pxs'))
        info = (f"{pid}: {p['name']!r} {p['w']}x{p['h']} fps={p['fps']} "
                f"frames={p['frames']} layers={p['layers']} palette={p['palette']}")
        print(info)
        print('  layers:', p['layer_meta'])
        # 全帧 × 全层平铺图（最近邻放大 8 倍）
        scale = max(4, 128 // max(p['w'], p['h']))
        tiles = []
        for f in range(p['frames']):
            for l in range(p['layers']):
                tiles.append(p['cells'][f][l])
        sheet = Image.new('RGBA', (len(tiles) * (p['w'] * scale + 4) + 4,
                                   p['h'] * scale + 8), (40, 44, 52, 255))
        for i, t in enumerate(tiles):
            big = t.resize((p['w'] * scale, p['h'] * scale), Image.NEAREST)
            sheet.paste(big, (4 + i * (p['w'] * scale + 4), 4), big)
        sheet.save(os.path.join(out, f'{pid}_sheet.png'))
        # 帧合成预览（首帧）
        comp = Image.new('RGBA', (p['w'], p['h']))
        for l in range(p['layers']):
            comp = Image.alpha_composite(comp, p['cells'][0][l])
        comp.resize((p['w'] * 8, p['h'] * 8), Image.NEAREST).save(
            os.path.join(out, f'{pid}_f0.png'))
        # thumb 边车
        th = read_thumb(os.path.join(src, f'{pid}.thumb'))
        print(f"  thumb: {th.size[0]}x{th.size[1]}")
        th.resize((th.size[0] * 6, th.size[1] * 6), Image.NEAREST).save(
            os.path.join(out, f'{pid}_thumb.png'))
    print('previews ->', os.path.abspath(out))


if __name__ == '__main__':
    main()
