#!/usr/bin/env python3
"""把 UI 测试拍的截图做成 README 用的图（单张缩到 480 宽、对比图拼成网格、界面一览标上序号）。

截图来自 CineGLUITests 的 testScreenshots：每张 <名字>.png 旁边有一个 <名字>.json，
记着关键控件和画面框的位置（点为单位）和屏幕倍率。

用法：
  python3 tools/make_readme_images.py <截图目录> zh  docs/images
  python3 tools/make_readme_images.py <截图目录> en  docs/images/en
  python3 tools/make_readme_images.py <截图目录> zh  docs/images --photo <模拟器相册里的照片>
"""
import argparse
import json
import os
import re

from PIL import Image, ImageDraw, ImageFont

BG = (14, 14, 16)
TEXT = (242, 242, 242)
SUB = (142, 142, 147)
ACCENT = (255, 138, 61)
FONT = '/System/Library/Fonts/Hiragino Sans GB.ttc'

LOOKS = [
    ('natural', '原生', 'Natural'), ('teal_orange', '青橙', 'Teal & Orange'), ('warm_film', '暖阳', 'Warm Film'),
    ('nordic', '冷冽', 'Nordic'), ('matte', '褪色', 'Matte'), ('silver', '银盐', 'Silver'), ('neon', '霓虹', 'Neon Night'),
    ('forest', '森屿', 'Forest'), ('golden_hour', '黄昏', 'Golden Hour'), ('bleach', '漂白', 'Bleach Bypass'),
    ('chrome', '浓彩', 'Rich Chrome'),
]

TEXTS = {
    'zh': {
        'original': ('原片', '影调强度 0'),
        'fx': [('fx-none', '无效果', '全部为 0'), ('fx-halation', '光晕 10', '高光边缘泛红'), ('fx-mist', '柔光 10', '高光向外漫射'),
               ('fx-grain', '颗粒 10', '颗粒大小 3'), ('fx-vignette', '暗角 10', '四周压暗'), ('fx-aberration', '色散 10', '边缘出现彩边')],
        'log': [('log-709', 'Rec.709 直出', 'Log 关闭、不套影调'), ('log-signal', 'CineLog 原片', 'GPU 模拟，显示 Log 原片'),
                ('log-graded', 'CineLog + 青橙', 'Log 素材套用影调后')],
        'aspects': ['16:9', '4:3 全开', '1:1', '2.39:1'],
    },
    'en': {
        'original': ('Original', 'Look strength 0'),
        'fx': [('fx-none', 'No effects', 'All at 0'), ('fx-halation', 'Halation 10', 'Red glow around highlights'),
               ('fx-mist', 'Diffusion 10', 'Highlights bloom outward'), ('fx-grain', 'Grain 10', 'Grain size 3'),
               ('fx-vignette', 'Vignette 10', 'Darker corners'), ('fx-aberration', 'Aberration 10', 'Color fringes at the edges')],
        'log': [('log-709', 'Rec.709', 'Log off, no look'), ('log-signal', 'CineLog signal', 'GPU emulation, log view'),
                ('log-graded', 'CineLog + Teal & Orange', 'Log footage with a look')],
        'aspects': ['16:9', '4:3 Full', '1:1', '2.39:1'],
    },
}

SINGLES = ['look-panel', 'cube-import', 'log-monitor', 'settings', 'settings-assist', 'manual-iso', 'manual-wb', 'reset-before',
           'reset-after', 'assist-zebra', 'assist-peaking', 'assist-waveform', 'recording', 'ui-photo']


def font(size):
    return ImageFont.truetype(FONT, size)


def load(shots, name):
    im = Image.open(os.path.join(shots, name + '.png')).convert('RGB')
    meta = json.load(open(os.path.join(shots, name + '.json')))
    return im, meta


def rect(meta, key):
    s = meta['scale']
    x, y, w, h = meta[key]
    return x * s, y * s, w * s, h * s


def frame_rect(meta):
    """画面在屏幕上的位置（像素）：预览视图的位置 + 它报告的画面框。"""
    px, py, _, _ = rect(meta, 'preview')
    nums = [float(v) for v in re.findall(r'-?[\d.]+', meta['frameRect'])]
    s = meta['scale']
    return px + nums[0] * s, py + nums[1] * s, nums[2] * s, nums[3] * s


def chrome_crop(im, meta):
    """去掉状态栏和底部的横条：上边从顶栏上方 4pt 开始，下边留到底栏下方。"""
    s = meta['scale']
    top = max(0, rect(meta, 'mode.0')[1] - 14 * s)
    sx, sy, sw, sh = rect(meta, 'shutter')
    bottom = min(im.height, sy + sh + (112 - 78) / 2 * s + 6 * s)
    return im.crop((0, int(top), im.width, int(bottom))), top


def single(shots, name, out, width=480):
    im, meta = load(shots, name)
    im, _ = chrome_crop(im, meta)
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(os.path.join(out, name + '.jpg'), quality=88)


def tile_grid(tiles, cols, out_path, tile_w, tile_h, label=True):
    """tiles：[(图, 标题, 小字)]。"""
    pad, gap, title_h = 12, 12, 62 if label else 34
    rows = (len(tiles) + cols - 1) // cols
    W = pad * 2 + cols * tile_w + (cols - 1) * gap
    H = pad * 2 + rows * (tile_h + title_h) + (rows - 1) * gap // 2
    sheet = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(sheet)
    for i, (im, title, sub) in enumerate(tiles):
        c, r = i % cols, i // cols
        x = pad + c * (tile_w + gap)
        y = pad + r * (tile_h + title_h + gap // 2)
        sheet.paste(im.resize((tile_w, tile_h), Image.LANCZOS), (x, y))
        d.text((x + 2, y + tile_h + 6), title, fill=TEXT, font=font(22))
        if sub:
            d.text((x + 2, y + tile_h + 36), sub, fill=SUB, font=font(15))
    sheet.save(out_path, quality=88)


def frame_crop(shots, name, aspect_hw, center_y=0.42):
    """从画面里裁一块（宽 = 画面宽，高 = 宽 × aspect_hw），中心在画面高度的 center_y 处。"""
    im, meta = load(shots, name)
    x, y, w, h = frame_rect(meta)
    ch = min(h, w * aspect_hw)
    cy = y + h * center_y
    top = min(max(y, cy - ch / 2), y + h - ch)
    inset = 2 * meta['scale']   # 避开圆角
    return im.crop((int(x + inset), int(top + inset), int(x + w - inset), int(top + ch - inset)))


def looks_sheet(shots, lang, out):
    t = TEXTS[lang]
    tiles = [(frame_crop(shots, 'look-original', 1.0), t['original'][0], t['original'][1])]
    for look_id, zh, en in LOOKS:
        title, sub = (zh, en) if lang == 'zh' else (en, None)
        tiles.append((frame_crop(shots, 'look-' + look_id, 1.0), title, sub))
    tile_grid(tiles, 4, os.path.join(out, 'looks.jpg'), 300, 300, label=lang == 'zh')


def effects_sheet(shots, lang, out):
    tiles = [(frame_crop(shots, n, 1.4, 0.36), a, b) for n, a, b in TEXTS[lang]['fx']]
    tile_grid(tiles, 3, os.path.join(out, 'effects.jpg'), 300, 420)


def log_sheet(shots, lang, out):
    tiles = [(frame_crop(shots, n, 1.3, 0.38), a, b) for n, a, b in TEXTS[lang]['log']]
    tile_grid(tiles, 3, os.path.join(out, 'log-compare.jpg'), 300, 390)


def aspects_sheet(shots, lang, out):
    tiles = []
    for i, label in enumerate(TEXTS[lang]['aspects']):
        im, meta = load(shots, 'aspect-%d' % i)
        tiles.append((im.crop(tuple(int(v) for v in _xyxy(rect(meta, 'preview')))), label, None))
    w0, h0 = tiles[0][0].size
    tile_grid(tiles, 4, os.path.join(out, 'aspects.jpg'), 240, round(240 * h0 / w0), label=False)


def _xyxy(r):
    x, y, w, h = r
    return x, y, x + w, y + h


def overview(shots, out, width=600):
    """界面一览：在截图上标 1–10 的序号（和 README 表格对应）。"""
    im, meta = load(shots, 'ui-overview')
    im, top = chrome_crop(im, meta)
    k = width / im.width
    im = im.resize((width, round(im.height * k)), Image.LANCZOS)
    d = ImageDraw.Draw(im)

    def pt(x, y):
        return x * k, (y - top) * k

    def r(key):
        x, y, w, h = rect(meta, key)
        return x, y, w, h

    fx, fy, fw, fh = frame_rect(meta)
    mx, my, mw, mh = r('meter')
    tx, ty, tw, th = r('mode.1')
    ox, oy, ow, oh = r('more')
    cx, cy, cw, chh = r('chips')
    t0 = r('tool.focus')
    rs = r('tool.reset')
    g = r('gallery')
    sh = r('shutter')
    lk = r('looks')
    s = meta['scale']
    marks = [
        pt(mx + mw + 14 * s, my + mh / 2),
        pt(tx + tw + 18 * s, ty + th / 2),
        pt(ox + ow / 2, oy + oh + 14 * s),
        pt(cx + cw + 14 * s, cy + chh / 2),
        pt(fx + fw / 2, fy + fh / 2 - 20 * s),
        pt(t0[0] + 6 * s, t0[1] + t0[3] - 8 * s),
        pt(rs[0] + rs[2] - 4 * s, rs[1] + rs[3] - 8 * s),
        pt(g[0] + g[2] + 14 * s, g[1] + g[3] / 2),
        pt(sh[0] + sh[2] + 12 * s, sh[1] + sh[3] / 2),
        pt(lk[0] - 12 * s, lk[1] + lk[3] / 2),
    ]
    rad = 13
    for i, (x, y) in enumerate(marks, 1):
        x = min(max(x, rad + 2), width - rad - 2)
        d.ellipse((x - rad, y - rad, x + rad, y + rad), fill=ACCENT)
        label = str(i)
        f = font(15 if i < 10 else 13)
        bw = d.textlength(label, font=f)
        d.text((x - bw / 2, y - 10), label, fill=(255, 255, 255), font=f)
    im.save(os.path.join(out, 'ui-overview.jpg'), quality=90)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('shots')
    ap.add_argument('lang', choices=['zh', 'en'])
    ap.add_argument('out')
    ap.add_argument('--photo', help='拍出来的照片（模拟器相册里的 JPEG）')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    overview(a.shots, a.out)
    for name in SINGLES:
        single(a.shots, name, a.out)
    looks_sheet(a.shots, a.lang, a.out)
    effects_sheet(a.shots, a.lang, a.out)
    log_sheet(a.shots, a.lang, a.out)
    aspects_sheet(a.shots, a.lang, a.out)
    if a.photo:
        im = Image.open(a.photo).convert('RGB')
        im.thumbnail((520, 520), Image.LANCZOS)
        im.save(os.path.join(a.out, 'photo-sample.jpg'), quality=88)


if __name__ == '__main__':
    main()
