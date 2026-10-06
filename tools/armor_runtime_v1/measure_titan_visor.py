"""Measure visible amber glass against a real Godot helmet-only front silhouette.

Reads diagnostic renders; never paints or changes any artwork.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"
REVISIONS = {"helmet_refinement_v4": 4, "helmet_refinement_v5": 5}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    config = json.loads((WORK / "runtime_config.json").read_text())
    revision = config.get("active_helmet_revision")
    assert revision in REVISIONS, f"Unsupported Titan visor coverage revision: {revision}"
    version = REVISIONS[revision]
    captures = WORK / f"review/helmet_v{version}_coverage"
    capture = json.loads((captures / "capture.json").read_text())
    scene = ROOT / config["asset"] / "titan.scn"
    target = WORK / "build/target.json"
    head = ROOT / config["asset"] / config["texture_files"]["head"]
    assert capture["runtime_scene_sha256"] == digest(scene)
    assert capture["target_sha256"] == digest(target)
    assert capture["canonical_diffuse_sha256_at_start"]["head"] == digest(head)
    assert capture["resource_mode"] == "normal_imported_resources" and capture["save_unchanged"]
    paths = {name: captures / f"visor_front_{name}.png" for name in ("mask", "color")}
    for path in paths.values():
        assert capture["capture_sha256"]["res://" + path.relative_to(ROOT).as_posix()] == digest(path)
    mask = Image.open(paths["mask"]).convert("RGB")
    color = Image.open(paths["color"]).convert("RGB")
    assert mask.size == color.size == (640, 720)
    silhouette = glass = 0
    bounds = [mask.width, mask.height, -1, -1]
    for y in range(mask.height):
        for x in range(mask.width):
            # Conservative solid-white silhouette interior excludes antialias borders.
            if min(mask.getpixel((x, y))) < 224:
                continue
            silhouette += 1
            bounds = [min(bounds[0], x), min(bounds[1], y), max(bounds[2], x), max(bounds[3], y)]
            r, g, b = color.getpixel((x, y))
            # The selected atlas uses amber glass and steel-blue shell. This
            # fixed color test excludes blue metal, neutral fasteners and gasket.
            if r > g > b and r - g >= 7 and g - b >= 9 and r - b >= 35:
                glass += 1
    assert silhouette > 0 and bounds[0] > 1 and bounds[1] > 1
    assert bounds[2] < mask.width - 2 and bounds[3] < mask.height - 2, "Helmet-only mask is clipped"
    fraction = glass / silhouette
    report = {"status": "PASS" if fraction >= .50 else "FAIL", "minimum_fraction": .50,
              "projected_front_visor_fraction": fraction, "visor_pixels": glass,
              "helmet_silhouette_pixels": silhouette, "helmet_bounds_px": bounds,
              "definition": "Visible amber glass pixels divided by the whole ArmorHead_05 mesh front orthographic white silhouette interior; all other meshes, background and antialias edges excluded. Any neck geometry contained in ArmorHead_05 remains in the denominator. Not UV area, total 3D surface area, roundness or artistic likeness.",
              "classification": "mask RGB channels >=224; amber r>g>b, r-g>=7, g-b>=9, r-b>=35; fixed for selected amber/steel-blue palette",
              "capture_summary_sha256": digest(captures / "capture.json"),
              "capture_sha256": {name: digest(path) for name, path in paths.items()},
              "current_scene_sha256": digest(scene), "target_sha256": digest(target),
              "canonical_head_sha256": digest(head), "geometry_sha256": digest(WORK / "build/geometry.json")}
    (WORK / f"review/helmet_v{version}_visor_coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"TITAN_VISOR_COVERAGE_{report['status']} front_glass={fraction:.4%}")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
