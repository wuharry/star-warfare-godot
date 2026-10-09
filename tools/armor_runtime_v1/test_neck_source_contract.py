"""Exercise the original neck guard against actual-source mutations."""
import copy
import importlib.util
import hashlib
import json
from pathlib import Path
import struct
import unittest

from neck_source_contract import discover_neck, evaluate_neck, matching_neck_point, verify_neck

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"


class OriginalNeckContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = json.loads((WORK / "revisions/original_source_v1/source.json").read_text(encoding="utf-8-sig"))
        cls.original = source["parts"]["ArmorHead_05"]["surfaces"][0]
        cls.neck = discover_neck(cls.original)

    def setUp(self):
        self.authored = copy.deepcopy(self.original)

    def assert_rejected(self, text):
        with self.assertRaisesRegex(AssertionError, text):
            verify_neck(self.original, self.authored)

    def test_original_interface_passes(self):
        report = verify_neck(self.original, self.authored)
        self.assertEqual(report["physical_vertex_count"], 12)
        self.assertEqual(len(report["vertex_ids"]), 24)
        self.assertEqual(len(report["triangle_ids"]), 12)
        self.assertEqual(report["max_neck_displacement_m"], 0)

    def test_discovery_is_independent_of_vertex_numbering(self):
        reordered = copy.deepcopy(self.original)
        count = len(reordered["positions"])
        for field in ("positions", "raw_positions", "uv", "normals", "bone_indices", "bone_names", "weights"):
            reordered[field] = list(reversed(reordered[field]))
        reordered["indices"] = [count - 1 - i for i in reordered["indices"]]
        neck = discover_neck(reordered)
        self.assertEqual(set(neck["vertex_ids"]), {count - 1 - i for i in self.neck["vertex_ids"]})
        self.assertEqual(neck["physical_vertex_count"], 12)
        verify_neck(reordered, reordered)

    def test_discovery_uses_active_named_bones_not_unused_bind_slots(self):
        unrelated = copy.deepcopy(self.original)
        unrelated["bone_names"] = [["Bip01 Head"] * 4 for _ in unrelated["positions"]]
        with self.assertRaisesRegex(AssertionError, "No original head-to-torso"):
            discover_neck(unrelated)

    def test_one_moved_seam_duplicate_is_rejected(self):
        i = self.neck["vertex_ids"][0]
        self.authored["positions"][i][1] += .001
        self.assert_rejected("neck positions changed")

    def test_other_helmet_geometry_remains_authorable(self):
        i = next(i for i in range(len(self.authored["positions"])) if i not in self.neck["vertex_ids"])
        self.authored["positions"][i][1] += .02
        verify_neck(self.original, self.authored)

    def test_neck_uv_mutation_is_rejected(self):
        self.authored["uv"][self.neck["vertex_ids"][0]][0] += .001
        self.assert_rejected("neck uv changed")

    def test_neck_weights_mutation_is_rejected(self):
        self.authored["weights"][self.neck["vertex_ids"][0]][0] = .95
        self.assert_rejected("neck weights changed")

    def test_neck_bind_indices_mutation_is_rejected(self):
        self.authored["bone_indices"][self.neck["vertex_ids"][0]][0] += 1
        self.assert_rejected("neck bone_indices changed")

    def test_neck_named_bind_mutation_is_rejected(self):
        self.authored["bone_names"][self.neck["vertex_ids"][0]][0] = "Bip01 Head Wrong"
        self.assert_rejected("neck bone_names changed")

    def test_neck_raw_bind_position_mutation_is_rejected(self):
        self.authored["raw_positions"][self.neck["vertex_ids"][0]][0] += .001
        self.assert_rejected("neck raw_positions changed")

    def test_removed_neck_face_is_rejected(self):
        start = self.neck["triangle_ids"][0] * 3
        del self.authored["indices"][start:start+3]
        self.assert_rejected("neck triangles changed")

    def test_duplicate_neck_face_is_rejected(self):
        start = self.neck["triangle_ids"][0] * 3
        self.authored["indices"].extend(self.authored["indices"][start:start+3])
        self.assert_rejected("neck triangles changed")

    def test_reversed_neck_face_is_rejected(self):
        start = self.neck["triangle_ids"][0] * 3
        self.authored["indices"][start:start+3] = reversed(self.authored["indices"][start:start+3])
        self.assert_rejected("neck triangles changed")

    def test_new_face_attached_to_neck_is_rejected(self):
        self.authored["indices"].extend([self.neck["vertex_ids"][0], 0, 1])
        self.assert_rejected("neck triangles changed")

    def test_all_neck_duplicates_are_identified_from_physical_points(self):
        f32 = lambda p: list(struct.unpack("<3f", struct.pack("<3f", *p)))
        for i in self.neck["vertex_ids"]:
            self.assertIsNotNone(matching_neck_point(f32(self.original["positions"][i]), self.neck))
        self.assertIsNone(matching_neck_point([100, 100, 100], self.neck))

    def test_guard_scope_does_not_claim_rendered_mixed_body_coverage(self):
        self.assertIn("rendered mixed-body coverage is a separate requirement", evaluate_neck(self.original, self.authored)["scope"])


class TitanShapeNeckProtectionTest(unittest.TestCase):
    def setUp(self):
        source = json.loads((WORK / "revisions/original_source_v1/source.json").read_text(encoding="utf-8-sig"))
        self.original = source["parts"]["ArmorHead_05"]["surfaces"][0]
        self.neck = discover_neck(self.original)
        spec = importlib.util.spec_from_file_location("titan_shape_under_test", ROOT / "tools/armor_runtime_v1/shapes/titan.py")
        self.shape = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.shape)
        path = ROOT / "docs/art/titan_neck_mix_v1/revisions/before_neck_fix/docs/art/titan_runtime_v1/build/target.json"
        # This is the immutable delivered v5 target, not a newly approved base.
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), "4dd127a135f0585d6c5d229864eb40dc49246c5f3ce130eae7ae5d8abc2b7acf")
        self.before = json.loads(path.read_text(encoding="utf-8-sig"))["parts"]["ArmorHead_05"]["surfaces"][0]

    @staticmethod
    def float32(point):
        return list(struct.unpack("<3f", struct.pack("<3f", *point)))

    def make_shape(self):
        self.shape.configure_neck_source(self.original)
        positions = [self.float32(self.shape.reshape(self.float32(p))) for p in self.original["positions"]]
        uv = [self.shape.adjust_uv(p, u) for p, u in zip(positions, self.original["uv"])]
        row, authored = self.shape.refine_surface(self.original, positions, uv)
        row["positions"] = [self.float32(p) for p in authored]
        return row

    def test_real_previous_v5_neck_fault_remains_reproducible(self):
        report = evaluate_neck(self.original, self.before)
        self.assertEqual(report["status"], "FAIL")
        self.assertEqual(len(report["moved_vertex_ids"]), 8)
        self.assertAlmostEqual(report["max_neck_displacement_m"], .01579902988286401)
        self.assertTrue(report["neck_triangles_exact"])

    def test_shape_refuses_to_run_without_original_neck_source(self):
        with self.assertRaisesRegex(AssertionError, "true original neck source"):
            self.shape.reshape(self.original["positions"][0])

    def test_real_shape_preserves_all_neck_vertices_and_channels(self):
        report = verify_neck(self.original, self.make_shape())
        self.assertEqual(report["moved_vertex_ids"], [])
        self.assertLess(report["max_neck_displacement_m"], 1e-12)

    def test_round_helmet_shape_outside_neck_is_exactly_unchanged(self):
        authored = self.make_shape()
        protected = set(self.neck["vertex_ids"])
        for i, point in enumerate(authored["positions"]):
            if i not in protected:
                self.assertEqual(point, self.before["positions"][i], "Changed approved helmet vertex " + str(i))
        for field in ("uv", "indices", "bone_names", "bone_indices", "weights"):
            self.assertEqual(authored[field], self.before[field])

    def test_future_alignment_cannot_move_a_neck_duplicate(self):
        self.shape.configure_neck_source(self.original)
        i = self.neck["vertex_ids"][0]
        key = tuple(round(abs(v) if axis == 0 else v, 4) for axis, v in enumerate(self.original["positions"][i]))
        self.shape.DRAFT_ALIGNMENT_OFFSETS[key] = (0, .001, 0)
        with self.assertRaisesRegex(AssertionError, "neck positions changed"):
            self.make_shape()


if __name__ == "__main__":
    unittest.main()
