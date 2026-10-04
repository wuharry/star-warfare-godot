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
BEFORE = WORK / "revisions/before_helmet_refinement_v3/delivery"


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
    if original['rigs']!=current['rigs']:errors.append('Rest rig changed')
    changed=0
    for name,old in original['meshes'].items():
        new=current['meshes'][name]
        for key,value in old.items():
            if name=='ArmorHead_02' and key=='positions':
                # Surface1 neck is already independently exact in the scene and
                # target; packed vertices retain source concatenation order.
                count=len(json.loads((WORK/'build/source.json').read_text())['parts'][name]['surfaces'][0]['positions'])
                changed=sum(a!=b for a,b in zip(value[:count],new[key][:count]))
                if value[count:]!=new[key][count:]:errors.append('Packed shared neck changed')
                continue
            if value!=new[key]:errors.append(f'Packed {name}/{key} changed')
    original_source=json.loads((WORK/'build/source.json').read_text())
    old_target=json.loads((BEFORE/'target.json').read_text())
    new_target=json.loads((WORK/'build/target.json').read_text())
    maximum=0.0;dimensions=[];head_count=0
    for name,part in new_target['parts'].items():
        old_part=old_target['parts'][name]; source_part=original_source['parts'][name]
        for sid,row in enumerate(part['surfaces']):
            if row['uv']!=old_part['surfaces'][sid]['uv']:errors.append('Authored UV changed '+name)
            if name!='ArmorHead_02' or sid!=0:
                if row!=old_part['surfaces'][sid]:errors.append('Untouched part/neck changed '+name)
        if name!='ArmorHead_02':continue
        before=[p for row in source_part['surfaces'] for p in row['positions']]
        after=[p for row in part['surfaces'] for p in row['positions']]
        sizes=[max(p[i] for p in before)-min(p[i] for p in before) for i in range(3)]
        dimensions=[abs((max(p[i] for p in after)-min(p[i] for p in after))/sizes[i]-1) for i in range(3)]
        maximum=max(sum((a[i]-b[i])**2 for i in range(3))**.5 for a,b in zip(before,after))/min(sizes)
        if maximum>.200001 or max(dimensions)>.200001:errors.append('True original-total head20% budget exceeded')
    if changed<=0:errors.append('No packed head changes')
    before_manifest = json.loads((BEFORE.parent / "snapshot.json").read_text(encoding="utf-8"))
    source = WORK / "build/source.json"
    if sha(source) != before_manifest["files"]["delivery/source.json"]["sha256"]:
        errors.append("Original source positions/UV/indices/weights/bones snapshot changed")
    scene_report = json.loads((WORK / "review/helmet_refinement_scene_invariants.json").read_text(encoding="utf-8"))
    if scene_report["status"] != "PASS": errors.append("Actual SCN helmet refinement invariants failed")
    if scene_report["current_scene_sha256"] != sha(ROOT / "assets/armors/tank_v1/tank.scn"): errors.append("Stale actual SCN invariant report")
    if scene_report["before_scene_sha256"] != sha(BEFORE / "tank.scn"): errors.append("Changed frozen SCN baseline")
    report = {
        "status": "PASS" if not errors else "FAIL", "errors": errors,
        "scope": "Head surface0 geometry refinement against frozen stylev2: exact UV loops, polygons/materials, weights, rest rig/transforms; only head surface0 positions/normals allowed. True original-total20 percent independently measured. Art likeness awaits user review.",
        "before_scene_sha256": scene_report["before_scene_sha256"], "current_scene_sha256": scene_report["current_scene_sha256"],
        "before_target_sha256": sha(BEFORE / "target.json"),
        "scene_invariants": "review/helmet_refinement_scene_invariants.json", "scene_invariants_sha256": sha(WORK / "review/helmet_refinement_scene_invariants.json"),
        "scene_records": scene_report["records"], "material_parameters_preserved": scene_report["material_parameters_preserved"],
        "baseline_snapshot_sha256": sha(BEFORE.parent / "snapshot.json"),
        "baseline_master": old_master.relative_to(ROOT).as_posix(),
        "baseline_master_sha256": sha(old_master), "master_sha256": sha(new_master),
        "source_sha256": sha(source), "target_sha256": sha(WORK / "build/target.json"),
        "geometry_sha256": sha(WORK / "build/geometry.json"),
        "additional_vertex_position_changes": changed if not errors else None,
        "additional_uv_changes": 0 if not errors else None,
        "positions_changed_parts":["ArmorHead_02"], "allowed_geometry_scope":"ArmorHead_02 surface 0 positions and normals only",
        "original_total_limit":.20,"original_max_rest_displacement_fraction":maximum,"original_dimension_delta_fraction":dimensions,
        "packed_meshes": len(current["meshes"]), "packed_rigs": len(current["rigs"]),
    }
    (WORK / "review/helmet_refinement_invariants.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("TANK_HELMET_INVARIANTS_" + report["status"] + " errors=" + str(len(errors)))
    assert not errors, errors


if __name__ == "__main__":
    main()
