#!/usr/bin/env python3
import math
import os
import struct
import sys
import zlib


ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smooth(edge0, edge1, value):
    t = clamp((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return int(round(a + (b - a) * t))


def blend(dst, src):
    sr, sg, sb, sa = src
    if sa <= 0:
        return dst

    alpha = sa / 255.0
    inv = 1.0 - alpha
    dr, dg, db, da = dst
    out_alpha = alpha + (da / 255.0) * inv
    if out_alpha == 0:
        return (0, 0, 0, 0)

    return (
        int(round((sr * alpha + dr * (da / 255.0) * inv) / out_alpha)),
        int(round((sg * alpha + dg * (da / 255.0) * inv) / out_alpha)),
        int(round((sb * alpha + db * (da / 255.0) * inv) / out_alpha)),
        int(round(out_alpha * 255)),
    )


def rounded_rect_alpha(x, y, left, top, right, bottom, radius, aa):
    px = max(left + radius - x, 0.0, x - (right - radius))
    py = max(top + radius - y, 0.0, y - (bottom - radius))
    outside = math.hypot(px, py) - radius
    return 1.0 - smooth(-aa, aa, outside)


def segment_distance(px, py, ax, ay, bx, by):
    dx = bx - ax
    dy = by - ay
    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        return math.hypot(px - ax, py - ay)

    t = clamp(((px - ax) * dx + (py - ay) * dy) / length_squared)
    cx = ax + t * dx
    cy = ay + t * dy
    return math.hypot(px - cx, py - cy)


def render_icon(size):
    pixels = []
    aa = 1.25 / size

    for row in range(size):
        y = (row + 0.5) / size
        for column in range(size):
            x = (column + 0.5) / size

            bg_alpha = rounded_rect_alpha(x, y, 0.055, 0.055, 0.945, 0.945, 0.205, aa)
            top = (41, 139, 255)
            bottom = (82, 71, 214)
            color = (
                mix(top[0], bottom[0], y),
                mix(top[1], bottom[1], y),
                mix(top[2], bottom[2], y),
                int(round(255 * bg_alpha)),
            )

            highlight = rounded_rect_alpha(x, y, 0.12, 0.10, 0.88, 0.48, 0.16, aa) * (1.0 - smooth(0.22, 0.62, y))
            color = blend(color, (255, 255, 255, int(34 * highlight * bg_alpha)))

            shadow_distance = segment_distance(x, y, 0.55, 0.58, 0.76, 0.79)
            shadow = 1.0 - smooth(0.047, 0.066, shadow_distance)
            color = blend(color, (21, 32, 73, int(70 * shadow * bg_alpha)))

            lens_center_x = 0.405
            lens_center_y = 0.395
            lens_radius = 0.205
            ring_width = 0.063
            lens_distance = math.hypot(x - lens_center_x, y - lens_center_y)
            ring = 1.0 - smooth(ring_width * 0.5, ring_width * 0.5 + aa, abs(lens_distance - lens_radius))
            fill = (1.0 - smooth(lens_radius - ring_width, lens_radius - ring_width + aa, lens_distance)) * 0.12

            color = blend(color, (255, 255, 255, int(255 * fill * bg_alpha)))
            color = blend(color, (255, 255, 255, int(245 * ring * bg_alpha)))

            handle_distance = segment_distance(x, y, 0.55, 0.56, 0.76, 0.77)
            handle = 1.0 - smooth(0.041, 0.041 + aa, handle_distance)
            color = blend(color, (255, 255, 255, int(250 * handle * bg_alpha)))

            sparkle = max(0.0, 1.0 - abs(x - 0.69) / 0.055) * max(0.0, 1.0 - abs(y - 0.24) / 0.055)
            color = blend(color, (255, 255, 255, int(120 * sparkle * bg_alpha)))

            pixels.append(color)

    return pixels


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_png(path, width, height, pixels):
    raw_rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(pixels[y * width + x])
        raw_rows.append(bytes(row))

    with open(path, "wb") as output:
        output.write(b"\x89PNG\r\n\x1a\n")
        output.write(png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        output.write(png_chunk(b"IDAT", zlib.compress(b"".join(raw_rows), 9)))
        output.write(png_chunk(b"IEND", b""))


def main():
    if len(sys.argv) != 2:
        print("usage: generate-icon.py OUTPUT_ICONSET_DIR", file=sys.stderr)
        return 2

    output_dir = sys.argv[1]
    os.makedirs(output_dir, exist_ok=True)

    for filename, size in ICON_SIZES.items():
        write_png(os.path.join(output_dir, filename), size, size, render_icon(size))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
