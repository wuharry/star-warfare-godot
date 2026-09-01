#!/usr/bin/env python3
"""Cut individual UI component PNGs out of the recovered NGUI page atlases.

The menu used to sample these sprites at runtime with hand written Rect2
coordinates. Several of those rectangles were wrong: the button plate sample was
wide enough to pull in the cyan play arrow packed two pixels to its right, and
short enough to slice the bottom border off. Cutting each sprite to its own file
removes that whole class of bug and lets Godot treat every element as a plain
texture.

Coordinates below are in SOURCE pixels of the 2x atlases. Each rectangle is
deliberately generous; every crop is then trimmed inwards to its real alpha
bounding box, so a few pixels of slack cannot reintroduce a neighbour.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
PAGES = REPO / "assets/original/ui/pages"
OUT = REPO / "assets/ui/components"

ALPHA_FLOOR = 8

# name -> (page, x, y, w, h) in 2x source pixels
COMPONENTS: dict[str, tuple[str, int, int, int, int]] = {
    # Title lockup. The old sample reached into the yellow reward coin packed
    # beside it, which the menu then erased with a dedicated shader.
    "menu_logo":       ("2",  0,  355,  998, 277),
    "menu_subtitle":   ("2",  0, 1010,  828,  69),

    # Button plates. Measured to their true edges - the states are stacked
    # behind one pixel seams and a play arrow sits two pixels to the right.
    "button_normal":   ("4", 1265,   0, 642, 117),
    "button_hover":    ("4", 1265, 121, 642, 117),
    "button_pressed":  ("4", 1265, 240, 642, 118),
    "button_equip":    ("4", 1265, 849, 618, 117),

    "store_backdrop":  ("4", 3136,   0, 960, 1280),
    "menu_hero":       ("16",   0,   0, 2048, 1300),
}


def trim_to_alpha(image: Image.Image) -> Image.Image:
    """Shrink to the alpha bounding box. Never grows the crop."""
    alpha = image.getchannel("A")
    box = alpha.point(lambda v: 255 if v > ALPHA_FLOOR else 0).getbbox()
    return image if box is None else image.crop(box)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    pages: dict[str, Image.Image] = {}
    written = 0

    for name, (page, x, y, w, h) in sorted(COMPONENTS.items()):
        source = PAGES / f"{page}.png"
        if not source.exists():
            print(f"  MISSING PAGE {source}", file=sys.stderr)
            return 1
        if page not in pages:
            pages[page] = Image.open(source).convert("RGBA")
        sheet = pages[page]
        x1 = min(x + w, sheet.width)
        y1 = min(y + h, sheet.height)
        raw = sheet.crop((x, y, x1, y1))
        cut = trim_to_alpha(raw)
        target = OUT / f"{name}.png"
        cut.save(target, optimize=True)
        written += 1
        trimmed = "" if cut.size == raw.size else f"  (trimmed from {raw.size[0]}x{raw.size[1]})"
        print(f"  {name:<16} {cut.size[0]:>5} x {cut.size[1]:<5} <- pages/{page}.png{trimmed}")

    print(f"\nwrote {written} components to {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
