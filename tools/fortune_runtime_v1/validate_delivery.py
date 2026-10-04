"""Read-only validation of the delivered, packed Fortune Blender master.

Run with the project Blender, opening the existing master before this script:
  blender --background docs/art/fortune_runtime_v1/build/fortune_master.blend \
    --python-exit-code 1 --python tools/fortune_runtime_v1/validate_delivery.py

Only review/delivery_validate.json is written. No image, UV, mesh, rig or .blend
is modified or saved. Coordinate-count and displacement metrics are separate.
"""
import hashlib
import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/fortune_runtime_v1"
MASTER = WORK / "build/fortune_master.blend"
REPORT = WORK / "review/delivery_validate.json"
LABELS = {
    "ArmorHead_01": ["head"],
    "ArmorBody_01": ["body", "shoulder"],
    "ArmorHand_01": ["hand"],
    "ArmorFoot_01": ["foot"],
}
EPSILON = 0.000001
LOCAL_GEOMETRY_CHANGE_LIMIT = 0.15
UV_CHANGED_COORDINATE_LIMIT = 0.15


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def uv_chart_count(original_rows: list[dict], authored_rows: list[dict]) -> int:
    adjacency: dict[tuple[float, ...], set[tuple[float, ...]]] = {}
    for source_row, authored_row in zip(original_rows, authored_rows):
        keys = [tuple(round(value, 6) for value in uv) for uv in authored_row["uv"]]
        for start in range(0, len(source_row["indices"]), 3):
            triangle = [keys[index] for index in source_row["indices"][start:start + 3]]
            for key in triangle:
                adjacency.setdefault(key, set()).update(triangle)
    remaining = set(adjacency)
    count = 0
    while remaining:
        count += 1
        pending = [remaining.pop()]
        while pending:
            for neighbor in adjacency[pending.pop()]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    pending.append(neighbor)
    return count


def main() -> None:
    source = json.loads((WORK / "build/source.json").read_text(encoding="utf-8"))
    target = json.loads((WORK / "build/target.json").read_text(encoding="utf-8"))
    errors: list[str] = []

    def check(ok: bool, message: str) -> None:
        if not ok:
            errors.append(message)

    loaded_file = Path(bpy.data.filepath).resolve()
    check(loaded_file == MASTER.resolve(), "Loaded file is not the delivered Fortune master")
    meshes = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    check(set(meshes) == set(LABELS), "Expected exactly the four original modular meshes")
    check(len(rigs) == 1, "Expected one armature")
    expected_bones = {row["name"] for row in source["bones"]}
    if len(rigs) == 1:
        check(len(rigs[0].data.bones) == 28, "Expected 28 original bones")
        check({bone.name for bone in rigs[0].data.bones} == expected_bones,
              "Armature bone names differ from original")

    mesh_records: list[dict] = []
    image_records: dict[str, dict] = {}
    triangles = 0
    surfaces = 0
    total_uv_coordinates = 0
    total_changed_coordinates = 0
    for name, labels in LABELS.items():
        if name not in meshes:
            continue
        obj = meshes[name]
        mesh = obj.data
        original_rows = source["parts"][name]["surfaces"]
        authored_rows = target["parts"][name]["surfaces"]
        authored_uv = [uv for row in authored_rows for uv in row["uv"]]
        original_uv = [uv for row in original_rows for uv in row["uv"]]
        authored_positions = [point for row in authored_rows for point in row["positions"]]
        original_positions = [point for row in original_rows for point in row["positions"]]
        check(len(authored_uv) == len(original_uv), f"{name}: UV coordinate count changed")
        check(len(mesh.vertices) == len(authored_uv), f"{name}: master vertex count differs from authored UV count")
        check(len(mesh.materials) == len(labels), f"{name}: material surface count changed")
        check(mesh.uv_layers.active is not None, f"{name}: missing UV layer")
        check(any(mod.type == "ARMATURE" and mod.object in rigs for mod in obj.modifiers),
              f"{name}: missing original-rig armature modifier")

        vertex_weights = []
        for row in original_rows:
            for names, weights in zip(row["bone_names"], row["weights"]):
                accumulated = {}
                for bone, weight in zip(names, weights):
                    if weight > 0:
                        accumulated[bone] = accumulated.get(bone, 0.0) + weight
                vertex_weights.append(accumulated)
        maximum_weight_error = 0.0
        for vertex in mesh.vertices:
            if vertex.index >= len(vertex_weights):
                continue
            expected = vertex_weights[vertex.index]
            actual = {obj.vertex_groups[group.group].name: group.weight for group in vertex.groups if group.weight > 0}
            check(set(actual) == set(expected), f"{name}/{vertex.index}: original weighted bones changed")
            maximum_weight_error = max(maximum_weight_error, max([abs(actual.get(key, 0.0) - value) for key, value in expected.items()] or [0.0]))
        check(maximum_weight_error <= EPSILON, f"{name}: original weights changed in master")

        expected_faces: list[tuple[int, ...]] = []
        vertex_offset = 0
        for row in original_rows:
            for index in range(0, len(row["indices"]), 3):
                expected_faces.append(tuple(vertex_offset + item for item in reversed(row["indices"][index:index + 3])))
            vertex_offset += len(row["uv"])
        actual_faces = [tuple(poly.vertices) for poly in mesh.polygons]
        check(actual_faces == expected_faces, f"{name}: original triangle indices or winding changed")
        count = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
        triangles += count
        surfaces += len(mesh.materials)

        max_uv_error = 0.0
        if mesh.uv_layers.active is not None:
            layer = mesh.uv_layers.active.data
            for loop_index, loop in enumerate(mesh.loops):
                index = loop.vertex_index
                if index >= len(authored_uv):
                    continue
                expected = authored_uv[index]
                actual = layer[loop_index].uv
                error = math.hypot(actual.x - expected[0], 1.0 - actual.y - expected[1])
                max_uv_error = max(max_uv_error, error)
            check(max_uv_error <= EPSILON, f"{name}: packed master UV differs from authored UV")

        max_position_error = 0.0
        for vertex in mesh.vertices:
            if vertex.index >= len(authored_positions):
                continue
            x, y, z = authored_positions[vertex.index]
            # Same Godot-to-Blender conversion used by build.py: (-x,z,y).
            max_position_error = max(max_position_error, (vertex.co - Vector((-x, z, y))).length)
        check(max_position_error <= EPSILON, f"{name}: packed master position differs from authored cage")
        actual_positions = [(-vertex.co.x, vertex.co.z, vertex.co.y) for vertex in mesh.vertices]
        check(len(actual_positions) == len(original_positions), f"{name}: original vertex count changed")
        original_size = [max(point[axis] for point in original_positions) - min(point[axis] for point in original_positions)
                         for axis in range(3)]
        actual_size = [max(point[axis] for point in actual_positions) - min(point[axis] for point in actual_positions)
                       for axis in range(3)]
        dimension_delta = [abs(new / old - 1.0) for old, new in zip(original_size, actual_size)]
        max_rest_displacement = max(math.dist(old, new) for old, new in zip(original_positions, actual_positions))
        displacement_fraction = max_rest_displacement / min(original_size)
        check(max(dimension_delta) <= LOCAL_GEOMETRY_CHANGE_LIMIT, f"{name}: dimensions exceed15% of original")
        check(displacement_fraction <= LOCAL_GEOMETRY_CHANGE_LIMIT, f"{name}: rest displacement exceeds15% of original smallest dimension")

        uv_displacements = [math.dist(a, b) for a, b in zip(original_uv, authored_uv)]
        changed = sum(distance > EPSILON for distance in uv_displacements)
        total_uv_coordinates += len(original_uv)
        total_changed_coordinates += changed
        original_chart_count = uv_chart_count(original_rows, original_rows)
        authored_chart_count = uv_chart_count(original_rows, authored_rows)
        check(authored_chart_count == original_chart_count, f"{name}: original UV chart count changed")
        surface_uv_records = []
        for surface, (old_row, new_row) in enumerate(zip(original_rows, authored_rows)):
            distances = [math.dist(a, b) for a, b in zip(old_row["uv"], new_row["uv"])]
            moved = sum(distance > EPSILON for distance in distances)
            check(moved / len(old_row["uv"]) <= UV_CHANGED_COORDINATE_LIMIT,
                  f"{labels[surface]}: changed UV coordinate count exceeds15% of material surface")
            surface_uv_records.append({
                "surface": surface, "label": labels[surface],
                "original_uv_coordinates": len(old_row["uv"]),
                "changed_uv_coordinates": moved,
                "changed_uv_coordinate_fraction": moved / len(old_row["uv"]),
                "maximum_uv_displacement_from_original": max(distances),
            })
        check(changed / len(original_uv) <= UV_CHANGED_COORDINATE_LIMIT, f"{name}: changed UV coordinate count exceeds15%")

        for surface, label in enumerate(labels):
            if surface >= len(mesh.materials):
                continue
            material = mesh.materials[surface]
            check(material is not None and material.node_tree is not None, f"{name}/{label}: missing texture material")
            if material is None or material.node_tree is None:
                continue
            images = [node.image for node in material.node_tree.nodes
                      if node.bl_idname == "ShaderNodeTexImage" and node.image is not None]
            check(len(images) == 1, f"{name}/{label}: expected one diffuse image")
            if len(images) != 1:
                continue
            image = images[0]
            canonical = ROOT / f"assets/armors/fortune_v1/{label}_diffuse.png"
            canonical_bytes = canonical.read_bytes()
            dimensions = list(struct.unpack(">II", canonical_bytes[16:24]))
            check(canonical_bytes[:8] == b"\x89PNG\r\n\x1a\n", f"{label}: canonical diffuse is not PNG")
            check(dimensions[0] == dimensions[1] and dimensions[0] >= 1024, f"{label}: diffuse must be a square game atlas >=1024 px")
            check(list(image.size) == dimensions, f"{label}: packed image dimensions changed")
            packed = image.packed_file
            check(packed is not None, f"{label}: master image is not packed")
            packed_sha = sha256(bytes(packed.data)) if packed is not None else None
            canonical_sha = sha256(canonical_bytes)
            check(packed_sha == canonical_sha, f"{label}: packed PNG bytes differ from canonical delivered diffuse")
            check(label not in image_records, f"{label}: material label is used more than once")
            image_records[label] = {
                "material": material.name,
                "image": image.name,
                "canonical_path": canonical.relative_to(ROOT).as_posix(),
                "dimensions": dimensions,
                "packed_bytes": len(packed.data) if packed is not None else 0,
                "packed_sha256": packed_sha,
                "canonical_sha256": canonical_sha,
                "byte_identical": packed_sha == canonical_sha,
            }
        mesh_records.append({
            "name": name, "vertices": len(mesh.vertices), "triangles": count,
            "surfaces": len(mesh.materials), "uv_loops": len(mesh.loops),
            "original_uv_coordinates": len(original_uv),
            "authored_uv_coordinates": len(authored_uv),
            "changed_uv_coordinates": changed,
            "changed_uv_coordinate_fraction": changed / len(original_uv),
            "maximum_uv_displacement_from_original": max(uv_displacements),
            "rms_uv_displacement_from_original": math.sqrt(sum(value * value for value in uv_displacements) / len(uv_displacements)),
            "maximum_master_uv_error_from_authored": max_uv_error,
            "maximum_weight_error": maximum_weight_error,
            "maximum_master_position_error_from_authored": max_position_error,
            "dimension_delta_fraction": dimension_delta,
            "max_rest_displacement": max_rest_displacement,
            "max_displacement_fraction_of_smallest_dimension": displacement_fraction,
            "original_uv_charts": original_chart_count,
            "authored_uv_charts": authored_chart_count,
            "uv_by_surface": surface_uv_records,
        })
    check(triangles == 720, "Expected original 720 triangles")
    check(surfaces == 5, "Expected five material surfaces")
    check(set(image_records) == {"head", "body", "shoulder", "hand", "foot"},
          "Expected all five canonical packed diffuse images")
    file_images = [image for image in bpy.data.images if image.source == "FILE"]
    check(len(file_images) == 5, "Expected exactly five file images in the master")

    report = {
        "status": "FAIL" if errors else "PASS",
        "scope": "Read-only packed-master identity, PNG bytes, original topology/rig, and authored UV/position consistency. Does not measure artistic likeness or certify fresh engine captures.",
        "master": MASTER.relative_to(ROOT).as_posix(),
        "master_sha256": sha256(MASTER.read_bytes()),
        "source_sha256": sha256((WORK / "build/source.json").read_bytes()),
        "target_sha256": sha256((WORK / "build/target.json").read_bytes()),
        "blender": bpy.app.version_string,
        "errors": errors,
        "mesh_count": len(meshes), "surface_count": surfaces,
        "bone_count": len(rigs[0].data.bones) if len(rigs) == 1 else None,
        "triangle_count": triangles, "packed_diffuse_count": len(image_records),
        "original_uv_coordinate_count": total_uv_coordinates,
        "changed_uv_coordinate_count": total_changed_coordinates,
        "changed_uv_coordinate_fraction": total_changed_coordinates / total_uv_coordinates,
        "uv_count_limit": UV_CHANGED_COORDINATE_LIMIT,
        "uv_count_scope": "per_material_surface",
        "local_geometry_change_limit": LOCAL_GEOMETRY_CHANGE_LIMIT,
        "uv_metric_note": "The 15% limit counts original coordinates changed independently per material surface. Coordinate/chart counts and topology remain unchanged; absolute atlas displacement is reported separately.",
        "meshes": mesh_records, "images": image_records,
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"FORTUNE_DELIVERY_VALIDATE_{report['status']} meshes={len(meshes)} surfaces={surfaces} bones={report['bone_count']} tris={triangles} packed={len(image_records)} errors={len(errors)}")
    if errors:
        raise RuntimeError("; ".join(errors))


if __name__ == "__main__":
    main()
