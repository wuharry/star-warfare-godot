"""Fit the Viper-style chamfered panels to the original Thunder helmet.

Blender --background --python tools/armor_facets/build_thunder_head.py
godot --headless --path . --script tools/armor_facets/compile_thunder_head.gd

Only ArmorHead_06 is rebuilt, from the untouched player.gltf mesh that
export.gd already records as sources.json's reference entry. The hand-modelled
v5 body, hands and feet are reused as they are. Panels are projected onto the
original surface, so its UVs, texture and 28 named binds are unchanged.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build_meshes import (  # noqa: E402: same directory, shares the fitted shells
    FittedShells,
    ROOT,
    SourceAttributes,
    UPRIGHT,
    WORK,
    build_object,
    export_object,
)

PART = "ArmorHead_06"
# Viper's own fit profile. The helmet is a single closed shell, so the
# largest-component filter keeps a front projection off the inner face lining.
PROFILE = {"blend_source_boundaries": False, "flatten": .30,
           "outer_surface_only": True, "max_lift": .042, "largest_component_only": True}


def panels() -> list[tuple[str, list, float, bool, float]]:
    """Viper's helmet treatment on the original Thunder crown proportions.

    Every outline is cut to where the source triangles still face the
    projection axis. Thunder's shell turns to the side much earlier than
    Viper's, and a panel that reaches past that turn extrudes its wall out of
    the silhouette as a flat shard. Measured reach of triangles with a normal
    at least .35 along the axis, by height band:

        front  1.70-1.75 .110   1.65-1.70 .178   1.60-1.65 .189
               1.35-1.40 .123   1.30-1.35 .162   1.25-1.30 .093
        rear   1.80-1.85 .133   1.70-1.75 .165   1.55-1.60 .250

    The band between the brow and the chin stays bare: that gap is the visor.
    """
    return [
        ("brow rim", [(-.170, 1.598), (-.115, 1.706), (.115, 1.706), (.170, 1.598)], .012, False, 0.0),
        ("chin guard", [(-.114, 1.388), (.114, 1.388), (.145, 1.310), (0, 1.248), (-.145, 1.310)], .012, False, .003),
        ("rear helmet", [(0, 1.845), (.126, 1.810), (.205, 1.690), (.232, 1.575), (.196, 1.470),
                         (0, 1.430), (-.196, 1.470), (-.232, 1.575), (-.205, 1.690), (-.126, 1.810)], .012, True, .004),
    ]


def main() -> None:
    sources_path = WORK / "sources.json"
    data = json.loads(sources_path.read_text())
    reference = data["reference"]
    assert reference["id"] == 6 and reference["reference_only"], "Thunder reference parts moved"
    part = next(p for p in reference["parts"] if p["name"] == PART)
    assert len(part["surfaces"]) == 1, "The original helmet is a single textured surface"
    surface = part["surfaces"][0]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    rotation: Matrix = UPRIGHT
    obj = build_object(surface, PART, rotation, 1)
    shells = FittedShells(obj, PROFILE)
    names = []
    try:
        for name, outline, height, rear, crest in panels():
            shells.panel(name, 1, outline, height=height, bevel=.085, back=rear, bulge=crest)
            names.append(name)
        shells.finish()
    except Exception:
        if shells.bm.is_valid:
            shells.bm.free()
        raise
    assert len(names) == len(panels()), "Every authored helmet panel must fit"
    result = export_object(obj, rotation.inverted(), SourceAttributes(surface, rotation))

    source_triangles = len(surface["arrays"].get("12") or surface["arrays"]["0"]) // 3
    triangles = len(result["12"]) // 3
    fingerprints = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in (Path(__file__), HERE / "build_meshes.py",
                                 ROOT / "tools/armor_rework/thunder_body.py", sources_path)}
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "thunder_head.json").write_text(json.dumps({PART: [result]}, separators=(",", ":")))
    (WORK / "thunder_head_report.json").write_text(json.dumps({
        "revision": "thunder_original_helmet_v1",
        "source": reference["source"],
        "part": PART,
        "panels": names,
        "source_triangles": source_triangles,
        "triangles": triangles,
        "binds": len(part["binds"]),
        "fingerprints": fingerprints,
    }, indent=2) + "\n")
    print(f"THUNDER_ORIGINAL_HEAD_PASS panels={len(names)} "
          f"source_triangles={source_triangles} triangles={triangles}", flush=True)


if __name__ == "__main__":
    main()
