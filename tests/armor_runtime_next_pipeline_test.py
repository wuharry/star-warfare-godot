"""Pure-Python failure guards for the Atom/Pegasus source pipeline.

No Godot, Blender, native image generation or real runtime resource is invoked.
"""
import importlib.util
import copy
import json
import math
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


PREPARE = load("next_armor_source_prepare", "tools/armor_runtime_v1/prepare_sources.py")
CONTRACT = load("next_armor_source_contract", "tools/armor_runtime_v1/first_integration_contract.py")
sys.modules["first_integration_contract"] = CONTRACT
PREPARE_GENERATION = load("prepare_generation", "tools/armor_runtime_v1/prepare_generation.py")
REGISTER_GENERATION = load("register_generation", "tools/armor_runtime_v1/register_generation.py")


class NextArmorPipelineTest(unittest.TestCase):
    def _generation_plan_fixture(self):
        output = ROOT / "test_output"
        output.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="armor_plan_guard_", dir=output)
        self.addCleanup(temporary.cleanup)
        sandbox = Path(temporary.name)
        work = sandbox / "docs/art/atom_runtime_v1"
        (work / "generated").mkdir(parents=True)
        base = sandbox / "docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt"
        base.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt", base)
        prompt = work / "prepared_prompt.txt"
        prompt.write_text(base.read_text(encoding="utf-8") + "\nFixture asset addendum\n", encoding="utf-8")
        references = []
        for index in range(2):
            source, snapshot = work / f"original_{index}.png", work / f"snapshot_{index}.png"
            source.write_bytes(b"immutable fixture reference bytes " + bytes([index]))
            shutil.copyfile(source, snapshot)
            references.append({"path": source.relative_to(sandbox).as_posix(), "snapshot": snapshot.relative_to(sandbox).as_posix(),
                               "sha256": CONTRACT.digest(source), "role": "edit_target" if index == 0 else "approved_body_design"})
        plan = {"label": "body", "prompt": prompt.relative_to(sandbox).as_posix(), "prompt_sha256": CONTRACT.digest(prompt),
                "base_prompt": base.relative_to(sandbox).as_posix(), "base_prompt_sha256": CONTRACT.digest(base),
                "references": references, "reference_images": [row["snapshot"] for row in references]}
        (work / "generation_plan.json").write_text(json.dumps([plan]))
        (work / "generation_inputs.json").write_bytes(b'[{"label":"body","selected":true,"existing_history":"keep exact bytes"}]')
        native = sandbox / "unused_native.png"
        native.write_bytes(b"Unused fixture: invalid plans must fail before opening this as an image")
        return sandbox, work, base, plan, native

    def _tree_bytes(self, root):
        return {path.relative_to(root).as_posix(): path.read_bytes() for path in root.rglob("*") if path.is_file()}

    def _assert_invalid_plan_has_no_side_effects(self, sandbox, work, base, plan, native, pattern):
        (work / "generation_plan.json").write_text(json.dumps([plan]))
        before = self._tree_bytes(sandbox)
        with patch.object(REGISTER_GENERATION, "ROOT", sandbox), patch.object(REGISTER_GENERATION, "BASE", base):
            with self.assertRaisesRegex(AssertionError, pattern):
                REGISTER_GENERATION.register_generation("atom", "body", native)
        self.assertEqual(self._tree_bytes(sandbox), before)

    def test_generation_prepare_cannot_rewrite_registered_history(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        before = self._tree_bytes(sandbox)
        with patch.object(PREPARE_GENERATION, "ROOT", sandbox), patch.object(sys, "argv", ["prepare_generation.py", "--armor", "atom"]):
            with self.assertRaisesRegex(FileExistsError, "history already exists"):
                PREPARE_GENERATION.main()
        self.assertEqual(self._tree_bytes(sandbox), before)

    def test_valid_generation_plan_is_read_only(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        before = self._tree_bytes(sandbox)
        with patch.object(REGISTER_GENERATION, "ROOT", sandbox), patch.object(REGISTER_GENERATION, "BASE", base):
            REGISTER_GENERATION.validate_plan(plan)
        self.assertEqual(self._tree_bytes(sandbox), before)

    def test_stale_prompt_plan_is_rejected_before_archive_or_history_write(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        (sandbox / plan["prompt"]).write_text("changed prepared prompt")
        self._assert_invalid_plan_has_no_side_effects(sandbox, work, base, plan, native, "Prepared prompt bytes changed")

    def test_stale_base_plan_is_rejected_before_archive_or_history_write(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        plan["base_prompt_sha256"] = "stale base hash"
        self._assert_invalid_plan_has_no_side_effects(sandbox, work, base, plan, native, "base prompt bytes changed")

    def test_missing_base_text_is_rejected_before_archive_or_history_write(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        (sandbox / plan["prompt"]).write_text("prompt without shared required text")
        plan["prompt_sha256"] = CONTRACT.digest(sandbox / plan["prompt"])
        self._assert_invalid_plan_has_no_side_effects(sandbox, work, base, plan, native, "omitted the required base")

    def test_stale_original_plan_is_rejected_before_archive_or_history_write(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        (sandbox / plan["references"][0]["path"]).write_bytes(b"changed original reference")
        self._assert_invalid_plan_has_no_side_effects(sandbox, work, base, plan, native, "Original reference bytes changed")

    def test_stale_snapshot_plan_is_rejected_before_archive_or_history_write(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        (sandbox / plan["references"][0]["snapshot"]).write_bytes(b"changed frozen reference")
        self._assert_invalid_plan_has_no_side_effects(sandbox, work, base, plan, native, "Frozen reference bytes changed")

    def test_unrecorded_actual_plan_reference_rejects_without_writes(self):
        sandbox, work, base, plan, native = self._generation_plan_fixture()
        plan["reference_images"][0] = "unrecorded.png"
        self._assert_invalid_plan_has_no_side_effects(sandbox, work, base, plan, native, "Actual reference path")

    def _retry_lineage(self):
        first = {"label": "body", "selected": False, "archive_sha256": "first_native",
                 "references": [{"role": "edit_target", "sha256": "original_atlas"}]}
        second = {"label": "body", "selected": False, "archive_sha256": "second_native",
                  "references": [{"role": "edit_target_previous_attempt", "sha256": "first_native"}]}
        third = {"label": "body", "selected": True, "archive_sha256": "third_native",
                 "references": [{"role": "edit_target_previous_attempt", "sha256": "second_native"}]}
        return [first, second, third]

    def test_two_retained_retry_generations_reach_true_original(self):
        rows = self._retry_lineage()
        for row in rows:
            CONTRACT.verify_edit_lineage(row, rows, "original_atlas")

    def test_selected_ancestor_can_be_restored_when_retry_rejected(self):
        rows = self._retry_lineage()
        rows[1]["selected"] = True
        rows[2]["selected"] = False
        rows[2]["status"] = "rejected_moved_rear_lamp_instead_of_front_window"
        for row in rows:
            CONTRACT.verify_edit_lineage(row, rows, "original_atlas")

    def test_selected_retry_and_parent_are_rejected(self):
        rows = self._retry_lineage()
        rows[1]["selected"] = True
        with self.assertRaisesRegex(AssertionError, "cannot both be selected"):
            CONTRACT.verify_edit_lineage(rows[2], rows, "original_atlas")

    def test_selected_retry_and_distant_ancestor_are_rejected(self):
        rows = self._retry_lineage()
        rows[0]["selected"] = True
        with self.assertRaisesRegex(AssertionError, "cannot both be selected"):
            CONTRACT.verify_edit_lineage(rows[2], rows, "original_atlas")

    def test_rejected_retry_does_not_hide_two_selected_ancestors(self):
        rows = self._retry_lineage()
        rows[2]["selected"] = False
        rows[0]["selected"] = rows[1]["selected"] = True
        with self.assertRaisesRegex(AssertionError, "cannot both be selected"):
            CONTRACT.verify_edit_lineage(rows[2], rows, "original_atlas")

    def test_retry_duplicate_native_parent_hash_is_rejected(self):
        rows = self._retry_lineage()
        duplicate = dict(rows[0])
        rows.insert(1, duplicate)
        with self.assertRaisesRegex(AssertionError, "one retained"):
            CONTRACT.verify_edit_lineage(rows[-1], rows, "original_atlas")

    def test_retry_without_retained_native_parent_is_rejected(self):
        rows = self._retry_lineage()
        rows[1]["references"][0]["sha256"] = "missing_native"
        with self.assertRaisesRegex(AssertionError, "one retained"):
            CONTRACT.verify_edit_lineage(rows[2], rows, "original_atlas")

    def test_retry_cannot_use_a_different_label_parent(self):
        rows = self._retry_lineage()
        rows[0]["label"] = "head"
        with self.assertRaisesRegex(AssertionError, "same label"):
            CONTRACT.verify_edit_lineage(rows[2], rows, "original_atlas")

    def test_retry_cycles_or_forward_links_are_rejected(self):
        rows = self._retry_lineage()
        rows[0]["references"][0] = {"role": "edit_target_previous_attempt", "sha256": "second_native"}
        with self.assertRaisesRegex(AssertionError, "precede"):
            CONTRACT.verify_edit_lineage(rows[2], rows, "original_atlas")

    def test_retry_cannot_rebase_to_another_original(self):
        rows = self._retry_lineage()
        rows[0]["references"][0]["sha256"] = "wrong_original"
        with self.assertRaisesRegex(AssertionError, "true original"):
            CONTRACT.verify_edit_lineage(rows[2], rows, "original_atlas")

    def _reference_fixture(self):
        output = ROOT / "test_output"
        output.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="armor_reference_guard_", dir=output)
        self.addCleanup(temporary.cleanup)
        sandbox = Path(temporary.name)
        (sandbox / "original.png").write_bytes(b"immutable source image bytes")
        (sandbox / "snapshot.png").write_bytes(b"immutable source image bytes")
        reference = {"path": "original.png", "snapshot": "snapshot.png", "sha256": CONTRACT.digest(sandbox / "original.png")}
        return sandbox, reference

    def test_actual_frozen_snapshot_reference_is_accepted(self):
        sandbox, reference = self._reference_fixture()
        with patch.object(CONTRACT, "ROOT", sandbox):
            CONTRACT.verify_reference(reference, "snapshot.png")

    def test_actual_original_reference_is_accepted(self):
        sandbox, reference = self._reference_fixture()
        with patch.object(CONTRACT, "ROOT", sandbox):
            CONTRACT.verify_reference(reference, "original.png")

    def test_unrecorded_passed_reference_is_rejected_even_with_same_bytes(self):
        sandbox, reference = self._reference_fixture()
        (sandbox / "unrecorded.png").write_bytes((sandbox / "snapshot.png").read_bytes())
        with patch.object(CONTRACT, "ROOT", sandbox), self.assertRaisesRegex(AssertionError, "path"):
            CONTRACT.verify_reference(reference, "unrecorded.png")

    def test_changed_snapshot_reference_is_rejected(self):
        sandbox, reference = self._reference_fixture()
        (sandbox / "snapshot.png").write_bytes(b"changed snapshot")
        with patch.object(CONTRACT, "ROOT", sandbox), self.assertRaisesRegex(AssertionError, "Frozen"):
            CONTRACT.verify_reference(reference, "snapshot.png")

    def test_changed_original_reference_is_rejected(self):
        sandbox, reference = self._reference_fixture()
        (sandbox / "original.png").write_bytes(b"changed original")
        with patch.object(CONTRACT, "ROOT", sandbox), self.assertRaisesRegex(AssertionError, "Original"):
            CONTRACT.verify_reference(reference, "snapshot.png")

    def test_actual_atom_body_material_order_is_detected(self):
        gltf = json.loads((ROOT / "assets/models/player/animated/player.gltf").read_text())
        node = next(row for row in gltf["nodes"] if row.get("name") == "ArmorBody_07")
        labels = []
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            material = gltf["materials"][primitive["material"]]
            index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            image = gltf["images"][gltf["textures"][index]["source"]]
            labels.append(PREPARE.texture_label(image["uri"]))
        self.assertEqual(labels, ["shoulder", "body"])

    def test_pegasus_original_texture_prefix(self):
        self.assertEqual(PREPARE.texture_label("res://armor/09_head_7f3e9b9b23ec_2x.png"), "head")
        self.assertEqual(PREPARE.texture_label("res://armor/09_jian_3d289fdf8273_2x.png"), "shoulder")
        with self.assertRaises(ValueError):
            PREPARE.texture_label("unknown.png")

    def test_uv_guide_keeps_original_outlier_coordinates(self):
        surface = {"uv": [[-.01, .2], [.5, .2], [.5, 1.02]], "indices": [0, 1, 2]}
        svg = PREPARE.uv_svg(surface)
        self.assertIn("-10.240000,204.800000", svg)
        self.assertIn("512.000000,1044.480000", svg)
        self.assertEqual(PREPARE.chart_count(surface), 1)

    def test_shapes_obey_current_explicit_source_contract(self):
        for slug in ["atom", "pegasus"]:
            shape = load(slug + "_shape_guard", f"tools/armor_runtime_v1/shapes/{slug}.py")
            work=ROOT / f"docs/art/{slug}_runtime_v1"
            config=CONTRACT.read(work / "runtime_config.json")
            source=CONTRACT.read(work / "revisions/original_source_v1/source.json")
            movable=CONTRACT.geometry_parts(config,source["parts"])
            for name,part in source["parts"].items():
                old=[point for row in part["surfaces"] for point in row["positions"]]
                new=[]
                for sid,row in enumerate(part["surfaces"]):
                    for point in row["positions"]:
                        result=shape.reshape_part(name,point,sid) if movable else shape.reshape(point)
                        self.assertTrue(len(result)==3 and all(math.isfinite(value) for value in result))
                        if name not in movable:self.assertEqual(result,point)
                        new.append(result)
                dimensions=lambda points:[max(point[axis] for point in points)-min(point[axis] for point in points) for axis in range(3)]
                before,after=dimensions(old),dimensions(new)
                self.assertLessEqual(max(math.dist(a,b) for a,b in zip(old,new))/min(before),.20)
                self.assertTrue(all(abs(a/b-1)<=.20 for a,b in zip(after,before)))
            self.assertFalse(hasattr(shape, "adjust_uv"))
            self.assertFalse(hasattr(shape, "refine_surface"))

    def _bounded_fixture(self, displacement=.05):
        identity=[[int(i==j) for j in range(4)] for i in range(4)]
        points=[[0.,0.,0.],[1.,0.,0.],[0.,1.,0.],[0.,0.,1.]]
        old={"positions":points,"raw_positions":copy.deepcopy(points),"normals":[[0.,0.,1.] for _ in points],
             "uv":[[0.,0.],[1.,0.],[0.,1.],[1.,1.]],"indices":[0,1,2,0,3,1,0,2,3,1,3,2],
             "bone_indices":[[0]*4 for _ in points],"bone_names":[["Root"]*4 for _ in points],"weights":[[1.,0.,0.,0.] for _ in points]}
        name="ArmorHead_07"
        source={"bones":[{"name":"Root","matrix":identity}],"parts":{name:{"surfaces":[old],"bind_records":[{"name":"Root","matrix":identity}]}}}
        positions=[[x+displacement,y,z] for x,y,z in points]
        new={"positions":positions,"uv":copy.deepcopy(old["uv"]),"label":"head","geometry_changed":displacement>1e-6,
             "raw_positions":copy.deepcopy(positions)}
        new["normals"],new["tangents"]=CONTRACT.bind_normal_frames(old,new["raw_positions"])
        target={"geometry_mode":"original_source_bounded_refinement","geometry_parts":[name],"parts":{name:{"surfaces":[new]}}}
        config={"preserve_all_geometry":False,"geometry_mode":target["geometry_mode"],"geometry_parts":[name]}
        surface={"surface":0,"label":"head","uv_coordinate_count":4,"uv_changed_count":0,"uv_changed_fraction":0}
        measured=max(math.dist(a,b) for a,b in zip(points,positions))
        geometry={"parts":{name:{"triangles":4,"uv_coordinate_count":4,"original_uv_coordinate_count":4,
                  "uv_changed_count":0,"original_uv_charts":1,"uv_charts":1,"uv_changed_fraction":0,
                  "max_displacement_fraction_of_smallest_dimension":measured,"dimension_delta_fraction":[0.,0.,0.],"uv_by_surface":[surface]}}}
        return source,target,geometry,{name:.20},config

    def test_bounded_refinement_accepts_authored_frames_with_exact_uv_and_original_budget(self):
        source,target,geometry,limits,config=self._bounded_fixture()
        measured=CONTRACT.measure_original_geometry(source,target,geometry,limits,config)
        self.assertEqual(measured["geometry_mode"],"original_source_bounded_refinement")
        self.assertAlmostEqual(measured["original_measurements"][0]["original_max_rest_displacement_fraction"],.05)
        self.assertEqual(measured["uv_coordinates"],4)

    def test_bounded_cannot_exceed_cumulative_true_original_twenty_percent(self):
        with self.assertRaisesRegex(AssertionError,"original-total shape limit exceeded"):
            CONTRACT.measure_original_geometry(*self._bounded_fixture(.201))

    def test_bounded_does_not_relax_twenty_percent_limit(self):
        args=list(self._bounded_fixture());args[3]={"ArmorHead_07":.25}
        with self.assertRaisesRegex(AssertionError,"remain 20%"):
            CONTRACT.measure_original_geometry(*args)

    def test_bounded_unknown_mode_or_nonoriginal_part_is_rejected(self):
        source,target,geometry,limits,config=self._bounded_fixture()
        for key,value in [("geometry_mode","anything"),("geometry_parts",["ArmorHead_99"])]:
            bad={**config,key:value}
            with self.assertRaises(AssertionError):CONTRACT.measure_original_geometry(source,target,geometry,limits,bad)

    def test_bounded_unauthorized_source_part_cannot_move(self):
        source,target,geometry,limits,config=self._bounded_fixture()
        source["parts"]["ArmorBody_07"]=copy.deepcopy(source["parts"]["ArmorHead_07"])
        target["parts"]["ArmorBody_07"]=copy.deepcopy(target["parts"]["ArmorHead_07"])
        with self.assertRaisesRegex(AssertionError,"positions changed"):
            CONTRACT.measure_original_geometry(source,target,geometry,limits,config)

    def test_bounded_cannot_hide_a_position_edit_as_unchanged(self):
        source,target,geometry,limits,config=self._bounded_fixture()
        target["parts"]["ArmorHead_07"]["surfaces"][0]["geometry_changed"]=False
        with self.assertRaisesRegex(AssertionError,"false geometry-change"):
            CONTRACT.measure_original_geometry(source,target,geometry,limits,config)

    def test_bounded_indices_weights_and_uv_must_remain_original(self):
        for field,replacement in [("indices",[0,2,1]),("weights",[[.5,.5,0.,0.]]*4),("uv",[[.01,0.],[1,0],[0,1],[1,1]])]:
            source,target,geometry,limits,config=self._bounded_fixture()
            target["parts"]["ArmorHead_07"]["surfaces"][0][field]=replacement
            with self.assertRaises(AssertionError):CONTRACT.measure_original_geometry(source,target,geometry,limits,config)

    def test_bounded_raw_bind_positions_must_resolve_to_authored_rest(self):
        source,target,geometry,limits,config=self._bounded_fixture()
        target["parts"]["ArmorHead_07"]["surfaces"][0]["raw_positions"][0][0]+=.01
        with self.assertRaisesRegex(AssertionError,"raw bind positions differ"):
            CONTRACT.measure_original_geometry(source,target,geometry,limits,config)

    def test_bounded_authored_normal_and_tangent_cannot_be_substituted(self):
        for field in ["normals","tangents"]:
            source,target,geometry,limits,config=self._bounded_fixture()
            target["parts"]["ArmorHead_07"]["surfaces"][0][field][0][0]+=.01
            with self.assertRaisesRegex(AssertionError,"normal/tangent frame changed"):
                CONTRACT.measure_original_geometry(source,target,geometry,limits,config)

    def test_triangle_reversal_and_new_degenerate_are_detected(self):
        old={"positions":[[0,0,0],[1,0,0],[0,1,0]],"indices":[0,1,2]}
        reversed_row={"positions":[[0,0,0],[0,1,0],[1,0,0]]}
        self.assertEqual(CONTRACT.part_shape_quality([old],[reversed_row])["reversed_triangles"],1)
        collapsed={"positions":[[0,0,0],[0,0,0],[0,1,0]]}
        self.assertEqual(CONTRACT.part_shape_quality([old],[collapsed])["new_degenerate_triangles"],1)

    def test_cross_surface_coincident_seams_must_not_split(self):
        old={"positions":[[0,0,0],[1,0,0],[0,1,0]],"indices":[0,1,2]}
        a,b=copy.deepcopy(old),copy.deepcopy(old);b["positions"][0][2]=.01
        self.assertAlmostEqual(CONTRACT.part_shape_quality([old,old],[a,b])["coincident_seam_max_rest_gap"],.01)

    def test_frozen_texture_only_delivery_remains_strict_and_verifiable(self):
        for slug in ["atom","pegasus"]:
            self.assertEqual(CONTRACT.verify_texture_history(slug)["files_verified"],96)
            frozen=ROOT/f"docs/art/{slug}_runtime_v1/revisions/before_draft_refinement_v2"
            files=CONTRACT.read(frozen/"snapshot.json")["files"]
            def locate(suffix):
                candidates=[ROOT/row['snapshot_path'] for row in files if row['original_path'].endswith(suffix)]
                self.assertEqual(len(candidates),1,suffix)
                return CONTRACT.read(candidates[0])
            source=locate("build/source.json");target=locate("build/target.json");geometry=locate("build/geometry.json");config=locate("runtime_config.json")
            self.assertTrue(config["preserve_all_geometry"])
            result=CONTRACT.measure_original_geometry(source,target,geometry,{name:.20 for name in source["parts"]},config)
            self.assertEqual(result["geometry_mode"],"texture_only")
            self.assertTrue(all(row["original_max_rest_displacement_fraction"]==0 for row in result["original_measurements"]))

    def test_existing_snapshot_cannot_be_overwritten(self):
        output = ROOT / "test_output"
        output.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="armor_source_guard_", dir=output) as temporary:
            sandbox = Path(temporary)
            frozen = sandbox / "docs/art/atom_runtime_v1/revisions/original_source_v1"
            frozen.mkdir(parents=True)
            sentinel = frozen / "source.json"
            sentinel.write_bytes(b"existing original bytes")
            with patch.object(PREPARE, "ROOT", sandbox), self.assertRaises(FileExistsError):
                PREPARE.prepare("atom")
            self.assertEqual(sentinel.read_bytes(), b"existing original bytes")

    def test_stale_engine_export_cannot_create_a_baseline(self):
        output = ROOT / "test_output"
        output.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="armor_stale_guard_", dir=output) as temporary:
            sandbox = Path(temporary)
            original = sandbox / "assets/models/player/animated/player.gltf"
            original.parent.mkdir(parents=True)
            original.write_text("{}")
            source = sandbox / "docs/art/atom_runtime_v1/build/source.json"
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps({"original_scene": "res://assets/models/player/animated/player.gltf", "original_scene_sha256": "stale"}))
            with patch.object(PREPARE, "ROOT", sandbox), self.assertRaisesRegex(AssertionError, "stale"):
                PREPARE.prepare("atom")
            self.assertFalse((source.parent.parent / "revisions/original_source_v1").exists())

    def test_texture_only_contract_rejects_position_edits(self):
        source = {"parts": {"ArmorHead_07": {"surfaces": [{"positions": [[0, 1, 0]], "uv": [[0, 0]]}]}}}
        target = {"parts": {"ArmorHead_07": {"surfaces": [{"positions": [[0, 1.001, 0]], "uv": [[0, 0]]}]}}}
        with self.assertRaisesRegex(AssertionError, "positions changed"):
            CONTRACT.measure_original_geometry(source, target, {}, {})

    def test_texture_only_contract_rejects_uv_edits(self):
        source = {"parts": {"ArmorHead_07": {"surfaces": [{"positions": [[0, 1, 0]], "uv": [[0, 0]]}]}}}
        target = {"parts": {"ArmorHead_07": {"surfaces": [{"positions": [[0, 1, 0]], "uv": [[.001, 0]]}]}}}
        with self.assertRaisesRegex(AssertionError, "UV changed"):
            CONTRACT.measure_original_geometry(source, target, {}, {})


if __name__ == "__main__":
    unittest.main()
