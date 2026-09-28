"""Reproduce our geometric icon as uncompressed 32-bit TGA; no dependencies.

The editable SVG is the design source. This tiny matching raster recipe is an
asset-authoring tool, not an addon/release build. The default keeps the game icon
at 64x64. Use --png-only --size 512 OUTPUT.png for a standalone upload image.
"""
import argparse
from pathlib import Path
import struct
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


def render(size):
    rgba = bytearray()
    # Sample the original 64-unit geometry directly at the requested resolution;
    # this never enlarges or resamples the small in-game bitmap.
    unit = SIZE / size
    for y in range(size):
        for x in range(size):
            samples = [pixel((x + (sx + .5) / SAMPLES) * unit, (y + (sy + .5) / SAMPLES) * unit)
                       for sy in range(SAMPLES) for sx in range(SAMPLES)]
            alpha = sum(p[3] for p in samples)
            # Unassociated alpha avoids a black fringe on translucent edges.
            rgba.extend([round(sum(p[c] * p[3] for p in samples) / alpha) if alpha else 0
                         for c in range(3)] + [round(alpha / len(samples))])
    return rgba


def tga_bytes(rgba):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    bgra = bytearray()
    for y in reversed(range(SIZE)):
        for x in range(SIZE):
            r, g, b, a = rgba[(y * SIZE + x) * 4:(y * SIZE + x + 1) * 4]
            bgra.extend((b, g, r, a))
    return header + bgra


def png_bytes(rgba, size):
    def chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + rgba[y * size * 4:(y + 1) * size * 4] for y in range(size))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!IIBBBBB", size, size, 8, 6, 0, 0, 0))
    return png + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("png", nargs="?", type=Path, help="optional PNG output path")
    parser.add_argument("--png-only", action="store_true", help="export PNG without writing the in-game TGA")
    parser.add_argument("--size", type=int, default=SIZE, help="PNG edge length in pixels (default: 64)")
    args = parser.parse_args()
    if args.size < 1 or args.size > 2048:
        parser.error("size must be between 1 and 2048 pixels")
    if args.png_only and args.png is None:
        parser.error("--png-only requires an output PNG path")
    if args.size != SIZE and not args.png_only:
        parser.error("a custom PNG size requires --png-only; the in-game icon stays 64x64")
    rgba = render(args.size)
    if not args.png_only:
        (ROOT / "src/MarketPilot/Media/Icon.tga").write_bytes(tga_bytes(rgba))
    if args.png:
        args.png.parent.mkdir(parents=True, exist_ok=True)
        args.png.write_bytes(png_bytes(rgba, args.size))
        print(f"Rendered {args.png} ({args.size}x{args.size} RGBA PNG)")


if __name__ == "__main__":
    main()
