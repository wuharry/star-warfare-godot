"""Read-only checks for the current Titan helmet refinement and preserved parts.

python3 tools/armor_runtime_v1/validate_titan_helmet.py
Blender -b <titan_master.blend> --python-exit-code 1 --python <this file>
Historical first-integration hashes remain historical; no baseline is rewritten.
"""
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def inputs():
    config = read(WORK / "runtime_config.json")
    source = read(WORK / "build/source.json")
    target = read(WORK / "build/target.json")
    snapshot = read(ROOT / config["before_revision_snapshot"])
    for record in snapshot["files"]:
        assert digest(ROOT / record["snapshot"]) == record["sha256"], record["snapshot"]
    assert (WORK / "build/source.json").read_bytes() == (WORK / "revisions/original_source_v1/source.json").read_bytes()
    assert source == read(next(ROOT / row["snapshot"] for row in snapshot["files"] if row["path"].endswith("build/source.json")))
    scene_check = read(WORK / "review/original_scene_invariants.json")
    assert scene_check["status"] == "PASS"
    assert scene_check["current_scene_sha256"] == digest(ROOT / config["asset"] / "titan.scn")
    assert scene_check["target_sha256"] == digest(WORK / "build/target.json")
    generation = read(ROOT / config["generation_record"])
    assert generation["tool"] == "image_gen.imagegen"
    assert digest(ROOT / generation["prompt_path"]) == generation["prompt_sha256"]
    for ref in generation["references"]:
        assert digest(ROOT / ref.get("snapshot", ref["path"])) == ref["sha256"]
    head = ROOT / generation["canonical_path"]
    assert digest(head) == digest(ROOT / generation["archive_path"]) == generation["native_output_sha256"]
    native = Path(generation["native_output_path"])
    if native.exists():
        assert digest(native) == digest(head)
    textures = {label: ROOT / config["asset"] / filename for label, filename in config["texture_files"].items()}
    assert textures["head"] == head and len(textures) == 5
    for label, path in textures.items():
        if label != "head":
            prior = next(row for row in snapshot["files"] if ROOT / row["path"] == path)
            assert digest(path) == prior["sha256"], label + " was modified"
    for name, part in target["parts"].items():
        for authored, original in zip(part["surfaces"], source["parts"][name]["surfaces"]):
            assert authored["uv"] == original["uv"]
            if name != "ArmorHead_05":
                assert authored["positions"] == original["positions"]
    return config, source, target, textures


def verify_master(config, source, target, textures):
    import bpy
    from mathutils import Matrix, Vector
    master = WORK / "build/titan_master.blend"
    assert Path(bpy.data.filepath).resolve() == master.resolve()
    meshes = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    assert set(meshes) == set(config["parts"])
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    assert len(rigs) == 1
    rig = rigs[0]
    names = {bone["name"] for bone in source["bones"]}
    assert {bone.name for bone in rig.data.bones} == names and len(names) == 28
    conversion = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    for original in source["bones"]:
        bone = rig.data.bones[original["name"]]
        parent = source["bones"][original["parent"]]["name"] if original["parent"] >= 0 else None
        assert (bone.parent.name if bone.parent else None) == parent
        rest = conversion @ Matrix(original["matrix"])
        assert (bone.head_local - rest.translation).length < 1e-6
        assert (bone.tail_local - rest.translation - rest.to_3x3() @ Vector((0, .06, 0))).length < 1e-6
    triangles = 0
    for name, obj in meshes.items():
        assert obj.parent == rig and any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)
        offset = 0
        faces, slots = [], []
        for sid, (original, authored) in enumerate(zip(source["parts"][name]["surfaces"], target["parts"][name]["surfaces"])):
            for start in range(0, len(original["indices"]), 3):
                faces.append(tuple(offset + i for i in reversed(original["indices"][start:start + 3])))
                slots.append(sid)
            for i, position in enumerate(authored["positions"]):
                vertex = obj.data.vertices[offset + i]
                x, y, z = position
                assert (vertex.co - Vector((-x, z, y))).length < 1e-6
                expected = {}
                for bone, weight in zip(original["bone_names"][i], original["weights"][i]):
                    if weight > 0:
                        expected[bone] = expected.get(bone, 0) + weight
                actual = {obj.vertex_groups[group.group].name: group.weight for group in vertex.groups if group.weight > 0}
                assert set(actual) == set(expected)
                assert all(abs(actual[bone] - weight) < 1e-6 for bone, weight in expected.items())
            offset += len(authored["positions"])
        assert len(obj.data.vertices) == offset
        assert [tuple(poly.vertices) for poly in obj.data.polygons] == faces
        assert [poly.material_index for poly in obj.data.polygons] == slots
        uv = [p for row in target["parts"][name]["surfaces"] for p in row["uv"]]
        for loop, actual in zip(obj.data.loops, obj.data.uv_layers.active.data):
            expected = uv[loop.vertex_index]
            assert math.dist((actual.uv.x, 1 - actual.uv.y), expected) < 1e-6
        for sid, label in enumerate(config["parts"][name]):
            images = [node.image for node in obj.data.materials[sid].node_tree.nodes if node.type == "TEX_IMAGE"]
            assert len(images) == 1 and images[0].packed_file
            assert hashlib.sha256(bytes(images[0].packed_file.data)).hexdigest() == digest(textures[label])
        triangles += len(faces)
    assert triangles == 700
    return {"master_sha256": digest(master), "triangles": triangles, "bones": 28,
            "original_uv_indices_weights_verified": True, "five_packed_native_pngs_exact": True}


def verify_glb(config, source, target, textures):
    import io
    from PIL import Image, ImageChops
    from validate_glb_images import read_accessor
    path = ROOT / config["asset"] / "titan.glb"
    data = path.read_bytes()
    assert data[:4] == b"glTF" and struct.unpack_from("<II", data, 4) == (2, len(data))
    chunks, cursor = {}, 12
    while cursor < len(data):
        length, kind = struct.unpack_from("<II", data, cursor)
        chunks[kind] = data[cursor + 8:cursor + 8 + length]
        cursor += 8 + length
    assert cursor == len(data)
    gltf, binary = json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]
    assert len(gltf["meshes"]) == 4 and len(gltf["images"]) == 5
    records = {}
    for name, labels in config["parts"].items():
        node = next(node for node in gltf["nodes"] if node.get("name") == name)
        joints = [gltf["nodes"][i]["name"] for i in gltf["skins"][node["skin"]]["joints"]]
        assert len(joints) == len(set(joints)) == 28 and set(joints) == {b["name"] for b in source["bones"]}
        primitives = gltf["meshes"][node["mesh"]]["primitives"]
        assert len(primitives) == len(labels)
        for sid, (label, primitive) in enumerate(zip(labels, primitives)):
            original = source["parts"][name]["surfaces"][sid]
            uv = read_accessor(gltf, binary, primitive["attributes"]["TEXCOORD_0"])
            indices = [r[0] for r in read_accessor(gltf, binary, primitive["indices"])]
            assert len(uv) == len(original["uv"]) and len(indices) == len(original["indices"])
            assert all(math.dist(a, b) < 1e-6 for a, b in zip(uv, original["uv"]))
            assert all(indices[i:i + 3] == list(reversed(original["indices"][i:i + 3])) for i in range(0, len(indices), 3))
            binds = read_accessor(gltf, binary, primitive["attributes"]["JOINTS_0"])
            weights = read_accessor(gltf, binary, primitive["attributes"]["WEIGHTS_0"])
            assert len(binds) == len(weights) == len(uv)
            for i, (bones, values) in enumerate(zip(binds, weights)):
                expected, actual = {}, {}
                for bone, value in zip(original["bone_names"][i], original["weights"][i]):
                    if value > 0:
                        expected[bone] = expected.get(bone, 0) + value / sum(original["weights"][i])
                for bone, value in zip(bones, values):
                    if value > 0:
                        actual[joints[bone]] = actual.get(joints[bone], 0) + value
                assert set(actual) == set(expected) and abs(sum(values) - 1) < 1e-5
                assert all(abs(actual[bone] - value) < 2e-6 for bone, value in expected.items())
            material = gltf["materials"][primitive["material"]]
            texture = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            image = gltf["images"][gltf["textures"][texture]["source"]]
            assert image["mimeType"] == "image/png" and "bufferView" in image
            view = gltf["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            embedded = Image.open(io.BytesIO(binary[start:start + view["byteLength"]])).convert("RGB")
            canonical = Image.open(textures[label]).convert("RGB")
            assert embedded.size == canonical.size and ImageChops.difference(embedded, canonical).getbbox() is None
            records[label] = {"canonical_sha256": digest(textures[label]), "dimensions": list(canonical.size), "rgb_exact": True}
    return {"glb_sha256": digest(path), "original_triangle_uv_normalized_skin_verified": True, "images": records}


def main():
    config, source, target, textures = inputs()
    try:
        import bpy
    except ImportError:
        mode, checks = "glb", verify_glb(config, source, target, textures)
    else:
        mode, checks = "master", verify_master(config, source, target, textures)
    report = {"status": "PASS", "revision": config["active_helmet_revision"],
              "scope": "Current revision; exact source snapshot, actual SCN original-array check, preserved non-head textures and native generation provenance. Historical integration hashes are not recertified.",
              "source_sha256": digest(WORK / "build/source.json"), "target_sha256": digest(WORK / "build/target.json"), **checks}
    (WORK / f"review/helmet_v3_{mode}_test.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"TITAN_HELMET_V3_{mode.upper()}_PASS")


if __name__ == "__main__":
    main()
