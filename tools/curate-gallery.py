#!/usr/bin/env python3
"""把 --ui-studio 生成的原始截图压缩成仓库里提交的精选图（docs/design/gallery）。

原始 PNG 很大（2x、带阴影），不适合入库；这个脚本把它们统一成宽 1400px 的 JPEG，
并生成 README 用的拼版图。

用法:
    python3 tools/curate-gallery.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "design" / "screens"
OUT = ROOT / "docs" / "design" / "gallery"

# 精选: 文件名 → 输出名(不带扩展名)
CURATED = {
    "popover-home-dark": "popover-home",
    "popover-tracks-dark": "popover-tracks",
    "popover-search-dark": "popover-search",
    "popover-bili-dark": "popover-bili",
    "popover-settings-dark": "popover-settings",
    "popover-login-dark": "popover-login",
    "popover-login-scanned-dark": "popover-login-scanned",
    "window-hero-dark": "window-hero",
    "window-lyrics-dark": "window-lyrics",
    "window-signal-dark": "window-signal",
    "window-settings-dark": "window-settings",
    "window-idle-dark": "window-idle",
    "bili-web-login-dark": "bili-web-login",
    "popover-home-light": "popover-home-light",
    "window-hero-light": "window-hero-light",
}

TARGET_WIDTH = 1400


def trim_shadow(image: Image.Image) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    return image.crop(bbox) if bbox else image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    converted = 0
    for source_name, out_name in CURATED.items():
        path = SRC / f"{source_name}.png"
        if not path.exists():
            print(f"  · 跳过（缺失）: {source_name}")
            continue
        image = trim_shadow(Image.open(path).convert("RGBA"))
        if image.width > TARGET_WIDTH:
            ratio = TARGET_WIDTH / image.width
            image = image.resize((TARGET_WIDTH, int(image.height * ratio)), Image.LANCZOS)
        # JPEG 不支持透明: 铺一个与截图背景相近的中性底, 并留出呼吸边距
        margin = 28
        canvas = Image.new("RGB", (image.width + margin * 2, image.height + margin * 2),
                           (10, 10, 12))
        canvas.paste(image, (margin, margin), mask=image.getchannel("A"))
        target = OUT / f"{out_name}.jpg"
        canvas.save(target, quality=88, optimize=True, progressive=True)
        converted += 1
        print(f"  ✓ {target.relative_to(ROOT)}  {canvas.size[0]}×{canvas.size[1]}")

    print(f"完成: {converted} 张 → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
