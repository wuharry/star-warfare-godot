"""Recover the five loot/pickup prefabs, including mesh UV2 and animation curves.

Uses the existing Unity YAML mesh decoder; no Unity installation is required.
Only the original pickup particle configuration is supported, not arbitrary VFX.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "yaml_mesh_converter"))
import convert as unity


def scalar(text: str, key: str) -> float:
    return float(re.search(rf"^\s*{re.escape(key)}: ([-+\d.eE]+)$", text, re.M)[1])


def section(text: str, key: str, indent: int) -> str:
    match = re.search(rf"^{' ' * indent}{key}:[ \t]*$", text, re.M)
    if not match:
        return ""
    tail = text[match.end():]
    # Unity lists put '- curve' at the same indent as their parent heading.
    end = re.search(rf"^ {{0,{indent}}}[A-Za-z_]", tail, re.M)
    return tail[:end.start()] if end else tail


def keys(text: str) -> list[dict]:
    result = []
    for match in re.finditer(
        r"- time: ([^\n]+)\n\s*value: ([^\n]+)\n\s*inSlope: ([^\n]+)\n\s*outSlope: ([^\n]+)", text
    ):
        def value(raw: str) -> list[float]:
            return [float(v) for v in re.findall(r": ([-+\d.eE]+)", raw)] if "{" in raw else [float(raw)]
        result.append({"time": float(match[1]), "value": value(match[2]),
                       "in": value(match[3]), "out": value(match[4])})
    return result


class Exporter:
    def __init__(self, assets: Path, output: Path):
        self.assets, self.output = assets, output
        self.index = unity.GuidIndex(assets)
        self.data = {"prefabs": {}, "meshes": {}, "materials": {}, "animations": {}, "sources": {}}
        output.mkdir(parents=True, exist_ok=True)

    def source(self, path: Path) -> str:
        name = path.relative_to(self.assets).as_posix()
        self.data["sources"][name] = hashlib.sha256(path.read_bytes()).hexdigest()
        return name

    def texture(self, path: Path) -> str:
        self.source(path)
        shutil.copy2(path, self.output / path.name)
        return path.name

    def material(self, guid: str) -> str:
        if guid in self.data["materials"]:
            return guid
        path = self.index.resolve(guid)
        material = unity.parse_material(path, self.index)
        record = {"source": self.source(path), "shader": material.shader_name,
                  "texture": self.texture(material.diffuse_source), "color": material.color}
        self.source(self.index.resolve(material.shader_guid))
        if material.shader_name == "iPhone/SolidAndAlphaTexture_Bright":
            overlay = re.search(r"name: _tex2.*?guid: ([a-f0-9]{32})", path.read_text(), re.S)[1]
            record["overlay"] = self.texture(self.index.resolve(overlay))
        self.data["materials"][guid] = record
        return guid

    def mesh(self, guid: str) -> str:
        if guid not in self.data["meshes"]:
            path = self.index.resolve(guid)
            mesh = unity.parse_mesh(path)
            # Both engines use clockwise front faces; reflecting Z converts handedness.
            self.data["meshes"][guid] = {
                "source": self.source(path), "positions": mesh.positions,
                "uv": mesh.uvs, "uv2": mesh.uv2s,
                "surfaces": [part.indices for part in mesh.submeshes],
            }
        return guid

    def animation(self, guid: str) -> str:
        if guid in self.data["animations"]:
            return guid
        path = self.index.resolve(guid)
        text = path.read_text(encoding="utf-8-sig")
        channels = []
        for heading, kind in (("m_RotationCurves", "rotation"), ("m_PositionCurves", "position"),
                              ("m_ScaleCurves", "scale"), ("m_FloatCurves", "alpha")):
            for entry in re.split(r"^  - curve:", section(text, heading, 2), flags=re.M)[1:]:
                if kind == "alpha" and "attribute: _TintColor.a" not in entry:
                    continue
                target = re.search(r"^    path:[ \t]*(.*)$", entry, re.M)[1]
                if target:
                    raise ValueError(f"Unsupported non-local pickup animation target: {target}")
                channels.append({"kind": kind, "keys": keys(entry)})
        self.data["animations"][guid] = {"source": self.source(path), "channels": channels}
        return guid

    def particles(self, body: str) -> dict:
        initial = section(body, "InitialModule", 2)
        def limits(key: str) -> list[float]:
            curve = section(initial, key, 4)
            scale = scalar(curve, "scalar")
            if scalar(curve, "minMaxState") == 3:
                return [scale * keys(section(curve, "minCurve", 6))[0]["value"][0], scale]
            return [scale, scale]
        shape = section(body, "ShapeModule", 2)
        if scalar(shape, "type") != 0 or scalar(body, "looping") != 0:
            raise ValueError("Expected a one-shot spherical pickup emitter")
        return {"delay": scalar(body, "startDelay"), "duration": scalar(body, "lengthInSec"),
                "lifetime": limits("startLifetime"), "size": limits("startSize"),
                "speed": limits("startSpeed"), "radius": scalar(shape, "radius"),
                "rate": scalar(section(section(body, "EmissionModule", 2), "rate", 4), "scalar"),
                "size_curve": keys(section(section(section(body, "SizeModule", 2), "curve", 4), "maxCurve", 6))}

    def prefab(self, relative: str) -> None:
        path = self.assets / "Resources" / relative
        docs = unity._documents(path.read_text(encoding="utf-8-sig"))
        components, transforms, names = {}, {}, {}
        for kind, file_id, body in docs:
            if kind == 1:
                names[file_id] = re.search(r"m_Name: (.*)", body)[1]
            elif kind != 1001:
                game_id = re.search(r"m_GameObject: \{fileID: (\d+)\}", body)[1]
                components.setdefault(game_id, {})[kind] = body
                if kind == 4:
                    transforms[str(file_id)] = game_id
        records = []
        for transform_id, game_id in transforms.items():
            parts = components[game_id]
            transform = parts[4]
            parent = re.search(r"m_Father: \{fileID: (\d+)\}", transform)[1]
            record = {"id": transform_id, "parent": parent, "name": names[int(game_id)],
                      "position": unity._yaml_vector(transform, "m_LocalPosition", 3, (0, 0, 0)),
                      "rotation": unity._yaml_vector(transform, "m_LocalRotation", 4, (0, 0, 0, 1)),
                      "scale": unity._yaml_vector(transform, "m_LocalScale", 3, (1, 1, 1))}
            if 33 in parts:
                record["mesh"] = self.mesh(re.search(r"guid: ([a-f0-9]{32})", parts[33])[1])
                record["material"] = self.material(unity._material_guids(parts[23])[0])
            if 111 in parts:
                match = re.search(r"m_Animation:.*guid: ([a-f0-9]{32})", parts[111])
                if match:
                    record["animation"] = self.animation(match[1])
            if 198 in parts:
                record["particles"] = self.particles(parts[198])
                record["material"] = self.material(unity._material_guids(parts[199])[0])
            records.append(record)
        self.data["prefabs"][path.stem] = {"source": self.source(path), "nodes": records}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    exporter = Exporter(args.assets_root.resolve(), args.output.resolve())
    for path in ("loot/Money.prefab", "loot/Enegy.prefab", "loot/Halo.prefab",
                 "effect/update_effect/effect_pick_gold_001.prefab",
                 "effect/update_effect/effect_pick_energy_001.prefab"):
        exporter.prefab(path)
    (exporter.output / "pickups.json").write_text(json.dumps(exporter.data, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({key: len(value) for key, value in exporter.data.items()}))


if __name__ == "__main__":
    main()
