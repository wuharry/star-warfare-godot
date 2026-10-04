"""Validate actual generation records and record the final Tank delivery.

Read-only for assets; writes manifest.json after fresh runtime/Blender checks.
"""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/tank_runtime_v1"
LABELS = {"head", "body", "shoulder", "hand", "foot"}


def describe(path):
    path = Path(path)
    if not path.is_absolute():
        path = ROOT / path
    path = path.resolve()
    data = path.read_bytes()
    row = {"path": path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path),
           "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    if path.suffix.lower() in {".png", ".jpg", ".jpeg"}:
        with Image.open(path) as image:
            row["dimensions"] = list(image.size)
            row["mode"] = image.mode
    return row


def main():
    inputs = json.loads((WORK / "generation_inputs.json").read_text(encoding="utf-8"))
    chosen = [row for row in inputs if row["selected"]]
    # Actual generation labels include attempt/version names. Canonical output
    # defines the runtime slot; retain the tool's original label as provenance.
    runtime_label=lambda row:Path(row["output"]).stem.removesuffix("_diffuse")
    assert len(chosen) == 5 and {runtime_label(row) for row in chosen} == LABELS
    head_variant=next(row['variant'] for row in chosen if runtime_label(row)=='head')
    baseline = WORK / "revisions/before_helmet_refinement_v3"
    frozen = json.loads((baseline / "snapshot.json").read_text(encoding="utf-8"))
    for filename in ("source.json",):
        assert (WORK / "build" / filename).read_bytes() == (baseline / "delivery" / filename).read_bytes(), "Head stage changed true source " + filename
    for name, record in frozen["files"].items():
        assert describe(baseline / name)["sha256"] == record["sha256"], "Frozen baseline changed " + name
    generation = []
    for row in inputs:
        archive = describe(row["archive"])
        assert archive["sha256"] == row["sha256"], "Archived generation differs from actual output"
        assert archive["dimensions"] == row["dimensions"]
        references = []
        for reference in row["references"]:
            current = describe(reference["path"])
            if current["sha256"] != reference["sha256"]:
                saved = next((describe(item["archive"]) for item in inputs
                              if item["sha256"] == reference["sha256"]), None)
                assert saved is not None, "Missing immutable generation reference snapshot"
                saved["actual_input_path"] = reference["path"]
                current = saved
            references.append(current)
        entry = {**row, "archive": archive, "prompt": describe(row["prompt"]),
                 "references": references, "original_generation_path": row["generated_file"]}
        if row["selected"]:
            assert row.get("variant", "").startswith("helmet_refinement_") if runtime_label(row)=="head" else row.get("variant", "").startswith("style_unified_"), "Wrong selected current stage"
            prompt_path = ROOT / row["prompt"]
            base_path = ROOT / row["base_prompt"]
            assert describe(prompt_path)["sha256"] == row["prompt_sha256"]
            assert describe(base_path)["sha256"] == row["base_prompt_sha256"]
            assert prompt_path.read_text(encoding="utf-8").startswith(base_path.read_text(encoding="utf-8")), "Missing actual common base prompt"
            canonical = describe(row["output"])
            assert canonical["sha256"] == archive["sha256"]
            entry["canonical"] = canonical
            entry["runtime_label"] = runtime_label(row)
        generation.append(entry)
    tests = {}
    for name in ["runtime_test", "roundtrip_test", "proportion_test", "delivery_validate", "helmet_refinement_invariants", "glb_images_test"]:
        path = WORK / f"review/{name}.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        assert report["status"] == "PASS", f"{name}: validation not passed"
        tests[name] = {"file": describe(path), "status": report["status"]}
    delivery = json.loads((WORK / "review/delivery_validate.json").read_text(encoding="utf-8"))
    for key, path in [("master_sha256", WORK / "build/tank_master.blend"),
                      ("source_sha256", WORK / "build/source.json"),
                      ("target_sha256", WORK / "build/target.json")]:
        assert delivery[key] == describe(path)["sha256"], "Stale packed-master validation"
    for label, record in delivery["images"].items():
        assert record["canonical_sha256"] == describe(f"assets/armors/tank_v1/{label}_diffuse.png")["sha256"]
    runtime = json.loads((WORK / "review/runtime_test.json").read_text(encoding="utf-8"))
    assert runtime["runtime_scene_sha256"] == describe("assets/armors/tank_v1/tank.scn")["sha256"]
    assert runtime["target_sha256"] == describe(WORK / "build/target.json")["sha256"]
    capture = json.loads((WORK / "review/engine/capture.json").read_text(encoding="utf-8"))
    assert capture["save_unchanged"] and len(capture["files"]) == 64
    assert capture["runtime_scene_sha256"] == describe("assets/armors/tank_v1/tank.scn")["sha256"]
    assert capture["target_sha256"] == describe(WORK / "build/target.json")["sha256"]
    assert capture["scene_sha256_at_start"] == capture["runtime_scene_sha256"]
    assert capture["target_sha256_at_start"] == capture["target_sha256"]
    assert capture["resource_mode"] == "normal_imported_resources"
    assert capture["canonical_diffuse_sha256_at_start"] == {label:describe(f"assets/armors/tank_v1/{label}_diffuse.png")["sha256"] for label in LABELS}
    for resource in capture["files"]:
        assert capture["capture_sha256"][resource] == describe(resource.removeprefix("res://"))["sha256"]
    startup_log = WORK / "review/helmet_refinement_angle_capture.log"
    startup = startup_log.read_text(encoding="utf-8")
    banner = next(line for line in startup.splitlines() if line.startswith("OpenGL API "))
    assert "ANGLE" in banner and "Direct3D11" in banner and "TANK_CAPTURE_PASS files=64 save_unchanged=true" in startup
    roundtrip=json.loads((WORK / "review/roundtrip_test.json").read_text(encoding="utf-8"))
    assert roundtrip["glb_sha256"] == describe("assets/armors/tank_v1/tank.glb")["sha256"]
    assert roundtrip["runtime_scene_sha256"] == capture["runtime_scene_sha256"] and roundtrip["target_sha256"] == capture["target_sha256"]
    assert roundtrip["head_atlas_pixels"]["canonical_sha256"] == describe("assets/armors/tank_v1/head_diffuse.png")["sha256"]
    assert len(roundtrip["head_atlas_pixels"]["samples"]) >= 30 and roundtrip["head_atlas_pixels"]["max_rgb_error"] <= .05
    assert runtime["save_unchanged"] and roundtrip["save_unchanged"]
    invariants = json.loads((WORK / "review/helmet_refinement_invariants.json").read_text(encoding="utf-8"))
    assert invariants["before_scene_sha256"] == describe(baseline / "delivery/tank.scn")["sha256"]
    assert invariants["current_scene_sha256"] == capture["runtime_scene_sha256"]
    for key, path in [("master_sha256", WORK / "build/tank_master.blend"), ("source_sha256", WORK / "build/source.json"), ("target_sha256", WORK / "build/target.json"), ("geometry_sha256", WORK / "build/geometry.json")]:
        assert invariants[key] == describe(path)["sha256"], "Stale paint-only invariant " + key
    assert invariants["additional_vertex_position_changes"] > 0 and invariants["additional_uv_changes"] == 0
    assert invariants["positions_changed_parts"] == ["ArmorHead_02"] and invariants["original_total_limit"] == .20
    for label in LABELS - {"head"}: assert describe(f"assets/armors/tank_v1/{label}_diffuse.png")["sha256"] == frozen["files"][f"atlases/{label}_diffuse.png"]["sha256"], "Body/limb atlas changed in head-only stage"
    full_pixels = json.loads((WORK / "review/glb_images_test.json").read_text(encoding="utf-8"))
    assert full_pixels["glb_sha256"] == roundtrip["glb_sha256"] and set(full_pixels["images"]) == LABELS
    for label, record in full_pixels["images"].items():
        assert record["canonical_sha256"] == describe(f"assets/armors/tank_v1/{label}_diffuse.png")["sha256"] and record["pixels_equal"] and record["max_channel_error_8bit"] == 0
    geometry = json.loads((WORK / "build/geometry.json").read_text(encoding="utf-8"))
    files = [describe(WORK / "build/tank_master.blend"),
             describe("assets/armors/tank_v1/tank.scn"),
             describe("assets/armors/tank_v1/tank.glb")]
    files += [describe(f"assets/armors/tank_v1/{label}_diffuse.png") for label in sorted(LABELS)]
    captures = [describe(str(path).removeprefix("res://")) for path in capture["files"]]
    manifest = {"schema_version": 1, "design_id": "C-03", "runtime_id": 2,
                "name": "Tank", "revision": "tank_runtime_v1",
                "status": "runtime_integrated_pending_user_art_review",
                "checked_at_utc": datetime.now(timezone.utc).isoformat(),
                "texture_surface_revision": head_variant,
                "helmet_refinement": {"stage":"helmet_refinement_v3_geometry_"+head_variant+"_paint", "scope":"Only head surface0 positions/normals and native head diffuse. Current UV, neck, body/limbs, topology, Skin/weights and material parameters exact against frozen stylev2.",
                    "baseline":baseline.relative_to(ROOT).as_posix(),"baseline_snapshot_sha256":describe(baseline/'snapshot.json')['sha256'],
                    "invariants":"review/helmet_refinement_invariants.json", "additional_vertex_position_changes":invariants['additional_vertex_position_changes'],"additional_uv_changes":0,
                    "original_total_limit":.20,"original_max_rest_displacement_fraction":invariants['original_max_rest_displacement_fraction'],"original_dimension_delta_fraction":invariants['original_dimension_delta_fraction'],
                    "user_authorized_ceiling":.20,"art_acceptance":"pending user review; low-poly facets, thin dark outlines and some bright contact edges remain", "padding_repair":"Native full-canvas muted steel-blue color bleed removes formerly missing rear chart coverage; no UV edits", "prior_capture_failure":"review/failed_capture_v6_savecheck/capture.json (save_unchanged false); fresh recapture independently passed with recorded start/end hashes"},
                "style_pass_history":{"baseline":"revisions/before_style_unification_v2/snapshot.json","last_paint_only_stage":"revisions/before_helmet_refinement_v3/manifest.json"},
                "helmet_design_authority":describe(WORK/'approved_helmet_reference.png'),
                "capture_driver_evidence": {"driver":"opengl3_angle","renderer_banner":banner,"log":describe(startup_log)},
                "design_authority": describe(WORK / "approved_parts_reference.png"),
                "helmet_concept": describe("docs/art/fusion_v2_generated/c03_tank_fusion.jpg"),
                "limits": {"local_geometry_displacement": .20, "dimension_change": .20,
                           "silhouette_change": .20, "uv_changed_fraction_per_material": .20,
                           "uv_coordinate_and_chart_counts_preserved": True},
                "geometry": geometry, "topology": {"triangles": 796, "original_bones": 28,
                                                     "parts": 4, "surfaces": 6, "diffuse_maps": 5},
                "files": files, "generation": generation, "tests": tests,
                "captures": captures, "capture_summary": describe(WORK / "review/engine/capture.json"),
                "uv_summary": {"original_coordinate_count":delivery["original_uv_coordinate_count"],
                               "changed_coordinate_count":delivery["changed_uv_coordinate_count"],
                               "changed_coordinate_fraction":delivery["changed_uv_coordinate_fraction"],
                               "per_material":runtime["uv_edits"],
                               "original_guides_preserved":True,
                               "authored_guides":[describe(WORK/f"guides/{label}_authored_uv.svg") for label in sorted(LABELS)]},
                "metric_scope": "Latest original-total head geometry20% authorization; head-only positions/normals changed. All UV exact against stylev2, inherited chin/collar samples retained. Body/limbs/neck/topology/Skin exact. Not concept pixel similarity. Stats, abilities and backpacks unchanged."}
    (WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("TANK_PROVENANCE_PASS latest head native image / four retained maps / head-only geometry20% / fresh64 GPU captures")


if __name__ == "__main__":
    main()
