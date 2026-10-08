"""Read-only native RGB and original topology/skin checks for three new GLBs.

python tools/armor_runtime_v1/validate_glb_images.py --armor hydra
Decoding is for inspection only; no image, GLB or imported resource is changed.
"""
import argparse
import hashlib
import importlib.util
import io
import json
import math
import struct
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_accessor(gltf, binary, number):
    accessor = gltf["accessors"][number]
    assert "sparse" not in accessor and "bufferView" in accessor
    view = gltf["bufferViews"][accessor["bufferView"]]
    assert view.get("buffer", 0) == 0
    code, width = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
                   5125: ("I", 4), 5126: ("f", 4)}[accessor["componentType"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[accessor["type"]]
    stride = view.get("byteStride", components * width)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    assert stride >= components * width
    rows = []
    for index in range(accessor["count"]):
        offset = start + index * stride
        assert offset + width * components <= len(binary)
        values = list(struct.unpack_from("<" + code * components, binary, offset))
        if accessor.get("normalized") and accessor["componentType"] != 5126:
            maximum = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535, 5125: 4294967295}[accessor["componentType"]]
            values = [max(-1, value / maximum) if code.islower() else value / maximum for value in values]
        assert all(math.isfinite(value) for value in values)
        rows.append(values)
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--armor", required=True, choices=["hydra", "strike", "titan", "atom", "pegasus"])
    slug = parser.parse_args().armor
    contract_path = ROOT / ("tools/armor_runtime_v1/first_integration_contract.py"
                            if slug in ["atom", "pegasus"] else "tools/armor_style_unification_v1/validate.py")
    spec = importlib.util.spec_from_file_location("armor_source_contract", contract_path)
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    source, snapshot = validator.verify_first_source(slug)
    work, assets = ROOT / f"docs/art/{slug}_runtime_v1", ROOT / f"assets/armors/{slug}_v1"
    config = validator.read(work / "runtime_config.json")
    target = validator.read(work / "build/target.json")
    generated = validator.verify_first_generation(slug, work, assets)
    native_sha = {row["label"]: row["canonical_sha256"] for row in generated}
    path = assets / f"{slug}.glb"
    data = path.read_bytes()
    assert data[:4] == b"glTF" and struct.unpack_from("<I", data, 4)[0] == 2
    assert struct.unpack_from("<I", data, 8)[0] == len(data)
    chunks, cursor = {}, 12
    while cursor < len(data):
        assert cursor + 8 <= len(data)
        length, kind = struct.unpack_from("<II", data, cursor)
        assert cursor + 8 + length <= len(data) and kind not in chunks
        chunks[kind] = data[cursor + 8:cursor + 8 + length]
        cursor += 8 + length
    assert cursor == len(data)
    gltf, binary = json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]
    assert len(gltf["meshes"]) == 4 and len(gltf["images"]) == 5
    image_records, primitive_records = {}, []
    bone_names = {bone["name"] for bone in source["bones"]}
    for node_name, labels in config["parts"].items():
        matches = [(number, node) for number, node in enumerate(gltf["nodes"]) if node.get("name") == node_name]
        assert len(matches) == 1
        node_index, node = matches[0]
        primitives = gltf["meshes"][node["mesh"]]["primitives"]
        assert len(primitives) == len(labels)
        skin = gltf["skins"][node["skin"]]
        joints = [gltf["nodes"][number]["name"] for number in skin["joints"]]
        assert len(joints) == len(set(joints)) == 28 and set(joints) == bone_names
        assert gltf["accessors"][skin["inverseBindMatrices"]]["count"] == 28
        for sid, label in enumerate(labels):
            primitive = primitives[sid]
            assert primitive.get("mode", 4) == 4
            original = source["parts"][node_name]["surfaces"][sid]
            authored = target["parts"][node_name]["surfaces"][sid]
            indices = [row[0] for row in read_accessor(gltf, binary, primitive["indices"])]
            assert len(indices) == len(original["indices"])
            uv = read_accessor(gltf, binary, primitive["attributes"]["TEXCOORD_0"])
            joint_values = read_accessor(gltf, binary, primitive["attributes"]["JOINTS_0"])
            weights = read_accessor(gltf, binary, primitive["attributes"]["WEIGHTS_0"])
            assert len(uv) == len(joint_values) == len(weights)
            assert all(isinstance(index, int) and 0 <= index < len(uv) for index in indices)
            actual_weights = []
            for binds, ws in zip(joint_values, weights):
                assert len(binds) == len(ws) == 4
                grouped = {}
                for bind, weight in zip(binds, ws):
                    assert isinstance(bind, int) and 0 <= bind < 28 and 0 <= weight <= 1
                    if weight > 0:
                        grouped[joints[bind]] = grouped.get(joints[bind], 0) + weight
                assert abs(sum(grouped.values()) - 1) < 1e-5
                actual_weights.append(grouped)
            expected_weights = []
            for names, ws in zip(original["bone_names"], original["weights"]):
                grouped = {}
                total = sum(ws)
                for name, weight in zip(names, ws):
                    if weight > 0:
                        grouped[name] = grouped.get(name, 0) + weight / total
                expected_weights.append(grouped)
            maximum_uv_error = maximum_weight_error = 0.0
            for start in range(0, len(indices), 3):
                # Blender-to-glTF may rotate the corner order or reverse winding;
                # preserve the exact source triangle's UV/bone-weight identity.
                old_triangle = original["indices"][start:start + 3]
                new_triangle = indices[start:start + 3]
                candidates = []
                for reverse in [False, True]:
                    row = list(reversed(new_triangle)) if reverse else new_triangle
                    for shift in range(3):
                        order = row[shift:] + row[:shift]
                        uv_error = max(math.dist(uv[new], authored["uv"][old]) for old, new in zip(old_triangle, order))
                        weight_error = 0.0
                        compatible = True
                        for old, new in zip(old_triangle, order):
                            expected, actual = expected_weights[old], actual_weights[new]
                            compatible &= set(expected) == set(actual)
                            weight_error = max(weight_error, max((abs(actual.get(name, 0) - value) for name, value in expected.items()), default=0))
                        if compatible:
                            candidates.append((uv_error, weight_error))
                assert candidates, f"{slug}/{label}: original triangle skin/bone assignment changed"
                uv_error, weight_error = min(candidates, key=lambda pair: max(pair))
                assert uv_error <= 1e-6 and weight_error <= 2e-6, f"{slug}/{label}: original triangle UV/normalized weight identity changed"
                maximum_uv_error, maximum_weight_error = max(maximum_uv_error, uv_error), max(maximum_weight_error, weight_error)
            material_index = primitive["material"]
            material = gltf["materials"][material_index]
            texture_index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            image_index = gltf["textures"][texture_index]["source"]
            image = gltf["images"][image_index]
            assert image["name"] == label + "_diffuse" and image["mimeType"] == "image/png" and "bufferView" in image
            view = gltf["bufferViews"][image["bufferView"]]
            assert view.get("buffer", 0) == 0
            offset = view.get("byteOffset", 0)
            assert offset + view["byteLength"] <= len(binary)
            embedded = Image.open(io.BytesIO(binary[offset:offset + view["byteLength"]])).convert("RGB")
            canonical_path = assets / f"{label}_diffuse.png"
            canonical = Image.open(canonical_path).convert("RGB")
            assert embedded.size == canonical.size and digest(canonical_path) == native_sha[label]
            delta = ImageChops.difference(embedded, canonical)
            maximum = max(high for _, high in delta.getextrema())
            assert delta.getbbox() is None, f"{slug}/{label}: embedded RGB differs from native canonical PNG"
            image_records[label] = {"node": node_name, "node_index": node_index, "mesh_index": node["mesh"], "surface": sid,
                                    "material_index": material_index, "texture_index": texture_index, "image_index": image_index,
                                    "canonical_sha256": digest(canonical_path), "dimensions": list(embedded.size),
                                    "compared_rgb_pixels": embedded.width * embedded.height,
                                    "max_channel_error_8bit": maximum, "pixels_equal": True}
            primitive_records.append({"part": node_name, "surface": sid, "label": label, "original_triangle_count": len(indices) // 3,
                                      "original_triangle_uv_skin_weight_identity_verified": True,
                                      "max_uv_error": maximum_uv_error, "max_normalized_weight_error": maximum_weight_error})
    assert set(image_records) == validator.LABELS and len(primitive_records) == 5
    report = {"status": "PASS", "scope": "Full native RGB pixels plus original triangle UV/skin/normalized-weight identity in the portable GLB. SCN original quantized weights stay exact; exchange weights are necessarily normalized by glTF export.",
              "glb_sha256": digest(path), "source_sha256": digest(work / "build/source.json"), "target_sha256": digest(work / "build/target.json"),
              "original_source_snapshot_sha256": snapshot["original_source_snapshot_sha256"], "original_node_ids": snapshot["used_node_ids"],
              "original_bones": 28, "original_topology_skin_weights_verified": True, "primitives": primitive_records, "images": image_records}
    output = work / "review/glb_images_test.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{slug.upper()}_GLB_IMAGE_PIXELS_PASS five native RGB atlases exact; original triangles/28-bone skin/normalized weights verified")


if __name__ == "__main__":
    main()
