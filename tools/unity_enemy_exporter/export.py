#!/usr/bin/env python3
"""Export one legacy Unity enemy prefab, skin and referenced clips to glTF."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
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


def validate_output(project_root: Path, output_path: Path, *, overwrite: bool = False) -> Path:
    """Validate all destinations before mkdir, texture copy, or buffer writes."""
    source_root = project_root.resolve()
    output = output_path.resolve()
    if output.suffix.lower() != ".gltf":
        raise ValueError("Enemy output must have a .gltf suffix")
    destinations = [output, output.with_suffix(".bin"),
                    output.with_name(output.stem + "_export_report.json"), output.parent / "textures"]
    def inside_source(destination: Path) -> bool:
        resolved = destination.resolve()
        if resolved.is_relative_to(source_root):
            return True
        # macOS commonly uses case-insensitive volumes. samefile also catches
        # alternate capitalization of an existing source ancestor.
        return any(parent.exists() and parent.samefile(source_root)
                   for parent in (resolved, *resolved.parents))
    for destination in destinations:
        if inside_source(destination):
            raise ValueError(f"Refusing to write inside read-only Unity source: {destination}")
    textures = output.parent / "textures"
    if textures.is_dir():
        for destination in textures.rglob("*"):
            if inside_source(destination):
                raise ValueError(f"Texture destination links into Unity source: {destination}")
    if not overwrite:
        for destination in destinations:
            if destination.exists() or destination.is_symlink():
                raise FileExistsError(f"Existing export requires explicit --overwrite: {destination}")
    return output


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


def quaternion_product(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, ...]:
    x, y, z, w = a
    u, v, t, s = b
    return (w*u+x*s+y*t-z*v, w*v-x*t+y*s+z*u, w*t+x*v-y*u+z*s, w*s-x*u-y*v-z*t)


def sample_keys(keys: list, at: float, rotation: bool = False) -> tuple[float, ...]:
    if at <= keys[0][0]:
        return tuple(keys[0][1])
    if at >= keys[-1][0]:
        return tuple(keys[-1][1])
    for (left_time, left), (right_time, right) in zip(keys, keys[1:]):
        if left_time <= at <= right_time:
            weight = (at - left_time) / (right_time - left_time)
            if rotation:
                dot = sum(a*b for a, b in zip(left, right))
                if dot < 0:
                    right = tuple(-v for v in right)
                    dot = -dot
                if dot < 0.9995:
                    angle = math.acos(max(-1.0, min(1.0, dot)))
                    return tuple((math.sin((1-weight)*angle)*a + math.sin(weight*angle)*b) / math.sin(angle)
                                 for a, b in zip(left, right))
            value = tuple(a + (b-a)*weight for a, b in zip(left, right))
            if rotation:
                length = math.sqrt(sum(v*v for v in value))
                return tuple(v / length for v in value)
            return value
    raise ValueError("Animation key times are not ordered")


def compose_trs(parent: dict, child: dict) -> dict:
    scale = parent["scale"]
    if max(scale) - min(scale) > 0.00001:
        raise ValueError("Nonuniform removed-parent scale can introduce shear")
    vector = tuple(child["translation"][i] * scale[i] for i in range(3)) + (0.0,)
    q = parent["rotation"]
    rotated = quaternion_product(quaternion_product(q, vector), (-q[0], -q[1], -q[2], q[3]))
    return {"translation": tuple(parent["translation"][i] + rotated[i] for i in range(3)),
            "rotation": quaternion_product(q, child["rotation"]),
            "scale": tuple(scale[i] * child["scale"][i] for i in range(3))}


def collapse_parent_curves(curves: dict, bone_path: str, removed_parents: list[str]) -> dict:
    """Bake P(t)*child(t), never apply the child's old local frame directly."""
    paths = [*removed_parents, bone_path]
    if any(not curves[channel].get(path) for path in paths for channel in ("translation", "rotation", "scale")):
        raise ValueError("Missing T/R/S curves for removed parent or child")
    times = {time for path in paths for channel in curves for time, _ in curves[channel][path]}
    # Composition adds nonlinear translation from animated parent rotation.
    # Bake both original key times and 120Hz samples, preserving key endpoints.
    start, end = min(times), max(times)
    times.update(start + i / 120.0 for i in range(math.ceil((end-start)*120)) if start + i / 120.0 <= end)
    result = {channel: [] for channel in curves}
    for time in sorted(times):
        local = {channel: sample_keys(curves[channel][bone_path], time, channel == "rotation") for channel in curves}
        for parent in reversed(removed_parents):
            parent_trs = {channel: sample_keys(curves[channel][parent], time, channel == "rotation") for channel in curves}
            local = compose_trs(parent_trs, local)
        for channel in curves:
            result[channel].append((time, local[channel]))
    return result


def removed_parent_binding(bone_path: str, hierarchy: list, root_name: str) -> tuple[int, list[str], list[str]] | None:
    """Require the complete retained ancestry to match, not only a leaf name."""
    authored = bone_path.split("/")
    matches = []
    for node in hierarchy:
        if node.name != authored[-1]:
            continue
        actual = node.path.removeprefix(root_name + "/").split("/")
        if actual[0] != authored[0]:
            continue
        retained = []
        cursor = 0
        for part in actual:
            try:
                cursor = authored.index(part, cursor)
            except ValueError:
                break
            retained.append(cursor)
            cursor += 1
        if len(retained) != len(actual) or not retained or retained[-1] != len(authored)-1:
            continue
        removed = ["/".join(authored[:i+1]) for i in range(len(authored)-1) if i not in retained]
        if not removed:
            continue
        # Only removed nodes after the nearest retained parent alter this
        # node's local frame. Higher removed ancestors are baked at that parent.
        direct = ["/".join(authored[:i+1]) for i in range(retained[-2]+1, retained[-1])] if len(retained) > 1 else removed
        matches.append((node.node_index, direct, removed))
    return matches[0] if len(matches) == 1 else None


def compensate_inserted_parent(raw: tuple[float, ...], channel: str, parent: object) -> tuple[float, ...]:
    # boss06 inserts Dummy_armLink nodes between the authored clip paths.
    # Compensate their rest transform, otherwise the arms are translated twice.
    q = parent.rotation
    inverse_q = (-q[0], -q[1], -q[2], q[3])
    if channel == "rotation":
        return quaternion_product(inverse_q, tuple(raw))
    if channel == "scale":
        return tuple(raw[i] / parent.scale[i] for i in range(3))
    vector = tuple(raw[i] - parent.translation[i] for i in range(3)) + (0.0,)
    rotated = quaternion_product(quaternion_product(inverse_q, vector), q)
    return tuple(rotated[i] / parent.scale[i] for i in range(3))


def export_rigid_meshes(prefab: Path, hierarchy: list, gltf: dict, buffer: object,
                        guid_index: object, output_path: Path, image_cache: dict,
                        image_uri_cache: dict) -> list[str]:
    by_game = {node.game_id: node for node in hierarchy}
    filters: dict[int, str] = {}
    renderers: list[tuple[int, str]] = []
    for class_id, _, body in avatar.documents(prefab.read_text(encoding="utf-8-sig")):
        if class_id not in (23, 33):
            continue
        game = re.search(r"m_GameObject:\s*\{fileID:\s*(\d+)\}", body)
        if not game:
            continue
        game_id = int(game.group(1))
        if class_id == 33:
            mesh_guid = re.search(r"m_Mesh:\s*\{[^}]*guid:\s*([0-9a-f]{32})", body)
            if mesh_guid:
                filters[game_id] = mesh_guid.group(1)
        elif not re.search(r"m_Enabled:\s*0", body):
            renderers.append((game_id, body))
    exported: list[str] = []
    for game_id, body in renderers:
        if game_id not in filters:
            continue
        node = by_game[game_id]
        # Unity blob shadows are supplied by Godot's actual lighting, not a
        # second opaque card. Decorative source meshes (boss06 lights) remain.
        if "shadow" in node.path.lower():
            continue
        mesh = unity_mesh.parse_mesh(guid_index.resolve(filters[game_id]))
        positions = [avatar.convert_translation(v) for v in mesh.positions]
        faces = [(s.indices[i], s.indices[i+2], s.indices[i+1])
                 for s in mesh.submeshes for i in range(0, len(s.indices), 3)]
        normals = ([avatar.convert_translation(v) for v in mesh.normals] if mesh.normals
                   else unity_mesh._generated_normals(positions, faces))
        attributes = {
            "POSITION": buffer.accessor(positions, 5126, "VEC3", target=34962, include_bounds=True),
            "NORMAL": buffer.accessor(normals, 5126, "VEC3", target=34962),
            "TEXCOORD_0": buffer.accessor([(v[0], 1-v[1]) for v in (mesh.uvs or [(0, 0)]*len(positions))], 5126, "VEC2", target=34962),
        }
        material_ids = [avatar.add_material(gltf, unity_mesh.parse_material(guid_index.resolve(g), guid_index),
                        output_path.parent, image_cache, image_uri_cache, texture_directory="textures")
                        for g in unity_mesh._material_guids(body)]
        if not material_ids:
            raise ValueError(f"Missing source material: {node.path}")
        primitives = []
        for i, submesh in enumerate(mesh.submeshes):
            indices = [v for k in range(0, len(submesh.indices), 3)
                       for v in (submesh.indices[k], submesh.indices[k+2], submesh.indices[k+1])]
            primitives.append({"attributes": attributes,
                "indices": buffer.accessor(indices, 5125, "SCALAR", target=34963),
                "material": material_ids[min(i, len(material_ids)-1)], "mode": 4})
        gltf["nodes"][node.node_index]["mesh"] = len(gltf["meshes"])
        gltf["meshes"].append({"name": node.name, "primitives": primitives})
        exported.append(node.path)
    return exported


def export_enemy(project_root: Path, prefab_relative: Path, output_path: Path, *, overwrite: bool = False) -> dict[str, object]:
    output_path = validate_output(project_root, output_path, overwrite=overwrite)
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
    image_uri_cache: dict[str, int] = {}
    materials: list[int] = []
    for guid in renderer.material_guids:
        material_path = guid_index.resolve(guid)
        materials.append(avatar.add_material(
            gltf, unity_mesh.parse_material(material_path, guid_index), output_path.parent,
            image_cache, image_uri_cache, texture_directory="textures"
        ))
    if not materials:
        raise ValueError(f"Missing original materials: {prefab}")
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
    rigid_paths = export_rigid_meshes(prefab, hierarchy, gltf, buffer, guid_index,
                                     output_path, image_cache, image_uri_cache)

    # Some enemy prefabs insert a visual container (for example
    # boss01/Dragon/Bip02) while their AnimationClips are authored from the
    # skeleton root (Bip02).  Index every unambiguous suffix so both Unity path
    # conventions resolve to the same joint.
    suffix_candidates: dict[str, set[int]] = {}
    inserted_parents: dict[str, object] = {}
    for node in hierarchy:
        relative = node.path.removeprefix(root.name + "/")
        parts = relative.split("/")
        for start in range(len(parts)):
            suffix_candidates.setdefault("/".join(parts[start:]), set()).add(node.node_index)
        without_links = "/".join(p for p in parts if not p.startswith("Dummy_armLink_"))
        if without_links != relative and not node.name.startswith("Dummy_armLink_"):
            suffix_candidates.setdefault(without_links, set()).add(node.node_index)
            parent = by_id.get(node.father_id)
            if parent and parent.name.startswith("Dummy_armLink_"):
                inserted_parents[without_links] = parent
    path_to_node = {p: next(iter(values)) for p, values in suffix_candidates.items() if len(values) == 1}
    unmatched: set[str] = set()
    retargeted: dict[str, str] = {}
    repairs: list[dict[str, object]] = []
    skipped: list[dict[str, str]] = []
    used_names: dict[str, int] = {}
    for clip in referenced_clips(prefab, guid_index):
        base_name = clip.stem
        suffix = used_names.get(base_name, 0)
        used_names[base_name] = suffix + 1
        animation_name = base_name if suffix == 0 else f"{base_name}_{suffix + 1}"
        curves = avatar.parse_animation(clip)
        bindings: dict[str, int] = {}
        rebaked: dict[str, dict] = {}
        for bone_path in set().union(*(channel.keys() for channel in curves.values())):
            node_index = path_to_node.get(bone_path)
            if node_index is None:
                binding = removed_parent_binding(bone_path, hierarchy, root.name)
                if binding is not None:
                    node_index, direct_parents, all_removed = binding
                    try:
                        # Validate all removed ancestors, including those baked
                        # into retained parent nodes rather than this child.
                        if any(not curves[c].get(p) for p in all_removed for c in curves):
                            raise ValueError("Incomplete removed-ancestor T/R/S curves")
                        if direct_parents:
                            rebaked[bone_path] = collapse_parent_curves(curves, bone_path, direct_parents)
                    except ValueError as error:
                        skipped.append({"clip": animation_name, "path": bone_path, "reason": str(error)})
                        node_index = None
                    else:
                        retargeted[bone_path] = hierarchy[node_index].path
                        repairs.append({"clip": animation_name, "path": bone_path,
                                        "node": hierarchy[node_index].path, "removed_parents": direct_parents,
                                        "method": "compose_parent_curves_120hz" if direct_parents else "retained_parent_local_frame"})
            if node_index is None:
                unmatched.add(bone_path)
                skipped.append({"clip": animation_name, "path": bone_path, "reason": "No unambiguous hierarchy-compatible target"})
            else:
                bindings[bone_path] = node_index
        animation: dict[str, object] = {"name": animation_name, "samplers": [], "channels": []}
        for target_path, gltf_path in (("translation", "translation"), ("rotation", "rotation"), ("scale", "scale")):
            for bone_path, keys in curves[target_path].items():
                node_index = bindings.get(bone_path)
                if node_index is None:
                    continue
                if bone_path in rebaked:
                    keys = rebaked[bone_path][target_path]
                times = [key[0] for key in keys]
                values: list[tuple[float, ...]] = []
                previous_rotation: tuple[float, ...] | None = None
                for _, raw in keys:
                    if bone_path in inserted_parents:
                        raw = compensate_inserted_parent(raw, target_path, inserted_parents[bone_path])
                        retargeted[bone_path] = hierarchy[node_index].path
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
        "source_mesh_guid": renderer.mesh_guid,
        "source_material_guids": renderer.material_guids,
        "rigid_mesh_paths": rigid_paths,
        "retargeted_animation_paths": retargeted,
        "animation_binding_repairs": repairs,
        "skipped_animation_paths": skipped,
        "animations": [animation["name"] for animation in gltf["animations"]],  # type: ignore[index]
        "unmatched_animation_paths": sorted(unmatched),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--prefab", type=Path, required=True, help="Path relative to Assets")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--overwrite", action="store_true", help="Explicitly update an export outside the read-only Unity source tree")
    args = parser.parse_args()
    report = export_enemy(args.project_root.resolve(), args.prefab, args.output.resolve(), overwrite=args.overwrite)
    # Use the exact canonical destination that passed validation. A CLI file
    # symlink can have a different parent/name and unsafe adjacent sidecars.
    output = Path(report["output"])
    report_path = output.with_name(output.stem + "_export_report.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
