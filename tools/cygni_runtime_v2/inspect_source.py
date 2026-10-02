"""Read the raw game rig in Blender; no geometry changes."""
import bpy
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
source = ROOT / "assets/models/player/animated/player.gltf"
data = json.loads(source.read_text())
# Blender 5.1 cannot import this display-only extension. Remove it from an
# analysis copy, leaving original mesh, bind data and files untouched.
for key in ["extensionsUsed", "extensionsRequired"]:
    data[key] = [x for x in data.get(key, []) if x != "KHR_node_visibility"]
for node in data["nodes"]:
    node.get("extensions", {}).pop("KHR_node_visibility", None)
for item in data["buffers"] + data["images"]:
    item["uri"] = str((source.parent / item["uri"]).resolve())
compatible = ROOT / "test_output/cygni_runtime_v2/source_blender.gltf"
compatible.parent.mkdir(parents=True, exist_ok=True)
ignore = compatible.parent / ".gdignore"
if not ignore.exists():
    ignore.write_text("# Authoring diagnostics are not runtime resources.\n")
compatible.write_text(json.dumps(data))
bpy.ops.import_scene.gltf(filepath=str(compatible))
records = {}
for ob in bpy.data.objects:
    if ob.type == "MESH" and ob.name in ["ArmorHead_11", "ArmorBody_11", "ArmorHand_11", "ArmorFoot_11"]:
        pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
        records[ob.name] = {"min": [min(p[i] for p in pts) for i in range(3)], "max": [max(p[i] for p in pts) for i in range(3)], "matrix": [list(row) for row in ob.matrix_world], "materials": [m.name for m in ob.data.materials], "groups": [g.name for g in ob.vertex_groups], "verts": len(pts)}
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
records["rig"] = {"name": rig.name, "matrix": [list(row) for row in rig.matrix_world], "bones": [{"name":b.name,"head":list(rig.matrix_world @ b.head_local),"tail":list(rig.matrix_world @ b.tail_local), "matrix": [list(row) for row in rig.matrix_world @ b.matrix_local]} for b in rig.data.bones]}
(ROOT / "test_output/cygni_runtime_v2/source_rig.json").write_text(json.dumps(records,indent=2))
print("CYGNI_SOURCE_INSPECT_PASS")
