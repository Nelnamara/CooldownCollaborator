#!/usr/bin/env python3
"""Draws Media/speaker-off.tga (a speaker) and Media/speaker-on.tga (the speaker with two sound waves).

32x32, white on transparent, uncompressed 32-bit TGA (the game wants .tga for addon art: a .png shows as
a checkerboard on Midnight). The addon tints them with SetVertexColor: grey for no alert, gold for one.
    python3 tools/make-speaker.py
"""
import math
import os
import struct

SIZE = 32
SS = 4  # samples per pixel side, for smooth edges


def in_polygon(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


# the speaker: a small box, then a cone opening to the right
BOX = [(4, 12), (10, 12), (10, 20), (4, 20)]
CONE = [(10, 12), (17, 6), (17, 26), (10, 20)]
WAVE_CENTER = (16.0, 16.0)
WAVES = [(7.5, 10.5), (11.5, 14.5)]  # (inner radius, outer radius) of each arc
WAVE_HALF_ANGLE = math.radians(48)


def covered(x, y, waves):
    if in_polygon(x, y, BOX) or in_polygon(x, y, CONE):
        return True
    if waves:
        dx, dy = x - WAVE_CENTER[0], y - WAVE_CENTER[1]
        r = math.hypot(dx, dy)
        if dx > 0 and abs(math.atan2(dy, dx)) <= WAVE_HALF_ANGLE:
            for lo, hi in WAVES:
                if lo <= r <= hi:
                    return True
    return False


def render(waves):
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    if covered(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS, waves):
                        hits += 1
            alpha = round(255 * hits / (SS * SS))
            row += bytes((255, 255, 255, alpha))  # B, G, R, A
        rows.append(bytes(row))
    return rows


def write_tga(path, rows):
    # id length 0, no colour map, type 2 (uncompressed true colour), 32 bits, top-left origin, 8 alpha bits
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header)
        for row in rows:
            f.write(row)


if __name__ == "__main__":
    media = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")
    write_tga(os.path.join(media, "speaker-off.tga"), render(False))
    write_tga(os.path.join(media, "speaker-on.tga"), render(True))
    print("wrote Media/speaker-off.tga and Media/speaker-on.tga")
