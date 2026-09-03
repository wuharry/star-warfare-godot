#!/usr/bin/env python3
"""Cut individual UI component PNGs out of the recovered NGUI page atlases.

The menu used to sample these sprites at runtime with hand written Rect2
coordinates. Several of those rectangles were wrong: the button plate sample was
wide enough to pull in the cyan play arrow packed two pixels to its right, and
short enough to slice the bottom border off. Cutting each sprite to its own file
removes that whole class of bug and lets Godot treat every element as a plain
texture.

Coordinates in ``COMPONENTS`` are SOURCE pixels of the 2x atlases.  The
composites below use the logical 1x module coordinates stored in resUI.bytes;
they are assembled at 2x so Godot can render the original 960x640 layout with
the same detail as Unity.
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
    "menu_hero":       ("16",   0,   0, 1920, 1280),
}

SOURCE_SCALE = 2


def module_crop(pages: dict[str, Image.Image], page: str,
                rect: tuple[int, int, int, int]) -> Image.Image:
    """Crop one logical resUI module from a native 2x atlas page."""
    if page not in pages:
        source = PAGES / f"{page}.png"
        if not source.exists():
            raise FileNotFoundError(source)
        pages[page] = Image.open(source).convert("RGBA")
    x, y, width, height = rect
    return pages[page].crop((
        x * SOURCE_SCALE,
        y * SOURCE_SCALE,
        (x + width) * SOURCE_SCALE,
        (y + height) * SOURCE_SCALE,
    ))


def composite(size: tuple[int, int], pages: dict[str, Image.Image],
              pieces: list[tuple[str, tuple[int, int, int, int], tuple[int, int]]]) -> Image.Image:
    """Rebuild a multi-module Unity UIImage at its original relative offsets."""
    canvas = Image.new("RGBA", (size[0] * SOURCE_SCALE, size[1] * SOURCE_SCALE))
    for page, source_rect, position in pieces:
        cut = module_crop(pages, page, source_rect)
        canvas.alpha_composite(cut, (position[0] * SOURCE_SCALE, position[1] * SOURCE_SCALE))
    return canvas


def build_unity_composites(pages: dict[str, Image.Image]) -> dict[str, Image.Image]:
    title_modules = [
        ("2", (518, 619, 185, 102), (410, 0)),
        ("2", (0, 317, 417, 187), (22, 32)),
        ("2", (0, 176, 499, 140), (148, 105)),
        ("2", (0, 600, 243, 108), (0, 55)),
        ("2", (0, 505, 414, 34), (176, 219)),
        ("2", (500, 238, 35, 34), (385, 79)),
        ("2", (500, 273, 32, 32), (110, 128)),
        ("2", (500, 306, 32, 32), (236, 150)),
    ]

    normal_plate = (518, 531, 348, 87)
    pressed_plate = (0, 540, 320, 59)

    result = {
        "main_title": composite((595, 253), pages, title_modules),
        "main_bottom_panel": module_crop(pages, "2", (0, 0, 960, 150)),
        "main_free_mithril": module_crop(pages, "18", (3, 2, 128, 137)),
        "main_new_badge": module_crop(pages, "18", (133, 114, 44, 25)),
        "main_single_normal": composite((348, 87), pages, [
            ("2", normal_plate, (0, 0)),
            ("2", (867, 573, 132, 25), (108, 23)),
        ]),
        "main_single_pressed": composite((348, 87), pages, [
            ("2", pressed_plate, (14, 14)),
            ("2", (867, 547, 132, 25), (108, 31)),
        ]),
        "main_online_normal": composite((348, 87), pages, [
            ("2", normal_plate, (0, 0)),
            ("2", (134, 787, 133, 25), (108, 23)),
        ]),
        "main_online_pressed": composite((348, 87), pages, [
            ("2", pressed_plate, (14, 14)),
            ("2", (0, 787, 133, 25), (108, 31)),
        ]),
        "main_nav_panel": composite((960, 272), pages, [
            ("7", (544, 238, 480, 240), (0, 0)),
            ("7", (544, 238, 480, 240), (480, 0)),
            ("7", (120, 480, 840, 32), (0, 240)),
        ]),
        "main_nav_toggle": module_crop(pages, "7", (191, 102, 120, 110)),
        "main_nav_bank": module_crop(pages, "7", (0, 0, 410, 100)),
        "main_nav_button_normal": module_crop(pages, "7", (0, 101, 190, 100)),
        "main_nav_button_pressed": module_crop(pages, "7", (692, 0, 190, 100)),
        "main_nav_options_icon": module_crop(pages, "5", (173, 0, 52, 62)),
        "main_nav_options_icon_pressed": module_crop(pages, "5", (384, 129, 52, 62)),
        "main_nav_store_icon": module_crop(pages, "5", (275, 0, 60, 47)),
        "main_nav_store_icon_pressed": module_crop(pages, "5", (274, 61, 60, 47)),
        "main_nav_customize_icon": module_crop(pages, "5", (226, 0, 48, 60)),
        "main_nav_customize_icon_pressed": module_crop(pages, "5", (225, 63, 48, 60)),
        "main_nav_edit_normal": module_crop(pages, "7", (333, 262, 151, 57)),
        "main_nav_edit_pressed": module_crop(pages, "7", (333, 203, 151, 57)),
        "main_nav_shadow": module_crop(pages, "8", (908, 53, 98, 98)),
    }

    # StoreUI/CustomizeUI share the same two-piece 960x640 background.  The
    # second module is the first module with Unity's rotation flag 4 (FlipX).
    armory_half = module_crop(pages, "4", (1568, 0, 480, 640))
    armory_background = Image.new("RGBA", (960 * SOURCE_SCALE, 640 * SOURCE_SCALE))
    armory_background.alpha_composite(armory_half, (0, 0))
    armory_background.alpha_composite(
        armory_half.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
        (480 * SOURCE_SCALE, 0),
    )

    nav_bar = composite((960, 80), pages, [
        ("7", (0, 241, 320, 80), (0, 0)),
        ("7", (0, 241, 320, 80), (320, 0)),
        ("7", (0, 241, 320, 80), (640, 0)),
        ("7", (455, 33, 41, 78), (97, 1)),
        ("7", (0, 322, 320, 78), (138, 1)),
        ("7", (0, 322, 200, 78), (458, 1)),
        ("7", (252, 401, 39, 78), (658, 1)),
        ("7", (416, 343, 21, 21), (705, 11)),
        ("7", (416, 321, 21, 21), (705, 30)),
        ("7", (438, 321, 21, 21), (705, 49)),
    ])
    back_normal = composite((125, 78), pages, [
        ("7", (0, 401, 125, 78), (0, 0)),
        ("7", (324, 321, 40, 46), (30, 15)),
    ])
    back_pressed = composite((125, 78), pages, [
        ("7", (126, 401, 125, 78), (0, 0)),
        ("7", (372, 321, 40, 46), (30, 16)),
    ])

    # The right-hand equipment description is assembled from twelve border
    # modules around a resized authored fill, exactly as StoreUI.Create does.
    detail_panel = Image.new("RGBA", (232 * SOURCE_SCALE, 374 * SOURCE_SCALE))
    detail_fill = module_crop(pages, "4", (1207, 63, 218, 114)).resize(
        (222 * SOURCE_SCALE, 292 * SOURCE_SCALE), Image.Resampling.BILINEAR
    )
    detail_panel.alpha_composite(detail_fill, (5 * SOURCE_SCALE, 59 * SOURCE_SCALE))
    detail_border = composite((232, 374), pages, [
        ("4", (1199, 1, 25, 61), (0, 0)),
        ("4", (1225, 1, 183, 61), (25, 0)),
        ("4", (1409, 1, 24, 61), (208, 0)),
        ("4", (1199, 62, 6, 85), (0, 60)),
        ("4", (1427, 62, 6, 85), (226, 60)),
        ("4", (1199, 62, 6, 116), (0, 145)),
        ("4", (1428, 62, 5, 116), (227, 145)),
        ("4", (1428, 62, 5, 116), (227, 234)),
        ("4", (1199, 62, 6, 116), (0, 234)),
        ("4", (1199, 179, 25, 25), (0, 349)),
        ("4", (1409, 179, 24, 25), (208, 349)),
        ("4", (1225, 179, 183, 25), (25, 349)),
    ])
    detail_panel.alpha_composite(detail_border)

    result.update({
        "armory_background": armory_background,
        "armory_nav_bar": nav_bar,
        "armory_back_normal": back_normal,
        "armory_back_pressed": back_pressed,
        "armory_side_button": module_crop(pages, "4", (1285, 326, 88, 75)),
        "armory_side_flag": module_crop(pages, "4", (954, 106, 21, 21)),
        "armory_category_frame": module_crop(pages, "4", (621, 740, 120, 99)),
        "armory_nav_dot": module_crop(pages, "4", (406, 905, 10, 10)),
        "armory_nav_selected": module_crop(pages, "4", (406, 886, 18, 18)),
        "armory_detail_panel": detail_panel,
        # StoreUI modules 30-41 form the three comparison meters above the
        # equipment description.  Keeping the authored rails and coloured
        # fills separate lets Godot clip them to the live HP/POW/SPD values in
        # the same way as StoreUI.DrawComparsion.
        "armory_stat_rail": module_crop(pages, "4", (187, 986, 214, 12)),
        "armory_stat_hp_fill": module_crop(pages, "4", (406, 944, 210, 10)),
        "armory_stat_hp_gain": module_crop(pages, "4", (179, 1003, 210, 10)),
        "armory_stat_hp_loss": module_crop(pages, "4", (406, 977, 210, 10)),
        "armory_stat_pow_fill": module_crop(pages, "4", (406, 933, 210, 10)),
        "armory_stat_pow_gain": module_crop(pages, "4", (406, 922, 210, 10)),
        "armory_stat_pow_loss": module_crop(pages, "4", (406, 966, 210, 10)),
        "armory_stat_spd_fill": module_crop(pages, "4", (406, 955, 210, 10)),
        "armory_stat_spd_gain": module_crop(pages, "4", (179, 1014, 210, 10)),
        "armory_stat_spd_loss": module_crop(pages, "4", (406, 988, 210, 10)),
        "armory_stat_hp_title": module_crop(pages, "4", (1084, 967, 240, 18)),
        "armory_stat_pow_title": module_crop(pages, "4", (1084, 1005, 240, 18)),
        "armory_stat_spd_title": module_crop(pages, "4", (1084, 986, 240, 18)),
        # The original dialog owns a compact 150x58 action plate at
        # (747,526).  Text and numeric price glyphs are separate UI controls,
        # so only the three plate states are extracted here.
        "armory_action_disabled": module_crop(pages, "4", (984, 704, 150, 58)),
        "armory_action_pressed": module_crop(pages, "4", (984, 763, 150, 58)),
        "armory_action_normal": module_crop(pages, "4", (983, 822, 150, 58)),
    })
    for category_id, rect in enumerate([
        (156, 173, 64, 64), (104, 173, 64, 64), (51, 173, 64, 64),
        (0, 173, 64, 64), (400, 192, 64, 64), (208, 172, 64, 64),
    ]):
        result[f"armory_category_{category_id:02d}"] = module_crop(pages, "5", rect)
    for rank_id, rect in enumerate([
        (497, 0, 64, 64), (562, 0, 64, 64), (627, 0, 64, 64),
        (497, 65, 64, 64), (562, 65, 64, 64), (627, 65, 64, 64),
        (497, 130, 64, 64), (562, 130, 64, 64), (627, 130, 64, 64),
        (692, 101, 64, 64), (757, 101, 64, 64), (822, 101, 64, 64),
    ]):
        result[f"main_rank_{rank_id:02d}"] = module_crop(pages, "7", rect)
    return result


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

    for name, cut in sorted(build_unity_composites(pages).items()):
        target = OUT / f"{name}.png"
        cut.save(target, optimize=True)
        written += 1
        print(f"  {name:<28} {cut.size[0]:>5} x {cut.size[1]:<5} <- resUI module composite")

    print(f"\nwrote {written} components to {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
