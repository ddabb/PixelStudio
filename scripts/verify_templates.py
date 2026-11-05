# -*- coding: utf-8 -*-
"""verify_templates.py — 校验模板库三类产物的一致性并输出 PIL 预览。

校验项：
1. templates_manifest.json：categories 六类有序、27 条目（两批 24 原创 + 3 示例）、id 唯一；
2. rawfile 文件 ↔ manifest ↔ .pxs 元数据（name/w/h/fps/frames）逐条一致；
3. TemplateDefs.ets：id 序列与 manifest 完全一致（防手改漂移）；
4. .cache/tpl_preview/<id>.png：每模板全帧最近邻放大合成预览（目检画风用）。

用法：py -3 scripts/verify_templates.py
"""
import json
import os
import re
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_store_demo import read_pxs, read_thumb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAWFILE = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile')
MANIFEST = os.path.join(ROOT, 'scripts', 'templates_manifest.json')
DEFS_ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets',
                        'viewmodel', 'TemplateDefs.ets')
PREVIEW_DIR = os.path.join(ROOT, '.cache', 'tpl_preview')

EXPECTED_CATS = ['animals', 'scenery', 'food', 'creatures', 'items', 'glyphs']
EXPECTED_COUNT = 27


def compose_frame(p, f):
    """按层序 alpha 合成第 f 帧为单张 RGBA。"""
    comp = Image.new('RGBA', (p['w'], p['h']))
    for layer in range(p['layers']):
        comp = Image.alpha_composite(comp, p['cells'][f][layer])
    return comp


def main():
    manifest = json.load(open(MANIFEST, encoding='utf-8'))
    assert manifest['categories'] == EXPECTED_CATS, \
        f"categories 漂移: {manifest['categories']}"
    entries = manifest['entries']
    assert len(entries) == EXPECTED_COUNT, \
        f"条目数 {len(entries)} != {EXPECTED_COUNT}"
    ids = [e['id'] for e in entries]
    assert len(set(ids)) == len(ids), 'id 重复'

    # TemplateDefs.ets id 序列防漂移
    ets = open(DEFS_ETS, encoding='utf-8').read()
    ets_ids = re.findall(r"id: '([^']+)'", ets)
    assert ets_ids == ids, f"TemplateDefs.ets id 漂移: {ets_ids} != {ids}"

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for e in entries:
        pxs_path = os.path.join(RAWFILE, e['file'])
        assert os.path.isfile(pxs_path), f"缺少 {e['file']}"
        p = read_pxs(pxs_path)
        assert p['name'] == e['nameZh'], \
            f"{e['id']}: pxs name {p['name']!r} != {e['nameZh']!r}"
        for key in ('w', 'h', 'frames', 'fps'):
            assert p[key] == e[key], \
                f"{e['id']}: {key} {p[key]} != {e[key]}"
        thumb_path = pxs_path[:-4] + '.thumb'
        assert os.path.isfile(thumb_path), f"缺少 thumb: {e['id']}"
        th = read_thumb(thumb_path)
        assert th.size[0] == e['w'] and th.size[1] == e['h'], \
            f"{e['id']}: thumb 尺寸 {th.size} != ({e['w']}, {e['h']})"

        # 预览：全部帧横向平铺，最近邻放大 6 倍
        scale = 6
        frames = [compose_frame(p, f) for f in range(p['frames'])]
        sheet = Image.new('RGBA', (
            len(frames) * (p['w'] * scale + 4) + 4, p['h'] * scale + 8),
            (40, 44, 52, 255))
        for i, fr in enumerate(frames):
            big = fr.resize((p['w'] * scale, p['h'] * scale), Image.NEAREST)
            sheet.paste(big, (4 + i * (p['w'] * scale + 4), 4), big)
        sheet.save(os.path.join(PREVIEW_DIR, f"{e['id']}.png"))
        print(f"ok {e['id']}: {e['nameZh']} {e['w']}x{e['h']} "
              f"frames={e['frames']} fps={e['fps']}")
    print(f"verify: {len(entries)} 模板全部一致；预览 -> "
          f"{os.path.abspath(PREVIEW_DIR)}")


if __name__ == '__main__':
    main()
