#!/usr/bin/env python3
"""Export one legacy Unity enemy prefab, skin and referenced clips to glTF."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path


AVATAR_EXPORTER = Path(__file__).resolve().parents[1] / "unity_avatar_exporter" / "export.py"
SPEC = importlib.util.spec_from_file_location("star_warfare_avatar_exporter", AVATAR_EXPORTER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load shared exporter from {AVATAR_EXPORTER}")
avatar = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = avatar
SPEC.loader.exec_module(avatar)
unity_mesh = avatar.unity_mesh


def referenced_clips(prefab: Path, guid_index: object) -> list[Path]:
    text = prefab.read_text(encoding="utf-8-sig")
    animation = re.search(r"^Animation:\s*$([\s\S]*?)^---", text, re.MULTILINE)
    if not animation:
        return []
    block = re.search(r"^\s*m_Animations:\s*$([\s\S]*?)^\s*m_WrapMode:", animation.group(1), re.MULTILINE)
    if not block:
        return []
    clips: list[Path] = []
    for guid in re.findall(r"guid:\s*([0-9a-f]{32})", block.group(1)):
        path = guid_index.resolve(guid)
        if path.is_file() and path.suffix == ".anim":
            clips.append(path)
    return clips


def export_enemy(project_root: Path, prefab_relative: Path, output_path: Path) -> dict[str, object]:
    assets = project_root / "Assets"
    prefab = assets / prefab_relative
    output_path.parent.mkdir(parents=True, exist_ok=True)
    guid_index = unity_mesh.GuidIndex(assets)
    hierarchy, root_id = avatar.parse_transform_hierarchy(prefab)
    by_id = {node.transform_id: node for node in hierarchy}
    renderer = avatar.parse_skinned_renderer(prefab)
    mesh_path = guid_index.resolve(renderer.mesh_guid)
    mesh = unity_mesh.parse_mesh(mesh_path)
    bind_poses, joints, weights = avatar.parse_skin(mesh_path, len(mesh.positions))
    if len(bind_poses) != len(renderer.bone_names):
        raise ValueError(
            f"{prefab.name}: {len(bind_poses)} bind poses for {len(renderer.bone_names)} renderer bones"
        )

    gltf: dict[str, object] = {
        "asset": {"version": "2.0", "generator": "Star Warfare Unity YAML enemy exporter"},
        "scene": 0,
        "scenes": [{"nodes": []}],
        "nodes": [], "meshes": [], "skins": [], "animations": [],
        "buffers": [], "bufferViews": [], "accessors": [],
        "materials": [], "images": [], "textures": [],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
    }
    nodes: list[dict[str, object]] = gltf["nodes"]  # type: ignore[assignment]
    for node in hierarchy:
        node.node_index = len(nodes)
        nodes.append({
            "name": node.name,
            "translation": list(avatar.convert_translation(node.translation)),
            "rotation": list(avatar.convert_rotation(node.rotation)),
            "scale": list(node.scale),
        })
    for node in hierarchy:
        children = [child.node_index for child in hierarchy if child.father_id == node.transform_id]
        if children:
            nodes[node.node_index]["children"] = children
    root = by_id[root_id]
    gltf["scenes"][0]["nodes"].append(root.node_index)  # type: ignore[index]
    name_to_node = {node.name: node.node_index for node in hierarchy}
    missing_bones = [name for name in renderer.bone_names if name not in name_to_node]
    if missing_bones:
        raise ValueError(f"Renderer bones missing from prefab hierarchy: {missing_bones}")

    buffer = avatar.BufferBuilder(gltf)
    inverse_accessor = buffer.accessor(
        [avatar.convert_matrix(matrix) for matrix in bind_poses], 5126, "MAT4"
    )
    gltf["skins"].append({  # type: ignore[union-attr]
        "name": f"{prefab.stem}Skin",
        "inverseBindMatrices": inverse_accessor,
        "joints": [name_to_node[name] for name in renderer.bone_names],
    })

    positions = [avatar.convert_translation(value) for value in mesh.positions]
    faces = [
        tuple(submesh.indices[offset:offset + 3])
        for submesh in mesh.submeshes
        for offset in range(0, len(submesh.indices), 3)
    ]
    reversed_faces = [(face[0], face[2], face[1]) for face in faces]
    normals = (
        [avatar.convert_translation(value) for value in mesh.normals]
        if mesh.normals else unity_mesh._generated_normals(positions, reversed_faces)
    )
    uvs = [
        (float(value[0]), 1.0 - float(value[1]))
        for value in (mesh.uvs or [(0.0, 0.0)] * len(positions))
    ]
    attributes = {
        "POSITION": buffer.accessor(positions, 5126, "VEC3", target=34962, include_bounds=True),
        "NORMAL": buffer.accessor(normals, 5126, "VEC3", target=34962),
        "TEXCOORD_0": buffer.accessor(uvs, 5126, "VEC2", target=34962),
        "JOINTS_0": buffer.accessor(joints, 5123, "VEC4", target=34962),
        "WEIGHTS_0": buffer.accessor(weights, 5126, "VEC4", target=34962),
    }
    image_cache: dict[Path, int] = {}
    materials: list[int] = []
    for guid in renderer.material_guids:
        material_path = guid_index.resolve(guid)
        materials.append(avatar.add_material(
            gltf, unity_mesh.parse_material(material_path, guid_index), output_path.parent, image_cache
        ))
    if not materials:
        materials.append(avatar.add_material(
            gltf, unity_mesh.fallback_material(prefab.stem), output_path.parent, image_cache
        ))
    primitives: list[dict[str, object]] = []
    for submesh_index, submesh in enumerate(mesh.submeshes):
        indices: list[int] = []
        for offset in range(0, len(submesh.indices), 3):
            first, second, third = submesh.indices[offset:offset + 3]
            indices.extend((first, third, second))
        primitives.append({
            "attributes": attributes,
            "indices": buffer.accessor(indices, 5125, "SCALAR", target=34963),
            "material": materials[min(submesh_index, len(materials) - 1)],
            "mode": 4,
        })
    gltf["meshes"].append({"name": renderer.name, "primitives": primitives})  # type: ignore[union-attr]
    mesh_node = len(nodes)
    nodes.append({"name": f"{renderer.name}_Skinned", "mesh": 0, "skin": 0})
    nodes[root.node_index].setdefault("children", []).append(mesh_node)  # type: ignore[union-attr]

    # Some enemy prefabs insert a visual container (for example
    # boss01/Dragon/Bip02) while their AnimationClips are authored from the
    # skeleton root (Bip02).  Index every unambiguous suffix so both Unity path
    # conventions resolve to the same joint.
    path_to_node: dict[str, int] = {}
    for node in hierarchy:
        relative = node.path.removeprefix(root.name + "/")
        parts = relative.split("/")
        for start in range(len(parts)):
            path_to_node.setdefault("/".join(parts[start:]), node.node_index)
    unmatched: set[str] = set()
    used_names: dict[str, int] = {}
    for clip in referenced_clips(prefab, guid_index):
        base_name = clip.stem
        suffix = used_names.get(base_name, 0)
        used_names[base_name] = suffix + 1
        animation_name = base_name if suffix == 0 else f"{base_name}_{suffix + 1}"
        curves = avatar.parse_animation(clip)
        animation: dict[str, object] = {"name": animation_name, "samplers": [], "channels": []}
        for target_path, gltf_path in (("translation", "translation"), ("rotation", "rotation"), ("scale", "scale")):
            for bone_path, keys in curves[target_path].items():
                node_index = path_to_node.get(bone_path)
                if node_index is None:
                    unmatched.add(bone_path)
                    continue
                times = [key[0] for key in keys]
                values: list[tuple[float, ...]] = []
                previous_rotation: tuple[float, ...] | None = None
                for _, raw in keys:
                    if target_path == "translation":
                        value = avatar.convert_translation(raw)
                    elif target_path == "rotation":
                        value = avatar.convert_rotation(raw)
                        if previous_rotation is not None and sum(a * b for a, b in zip(previous_rotation, value)) < 0:
                            value = tuple(-component for component in value)
                        previous_rotation = value
                    else:
                        value = tuple(float(component) for component in raw)
                    values.append(value)
                input_accessor = buffer.accessor(times, 5126, "SCALAR", include_bounds=True)
                output_accessor = buffer.accessor(
                    values, 5126, "VEC4" if target_path == "rotation" else "VEC3"
                )
                sampler_index = len(animation["samplers"])  # type: ignore[arg-type]
                animation["samplers"].append({  # type: ignore[union-attr]
                    "input": input_accessor, "output": output_accessor, "interpolation": "LINEAR"
                })
                animation["channels"].append({  # type: ignore[union-attr]
                    "sampler": sampler_index, "target": {"node": node_index, "path": gltf_path}
                })
        if animation["channels"]:
            gltf["animations"].append(animation)  # type: ignore[union-attr]

    binary_name = output_path.with_suffix(".bin").name
    gltf["buffers"] = [{"uri": binary_name, "byteLength": len(buffer.data)}]
    gltf["asset"]["extras"] = {"buffer_sha256": hashlib.sha256(buffer.data).hexdigest()}  # type: ignore[index]
    output_path.with_suffix(".bin").write_bytes(buffer.data)
    output_path.write_text(json.dumps(gltf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {
        "prefab": str(prefab_relative), "output": str(output_path),
        "bones": len(renderer.bone_names), "vertices": len(mesh.positions),
        "animations": [animation["name"] for animation in gltf["animations"]],  # type: ignore[index]
        "unmatched_animation_paths": sorted(unmatched),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--prefab", type=Path, required=True, help="Path relative to Assets")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = export_enemy(args.project_root.resolve(), args.prefab, args.output.resolve())
    report_path = args.output.with_name(args.output.stem + "_export_report.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
