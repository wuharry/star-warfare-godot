"""Deform only the frozen current Thunder head; keep its UV/triangle stream."""
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from thunder_head_alignment import deform, measure_alignment

WORK = ROOT / "docs/art/thunder_head_alignment_v1"
BEFORE = WORK / "before/resources"
bpy.ops.wm.open_mainfile(filepath=str(BEFORE / "docs/art/armor_rework/thunder.blend"))
for image in bpy.data.images:
    normalized = image.filepath.replace("\\", "/")
    if "assets/" in normalized:
        image.filepath = str(ROOT / normalized[normalized.index("assets/"):])
head = bpy.data.objects["ArmorHead_06"]
old = [list(vertex.co) for vertex in head.data.vertices]
head.data.calc_loop_triangles()
triangles = [list(tri.vertices) for tri in head.data.loop_triangles]
old_normals = [list(normal.vector) for normal in head.data.corner_normals]
normal_groups = []
for loop in head.data.loops:
    normal_groups.append(tuple(round(v, 6) for v in old[loop.vertex_index])
                         + tuple(round(v, 4) for v in old_normals[loop.index]))
for vertex in head.data.vertices:
    vertex.co = deform(vertex.co)
measure = measure_alignment(old, [list(v.co) for v in head.data.vertices], triangles)
head.data.update()
head.data.calc_loop_triangles()
# Source smooth/hard borders are encoded in custom split normals. Rebuild
# those same groups from the changed faces instead of retaining stale lighting.
sums = {}
for tri in head.data.loop_triangles:
    a, b, c = [head.data.vertices[index].co for index in tri.vertices]
    area_normal = (b-a).cross(c-a)
    for loop in tri.loops:
        key = normal_groups[loop]
        sums[key] = sums.get(key, Vector()) + area_normal
head.data.normals_split_custom_set([
    sums[key].normalized() if sums[key].length_squared > 1e-20 else Vector(old_normals[index])
    for index, key in enumerate(normal_groups)
])
head.data.calc_tangents(uvmap=head.data.uv_layers.active.name)
native = ROOT / "assets/armors/thunder/textures/helmet_aligned_albedo.png"
assert native.is_file(), native
for slot in [11, 14]:
    mat = head.data.materials[slot].copy()
    head.data.materials[slot] = mat
    for node in mat.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image and "helmet_detail_albedo" in node.image.name:
            node.image = bpy.data.images.load(str(native), check_existing=True)
for slot, color in [(12, (.208, .373, .533, 1)), (13, (.32, .42, .52, 1))]:
    mat = head.data.materials[slot].copy()
    head.data.materials[slot] = mat
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = color
attrs = {"name": head.name, "positions": [], "normals": [], "tangents": [],
         "uv": [], "bones": [], "weights": [], "materials": []}
for tri in head.data.loop_triangles:
    attrs["materials"].append(tri.material_index)
    for loop in tri.loops:
        vertex = head.data.vertices[head.data.loops[loop].vertex_index]
        attrs["positions"].extend(vertex.co)
        attrs["normals"].extend(head.data.corner_normals[loop].vector.normalized())
        attrs["tangents"].extend(head.data.loops[loop].tangent)
        attrs["tangents"].append(head.data.loops[loop].bitangent_sign)
        attrs["uv"].extend(head.data.uv_layers.active.data[loop].uv)
        groups = sorted((g for g in vertex.groups if g.weight > 0), key=lambda g: g.weight, reverse=True)[:4]
        total = sum(g.weight for g in groups)
        attrs["bones"].append([head.vertex_groups[g.group].name for g in groups])
        attrs["weights"].append([g.weight / total for g in groups])
source = json.loads((BEFORE / "test_output/armor_rework/thunder_sw2_meshes.json").read_text())[0]
for key in ["uv", "bones", "weights", "materials"]:
    assert attrs[key] == source[key], f"Frozen Blender triangle stream changed: {key}"
output = ROOT / "test_output/armor_rework/thunder_aligned_head.json"
output.write_text(json.dumps(attrs, separators=(",", ":")), encoding="utf-8")
measure.update({"head_json_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                "native_albedo_sha256": hashlib.sha256(native.read_bytes()).hexdigest(),
                "head_triangles": len(attrs["materials"]), "uv_added": 0,
                "scope": "current approved Thunder A head only; body untouched"})
(WORK / "build_measure.json").write_text(json.dumps(measure, indent=2) + "\n", encoding="utf-8", newline="\n")
head["head_revision"] = "thunder_head_alignment_v1"
for image in bpy.data.images:
    if image.filepath and Path(image.filepath).is_absolute():
        image.filepath = "//../../../" + Path(image.filepath).relative_to(ROOT).as_posix()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "docs/art/armor_rework/thunder.blend"), compress=True)
print("THUNDER_HEAD_ALIGNMENT_BUILD_PASS", json.dumps(measure))
