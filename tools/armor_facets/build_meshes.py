"""Fit solid chamfered armor panels to the accepted meshes in Blender.

Run export.gd first, then Blender --background --python this_file -- --ids=0,9.
The proven Thunder clipping code retains UV islands and interpolates skinning.
No texture pixels, skeletons, socket positions or Thunder assets are changed.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "test_output/armor_facets"
sys.path.insert(0, str(ROOT / "tools/armor_rework"))
from thunder_body import _Shells  # noqa: E402: shared, tested UV/skin clipping

# SW1's refined scenes retain their original rotated mesh coordinates; Viper
# and the retargeted CoM parts are already in the upright player bind pose.
UPRIGHT = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
SOFT_SETS = {22, 23, 26, 28}
SPIKED_SETS = {10, 11, 14, 16, 20, 27}
HEAVY_SETS = {2, 5, 9, 13, 17, 18, 24, 25}


class FittedShells(_Shells):
    """Deduplicate T-junction vertices on already-beveled source meshes."""

    def face(self, vertices, uvs, material):
        pairs = []
        seen = set()
        for vertex, uv in zip(vertices, uvs):
            if vertex not in seen:
                seen.add(vertex)
                pairs.append((vertex, uv))
        if len(pairs) < 3:
            raise ValueError(f"Collapsed fitted polygon in {self.obj.name}")
        vertices = tuple(v for v, _ in pairs)
        existing = self.bm.faces.get(vertices)
        if existing is not None:
            return existing
        return super().face(vertices, tuple(uv for _, uv in pairs), material)


class SourceAttributes:
    """Interpolate original corner normals and baked AO on clipped source faces."""

    def __init__(self, surface: dict, rotation: Matrix):
        arrays = surface["arrays"]
        self.points = [rotation @ Vector(v) for v in arrays["0"]]
        self.normals = [rotation @ Vector(v) for v in arrays["1"]]
        ids = arrays.get("12") or list(range(len(self.points)))
        self.faces = []
        for i in range(0, len(ids), 3):
            a, b, c = ids[i:i + 3]
            if (self.points[b] - self.points[a]).cross(self.points[c] - self.points[a]).length_squared > 1e-20:
                self.faces.append([a, b, c])
        self.tree = BVHTree.FromPolygons(self.points, self.faces, all_triangles=True)
        use_color = surface.get("parameters", {}).get("vertex_color_use_as_albedo", False)
        self.colors = [Vector(c[:3]) for c in arrays["3"]] if use_color and arrays.get("3") else None
        self.exact: dict[tuple, list[int]] = {}
        for i, (point, uv) in enumerate(zip(self.points, arrays["4"])):
            self.exact.setdefault(self.key(point, uv), []).append(i)

    @staticmethod
    def key(point, uv) -> tuple:
        return tuple(round(float(v), 7) for v in (*point, *uv))

    def triangle(self, center: Vector) -> list[int]:
        _, _, index, _ = self.tree.find_nearest(center)
        if index is None:
            raise ValueError("Cannot project source attributes")
        return self.faces[index]

    def interpolate(self, point: Vector, face: list[int], values: list[Vector]) -> Vector:
        a, b, c = face
        return barycentric_transform(point, self.points[a], self.points[b], self.points[c], values[a], values[b], values[c])


def mirror(points: list[tuple[float, float]], side: int) -> list[tuple[float, float]]:
    return [(x * side, y) for x, y in points]


def panels(role: int, set_id: int) -> list[tuple[str, list, float, bool, float]]:
    """Authored regions avoid visor, fingers, elbows, abdomen and inner thighs."""
    result = []
    for side in (-1, 1):
        if role == 1:
            shapes = [
                ("breastplate", [(.014, 1.24), (.095, 1.27), (.215, 1.24), (.227, 1.16), (.115, 1.13), (.015, 1.16)], .030, False, .009),
                ("lower chest", [(.018, 1.117), (.111, 1.137), (.159, 1.084), (.135, 1.025), (.018, .995)], .024, False, .008),
                ("outer thigh", [(.182, .799), (.255, .810), (.278, .7), (.26, .565), (.186, .57)], .017, False, .006),
                ("back plate", [(.024, 1.253), (.155, 1.268), (.215, 1.202), (.174, 1.075), (.028, 1.10)], .018, True, .006),
            ]
        elif role == 2:
            shapes = [
                ("shoulder crown", [(.293, 1.373), (.4, 1.371), (.506, 1.303), (.529, 1.264), (.432, 1.237), (.295, 1.278)], .032, False, .009),
                ("shoulder lower", [(.3, 1.226), (.429, 1.237), (.55, 1.158), (.526, 1.104), (.389, 1.089), (.304, 1.117)], .024, False, .008),
                ("shoulder rear", [(.3, 1.354), (.405, 1.35), (.523, 1.261), (.48, 1.19), (.302, 1.229)], .023, True, .006),
            ]
        elif role == 3:
            shapes = [
                ("forearm", [(.419, .866), (.54, .908), (.569, .834), (.55, .756), (.483, .75), (.442, .798)], .026, False, .011),
                ("wrist cuff", [(.473, .733), (.55, .738), (.56, .682), (.495, .65), (.468, .683)], .015, False, .005),
                ("forearm rear", [(.439, .853), (.546, .893), (.57, .823), (.54, .749), (.473, .758)], .015, True, .005),
            ]
        elif role == 4:
            shapes = [
                ("knee", [(.085, .419), (.127, .464), (.225, .455), (.261, .397), (.23, .349), (.12, .35)], .037, False, .007),
                ("shin", [(.087, .333), (.157, .358), (.24, .332), (.27, .252), (.232, .175), (.158, .151), (.091, .216)], .029, False, .014),
                ("calf", [(.104, .4), (.22, .405), (.259, .322), (.238, .18), (.115, .18), (.091, .299)], .018, True, .006),
                ("toe", [(.095, .099), (.227, .103), (.269, .051), (.25, .027), (.083, .027), (.068, .051)], .017, False, .006),
            ]
        else:
            # Separate crown cheeks retain the center groove, visor and vents.
            # Spiked helmets only get rear support panels; their authored fins
            # and crests must not be clipped by a generic crown outline.
            shapes = [
                ("rear helmet", [(.022, 1.79), (.15, 1.79), (.228, 1.699), (.217, 1.53), (.042, 1.51)], .014, True, .004),
            ]
            if set_id not in SPIKED_SETS | {21, 26, 28}:
                shapes.append(("crown side", [(.03, 1.80), (.125, 1.849), (.203, 1.793), (.22, 1.726), (.112, 1.714), (.033, 1.739)], .018, False, .005))
        for name, outline, height, rear, crest in shapes:
            strength = 1.12 if set_id in HEAVY_SETS else (.78 if set_id in SOFT_SETS else 1.0)
            if set_id in SPIKED_SETS and role == 2:
                strength *= .72
            result.append((f"{side} {name}", mirror(outline, side), height * strength, rear, crest * strength))
    return result


def build_object(surface: dict, name: str, upright: Matrix, role: int) -> bpy.types.Object:
    arrays = surface["arrays"]
    vertices = [upright @ Vector(v) for v in arrays["0"]]
    indices = arrays.get("12") or list(range(len(vertices)))
    faces = [list(reversed(indices[i:i + 3])) for i in range(0, len(indices), 3)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # The reusable shell builder uses canonical material roles internally.
    for i in range(11):
        mesh.materials.append(bpy.data.materials.get(f"role_{i}") or bpy.data.materials.new(f"role_{i}"))
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        polygon.material_index = role
        polygon.use_smooth = True
        for li in polygon.loop_indices:
            uv_layer.data[li].uv = arrays["4"][mesh.loops[li].vertex_index]
    bone_count = max(arrays["10"]) + 1
    for bone in range(bone_count):
        obj.vertex_groups.new(name=str(bone))
    for vi in range(len(vertices)):
        for k in range(4):
            w = arrays["11"][vi * 4 + k]
            if w > 0:
                obj.vertex_groups[arrays["10"][vi * 4 + k]].add([vi], w, "REPLACE")
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-7)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


def export_object(obj: bpy.types.Object, inverse: Matrix, source: SourceAttributes) -> dict:
    mesh = obj.data
    mesh.calc_loop_triangles()
    normals = mesh.corner_normals
    result: dict[str, list] = {k: [] for k in ("0", "1", "3", "4", "10", "11", "12")}
    for tri in mesh.loop_triangles:
        # Omit only degeneracies introduced by clipping exactly at a boundary.
        if tri.area < 1e-12:
            continue
        source_face = source.triangle(sum((mesh.vertices[i].co for i in tri.vertices), Vector()) / 3.0)
        is_original = mesh.polygons[tri.polygon_index].use_smooth
        a, b, c = (mesh.vertices[i].co for i in tri.vertices)
        geometric_normal = (b - a).cross(c - a).normalized()
        if geometric_normal.length_squared < .5:
            # Blender's polygon area can be nonzero for an individual collapsed
            # loop triangle. Such a triangle has no renderable oriented surface.
            continue
        for li in reversed(tri.loops):
            vertex = mesh.vertices[mesh.loops[li].vertex_index]
            weights = sorted(((g.group, g.weight) for g in vertex.groups if g.weight > 0), key=lambda v: -v[1])[:4]
            total = sum(w for _, w in weights)
            if total <= 0:
                raise ValueError(f"Unbound generated vertex in {obj.name}")
            result["0"].append(list(inverse @ vertex.co))
            normal = source.interpolate(vertex.co, source_face, source.normals) if is_original else normals[li].vector
            uv = mesh.uv_layers.active.data[li].uv
            matches = source.exact.get(source.key(vertex.co, uv), []) if is_original else []
            exact = min(matches, key=lambda i: (source.normals[i] - normal).length_squared) if matches else None
            if exact is not None:
                normal = source.normals[exact]
            if normal.length_squared < 1e-10:
                normal = geometric_normal
            result["1"].append(list((inverse @ normal).normalized()))
            result["4"].append(list(uv))
            shade = .38 if tri.material_index in (6, 10) else 1.0
            color = source.interpolate(vertex.co, source_face, source.colors) if source.colors else Vector((1, 1, 1))
            if exact is not None and source.colors:
                color = source.colors[exact]
            result["3"].append([max(0.0, min(1.0, c)) * shade for c in color] + [1.0])
            result["10"].extend([g for g, _ in weights] + [0] * (4 - len(weights)))
            result["11"].extend([w / total for _, w in weights] + [0.0] * (4 - len(weights)))
    result["12"] = list(range(len(result["0"])))
    return result


def role_for(name: str, material: str, points: list[Vector]) -> int:
    if "Head" in name:
        return 0
    if "Hand" in name:
        return 3
    if "Foot" in name:
        return 4
    shoulder_only = min(abs(p.x) for p in points) > .24 and min(p.y for p in points) > .85
    return 2 if shoulder_only or any(k in material.lower() for k in ("jian", "shoulder", "shou_")) else 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ids", default="")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    selected = {int(x) for x in args.ids.split(",") if x} or set(range(29)) - {6}
    data = json.loads((WORK / "sources.json").read_text())
    output_path = WORK / "meshes.json"
    output: dict[str, Any] = json.loads(output_path.read_text()) if output_path.exists() else {}
    report_path = WORK / "geometry_report.json"
    reports = json.loads(report_path.read_text()) if report_path.exists() else {}
    state_path = WORK / "build_state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    fingerprints = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in (Path(__file__), ROOT / "tools/armor_rework/thunder_body.py", WORK / "sources.json")}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for entry in data["entries"]:
        set_id = entry["id"]
        if set_id not in selected or set_id == 6:
            continue
        rotation = UPRIGHT if 1 <= set_id <= 20 else Matrix.Identity(3)
        for part in entry["parts"]:
            surfaces, report = [], []
            for sid, surface in enumerate(part["surfaces"]):
                surface = copy.deepcopy(surface)
                if "raw_surfaces" in part:
                    raw = copy.deepcopy(part["raw_surfaces"][sid]["arrays"])
                    # Use the pre-bevel topology: bevel microfaces are not
                    # independent plate regions. Keep accepted paint/material.
                    bind_map = {b["name"]: b["index"] for b in part["binds"]}
                    raw["10"] = [bind_map[part["raw_binds"][int(index)]["name"]] for index in raw["10"]]
                    if set_id == 0:
                        for key in ("0", "1"):
                            raw[key] = [list(UPRIGHT @ Vector(v)) for v in raw[key]]
                    surface["arrays"] = raw
                arrays = surface["arrays"]
                points = [rotation @ Vector(v) for v in arrays["0"]]
                role = role_for(part["name"], surface["material"], points)
                # Preserve inner cloth, neck insert and effect surfaces. Their
                # paint/alpha and animation must not turn into armored slabs.
                skip = "role_001" in surface["material"] or (set_id == 21 and sid in (2, 3))
                if skip:
                    surfaces.append(arrays)
                    report.append({"surface": sid, "panels": [], "reason": "retained inner/trim surface"})
                    continue
                canonical_role = max(role, 1)
                obj = build_object(surface, part["name"], rotation, canonical_role)
                shells = FittedShells(obj, {"blend_source_boundaries": False, "flatten": .30,
                                           "outer_surface_only": True, "max_lift": .042})
                names = []
                try:
                    authored = panels(role, set_id)
                    # CoM suits share one atlas/surface across torso and shoulders.
                    if set_id >= 22 and role == 1 and any(abs(p.x) > .40 and p.y > 1.05 for p in points):
                        authored += panels(2, set_id)
                    for name, outline, height, rear, crest in authored:
                        try:
                            shells.panel(name, canonical_role, outline, height=height, bevel=.085, back=rear, bulge=crest)
                        except ValueError as error:
                            if "panel has no fitted surface" not in str(error):
                                raise
                            continue
                        names.append(name)
                    shells.finish()
                except Exception:
                    if shells.bm.is_valid:
                        shells.bm.free()
                    raise
                result = export_object(obj, rotation.inverted(), SourceAttributes(surface, rotation)) if names else arrays
                surfaces.append(result)
                report.append({"surface": sid, "panels": names, "source_triangles": len(arrays.get("12") or arrays["0"]) // 3, "triangles": len(result.get("12") or result["0"]) // 3})
                bpy.data.objects.remove(obj, do_unlink=True)
            output[part["name"]] = surfaces
            reports[part["name"]] = report
            state[part["name"]] = fingerprints
        print(f"ANGULAR_MESH_BUILT {set_id:02d} {entry['name']}", flush=True)
    WORK.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, separators=(",", ":")))
    report_path.write_text(json.dumps(reports, indent=2) + "\n")
    state_path.write_text(json.dumps(state, indent=2) + "\n")
    print("ANGULAR_GEOMETRY_PASS", len(output), "parts", "source", hashlib.sha256((WORK / "sources.json").read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
