#!/usr/bin/env python3
"""
Crop a source image tightly around visible content and export square logo assets.

Usage:
  python scripts/make_logo.py input.png --out ui/public --size 512 --pad 32 --bg "#0b1324"

Notes:
- Automatically trims uniform background (near the top-left pixel color) with tolerance.
- Adds padding and exports square canvases (centers content).
- Writes: logo.png, logo-256.png, logo-128.png, favicon.ico (16/32/48).
"""

import argparse
from pathlib import Path
from typing import Tuple

from PIL import Image


def parse_color(c: str) -> Tuple[int, int, int, int]:
    c = c.strip()
    if c.startswith('#'):
        c = c[1:]
        if len(c) == 6:
            r = int(c[0:2], 16); g = int(c[2:4], 16); b = int(c[4:6], 16)
            return (r, g, b, 255)
        if len(c) == 8:
            r = int(c[0:2], 16); g = int(c[2:4], 16); b = int(c[4:6], 16); a = int(c[6:8], 16)
            return (r, g, b, a)
    raise ValueError("Unsupported color format; use #RRGGBB or #RRGGBBAA")


def color_close(a, b, tol=6):
    return all(abs(int(a[i]) - int(b[i])) <= tol for i in range(3))


def _avg_color(block: Image.Image) -> Tuple[int, int, int, int]:
    if block.mode != 'RGBA':
        block = block.convert('RGBA')
    px = list(block.getdata())
    n = max(1, len(px))
    r = sum(p[0] for p in px) // n
    g = sum(p[1] for p in px) // n
    b = sum(p[2] for p in px) // n
    a = sum(p[3] for p in px) // n
    return (r, g, b, a)


def _edge_bg_color(img: Image.Image) -> Tuple[int, int, int, int]:
    w, h = img.size
    s = max(2, min(w, h) // 40)  # small sample blocks (~2.5% of edge)
    tl = _avg_color(img.crop((0, 0, s, s)))
    tr = _avg_color(img.crop((w - s, 0, w, s)))
    bl = _avg_color(img.crop((0, h - s, s, h)))
    br = _avg_color(img.crop((w - s, h - s, w, h)))
    # average the four corners
    return (
        (tl[0] + tr[0] + bl[0] + br[0]) // 4,
        (tl[1] + tr[1] + bl[1] + br[1]) // 4,
        (tl[2] + tr[2] + bl[2] + br[2]) // 4,
        (tl[3] + tr[3] + bl[3] + br[3]) // 4,
    )


def trim_uniform_bg(img: Image.Image, tolerance=24) -> Image.Image:
    """Trim edges matching the (averaged) edge background color within tolerance."""
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    bg_px = _edge_bg_color(img)
    # Build mask of non-background pixels
    datas = img.getdata()
    new_data = []
    for px in datas:
        if px[3] == 0:
            new_data.append((0, 0, 0, 0))
        elif color_close(px, bg_px, tolerance):
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append((255, 255, 255, 255))
    mask = Image.new('RGBA', img.size)
    mask.putdata(new_data)
    bbox = mask.getbbox()
    if not bbox:
        return img
    return img.crop(bbox)


def pad_and_square(img: Image.Image, size: int, pad: int, bg_rgba: Tuple[int, int, int, int]) -> Image.Image:
    # Add pad around trimmed content first
    w, h = img.size
    padded = Image.new('RGBA', (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    padded.paste(img, (pad, pad), img)

    # Fit into square while preserving aspect
    scale = min((size) / padded.width, (size) / padded.height)
    nw = max(1, int(round(padded.width * scale)))
    nh = max(1, int(round(padded.height * scale)))
    fitted = padded.resize((nw, nh), Image.LANCZOS)

    canvas = Image.new('RGBA', (size, size), bg_rgba)
    x = (size - nw) // 2
    y = (size - nh) // 2
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('input', type=Path)
    ap.add_argument('--out', type=Path, default=Path('ui/public'))
    ap.add_argument('--size', type=int, default=512, help='Base logo size (px)')
    ap.add_argument('--pad', type=int, default=32, help='Padding (px) before fitting')
    ap.add_argument('--bg', type=str, default='#0b1324', help='Background color hex (or #00000000 for transparent)')
    ap.add_argument('--tolerance', type=int, default=28, help='BG trim color tolerance')
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    bg = parse_color(args.bg)

    img = Image.open(args.input)
    trimmed = trim_uniform_bg(img, tolerance=args.tolerance)

    base = pad_and_square(trimmed, args.size, args.pad, bg)
    base.save(args.out / 'logo.png')

    # Additional sizes
    for s in (256, 128):
        pad = max(12, args.pad // 2)
        im = pad_and_square(trimmed, s, pad, bg)
        im.save(args.out / f'logo-{s}.png')

    # Favicon ico (multiple sizes, transparent background is preferred)
    ico_bg = (0, 0, 0, 0) if bg[3] == 0 else bg
    ico_sizes = [16, 32, 48]
    ico_imgs = [pad_and_square(trimmed, s, max(4, args.pad // 4), ico_bg) for s in ico_sizes]
    ico_imgs[0].save(args.out / 'favicon.ico', sizes=[(s, s) for s in ico_sizes])

    print(f"Wrote: {args.out / 'logo.png'}, {args.out / 'logo-256.png'}, {args.out / 'logo-128.png'}, {args.out / 'favicon.ico'}")


if __name__ == '__main__':
    main()
