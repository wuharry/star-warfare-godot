"""Cygni style trial: fit shallow concept layers onto the original painted cage.

Uses the original game coordinates, UV seams and skin interpolation. No source
asset, skeleton or animation is edited. Run armor_facets/export.gd first.
"""
from __future__ import annotations

import copy
import hashlib
import json
import runpy
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/armor_facets"))
from build_meshes import FittedShells, SourceAttributes, UPRIGHT, build_object, export_object, mirror, role_for

WORK = ROOT / "test_output/armor_concept_runtime"
ASSET = ROOT / "docs/art/armor_runtime_v1/armor_11/painted_trial"
REVISION = "concept_painted_cygni_trial_v2"


def authored_regions(role: int) -> list:
    # Placement follows the original Cygni bind-pose surface, in metres.
    # Layer depths and projected concept panel outlines are inferred; the
    # original per-part bounding boxes and joint centres remain authoritative.
    shapes = {
        0: [
            ("layered brow", [(.024, 1.747), (.10, 1.767), (.22, 1.718), (.229, 1.676), (.124, 1.681), (.024, 1.710)], .008, False),
            ("swept cheek", [(.066, 1.361), (.109, 1.389), (.191, 1.530), (.240, 1.534), (.217, 1.415), (.142, 1.292), (.066, 1.279)], .008, False),
        ],
        1: [
            ("upper breastplate", [(.029, 1.249), (.122, 1.273), (.212, 1.228), (.204, 1.142), (.111, 1.103), (.032, 1.135)], .009, False),
            ("outer thigh", [(.183, .766), (.270, .772), (.291, .635), (.262, .498), (.194, .520)], .007, False),
        ],
        2: [("shoulder plate", [(.325, 1.353), (.422, 1.350), (.517, 1.279), (.518, 1.210), (.410, 1.165), (.335, 1.192)], .009, False)],
        3: [("forearm plate", [(.448, .997), (.539, 1.018), (.590, .925), (.563, .817), (.487, .804), (.439, .906)], .007, False)],
        4: [("shin plate", [(.211, .405), (.320, .408), (.377, .261), (.345, .137), (.241, .141), (.201, .258)], .009, False)],
    }[role]
    return [(f"{side} {name}", mirror(outline, side), height, rear)
            for side in (-1, 1) for name, outline, height, rear in shapes]


def bounds(points: list) -> list:
    return [[min(p[k] for p in points), max(p[k] for p in points)] for k in range(3)]


def clean_delivery_mesh(obj: bpy.types.Object) -> None:
    """Remove clipping-only debris, retaining source seams and bind weights."""
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
    empty = [face for face in mesh.faces if face.calc_area() < 1e-12]
    if empty:
        bmesh.ops.delete(mesh, geom=empty, context="FACES_ONLY")
    wires = [edge for edge in mesh.edges if not edge.link_faces]
    if wires:
        bmesh.ops.delete(mesh, geom=wires, context="EDGES")
    loose = [vertex for vertex in mesh.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(mesh, geom=loose, context="VERTS")
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()


def native_material(path: str, tint: list, name: str) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes.clear()
    image = bpy.data.images.load(str(ROOT / path.removeprefix("res://")), check_existing=True)
    image.colorspace_settings.name = "sRGB"
    nodes = material.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.inputs[2].default_value = tint
    emit = nodes.new("ShaderNodeEmission")
    out = nodes.new("ShaderNodeOutputMaterial")
    links = material.node_tree.links
    links.new(tex.outputs["Color"], mix.inputs[1])
    links.new(mix.outputs[0], emit.inputs[0])
    links.new(emit.outputs[0], out.inputs[0])
    return material


def main() -> None:
    data = json.loads((ROOT / "test_output/armor_facets/sources.json").read_text())
    entry = next(e for e in data["entries"] if e["id"] == 11)
    # Import the original rig exactly; retain it as the native animation master.
    scope = runpy.run_path(str(ROOT / "tools/armor_rework/inspect_source.py"))
    rig = scope["rig"]
    for obj in list(bpy.data.objects):
        if obj != rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    output, reports = {}, {}
    collection = bpy.data.collections.new("LOW")
    bpy.context.scene.collection.children.link(collection)
    for part in entry["parts"]:
        output[part["name"]] = []
        reports[part["name"]] = []
        bind_map = {b["name"]: b["index"] for b in part["binds"]}
        for sid, refined in enumerate(part["surfaces"]):
            surface = copy.deepcopy(refined)
            raw = copy.deepcopy(part["raw_surfaces"][sid]["arrays"])
            raw["10"] = [bind_map[part["raw_binds"][int(i)]["name"]] for i in raw["10"]]
            surface["arrays"] = raw
            points = [UPRIGHT @ Vector(p) for p in raw["0"]]
            role = role_for(part["name"], surface["material"], points)
            canonical = max(role, 1)
            obj = build_object(surface, f"{part['name']}_surface_{sid}", UPRIGHT, canonical)
            shell = FittedShells(obj, {"blend_source_boundaries": True, "flatten": 0.0,
                                      "outer_surface_only": True, "max_lift": .012,
                                      "largest_component_only": True})
            names = []
            try:
                for name, outline, height, rear in authored_regions(role):
                    shell.panel(name, canonical, outline, height=height, bevel=.035, back=rear, bulge=0.0)
                    names.append(name)
                shell.finish()
            except Exception:
                if shell.bm.is_valid:
                    shell.bm.free()
                raise
            clean_delivery_mesh(obj)
            result = export_object(obj, UPRIGHT.inverted(), SourceAttributes(surface, UPRIGHT))
            output[part["name"]].append(result)
            old_box = bounds(points)
            new_box = bounds([UPRIGHT @ Vector(p) for p in result["0"]])
            extent_delta = [((b[1] - b[0]) / (a[1] - a[0]) - 1.0) * 100
                            for a, b in zip(old_box, new_box)]
            if max(abs(v) for v in extent_delta) > 2.0:
                raise ValueError(f"Cygni proportion gate failed: {obj.name} {extent_delta}")
            reports[part["name"]].append({"source_triangles": len(raw["12"]) // 3,
                                          "triangles": len(result["12"]) // 3,
                                          "fitted_layers": names, "original_bounds": old_box,
                                          "candidate_bounds": new_box, "extent_change_percent": extent_delta})
            # Native Blender coordinates are Y-up. Flip UV V only for Blender
            # display; exported Godot arrays retain the exact source convention.
            for uv in obj.data.uv_layers.active.data:
                uv.uv.y = 1.0 - uv.uv.y
            texture = "res://assets/armors/concept_runtime/textures/cygni_head.png" if role == 0 else refined["texture"]
            tint = [1, 1, 1, 1] if role == 0 else refined["parameters"]["albedo_tint"]
            paint = native_material(texture, tint, obj.name + "_paint")
            backing = native_material(texture, [c * .38 for c in tint[:3]] + [1], obj.name + "_backing")
            for i in range(len(obj.data.materials)):
                obj.data.materials[i] = backing if i in (6, 10) else paint
            for group in obj.vertex_groups:
                group.name = part["binds"][int(group.name)]["name"]
            modifier = obj.modifiers.new("Original rig", "ARMATURE")
            modifier.object = rig
            obj.parent = rig
            for previous in list(obj.users_collection):
                previous.objects.unlink(obj)
            collection.objects.link(obj)
    ASSET.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "painted_meshes.json").write_text(json.dumps(output, separators=(",", ":")))
    fingerprints = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in [Path(__file__), ROOT / "tools/armor_facets/build_meshes.py",
                              ROOT / "tools/armor_rework/thunder_body.py", ROOT / "test_output/armor_facets/sources.json",
                              ROOT / "assets/armors/concept_runtime/textures/cygni_head.png"]}
    report = {"id": 11, "revision": REVISION, "status": "style_trial_pending_visual_review",
              "source_fingerprints": fingerprints, "parts": reports,
              "coordinates": "original game Y-up, -Z forward",
              "inferred": ["Shallow projected plate outlines and layer thickness", "Helmet back retains original source geometry"],
              "retained": "Original skeleton, joints, UV seams, gloves, fin silhouettes and all body texture atlases"}
    (WORK / "painted_build.json").write_text(json.dumps(report, indent=2) + "\n")
    (ASSET / "asset-manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET / "master.blend"))
    print("CYGNI_PAINTED_BUILD_PASS proportions_within_2_percent=true", flush=True)


if __name__ == "__main__":
    main()
