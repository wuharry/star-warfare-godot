"""Exact UV masks for the mirrored visor-centre and neck repaint only.

Technical SVG output is not a modification of generated artwork or mesh UVs.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/fortune_runtime_v1"
SIZE = 1254


def clip(poly, axis, limit, above):
    out = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        a_in = a[axis] >= limit if above else a[axis] <= limit
        b_in = b[axis] >= limit if above else b[axis] <= limit
        if a_in:
            out.append(a)
        if a_in != b_in:
            weight = (limit - a[axis]) / (b[axis] - a[axis])
            out.append([x + (y - x) * weight for x, y in zip(a, b)])
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", choices=["v5", "v6"], default="v6")
    revision = parser.parse_args().revision
    front_end = .69 if revision == "v6" else .64
    side_start = .70 if revision == "v6" else .65
    front_color = "#a178bb" if revision == "v6" else "#a97bc6"
    original = json.loads((WORK / "build/source.json").read_text())["parts"]["ArmorHead_01"]["surfaces"][0]
    target = json.loads((WORK / "build/target.json").read_text())["parts"]["ArmorHead_01"]["surfaces"][0]
    layers = []
    polygons = []

    def draw(poly, color, label, tid):
        if len(poly) < 3:
            return
        points = " ".join(f"{u * SIZE:.3f},{v * SIZE:.3f}" for u, v in poly)
        polygons.append(f'<polygon points="{points}" fill="{color}" stroke="#516777" stroke-width=".7"/>')
        layers.append({"label": label, "original_triangle": tid, "authored_uv_polygon": poly})

    for offset in range(0, len(original["indices"]), 3):
        tid = offset // 3
        poly = [target["uv"][i] for i in original["indices"][offset:offset + 3]]
        draw(poly, "#283642", "unchanged", tid)
    for offset in range(0, len(original["indices"]), 3):
        tid = offset // 3
        poly = [target["uv"][i] for i in original["indices"][offset:offset + 3]]
        if tid < 11 or 79 <= tid <= 89:
            draw(poly, "#54276b", "deep_purple_side_facet", tid)
            draw(clip(clip(poly, 0, front_end, True), 0, side_start, False), "#9562b0", "soft_transition", tid)
            draw(clip(poly, 0, front_end, False), front_color, "continuous_mid_purple_front_centre", tid)
            # Retain the v4 small blue lip at the actual lowest visor tip.
            draw(clip(clip(poly, 1, .977, True), 0, .63, False), "#8aafc8", "preserve_tiny_blue_lower_lip", tid)
        elif tid >= 158:
            draw(poly, "#20252a", "pure_charcoal_neck_ribs", tid)
    # Bleed beyond the shared central sample edge; this is not a gasket edge.
    polygons.append(f'<rect x="{.548 * SIZE:.3f}" y="{.707 * SIZE:.3f}" width="{.006 * SIZE:.3f}" height="{.268 * SIZE:.3f}" fill="{front_color}"/>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">'
           f'<rect width="{SIZE}" height="{SIZE}" fill="#17222d"/>' + "".join(polygons) + "</svg>")
    notes = {
        "guide_only": "Flat technical colour labels. Do not paint triangle edges, guide colours, text or mask boundaries into the artwork.",
        "size": [SIZE, SIZE],
        "unchanged": "All crown, eyebrow, cheek and solid-green short chin improvements in head v4 must remain unchanged.",
        "front": {"uv": [.548, front_end, .707, .975], "color": "one uniform mid violet plane, with sampling bleed",
                  "meaning": "The LEFT edge of the lower-right visor atlas is the shared physical FRONT centre, not an outer gasket border. Its brightness must equal u=.60; bleed uniform violet past the left edge. No central vertical gradient/columns, black outlining, central V/nose fold or two mirrored bright pillars. The gasket belongs only on physical top/right outer edges."},
        "side": {"uv": [side_start, .965, .700, .977], "color": "deep violet angular side planes",
                 "meaning": "The right of this atlas island is the side cheek. Transition into the light main front plane rather than making a second centre stripe."},
        "neck": {"uv": [.045, .436, .841, .957], "color": "pure neutral charcoal with fine horizontal ribs",
                 "meaning": "Bottom-left rectangular atlas strip; no brown leather, bronze or coarse quilt."},
        "small_blue_lower_lip": "Preserve the tiny existing blue tip around u=.553..63, v=.977..991.",
        "polygons": layers,
    }
    for suffix, content in [("svg", svg), ("json", json.dumps(notes, indent=2) + "\n")]:
        path = WORK / f"guides/head_visor_neck_semantic_{revision}.{suffix}"
        if path.exists():
            assert path.read_text() == content, "Choose a new guide revision instead of changing existing generation inputs"
        else:path.write_text(content)
    print(f"FORTUNE_VISOR_NECK_{revision.upper()}_GUIDE_PASS original shared UV positions, no mesh or artwork edits")


if __name__ == "__main__":
    main()
