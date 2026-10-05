"""Publish Titan v4 metadata from fresh, independently generated evidence.

Run only after the actual scene/GLB/master tests and normal-renderer capture.
This does not create tests, approve art, or alter any historical snapshot.
"""
import json
from datetime import datetime, timezone
from pathlib import Path

from provenance import describe

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"
REVISION = "helmet_refinement_v4"
LABELS = ("head", "body", "shoulder", "hand", "foot")


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    config = read(WORK / "runtime_config.json")
    assert config["active_helmet_revision"] == REVISION
    assert config["head_refinement"]["count_growth_ceiling"] == .35
    assets = ROOT / config["asset"]
    scene = describe(assets / "titan.scn")
    target = describe(WORK / "build/target.json")
    geometry = read(WORK / "build/geometry.json")
    maps = {label: describe(assets / config["texture_files"][label]) for label in LABELS}
    tests = {}
    reports = {}
    names = ("original_scene_invariants", "runtime_test", "roundtrip_test",
             "helmet_v4_glb_test", "helmet_v4_master_test",
             "helmet_v4_contract_and_guards_test", "helmet_v4_proportion_test",
             "helmet_v4_visor_coverage", "helmet_v4_lossless_import")
    for name in names:
        path = WORK / "review" / (name + ".json")
        report = read(path)
        assert report["status"] == "PASS", name
        assert not report.get("errors", report.get("failures", [])), name
        for field, expected in (("runtime_scene_sha256", scene["sha256"]),
                                ("current_scene_sha256", scene["sha256"]),
                                ("target_sha256", target["sha256"])):
            if field in report:
                assert report[field] == expected, (name, field)
        reports[name] = report
        tests[name] = {"file": describe(path), "status": report["status"]}
    runtime, roundtrip = reports["runtime_test"], reports["roundtrip_test"]
    assert len(runtime["poses"]) == 15 and len(roundtrip["poses"]) == 9
    assert runtime["save_unchanged"] and roundtrip["save_unchanged"]
    assert roundtrip["glb_sha256"] == describe(assets / "titan.glb")["sha256"]
    pixels = roundtrip["head_atlas_pixels"]
    assert len(pixels["samples"]) == 30 and pixels["max_rgb_error"] <= .05
    coverage = reports["helmet_v4_visor_coverage"]
    assert coverage["minimum_fraction"] == .50 and coverage["projected_front_visor_fraction"] >= .50
    folder = WORK / "review/helmet_v4_final"
    capture = read(folder / "capture.json")
    assert capture["runtime_scene_sha256"] == capture["scene_sha256_at_start"] == scene["sha256"]
    assert capture["target_sha256"] == capture["target_sha256_at_start"] == target["sha256"]
    assert capture["canonical_diffuse_sha256_at_start"] == {k: v["sha256"] for k, v in maps.items()}
    assert len(capture["files"]) == 64 and capture["save_unchanged"]
    assert capture["resource_mode"] == "normal_imported_resources"
    captures = []
    for filename in capture["files"]:
        record = describe(filename.removeprefix("res://"))
        assert record["sha256"] == capture["capture_sha256"][filename]
        captures.append(record)
    log = (WORK / "review/helmet_v4_angle_capture.log").read_text(encoding="utf-8-sig")
    banner = next(line for line in log.splitlines() if line.startswith("OpenGL API "))
    assert "ANGLE" in banner and "Direct3D11" in banner
    assert "ARMOR_CAPTURE_PASS files=64 save_unchanged=true" in log
    frozen = WORK / "revisions/before_helmet_refinement_v4"
    historical_path = frozen / "docs/art/titan_runtime_v1/manifest.json"
    manifest = read(historical_path)
    head = geometry["parts"]["ArmorHead_05"]
    manifest.update(revision=REVISION, texture_surface_revision=REVISION,
                    checked_at_utc=datetime.now(timezone.utc).isoformat(), geometry=geometry,
                    before_revision_snapshot=describe(frozen / "snapshot.json"),
                    historical_manifest=describe(historical_path), texture_files=config["texture_files"],
                    tests=tests, captures=captures,
                    capture_summary=describe(folder / "capture.json"))
    manifest["source_validation_scope"]["actual_scn_original_array_report"] = tests["original_scene_invariants"]["file"]
    manifest["limits"].update(head_only_count_growth_ceiling=.35,
                              silhouette_similarity_measured=True,
                              silhouette_change=.20, projected_front_visor_minimum=.50)
    manifest["limits"]["budget_scope"] = "Titan head only; user requested more UV arc cuts below 1.6-2x. Chosen ceiling is 1.35x. Original-total geometry and original UV edit ceilings remain 20%."
    original_uv = sum(p["original_uv_coordinate_count"] for p in geometry["parts"].values())
    authored_uv = sum(p["uv_coordinate_count"] for p in geometry["parts"].values())
    manifest["topology"].update(triangles=runtime["triangles"], head_triangles=head["triangles"],
                                head_triangle_growth_fraction=head["triangle_growth_fraction"])
    manifest["uv_summary"].update(original_coordinate_count=original_uv,
                                  authored_coordinate_count=authored_uv,
                                  added_coordinate_count=authored_uv-original_uv,
                                  per_material=runtime["uv_edits"],
                                  note="Per-material coordinates count the original prefix. Forty added original-edge midpoint coordinates are independently checked by the refinement contract; original chart counts are retained.")
    record_path = ROOT / config["generation_record"]
    generation = read(record_path)
    assert maps["head"]["sha256"] == generation["native_output_sha256"]
    manifest["generation"].update(current_head=describe(record_path), head_output=maps["head"],
                                  native_archive=describe(generation["archive_path"]))
    old_paths = [r["path"].replace("helmet_refinement_v3", REVISION) for r in manifest["files"]]
    extra = ["tools/armor_runtime_v1/measure_titan_visor.py",
             "tools/armor_runtime_v1/test_titan_helmet_guards.py",
             "tools/armor_runtime_v1/reimport_titan_head_lossless.gd",
             "tools/armor_runtime_v1/titan_refinement_manifest.py",
             "tools/armor_runtime_v1/capture.gd", "tools/armor_runtime_v1/measure.py"]
    manifest["files"] = [describe(path) for path in dict.fromkeys(old_paths + extra)]
    manifest["runtime_summary"] = {"poses": len(runtime["poses"]), "save_unchanged": runtime["save_unchanged"], "triangles": runtime["triangles"]}
    manifest["roundtrip_summary"].update(poses=len(roundtrip["poses"]), save_unchanged=roundtrip["save_unchanged"], max_sample_rgb_error=pixels["max_rgb_error"], all_five_embedded_glb_rgb_exact=True)
    manifest["capture_driver_evidence"].update(platform="Windows", device="NVIDIA GeForce RTX 4080 Laptop GPU", renderer_banner=banner, file_count=len(captures), save_unchanged=capture["save_unchanged"])
    manifest["visor_coverage_summary"] = coverage
    manifest["proportion_summary"] = reports["helmet_v4_proportion_test"]["silhouettes"]
    manifest["review_page"] = describe(WORK / "revisions" / REVISION / "index.html")
    manifest["metric_scope"] = "Original-total geometry/UV/counts and rendered geometry silhouettes are measured, not artistic similarity. Visor coverage is amber pixels divided by the isolated full head's projected front silhouette, not total 3D surface area. Original body, limbs and skin binds remain exact."
    manifest["not_run"] = {"user_art_acceptance": "NOT RUN", "mobile_performance": "NOT RUN", "exported_product_smoke": "NOT RUN"}
    manifest["residuals"] = ["Only the approved quarter concept exists; side and rear surfaces are inferred.", "The original short game proportions and low polygon ear/crown structure remain; this is not a pixel-exact match to the adult concept.", "Lossless head import preserves RGB; its exact GPU memory cost has not been measured on mobile."]
    manifest["editor_import_log_limitations"] = "Editor import exits successfully but emits the existing audio-missing-archive-tfpon_0v directory warning; the transient import helper also logs editor shutdown RID cleanup warnings. These are not counted as a clean editor log."
    (WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("TITAN_REFINEMENT_MANIFEST_PASS fresh v4 evidence / 64 normal captures / user art review pending")


if __name__ == "__main__":
    main()
