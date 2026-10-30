"""Source parity and prefab failure-path checks; no dependencies beyond exporter."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import struct
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from PIL import Image


SPEC = importlib.util.spec_from_file_location("boss_export", Path(__file__).with_name("export.py"))
assert SPEC is not None and SPEC.loader is not None
export = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export)
ASSETS = export.REPO_ROOT.parent / "star-warfare/Assets"
OUTPUT = export.REPO_ROOT / "assets/models/boss_arenas"
SourceMaterials = dict[str, tuple[str, export.levels.legacy.MaterialInfo]]


def _image_fingerprint(path: Path) -> tuple[tuple[int, int], str]:
    with Image.open(path) as image:
        return image.size, hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


@contextmanager
def _arena_fixture(number: int) -> Iterator[Path]:
    """Mutate only a disposable copy under tests, never exported or Unity art."""
    with tempfile.TemporaryDirectory(prefix="boss_texture_test_", dir=export.REPO_ROOT / "tests") as temporary:
        yield shutil.copytree(OUTPUT / f"boss_{number:02d}", Path(temporary) / f"boss_{number:02d}")


class BossArenaExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not ASSETS.is_dir():
            raise unittest.SkipTest(f"Read-only Unity source unavailable: {ASSETS}")
        cls.index = export.levels.legacy.GuidIndex(ASSETS)

    def test_root_instantiation_preserves_scale_and_child_activation(self) -> None:
        # A rotated, scaled root with an editor offset must become zero/identity,
        # while a deliberately disabled child must remain disabled.
        fixture = """%YAML 1.1
--- !u!1001 &100
Prefab:
  m_RootGameObject: {fileID: 1}
--- !u!1 &1
GameObject:
  m_Name: Boss6
  m_IsActive: 1
--- !u!4 &4
Transform:
  m_GameObject: {fileID: 1}
  m_Father: {fileID: 0}
  m_LocalPosition: {x: 1, y: 300, z: 4}
  m_LocalRotation: {x: 0, y: 0.7071067811865476, z: 0, w: 0.7071067811865476}
  m_LocalScale: {x: 2, y: 3, z: 4}
--- !u!1 &2
GameObject:
  m_Name: DisabledChild
  m_IsActive: 0
--- !u!4 &5
Transform:
  m_GameObject: {fileID: 2}
  m_Father: {fileID: 4}
  m_LocalPosition: {x: 1, y: 2, z: 3}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 1, z: 1}
"""
        with tempfile.TemporaryDirectory(dir=export.REPO_ROOT / "tests") as temp:
            path = Path(temp) / "Boss6.prefab"
            path.write_text(fixture)
            scene, record = export.prepare_prefab(path)
            resolver = export.levels.SceneResolver(scene)
            self.assertEqual(record["local_scale"], [2.0, 3.0, 4.0])
            self.assertEqual(record["runtime_unity_transform"], [2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 0, 0, 0, 1])
            self.assertEqual(export.levels._position_json(resolver.world_transform(2)), [2, 6, -12])
            self.assertFalse(resolver.active_in_hierarchy(2))
            path.write_text(fixture.replace("m_IsActive: 1", "m_IsActive: 0", 1))
            with self.assertRaisesRegex(ValueError, "inactive prefab root"):
                export.prepare_prefab(path)
            path.write_text(fixture.replace("m_RootGameObject: {fileID: 1}", "m_RootGameObject: {fileID: 2}"))
            with self.assertRaisesRegex(ValueError, "root declaration"):
                export.prepare_prefab(path)

    def test_six_source_exports_and_original_spawns(self) -> None:
        for number, campaign in export.BOSS_SCENES.items():
            with self.subTest(boss=number):
                directory = OUTPUT / f"boss_{number:02d}"
                metadata = json.loads((directory / "level.json").read_text())
                prefab = ASSETS / metadata["source"]
                self.assertEqual(metadata["format"], 3)
                self.assertEqual(metadata["warnings"], [])
                self.assertEqual(metadata["source_sha256"], export.sha256(prefab))
                self.assertEqual(metadata["spawn_source_sha256"], export.sha256(ASSETS / metadata["spawn_source"]))
                source = export.levels.parse_scene(ASSETS / "Scenes" / f"Level{campaign}.unity")
                self.assertEqual({tag: metadata["markers"][tag] for tag in export.SPAWN_TAGS}, export.source_markers(source))
                self.assertEqual(len(metadata["markers"]["BossSpawnPoint"]), 2 if number == 4 else 1)
                for tag in ("EnemySpawnPoint", "Respawn", "WayPoint"):
                    self.assertEqual(metadata["markers"][tag], [], "Never merge unrelated campaign spawns")
                bounds = export.levels.legacy.validate_obj(directory / "stage.obj")
                self.assertEqual(list(bounds["bounds_min"]), metadata["visual_bounds_min"])
                self.assertEqual(list(bounds["bounds_max"]), metadata["visual_bounds_max"])
                self.assertGreater(metadata["source_summary"]["visual_renderers"], 20)
                self.assertGreater(metadata["source_summary"]["primitive_colliders"], 0)
                for state in metadata["material_render_modes"].values():
                    for key in ("lightmap_texture", "overlay_texture"):
                        if key in state:
                            self.assertTrue(state[key].startswith(metadata["resource_directory"] + "/"))
                            self.assertTrue((directory / Path(state[key]).name).is_file())
                glb = (directory / "level.glb").read_bytes()
                magic, version, size = struct.unpack_from("<4sII", glb)
                self.assertEqual((magic, version, size), (b"glTF", 2, len(glb)))
                json_size, kind = struct.unpack_from("<I4s", glb, 12)
                self.assertEqual(kind, b"JSON")
                gltf = json.loads(glb[20:20 + json_size])
                self.assertNotIn("uri", gltf["buffers"][0])
                binary = (directory / "stage.bin").read_bytes()
                self.assertEqual(glb[28 + json_size:28 + json_size + len(binary)], binary)
                self.assertTrue(all("TEXCOORD_1" in primitive["attributes"] for primitive in gltf["meshes"][0]["primitives"]))
                if number == 6:
                    self.assertEqual(metadata["source_root"]["source_unity_transform"][7], 300)
                    self.assertEqual(metadata["source_root"]["runtime_unity_transform"][7], 0)
                    self.assertLess(metadata["visual_bounds_min"][1], 2, "Boss6 must not float at y=300")

    def _source_materials(self, number: int) -> SourceMaterials:
        scene = export.levels.parse_scene(ASSETS / "Resources/level" / f"Boss{number}.prefab")
        resolver = export.levels.SceneResolver(scene)
        materials: SourceMaterials = {}
        for renderer in scene.renderers:
            if not resolver.active_in_hierarchy(renderer.game_object):
                continue
            for guid in renderer.material_guids:
                material = export.levels.legacy.parse_material(self.index.resolve(guid), self.index)
                name = export.levels.legacy._sanitize_name(material.name)
                # All six source arenas have unambiguous material names. Fail
                # closed if that changes instead of guessing by texture pixels.
                if name in materials:
                    self.assertEqual(materials[name][0], guid, f"Ambiguous source material: {name}")
                materials[name] = (guid, material)
        self.assertTrue(materials, f"Boss{number}: no source materials")
        return materials

    def _read_gltf(self, path: Path) -> dict:
        if path.suffix == ".gltf":
            return json.loads(path.read_text(encoding="utf-8"))
        data = path.read_bytes()
        self.assertEqual(struct.unpack_from("<4sII", data), (b"glTF", 2, len(data)))
        size, kind = struct.unpack_from("<I4s", data, 12)
        self.assertEqual(kind, b"JSON")
        return json.loads(data[20:20 + size])

    def _assert_texture_file(self, directory: Path, uri: str, source: Path, label: str,
                             *, exact_bytes: bool = False) -> None:
        destination = (directory / uri).resolve()
        self.assertTrue(destination.is_relative_to(directory.resolve()), f"Texture escapes arena: {uri}")
        self.assertTrue(destination.is_file(), f"Missing texture: {uri}; {label}")
        self.assertEqual(_image_fingerprint(destination), _image_fingerprint(source),
                         f"Texture pixels differ: {uri}; {label}; source={source}")
        if exact_bytes:
            self.assertEqual(export.sha256(destination), export.sha256(source),
                             f"Lightmap bytes differ: {uri}; {label}")

    def _assert_gltf_textures(self, directory: Path, document: dict, sources: SourceMaterials) -> None:
        names = [material["name"] for material in document["materials"]]
        self.assertCountEqual(names, sources, "glTF must retain every source material exactly once")
        used_images: set[int] = set()
        for material in document["materials"]:
            guid, source = sources[material["name"]]
            label = f"material={material['name']}; source GUID={guid}; diffuse"
            pbr = material["pbrMetallicRoughness"]
            if source.diffuse_source is None:
                self.assertNotIn("baseColorTexture", pbr, label)
                continue
            self.assertIn("baseColorTexture", pbr, f"Missing diffuse binding: {label}")
            texture_index = pbr["baseColorTexture"]["index"]
            self.assertIn(texture_index, range(len(document["textures"])), label)
            image_index = document["textures"][texture_index]["source"]
            self.assertIn(image_index, range(len(document["images"])), label)
            used_images.add(image_index)
            self._assert_texture_file(directory, document["images"][image_index]["uri"],
                                      source.diffuse_source, label)
        self.assertEqual(used_images, set(range(len(document["images"]))),
                         "Every glTF image must map to a source material GUID")

    def _assert_textures_match_source(self, number: int, directory: Path) -> None:
        sources = self._source_materials(number)
        for filename in ("stage.gltf", "level.glb"):
            self._assert_gltf_textures(directory, self._read_gltf(directory / filename), sources)
        metadata = json.loads((directory / "level.json").read_text(encoding="utf-8"))
        states = metadata["material_render_modes"]
        self.assertCountEqual(states, sources)
        for name, (guid, material) in sources.items():
            for role in ("lightmap", "overlay"):
                source = getattr(material, f"{role}_source")
                key = f"{role}_texture"
                label = f"material={name}; source GUID={guid}; {role}"
                if source is None:
                    self.assertNotIn(key, states[name], label)
                    continue
                self.assertIn(key, states[name], f"Missing {role} binding: {label}")
                resource = states[name][key]
                prefix = f"res://assets/models/boss_arenas/boss_{number:02d}/"
                self.assertTrue(resource.startswith(prefix), f"Wrong arena resource: {resource}")
                self._assert_texture_file(directory, resource.removeprefix(prefix), source,
                                          label, exact_bytes=role == "lightmap")

    def test_texture_pixels_and_lightmap_bytes_match_source(self) -> None:
        for number in export.BOSS_SCENES:
            with self.subTest(boss=number):
                self._assert_textures_match_source(number, OUTPUT / f"boss_{number:02d}")

    def test_missing_referenced_textures_are_rejected(self) -> None:
        for role in ("diffuse", "lightmap"):
            with self.subTest(role=role), _arena_fixture(2) as directory:
                self._assert_textures_match_source(2, directory)
                if role == "diffuse":
                    uri = self._read_gltf(directory / "stage.gltf")["images"][0]["uri"]
                else:
                    metadata = json.loads((directory / "level.json").read_text())
                    uri = next(Path(state["lightmap_texture"]).name
                               for state in metadata["material_render_modes"].values()
                               if "lightmap_texture" in state)
                (directory / uri).unlink()
                with self.assertRaisesRegex(AssertionError, "Missing texture"):
                    self._assert_textures_match_source(2, directory)

    def test_swapped_texture_files_are_rejected(self) -> None:
        with _arena_fixture(2) as directory:
            self._assert_textures_match_source(2, directory)
            first, second = (directory / name for name in ("sc03_2.png", "sc03_3.png"))
            self.assertNotEqual(_image_fingerprint(first), _image_fingerprint(second))
            first_bytes, second_bytes = first.read_bytes(), second.read_bytes()
            first.write_bytes(second_bytes)
            second.write_bytes(first_bytes)
            with self.assertRaisesRegex(AssertionError, "Texture pixels differ"):
                self._assert_textures_match_source(2, directory)

    def test_swapped_material_texture_bindings_are_rejected(self) -> None:
        for filename in ("stage.gltf", "level.glb"):
            with self.subTest(document=filename), _arena_fixture(2) as directory:
                self._assert_textures_match_source(2, directory)
                gltf_path = directory / "stage.gltf"
                original = gltf_path.read_bytes()
                document = self._read_gltf(gltf_path)
                first, second = (material["pbrMetallicRoughness"] for material in document["materials"][:2])
                first["baseColorTexture"], second["baseColorTexture"] = (
                    second["baseColorTexture"], first["baseColorTexture"])
                export.write_json(gltf_path, document)
                if filename == "level.glb":
                    (directory / filename).unlink()
                    export.pack_glb(gltf_path, directory / filename)
                    gltf_path.write_bytes(original)
                with self.assertRaisesRegex(AssertionError, "Texture pixels differ"):
                    self._assert_textures_match_source(2, directory)

    def test_existing_output_is_never_overwritten(self) -> None:
        sentinel = OUTPUT / "boss_01/level.json"
        before = sentinel.read_bytes()
        with self.assertRaises(FileExistsError):
            export.export_arena(1, ASSETS, OUTPUT, self.index, {}, {})
        self.assertEqual(sentinel.read_bytes(), before)

    def test_fresh_export_completes_and_restores_private_api(self) -> None:
        original_parse = export.levels.parse_scene
        original_scale = export.levels.TEXTURE_EXPORT_SCALE
        with tempfile.TemporaryDirectory(dir=export.REPO_ROOT / "tests") as temporary:
            result = export.export_arena(1, ASSETS, Path(temporary), self.index, {}, {})
            self.assertEqual(result["triangles"], 1909)
            directory = Path(temporary) / "boss_01"
            for filename in ("stage.obj", "stage.gltf", "stage.bin", "level.glb", "level.json"):
                self.assertEqual((directory / filename).read_bytes(), (OUTPUT / "boss_01" / filename).read_bytes())
            self._assert_textures_match_source(1, directory)
        self.assertIs(export.levels.parse_scene, original_parse)
        self.assertEqual(export.levels.TEXTURE_EXPORT_SCALE, original_scale)


if __name__ == "__main__":
    unittest.main()
