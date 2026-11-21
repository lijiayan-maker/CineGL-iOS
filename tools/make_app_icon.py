#!/usr/bin/env python3
"""生成 App 图标（1024x1024 PNG）：和安卓版 ic_launcher_foreground.xml 同一个图形。

安卓自适应图标画布 108dp，系统只露出中间 72dp；iOS 图标是整张方图、由系统切圆角，
所以把中间 72dp 映射到 1024 像素。先按 4 倍尺寸画再缩小，相当于抗锯齿。

用法：python3 tools/make_app_icon.py CineGL/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""
import math
import sys

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # 超采样倍数
SCALE = SIZE * SS / 72.0  # 每 dp 多少像素
OFFSET = 18.0  # 108dp 画布里，可见区域从 18dp 开始

BACKGROUND = (0x0E, 0x0E, 0x10, 255)
STROKE = (0xF2, 0xF2, 0xF2, 255)
GLOW = (0xFF, 0x7A, 0x3D, 255)


def p(x, y):
    return ((x - OFFSET) * SCALE, (y - OFFSET) * SCALE)


def line(draw, a, b, width_dp):
    w = int(round(width_dp * SCALE))
    draw.line([p(*a), p(*b)], fill=STROKE, width=w)
    # 圆头
    r = w / 2.0
    for q in (a, b):
        cx, cy = p(*q)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=STROKE)


def main(out):
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), BACKGROUND)
    draw = ImageDraw.Draw(img)

    # 外圈：圆心 (54, 54)，半径 27，线宽 3
    cx, cy = p(54, 54)
    r = 27 * SCALE
    w = 3 * SCALE
    draw.ellipse([cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2], outline=STROKE, width=int(round(w)))

    # 光圈叶片：六边形开口 + 六条叶片边
    hexagon = [(54, 38), (67.86, 46), (67.86, 62), (54, 70), (40.14, 62), (40.14, 46)]
    for i in range(6):
        line(draw, hexagon[i], hexagon[(i + 1) % 6], 2.4)
    blades = [((54, 38), (60, 28)), ((67.86, 46), (79, 42)), ((67.86, 62), (75, 72)),
              ((54, 70), (48, 80)), ((40.14, 62), (29, 66)), ((40.14, 46), (33, 36))]
    for a, b in blades:
        line(draw, a, b, 2.4)

    # 中心光晕：半径 7
    gx, gy = p(54, 54)
    gr = 7 * SCALE
    draw.ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=GLOW)

    img = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")  # App Store 要求图标不带透明通道
    img.save(out)


if __name__ == "__main__":
    main(sys.argv[1])
