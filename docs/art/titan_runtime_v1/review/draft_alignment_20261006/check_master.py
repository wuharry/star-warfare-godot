"""Read the saved review master; verify rig, meshes, UVs and packed native PNGs."""
import hashlib
import json
from pathlib import Path
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
WORK = OUT.parent.parent
ROOT = WORK.parent.parent.parent
read = lambda path: json.loads(path.read_text(encoding="utf-8-sig"))
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert Path(bpy.data.filepath).resolve() == (OUT / "candidate_master.blend").resolve()
config = read(WORK / "runtime_config.json")
source = read(WORK / "build/source.json")
target = read(OUT / "candidate_target.json")
rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
assert len(rigs) == 1 and len(rigs[0].data.bones) == 28
assert {bone.name for bone in rigs[0].data.bones} == {row["name"] for row in source["bones"]}
records = {}
for name, part in target["parts"].items():
    obj = bpy.data.objects[name]
    assert obj.parent == rigs[0] and any(m.type == "ARMATURE" and m.object == rigs[0] for m in obj.modifiers)
    offset = 0
    indices, uvs = [], []
    for sid, row in enumerate(part["surfaces"]):
        original = source["parts"][name]["surfaces"][sid]
        ids = row.get("indices", original["indices"])
        indices.extend(tuple(offset+i for i in reversed(ids[start:start+3])) for start in range(0, len(ids), 3))
        for vertex, p in zip(obj.data.vertices[offset:], row["positions"]):
            assert (vertex.co-Vector((-p[0], p[2], p[1]))).length < 1e-6
        label = config["parts"][name][sid]
        images = [node.image for node in obj.data.materials[sid].node_tree.nodes if node.type == "TEX_IMAGE"]
        assert len(images) == 1 and images[0].packed_file
        expected = sha(ROOT / config["asset"] / config["texture_files"][label])
        assert hashlib.sha256(bytes(images[0].packed_file.data)).hexdigest() == expected
        uvs.extend(row["uv"])
        offset += len(row["positions"])
    assert len(obj.data.vertices) == offset
    assert [tuple(face.vertices) for face in obj.data.polygons] == indices
    for loop, uv in zip(obj.data.loops, obj.data.uv_layers.active.data):
        point = uvs[loop.vertex_index]
        assert abs(uv.uv.x-point[0]) < 1e-6 and abs(1-uv.uv.y-point[1]) < 1e-6
    records[name] = {"vertices": offset, "triangles": len(indices)}
report = {"status": "PASS", "scope": "Stored candidate master matches the review target, original rig names and five packed canonical PNGs; SCN skin weights are independently checked by candidate_scene_test.json.", "candidate_master_sha256": sha(OUT / "candidate_master.blend"), "candidate_target_sha256": sha(OUT / "candidate_target.json"), "bones": 28, "parts": records}
(OUT / "candidate_master_test.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
print("TITAN_ALIGNMENT_MASTER_PASS rig / target / UVs / five packed PNGs")
