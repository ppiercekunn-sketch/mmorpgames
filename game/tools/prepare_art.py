#!/usr/bin/env python3
"""Prepare an AI-generated character image for the game.

Usage:
    python3 game/tools/prepare_art.py <input> <id> [--tolerance N] [--soft N]
                                       [--size N] [--force-key] [--out-dir DIR]

Writes game/art/characters/<id>.png (RGBA, <size>x<size>, default 512):
  1. If the image has no real transparency (fully opaque, e.g. a plain or a
     baked-in checkerboard background), the background is removed: the
     dominant border colours are flood-filled from the image edges (within
     --tolerance), with a soft, colour-decontaminated edge (--soft).
  2. Crops to the opaque pixels, pads to a square with the character's feet
     (lowest opaque pixel) on the bottom edge, centred horizontally.
  3. Resizes to --size with Lanczos filtering (premultiplied alpha).

Requires Pillow (pip install Pillow). This folder has a .gdignore, so Godot
neither imports nor exports it.
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter, deque
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageFilter
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: pip install Pillow")

KNOWN_IDS = ("warrior", "slime", "wolf", "bandit", "field_boss", "star_pup")
DEFAULT_OUT_DIR = Path(__file__).resolve().parent.parent / "art" / "characters"
# Images are shrunk to at most this size before keying (speed; the output is
# smaller anyway).
WORK_SIZE = 1024
# Fraction of the side kept free above / beside the character.
MARGIN = 0.02


def has_real_transparency(img: Image.Image) -> bool:
    """True when at least 1% of the pixels are clearly transparent."""
    alpha = img.getchannel("A")
    hist = alpha.histogram()
    transparent = sum(hist[:128])
    return transparent >= 0.01 * img.width * img.height


def border_key_colors(rgb: Image.Image, max_keys: int = 3) -> list[tuple[int, int, int]]:
    """Dominant colours along the image border (handles checkerboards)."""
    w, h = rgb.size
    px = rgb.load()
    samples = []
    for x in range(w):
        samples.append(px[x, 0])
        samples.append(px[x, h - 1])
    for y in range(h):
        samples.append(px[0, y])
        samples.append(px[w - 1, y])
    buckets: dict[tuple[int, int, int], list[tuple[int, int, int]]] = {}
    for c in samples:
        buckets.setdefault((c[0] >> 4, c[1] >> 4, c[2] >> 4), []).append(c)
    counts = Counter({k: len(v) for k, v in buckets.items()})
    keys = []
    for bucket, count in counts.most_common(max_keys):
        if keys and count < 0.08 * len(samples):
            break
        members = buckets[bucket]
        n = len(members)
        keys.append(tuple(sum(c[i] for c in members) // n for i in range(3)))
    return keys


def distance_image(rgb: Image.Image, keys: list[tuple[int, int, int]]) -> Image.Image:
    """Per pixel: max channel difference to the nearest key colour (L image)."""
    result = None
    for key in keys:
        diff = ImageChops.difference(rgb, Image.new("RGB", rgb.size, key))
        r, g, b = diff.split()
        d = ImageChops.lighter(ImageChops.lighter(r, g), b)
        result = d if result is None else ImageChops.darker(result, d)
    return result


def flood_from_border(candidate: Image.Image) -> Image.Image:
    """255 where a candidate pixel (255) is connected to the image border."""
    w, h = candidate.size
    cand = candidate.tobytes()
    out = bytearray(w * h)
    queue: deque[int] = deque()
    for x in range(w):
        for i in (x, (h - 1) * w + x):
            if cand[i] and not out[i]:
                out[i] = 255
                queue.append(i)
    for y in range(h):
        for i in (y * w, y * w + w - 1):
            if cand[i] and not out[i]:
                out[i] = 255
                queue.append(i)
    while queue:
        i = queue.popleft()
        x = i % w
        for j in (i - w, i + w, i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1):
            if 0 <= j < w * h and cand[j] and not out[j]:
                out[j] = 255
                queue.append(j)
    return Image.frombytes("L", (w, h), bytes(out))


def remove_background(img: Image.Image, tolerance: int, soft: int) -> Image.Image:
    rgb = img.convert("RGB")
    keys = border_key_colors(rgb)
    print(f"  background key colours: {keys}")
    dist = distance_image(rgb, keys)
    candidate = dist.point(lambda v: 255 if v <= tolerance else 0)
    removed = flood_from_border(candidate)
    # Soft edge: pixels next to the removed area get alpha from their distance.
    edge = ImageChops.subtract(removed.filter(ImageFilter.MaxFilter(5)), removed)
    scale = 255.0 / max(soft, 1)
    ramp = dist.point(lambda v: max(0, min(255, int((v - tolerance) * scale))))
    ramp_in_edge = ImageChops.lighter(ramp, ImageChops.invert(edge))
    alpha = ImageChops.darker(ImageChops.invert(removed), ramp_in_edge)
    out = img.convert("RGBA")
    out.putalpha(alpha)
    _decontaminate(out, edge, keys)
    return out


def _decontaminate(img: Image.Image, edge: Image.Image, keys) -> None:
    """Un-mix the background colour from semi-transparent edge pixels."""
    px = img.load()
    w = img.width
    key = keys[0]
    for i, e in enumerate(edge.tobytes()):
        if not e:
            continue
        x, y = i % w, i // w
        r, g, b, a = px[x, y]
        if a == 0 or a == 255:
            continue
        f = a / 255.0
        px[x, y] = tuple(
            max(0, min(255, int((c - k * (1.0 - f)) / f))) for c, k in zip((r, g, b), key)
        ) + (a,)


def crop_pad_resize(img: Image.Image, size: int) -> Image.Image:
    bbox = img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if bbox is None:
        sys.exit("error: the image is fully transparent after background removal "
                 "(try a lower --tolerance)")
    img = img.crop(bbox)
    w, h = img.size
    content = max(w, h)
    side = int(round(content / (1.0 - MARGIN)))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    # Feet on the bottom edge, centred horizontally.
    canvas.paste(img, ((side - w) // 2, side - h))
    resized = canvas.convert("RGBa").resize((size, size), Image.LANCZOS)
    return resized.convert("RGBA")


def prepare(path: Path, tolerance: int, soft: int, size: int, force_key: bool) -> Image.Image:
    img = Image.open(path)
    img.load()
    img = img.convert("RGBA")
    if max(img.size) > WORK_SIZE:
        img.thumbnail((WORK_SIZE, WORK_SIZE), Image.LANCZOS)
    if force_key or not has_real_transparency(img):
        print("  no transparency found: removing the background")
        img = remove_background(img, tolerance, soft)
    else:
        print("  image already has transparency: keeping it")
    return crop_pad_resize(img, size)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("input", type=Path, help="source image (PNG/JPG/WebP)")
    parser.add_argument("id", help="character id: " + ", ".join(KNOWN_IDS))
    parser.add_argument("--tolerance", type=int, default=32,
                        help="max colour difference (0-255) treated as background (default 32)")
    parser.add_argument("--soft", type=int, default=40,
                        help="width of the soft edge ramp in colour difference (default 40)")
    parser.add_argument("--size", type=int, default=512, help="output size in pixels (default 512)")
    parser.add_argument("--force-key", action="store_true",
                        help="remove the background even if the image has transparency")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR,
                        help="output folder (default game/art/characters)")
    args = parser.parse_args(argv)
    if args.id not in KNOWN_IDS:
        print(f"warning: '{args.id}' is not a known id ({', '.join(KNOWN_IDS)})")
    print(f"Preparing {args.input} as '{args.id}'")
    out = prepare(args.input, args.tolerance, args.soft, args.size, args.force_key)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    out_path = args.out_dir / f"{args.id}.png"
    out.save(out_path, optimize=True)
    print(f"  wrote {out_path} ({out.width}x{out.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
