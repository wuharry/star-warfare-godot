"""Decode all five images embedded in the GLB and compare full RGB pixels.

This checks the portable exchange file independently of Godot's texture importer
and its VRAM block compression. No generated or exported image is changed.
"""
import hashlib
import io
import json
import struct
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/tank_runtime_v1"
ASSETS = ROOT / "assets/armors/tank_v1"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    path = ASSETS / "tank.glb"
    data = path.read_bytes()
    assert data[:4] == b"glTF" and struct.unpack_from("<I", data, 4)[0] == 2
    assert struct.unpack_from("<I", data, 8)[0] == len(data)
    chunks = {}
    cursor = 12
    while cursor < len(data):
        length, kind = struct.unpack_from("<II", data, cursor)
        chunks[kind] = data[cursor + 8:cursor + 8 + length]
        cursor += 8 + length
    gltf = json.loads(chunks[0x4E4F534A])
    binary = chunks[0x004E4942]
    records = {}
    surfaces = {"head": ("ArmorHead_02", 0), "body": ("ArmorBody_02", 0),
                "shoulder": ("ArmorBody_02", 1), "hand": ("ArmorHand_02", 0), "foot": ("ArmorFoot_02", 0)}
    for label, (node_name, surface) in surfaces.items():
        node_index, node = next((index, node) for index, node in enumerate(gltf["nodes"]) if node.get("name") == node_name)
        primitive = gltf["meshes"][node["mesh"]]["primitives"][surface]
        material_index = primitive["material"]
        material = gltf["materials"][material_index]
        texture_index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        image_index = gltf["textures"][texture_index]["source"]
        row = gltf["images"][image_index]
        assert row["name"] == label + "_diffuse", f"{label}: actual GLB material points to the wrong image"
        assert row["mimeType"] == "image/png" and "bufferView" in row
        view = gltf["bufferViews"][row["bufferView"]]
        assert view["buffer"] == 0
        start = view.get("byteOffset", 0)
        embedded = Image.open(io.BytesIO(binary[start:start + view["byteLength"]])).convert("RGB")
        canonical_path = ASSETS / (label + "_diffuse.png")
        canonical = Image.open(canonical_path).convert("RGB")
        assert embedded.size == canonical.size
        delta = ImageChops.difference(embedded, canonical)
        extrema = delta.getextrema()
        maximum = max(high for _, high in extrema)
        assert delta.getbbox() is None, f"{label}: GLB contains different RGB pixels (max error {maximum})"
        records[label] = {"node": node_name, "node_index": node_index, "mesh_index": node["mesh"], "surface": surface,
                          "material_index": material_index, "texture_index": texture_index, "image_index": image_index,
                          "buffer_view": row["bufferView"], "canonical_sha256": sha(canonical_path), "dimensions": list(embedded.size),
                          "compared_rgb_pixels": embedded.width * embedded.height,
                          "max_channel_error_8bit": maximum, "pixels_equal": True}
    neck_node = next(node for node in gltf["nodes"] if node.get("name") == "ArmorHead_02")
    neck_primitive = gltf["meshes"][neck_node["mesh"]]["primitives"][1]
    neck_material = gltf["materials"][neck_primitive["material"]]
    neck_texture = neck_material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    assert gltf["textures"][neck_texture]["source"] == records["hand"]["image_index"], "Shared head neck does not use current hand image"
    report = {"status": "PASS", "shared_head_hand_image_verified": True, "scope": "Full decoded RGB image pixels embedded in the standalone GLB, before any engine VRAM compression.",
              "glb_sha256": sha(path), "images": records}
    (WORK / "review/glb_images_test.json").write_text(json.dumps(report, indent=2) + "\n")
    print("TANK_GLB_IMAGE_PIXELS_PASS five full embedded atlases equal current canonical RGB")


if __name__ == "__main__":
    main()
