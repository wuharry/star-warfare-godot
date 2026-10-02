"""Measure a candidate armor texture set against the original SW1 distribution.

Usage: python3 tools/armor_texture_check.py new_set/*.png

Thresholds come from the 21 original SW1 sets (ids 00-20) in
assets/models/player/animated/armor_textures/. See docs/art/ARMOR_TEXTURE_STYLE_SPEC.md.
A set is 5 textures (head/body/jian/hand/foot); single files vary far too much
to judge on their own, so the statistics below are computed over the whole set.
"""

from __future__ import annotations

import colorsys
import math
import sys

from PIL import Image

# (label, low, high, median) — the measured min..max across the 21 original
# sets, rounded to 3dp. TOLERANCE covers that rounding so the sets that define
# an endpoint (09 Draco sits exactly on the p98 low) still pass their own band.
# Staying inside the band means "indistinguishable from the original family",
# not "good art"; the painting rules in the spec are not measurable here, and
# a set whose design is deliberately bright or white is expected to sit near an
# endpoint rather than near the median.
TOLERANCE = 0.001
BANDS = {
    "mean_value": ("平均明度", 0.140, 0.412, 0.224),
    "p98_value": ("p98 明度", 0.416, 1.000, 0.745),
    "bright_ratio": ("亮像素占比 (>0.62)", 0.001, 0.181, 0.050),
    "hue_concentration": ("色相集中度 (±30°)", 0.172, 1.000, 0.926),
}


def measure(paths: list[str]) -> dict[str, float]:
    values: list[float] = []
    hues: list[float] = []
    opaque = True
    for path in paths:
        image = Image.open(path).convert("RGBA")
        for red, green, blue, alpha in image.get_flattened_data():
            if alpha != 255:
                opaque = False
            hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
            values.append(value)
            if saturation > 0.25 and value > 0.25:
                hues.append(hue * 360.0)
    values.sort()
    count = len(values)
    if hues:
        x = sum(math.cos(math.radians(h)) for h in hues)
        y = sum(math.sin(math.radians(h)) for h in hues)
        mean_hue = math.degrees(math.atan2(y, x)) % 360.0
        inside = sum(1 for h in hues if min(abs(h - mean_hue), 360 - abs(h - mean_hue)) <= 30)
        concentration = inside / len(hues)
    else:
        # No pixel clears the saturation/value gate, so there is no hue to
        # concentrate. Original 09 Draco lands here: it still has pixels whose
        # channels differ, so it is low-chroma dark grey, not true greyscale.
        # Reporting 1.0 here would print a PASS the measurement cannot support.
        mean_hue, concentration = float("nan"), float("nan")
    return {
        "opaque": opaque,
        "mean_value": sum(values) / count,
        "p98_value": values[int(count * 0.98)],
        "bright_ratio": sum(1 for v in values if v > 0.62) / count,
        "hue_concentration": concentration,
        "coloured_ratio": len(hues) / count,
        "mean_hue": mean_hue,
    }


def main(paths: list[str]) -> int:
    if not paths:
        print(__doc__)
        return 2
    if len(paths) != 5:
        print(f"注意：原版一套是 5 張，這裡收到 {len(paths)} 張，門檻仍以整組計算。\n")
    result = measure(paths)
    failures = 0

    status = "PASS" if result["opaque"] else "FAIL  有透明像素，原版 105 張全不透明"
    print(f"{'不透明':<22} {status}")
    failures += 0 if result["opaque"] else 1

    for key, (label, low, high, median) in BANDS.items():
        value = result[key]
        if math.isnan(value):
            print(f"{label:<22} 無達標彩色像素，不適用")
            continue
        ok = low - TOLERANCE <= value <= high + TOLERANCE
        failures += 0 if ok else 1
        print(
            f"{label:<22} {value:.3f}   原版 {low:.3f}–{high:.3f}（中位 {median:.3f}）"
            f"   {'PASS' if ok else 'FAIL'}"
        )

    print(f"\n有彩色像素占比 {result['coloured_ratio'] * 100:.1f}%   原版 0.0%–62.8%，不設門檻")
    if not math.isnan(result["mean_hue"]):
        print(f"主色相 {result['mean_hue']:.0f}°")
    print(
        "\n驗收通過只代表亮度與配色落在原版家族內，"
        "打光方向、縫隙畫法與細節尺度仍要目視比對。"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
