#!/usr/bin/env python3
"""Recover the enabled ambient particle effects, leaving Unity source untouched.

This companion exporter deliberately handles the two particle configurations
present in the recovered levels. Unsupported live emitters fail loudly instead
of silently disappearing from the scene.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
from pathlib import Path

import export as levels


def block(text: str, key: str, indent: int) -> str:
    match = re.search(rf"^{' ' * indent}{re.escape(key)}:\s*$", text, re.MULTILINE)
    if not match:
        raise ValueError(f"Missing particle field {key}")
    result = []
    for line in text[match.end():].splitlines():
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        result.append(line)
    return "\n".join(result)


def curve_limits(text: str, key: str) -> list[float]:
    value = block(text, key, 4)
    mode = levels._int_scalar(value, "minMaxState")
    maximum = levels._float_scalar(value, "scalar")
    minimum = levels._float_scalar(value, "minScalar") if mode == 3 else maximum
    if mode not in (0, 3):
        raise ValueError(f"Unsupported curve mode {mode} for {key}")
    return [minimum, maximum]


class EffectAssets:
    def __init__(self, root: Path):
        self.root = root
        self.paths: dict[str, Path] = {}
        # Only these asset types can be referenced by the particle materials.
        # Avoid an unrelated full-project mesh/animation metadata scan.
        for extension in ("*.mat.meta", "*.shader.meta", "*.png.meta"):
            for metadata in root.rglob(extension):
                match = re.search(r"^guid: ([0-9a-f]{32})$", metadata.read_text(encoding="utf-8-sig"), re.MULTILINE)
                if match:
                    self.paths[match.group(1)] = metadata.with_suffix("")

    def resolve(self, guid: str) -> Path:
        return self.paths[guid]


def export_effects(assets_root: Path, godot_root: Path) -> dict:
    output = godot_root / "assets" / "scene_effects"
    output.mkdir(parents=True, exist_ok=True)
    assets = EffectAssets(assets_root)
    result: dict = {"format": 1, "levels": {}, "textures": {}}
    for number in levels.LEVEL_NUMBERS:
        path = assets_root / "Scenes" / f"Level{number}.unity"
        scene_text = path.read_text(encoding="utf-8-sig")
        scene = levels.parse_scene(path)
        resolver = levels.SceneResolver(scene)
        components: dict[int, dict[int, str]] = {}
        for class_id, _file_id, body in levels.legacy._documents(scene_text):
            if class_id in (12, 15, 26, 198, 199):
                components.setdefault(levels._game_object_reference(body), {})[class_id] = body
        records = []
        for game_object, parts in components.items():
            if not resolver.active_in_hierarchy(game_object):
                continue
            legacy_emitter = 15 in parts
            emitter = parts.get(15, parts.get(198, ""))
            renderer = parts.get(26, parts.get(199, ""))
            if not emitter or not renderer or not levels._bool_scalar(renderer, "m_Enabled"):
                continue
            if legacy_emitter and not levels._bool_scalar(emitter, "m_Enabled"):
                continue
            name = scene.game_objects[game_object].name
            material_guid = levels.legacy._material_guids(renderer)[0]
            material = levels.legacy.parse_material(assets.resolve(material_guid), assets)
            if material.diffuse_source is None:
                raise ValueError(f"{path}: {name} has no particle texture")
            texture = material.diffuse_source
            texture_name = f"{material.diffuse_guid[:8]}_{texture.name}"
            shutil.copy2(texture, output / texture_name)
            result["textures"][texture_name] = {
                "source": texture.relative_to(assets_root).as_posix(),
                "guid": material.diffuse_guid,
                "sha256": hashlib.sha256(texture.read_bytes()).hexdigest(),
            }
            record = {
                "name": name,
                "game_object": game_object,
                "source_scene": path.relative_to(assets_root).as_posix(),
                "transform": levels._matrix_json(levels._godot_node_transform(resolver.world_transform(game_object))),
                "texture": texture_name,
                "shader": material.shader_name,
                "source_material": material.source_path.relative_to(assets_root).as_posix(),
                "source_scene_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
            if legacy_emitter:
                if name != "sc_03_fire1" or material.shader_name != "iPhone/AlphaBlend_VertexColor":
                    raise ValueError(f"Unsupported legacy emitter {path}: {name}")
                animator = parts[12]
                packed_colors = [int(value) for value in re.findall(r"rgba:\s*(\d+)", animator)]
                record.update({
                    "kind": "legacy_glow",
                    "emitting": levels._bool_scalar(emitter, "m_Emit"),
                    "one_shot": levels._bool_scalar(emitter, "m_OneShot", False),
                    "lifetime": [levels._float_scalar(emitter, "minEnergy"), levels._float_scalar(emitter, "maxEnergy")],
                    "emission_rate": [levels._float_scalar(emitter, "minEmission"), levels._float_scalar(emitter, "maxEmission")],
                    "size": [levels._float_scalar(emitter, "minSize"), levels._float_scalar(emitter, "maxSize")],
                    "ellipsoid": levels.legacy._yaml_vector(emitter, "m_Ellipsoid", 3, (0.0, 0.0, 0.0)),
                    "world_velocity": levels.legacy._yaml_vector(emitter, "worldVelocity", 3, (0.0, 0.0, 0.0)),
                    "local_velocity": levels.legacy._yaml_vector(emitter, "localVelocity", 3, (0.0, 0.0, 0.0)),
                    "random_velocity": levels.legacy._yaml_vector(emitter, "rndVelocity", 3, (0.0, 0.0, 0.0)),
                    "random_rotation": levels._bool_scalar(emitter, "rndRotation", False),
                    "size_grow": levels._float_scalar(animator, "sizeGrow"),
                    "local_rotation_axis": levels.legacy._yaml_vector(animator, "localRotationAxis", 3, (0.0, 0.0, 0.0)),
                    "world_rotation_axis": levels.legacy._yaml_vector(animator, "worldRotationAxis", 3, (0.0, 0.0, 0.0)),
                    "color_over_life": [[((value >> shift) & 255) / 255.0 for shift in (0, 8, 16, 24)] for value in packed_colors],
                    "shader_color_multiplier": 2.0,
                })
                if any(any(abs(v) > 1e-6 for v in record[key]) for key in ("world_velocity", "local_velocity", "random_velocity")):
                    raise ValueError(f"Unsupported moving legacy emitter {path}: {name}")
                if len(set(record["ellipsoid"])) != 1:
                    raise ValueError(f"Unsupported non-spherical legacy emitter {path}: {name}")
            else:
                if name != "effect_snow_001" or material.shader_name != "iPhone/Additive":
                    raise ValueError(f"Unsupported ParticleSystem {path}: {name}")
                initial = block(emitter, "InitialModule", 2)
                shape = block(emitter, "ShapeModule", 2)
                emission = block(emitter, "EmissionModule", 2)
                if levels._int_scalar(shape, "type") != 5:
                    raise ValueError(f"Unsupported snow shape {path}: {name}")
                record.update({
                    "kind": "snow",
                    "emitting": levels._bool_scalar(emitter, "playOnAwake") and levels._bool_scalar(emission, "enabled"),
                    "one_shot": not levels._bool_scalar(emitter, "looping"),
                    "lifetime": curve_limits(initial, "startLifetime"),
                    "emission_rate": curve_limits(emission, "rateOverTime"),
                    "size": curve_limits(initial, "startSize"),
                    "start_speed": curve_limits(initial, "startSpeed"),
                    "box_size": levels.legacy._yaml_vector(shape, "m_Scale", 3, (1.0, 1.0, 1.0)),
                    "max_particles": levels._int_scalar(initial, "maxNumParticles"),
                    "prewarm": levels._bool_scalar(emitter, "prewarm", False),
                    "speed_scale": levels._float_scalar(emitter, "simulationSpeed", 1.0),
                    # iPhone/Additive ignores _TintColor and vertex color.
                    "shader_color_multiplier": 1.0,
                })
            record["particle_capacity"] = math.ceil(sum(record["emission_rate"]) * 0.5 * record["lifetime"][1])
            records.append(record)
        if records:
            result["levels"][str(number)] = records
    (output / "effects.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--godot-root", type=Path, required=True)
    args = parser.parse_args()
    result = export_effects(args.assets_root.resolve(), args.godot_root.resolve())
    print(json.dumps({"levels": list(result["levels"]), "effects": sum(map(len, result["levels"].values())), "textures": len(result["textures"])}))


if __name__ == "__main__":
    main()
