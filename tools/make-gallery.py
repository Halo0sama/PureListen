#!/usr/bin/env python3
"""把精选截图拼成一张预览展板（README / PR / 聊天展示用）。

用法:
    python3 tools/make-gallery.py [--out docs/design/gallery.png]

依赖 Pillow。输入是 docs/design/gallery/*.jpg（由 tools/curate-gallery.py 生成）。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GALLERY = ROOT / "docs" / "design" / "gallery"

# 2×2 展板: (左, 右)
ROWS = [
    ("popover-home.jpg", "window-hero.jpg"),
    ("popover-tracks.jpg", "window-signal.jpg"),
]

CELL_HEIGHT = 860
GAP = 44
MARGIN = 64
BG = (11, 11, 14)


def fit_height(image: Image.Image, height: int) -> Image.Image:
    ratio = height / image.height
    return image.resize((int(image.width * ratio), height), Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="docs/design/gallery.png")
    args = parser.parse_args()

    rows: list[tuple[Image.Image, Image.Image]] = []
    for left_name, right_name in ROWS:
        left = Image.open(GALLERY / left_name).convert("RGB")
        right = Image.open(GALLERY / right_name).convert("RGB")
        rows.append((fit_height(left, CELL_HEIGHT), fit_height(right, CELL_HEIGHT)))

    left_w = max(left.width for left, _ in rows)
    right_w = max(right.width for _, right in rows)
    width = MARGIN * 2 + left_w + GAP * 2 + right_w
    height = MARGIN * 2 + CELL_HEIGHT * len(rows) + GAP * (len(rows) - 1)

    canvas = Image.new("RGB", (width, height), BG)
    y = MARGIN
    for left, right in rows:
        canvas.paste(left, (MARGIN + left_w - left.width, y))
        canvas.paste(right, (MARGIN + left_w + GAP * 2, y))
        y += CELL_HEIGHT + GAP

    out = ROOT / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, quality=92, optimize=True)
    print(f"✓ {out}  {canvas.size[0]}×{canvas.size[1]}")


if __name__ == "__main__":
    main()
