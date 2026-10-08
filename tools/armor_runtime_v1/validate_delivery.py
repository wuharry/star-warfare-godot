"""Read-only validation of a Hydra, Strike or Titan packed Blender master.

Run Blender with the existing master and --python-exit-code 1:
  --python tools/armor_runtime_v1/validate_delivery.py -- --armor hydra
Only review/delivery_validate.json is written. No master or image is saved.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
EPSILON = 1e-6
C = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shared_validator(slug):
    path = ROOT / ("tools/armor_runtime_v1/first_integration_contract.py"
                   if slug in ["atom", "pegasus"] else "tools/armor_style_unification_v1/validate.py")
    spec = importlib.util.spec_from_file_location("armor_source_contract", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--armor", required=True, choices=["hydra", "strike", "titan", "atom", "pegasus"])
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    slug = args.armor
    validator = shared_validator(slug)
    source, frozen = validator.verify_first_source(slug)
    work = ROOT / f"docs/art/{slug}_runtime_v1"
    assets = ROOT / f"assets/armors/{slug}_v1"
    config = validator.read(work / "runtime_config.json")
    target = validator.read(work / "build/target.json")
    geometry = validator.read(work / "build/geometry.json")
    original_metrics = validator.measure_original_geometry(source, target, geometry, {name: .20 for name in source["parts"]})
    generated = validator.verify_first_generation(slug, work, assets)
    native_sha = {row["label"]: row["canonical_sha256"] for row in generated}
    master = work / f"build/{slug}_master.blend"
    errors = []

    def check(ok, message):
        if not ok:
            errors.append(message)

    check(Path(bpy.data.filepath).resolve() == master.resolve(), "Wrong loaded master")
    meshes = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    check(set(meshes) == set(config["parts"]), "Four original modular parts required")
    check(len(rigs) == 1, "One original 28-bone armature required")
    rig = rigs[0] if len(rigs) == 1 else None
    names = {bone["name"] for bone in source["bones"]}
    if rig:
        check({bone.name for bone in rig.data.bones} == names and len(rig.data.bones) == 28, "Original bone names/count changed")
        for original in source["bones"]:
            bone = rig.data.bones.get(original["name"])
            if bone is None:
                continue
            parent_name = source["bones"][original["parent"]]["name"] if original["parent"] >= 0 else None
            check((bone.parent.name if bone.parent else None) == parent_name, "Original bone parent changed: " + bone.name)
            rest = C @ Matrix(original["matrix"])
            check((bone.head_local - rest.translation).length <= EPSILON, "Original bone head changed: " + bone.name)
            check((bone.tail_local - (rest.translation + rest.to_3x3() @ Vector((0, .06, 0)))).length <= EPSILON,
                  "Original bone tail changed: " + bone.name)

    triangles = surfaces = coordinates = changed_coordinates = 0
    mesh_records, image_records = [], {}
    for name, labels in config["parts"].items():
        if name not in meshes:
            continue
        obj, originals, authored = meshes[name], source["parts"][name]["surfaces"], target["parts"][name]["surfaces"]
        mesh = obj.data
        positions = [point for row in authored for point in row["positions"]]
        original_positions = [point for row in originals for point in row["positions"]]
        uv = [point for row in authored for point in row["uv"]]
        original_uv = [point for row in originals for point in row["uv"]]
        check(len(mesh.vertices) == len(positions) == len(uv) == len(original_uv), name + ": original coordinate count changed")
        check(len(mesh.materials) == len(labels) == len(originals), name + ": original surface count changed")
        check(obj.parent == rig and any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers), name + ": original rig binding changed")
        check({group.name for group in obj.vertex_groups} == names, name + ": original weight group names changed")
        check(max(abs(obj.matrix_world[row][col] - int(row == col)) for row in range(4) for col in range(4)) <= EPSILON,
              name + ": unexpected object transform")
        expected_faces, expected_materials, offset = [], [], 0
        expected_weights = []
        for sid, original in enumerate(originals):
            for start in range(0, len(original["indices"]), 3):
                expected_faces.append(tuple(offset + index for index in reversed(original["indices"][start:start + 3])))
                expected_materials.append(sid)
            for bone_names, weights in zip(original["bone_names"], original["weights"]):
                grouped = {}
                for bone_name, weight in zip(bone_names, weights):
                    if weight > 0:
                        grouped[bone_name] = grouped.get(bone_name, 0) + weight
                expected_weights.append(grouped)
            offset += len(original["uv"])
        check([tuple(poly.vertices) for poly in mesh.polygons] == expected_faces, name + ": original indices/winding changed")
        check([poly.material_index for poly in mesh.polygons] == expected_materials, name + ": original triangle material assignment changed")
        max_position_error = max_weight_error = 0.0
        actual_positions = []
        for vertex in mesh.vertices:
            if vertex.index >= len(positions):
                continue
            x, y, z = positions[vertex.index]
            max_position_error = max(max_position_error, (vertex.co - Vector((-x, z, y))).length)
            actual_positions.append([-vertex.co.x, vertex.co.z, vertex.co.y])
            actual_weights = {obj.vertex_groups[group.group].name: group.weight for group in vertex.groups if group.weight > 0}
            original_weights = expected_weights[vertex.index]
            check(set(actual_weights) == set(original_weights), name + ": vertex weight bone assignment changed")
            max_weight_error = max(max_weight_error, max((abs(actual_weights.get(key, 0) - value) for key, value in original_weights.items()), default=0))
        check(max_position_error <= EPSILON, name + ": packed positions differ from target")
        check(max_weight_error <= EPSILON, name + ": original quantized weights changed/normalized")
        max_uv_error = 0.0
        check(mesh.uv_layers.active is not None, name + ": missing UV layer")
        if mesh.uv_layers.active:
            for index, loop in enumerate(mesh.loops):
                if loop.vertex_index >= len(uv):
                    continue
                expected, actual = uv[loop.vertex_index], mesh.uv_layers.active.data[index].uv
                max_uv_error = max(max_uv_error, math.hypot(actual.x - expected[0], 1 - actual.y - expected[1]))
        check(max_uv_error <= EPSILON, name + ": packed UV differs from target")
        original_size = [max(point[i] for point in original_positions) - min(point[i] for point in original_positions) for i in range(3)]
        if actual_positions:
            actual_size = [max(point[i] for point in actual_positions) - min(point[i] for point in actual_positions) for i in range(3)]
            delta = [abs(after / before - 1) for before, after in zip(original_size, actual_size)]
            displacement = max(math.dist(a, b) for a, b in zip(original_positions, actual_positions))
            check(max(delta) <= .20 and displacement / min(original_size) <= .20, name + ": packed geometry exceeds true original20%")
        surface_records = []
        for sid, (original, current) in enumerate(zip(originals, authored)):
            moved = sum(math.dist(a, b) > EPSILON for a, b in zip(original["uv"], current["uv"]))
            count = len(original["uv"])
            coordinates += count
            changed_coordinates += moved
            check(moved / count <= .20, name + ": UV coordinate changes exceed original20% per surface")
            surface_records.append({"surface": sid, "label": labels[sid], "original_uv_coordinates": count,
                                    "changed_uv_coordinates": moved, "changed_uv_coordinate_fraction": moved / count})
        for sid, label in enumerate(labels):
            if sid >= len(mesh.materials):
                continue
            material = mesh.materials[sid]
            nodes = [node.image for node in material.node_tree.nodes if node.bl_idname == "ShaderNodeTexImage" and node.image] if material and material.node_tree else []
            check(len(nodes) == 1, label + ": one canonical diffuse image required")
            if len(nodes) != 1:
                continue
            image = nodes[0]
            canonical = assets / f"{label}_diffuse.png"
            raw = canonical.read_bytes()
            check(raw[:8] == b"\x89PNG\r\n\x1a\n", label + ": native PNG required")
            dimensions = list(struct.unpack(">II", raw[16:24]))
            check(list(image.size) == dimensions and dimensions[0] == dimensions[1], label + ": packed native dimensions differ")
            packed_sha = hashlib.sha256(bytes(image.packed_file.data)).hexdigest() if image.packed_file else None
            check(packed_sha == digest(canonical) == native_sha[label], label + ": packed bytes differ from actual generated native PNG")
            image_records[label] = {"material": material.name, "image": image.name, "dimensions": dimensions,
                                   "canonical_sha256": digest(canonical), "packed_sha256": packed_sha,
                                   "byte_identical": packed_sha == digest(canonical)}
        count = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
        triangles += count
        surfaces += len(mesh.materials)
        mesh_records.append({"name": name, "vertices": len(mesh.vertices), "triangles": count, "surfaces": len(mesh.materials),
                             "maximum_master_position_error_from_authored": max_position_error,
                             "maximum_master_uv_error_from_authored": max_uv_error,
                             "maximum_original_weight_error": max_weight_error,
                             "original_topology_indices_material_assignments_verified": [tuple(poly.vertices) for poly in mesh.polygons] == expected_faces,
                             "uv_by_surface": surface_records})
    check(triangles == config["original_triangles"] and surfaces == 5 and coordinates == config["original_uv_coordinate_count"], "Original total topology/surface/coordinate count changed")
    check(set(image_records) == validator.LABELS and len([image for image in bpy.data.images if image.source == "FILE"]) == 5, "Exactly five canonical packed PNGs required")
    report = {"status": "FAIL" if errors else "PASS", "errors": errors,
              "scope": "Read-only first-integration packed master, true original indices/weights/rig and original-total20% geometry/UV. No artistic likeness score.",
              "master": master.relative_to(ROOT).as_posix(), "master_sha256": digest(master),
              "loaded_master": bpy.data.filepath,
              "source_sha256": digest(work / "build/source.json"), "target_sha256": digest(work / "build/target.json"),
              "geometry_sha256": digest(work / "build/geometry.json"), "blender": bpy.app.version_string,
              "original_source_snapshot_sha256": frozen["original_source_snapshot_sha256"], "original_node_ids": frozen["used_node_ids"],
              "mesh_count": len(meshes), "surface_count": surfaces, "bone_count": len(rig.data.bones) if rig else None,
              "actual_mesh_names": sorted(meshes), "expected_mesh_names": sorted(config["parts"]),
              "triangle_count": triangles, "packed_diffuse_count": len(image_records), "original_uv_coordinate_count": coordinates,
              "changed_uv_coordinate_count": changed_coordinates,
              "changed_uv_coordinate_fraction": changed_coordinates / coordinates if coordinates else None,
              "uv_count_limit": .20, "uv_count_scope": "per_material_surface", "local_geometry_change_limit": .20,
              "original_topology_indices_weights_rig_verified": not errors,
              "original_metrics": original_metrics, "meshes": mesh_records, "images": image_records}
    path = work / "review/delivery_validate.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{slug.upper()}_DELIVERY_VALIDATE_{report['status']} meshes={len(meshes)} surfaces={surfaces} bones={report['bone_count']} tris={triangles} packed={len(image_records)} errors={len(errors)}")
    if errors:
        raise RuntimeError("; ".join(errors))


if __name__ == "__main__":
    main()
