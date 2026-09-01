#!/usr/bin/env python3
"""Export Star Warfare's legacy YAML avatar and clips to an animated glTF."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image

MESH_TOOL_DIR = Path(__file__).resolve().parents[1] / "yaml_mesh_converter"
sys.path.insert(0, str(MESH_TOOL_DIR))
import convert as unity_mesh  # noqa: E402


ANIMATION_NAMES = (
    "idle_rifle", "run_rifle", "stand_shoot_rifle", "run_shoot_rifle",
    "idle_shotgun", "run_shotgun", "stand_shoot_shotgun", "run_shoot_shotgun",
    "idle_bazinga", "run_bazinga", "stand_shoot_bazinga", "run_shoot_bazinga",
    "idle_jian", "run_jian", "stand_shoot_jian", "run_shoot_jian",
    "idle_bow", "run_bow", "stand_shoot_bow", "run_shoot_bow",
    "idle_fist", "run_fist", "stand_shoot_fist", "run_shoot_fist",
    "idle_machinegun", "run_machinegun", "stand_shoot_machinegun", "run_shoot_machinegun",
    "idle_Sniper", "run_Sniper", "stand_shoot_Sniper", "run_shoot_Sniper",
    "stand_shoot_grenade_launcher", "run_shoot_grenade_launcher",
    "stand_shoot_laser", "run_shoot_laser",
    "stand_shoot_BLACKSTARS", "run_shoot_BLACKSTARS",
    "attacked", "attacked_back", "dead", "win", "win01", "idle01",
    # The FLY armor skill swaps the entire locomotion/weapon animation stack in
    # Unity.  These clips live beside the ground animations and target the same
    # Bip01 skeleton, so keep them in the canonical avatar export as well.
    "fly_idle", "fly_front", "fly_back", "fly_left", "fly_right",
    "fly_rifle", "fly_shotgun", "fly_bazinga", "fly_jian", "fly_bow",
    "fly_fist", "fly_machinegun", "fly_Sniper",
    "fly_idle_rifle", "fly_idle_shotgun", "fly_idle_bazinga",
    "fly_idle_jian", "fly_idle_bow", "fly_idle_fist",
    "fly_idle_machinegun", "fly_idle_Sniper",
    "fly_stand_shoot_rifle", "fly_stand_shoot_shotgun",
    "fly_stand_shoot_bazinga", "fly_stand_shoot_jian",
    "fly_stand_shoot_bow", "fly_stand_shoot_fist",
    "fly_stand_shoot_machinegun", "fly_stand_shoot_Sniper",
    "fly_stand_shoot_grenade_launcher", "fly_stand_shoot_laser",
    "fly_stand_shoot_BLACKSTARS", "fly_stand_shoot_jian_lower",
    "fly_runshoot_jian", "fly_runshoot_machinegun",
)

ARMOR_PART_NAMES = ("Head", "Body", "Hand", "Foot")
ARMOR_VARIANT_COUNT = 21
BAG_VARIANT_COUNT = 25
# WeaponResourceConfig.GetBagSize() uses zero-based bag IDs. AvatarBuilder then
# applies another 0.8 multiplier for every body except body ID 5.
BAG_SIZE_OVERRIDES = {
    14: 1.2,
    15: 1.2,
    16: 1.2,
    17: 1.2,
    18: 1.1,
    19: 1.2,
    20: 1.2,
}
ANIMATED_UNITY_BAGS = {15, 23}
TEXTURE_EXPORT_SCALE = 2


@dataclass
class TransformNode:
    transform_id: int
    game_id: int
    name: str
    father_id: int
    translation: tuple[float, float, float]
    rotation: tuple[float, float, float, float]
    scale: tuple[float, float, float]
    node_index: int = -1
    path: str = ""


@dataclass
class SkinnedRenderer:
    name: str
    mesh_guid: str
    material_guids: list[str]
    bone_names: list[str]


@dataclass
class ArmorPartData:
    armor_id: int
    part_name: str
    source_prefab: Path
    renderer: SkinnedRenderer
    mesh_path: Path
    mesh: object
    bind_poses: list[tuple[float, ...]]
    joints: list[tuple[int, ...]]
    weights: list[tuple[float, ...]]


class BufferBuilder:
    def __init__(self, gltf: dict[str, object]):
        self.gltf = gltf
        self.data = bytearray()

    def _align(self) -> None:
        while len(self.data) % 4:
            self.data.append(0)

    def accessor(
        self,
        values: Sequence[Sequence[float | int]] | Sequence[float | int],
        component_type: int,
        accessor_type: str,
        *,
        target: int | None = None,
        include_bounds: bool = False,
    ) -> int:
        self._align()
        offset = len(self.data)
        dimensions = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[accessor_type]
        code, size = {
            5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)
        }[component_type]
        flat: list[float | int] = []
        if dimensions == 1:
            flat.extend(values)  # type: ignore[arg-type]
            count = len(values)
        else:
            for value in values:  # type: ignore[assignment]
                if len(value) != dimensions:  # type: ignore[arg-type]
                    raise ValueError(f"{accessor_type} requires {dimensions} components")
                flat.extend(value)  # type: ignore[arg-type]
            count = len(values)
        self.data.extend(struct.pack("<" + code * len(flat), *flat))
        view: dict[str, object] = {"buffer": 0, "byteOffset": offset, "byteLength": len(flat) * size}
        if target is not None:
            view["target"] = target
        views: list[dict[str, object]] = self.gltf["bufferViews"]  # type: ignore[assignment]
        view_index = len(views)
        views.append(view)
        accessor: dict[str, object] = {
            "bufferView": view_index,
            "componentType": component_type,
            "count": count,
            "type": accessor_type,
        }
        if include_bounds and count:
            grouped = [flat[i * dimensions : (i + 1) * dimensions] for i in range(count)]
            accessor["min"] = [min(value[axis] for value in grouped) for axis in range(dimensions)]
            accessor["max"] = [max(value[axis] for value in grouped) for axis in range(dimensions)]
        accessors: list[dict[str, object]] = self.gltf["accessors"]  # type: ignore[assignment]
        index = len(accessors)
        accessors.append(accessor)
        return index


def documents(text: str) -> list[tuple[int, int, str]]:
    return unity_mesh._documents(text)


def yaml_vector(text: str, key: str, count: int, default: tuple[float, ...]) -> tuple[float, ...]:
    return unity_mesh._yaml_vector(text, key, count, default)


def parse_transform_hierarchy(prefab: Path) -> tuple[list[TransformNode], int]:
    text = prefab.read_text(encoding="utf-8-sig")
    docs = documents(text)
    names: dict[int, str] = {}
    raw: dict[int, tuple[int, int, tuple[float, ...], tuple[float, ...], tuple[float, ...]]] = {}
    transform_for_game: dict[int, int] = {}
    for class_id, file_id, body in docs:
        if class_id == 1:
            match = re.search(r"^\s*m_Name:\s*(.*?)\s*$", body, re.MULTILINE)
            if match:
                names[file_id] = match.group(1)
        elif class_id == 4:
            game_match = re.search(r"m_GameObject:\s*\{fileID:\s*(\d+)\}", body)
            father_match = re.search(r"m_Father:\s*\{fileID:\s*(\d+)\}", body)
            game_id = int(game_match.group(1)) if game_match else 0
            father_id = int(father_match.group(1)) if father_match else 0
            raw[file_id] = (
                game_id,
                father_id,
                yaml_vector(body, "m_LocalPosition", 3, (0.0, 0.0, 0.0)),
                yaml_vector(body, "m_LocalRotation", 4, (0.0, 0.0, 0.0, 1.0)),
                yaml_vector(body, "m_LocalScale", 3, (1.0, 1.0, 1.0)),
            )
            transform_for_game[game_id] = file_id
    nodes: list[TransformNode] = []
    for transform_id, (game_id, father, translation, rotation, scale) in raw.items():
        nodes.append(TransformNode(transform_id, game_id, names.get(game_id, f"Bone_{game_id}"), father, translation, rotation, scale))
    by_id = {node.transform_id: node for node in nodes}
    roots = [node for node in nodes if node.father_id == 0]
    if len(roots) != 1:
        raise ValueError(f"Expected one skeleton root in {prefab}, found {len(roots)}")

    def assign_path(node: TransformNode, parent_path: str) -> None:
        node.path = f"{parent_path}/{node.name}" if parent_path else node.name
        for child in nodes:
            if child.father_id == node.transform_id:
                assign_path(child, node.path)

    assign_path(roots[0], "")
    return nodes, roots[0].transform_id


def parse_skinned_renderer(prefab: Path) -> SkinnedRenderer:
    text = prefab.read_text(encoding="utf-8-sig")
    docs = documents(text)
    names: dict[int, str] = {}
    transform_game: dict[int, int] = {}
    renderer_body = ""
    renderer_game = 0
    for class_id, file_id, body in docs:
        if class_id == 1:
            match = re.search(r"^\s*m_Name:\s*(.*?)\s*$", body, re.MULTILINE)
            if match:
                names[file_id] = match.group(1)
        elif class_id == 4:
            game_match = re.search(r"m_GameObject:\s*\{fileID:\s*(\d+)\}", body)
            if game_match:
                transform_game[file_id] = int(game_match.group(1))
        elif class_id == 137:
            renderer_body = body
            game_match = re.search(r"m_GameObject:\s*\{fileID:\s*(\d+)\}", body)
            renderer_game = int(game_match.group(1)) if game_match else 0
    if not renderer_body:
        raise ValueError(f"No SkinnedMeshRenderer in {prefab}")
    mesh_match = re.search(r"m_Mesh:\s*\{[^}]*guid:\s*([0-9a-f]{32})", renderer_body)
    if not mesh_match:
        raise ValueError(f"No mesh GUID in {prefab}")
    bones_match = re.search(r"^\s*m_Bones:\s*$([\s\S]*?)^\s*m_BlendShapeWeights:", renderer_body, re.MULTILINE)
    if not bones_match:
        raise ValueError(f"No bone list in {prefab}")
    bone_ids = [int(value) for value in re.findall(r"fileID:\s*(\d+)", bones_match.group(1))]
    bone_names = [names.get(transform_game.get(value, 0), f"MissingBone_{value}") for value in bone_ids]
    return SkinnedRenderer(
        names.get(renderer_game, prefab.stem),
        mesh_match.group(1),
        unity_mesh._material_guids(renderer_body),
        bone_names,
    )


def parse_skin(mesh_path: Path, vertex_count: int) -> tuple[list[tuple[float, ...]], list[tuple[int, ...]], list[tuple[float, ...]]]:
    text = mesh_path.read_text(encoding="utf-8-sig")
    bind_section = re.search(r"^\s*m_BindPose:\s*$([\s\S]*?)^\s*m_BoneNameHashes:", text, re.MULTILINE)
    if not bind_section:
        raise ValueError(f"No bind poses in {mesh_path}")
    # Parse one Unity Matrix4x4 at a time. Python's regular expression engine has
    # no \G anchor, so keeping this line-oriented also makes old YAML variants
    # less brittle.
    matrices: list[tuple[float, ...]] = []
    current: dict[str, float] = {}
    for line in bind_section.group(1).splitlines():
        first = re.match(r"\s*-\s+(e\d\d):\s*([-+0-9.eE]+)", line)
        field = re.match(r"\s+(e\d\d):\s*([-+0-9.eE]+)", line)
        match = first or field
        if not match:
            continue
        if first and current:
            matrices.append(tuple(current[f"e{row}{column}"] for row in range(4) for column in range(4)))
            current = {}
        current[match.group(1)] = float(match.group(2))
    if current:
        matrices.append(tuple(current[f"e{row}{column}"] for row in range(4) for column in range(4)))

    # Unity 4 writes m_Skin after the index buffer and before m_VertexData;
    # some neighbouring releases put a different field after it. Stop at the
    # next top-level Mesh property instead of depending on one exact version.
    skin_section = re.search(r"^  m_Skin:\s*$([\s\S]*?)(?=^  m_[A-Za-z][^\r\n]*:)", text, re.MULTILINE)
    if skin_section is None:
        raise ValueError(f"No skin weights in {mesh_path}")
    entries = re.split(r"(?=^\s*-\s+weight\[0\]:)", skin_section.group(1), flags=re.MULTILINE)
    joints: list[tuple[int, ...]] = []
    weights: list[tuple[float, ...]] = []
    for entry in entries:
        raw_weights = {int(i): float(value) for i, value in re.findall(r"weight\[(\d)\]:\s*([-+0-9.eE]+)", entry)}
        raw_joints = {int(i): int(value) for i, value in re.findall(r"boneIndex\[(\d)\]:\s*(\d+)", entry)}
        if len(raw_weights) == 4 and len(raw_joints) == 4:
            value = tuple(raw_weights[i] for i in range(4))
            total = sum(value)
            weights.append(tuple(component / total for component in value) if total > 1e-8 else (1.0, 0.0, 0.0, 0.0))
            joints.append(tuple(raw_joints[i] for i in range(4)))
    if len(joints) != vertex_count:
        raise ValueError(f"{mesh_path}: {len(joints)} skin entries for {vertex_count} vertices")
    return matrices, joints, weights


def convert_matrix(matrix: Sequence[float]) -> tuple[float, ...]:
    rows = [list(matrix[row * 4 : row * 4 + 4]) for row in range(4)]
    signs = (1.0, 1.0, -1.0, 1.0)
    converted = [[rows[row][column] * signs[row] * signs[column] for column in range(4)] for row in range(4)]
    # glTF stores matrices column-major.
    return tuple(converted[row][column] for column in range(4) for row in range(4))


def matrix_multiply(left: Sequence[float], right: Sequence[float]) -> tuple[float, ...]:
    return tuple(
        sum(left[row * 4 + pivot] * right[pivot * 4 + column] for pivot in range(4))
        for row in range(4) for column in range(4)
    )


def invert_matrix(matrix: Sequence[float]) -> tuple[float, ...]:
    augmented = [
        [float(matrix[row * 4 + column]) for column in range(4)]
        + [1.0 if row == column else 0.0 for column in range(4)]
        for row in range(4)
    ]
    for column in range(4):
        pivot = max(range(column, 4), key=lambda row: abs(augmented[row][column]))
        if abs(augmented[pivot][column]) < 1e-10:
            raise ValueError("Cannot invert singular transform")
        augmented[column], augmented[pivot] = augmented[pivot], augmented[column]
        divisor = augmented[column][column]
        augmented[column] = [value / divisor for value in augmented[column]]
        for row in range(4):
            if row == column:
                continue
            factor = augmented[row][column]
            augmented[row] = [
                augmented[row][index] - factor * augmented[column][index]
                for index in range(8)
            ]
    return tuple(augmented[row][column] for row in range(4) for column in range(4, 8))


def trs_matrix(
    translation: Sequence[float], rotation: Sequence[float], scale: Sequence[float]
) -> tuple[float, ...]:
    x, y, z, w = (float(value) for value in rotation)
    length = math.sqrt(x * x + y * y + z * z + w * w)
    x, y, z, w = x / length, y / length, z / length, w / length
    sx, sy, sz = (float(value) for value in scale)
    rotation_rows = (
        (1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w)),
        (2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w)),
        (2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)),
    )
    return (
        rotation_rows[0][0] * sx, rotation_rows[0][1] * sy, rotation_rows[0][2] * sz, float(translation[0]),
        rotation_rows[1][0] * sx, rotation_rows[1][1] * sy, rotation_rows[1][2] * sz, float(translation[1]),
        rotation_rows[2][0] * sx, rotation_rows[2][1] * sy, rotation_rows[2][2] * sz, float(translation[2]),
        0.0, 0.0, 0.0, 1.0,
    )


def convert_translation(value: Sequence[float]) -> tuple[float, float, float]:
    return float(value[0]), float(value[1]), -float(value[2])


def convert_rotation(value: Sequence[float]) -> tuple[float, float, float, float]:
    quaternion = (-float(value[0]), -float(value[1]), float(value[2]), float(value[3]))
    length = math.sqrt(sum(component * component for component in quaternion))
    return tuple(component / length for component in quaternion)  # type: ignore[return-value]


def parse_curve_section(text: str, heading: str, dimensions: int) -> dict[str, list[tuple[float, tuple[float, ...]]]]:
    start = re.search(rf"^  {re.escape(heading)}:\s*$", text, re.MULTILINE)
    if not start:
        return {}
    next_heading = re.search(r"^  m_[A-Za-z].*:\s*(?:\[\])?\s*$", text[start.end() :], re.MULTILINE)
    end = start.end() + next_heading.start() if next_heading else len(text)
    section = text[start.end() : end]
    entries = re.split(r"(?=^  - curve:\s*$)", section, flags=re.MULTILINE)
    result: dict[str, list[tuple[float, tuple[float, ...]]]] = {}
    component_names = "xyzw"[:dimensions]
    for entry in entries:
        path_match = re.search(r"^    path:\s*(.*?)\s*$", entry, re.MULTILINE)
        if not path_match:
            continue
        keys: list[tuple[float, tuple[float, ...]]] = []
        pattern = re.compile(r"^      - time:\s*([-+0-9.eE]+)\s*$\s*^        value:\s*\{([^}]+)\}", re.MULTILINE)
        for time_value, fields in pattern.findall(entry):
            parsed = {name: float(raw) for name, raw in re.findall(r"([xyzw]):\s*([-+0-9.eE]+)", fields)}
            keys.append((float(time_value), tuple(parsed[name] for name in component_names)))
        if keys:
            result[path_match.group(1)] = keys
    return result


def parse_animation(path: Path) -> dict[str, dict[str, list[tuple[float, tuple[float, ...]]]]]:
    text = path.read_text(encoding="utf-8-sig")
    return {
        "rotation": parse_curve_section(text, "m_RotationCurves", 4),
        "translation": parse_curve_section(text, "m_PositionCurves", 3),
        "scale": parse_curve_section(text, "m_ScaleCurves", 3),
    }


def copy_upscaled_texture(source: Path, destination: Path) -> None:
    """Copy a Unity texture into the restoration's 2x RGBA asset corpus."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.suffix.lower() != ".png" or TEXTURE_EXPORT_SCALE == 1:
        if source.resolve() != destination.resolve():
            shutil.copy2(source, destination)
        return
    with Image.open(source) as image:
        rgba = image.convert("RGBA")
        target_size = (
            rgba.width * TEXTURE_EXPORT_SCALE,
            rgba.height * TEXTURE_EXPORT_SCALE,
        )
        rgba.resize(target_size, Image.Resampling.LANCZOS).save(
            destination,
            format="PNG",
            optimize=True,
        )


def add_material(
    gltf: dict[str, object],
    material_info: unity_mesh.MaterialInfo,
    output_dir: Path,
    image_cache: dict[Path, int],
    image_uri_cache: dict[str, int],
    *,
    material_prefix: str = "",
    texture_directory: str = "armor_textures",
) -> int:
    material_name = material_info.name
    if material_prefix:
        material_name = f"{material_prefix}_{material_name}"
    material: dict[str, object] = {
        "name": material_name,
        "pbrMetallicRoughness": {
            "baseColorFactor": list(material_info.color),
            "metallicFactor": 0.08,
            "roughnessFactor": 0.62,
        },
        "doubleSided": True,
    }
    source = material_info.diffuse_source
    if source and source.is_file():
        source_key = source.resolve()
        if source_key not in image_cache:
            # The legacy project stores many unrelated textures as body.png,
            # head.png, and similar basenames. Content-addressing the copied
            # name keeps the glTF deterministic while preventing later armor
            # variants from silently overwriting an earlier variant's image.
            digest = hashlib.sha256(source.read_bytes()).hexdigest()[:12]
            safe_stem = unity_mesh._sanitize_name(source.stem)
            safe_name = f"{safe_stem}_{digest}_2x{source.suffix.lower()}"
            relative_destination = Path(texture_directory) / safe_name
            relative_uri = relative_destination.as_posix()
            if relative_uri in image_uri_cache:
                texture_index = image_uri_cache[relative_uri]
            else:
                destination = output_dir / relative_destination
                copy_upscaled_texture(source, destination)
                images: list[dict[str, object]] = gltf["images"]  # type: ignore[assignment]
                textures: list[dict[str, object]] = gltf["textures"]  # type: ignore[assignment]
                image_index = len(images)
                images.append({"uri": relative_uri})
                texture_index = len(textures)
                textures.append({"source": image_index, "sampler": 0})
                image_uri_cache[relative_uri] = texture_index
            image_cache[source_key] = texture_index
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": image_cache[source_key]}  # type: ignore[index]
    materials: list[dict[str, object]] = gltf["materials"]  # type: ignore[assignment]
    index = len(materials)
    materials.append(material)
    return index


def load_armor_parts(
    assets: Path,
    guid_index: unity_mesh.GuidIndex,
    canonical_bones: set[str],
) -> tuple[dict[tuple[str, int], ArmorPartData], dict[str, list[str]]]:
    part_data: dict[tuple[str, int], ArmorPartData] = {}
    ignored_zero_weight_bones: dict[str, list[str]] = {}
    for armor_id in range(ARMOR_VARIANT_COUNT):
        source_directory = assets / "Resources" / "avatar" / f"{armor_id + 1:02d}"
        for part_name in ARMOR_PART_NAMES:
            prefab = source_directory / f"{part_name}.prefab"
            renderer = parse_skinned_renderer(prefab)
            mesh_path = guid_index.resolve(renderer.mesh_guid)
            mesh = unity_mesh.parse_mesh(mesh_path)
            bind_poses, joints, weights = parse_skin(mesh_path, len(mesh.positions))
            if len(bind_poses) != len(renderer.bone_names):
                raise ValueError(
                    f"{prefab}: {len(bind_poses)} bind poses for "
                    f"{len(renderer.bone_names)} bones"
                )

            unknown_indices = {
                index for index, bone_name in enumerate(renderer.bone_names)
                if bone_name not in canonical_bones
            }
            weighted_unknowns: set[str] = set()
            for vertex_joints, vertex_weights in zip(joints, weights):
                for joint, weight in zip(vertex_joints, vertex_weights):
                    if joint >= len(renderer.bone_names):
                        raise ValueError(f"{prefab}: joint index {joint} is outside its bone list")
                    if joint in unknown_indices and weight > 1e-6:
                        weighted_unknowns.add(renderer.bone_names[joint])
            if weighted_unknowns:
                raise ValueError(
                    f"{prefab}: non-canonical bones carry skin weights: "
                    f"{', '.join(sorted(weighted_unknowns))}"
                )
            if unknown_indices:
                node_name = f"Armor{part_name}_{armor_id:02d}"
                ignored_zero_weight_bones[node_name] = sorted(
                    renderer.bone_names[index] for index in unknown_indices
                )

            part_data[(part_name, armor_id)] = ArmorPartData(
                armor_id,
                part_name,
                prefab,
                renderer,
                mesh_path,
                mesh,
                bind_poses,
                joints,
                weights,
            )
    return part_data, ignored_zero_weight_bones


def export_bags(
    assets: Path,
    output_directory: Path,
    guid_index: unity_mesh.GuidIndex,
) -> dict[str, object]:
    output_directory.mkdir(parents=True, exist_ok=True)
    bag_records: list[dict[str, object]] = []
    for bag_id in range(BAG_VARIANT_COUNT):
        prefab = assets / "Resources" / "avatar" / f"{bag_id + 1:02d}" / "Bag.prefab"
        renderers = unity_mesh.parse_prefab_renderers(prefab)
        if not renderers:
            raise ValueError(f"{prefab}: no renderable bag geometry")
        pieces: list[unity_mesh.ObjPiece] = []
        for renderer_index, renderer in enumerate(renderers):
            mesh_path = guid_index.resolve(renderer.mesh_guid)
            materials = [
                unity_mesh.parse_material(guid_index.resolve(guid), guid_index)
                for guid in renderer.material_guids
            ]
            if not materials:
                materials = [unity_mesh.fallback_material(renderer.name)]
            pieces.append(unity_mesh.ObjPiece(
                f"ArmorBag_{bag_id:02d}_{renderer_index:02d}_{unity_mesh._sanitize_name(renderer.name)}",
                unity_mesh.parse_mesh(mesh_path),
                renderer.transform,
                materials,
            ))

        bag_name = f"ArmorBag_{bag_id:02d}"
        bag_directory = output_directory / bag_name
        obj_path = bag_directory / f"{bag_name}.obj"
        result = unity_mesh.write_obj(obj_path, pieces)
        for texture_name in result["textures"]:
            texture_path = bag_directory / str(texture_name)
            # write_obj copied the original source image. Upscale from that
            # fresh copy once so rerunning the exporter is idempotent.
            with Image.open(texture_path) as image:
                rgba = image.convert("RGBA")
                rgba.resize(
                    (rgba.width * TEXTURE_EXPORT_SCALE, rgba.height * TEXTURE_EXPORT_SCALE),
                    Image.Resampling.LANCZOS,
                ).save(texture_path, format="PNG", optimize=True)
        validation = unity_mesh.validate_obj(obj_path)
        unity_scale = BAG_SIZE_OVERRIDES.get(bag_id, 1.0)
        bag_records.append({
            "id": bag_id,
            "name": bag_name,
            "source_folder": f"{bag_id + 1:02d}",
            "obj": obj_path.relative_to(output_directory).as_posix(),
            "renderer_count": len(renderers),
            "renderer_kinds": [renderer.kind for renderer in renderers],
            "vertices": validation["vertices"],
            "faces": validation["faces"],
            "textures": result["textures"],
            "unity_scale": unity_scale,
            "default_body_scale": unity_scale * 0.8,
            "body_05_scale": unity_scale,
            "animated_in_unity": bag_id in ANIMATED_UNITY_BAGS,
            "static_geometry_only": True,
        })

    manifest = {
        "naming": "ArmorBag_XX uses the zero-based Unity bag ID",
        "count": len(bag_records),
        "special_animation_limit": (
            "Unity bag IDs 15 and 23 use FlyBagAnimationScript. Their recovered "
            "OBJ assets preserve all renderable geometry but not the legacy script animation."
        ),
        "bags": bag_records,
    }
    manifest_path = output_directory / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"manifest": str(manifest_path), **manifest}


def export(project_root: Path, output_path: Path) -> dict[str, object]:
    assets = project_root / "Assets"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    guid_index = unity_mesh.GuidIndex(assets)
    skeleton_nodes, root_transform_id = parse_transform_hierarchy(
        assets / "Resources" / "avatar" / "Bone.prefab"
    )

    # Bone.prefab stores the non-deforming weapon helper in a construction
    # pose. Clips which animate it override that pose, but idle_rifle omits
    # constant tracks, leaving an attached weapon aimed almost vertically.
    # The original runtime prefab uses the idle-rifle socket transform as the
    # default. Preserve that authored rest transform in the exported skeleton.
    idle_nodes, _idle_root = parse_transform_hierarchy(
        assets / "Resources" / "avatar" / "animation" / "idle_rifle.prefab"
    )
    idle_by_name = {node.name: node for node in idle_nodes}
    for node in skeleton_nodes:
        if node.name == "r hand gun" and node.name in idle_by_name:
            reference = idle_by_name[node.name]
            node.translation = reference.translation
            node.rotation = reference.rotation
            node.scale = reference.scale
    by_transform = {node.transform_id: node for node in skeleton_nodes}

    gltf: dict[str, object] = {
        "asset": {"version": "2.0", "generator": "Star Warfare Unity YAML avatar exporter"},
        "extensionsUsed": ["KHR_node_visibility"],
        "extensionsRequired": ["KHR_node_visibility"],
        "scene": 0,
        "scenes": [{"nodes": []}],
        "nodes": [], "meshes": [], "skins": [], "animations": [],
        "buffers": [], "bufferViews": [], "accessors": [],
        "materials": [], "images": [], "textures": [],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
    }
    nodes: list[dict[str, object]] = gltf["nodes"]  # type: ignore[assignment]
    for node in skeleton_nodes:
        node.node_index = len(nodes)
        nodes.append({
            "name": node.name,
            "translation": list(convert_translation(node.translation)),
            "rotation": list(convert_rotation(node.rotation)),
            "scale": list(node.scale),
        })
    for node in skeleton_nodes:
        children = [child.node_index for child in skeleton_nodes if child.father_id == node.transform_id]
        if children:
            nodes[node.node_index]["children"] = children
    root_node = by_transform[root_transform_id]
    gltf["scenes"][0]["nodes"].append(root_node.node_index)  # type: ignore[index]
    path_to_node = {
        node.path.removeprefix(root_node.name + "/"): node.node_index
        for node in skeleton_nodes
    }
    name_to_node = {node.name: node.node_index for node in skeleton_nodes}
    bip_node = name_to_node["Bip01"]

    buffer = BufferBuilder(gltf)
    image_cache: dict[Path, int] = {}
    image_uri_cache: dict[str, int] = {}
    material_cache: dict[Path, int] = {}
    mesh_nodes: list[int] = []

    canonical_bones = set(name_to_node)
    part_data, ignored_zero_weight_bones = load_armor_parts(
        assets,
        guid_index,
        canonical_bones,
    )

    # Build the canonical inverse-bind fallback from armor ID 0. Every variant
    # keeps its own authored bind poses for the bones it uses; this table only
    # fills attachment/end bones that Unity omits from a renderer's bone list.
    master_inverse_bind: dict[str, tuple[float, ...]] = {}
    for part_name in ARMOR_PART_NAMES:
        data = part_data[(part_name, 0)]
        for bone_name, bind_pose in zip(data.renderer.bone_names, data.bind_poses):
            if bone_name in canonical_bones:
                master_inverse_bind.setdefault(bone_name, bind_pose)

    skeleton_root_path = f"{root_node.name}/Bip01"
    complete_bone_names = [
        node.name for node in skeleton_nodes if node.path.startswith(skeleton_root_path)
    ]
    for node in skeleton_nodes:
        if node.name not in complete_bone_names or node.name in master_inverse_bind:
            continue
        parent = by_transform[node.father_id]
        if parent.name not in master_inverse_bind:
            raise ValueError(
                f"Cannot derive bind pose for {node.name}: parent {parent.name} is missing"
            )
        inverse_local = invert_matrix(trs_matrix(node.translation, node.rotation, node.scale))
        master_inverse_bind[node.name] = matrix_multiply(
            inverse_local,
            master_inverse_bind[parent.name],
        )

    for armor_id in range(ARMOR_VARIANT_COUNT):
        for part_name in ARMOR_PART_NAMES:
            data = part_data[(part_name, armor_id)]
            renderer = data.renderer
            mesh = data.mesh
            node_name = f"Armor{part_name}_{armor_id:02d}"

            # Unity's AvatarBuilder binds renderer bones to the canonical Bone
            # prefab by name. A handful of prefabs list unused helper bones not
            # present in Bone.prefab; load_armor_parts proves their weights are
            # zero, so mapping those joint slots to Bip01 preserves JOINTS_0
            # indices without expanding or destabilising the 28-bone import.
            attachment_bones = [
                name for name in complete_bone_names if name not in renderer.bone_names
            ]
            skin_bone_names = renderer.bone_names + attachment_bones
            skin_joints = [name_to_node.get(name, bip_node) for name in skin_bone_names]
            inverse_bind_by_name = master_inverse_bind.copy()
            inverse_bind_by_name.update(zip(renderer.bone_names, data.bind_poses))
            expanded_bind_poses = [inverse_bind_by_name[name] for name in skin_bone_names]
            skin_index = len(gltf["skins"])  # type: ignore[arg-type]
            inverse_accessor = buffer.accessor(
                [convert_matrix(matrix) for matrix in expanded_bind_poses],
                5126,
                "MAT4",
            )
            gltf["skins"].append({  # type: ignore[union-attr]
                "name": f"{node_name}Skin",
                "inverseBindMatrices": inverse_accessor,
                "joints": skin_joints,
                "skeleton": bip_node,
            })

            positions = [convert_translation(value) for value in mesh.positions]
            faces = [
                tuple(submesh.indices[offset : offset + 3])
                for submesh in mesh.submeshes
                for offset in range(0, len(submesh.indices), 3)
            ]
            reversed_faces = [(face[0], face[2], face[1]) for face in faces]
            normals = (
                [convert_translation(value) for value in mesh.normals]
                if mesh.normals
                else unity_mesh._generated_normals(positions, reversed_faces)
            )
            uvs = [
                (float(value[0]), 1.0 - float(value[1]))
                for value in (mesh.uvs or [(0.0, 0.0)] * len(positions))
            ]
            attributes = {
                "POSITION": buffer.accessor(
                    positions, 5126, "VEC3", target=34962, include_bounds=True
                ),
                "NORMAL": buffer.accessor(normals, 5126, "VEC3", target=34962),
                "TEXCOORD_0": buffer.accessor(uvs, 5126, "VEC2", target=34962),
                "JOINTS_0": buffer.accessor(data.joints, 5123, "VEC4", target=34962),
                "WEIGHTS_0": buffer.accessor(data.weights, 5126, "VEC4", target=34962),
            }
            part_materials: list[int] = []
            for guid in renderer.material_guids:
                material_path = guid_index.resolve(guid)
                if material_path not in material_cache:
                    material_cache[material_path] = add_material(
                        gltf,
                        unity_mesh.parse_material(material_path, guid_index),
                        output_path.parent,
                        image_cache,
                        image_uri_cache,
                        material_prefix=node_name,
                    )
                part_materials.append(material_cache[material_path])
            if not part_materials:
                fallback = unity_mesh.fallback_material(node_name)
                part_materials.append(add_material(
                    gltf,
                    fallback,
                    output_path.parent,
                    image_cache,
                    image_uri_cache,
                    material_prefix=node_name,
                ))
            primitives: list[dict[str, object]] = []
            for submesh_index, submesh in enumerate(mesh.submeshes):
                indices: list[int] = []
                for offset in range(0, len(submesh.indices), 3):
                    first, second, third = submesh.indices[offset : offset + 3]
                    indices.extend((first, third, second))
                index_accessor = buffer.accessor(indices, 5125, "SCALAR", target=34963)
                primitives.append({
                    "attributes": attributes,
                    "indices": index_accessor,
                    "material": part_materials[min(submesh_index, len(part_materials) - 1)],
                    "mode": 4,
                })
            mesh_index = len(gltf["meshes"])  # type: ignore[arg-type]
            gltf["meshes"].append({  # type: ignore[union-attr]
                "name": node_name,
                "primitives": primitives,
            })
            mesh_node_index = len(nodes)
            mesh_node: dict[str, object] = {
                "name": node_name,
                "mesh": mesh_index,
                "skin": skin_index,
                "extras": {
                    "armor_part": part_name.lower(),
                    "armor_id": armor_id,
                    "source_folder": f"{armor_id + 1:02d}",
                },
            }
            if armor_id != 0:
                mesh_node["extensions"] = {"KHR_node_visibility": {"visible": False}}
            nodes.append(mesh_node)
            mesh_nodes.append(mesh_node_index)

    nodes[root_node.node_index].setdefault("children", []).extend(mesh_nodes)  # type: ignore[union-attr]

    missing_paths: set[str] = set()
    for animation_name in ANIMATION_NAMES:
        animation_path = assets / "AnimationClip" / f"{animation_name}.anim"
        if not animation_path.is_file():
            continue
        curves = parse_animation(animation_path)
        animation: dict[str, object] = {
            "name": animation_name,
            "samplers": [],
            "channels": [],
        }
        for target_path, gltf_path in (
            ("translation", "translation"),
            ("rotation", "rotation"),
            ("scale", "scale"),
        ):
            for bone_path, keys in curves[target_path].items():
                node_index = path_to_node.get(bone_path)
                if node_index is None:
                    missing_paths.add(bone_path)
                    continue
                times = [key[0] for key in keys]
                values: list[tuple[float, ...]] = []
                previous_rotation: tuple[float, ...] | None = None
                for _, raw_value in keys:
                    if target_path == "translation":
                        value = convert_translation(raw_value)
                    elif target_path == "rotation":
                        value = convert_rotation(raw_value)
                        if (
                            previous_rotation is not None
                            and sum(a * b for a, b in zip(previous_rotation, value)) < 0.0
                        ):
                            value = tuple(-component for component in value)
                        previous_rotation = value
                    else:
                        value = tuple(float(component) for component in raw_value)
                    values.append(value)
                input_accessor = buffer.accessor(
                    times,
                    5126,
                    "SCALAR",
                    include_bounds=True,
                )
                output_accessor = buffer.accessor(
                    values,
                    5126,
                    "VEC4" if target_path == "rotation" else "VEC3",
                )
                samplers: list[dict[str, object]] = animation["samplers"]  # type: ignore[assignment]
                sampler_index = len(samplers)
                samplers.append({
                    "input": input_accessor,
                    "output": output_accessor,
                    "interpolation": "LINEAR",
                })
                animation["channels"].append({  # type: ignore[union-attr]
                    "sampler": sampler_index,
                    "target": {"node": node_index, "path": gltf_path},
                })
        if animation["channels"]:
            gltf["animations"].append(animation)  # type: ignore[union-attr]

    binary_name = output_path.with_suffix(".bin").name
    gltf["buffers"] = [{"uri": binary_name, "byteLength": len(buffer.data)}]
    gltf["asset"]["extras"] = {  # type: ignore[index]
        "buffer_sha256": hashlib.sha256(buffer.data).hexdigest(),
        "armor_variant_naming": "Armor{Head|Body|Hand|Foot}_XX; XX is zero-based",
        "default_visible_armor_id": 0,
    }
    output_path.with_suffix(".bin").write_bytes(buffer.data)
    output_path.write_text(
        json.dumps(gltf, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    bag_report = export_bags(
        assets,
        output_path.parent / "bags",
        guid_index,
    )
    return {
        "output": str(output_path),
        "binary_bytes": len(buffer.data),
        "source_bones": len(skeleton_nodes),
        "expected_godot_bones": 28,
        "meshes": len(gltf["meshes"]),  # type: ignore[arg-type]
        "armor_parts": list(ARMOR_PART_NAMES),
        "armor_variants_per_part": ARMOR_VARIANT_COUNT,
        "armor_mesh_naming": "Armor{Head|Body|Hand|Foot}_XX",
        "default_visible_armor_id": 0,
        "textures": [image["uri"] for image in gltf["images"]],  # type: ignore[index]
        "animations": [animation["name"] for animation in gltf["animations"]],  # type: ignore[index]
        "ignored_zero_weight_bones": ignored_zero_weight_bones,
        "unmatched_animation_paths": sorted(missing_paths),
        "bags": bag_report,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True, help="Original Unity project root")
    parser.add_argument("--output", type=Path, required=True, help="Output .gltf path")
    args = parser.parse_args()
    report = export(args.project_root.resolve(), args.output.resolve())
    report_path = args.output.with_name("avatar_export_report.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
