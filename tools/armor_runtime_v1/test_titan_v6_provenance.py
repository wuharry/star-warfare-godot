"""The neck fix cannot approve unrelated helmet changes or rewrite v5."""
import copy
import json
from pathlib import Path
import struct
import unittest

import validate_titan_helmet as validation
from neck_source_contract import discover_neck

ROOT = Path(__file__).resolve().parents[2]


class TitanV6GeometryProvenanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = validation.verify_before(6)
        frozen = {row["path"]: row for row in cls.snapshot["files"]}
        cls.old_config = validation.read(ROOT / frozen["docs/art/titan_runtime_v1/runtime_config.json"]["snapshot"])
        cls.original = validation.read(ROOT / frozen["docs/art/titan_runtime_v1/build/source.json"]["snapshot"])
        cls.old_target = validation.read(ROOT / frozen["docs/art/titan_runtime_v1/build/target.json"]["snapshot"])
        cls.neck = discover_neck(cls.original["parts"]["ArmorHead_05"]["surfaces"][0])

    def setUp(self):
        self.config = copy.deepcopy(self.old_config)
        self.config.update(active_helmet_revision="helmet_refinement_v6",
                           generation_record="docs/art/titan_runtime_v1/revisions/helmet_refinement_v6/generation_record.json",
                           before_revision_snapshot=validation.NECK_BEFORE.relative_to(ROOT).as_posix())
        self.config["head_refinement"]["revision"] = "helmet_refinement_v6"
        self.target = copy.deepcopy(self.old_target)
        self.target["revision"] = "helmet_refinement_v6"
        self.head = self.target["parts"]["ArmorHead_05"]["surfaces"][0]
        original_head = self.original["parts"]["ArmorHead_05"]["surfaces"][0]
        for i in self.neck["vertex_ids"]:
            self.head["positions"][i] = list(struct.unpack("<3f", struct.pack("<3f", *original_head["positions"][i])))

    def verify(self):
        return validation.verify_target(self.config, self.original, self.target, self.snapshot)

    def test_exact_v6_neck_only_fix_passes(self):
        report = self.verify()
        self.assertEqual(report["original_neck_interface"]["status"], "PASS")
        self.assertEqual(len(report["neck_only_geometry_revision"]["restored_neck_vertex_ids"]), 8)
        self.assertEqual(report["neck_only_geometry_revision"]["other_helmet_positions_exact"], 310)

    def test_original_v5_historical_contract_still_passes_without_new_guarantee(self):
        report = validation.verify_target(self.old_config, self.original, self.old_target, validation.verify_before(5))
        self.assertNotIn("original_neck_interface", report)
        self.assertNotIn("neck_only_geometry_revision", report)

    def test_v6_refuses_to_retain_previous_neck_drift(self):
        self.head["positions"] = copy.deepcopy(self.old_target["parts"]["ArmorHead_05"]["surfaces"][0]["positions"])
        with self.assertRaisesRegex(AssertionError, "Original neck positions changed"):
            self.verify()

    def test_v6_refuses_unrelated_round_visor_change(self):
        self.head["positions"][20][2] += .001
        # A matching metadata edit must not reapprove a changed visor.
        for row in self.head["added_vertices"]:
            if 20 in row["parents"]:
                a, b = row["parents"]
                row["bend"] = [p - (u + v) / 2 for p, u, v in zip(self.head["positions"][row["index"]], self.head["positions"][a], self.head["positions"][b])]
        with self.assertRaisesRegex(AssertionError, "non-neck helmet vertex 20"):
            self.verify()

    def test_v6_refuses_unrelated_added_arc_vertex_change(self):
        self.head["positions"][300][2] += .0000005
        with self.assertRaisesRegex(AssertionError, "non-neck helmet vertex 300"):
            self.verify()

    def test_v6_refuses_neck_uv_change(self):
        self.head["uv"][self.neck["vertex_ids"][0]][0] += .00001
        with self.assertRaisesRegex(AssertionError, "Original neck uv changed"):
            self.verify()

    def test_v6_refuses_unchanged_uv_count_but_repainted_coordinate_layout(self):
        self.head["uv"][0][0] += .0000001
        with self.assertRaisesRegex(AssertionError, "changed the reviewed head uv"):
            self.verify()

    def test_v6_refuses_body_geometry_change(self):
        self.target["parts"]["ArmorBody_05"]["surfaces"][0]["positions"][0][0] += .001
        with self.assertRaisesRegex(AssertionError, "Non-head geometry changed"):
            self.verify()

    def test_v6_refuses_count_budget_rebase(self):
        self.config["head_refinement"]["vertices"] += 1
        with self.assertRaisesRegex(AssertionError, "cannot increase"):
            validation.active_version(self.config)

    def test_v6_refuses_using_an_unpinned_before_path(self):
        self.config["before_revision_snapshot"] = "docs/art/titan_runtime_v1/revisions/before_helmet_refinement_v6/snapshot.json"
        with self.assertRaises(AssertionError):
            validation.active_version(self.config)


class TitanV6NativeLineageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = validation.verify_before(6)
        cls.config = validation.read(validation.WORK / "runtime_config.json")
        cls.generation = validation.read(ROOT / cls.config["generation_record"])
        assert cls.config["active_helmet_revision"] == "helmet_refinement_v6"

    def setUp(self):
        self.record = copy.deepcopy(self.generation)

    def verify(self):
        validation.verify_v6_generation(self.config, self.record, self.snapshot)

    def test_actual_native_v6_and_historical_v5_v4_v3_chain_pass(self):
        self.verify()

    def test_changed_previous_revision_identity_is_rejected(self):
        self.record["previous_revision_record"]["sha256"] = "0" * 64
        with self.assertRaises(AssertionError):
            self.verify()

    def test_postprocessed_image_claim_is_rejected(self):
        self.record["processing"] = "native followed by recoloring neck pixels"
        with self.assertRaises(AssertionError):
            self.verify()

    def test_missing_original_neck_texture_authority_is_rejected(self):
        for ref in self.record["references"]:
            if ref["role"] == "original_neck_texture":
                ref["role"] = "optional_inspiration"
        with self.assertRaisesRegex(AssertionError, "true-original neck atlas"):
            self.verify()

    def test_rebased_first_attempt_input_is_rejected(self):
        self.record = copy.deepcopy(validation.read(validation.WORK / "revisions/helmet_refinement_v6/generation_record.json"))
        if self.record["attempt"] != 1:
            self.record = validation.read(validation.WORK / "revisions/helmet_refinement_v6/generation_record_attempt_01.json")
        original = next(ref for ref in self.record["references"] if ref["role"] == "original_neck_texture")
        self.record["references"][0].update(path=original["path"], snapshot=original["snapshot"], sha256=original["sha256"])
        with self.assertRaisesRegex(AssertionError, "not based on frozen v5 head"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
