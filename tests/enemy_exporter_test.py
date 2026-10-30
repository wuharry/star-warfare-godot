"""Focused exporter safety and hierarchy-frame regressions; standard library only."""
import importlib.util
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("enemy_exporter_test_api", ROOT / "tools/unity_enemy_exporter/export.py")
api = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = api
SPEC.loader.exec_module(api)


class EnemyExporterTest(unittest.TestCase):
    def setUp(self):
        (ROOT / "test_output").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="enemy_exporter_fixture_", dir=ROOT / "test_output")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "unity"
        self.source.mkdir()

    def assert_blocked_before_writes(self, output, overwrite=False):
        with patch.object(Path, "mkdir", side_effect=AssertionError("mkdir reached")), \
             patch.object(Path, "write_bytes", side_effect=AssertionError("binary write reached")), \
             patch.object(Path, "write_text", side_effect=AssertionError("text write reached")), \
             patch.object(api.avatar, "copy_upscaled_texture", side_effect=AssertionError("texture copy reached")):
            with self.assertRaises((ValueError, FileExistsError)):
                api.export_enemy(self.source, Path("Resources/enemy/bogus.prefab"), output, overwrite=overwrite)

    def test_source_tree_is_read_only_with_and_without_overwrite(self):
        for overwrite in (False, True):
            self.assert_blocked_before_writes(self.source / "Assets/enemy.gltf", overwrite)
            self.assert_blocked_before_writes(self.source / "Assets/enemy.prefab", overwrite)
        self.assertEqual(list(self.source.iterdir()), [])

    def test_non_gltf_suffix_rejects_before_mkdir(self):
        self.assert_blocked_before_writes(self.root / "missing" / "enemy.bin")
        self.assertFalse((self.root / "missing").exists())

    def test_case_alias_of_source_is_still_read_only(self):
        alias = self.source.with_name(self.source.name.upper())
        if not alias.exists():
            self.skipTest("case-sensitive filesystem has no source alias")
        self.assert_blocked_before_writes(alias / "Assets/enemy.gltf", True)

    def test_existing_output_and_sidecar_require_explicit_overwrite(self):
        output = self.root / "export/enemy.gltf"
        output.parent.mkdir()
        for existing in (output, output.with_suffix(".bin"), output.with_name("enemy_export_report.json")):
            existing.write_bytes(b"artist bytes")
            self.assert_blocked_before_writes(output)
            self.assertEqual(existing.read_bytes(), b"artist bytes")
            self.assertEqual(api.validate_output(self.source, output, overwrite=True), output)
            existing.unlink()

    def test_symlinked_output_and_texture_targets_cannot_escape_into_source(self):
        link = self.root / "source_link"
        link.symlink_to(self.source, target_is_directory=True)
        self.assert_blocked_before_writes(link / "enemy.gltf", True)
        output = self.root / "export/enemy.gltf"
        output.parent.mkdir()
        (output.parent / "textures").symlink_to(self.source, target_is_directory=True)
        self.assert_blocked_before_writes(output, True)

    def test_tail06_frame_is_composed_at_every_key_not_only_rest(self):
        parent = "root/tail05/tail06"
        child = parent + "/arm"
        qz90 = (0.0, 0.0, math.sqrt(0.5), math.sqrt(0.5))
        qz180 = (0.0, 0.0, 1.0, 0.0)
        qx90 = (math.sqrt(0.5), 0.0, 0.0, math.sqrt(0.5))
        curves = {
            "translation": {parent: [(0, (1, 2, 3)), (1, (1, 2, 3))], child: [(0, (2, 0, 0)), (1, (2, 0, 0))]},
            "rotation": {parent: [(0, qz90), (1, qz180)], child: [(0, qx90), (1, qx90)]},
            "scale": {parent: [(0, (1, 1, 1)), (1, (1, 1, 1))], child: [(0, (1, 1, 1)), (1, (1, 1, 1))]},
        }
        baked = api.collapse_parent_curves(curves, child, [parent])
        for actual, expected in zip(baked["translation"][0][1], (1, 4, 3)):
            self.assertAlmostEqual(actual, expected)
        for actual, expected in zip(baked["translation"][-1][1], (-1, 2, 3)):
            self.assertAlmostEqual(actual, expected)
        for actual in baked["rotation"][0][1]:
            self.assertAlmostEqual(actual, 0.5)
        midway = api.sample_keys(baked["translation"], 0.5)
        self.assertAlmostEqual(midway[0], 1-math.sqrt(2))
        self.assertAlmostEqual(midway[1], 2+math.sqrt(2))

    def test_incomplete_or_sheared_parent_data_is_not_guessed(self):
        curves = {key: {"p/c": [(0, value)], "p": [(0, value)]} for key, value in
                  (("translation", (0, 0, 0)), ("rotation", (0, 0, 0, 1)), ("scale", (1, 1, 1)))}
        curves["scale"]["p"] = [(0, (2, 1, 1))]
        with self.assertRaisesRegex(ValueError, "shear"):
            api.collapse_parent_curves(curves, "p/c", ["p"])
        curves["scale"].pop("p")
        with self.assertRaisesRegex(ValueError, "Missing T/R/S"):
            api.collapse_parent_curves(curves, "p/c", ["p"])

    def test_leaf_name_alone_does_not_authorize_reparenting(self):
        node = SimpleNamespace(name="arm", path="enemy/root/left/arm", node_index=7)
        self.assertIsNone(api.removed_parent_binding("root/right/removed/arm", [node], "enemy"))
        self.assertEqual(api.removed_parent_binding("root/left/removed/arm", [node], "enemy"),
                         (7, ["root/left/removed"], ["root/left/removed"]))

    def test_original_attacked_clip_first_frame_matches_reviewer_evidence(self):
        clip = ROOT.parent / "star-warfare/Assets/AnimationClip/3/attacked.anim"
        self.assertTrue(clip.is_file(), "read-only Unity source fixture is required")
        curves = api.avatar.parse_animation(clip)
        parent = "Bone Spline 01/Bone tail 01/Bone tail 02/Bone tail 03/Bone tail 04/Bone tail 05/Bone tail 06"
        baked = api.collapse_parent_curves(curves, parent + "/Bone L Up01", [parent])
        expected = (-0.28873223019732663, -0.18398022214845083, 0.20563208464850008)
        for value, correct in zip(baked["translation"][0][1], expected):
            self.assertAlmostEqual(value, correct, places=6)
        self.assertGreater(len(baked["translation"]), 2, "animated parent rotation must affect translation after frame zero")

    def test_cli_report_uses_the_validated_canonical_destination(self):
        canonical = self.root / "canonical/actual.gltf"
        canonical.parent.mkdir()
        canonical.write_text("existing export")
        alias = self.root / "alias/enemy.gltf"
        alias.parent.mkdir()
        alias.symlink_to(canonical)
        source_file = self.source / "precious.prefab"
        source_file.write_text("source sentinel")
        alias.with_name("enemy_export_report.json").symlink_to(source_file)
        with patch.object(sys, "argv", ["export", "--project-root", str(self.source), "--prefab", "p.prefab",
                                         "--output", str(alias), "--overwrite"]), \
             patch.object(api, "export_enemy", return_value={"output": str(canonical)}), \
             patch("builtins.print"):
            self.assertEqual(api.main(), 0)
        self.assertEqual(source_file.read_text(), "source sentinel")
        self.assertTrue(canonical.with_name("actual_export_report.json").is_file())

    def test_original_machine_retains_shoulder_and_arm_animation_channels(self):
        source = ROOT.parent / "star-warfare"
        output = self.root / "machine/boss06.gltf"
        report = api.export_enemy(source, Path("Resources/enemy/boss06.prefab"), output)
        document = json.loads(output.read_text())
        self.assertFalse(report["unmatched_animation_paths"])
        # Shoulder tracks exist in every source clip. Distal Bone06/Bone16
        # are intentionally absent from e.g. attack01_joky in the source.
        for name in ("Bone05", "Bone15"):
            index = next(i for i, n in enumerate(document["nodes"]) if n["name"] == name)
            for animation in document["animations"]:
                channels = {c["target"]["path"] for c in animation["channels"] if c["target"]["node"] == index}
                self.assertIn("rotation", channels, (name, animation["name"]))


if __name__ == "__main__":
    unittest.main()
