"""Publish current Titan neck repair only from fresh engine evidence."""
import json
from datetime import datetime, timezone
from pathlib import Path

from provenance import describe

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"
MIX = ROOT / "docs/art/titan_neck_mix_v1"
REVISION = "helmet_refinement_v6"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    config = read(WORK / "runtime_config.json")
    assert config["active_helmet_revision"] == REVISION
    assets = ROOT / config["asset"]
    scene = describe(assets / "titan.scn")
    target = describe(WORK / "build/target.json")
    maps = {key: describe(assets / name) for key, name in config["texture_files"].items()}
    frozen = MIX / "revisions/before_neck_fix"
    old_path = frozen / "docs/art/titan_runtime_v1/manifest.json"
    manifest = read(old_path)
    reports, tests = {}, {}
    names = ("original_scene_invariants", "runtime_test", "roundtrip_test",
             "helmet_v6_glb_test", "helmet_v6_master_test", "helmet_v6_contract_and_guards_test",
             "helmet_v6_proportion_test", "helmet_v6_visor_coverage", "helmet_v6_lossless_import",
             "neck_contract_gate")
    for name in names:
        path = WORK / "review" / (name + ".json")
        report = read(path)
        assert report["status"] == "PASS" and not report.get("errors", report.get("failures", [])), name
        for key, expected in (("runtime_scene_sha256", scene["sha256"]),
                              ("current_scene_sha256", scene["sha256"]),
                              ("target_sha256", target["sha256"]),
                              ("candidate_target_sha256", target["sha256"])):
            if key in report:
                assert report[key] == expected, (name, key)
        reports[name] = report
        tests[name] = {"file": describe(path), "status": "PASS"}
    mix_reports = {}
    for name in ("after", "after_test_shared_finite"):
        path = MIX / "review" / name / "capture.json"
        report = read(path)
        assert report["status"] == "PASS" and not report["failures"]
        assert len(report["poses"]) == 261 and report["save_unchanged"]
        assert report["resource_sha256"]["res://assets/armors/titan_v1/titan.scn"] == scene["sha256"]
        for frame in report["frames"]:
            assert describe(path.parent / frame["file"])["sha256"] == frame["sha256"]
        tests[name] = {"file": describe(path), "status": "PASS"}
        mix_reports[name] = report
    assert len(mix_reports["after"]["frames"]) == 35
    final_mix = mix_reports["after_test_shared_finite"]
    assert len(final_mix["negative_fixtures"]) >= 10 and len(final_mix["shared_gate_checks"]) >= 24
    capture_path = WORK / "review/helmet_v6_final/capture.json"
    capture = read(capture_path)
    assert capture["runtime_scene_sha256"] == capture["scene_sha256_at_start"] == scene["sha256"]
    assert capture["target_sha256"] == capture["target_sha256_at_start"] == target["sha256"]
    assert capture["canonical_diffuse_sha256_at_start"] == {k: v["sha256"] for k, v in maps.items()}
    assert capture["resource_mode"] == "normal_imported_resources" and capture["save_unchanged"]
    assert len(capture["files"]) == 64
    captures = [describe(p.removeprefix("res://")) for p in capture["files"]]
    for row, path in zip(captures, capture["files"]):
        assert row["sha256"] == capture["capture_sha256"][path]
    generation = read(ROOT / config["generation_record"])
    assert maps["head"]["sha256"] == generation["native_output_sha256"]
    coverage = reports["helmet_v6_visor_coverage"]
    assert coverage["projected_front_visor_fraction"] >= .50
    runtime, roundtrip = reports["runtime_test"], reports["roundtrip_test"]
    assert len(runtime["poses"]) == 15 and len(roundtrip["poses"]) == 9
    assert runtime["save_unchanged"] and roundtrip["save_unchanged"]
    assert roundtrip["glb_sha256"] == describe(assets / "titan.glb")["sha256"]
    manifest.update(revision=REVISION, texture_surface_revision=REVISION,
                    checked_at_utc=datetime.now(timezone.utc).isoformat(),
                    before_revision_snapshot=describe(frozen / "snapshot.json"),
                    historical_manifest=describe(old_path), geometry=read(WORK / "build/geometry.json"),
                    tests=tests, captures=captures, capture_summary=describe(capture_path),
                    review_page=describe(MIX / "index.html"),
                    visor_coverage_summary=coverage,
                    proportion_summary=reports["helmet_v6_proportion_test"]["silhouettes"])
    manifest["source_validation_scope"]["actual_scn_original_array_report"] = tests["original_scene_invariants"]["file"]
    manifest["generation"].update(current_head=describe(ROOT / config["generation_record"]),
                                  head_output=maps["head"], native_archive=describe(generation["archive_path"]))
    manifest["runtime_summary"].update(poses=15, save_unchanged=True, triangles=runtime["triangles"])
    manifest["roundtrip_summary"].update(poses=9, save_unchanged=True,
        max_sample_rgb_error=roundtrip["head_atlas_pixels"]["max_rgb_error"], all_five_embedded_glb_rgb_exact=True)
    manifest["neck_mix_summary"] = {"body_ids": list(range(29)), "poses": 261, "captures": 35,
        "negative_fixtures": len(final_mix["negative_fixtures"]),
        "shared_gate_checks": len(final_mix["shared_gate_checks"]),
        "scope": "Titan source neck restored; Titan and shared compiler save gates; other custom compilers are not all migrated.",
        "mandatory_prompt": describe(MIX / "prompts/mandatory_neck_interface.txt")}
    manifest["capture_driver_evidence"].update(file_count=64, save_unchanged=True)
    manifest["residuals"] = ["Low-collar bodies retain source neck lower-edge and collar overlap outlines; these are not new transparent holes.",
        "Generated neck cloth is darker than v5 but lighter than the true original. Native generation can slightly change other painted details.",
        "Only sampled poses and selected close-up views were examined; user art acceptance, browser interaction, mobile performance and exported product smoke remain NOT RUN."]
    manifest["not_run"]["browser_interaction"] = "NOT RUN"
    manifest.pop("maintenance_review_20261006", None)
    paths = [assets / "titan.scn", assets / "titan.glb", WORK / "build/titan_master.blend",
             WORK / "build/source.json", WORK / "build/target.json", WORK / "build/geometry.json",
             WORK / "runtime_config.json", ROOT / config["generation_record"],
             MIX / "index.html", MIX / "README.md", MIX / "prompts/mandatory_neck_interface.txt",
             *[ROOT / row["path"] for row in maps.values()],
             *[ROOT / row["file"]["path"] for row in tests.values()]]
    paths += [ROOT / "tools/armor_runtime_v1" / name for name in
              ("build.py", "shapes/titan.py", "compile.gd", "update_titan_helmet.gd", "neck_contract.gd",
               "neck_source_contract.py", "validate_titan_helmet.py", "publish_titan_neck_fix.py")]
    manifest["files"] = [describe(p) for p in dict.fromkeys(paths)]
    (WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("TITAN_NECK_DELIVERY_PASS fresh v6 resources / 35 mixed captures / 261 poses / save gates")


if __name__ == "__main__":
    main()
