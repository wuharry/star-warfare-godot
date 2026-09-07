"""Carry the existing OBJ's exact triangles plus Unity UV1 into a glTF mesh.

OBJ remains the geometry audit/collision source. glTF is the runtime visual
asset because OBJ has no second texture-coordinate channel. No remeshing or
UV unwrapping occurs here; vertex splits retain the source lightmap seams.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path


def write_lightmap_gltf(obj_path: Path, pieces: list, states: dict) -> dict:
    positions, normals, uvs, uv2s = [], [], [], []
    for piece in pieces:
        if any(material.lightmap_source for material in piece.materials) and piece.mesh.uv2s is None:
            raise ValueError(f"Lightmapped mesh has no UV1: {piece.mesh.source_path}")
        uv2s.extend(piece.mesh.uv2s or [(0.0, 0.0)] * len(piece.mesh.positions))
    groups = {}
    current = None
    for line in obj_path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "v":
            positions.append(tuple(map(float, fields[1:])))
        elif fields[0] == "vn":
            normals.append(tuple(map(float, fields[1:])))
        elif fields[0] == "vt":
            uvs.append(tuple(map(float, fields[1:])))
        elif fields[0] == "usemtl":
            current = fields[1]
            groups.setdefault(current, [])
        elif fields[0] == "f":
            groups[current].append(tuple(tuple(int(i) - 1 if i else -1 for i in field.split("/")) for field in fields[1:]))
    if len(uv2s) != len(positions):
        raise ValueError(f"{obj_path}: {len(uv2s)} UV1 entries for {len(positions)} vertices")
    mtl = {}
    for line in obj_path.with_suffix(".mtl").read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "newmtl":
            current = fields[1]
            mtl[current] = {"color": [1.0, 1.0, 1.0, 1.0]}
        elif fields[0] == "Kd":
            mtl[current]["color"][:3] = map(float, fields[1:])
        elif fields[0] == "d":
            mtl[current]["color"][3] = float(fields[1])
        elif fields[0] == "map_Kd":
            mtl[current]["texture"] = fields[1]

    blob = bytearray()
    document = {
        "asset": {"version": "2.0", "generator": "Star Warfare Unity lightmap restoration"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "RestoredStage", "mesh": 0}],
        "meshes": [{"name": "RestoredStage", "primitives": []}],
        "bufferViews": [], "accessors": [], "materials": [], "images": [], "textures": [],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
    }

    def accessor(values, dimensions, integer=False):
        while len(blob) % 4:
            blob.append(0)
        start = len(blob)
        code = "I" if integer else "f"
        for value in values:
            blob.extend(struct.pack("<" + code * dimensions, *value))
        view = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": start, "byteLength": len(blob) - start})
        record = {"bufferView": view, "componentType": 5125 if integer else 5126,
                  "count": len(values), "type": {1: "SCALAR", 2: "VEC2", 3: "VEC3"}[dimensions]}
        if dimensions == 3:
            record["min"] = [min(v[axis] for v in values) for axis in range(3)]
            record["max"] = [max(v[axis] for v in values) for axis in range(3)]
        result = len(document["accessors"])
        document["accessors"].append(record)
        return result

    texture_indices = {}
    for name, faces in groups.items():
        remap, points, directions, first_uv, second_uv, indices = {}, [], [], [], [], []
        for face in faces:
            for entry in face:
                if entry not in remap:
                    remap[entry] = len(points)
                    vertex, uv, normal = entry
                    points.append(positions[vertex])
                    directions.append(normals[normal])
                    texcoord = uvs[uv] if uv >= 0 else (0.0, 0.0)
                    first_uv.append((texcoord[0], 1.0 - texcoord[1]))
                    second_uv.append((uv2s[vertex][0], 1.0 - uv2s[vertex][1]))
                indices.append((remap[entry],))
        material_index = len(document["materials"])
        source = mtl[name]
        pbr = {"baseColorFactor": source["color"], "metallicFactor": 0.0, "roughnessFactor": 1.0}
        if "texture" in source:
            filename = source["texture"]
            if filename not in texture_indices:
                texture_indices[filename] = len(document["textures"])
                document["textures"].append({"source": len(document["images"]), "sampler": 0})
                document["images"].append({"uri": filename})
            pbr["baseColorTexture"] = {"index": texture_indices[filename]}
        material = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": states[name]["cull_disabled"]}
        if states[name]["blend"] in ("alpha", "additive"):
            material["alphaMode"] = "BLEND"
        elif states[name]["blend"] == "cutout":
            material.update({"alphaMode": "MASK", "alphaCutoff": states[name]["alpha_scissor_threshold"]})
        document["materials"].append(material)
        document["meshes"][0]["primitives"].append({
            "attributes": {"POSITION": accessor(points, 3), "NORMAL": accessor(directions, 3),
                           "TEXCOORD_0": accessor(first_uv, 2), "TEXCOORD_1": accessor(second_uv, 2)},
            "indices": accessor(indices, 1, True), "material": material_index,
        })
    binary_path = obj_path.with_suffix(".bin")
    document["buffers"] = [{"uri": binary_path.name, "byteLength": len(blob)}]
    binary_path.write_bytes(blob)
    obj_path.with_suffix(".gltf").write_text(json.dumps(document, separators=(",", ":")) + "\n", encoding="utf-8")
    return {"file": obj_path.with_suffix(".gltf").name, "surfaces": len(groups), "triangles": sum(map(len, groups.values()))}
