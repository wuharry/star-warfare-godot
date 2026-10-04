"""Compare the current packed master to the immutable pre-paint master.

Run in Blender background mode. This reads both files, writes one JSON report,
and never saves or mutates either master or an image. It verifies the zero-new-
geometry/UV contract for this texture-only pass, independently of the inherited
15% comparison to the original game armor.
"""
import hashlib
import json
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/tank_runtime_v1"
BEFORE = WORK / "revisions/before_style_unification_v2/delivery"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(path: Path) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    meshes = {}
    bones = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            mesh = obj.data
            meshes[obj.name] = {
                "transform": [list(row) for row in obj.matrix_world],
                "positions": [list(vertex.co) for vertex in mesh.vertices],
                "polygons": [{"vertices": list(face.vertices), "material": face.material_index}
                             for face in mesh.polygons],
                "material_count": len(mesh.materials),
                "uv_layers": {layer.name: [list(loop.uv) for loop in layer.data]
                              for layer in mesh.uv_layers},
                "vertex_groups": [group.name for group in obj.vertex_groups],
                "weights": [[(group.group, group.weight) for group in vertex.groups]
                            for vertex in mesh.vertices],
                "parent": obj.parent.name if obj.parent else None,
                "armature_modifiers": [(modifier.name, modifier.object.name)
                                       for modifier in obj.modifiers if modifier.type == "ARMATURE"],
            }
        if obj.type == "ARMATURE":
            bones[obj.name] = {
                "transform": [list(row) for row in obj.matrix_world],
                "bones": [{"name": bone.name,
                           "parent": bone.parent.name if bone.parent else None,
                           "rest": [list(row) for row in bone.matrix_local],
                           "head": list(bone.head_local), "tail": list(bone.tail_local),
                           "deform": bone.use_deform} for bone in obj.data.bones],
            }
    return {"meshes": meshes, "rigs": bones}


def main() -> None:
    old_master = BEFORE / "tank_master.blend"
    new_master = WORK / "build/tank_master.blend"
    original = snapshot(old_master)
    current = snapshot(new_master)
    errors = []
    for category in ("meshes", "rigs"):
        if original[category] != current[category]:
            errors.append(f"Packed master {category} differs from pre-paint baseline")
    for filename in ("target.json", "geometry.json"):
        if (BEFORE / filename).read_bytes() != (WORK / "build" / filename).read_bytes():
            errors.append(f"Authored {filename} changed")
    before_manifest = json.loads((BEFORE.parent / "snapshot.json").read_text(encoding="utf-8"))
    source = WORK / "build/source.json"
    if sha(source) != before_manifest["files"]["delivery/source.json"]["sha256"]:
        errors.append("Original source positions/UV/indices/weights/bones snapshot changed")
    scene_report = json.loads((WORK / "review/style_pass_scene_invariants.json").read_text(encoding="utf-8"))
    if scene_report["status"] != "PASS": errors.append("Actual SCN paint-only invariants failed")
    if scene_report["current_scene_sha256"] != sha(ROOT / "assets/armors/tank_v1/tank.scn"): errors.append("Stale actual SCN invariant report")
    if scene_report["before_scene_sha256"] != sha(BEFORE / "tank.scn"): errors.append("Changed frozen SCN baseline")
    report = {
        "status": "PASS" if not errors else "FAIL", "errors": errors,
        "scope": "Exact packed-master vertex positions, UV loop values, polygon indices/materials, weights, rest rig and object transforms against immutable pre-paint master; source and authored target/geometry bytes unchanged. Does not certify artistic likeness or an engine capture.",
        "before_scene_sha256": scene_report["before_scene_sha256"], "current_scene_sha256": scene_report["current_scene_sha256"],
        "before_target_sha256": sha(BEFORE / "target.json"),
        "scene_invariants": "review/style_pass_scene_invariants.json", "scene_invariants_sha256": sha(WORK / "review/style_pass_scene_invariants.json"),
        "scene_records": scene_report["records"], "material_parameters_preserved": scene_report["material_parameters_preserved"],
        "baseline_snapshot_sha256": sha(BEFORE.parent / "snapshot.json"),
        "baseline_master": old_master.relative_to(ROOT).as_posix(),
        "baseline_master_sha256": sha(old_master), "master_sha256": sha(new_master),
        "source_sha256": sha(source), "target_sha256": sha(WORK / "build/target.json"),
        "geometry_sha256": sha(WORK / "build/geometry.json"),
        "additional_vertex_position_changes": 0 if not errors else None,
        "additional_uv_changes": 0 if not errors else None,
        "packed_meshes": len(current["meshes"]), "packed_rigs": len(current["rigs"]),
    }
    (WORK / "review/style_pass_invariants.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("TANK_STYLE_INVARIANTS_" + report["status"] + " errors=" + str(len(errors)))
    assert not errors, errors


if __name__ == "__main__":
    main()
