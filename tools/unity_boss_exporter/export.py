#!/usr/bin/env python3
"""Recover Boss1..6 prefabs with the existing level exporter's format-3 API.

The Unity source is read-only. New arena directories are published only after
successful conversion; an existing destination is never replaced. Run with:
python3 tools/unity_boss_exporter/export.py --assets-root ../star-warfare/Assets
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import struct
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator, Sequence


REPO_ROOT = Path(__file__).resolve().parents[2]
LEVEL_EXPORTER = REPO_ROOT / "tools/unity_level_exporter"
sys.path.insert(0, str(LEVEL_EXPORTER))
_spec = importlib.util.spec_from_file_location("boss_arena_level_api", LEVEL_EXPORTER / "export.py")
assert _spec is not None and _spec.loader is not None
levels = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = levels
_spec.loader.exec_module(levels)

# GameWorld.CreateBoss replaces the Level object, leaving these scene markers
# alive. These are the campaign scenes for the six boss encounter types.
BOSS_SCENES = {1: 4, 2: 3, 3: 5, 4: 6, 5: 7, 6: 8}
BOSS_TYPES = {1: "Dragon", 2: "Mantis", 3: "Beetle", 4: "MainMantis", 5: "Earthworm", 6: "SantaMachine"}
SPAWN_TAGS = ("PlayerSpawnInBoss", "BossSpawnPoint")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def prepare_prefab(path: Path) -> tuple[levels.SceneData, dict[str, object]]:
    scene = levels.parse_scene(path)
    documents = levels.legacy._documents(path.read_text(encoding="utf-8-sig"))
    roots = [(tid, transform) for tid, transform in scene.transforms.items() if transform.father == 0]
    if len(roots) != 1:
        raise ValueError(f"{path}: expected one prefab root, found {len(roots)}")
    transform_id, root = roots[0]
    prefab = next((body for kind, _, body in documents if kind == 1001), "")
    declared = re.search(r"m_RootGameObject:\s*\{fileID:\s*(\d+)\}", prefab)
    if declared is None or int(declared.group(1)) != root.game_object:
        raise ValueError(f"{path}: prefab root declaration does not match the Transform hierarchy")
    root_info = scene.game_objects[root.game_object]
    if not root_info.active:
        raise ValueError(f"{path}: inactive prefab root; CreateBoss does not activate it")
    root_body = next(body for kind, fid, body in documents if kind == 4 and fid == transform_id)
    scale = levels.legacy._yaml_vector(root_body, "m_LocalScale", 3, (1.0, 1.0, 1.0))
    source_transform = levels._matrix_json(root.local)
    # Instantiate(prefab, Vector3.zero, Quaternion.identity) overrides root T/R,
    # retaining the authored scale. Boss6's saved editor position is y=300.
    root.local = levels.legacy.local_matrix((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), scale)
    return scene, {
        "game_object": root.game_object,
        "transform_file_id": transform_id,
        "active": root_info.active,
        "source_unity_transform": source_transform,
        "runtime_unity_transform": levels._matrix_json(root.local),
        "local_scale": list(scale),
        "policy": "GameWorld.CreateBoss: Instantiate(prefab, Vector3.zero, Quaternion.identity); preserve scale and child active states",
    }


@contextmanager
def prefab_adapter(scene: levels.SceneData) -> Iterator[None]:
    """Adapt only this process's private module; never edit the shared exporter."""
    original_parse = levels.parse_scene
    original_scale = levels.TEXTURE_EXPORT_SCALE
    levels.parse_scene = lambda path: scene if path == scene.path else original_parse(path)
    levels.TEXTURE_EXPORT_SCALE = 1
    try:
        yield
    finally:
        levels.parse_scene = original_parse
        levels.TEXTURE_EXPORT_SCALE = original_scale


def source_markers(scene: levels.SceneData) -> dict[str, list[dict[str, object]]]:
    resolver = levels.SceneResolver(scene)
    markers: dict[str, list[dict[str, object]]] = {tag: [] for tag in SPAWN_TAGS}
    for game_object, info in scene.game_objects.items():
        if info.tag not in markers or not resolver.active_in_hierarchy(game_object):
            continue
        world = resolver.world_transform(game_object)
        markers[info.tag].append({
            "name": info.name,
            "game_object": game_object,
            "position": levels._position_json(world),
            "transform": levels._matrix_json(levels._godot_node_transform(world)),
        })
    if len(markers["PlayerSpawnInBoss"]) != 3 or not markers["BossSpawnPoint"]:
        raise ValueError(f"{scene.path}: incomplete original boss spawn markers")
    return markers


def pack_glb(gltf_path: Path, output: Path) -> None:
    """Pack the exporter's unchanged geometry/UV accessors into a glTF 2 GLB."""
    document = json.loads(gltf_path.read_text(encoding="utf-8"))
    if len(document["buffers"]) != 1:
        raise ValueError("Expected the level exporter's single binary buffer")
    buffer = document["buffers"][0]
    binary = (gltf_path.parent / buffer.pop("uri")).read_bytes()
    if len(binary) != buffer["byteLength"]:
        raise ValueError("glTF binary length does not match its declaration")
    encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    binary += b"\0" * (-len(binary) % 4)
    with output.open("xb") as stream:
        stream.write(struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary)))
        stream.write(struct.pack("<I4s", len(encoded), b"JSON"))
        stream.write(encoded)
        stream.write(struct.pack("<I4s", len(binary), b"BIN\0"))
        stream.write(binary)


def effect_metadata(scene: levels.SceneData, index: levels.legacy.GuidIndex, directory: Path) -> list[dict[str, object]]:
    """Preserve the original bubble emitter as data, without claiming playback."""
    resolver = levels.SceneResolver(scene)
    components: dict[int, dict[int, str]] = {}
    for kind, _, body in levels.legacy._documents(scene.path.read_text(encoding="utf-8-sig")):
        if kind in (12, 15, 26):
            components.setdefault(levels._game_object_reference(body), {})[kind] = body
    records = []
    for game_object, parts in components.items():
        if 15 not in parts or 26 not in parts:
            continue
        emitter, renderer, animator = parts[15], parts[26], parts.get(12, "")
        material_guid = levels.legacy._material_guids(renderer)[0]
        material = levels.legacy.parse_material(index.resolve(material_guid), index)
        texture_name = ""
        if material.diffuse_source is not None:
            texture_name = f"effect_{material.diffuse_guid}_{material.diffuse_source.name}"
            shutil.copyfile(material.diffuse_source, directory / texture_name)
        record = {
            "name": scene.game_objects[game_object].name,
            "game_object": game_object,
            "kind": "legacy_ellipsoid",
            "runtime_restored": False,
            "active_in_hierarchy": resolver.active_in_hierarchy(game_object),
            "enabled": levels._bool_scalar(emitter, "m_Enabled") and levels._bool_scalar(renderer, "m_Enabled"),
            "emitting": levels._bool_scalar(emitter, "m_Emit"),
            "one_shot": levels._bool_scalar(emitter, "m_OneShot", False),
            "transform": levels._matrix_json(levels._godot_node_transform(resolver.world_transform(game_object))),
            "texture": texture_name,
            "source_material_guid": material_guid,
            "shader": material.shader_name,
            "lifetime": [levels._float_scalar(emitter, key) for key in ("minEnergy", "maxEnergy")],
            "size": [levels._float_scalar(emitter, key) for key in ("minSize", "maxSize")],
            "emission_rate": [levels._float_scalar(emitter, key) for key in ("minEmission", "maxEmission")],
            "ellipsoid": levels.legacy._yaml_vector(emitter, "m_Ellipsoid", 3, (0.0, 0.0, 0.0)),
            "local_velocity_unity": levels.legacy._yaml_vector(emitter, "localVelocity", 3, (0.0, 0.0, 0.0)),
            "size_grow": levels._float_scalar(animator, "sizeGrow"),
            "color_over_life": [[((int(value) >> shift) & 255) / 255.0 for shift in (0, 8, 16, 24)] for value in re.findall(r"rgba:\s*(\d+)", animator)],
            "source_components": {str(kind): body for kind, body in parts.items()},
        }
        records.append(record)
    return records


def export_arena(number: int, assets_root: Path, output_root: Path, index: levels.legacy.GuidIndex,
                 mesh_cache: dict, material_cache: dict) -> dict[str, object]:
    target = output_root / f"boss_{number:02d}"
    if target.exists():
        raise FileExistsError(f"Refusing to overwrite existing arena: {target}")
    source = assets_root / "Resources/level" / f"Boss{number}.prefab"
    scene, root_record = prepare_prefab(source)
    spawn_path = assets_root / "Scenes" / f"Level{BOSS_SCENES[number]}.unity"
    spawn_scene = levels.parse_scene(spawn_path)
    spawns = source_markers(spawn_scene)
    expected_bosses = 2 if number == 4 else 1
    if len(spawns["BossSpawnPoint"]) != expected_bosses:
        raise ValueError(f"{spawn_path}: expected {expected_bosses} boss spawns")
    resource_directory = f"res://assets/models/boss_arenas/boss_{number:02d}"
    with tempfile.TemporaryDirectory(prefix=".boss_export_", dir=output_root) as temporary:
        with prefab_adapter(scene):
            result = levels.export_level(source, assets_root, Path(temporary), index, mesh_cache, material_cache)
        generated = Path(temporary) / f"level_{number:02d}"
        metadata = json.loads((generated / "level.json").read_text(encoding="utf-8"))
        if metadata["warnings"]:
            raise ValueError(f"Boss{number}: incomplete conversion: {metadata['warnings']}")
        for state in metadata["material_render_modes"].values():
            for key in ("lightmap_texture", "overlay_texture"):
                if key in state:
                    state[key] = f"{resource_directory}/{Path(state[key]).name}"
        metadata["markers"].update(spawns)
        metadata["render_settings"] = spawn_scene.render_settings
        metadata.update({
            "boss": True,
            "boss_type": BOSS_TYPES[number],
            "resource_directory": resource_directory,
            "source": source.relative_to(assets_root).as_posix(),
            "source_sha256": sha256(source),
            "source_root": root_record,
            "spawn_source": spawn_path.relative_to(assets_root).as_posix(),
            "spawn_source_sha256": sha256(spawn_path),
            "spawn_order": "source YAML GameObject order; Unity FindGameObjectsWithTag order is not specified",
            "render_settings_source": spawn_path.relative_to(assets_root).as_posix(),
            "source_effects": effect_metadata(scene, index, generated),
            "restoration_limits": [
                "Static geometry, source UV0/UV2, material lightmaps and collider transforms are restored.",
                "Dynamic Unity lights, particle playback and MonoBehaviour-driven texture animation are not restored.",
            ],
        })
        pack_glb(generated / str(metadata["visual_with_uv2"]), generated / "level.glb")
        metadata["visual_with_uv2"] = "level.glb"
        write_json(generated / "level.json", metadata)
        # No source or destination art is overwritten. Publish only this arena.
        if target.exists():
            raise FileExistsError(target)
        generated.rename(target)
    return {
        "boss": number,
        "boss_type": BOSS_TYPES[number],
        "resource_directory": resource_directory,
        "source": metadata["source"],
        "spawn_source": metadata["spawn_source"],
        "summary": metadata["source_summary"],
        "triangles": result["visual"]["faces"],
        "marker_counts": {tag: len(records) for tag, records in metadata["markers"].items() if records},
        "warnings": metadata["warnings"],
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--bosses", type=int, choices=tuple(BOSS_SCENES), nargs="+", default=list(BOSS_SCENES))
    args = parser.parse_args(argv)
    assets_root = args.assets_root.resolve()
    output_root = REPO_ROOT / "assets/models/boss_arenas"
    try:
        for number in args.bosses:
            if (output_root / f"boss_{number:02d}").exists():
                raise FileExistsError(f"boss_{number:02d} already exists; refusing to replace art")
        output_root.mkdir(parents=True, exist_ok=True)
        index = levels.legacy.GuidIndex(assets_root)
        mesh_cache: dict = {}
        material_cache: dict = {}
        results = []
        for number in args.bosses:
            print(f"Exporting Boss{number}...", file=sys.stderr, flush=True)
            results.append(export_arena(number, assets_root, output_root, index, mesh_cache, material_cache))
        print(json.dumps(results, indent=2, ensure_ascii=False))
    except (OSError, ValueError, levels.legacy.ConversionError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
