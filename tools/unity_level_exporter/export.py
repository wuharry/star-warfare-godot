#!/usr/bin/env python3
"""Export the original Star Warfare Unity levels into Godot-friendly assets.

The legacy project contains fully expanded Unity YAML scenes.  This tool reads
those scenes without opening or modifying the Unity project, bakes every static
renderer into an OBJ, and preserves the original physics/spawn metadata in JSON.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

from PIL import Image


CONVERTER_DIR = Path(__file__).resolve().parents[1] / "yaml_mesh_converter"
sys.path.insert(0, str(CONVERTER_DIR))
import convert as legacy  # noqa: E402


LEVEL_NUMBERS = (1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21)
MARKER_TAGS = (
    "Respawn",
    "EnemySpawnPoint",
    "BossSpawnPoint",
    "PlayerSpawnInBoss",
    "WayPoint",
    "FlagSpawn",
    "GiftSpawn",
    "Grave",
)
WAYPOINT_SCRIPT_GUID = "e6eb32104f095b444bc56c039c8cdd7f"
TEXTURE_EXPORT_SCALE = 2
MAX_TEXTURE_DIMENSION = 4096


@dataclass
class GameObjectInfo:
    name: str
    tag: str
    active: bool
    layer: int


@dataclass
class TransformInfo:
    game_object: int
    father: int
    local: tuple[tuple[float, ...], ...]


@dataclass
class PrimitiveCollider:
    kind: str
    game_object: int
    center: tuple[float, float, float]
    size: tuple[float, float, float] = (1.0, 1.0, 1.0)
    radius: float = 0.5
    height: float = 2.0
    direction: int = 1


@dataclass
class RendererInfo:
    kind: str
    game_object: int
    direct_mesh: str
    material_guids: list[str]
    first_submesh: int
    submesh_count: int


@dataclass
class SceneData:
    path: Path
    game_objects: dict[int, GameObjectInfo] = field(default_factory=dict)
    transforms: dict[int, TransformInfo] = field(default_factory=dict)
    transform_for_game_object: dict[int, int] = field(default_factory=dict)
    renderers: list[RendererInfo] = field(default_factory=list)
    mesh_filters: dict[int, str] = field(default_factory=dict)
    primitive_colliders: list[PrimitiveCollider] = field(default_factory=list)
    mesh_colliders: list[tuple[int, str, bool]] = field(default_factory=list)
    waypoint_scripts: dict[int, tuple[int, list[int]]] = field(default_factory=dict)
    render_settings: dict[str, object] = field(default_factory=dict)


def _bool_scalar(text: str, key: str, default: bool = True) -> bool:
    match = re.search(rf"^\s*{re.escape(key)}:\s*(\d+)\s*$", text, re.MULTILINE)
    return bool(int(match.group(1))) if match else default


def _int_scalar(text: str, key: str, default: int = 0) -> int:
    match = re.search(rf"^\s*{re.escape(key)}:\s*(-?\d+)\s*$", text, re.MULTILINE)
    return int(match.group(1)) if match else default


def _float_scalar(text: str, key: str, default: float = 0.0) -> float:
    match = re.search(rf"^\s*{re.escape(key)}:\s*([-+0-9.eE]+)\s*$", text, re.MULTILINE)
    return float(match.group(1)) if match else default


def _yaml_color(text: str, key: str, default: tuple[float, ...]) -> tuple[float, ...]:
    match = re.search(rf"^\s*{re.escape(key)}:\s*\{{([^}}]+)\}}", text, re.MULTILINE)
    if not match:
        return default
    values = {
        field_name: float(raw)
        for field_name, raw in re.findall(r"([rgba]):\s*([-+0-9.eE]+)", match.group(1))
    }
    return tuple(values.get(name, default[index]) for index, name in enumerate("rgba"))


def _game_object_reference(text: str) -> int:
    match = re.search(r"m_GameObject:\s*\{fileID:\s*(\d+)\}", text)
    return int(match.group(1)) if match else 0


def parse_scene(path: Path) -> SceneData:
    text = path.read_text(encoding="utf-8-sig")
    scene = SceneData(path)
    for class_id, file_id, body in legacy._documents(text):
        game_object = _game_object_reference(body)
        if class_id == 1:
            name_match = re.search(r"^\s*m_Name:\s*(.*?)\s*$", body, re.MULTILINE)
            tag_match = re.search(r"^\s*m_TagString:\s*(.*?)\s*$", body, re.MULTILINE)
            scene.game_objects[file_id] = GameObjectInfo(
                name_match.group(1) if name_match else f"GameObject_{file_id}",
                tag_match.group(1) if tag_match else "Untagged",
                _bool_scalar(body, "m_IsActive"),
                _int_scalar(body, "m_Layer"),
            )
        elif class_id == 4:
            father_match = re.search(r"m_Father:\s*\{fileID:\s*(\d+)\}", body)
            father = int(father_match.group(1)) if father_match else 0
            position = legacy._yaml_vector(body, "m_LocalPosition", 3, (0.0, 0.0, 0.0))
            rotation = legacy._yaml_vector(body, "m_LocalRotation", 4, (0.0, 0.0, 0.0, 1.0))
            scale = legacy._yaml_vector(body, "m_LocalScale", 3, (1.0, 1.0, 1.0))
            scene.transforms[file_id] = TransformInfo(
                game_object, father, legacy.local_matrix(position, rotation, scale)
            )
            scene.transform_for_game_object[game_object] = file_id
        elif class_id == 33:
            mesh_guid = legacy._reference_guid(body, "m_Mesh")
            if mesh_guid and set(mesh_guid) != {"0"}:
                scene.mesh_filters[game_object] = mesh_guid
        elif class_id in (23, 137):
            if not _bool_scalar(body, "m_Enabled"):
                continue
            direct_mesh = legacy._reference_guid(body, "m_Mesh") if class_id == 137 else None
            batch_match = re.search(
                r"m_StaticBatchInfo:\s*\r?\n\s+firstSubMesh:\s*(\d+)\s*\r?\n\s+subMeshCount:\s*(\d+)",
                body,
            )
            first_submesh = int(batch_match.group(1)) if batch_match else 0
            submesh_count = int(batch_match.group(2)) if batch_match else 0
            scene.renderers.append(
                RendererInfo(
                    "SkinnedMeshRenderer" if class_id == 137 else "MeshRenderer",
                    game_object,
                    direct_mesh or "",
                    legacy._material_guids(body),
                    first_submesh,
                    submesh_count,
                )
            )
        elif class_id == 65 and _bool_scalar(body, "m_Enabled") and not _bool_scalar(body, "m_IsTrigger", False):
            scene.primitive_colliders.append(
                PrimitiveCollider(
                    "box",
                    game_object,
                    legacy._yaml_vector(body, "m_Center", 3, (0.0, 0.0, 0.0)),
                    legacy._yaml_vector(body, "m_Size", 3, (1.0, 1.0, 1.0)),
                )
            )
        elif class_id == 135 and _bool_scalar(body, "m_Enabled") and not _bool_scalar(body, "m_IsTrigger", False):
            scene.primitive_colliders.append(
                PrimitiveCollider(
                    "sphere",
                    game_object,
                    legacy._yaml_vector(body, "m_Center", 3, (0.0, 0.0, 0.0)),
                    radius=_float_scalar(body, "m_Radius", 0.5),
                )
            )
        elif class_id == 136 and _bool_scalar(body, "m_Enabled") and not _bool_scalar(body, "m_IsTrigger", False):
            scene.primitive_colliders.append(
                PrimitiveCollider(
                    "capsule",
                    game_object,
                    legacy._yaml_vector(body, "m_Center", 3, (0.0, 0.0, 0.0)),
                    radius=_float_scalar(body, "m_Radius", 0.5),
                    height=_float_scalar(body, "m_Height", 2.0),
                    direction=_int_scalar(body, "m_Direction", 1),
                )
            )
        elif class_id == 64 and _bool_scalar(body, "m_Enabled") and not _bool_scalar(body, "m_IsTrigger", False):
            mesh_guid = legacy._reference_guid(body, "m_Mesh")
            if mesh_guid and set(mesh_guid) != {"0"}:
                scene.mesh_colliders.append((game_object, mesh_guid, _bool_scalar(body, "m_Convex", False)))
        elif class_id == 104:
            scene.render_settings = {
                "fog_enabled": _bool_scalar(body, "m_Fog", False),
                "fog_color": _yaml_color(body, "m_FogColor", (0.5, 0.5, 0.5, 1.0)),
                "fog_density": _float_scalar(body, "m_FogDensity", 0.01),
                "ambient_color": _yaml_color(body, "m_AmbientSkyColor", (0.2, 0.2, 0.2, 1.0)),
                "ambient_intensity": _float_scalar(body, "m_AmbientIntensity", 1.0),
            }
        elif class_id == 114 and legacy._reference_guid(body, "m_Script") == WAYPOINT_SCRIPT_GUID:
            nodes_match = re.search(r"^\s*nodes:\s*$", body, re.MULTILINE)
            node_ids: list[int] = []
            if nodes_match:
                for line in body[nodes_match.end() :].splitlines():
                    node_match = re.match(r"^\s*-\s*\{fileID:\s*(\d+)\}", line)
                    if node_match:
                        node_ids.append(int(node_match.group(1)))
                        continue
                    if line.strip():
                        break
            scene.waypoint_scripts[file_id] = (game_object, node_ids)
    return scene


class SceneResolver:
    def __init__(self, scene: SceneData):
        self.scene = scene
        self._world_cache: dict[int, tuple[tuple[float, ...], ...]] = {}
        self._active_cache: dict[int, bool] = {}

    def world_transform(self, game_object: int) -> tuple[tuple[float, ...], ...]:
        if game_object in self._world_cache:
            return self._world_cache[game_object]
        transform_id = self.scene.transform_for_game_object.get(game_object, 0)
        if not transform_id:
            return legacy.identity_matrix()
        visited: set[int] = set()
        chain: list[tuple[tuple[float, ...], ...]] = []
        while transform_id:
            if transform_id in visited or transform_id not in self.scene.transforms:
                raise legacy.ConversionError(
                    f"{self.scene.path}: broken/cyclic Transform hierarchy at fileID {transform_id}"
                )
            visited.add(transform_id)
            transform = self.scene.transforms[transform_id]
            chain.append(transform.local)
            transform_id = transform.father
        result = legacy.identity_matrix()
        for local in reversed(chain):
            result = legacy.matrix_multiply(result, local)
        self._world_cache[game_object] = result
        return result

    def parent_game_object(self, game_object: int) -> int:
        transform_id = self.scene.transform_for_game_object.get(game_object, 0)
        if not transform_id:
            return 0
        father = self.scene.transforms[transform_id].father
        return self.scene.transforms[father].game_object if father in self.scene.transforms else 0

    def active_in_hierarchy(self, game_object: int) -> bool:
        if game_object in self._active_cache:
            return self._active_cache[game_object]
        current = game_object
        visited: set[int] = set()
        while current:
            if current in visited:
                return False
            visited.add(current)
            info = self.scene.game_objects.get(current)
            if info is not None and not info.active:
                self._active_cache[game_object] = False
                return False
            current = self.parent_game_object(current)
        self._active_cache[game_object] = True
        return True

    def has_named_ancestor(self, game_object: int, names: set[str]) -> bool:
        current = game_object
        visited: set[int] = set()
        while current:
            if current in visited:
                return False
            visited.add(current)
            info = self.scene.game_objects.get(current)
            if info is not None and info.name in names:
                return True
            current = self.parent_game_object(current)
        return False


def _translation_matrix(position: tuple[float, float, float]) -> tuple[tuple[float, ...], ...]:
    return (
        (1.0, 0.0, 0.0, position[0]),
        (0.0, 1.0, 0.0, position[1]),
        (0.0, 0.0, 1.0, position[2]),
        (0.0, 0.0, 0.0, 1.0),
    )


def _mirror_z() -> tuple[tuple[float, ...], ...]:
    return (
        (1.0, 0.0, 0.0, 0.0),
        (0.0, 1.0, 0.0, 0.0),
        (0.0, 0.0, -1.0, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    )


def _godot_node_transform(
    unity_world: Sequence[Sequence[float]],
    center: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> tuple[tuple[float, ...], ...]:
    mirror = _mirror_z()
    # A node basis needs a basis conversion on both sides; this keeps rotations
    # proper while mirroring the final world position from Unity +Z to Godot -Z.
    return legacy.matrix_multiply(
        legacy.matrix_multiply(
            legacy.matrix_multiply(mirror, unity_world), _translation_matrix(center)
        ),
        mirror,
    )


def _matrix_json(matrix: Sequence[Sequence[float]]) -> list[float]:
    return [float(matrix[row][column]) for row in range(4) for column in range(4)]


def _position_json(unity_world: Sequence[Sequence[float]]) -> list[float]:
    return [float(unity_world[0][3]), float(unity_world[1][3]), float(-unity_world[2][3])]


def _copy_material(material: legacy.MaterialInfo) -> legacy.MaterialInfo:
    result = copy.copy(material)
    result.copied_name = None
    return result


def _prepare_level_texture(
    material: legacy.MaterialInfo,
    level_dir: Path,
    claimed_names: dict[str, Path],
) -> legacy.MaterialInfo:
    """Point an exported material at a collision-safe, preserved 2x texture.

    Existing restored textures may have been processed with a higher-quality
    upscaler, so a repeatable level export must not replace them with the
    lower-resolution Unity source.  Newly recovered textures are written as
    RGBA and enlarged up to 2x while retaining the mobile-safe 4096px cap.
    """
    source = material.diffuse_source
    if source is None:
        return material
    if not source.is_file():
        raise legacy.ConversionError(f"Referenced diffuse texture is missing: {source}")

    source_key = source.resolve()
    destination_name = legacy._sanitize_name(source.name)
    claimed_source = claimed_names.get(destination_name.casefold())
    if claimed_source is not None and claimed_source != source_key:
        safe_stem = legacy._sanitize_name(source.stem)
        guid_suffix = (material.diffuse_guid or "texture")[:8]
        destination_name = f"{safe_stem}_{guid_suffix}{source.suffix.lower()}"
        suffix = 2
        while (
            destination_name.casefold() in claimed_names
            and claimed_names[destination_name.casefold()] != source_key
        ):
            destination_name = (
                f"{safe_stem}_{guid_suffix}_{suffix}{source.suffix.lower()}"
            )
            suffix += 1
    claimed_names[destination_name.casefold()] = source_key

    level_dir.mkdir(parents=True, exist_ok=True)
    destination = level_dir / destination_name
    with Image.open(source) as source_image:
        target_scale = min(
            TEXTURE_EXPORT_SCALE,
            MAX_TEXTURE_DIMENSION / float(max(source_image.width, source_image.height)),
        )
        target_size = (
            max(1, int(round(source_image.width * target_scale))),
            max(1, int(round(source_image.height * target_scale))),
        )
        keep_existing = False
        if destination.is_file():
            try:
                with Image.open(destination) as existing:
                    keep_existing = (
                        existing.width >= target_size[0]
                        and existing.height >= target_size[1]
                    )
            except OSError:
                keep_existing = False
        if not keep_existing:
            rgba = source_image.convert("RGBA")
            if rgba.size != target_size:
                rgba = rgba.resize(target_size, Image.Resampling.LANCZOS)
            rgba.save(destination, format="PNG", optimize=True)

    # write_obj copies from diffuse_source into the destination directory. By
    # pointing it at the prepared destination itself, the existing/upscaled
    # file is retained and its collision-safe name is written into map_Kd.
    material.diffuse_source = destination
    material.copied_name = destination_name
    return material


def export_level(
    scene_path: Path,
    assets_root: Path,
    output_root: Path,
    guid_index: legacy.GuidIndex,
    mesh_cache: dict[str, legacy.MeshData | Exception],
    material_cache: dict[str, legacy.MaterialInfo | Exception],
) -> dict[str, object]:
    scene = parse_scene(scene_path)
    resolver = SceneResolver(scene)
    level_number = int(re.search(r"(\d+)$", scene_path.stem).group(1))
    level_dir = output_root / f"level_{level_number:02d}"
    level_dir.mkdir(parents=True, exist_ok=True)
    visual_path = level_dir / "stage.obj"
    collision_path = level_dir / "collision.obj"
    warnings: list[str] = []
    claimed_texture_names: dict[str, Path] = {}

    def mesh_for(guid: str) -> legacy.MeshData | None:
        if guid not in mesh_cache:
            try:
                mesh_cache[guid] = legacy.parse_mesh(guid_index.resolve(guid))
            except (legacy.ConversionError, OSError, ValueError) as error:
                mesh_cache[guid] = error
        value = mesh_cache[guid]
        if isinstance(value, Exception):
            warnings.append(f"mesh {guid}: {value}")
            return None
        return value

    def material_for(guid: str, fallback_name: str) -> legacy.MaterialInfo:
        if guid not in material_cache:
            try:
                material_cache[guid] = legacy.parse_material(guid_index.resolve(guid), guid_index)
            except (legacy.ConversionError, OSError, ValueError) as error:
                material_cache[guid] = error
        value = material_cache[guid]
        if isinstance(value, Exception):
            warnings.append(f"material {guid}: {value}")
            return legacy.fallback_material(fallback_name)
        return _prepare_level_texture(
            _copy_material(value),
            level_dir,
            claimed_texture_names,
        )

    visual_pieces: list[legacy.ObjPiece] = []
    batched_renderers: dict[str, list[RendererInfo]] = {}
    ui_camera_roots = {
        "GameUI",
        "Main Camera",
        "Camera",
        "Popup",
        "ScreenDirection",
        "Screen_Blood",
        "Screen_DeadBlood",
        "CameraFade",
    }
    for renderer in scene.renderers:
        if not resolver.active_in_hierarchy(renderer.game_object):
            continue
        if resolver.has_named_ancestor(renderer.game_object, ui_camera_roots):
            continue
        mesh_guid = renderer.direct_mesh or scene.mesh_filters.get(renderer.game_object, "")
        if not mesh_guid:
            continue
        if renderer.submesh_count > 0:
            batched_renderers.setdefault(mesh_guid, []).append(renderer)
            continue
        mesh = mesh_for(mesh_guid)
        if mesh is None:
            continue
        info = scene.game_objects.get(
            renderer.game_object,
            GameObjectInfo(f"GameObject_{renderer.game_object}", "Untagged", True, 0),
        )
        materials = [material_for(guid, info.name) for guid in renderer.material_guids]
        if not materials:
            materials = [legacy.fallback_material(info.name)]
        visual_pieces.append(
            legacy.ObjPiece(
                info.name,
                mesh,
                resolver.world_transform(renderer.game_object),
                materials,
            )
        )

    # Unity's static batching keeps one world-space mesh and records which
    # submeshes belong to each renderer. Export that combined mesh only once;
    # baking it once is both exact and dramatically smaller than duplicating it
    # at every source GameObject transform.
    for mesh_guid, renderers in batched_renderers.items():
        mesh = mesh_for(mesh_guid)
        if mesh is None:
            continue
        selected_submeshes: list[legacy.SubMesh] = []
        selected_materials: list[legacy.MaterialInfo] = []
        for renderer in sorted(renderers, key=lambda item: item.first_submesh):
            info = scene.game_objects.get(
                renderer.game_object,
                GameObjectInfo(f"GameObject_{renderer.game_object}", "Untagged", True, 0),
            )
            start = renderer.first_submesh
            end = start + renderer.submesh_count
            if start < 0 or end > len(mesh.submeshes):
                warnings.append(
                    f"{info.name}: static batch submeshes {start}:{end} exceed {len(mesh.submeshes)}"
                )
                continue
            renderer_materials = [material_for(guid, info.name) for guid in renderer.material_guids]
            if not renderer_materials:
                renderer_materials = [legacy.fallback_material(info.name)]
            for offset, submesh in enumerate(mesh.submeshes[start:end]):
                selected_submeshes.append(submesh)
                selected_materials.append(
                    renderer_materials[offset]
                    if offset < len(renderer_materials)
                    else renderer_materials[-1]
                )
        if selected_submeshes:
            selected_mesh = legacy.MeshData(
                mesh.name,
                mesh.positions,
                mesh.normals,
                mesh.uvs,
                selected_submeshes,
                mesh.source_path,
            )
            visual_pieces.append(
                legacy.ObjPiece(
                    f"Level{level_number}_StaticBatch",
                    selected_mesh,
                    legacy.identity_matrix(),
                    selected_materials,
                )
            )
    visual_result = legacy.write_obj(
        visual_path,
        visual_pieces,
        group_faces_by_material=True,
    )
    visual_validation = legacy.validate_obj(visual_path)

    collision_pieces: list[legacy.ObjPiece] = []
    mesh_collider_records: list[dict[str, object]] = []
    for game_object, mesh_guid, convex in scene.mesh_colliders:
        if not resolver.active_in_hierarchy(game_object):
            continue
        mesh = mesh_for(mesh_guid)
        if mesh is None:
            continue
        info = scene.game_objects.get(game_object, GameObjectInfo(f"GameObject_{game_object}", "Untagged", True, 0))
        collision_pieces.append(
            legacy.ObjPiece(
                f"collision_{info.name}",
                mesh,
                resolver.world_transform(game_object),
                [legacy.fallback_material("collision")],
            )
        )
        mesh_collider_records.append({"name": info.name, "convex": convex})
    collision_result: dict[str, object] | None = None
    if collision_pieces:
        collision_result = legacy.write_obj(collision_path, collision_pieces)

    primitive_records: list[dict[str, object]] = []
    for collider in scene.primitive_colliders:
        if not resolver.active_in_hierarchy(collider.game_object):
            continue
        info = scene.game_objects.get(
            collider.game_object,
            GameObjectInfo(f"GameObject_{collider.game_object}", "Untagged", True, 0),
        )
        record: dict[str, object] = {
            "type": collider.kind,
            "name": info.name,
            "transform": _matrix_json(
                _godot_node_transform(resolver.world_transform(collider.game_object), collider.center)
            ),
        }
        if collider.kind == "box":
            record["size"] = list(collider.size)
        elif collider.kind == "sphere":
            record["radius"] = collider.radius
        else:
            record.update(
                {"radius": collider.radius, "height": collider.height, "direction": collider.direction}
            )
        primitive_records.append(record)

    markers: dict[str, list[dict[str, object]]] = {tag: [] for tag in MARKER_TAGS}
    for game_object, info in scene.game_objects.items():
        if info.tag not in markers or not resolver.active_in_hierarchy(game_object):
            continue
        world = resolver.world_transform(game_object)
        markers[info.tag].append(
            {
                "name": info.name,
                "game_object": game_object,
                "position": _position_json(world),
                "transform": _matrix_json(_godot_node_transform(world)),
            }
        )

    waypoint_records = markers["WayPoint"]
    waypoint_index_by_game_object = {
        int(record["game_object"]): index for index, record in enumerate(waypoint_records)
    }
    waypoint_component_to_game_object = {
        component_id: game_object
        for component_id, (game_object, _nodes) in scene.waypoint_scripts.items()
    }
    waypoint_graph: list[set[int]] = [set() for _record in waypoint_records]
    for _component_id, (game_object, node_components) in scene.waypoint_scripts.items():
        source_index = waypoint_index_by_game_object.get(game_object)
        if source_index is None:
            continue
        for node_component in node_components:
            target_game_object = waypoint_component_to_game_object.get(node_component)
            target_index = waypoint_index_by_game_object.get(target_game_object)
            if target_index is None or target_index == source_index:
                continue
            # The original GameWorld.PreCalculateWayPoints explicitly made
            # every authored link bidirectional.
            waypoint_graph[source_index].add(target_index)
            waypoint_graph[target_index].add(source_index)

    unique_warnings = list(dict.fromkeys(warnings))
    metadata = {
        "format": 2,
        "level": level_number,
        "source": str(scene_path),
        "visual": "stage.obj",
        "collision_mesh": "collision.obj" if collision_pieces else "",
        "visual_bounds_min": visual_validation["bounds_min"],
        "visual_bounds_max": visual_validation["bounds_max"],
        "render_settings": scene.render_settings,
        "material_render_modes": visual_result["material_states"],
        "markers": markers,
        "waypoint_graph": [sorted(neighbours) for neighbours in waypoint_graph],
        "primitive_colliders": primitive_records,
        "mesh_colliders": mesh_collider_records,
        "source_summary": {
            "game_objects": len(scene.game_objects),
            "visual_renderers": len(visual_pieces),
            "primitive_colliders": len(primitive_records),
            "mesh_colliders": len(collision_pieces),
        },
        "warnings": unique_warnings,
    }
    metadata_path = level_dir / "level.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return {
        "level": level_number,
        "source": str(scene_path),
        "visual": visual_result,
        "collision": collision_result,
        "metadata": str(metadata_path),
        "summary": metadata["source_summary"],
        "marker_counts": {key: len(value) for key, value in markers.items() if value},
        "warning_count": len(unique_warnings),
    }


def export_all(assets_root: Path, godot_root: Path, levels: Sequence[int]) -> dict[str, object]:
    output_root = godot_root / "assets" / "models" / "levels"
    output_root.mkdir(parents=True, exist_ok=True)
    guid_index = legacy.GuidIndex(assets_root)
    mesh_cache: dict[str, legacy.MeshData | Exception] = {}
    material_cache: dict[str, legacy.MaterialInfo | Exception] = {}
    results = []
    for level_number in levels:
        scene_path = assets_root / "Scenes" / f"Level{level_number}.unity"
        if not scene_path.is_file():
            raise legacy.ConversionError(f"Missing original Unity scene: {scene_path}")
        print(f"Exporting Level{level_number}...", file=sys.stderr, flush=True)
        results.append(
            export_level(
                scene_path,
                assets_root,
                output_root,
                guid_index,
                mesh_cache,
                material_cache,
            )
        )
    report = {
        "format": 1,
        "source_assets": str(assets_root),
        "output_root": str(output_root),
        "levels": results,
        "totals": {
            "levels": len(results),
            "visual_renderers": sum(int(item["summary"]["visual_renderers"]) for item in results),
            "primitive_colliders": sum(int(item["summary"]["primitive_colliders"]) for item in results),
            "mesh_colliders": sum(int(item["summary"]["mesh_colliders"]) for item in results),
            "warnings": sum(int(item["warning_count"]) for item in results),
        },
    }
    report_path = Path(__file__).with_name("level_export_report.json")
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--godot-root", type=Path, required=True)
    parser.add_argument("--levels", type=int, nargs="*", default=list(LEVEL_NUMBERS))
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        report = export_all(args.assets_root.resolve(), args.godot_root.resolve(), args.levels)
    except (legacy.ConversionError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report["totals"], indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
