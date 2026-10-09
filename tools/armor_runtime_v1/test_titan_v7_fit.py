"""Check actual Titan v7 fit and exercise failures on immutable v6 mesh data.

Normal invocation runs in-memory negative fixtures without editing any asset.
--check-active validates the current authored target and inherited native art.
Neither mode launches Godot or Blender or substitutes for rendered coverage.
"""
import copy
import json
import math
import struct
import sys
import unittest

from neck_source_contract import discover_neck
from validate_titan_helmet import (ROOT, WORK, active_version, digest, read,
                                  verify_before, verify_generation, verify_shell_fit,
                                  verify_v7_generation, shell_profile_offsets,
                                  reviewed_visor_vertices)


def before_inputs():
    snapshot = verify_before(7)
    rows = {row["path"]: row for row in snapshot["files"]}
    previous_path = ROOT / rows["docs/art/titan_runtime_v1/build/target.json"]["snapshot"]
    previous = read(previous_path)
    assert previous["revision"] == "helmet_refinement_v6"
    source = read(WORK / "revisions/original_source_v1/source.json")
    original = source["parts"]["ArmorHead_05"]["surfaces"][0]
    return original, previous["parts"]["ArmorHead_05"]["surfaces"][0], snapshot


def f32(point):
    return list(struct.unpack("<3f", struct.pack("<3f", *point)))


class TitanV7ShellFitTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original, cls.previous, _ = before_inputs()
        cls.protected = set(discover_neck(cls.original)["vertex_ids"])

    def setUp(self):
        self.fit = {"delta_y": -.06}
        self.current = copy.deepcopy(self.previous)
        for i, point in enumerate(self.current["positions"]):
            if i not in self.protected:
                self.current["positions"][i] = f32([point[0], point[1] + self.fit["delta_y"], point[2]])

    def verify(self):
        return verify_shell_fit(self.original, self.previous, self.current, self.fit)

    def test_uniform_downward_shell_fit_passes(self):
        result = self.verify()
        self.assertEqual(result["translated_shell_vertices"], 310)
        self.assertEqual(result["original_neck_vertices_exact"], 24)
        self.assertIn("rendered mixed-body neck coverage is verified separately", result["scope"])

    def test_old_v6_geometry_is_not_accepted_as_v7(self):
        self.current = copy.deepcopy(self.previous)
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()

    def test_neck_source_stays_fixed_even_when_shell_moves(self):
        i = next(iter(self.protected))
        self.current["positions"][i][1] += self.fit["delta_y"]
        with self.assertRaisesRegex(AssertionError, "neck positions changed"):
            self.verify()

    def test_one_missed_shell_vertex_is_rejected(self):
        i = next(i for i in range(294) if i not in self.protected)
        self.current["positions"][i] = list(self.previous["positions"][i])
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()

    def test_one_missed_arc_midpoint_is_rejected(self):
        self.current["positions"][294] = list(self.previous["positions"][294])
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()

    def test_lateral_shell_shift_is_rejected(self):
        i = next(i for i in range(334) if i not in self.protected)
        self.current["positions"][i][0] += .001
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()

    def test_depth_shell_shift_is_rejected(self):
        i = next(i for i in range(334) if i not in self.protected)
        self.current["positions"][i][2] += .001
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()

    def test_upsizing_the_shell_is_rejected(self):
        for i in range(334):
            if i not in self.protected:
                self.current["positions"][i][0] *= 1.01
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()

    def test_uv_change_is_rejected(self):
        self.current["uv"][0][0] += .001
        with self.assertRaisesRegex(AssertionError, "changed reviewed uv"):
            self.verify()

    def test_shell_triangle_change_is_rejected(self):
        self.current["indices"][:3] = reversed(self.current["indices"][:3])
        self.assertNotEqual(self.current["indices"], self.previous["indices"])
        with self.assertRaisesRegex(AssertionError, "changed reviewed indices"):
            self.verify()

    def test_shell_weight_change_is_rejected(self):
        self.current["weights"][0][0] -= .01
        with self.assertRaisesRegex(AssertionError, "changed reviewed weights"):
            self.verify()

    def test_shell_bind_change_is_rejected(self):
        self.current["bone_indices"][0][0] += 1
        with self.assertRaisesRegex(AssertionError, "changed reviewed bone_indices"):
            self.verify()

    def test_shell_bone_name_change_is_rejected(self):
        self.current["bone_names"][0][0] = "Wrong Head"
        with self.assertRaisesRegex(AssertionError, "changed reviewed bone_names"):
            self.verify()

    def test_original_cage_rebaseline_is_rejected(self):
        self.current["baseline_positions"][0][1] += .001
        with self.assertRaisesRegex(AssertionError, "changed reviewed baseline_positions"):
            self.verify()

    def test_arc_original_edge_ownership_change_is_rejected(self):
        self.current["added_vertices"][0]["parents"] = [0, 1]
        with self.assertRaisesRegex(AssertionError, "changed arc ownership"):
            self.verify()

    def test_upward_zero_excessive_nan_and_boolean_deltas_are_rejected(self):
        for delta in (.06, 0, -.076, -.039, float("nan"), float("inf"), True):
            with self.subTest(delta=delta), self.assertRaisesRegex(AssertionError, "shell fit|Shell fit"):
                self.fit["delta_y"] = delta
                self.verify()

    def test_geometry_only_revision_cannot_claim_an_imagegen_call(self):
        record = {"record_type": "inherited_native_generation", "model_revision": "helmet_refinement_v7",
                  "tool": "image_gen.imagegen"}
        with self.assertRaisesRegex(AssertionError, "cannot claim a new raster generation"):
            verify_v7_generation({}, record, {}, {})

    def test_geometry_only_revision_cannot_claim_a_new_prompt_or_attempt(self):
        for key, value in (("prompt_path", "a-new-prompt.txt"), ("prompt_sha256", "0" * 64),
                           ("attempt", 1), ("native_output_path", "new.png")):
            record = {"record_type": "inherited_native_generation", "model_revision": "helmet_refinement_v7",
                      key: value}
            with self.subTest(field=key), self.assertRaisesRegex(AssertionError, "cannot claim a new raster generation"):
                verify_v7_generation({}, record, {}, {})

    def lower_group(self):
        anchor = next(i for i, p in enumerate(self.original["positions"])
                      if abs(p[0]) < 1e-5 and abs(p[1] - 1.29936) < 1e-4 and abs(p[2] + .22336) < 1e-4)
        return [i for i, p in enumerate(self.original["positions"])
                if math.dist(p, self.original["positions"][anchor]) <= 1e-5]

    def apply_profile(self):
        extras = shell_profile_offsets(self.original, self.previous, self.fit)
        for i, point in enumerate(self.previous["positions"]):
            if i not in self.protected:
                self.current["positions"][i] = f32([point[0], point[1] + self.fit["delta_y"] + extras[i], point[2]])
        return extras

    def test_complete_lower_seam_group_and_inherited_midpoint_profile_passes(self):
        ids = self.lower_group()
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids, "delta_y": -.025}]
        extras = self.apply_profile()
        self.assertGreater(sum(x != 0 for x in extras[294:]), 0)
        result = self.verify()
        self.assertEqual(result["profiled_original_shell_vertices"], len(ids))
        self.assertEqual(result["original_neck_vertices_exact"], 24)

    def test_partial_original_seam_group_is_rejected(self):
        ids = self.lower_group()
        self.assertGreater(len(ids), 1)
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids[:-1], "delta_y": -.02}]
        with self.assertRaisesRegex(AssertionError, "complete original physical seam group"):
            self.apply_profile()

    def test_overlapping_profile_rows_are_rejected(self):
        row = {"vertex_ids": self.lower_group(), "delta_y": -.02}
        self.fit["lower_frame_offsets"] = [copy.deepcopy(row), copy.deepcopy(row)]
        with self.assertRaisesRegex(AssertionError, "Overlapping lower frame"):
            self.apply_profile()

    def test_duplicate_profile_ids_are_rejected(self):
        ids = self.lower_group()
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids + ids[:1], "delta_y": -.02}]
        with self.assertRaisesRegex(AssertionError, "Duplicate lower frame"):
            self.apply_profile()

    def test_neck_profile_is_rejected(self):
        self.fit["lower_frame_offsets"] = [{"vertex_ids": [min(self.protected)], "delta_y": -.02}]
        with self.assertRaisesRegex(AssertionError, "cannot move original neck"):
            self.apply_profile()

    def test_midpoint_or_unknown_profile_ids_are_rejected(self):
        for ids in ([294], [334], [-1], [True], [0.0]):
            with self.subTest(ids=ids), self.assertRaisesRegex(AssertionError, "Unknown original lower frame"):
                self.fit["lower_frame_offsets"] = [{"vertex_ids": ids, "delta_y": -.02}]
                self.apply_profile()

    def test_positive_zero_nan_or_excessive_profile_offsets_are_rejected(self):
        for delta in (.01, 0, -.110001, float("nan"), float("inf"), True):
            with self.subTest(delta=delta), self.assertRaisesRegex(AssertionError, "finite, negative and at most"):
                self.fit["lower_frame_offsets"] = [{"vertex_ids": self.lower_group(), "delta_y": delta}]
                self.apply_profile()

    def test_gold_visor_local_extension_is_rejected(self):
        gold_vertices = reviewed_visor_vertices(self.previous)
        anchor = next(i for i in sorted(gold_vertices) if i < 294
                      and self.previous["positions"][i][1] + self.fit["delta_y"] < 1.58)
        ids = [i for i, p in enumerate(self.original["positions"])
               if math.dist(p, self.original["positions"][anchor]) <= 1e-5]
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids, "delta_y": -.02}]
        with self.assertRaisesRegex(AssertionError, "gold visor"):
            self.apply_profile()

    def test_mixed_physical_groups_are_rejected(self):
        ids = self.lower_group()
        other = next(i for i in range(294) if i not in ids and i not in self.protected)
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids + [other], "delta_y": -.02}]
        with self.assertRaisesRegex(AssertionError, "complete original physical seam group"):
            self.apply_profile()

    def test_rebased_source_position_is_rejected(self):
        ids = self.lower_group()
        point = list(self.original["positions"][ids[0]])
        point[1] += .001
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids, "delta_y": -.02,
                                             "source_physical_position_m": point}]
        with self.assertRaisesRegex(AssertionError, "physical position"):
            self.apply_profile()

    def test_upper_shell_profile_is_rejected(self):
        anchor = next(i for i, p in enumerate(self.previous["positions"][:294])
                      if p[1] + self.fit["delta_y"] >= 1.58 and i not in self.protected)
        ids = [i for i, p in enumerate(self.original["positions"])
               if math.dist(p, self.original["positions"][anchor]) <= 1e-5]
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids, "delta_y": -.02}]
        with self.assertRaisesRegex(AssertionError, "cannot alter upper shell"):
            self.apply_profile()

    def test_omitting_parent_offset_in_an_added_midpoint_is_rejected(self):
        self.fit["lower_frame_offsets"] = [{"vertex_ids": self.lower_group(), "delta_y": -.025}]
        extras = self.apply_profile()
        i = next(i for i in range(294, 334) if extras[i] != 0)
        before = self.previous["positions"][i]
        self.current["positions"][i] = f32([before[0], before[1] + self.fit["delta_y"], before[2]])
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()

    def test_extra_lateral_profile_deformation_is_rejected(self):
        ids = self.lower_group()
        self.fit["lower_frame_offsets"] = [{"vertex_ids": ids, "delta_y": -.025}]
        self.apply_profile()
        self.current["positions"][ids[0]][0] += .001
        with self.assertRaisesRegex(AssertionError, "reviewed shell shape"):
            self.verify()


class TitanV7ReferencePinTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from publish_titan_shell_fit import AUDITED_EXTRA_REFERENCE_SHADERS, verify_reference_resources
        path = ROOT / "docs/art/titan_neck_coverage_v2/review/before_final/capture.json"
        assert digest(path) == "b7815a104d5a45f22fa3fb80a58681a39e98a1096cc2d41f78a514823244c0af"
        cls.baseline = read(path)["reference_resource_sha256"]
        cls.current = {**cls.baseline, **{key: pins[0] for key, pins in AUDITED_EXTRA_REFERENCE_SHADERS.items()}}
        cls.check = staticmethod(verify_reference_resources)

    def test_exact_existing_pins_plus_two_audited_shader_pins_pass(self):
        self.check(self.current, self.baseline)

    def test_changed_frozen_reference_pin_is_rejected(self):
        bad = dict(self.current)
        bad[next(iter(self.baseline))] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "Frozen family resource SHA changed"):
            self.check(bad, self.baseline)

    def test_unknown_extra_shader_pin_is_rejected(self):
        bad = {**self.current, "res://assets/armors/titan_v1/not_audited.gdshader": "0" * 64}
        with self.assertRaisesRegex(AssertionError, "Unknown/missing extra"):
            self.check(bad, self.baseline)

    def test_wrong_audited_shader_pin_is_rejected(self):
        bad = {**self.current, "res://assets/armors/thunder/painted_armor.gdshader": "0" * 64}
        with self.assertRaisesRegex(AssertionError, "wrong audited SHA"):
            self.check(bad, self.baseline)


class TitanV7InheritedNativeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _, _, cls.snapshot = before_inputs()
        frozen = {row["path"]: row for row in cls.snapshot["files"]}
        cls.before_config = read(ROOT / frozen["docs/art/titan_runtime_v1/runtime_config.json"]["snapshot"])
        cls.parent_row = frozen["docs/art/titan_runtime_v1/revisions/helmet_refinement_v6/generation_record.json"]
        cls.parent = read(ROOT / cls.parent_row["snapshot"])

    def setUp(self):
        self.config = copy.deepcopy(self.before_config)
        self.config["shell_fit"] = {"delta_y": -.06}
        self.textures = {label: ROOT / self.config["asset"] / name
                         for label, name in self.config["texture_files"].items()}
        self.record = {"record_type": "inherited_native_generation", "model_revision": "helmet_refinement_v7",
                       "source_generation_record": {"path": self.parent_row["snapshot"], "sha256": self.parent_row["sha256"]},
                       "processing": "unchanged inherited v6 native PNG bytes; geometry-only shell fit",
                       "shell_fit": {"delta_y": -.06}}
        for key in ("canonical_path", "archive_path", "native_output_sha256", "dimensions", "alpha_extrema"):
            self.record[key] = copy.deepcopy(self.parent[key])

    def verify(self):
        return verify_v7_generation(self.config, self.record, self.textures, self.snapshot)

    def test_actual_v6_native_and_full_historical_lineage_pass(self):
        self.assertEqual(len(self.verify()), 5)

    def test_changed_inherited_record_identity_is_rejected(self):
        self.record["source_generation_record"]["sha256"] = "0" * 64
        with self.assertRaises(AssertionError):
            self.verify()

    def test_different_existing_head_png_is_rejected_without_editing_files(self):
        self.textures["head"] = WORK / "revisions/original_source_v1/atlases/head.png"
        with self.assertRaisesRegex(AssertionError, "changed native head PNG"):
            self.verify()

    def test_new_archive_claim_is_rejected(self):
        self.record["archive_path"] = "docs/art/titan_runtime_v1/revisions/helmet_refinement_v7/fake_new.png"
        with self.assertRaisesRegex(AssertionError, "changed archive_path"):
            self.verify()

    def test_rebased_native_sha_claim_is_rejected(self):
        self.record["native_output_sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "changed native_output_sha256"):
            self.verify()

    def test_mismatched_fit_provenance_is_rejected(self):
        self.record["shell_fit"]["delta_y"] = -.05
        with self.assertRaises(AssertionError):
            self.verify()


def check_active():
    config = read(WORK / "runtime_config.json")
    assert active_version(config) == 7, "Active target must be Titan v7"
    original, previous, snapshot = before_inputs()
    target_path = WORK / "build/target.json"
    target = read(target_path)
    assert target["revision"] == config["active_helmet_revision"]
    head = target["parts"]["ArmorHead_05"]["surfaces"][0]
    result = verify_shell_fit(original, previous, head, config["shell_fit"])
    textures = {label: ROOT / config["asset"] / name for label, name in config["texture_files"].items()}
    images = verify_generation(config, textures, snapshot)
    report = {"status": "PASS", "revision": config["active_helmet_revision"],
              "target_sha256": digest(target_path),
              "before_snapshot_sha256": digest(ROOT / config["before_revision_snapshot"]),
              "generation_record_sha256": digest(ROOT / config["generation_record"]),
              "shell_fit": result, "native_images": images,
              "scope": "Actual authored target and native PNG lineage. In-engine neck coverage is a separate rendered requirement."}
    output = WORK / "review/helmet_v7_shell_fit_test.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("TITAN_V7_SHELL_FIT_CONTRACT_PASS")


if __name__ == "__main__":
    if sys.argv[1:] == ["--check-active"]:
        check_active()
    else:
        unittest.main()
