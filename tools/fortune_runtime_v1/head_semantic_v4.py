"""Make technical, exact authored-UV regions for the approved Fortune helmet.

These SVGs are generation guides, never texture paint or additional UV charts.
Polygon clipping interpolates the existing triangles; it does not modify meshes.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/fortune_runtime_v1"
COLORS = {"dome": "#518c61", "brow": "#8aafc8", "visor": "#af55c6",
          "chin": "#df9944", "cheek": "#d3c05a", "rear": "#43525e", "neck": "#252c33"}


def clip_y(poly, limit, above):
    out = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        a_in = a["position"][1] >= limit if above else a["position"][1] <= limit
        b_in = b["position"][1] >= limit if above else b["position"][1] <= limit
        if a_in:
            out.append(a)
        if a_in != b_in:
            amount = (limit - a["position"][1]) / (b["position"][1] - a["position"][1])
            out.append({key: [x + (y - x) * amount for x, y in zip(a[key], b[key])]
                        for key in ("position", "uv")})
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", default="v4c")
    revision = parser.parse_args().revision
    assert revision.replace("_", "").isalnum(), "Guide revision must be a safe filename token"
    source = json.loads((WORK / "build/source.json").read_text())["parts"]["ArmorHead_01"]["surfaces"][0]
    target = json.loads((WORK / "build/target.json").read_text())["parts"]["ArmorHead_01"]["surfaces"][0]
    regions = []
    for offset in range(0, len(source["indices"]), 3):
        tid = offset // 3
        ids = source["indices"][offset:offset + 3]
        poly = [{"position": target["positions"][i], "uv": target["uv"][i]} for i in ids]
        centre = [sum(p["position"][axis] for p in poly) / 3 for axis in range(3)]
        if tid < 11 or 79 <= tid <= 89:
            zones = [("visor", poly)]
        elif 158 <= tid:
            zones = [("neck", poly)]
        elif 70 <= tid <= 78 or 149 <= tid <= 157:
            zones = [("rear", poly)]
        elif centre[1] > 1.60:
            # The thin front blue lip is now actually 1.615--1.643 m high.
            # Keep its rear continuation distinct from the front repaint mask.
            if centre[2] < -.18:
                zones = [("dome", clip_y(poly, 1.643, True)),
                         ("brow", clip_y(clip_y(poly, 1.643, False), 1.613, True)),
                         ("cheek", clip_y(poly, 1.613, False))]
            else:
                zones = [("dome" if centre[1] > 1.70 else "rear", poly)]
        elif centre[1] < 1.435 and centre[2] < -.185:
            zones = [("chin", poly)]
        else:
            zones = [("cheek" if centre[2] < -.06 else "rear", poly)]
        for semantic, polygon in zones:
            if len(polygon) >= 3:
                regions.append({"semantic": semantic, "triangle": tid,
                                "original_indices": ids, "polygon": polygon})

    def svg(front=False):
        size = 1254
        polygons = []
        order = sorted(regions, key=lambda r: sum(v["position"][2] for v in r["polygon"]) / len(r["polygon"]), reverse=True) if front else regions
        for row in order:
            if front:
                xy = [[(p["position"][0] + .32) / .64 * size,
                       (1.96 - p["position"][1]) / .79 * size] for p in row["polygon"]]
            else:
                xy = [[p["uv"][0] * size, p["uv"][1] * size] for p in row["polygon"]]
            points = " ".join(f"{x:.3f},{y:.3f}" for x, y in xy)
            polygons.append(f'<polygon points="{points}" fill="{COLORS[row["semantic"]]}" stroke="#15202a" stroke-width="1.2"/>')
        if not front:
            # Front dome highlight barycentric point on source triangle 11.
            # The atlas is mirrored: this dot samples both left/right halves.
            polygons.append('<ellipse cx="780.670" cy="102.380" rx="40" ry="27" fill="none" stroke="#fff5ab" stroke-width="5"/>')
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}"><rect width="{size}" height="{size}" fill="#17222d"/>'+"".join(polygons)+"</svg>"

    def write_guide(path, content):
        if path.exists():
            assert path.read_text() == content, f"{path.name}: choose a new revision instead of changing an existing generation guide"
        else:
            path.write_text(content)

    write_guide(WORK / f"guides/head_semantic_authored_{revision}.svg", svg())
    write_guide(WORK / f"guides/head_semantic_front_{revision}.svg", svg(True))
    changed = [{"index": i, "source_uv": before, "authored_uv": after}
               for i, (before, after) in enumerate(zip(source["uv"], target["uv"])) if before != after]
    instructions = {
        "authority": "docs/art/fortune_runtime_v1/approved_helmet_reference.png",
        "coordinate_system": "Atlas u/v in [0,1]; pixel x=u*1254, y=v*1254; Godot rest front is -Z.",
        "guide_only": "Colours and technical edges are labels, never artwork or paint seams.",
        "uv_changes": changed, "changed_count": len(changed), "original_count": len(source["uv"]),
        "colors": COLORS,
        "repaint": {
            "dome": "Smooth olive-green arc; remove dark central V crease and checker/grunge. Green continues down to thin blue band.",
            "brow": "Continuous steel-blue lip without two top holes. The clipped front band corresponds to world y=1.613..1.643, not the old entire broad-blue area.",
            "visor": "Strong broad purple planar facets; no nose button, hairline mesh triangles or diffuse round pink glow. Small steel-blue lower lip only near tip.",
            "chin": "Short mostly-solid olive green; remove large central horizontal vent. Only small paired vertical side slots from the approved image.",
            "cheek": "Olive diagonal cheeks and restrained steel-blue outline, not large blue lower jaw blocks.",
        },
        "highlight": {
            "triangle": 11, "indices": [96, 97, 61], "barycentric_weights": [.15, .70, .15],
            "uv": [sum(target["uv"][i][axis] * weight for i, weight in zip([96, 97, 61], [.15, .70, .15])) for axis in range(2)],
            "position": [sum(target["positions"][i][axis] * weight for i, weight in zip([96, 97, 61], [.15, .70, .15])) for axis in range(3)],
            "note": "Front dome, not back of head. Bilateral atlas coordinates are shared; a unilateral painted white spot cannot be exact without more UV edits. Use a very soft highlight merging across both front halves, not two crisp mirrored dots.",
        },
        "regions": regions,
    }
    write_guide(WORK / f"guides/head_repaint_regions_{revision}.json", json.dumps(instructions, indent=2) + "\n")
    print(f"FORTUNE_HEAD_SEMANTIC_V4_PASS {len(regions)} clipped regions; {len(changed)}/{len(source['uv'])} changed UVs")


if __name__ == "__main__":
    main()
