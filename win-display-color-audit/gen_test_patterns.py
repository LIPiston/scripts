#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成用于目视校验显示器的测试图（纯标准库写 PNG）。

--gen-patterns <目录>
  01_gray_ramp.png     0-255 连续灰阶 + 11 级阶梯（看是否跳阶/偏色）
  02_near_black.png    0-16 的 8bit 近黑块（看暗部是否被截断 / 黑位抬升）
  03_near_white.png    240-255 近白块（看高光是否被削平）
  04_primaries.png     原色/补色色块 + 25/50/75/100% 灰，用于和其他设备对比
  05_wide_gamut_probe.png  超 sRGB 探针：一串在 sRGB 里"到顶"的颜色，
                            在未做色彩管理的广色域屏上会比在手机上更艳。

这些图都是**未打 ICC 标记**的 sRGB 数值图。判断方法是：拿一台你信任的设备
（手机通常默认把 sRGB 内容收敛到 sRGB）并排比较，而不是只看这一块屏。
"""

import os
import struct
import sys
import zlib


def write_png(path, w, h, rgb_rows):
    """rgb_rows: list of bytes, each row = w*3 bytes, top-down."""
    raw = b''.join(b'\x00' + row for row in rgb_rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)
    return len(png)


def solid(w, h, rgb):
    row = bytes(rgb) * w
    return [row] * h


def hstripes(w, h, blocks):
    """blocks: list of (width_px, (r,g,b)) — 水平条带，竖直排布。"""
    rows = []
    band_h = max(1, h // len(blocks))
    for i, (_, rgb) in enumerate(blocks):
        rows.extend([bytes(rgb) * w] * band_h)
    while len(rows) < h:
        rows.append(bytes(blocks[-1][1]) * w)
    return rows[:h]


def make_gray_ramp(path, w=1024, h=512):
    rows = []
    top = h // 2
    for y in range(top):
        row = bytearray()
        for x in range(w):
            v = int(x * 255 / (w - 1))
            row += bytes((v, v, v))
        rows.append(bytes(row))
    steps = [0, 26, 51, 77, 102, 128, 153, 179, 204, 230, 255]
    for y in range(h - top):
        row = bytearray()
        for x in range(w):
            v = steps[min(len(steps) - 1, x * len(steps) // w)]
            row += bytes((v, v, v))
        rows.append(bytes(row))
    return write_png(path, w, h, rows)


def make_levels(path, lo, hi, cols=8, cell=96):
    vals = list(range(lo, hi + 1))
    rows_n = (len(vals) + cols - 1) // cols
    w = cols * cell
    h = rows_n * cell
    rows = []
    for r in range(rows_n):
        base = bytearray()
        for c in range(cols):
            i = r * cols + c
            v = vals[i] if i < len(vals) else 0
            base += bytes((v, v, v)) * cell
        for _ in range(cell):
            rows.append(bytes(base))
    for i, v in enumerate(vals):
        pass
    return write_png(path, w, h, rows), vals


def make_primaries(path, w=960, h=540):
    # 上排：R G B C M Y   中排：25/50/75/100% 灰   下排：sRGB 到顶的"广色域探针"
    row1 = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 255, 255), (255, 0, 255), (255, 255, 0)]
    row2 = [(64, 64, 64), (128, 128, 128), (192, 192, 192), (255, 255, 255)]
    # 纯 8bit 下 sRGB 里最饱和的几种颜色（未做色彩管理时会显得更艳）
    row3 = [(255, 0, 0), (255, 64, 0), (255, 128, 0), (255, 192, 0), (255, 255, 0), (128, 255, 0)]
    rows = []
    for band in (row1, row2, row3):
        n = len(band)
        base = bytearray()
        for c in range(n):
            base += bytes(band[c]) * (w // n)
        while len(base) < w * 3:
            base += bytes(band[-1])
        for _ in range(h // 3):
            rows.append(bytes(base[:w * 3]))
    while len(rows) < h:
        rows.append(rows[-1])
    return write_png(path, w, h, rows)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    out = sys.argv[2] if len(sys.argv) > 2 else '.'
    os.makedirs(out, exist_ok=True)
    made = []
    made.append(('01_gray_ramp.png', make_gray_ramp(os.path.join(out, '01_gray_ramp.png'))))
    n, vals = make_levels(os.path.join(out, '02_near_black.png'), 0, 16)
    made.append(('02_near_black.png', n))
    n, vals = make_levels(os.path.join(out, '03_near_white.png'), 240, 255)
    made.append(('03_near_white.png', n))
    made.append(('04_primaries.png', make_primaries(os.path.join(out, '04_primaries.png'))))
    made.append(('05_wide_gamut_probe.png', make_primaries(os.path.join(out, '05_wide_gamut_probe.png'))))
    for name, size in made:
        print('  %-30s %7d bytes  -> %s' % (name, size, os.path.abspath(os.path.join(out, name))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
