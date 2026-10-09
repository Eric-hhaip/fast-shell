#!/usr/bin/env python3
"""生成 Fast Shell 应用图标（纯 Python，SDF 抗锯齿，输出 PNG）。

用法：python3 tool/gen_logo.py <输出目录>
输出 1024x1024 主图标，其余尺寸由 sips 缩放生成。
"""
import math
import struct
import sys
import zlib

N = 1024


def clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def mix(c1, c2, t):
    return tuple(round(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def sd_rounded_rect(px, py, cx, cy, hx, hy, r):
    qx = abs(px - cx) - (hx - r)
    qy = abs(py - cy) - (hy - r)
    ox = max(qx, 0.0)
    oy = max(qy, 0.0)
    return math.hypot(ox, oy) + min(max(qx, qy), 0.0) - r


def sd_segment(px, py, ax, ay, bx, by):
    pax = px - ax
    pay = py - ay
    bax = bx - ax
    bay = by - ay
    h = clamp((pax * bax + pay * bay) / (bax * bax + bay * bay), 0.0, 1.0)
    dx = pax - bax * h
    dy = pay - bay * h
    return math.hypot(dx, dy)


def lerp(a, b, t):
    return a + (b - a) * t


def main() -> None:
    out_path = sys.argv[1] if len(sys.argv) > 1 else 'logo_1024.png'

    rows = []
    for y in range(N):
        row = bytearray()
        py = y + 0.5
        for x in range(N):
            px = x + 0.5

            # 背板：macOS 风圆角方形
            d_sq = sd_rounded_rect(px, py, 512, 512, 448, 448, 205)
            a_sq = clamp(0.5 - d_sq, 0.0, 1.0)
            if a_sq <= 0:
                row += b'\x00\x00\x00\x00'
                continue

            # 背景：上深蓝 → 近黑，带一点顶部微光
            t = clamp((py - 64) / 896.0, 0.0, 1.0)
            r = lerp(34, 10, t)
            g = lerp(46, 18, t)
            b = lerp(70, 32, t)
            # 顶部高光带
            glow = max(0.0, 1.0 - abs(py - 200) / 420.0) * 0.10
            r = lerp(r, 70, glow)
            g = lerp(g, 96, glow)
            b = lerp(b, 140, glow)

            # 提示符 ❯（两段圆头粗线）
            d1 = sd_segment(px, py, 322, 366, 496, 512)
            d2 = sd_segment(px, py, 496, 512, 322, 658)
            d_chev = min(d1, d2) - 30.0
            a_chev = clamp(0.5 - d_chev, 0.0, 1.0)
            if a_chev > 0:
                cg = clamp((px - 300) / 260.0, 0.0, 1.0)
                cc = mix((104, 160, 255), (47, 107, 255), cg)
                r = lerp(r, cc[0], a_chev)
                g = lerp(g, cc[1], a_chev)
                b = lerp(b, cc[2], a_chev)

            # 光标条 _
            d_cur = sd_rounded_rect(px, py, 648, 616, 86, 30, 28)
            a_cur = clamp(0.5 - d_cur, 0.0, 1.0)
            if a_cur > 0:
                r = lerp(r, 236, a_cur)
                g = lerp(g, 242, a_cur)
                b = lerp(b, 255, a_cur)

            row += bytes((round(r), round(g), round(b), round(a_sq * 255)))
        rows.append(bytes(row))

    raw = b''.join(b'\x00' + row for row in rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return (
            struct.pack('>I', len(data))
            + body
            + struct.pack('>I', zlib.crc32(body) & 0xFFFFFFFF)
        )

    png = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9))
        + chunk(b'IEND', b'')
    )
    with open(out_path, 'wb') as f:
        f.write(png)
    print(f'written {out_path}')


if __name__ == '__main__':
    main()
