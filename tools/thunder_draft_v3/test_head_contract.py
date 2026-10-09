"""Reject corrupted geometry/provenance; no Godot or image edits are involved."""

import copy
import json
import unittest

from head_contract import ROOT, HeadContractError, geometry_metrics, validate_files, validate_target


class OriginalHeadGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = ROOT / "docs/art/thunder_draft_v3/runtime_config.json"
        config = json.loads(cls.config.read_text())
        cls.source = json.loads((ROOT / config["head_source_json"].removeprefix("res://")).read_text())
        cls.target = json.loads((ROOT / config["head_target"].removeprefix("res://")).read_text())

    def test_current_target_and_all_pins(self):
        metrics = validate_files(self.config)
        self.assertGreater(metrics["max_rest_displacement"], 1e-6)
        self.assertLessEqual(metrics["max_displacement_fraction_of_smallest_dimension"], .20)
        self.assertEqual(metrics["flipped_triangles"], [])
        self.assertEqual(metrics["new_degenerate_triangles"], [])
        self.assertEqual(metrics["seam_breaks"], [])

    def test_immutable_original_channels(self):
        for field in ["uv", "indices", "bone_indices", "weights", "binds"]:
            with self.subTest(field=field):
                target = copy.deepcopy(self.target)
                target[field] = []
                with self.assertRaisesRegex(HeadContractError, field):
                    validate_target(self.source, target)

    def test_source_rebase(self):
        target = copy.deepcopy(self.target)
        target["source_positions"] = copy.deepcopy(target["positions"])
        with self.assertRaisesRegex(HeadContractError, "rebased"):
            validate_target(self.source, target)

    def test_source_pin_rebase(self):
        target = copy.deepcopy(self.target)
        target["source_scene_sha256"] = "0" * 64
        with self.assertRaisesRegex(HeadContractError, "source_scene_sha256"):
            validate_target(self.source, target)

    def test_displacement_over_limit(self):
        target = copy.deepcopy(self.target)
        target["positions"][0][0] += .5
        with self.assertRaisesRegex(HeadContractError, "20%"):
            validate_target(self.source, target)

    def test_limit_cannot_be_raised(self):
        target = copy.deepcopy(self.target)
        target["geometry_limit"] = .30
        with self.assertRaisesRegex(HeadContractError, "fixed original limit"):
            validate_target(self.source, target)

    def test_metadata_cannot_claim_smaller_displacement(self):
        target = copy.deepcopy(self.target)
        target["max_cumulative_source_displacement_fraction"] = 0
        with self.assertRaisesRegex(HeadContractError, "metadata"):
            validate_target(self.source, target)

    def test_normalizer_cannot_be_rebased(self):
        target = copy.deepcopy(self.target)
        target["normalizer_original_smallest_dimension_m"] *= 2
        with self.assertRaisesRegex(HeadContractError, "normalizer"):
            validate_target(self.source, target)

    def test_noop_geometry_rejected(self):
        target = copy.deepcopy(self.target)
        target["positions"] = copy.deepcopy(self.source["positions"])
        with self.assertRaisesRegex(HeadContractError, "no actual"):
            validate_target(self.source, target)

    def test_nonfinite_geometry_rejected(self):
        target = copy.deepcopy(self.target)
        target["positions"][0][0] = float("nan")
        with self.assertRaisesRegex(HeadContractError, "finite"):
            validate_target(self.source, target)

    def test_raw_physical_conversion(self):
        target = copy.deepcopy(self.target)
        target["physical_positions"][0][1] *= -1
        with self.assertRaisesRegex(HeadContractError, "physical"):
            validate_target(self.source, target)

    def test_duplicate_position_seam_cannot_split(self):
        source = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 0]]
        target = [[p[0] + .01, p[1], p[2]] for p in source]
        target[4][1] += .01
        with self.assertRaisesRegex(HeadContractError, "split seams"):
            geometry_metrics(source, target, [0, 1, 2])

    def test_dimension_change_limit_independent_of_displacement(self):
        source = [[0, 0, 0], [1, 1, 1]]
        target = [[-.15, 0, 0], [1.15, 1, 1]]
        with self.assertRaisesRegex(HeadContractError, "dimension change"):
            geometry_metrics(source, target, [])

    def test_triangle_flip_rejected_within_displacement_budget(self):
        source = [[0, 0, 0], [.01, 0, 0], [0, .01, 0], [1, 1, 1]]
        target = [[0, 0, 0], [-.01, 0, 0], [0, .01, 0], [1, 1, 1]]
        with self.assertRaisesRegex(HeadContractError, "triangle flips"):
            geometry_metrics(source, target, [0, 1, 2])

    def test_new_degenerate_rejected_within_displacement_budget(self):
        source = [[0, 0, 0], [.01, 0, 0], [0, .01, 0], [1, 1, 1]]
        target = [[0, 0, 0], [0, 0, 0], [0, .01, 0], [1, 1, 1]]
        with self.assertRaisesRegex(HeadContractError, "new degenerate"):
            geometry_metrics(source, target, [0, 1, 2])


if __name__ == "__main__":
    unittest.main()
