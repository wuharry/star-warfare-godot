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
    baseline = WORK / "revisions/before_style_unification_v2"
    frozen = json.loads((baseline / "snapshot.json").read_text(encoding="utf-8"))
    for filename in ("source.json", "target.json", "geometry.json"):
        assert (WORK / "build" / filename).read_bytes() == (baseline / "delivery" / filename).read_bytes(), "Paint-only stage changed " + filename
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
            assert row.get("variant", "").startswith("style_unified_"), "Current stage must select all five new style generations"
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
    for name in ["runtime_test", "roundtrip_test", "proportion_test", "delivery_validate", "style_pass_invariants", "glb_images_test"]:
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
    startup_log = WORK / "review/final_angle_capture.log"
    startup = startup_log.read_text(encoding="utf-8")
    banner = next(line for line in startup.splitlines() if line.startswith("OpenGL API "))
    assert "ANGLE" in banner and "Direct3D11" in banner and "TANK_CAPTURE_PASS files=64 save_unchanged=true" in startup
    roundtrip=json.loads((WORK / "review/roundtrip_test.json").read_text(encoding="utf-8"))
    assert roundtrip["glb_sha256"] == describe("assets/armors/tank_v1/tank.glb")["sha256"]
    assert roundtrip["runtime_scene_sha256"] == capture["runtime_scene_sha256"] and roundtrip["target_sha256"] == capture["target_sha256"]
    assert roundtrip["head_atlas_pixels"]["canonical_sha256"] == describe("assets/armors/tank_v1/head_diffuse.png")["sha256"]
    assert len(roundtrip["head_atlas_pixels"]["samples"]) >= 30 and roundtrip["head_atlas_pixels"]["max_rgb_error"] <= .05
    assert runtime["save_unchanged"] and roundtrip["save_unchanged"]
    invariants = json.loads((WORK / "review/style_pass_invariants.json").read_text(encoding="utf-8"))
    assert invariants["before_scene_sha256"] == describe(baseline / "delivery/tank.scn")["sha256"]
    assert invariants["current_scene_sha256"] == capture["runtime_scene_sha256"]
    for key, path in [("master_sha256", WORK / "build/tank_master.blend"), ("source_sha256", WORK / "build/source.json"), ("target_sha256", WORK / "build/target.json"), ("geometry_sha256", WORK / "build/geometry.json")]:
        assert invariants[key] == describe(path)["sha256"], "Stale paint-only invariant " + key
    assert invariants["additional_vertex_position_changes"] == 0 and invariants["additional_uv_changes"] == 0
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
                "texture_surface_revision": "style_unification_v2",
                "style_pass": {"scope":"Diffuse painting only; all existing Tank geometry/UV/skin/material rendering parameters exact.",
                               "baseline": baseline.relative_to(ROOT).as_posix(), "baseline_snapshot_sha256": describe(baseline / "snapshot.json")["sha256"],
                               "invariants":"review/style_pass_invariants.json","additional_uv_changes":0,"additional_vertex_position_changes":0,
                               "user_authorized_ceiling":.20,"actual_original_relative_validation_ceiling":.15,
                               "note":"Latest user permits15-20% if needed. This pass retains inherited geometry/UV exactly and still passes stricter existing15%; no numerical allowance is spent for its own sake.",
                               "art_acceptance":"pending user review; no quantified style-similarity score"},
                "capture_driver_evidence": {"driver":"opengl3_angle","renderer_banner":banner,"log":describe(startup_log)},
                "design_authority": describe(WORK / "approved_parts_reference.png"),
                "helmet_concept": describe("docs/art/fusion_v2_generated/c03_tank_fusion.jpg"),
                "limits": {"local_geometry_displacement": .15, "dimension_change": .15,
                           "silhouette_change": .15, "uv_changed_fraction_per_material": .15,
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
                "metric_scope": "Original geometry and UV coordinate/chart counts retained; local chin/collar UV samples changed within15% per material. Not concept pixel similarity. Stats, abilities and backpacks unchanged."}
    (WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("TANK_PROVENANCE_PASS five selected diffuse images / fresh delivery / 64 GPU captures")


if __name__ == "__main__":
    main()
