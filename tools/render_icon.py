"""Reproduce our geometric icon as uncompressed 32-bit TGA; no dependencies.

The editable SVG is the design source. This tiny matching raster recipe is an
asset-authoring tool, not an addon/release build. Optional PNG output is for QA.
"""
from pathlib import Path
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
SIZE, SAMPLES = 64, 4


def on_segment(x, y, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)))
    return (x - a[0] - t * dx) ** 2 + (y - a[1] - t * dy) ** 2 <= 1.5 ** 2


def pixel(x, y):
    radius = ((x - 32) ** 2 + (y - 32) ** 2) ** 0.5
    color = (16, 28, 39, 255) if radius <= 30 else (0, 0, 0, 0)
    if 26 <= radius <= 28:
        color = (217, 180, 92, 255)
    if any(left <= x <= left + 6 and top <= y <= 51 for left, top in ((17, 44), (29, 36), (41, 28))):
        color = (68, 126, 128, 255)
    segments = (((17, 34), (28, 23)), ((28, 23), (36, 28)), ((36, 28), (47, 15)),
                ((39, 15), (47, 15)), ((47, 15), (47, 23)))
    if any(on_segment(x, y, a, b) for a, b in segments):
        color = (244, 217, 140, 255)
    return color


def main():
    rgba = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            samples = [pixel(x + (sx + .5) / SAMPLES, y + (sy + .5) / SAMPLES)
                       for sy in range(SAMPLES) for sx in range(SAMPLES)]
            alpha = sum(p[3] for p in samples)
            # Unassociated alpha avoids a black fringe on translucent edges.
            rgba.extend([round(sum(p[c] * p[3] for p in samples) / alpha) if alpha else 0
                         for c in range(3)] + [round(alpha / len(samples))])
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    bgra = bytearray()
    for y in reversed(range(SIZE)):
        for x in range(SIZE):
            r, g, b, a = rgba[(y * SIZE + x) * 4:(y * SIZE + x + 1) * 4]
            bgra.extend((b, g, r, a))
    (ROOT / "src/MarketPilot/Media/Icon.tga").write_bytes(header + bgra)
    if len(sys.argv) == 2:
        def chunk(kind, data):
            return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
        rows = b"".join(b"\0" + rgba[y * SIZE * 4:(y + 1) * SIZE * 4] for y in range(SIZE))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
        Path(sys.argv[1]).write_bytes(png + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    main()
