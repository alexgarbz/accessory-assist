#!/usr/bin/env python3
"""Generate neutral placeholder product imagery for the sample catalogue.

Every product and bundle in remote-data references an image by file name. Real
photography is dropped into remote-data/images/ using the same file names; this
script exists so the prototype has a complete, self-consistent image set without
committing binary assets that pretend to be product photography.

The output deliberately follows the design system: Light Ash canvas, a single
neutral silhouette, no gradients, no shadows, no text.

Usage:
    python3 scripts/generate_placeholder_images.py
"""

import json
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "remote-data")
IMAGES = os.path.join(DATA, "images")

WIDTH, HEIGHT = 800, 600
SS = 2  # supersampling factor for edge quality

CANVAS = (244, 244, 244)      # Light Ash #F4F4F4
SILHOUETTE = (208, 209, 210)  # Pale Silver #D0D1D2
DETAIL = (142, 142, 142)      # Silver Fog #8E8E8E


def rounded_rect(x, y, w, h, r):
    """Return a coverage predicate for a rounded rectangle."""
    def inside(px, py):
        if px < x or px > x + w or py < y or py > y + h:
            return False
        cx = min(max(px, x + r), x + w - r)
        cy = min(max(py, y + r), y + h - r)
        return (px - cx) ** 2 + (py - cy) ** 2 <= r * r
    return inside


def ring(cx, cy, outer, inner):
    def inside(px, py):
        d2 = (px - cx) ** 2 + (py - cy) ** 2
        return inner * inner <= d2 <= outer * outer
    return inside


def disc(cx, cy, radius):
    def inside(px, py):
        return (px - cx) ** 2 + (py - cy) ** 2 <= radius * radius
    return inside


def arc(cx, cy, radius, thickness, start_deg, end_deg):
    def inside(px, py):
        d = math.hypot(px - cx, py - cy)
        if abs(d - radius) > thickness / 2:
            return False
        angle = math.degrees(math.atan2(py - cy, px - cx)) % 360
        return start_deg <= angle <= end_deg
    return inside


def shapes_for(kind):
    """Return (primary_shapes, detail_shapes) for a category silhouette."""
    cx, cy = WIDTH / 2, HEIGHT / 2
    if kind == "interior":
        return ([rounded_rect(140, 190, 520, 220, 28)],
                [rounded_rect(200, 250, 180, 100, 16), rounded_rect(420, 250, 180, 100, 16)])
    if kind == "cargo":
        return ([rounded_rect(120, 210, 560, 180, 24)],
                [rounded_rect(120, 300, 560, 8, 4)])
    if kind == "charging":
        return ([rounded_rect(320, 130, 160, 250, 20)],
                [arc(400, 380, 130, 26, 0, 180), rounded_rect(370, 175, 60, 60, 12)])
    if kind == "exterior":
        return ([rounded_rect(150, 200, 500, 200, 40)],
                [rounded_rect(150, 340, 500, 60, 24)])
    if kind == "wheels":
        return ([ring(cx, cy, 175, 95)],
                [disc(cx, cy, 55)])
    if kind == "care":
        return ([rounded_rect(280, 210, 240, 230, 26), rounded_rect(360, 150, 80, 70, 14)],
                [rounded_rect(320, 300, 160, 90, 12)])
    if kind == "apparel":
        # Cap: crown plus a forward brim.
        return ([disc(cx, 300, 130)],
                [rounded_rect(cx - 40, 290, 250, 44, 22)])
    if kind == "lifestyle":
        # Tapered cup with a lid band.
        return ([rounded_rect(310, 210, 180, 250, 24)],
                [rounded_rect(300, 200, 200, 44, 16)])
    if kind == "bundle":
        return ([rounded_rect(130, 210, 170, 170, 20),
                 rounded_rect(315, 210, 170, 170, 20),
                 rounded_rect(500, 210, 170, 170, 20)],
                [rounded_rect(130, 400, 540, 10, 5)])
    return ([rounded_rect(200, 200, 400, 200, 24)], [])


def render(kind, path):
    primary, detail = shapes_for(kind)
    rows = []
    inv = 1.0 / (SS * SS)
    for y in range(HEIGHT):
        row = bytearray()
        row.append(0)  # PNG filter type: none
        for x in range(WIDTH):
            p_hits = 0
            d_hits = 0
            for sy in range(SS):
                py = y + (sy + 0.5) / SS
                for sx in range(SS):
                    px = x + (sx + 0.5) / SS
                    if any(s(px, py) for s in detail):
                        d_hits += 1
                    elif any(s(px, py) for s in primary):
                        p_hits += 1
            if p_hits == 0 and d_hits == 0:
                row += bytes(CANVAS)
                continue
            pa = p_hits * inv
            da = d_hits * inv
            ca = 1.0 - pa - da
            row += bytes(
                int(round(CANVAS[i] * ca + SILHOUETTE[i] * pa + DETAIL[i] * da))
                for i in range(3)
            )
        rows.append(bytes(row))

    raw = b"".join(rows)

    def chunk(tag, payload):
        data = tag + payload
        return struct.pack(">I", len(payload)) + data + struct.pack(">I", zlib.crc32(data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as handle:
        handle.write(png)


def main():
    os.makedirs(IMAGES, exist_ok=True)

    with open(os.path.join(DATA, "catalogue.json")) as handle:
        catalogue = json.load(handle)
    with open(os.path.join(DATA, "bundles.json")) as handle:
        bundles = json.load(handle)

    wanted = {}
    for product in catalogue["products"]:
        wanted[product["imageName"]] = product["categoryId"]
    for bundle in bundles["bundles"]:
        wanted[bundle["imageName"]] = "bundle"

    for name, kind in sorted(wanted.items()):
        path = os.path.join(IMAGES, name)
        render(kind, path)
        print("wrote %s (%s)" % (name, kind))

    print("%d placeholder images generated" % len(wanted))


if __name__ == "__main__":
    main()
