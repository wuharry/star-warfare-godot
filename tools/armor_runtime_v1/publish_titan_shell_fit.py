"""Publish Titan v7 only from fresh engine coverage and material evidence.

This tool never runs an engine, alters a mesh, edits image pixels or approves art.
The optional visual-review JSON is a human/agent inspection record supplied by
the caller; absent inspection remains NOT RUN. Browser/mobile acceptance is
always separate. Historical v3-v6 reports and the 175-file before archive stay
immutable. Run --help for the required actual report paths.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess

from provenance import describe
from validate_titan_helmet import (ROOT, WORK, active_version, digest, read,
                                  verify_before, verify_generation, verify_geometry,
                                  verify_target)

REVISION = "helmet_refinement_v7"
PAGE = ROOT / "docs/art/titan_neck_coverage_v2"
STYLE = ROOT / "docs/art/armor_style_unification_v1"
SERIES_BEFORE = STYLE / "revisions/titan_v6_before_shell_fit_v7"
OLD_COMMIT = "bd71a0e5357790959a2d563556885a71ddfb4129"
AUDITED_EXTRA_REFERENCE_SHADERS = {
    "res://assets/armors/thunder/hard_surface.gdshader": (
        "c350d4479c31205743a17b2e5d2fe4c0e629e4f5307786c6f52ae82042093ddc",
        "fd541db401832f35b98a2412917534b7280cfd6755113fcda881c2449ff7d41f"),
    "res://assets/armors/thunder/painted_armor.gdshader": (
        "d06e63dbd06da0a3731968f6e655b348e7e1e4853d1544883e0d443ffc3c0bc6",
        "7c0cba282f8a486db7064323a4436811c136c3adfec0865281952cacfde5d7ff"),
}
SUFFIXES = ("diffuse_front", "diffuse_quarter", "diffuse_side", "diffuse_rear",
            "head_front", "head_quarter", "head_side", "head_rear", "clay_front", "clay_side",
            "level_01_gameplay", "level_08_gameplay", "idle_rifle", "run_rifle", "reload_04")


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def resource_path(value):
    path = Path(value.removeprefix("res://"))
    path = path if path.is_absolute() else ROOT / path
    path = path.resolve()
    assert path.is_relative_to(ROOT), "Report path escapes project"
    return path


def link(path, parent=PAGE):
    return Path(os.path.relpath(path, parent)).as_posix()


def freeze_series():
    """Freeze exact delivered bytes, including the old mislabeled after15 set."""
    index_path = SERIES_BEFORE / "snapshot.json"
    expected_paths = {f"docs/art/armor_style_unification_v1/after/titan/review/{name}.png" for name in SUFFIXES}
    expected_paths |= {"docs/art/armor_style_unification_v1/comparison.json",
                       "docs/art/armor_style_unification_v1/index.html",
                       "docs/art/original_armors_v1/c06_patchwork.json",
                       "docs/art/original_armors_v1/index.html"}
    if index_path.exists():
        data = read(index_path)
        assert data["source_commit"] == OLD_COMMIT and {r["source"] for r in data["files"]} == expected_paths
        for row in data["files"]:
            path = ROOT / row["snapshot"]
            assert path.resolve().is_relative_to(SERIES_BEFORE.resolve())
            assert digest(path) == row["sha256"] and path.stat().st_size == row["bytes"]
            committed = subprocess.check_output(["git", "show", f"{OLD_COMMIT}:{row['source']}"], cwd=ROOT)
            if committed.startswith(b"version https://git-lfs.github.com/spec/v1"):
                expected_sha = re.search(rb"oid sha256:([a-f0-9]{64})", committed).group(1).decode()
                expected_size = int(re.search(rb"size ([0-9]+)", committed).group(1))
            else:
                expected_sha, expected_size = hashlib.sha256(committed).hexdigest(), len(committed)
            assert row["sha256"] == expected_sha and row["bytes"] == expected_size, "Historical series archive no longer matches delivered commit"
        return index_path
    rows = []
    for relative in sorted(expected_paths):
        raw = subprocess.check_output(["git", "show", f"{OLD_COMMIT}:{relative}"], cwd=ROOT)
        if raw.startswith(b"version https://git-lfs.github.com/spec/v1"):
            expected = re.search(rb"oid sha256:([a-f0-9]{64})", raw).group(1).decode()
            raw = (ROOT / relative).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == expected, "Cannot freeze changed LFS source " + relative
        destination = SERIES_BEFORE / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
        rows.append({"source": relative, "snapshot": destination.relative_to(ROOT).as_posix(),
                     "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)})
    write_json(index_path, {"revision": "series_before_shell_fit_v7", "source_commit": OLD_COMMIT,
                           "scope": "Exact previous series/gallery delivery; after15 retained v5 images although text named v6. Not recertified as v6 captures.",
                           "files": rows})
    return index_path


def bind_fresh(path, scene_sha, target_sha, require_pass=True):
    report = read(path)
    if require_pass:
        assert report["status"] == "PASS", str(path)
        assert not report.get("failures", report.get("errors", [])), str(path)
    for key in ("runtime_scene_sha256", "current_scene_sha256"):
        if key in report:
            assert report[key] == scene_sha, (str(path), key)
    for key in ("target_sha256", "candidate_target_sha256"):
        if key in report:
            assert report[key] == target_sha, (str(path), key)
    if "resource_sha256" in report:
        assert report["resource_sha256"]["res://assets/armors/titan_v1/titan.scn"] == scene_sha
    if "save_unchanged" in report:
        assert report["save_unchanged"]
    if "gamestate_restored" in report:
        assert report["gamestate_restored"]
    for frame in report.get("frames", []):
        assert digest(path.parent / frame["file"]) == frame["sha256"], "Changed diagnostic/capture PNG"
    return report


def verify_surface_completeness(coverage):
    """Reject partial/nonindexed diagnostic meshes even if top-level PASS exists."""
    policy = coverage["occluder_policy"]
    assert "Only the four selected armor pieces" in policy and "hidden after EVERY pose" in policy
    rows = coverage["candidate_measurements"]
    assert len(rows) == 348 and coverage["candidate_sample_count"] == 348
    for row in rows:
        assert row["measurement_integrity"] == row["style_coverage"] == "PASS"
        assert row["head_id"] == 5 and row["complete_head_unclipped"] is True
        assert row["same_camera_as_approved_peers"] is True
        passes = row["diagnostic_surface_coverage"]
        for label in ("equipped_geometry", "complete_head"):
            result = passes[label]
            assert result["completed"] is True, "Diagnostic render did not finish"
            expected, rendered = result["expected_surfaces"], result["rendered_surfaces"]
            assert type(expected) in (int, float) and expected > 0 and expected == int(expected)
            assert rendered == expected == len(result["surfaces"]), "Diagnostic surface omitted"
            seen = set()
            for surface in result["surfaces"]:
                key = (surface["part"], surface["surface"])
                assert key not in seen, "Duplicate diagnostic surface"
                seen.add(key)
                assert surface["complete"] is True
                assert surface["indices_mode"] in ("source_indexed", "explicit_sequence_for_actual_nonindexed_triangles")
                count = surface["source_triangle_indices"]
                assert type(count) in (int, float) and count > 0 and count % 3 == 0
                assert count == surface["rendered_triangle_indices"], "Diagnostic source triangles omitted"
            if label == "complete_head":
                assert seen == {("ArmorHead_05", 0)}
                assert result["surfaces"][0]["source_triangle_indices"] == 492
            else:
                assert {part for part, _ in seen} == {"ArmorHead_05", f"ArmorBody_{int(row['body_id']):02d}",
                                                       "ArmorHand_00", "ArmorFoot_00"}, "Diagnostic occluders must be exactly the four selected armor pieces"
        exposed, complete = row["visible_neck_pixels"], row["complete_head_pixels"]
        assert type(exposed) in (int, float) and type(complete) in (int, float)
        assert 0 <= exposed <= complete and complete > 0
        assert exposed == int(exposed) and complete == int(complete)
        fraction = row["visible_neck_fraction"]
        assert math.isfinite(fraction) and abs(fraction - exposed / complete) < 1e-12
        assert abs(row["visible_neck_percent"] - fraction * 100) < 1e-10
        maximum = coverage["thresholds"][row["view"]]["maximum_fraction"]
        assert row["maximum_fraction"] == maximum and fraction <= maximum


def verify_reference_resources(current, baseline):
    """Old pins stay exact; only two newly audited opaque shader pins may join."""
    assert all(current.get(path) == sha for path, sha in baseline.items()), "Frozen family resource SHA changed"
    extras = set(current) - set(baseline)
    assert extras == set(AUDITED_EXTRA_REFERENCE_SHADERS), "Unknown/missing extra family shader resource"
    for path in extras:
        actual_pin, git_lf_pin = AUDITED_EXTRA_REFERENCE_SHADERS[path]
        assert current[path] == actual_pin, "Extra family shader has wrong audited SHA"
        actual = resource_path(path).read_bytes()
        assert hashlib.sha256(actual).hexdigest() == actual_pin, "Audited shader current bytes changed"
        committed = subprocess.check_output(["git", "show", f"{OLD_COMMIT}:{path.removeprefix('res://')}"], cwd=ROOT)
        assert hashlib.sha256(committed).hexdigest() == git_lf_pin, "Audited shader immutable Git blob changed"
        # These two existing Windows checkouts use CRLF; their immutable Git
        # blobs use LF. Only this pinned, explicitly checked difference is allowed.
        assert actual.replace(b"\r\n", b"\n") == committed, "Audited shader differs from frozen commit beyond CRLF"


def verify_coverage_log(path, capture_path):
    """Keep real driver/output failures beside the report; do not synthesize logs."""
    assert path.parent == capture_path.parent.parent
    assert path.stem == capture_path.parent.name, "Coverage log must be paired to the actual capture directory"
    text = path.read_text(encoding="utf-8-sig")
    assert not re.search(r"SCRIPT ERROR|PARSE ERROR|Parse Error|(?:^|\n)ERROR:", text, re.I), "Coverage engine logged an error"
    assert "ARMOR_NECK_EXPOSURE_PASS integrity=PASS style=PASS candidate_samples=348 references=20" in text
    banner = next(line for line in text.splitlines() if line.startswith("OpenGL API "))
    assert "ANGLE" in banner and "Direct3D11" in banner
    return banner


def embedded_report(path, report):
    data = copy.deepcopy(report)
    data["report_path"] = link(path)
    data["report_sha256"] = digest(path)
    for frame in data.get("frames", []):
        frame["url"] = link(path.parent / frame["file"])
    for collection in ("measurements", "candidate_measurements", "reference_measurements"):
        for row in data.get(collection, []):
            for key in ("diagnostic_exposed", "diagnostic_head_mask"):
                if key in row:
                    row[key + "_url"] = link(path.parent / row[key])
    return data


def inject_json(path, identifier, data):
    text = path.read_text(encoding="utf-8")
    pattern = rf'(<script id="{re.escape(identifier)}" type="application/json">)(.*?)(</script>)'
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    text, count = re.subn(pattern, lambda m: m.group(1) + payload + m.group(3), text, count=1, flags=re.S)
    assert count == 1, "Missing embedded JSON " + identifier
    path.write_text(text, encoding="utf-8", newline="\n")


def publish_series(config, manifest, coverage, capture_path, capture, series_snapshot, note):
    maps = {key: describe(ROOT / config["asset"] / name) for key, name in config["texture_files"].items()}
    copies = []
    for suffix in SUFFIXES:
        source = capture_path.parent / f"new_{suffix}.png"
        resource = "res://" + source.relative_to(ROOT).as_posix()
        assert resource in capture["files"] and digest(source) == capture["capture_sha256"][resource]
        destination = STYLE / f"after/titan/review/{suffix}.png"
        destination.write_bytes(source.read_bytes())
        copies.append({"suffix": suffix, "source": source.relative_to(ROOT).as_posix(),
                       "snapshot": destination.relative_to(ROOT).as_posix(), **{k: v for k, v in describe(source).items() if k != "path"}})
    after_index = STYLE / "titan_helmet_refinement_v7_after_snapshot.json"
    write_json(after_index, {"revision": REVISION, "status": "exact_copy_from_official_normal_resources_captures",
                            "source_capture_summary": capture_path.relative_to(ROOT).as_posix(),
                            "capture_summary_sha256": digest(capture_path),
                            "runtime_scene_sha256": manifest["current_scene_sha256"],
                            "canonical_diffuse_sha256": {k: v["sha256"] for k, v in maps.items()},
                            "historical_series_snapshot": series_snapshot.relative_to(STYLE).as_posix(),
                            "original_capture_set_unchanged": True, "files": copies})
    comparison_path = STYLE / "comparison.json"
    comparison = read(comparison_path)
    other_before = [copy.deepcopy(row) for row in comparison["armors"] if row["id"] != "titan"]
    row = next(row for row in comparison["armors"] if row["id"] == "titan")
    head = manifest["geometry"]["parts"]["ArmorHead_05"]
    projected = manifest["visor_coverage_summary"]["projected_front_visor_fraction"]
    max_iou = max(r["silhouette_changed_fraction"] for r in manifest["proportion_summary"])
    row.update(variant_after=REVISION, status="Titan v7 露頸遮蔽量工程 PASS；美術待評", after_ready=True,
               change_scope="圓面罩外殼向下貼合固定頸圈；原生貼圖完全沿用v6", scope_description=note,
               review_status="Titan v7 · 縮短可見頸部／美術待評", summary=note,
               art_residuals=manifest["residuals"],
               column_labels={"after": {"title": "Titan v7 遊戲素材", "description": "外殼貼合固定原頸圈 · 最新正常資源"}})
    row["reference_art"]["description"] = "C06壓力面罩設計；v7保持圓面罩形狀，修正露頸量。"
    row["changes"] = [{"part": "頭盔與衣領比例", "before": "v6來源接口合法，但圓面罩下緣偏高，黑色頸管露出過多。",
                       "after": note, "preserved": "原頸圈24點、334 UV／164 tris／3 charts／28 bones與五張原生PNG。"}]
    row["verification"] = [
        {"label": "原版總形狀／尺寸", "result": f"{head['max_displacement_fraction_of_smallest_dimension']:.4%} 位移；20% 上限 PASS", "evidence": "../titan_runtime_v1/build/geometry.json"},
        {"label": "本輪UV／拓樸／固定頸圈", "result": "新增UV 0；整體下收與下緣小幅延伸、24原頸點固定 PASS", "evidence": "../titan_runtime_v1/review/helmet_v7_shell_fit_test.json"},
        {"label": "正面面罩投影", "result": f"{projected:.4%} ≥50%；PASS", "evidence": "../titan_runtime_v1/review/helmet_v7_visor_coverage.json"},
        {"label": "四向整體灰模", "result": f"最大1−IoU {max_iou:.4%}；20% 上限 PASS", "evidence": "../titan_runtime_v1/review/helmet_v7_proportion_test.json"},
        {"label": "露頸遮蔽量", "result": f"{len(coverage['candidate_measurements'])}個混搭／動作／視角取樣；同家族門檻 PASS", "evidence": "../titan_neck_coverage_v2/index.html"},
        {"label": "runtime／GLB／五圖", "result": "15 runtime＋9 GLB；native PNG／packed master／SCN／guards PASS", "evidence": "../titan_runtime_v1/manifest.json"},
        {"label": "使用者美術／手機效能", "result": "NOT RUN", "evidence": "../titan_neck_coverage_v2/README.md"}]
    details = row["engineering_details"]
    details.update(head_max_displacement_fraction=head["max_displacement_fraction_of_smallest_dimension"],
                   head_dimensions_absolute_delta_fraction=head["dimension_delta_fraction"],
                   projected_front_visor_fraction=projected, max_wholebody_gray_1_minus_iou=max_iou,
                   head_scene_sha256=manifest["current_scene_sha256"],
                   canonical_diffuse_sha256={k: v["sha256"] for k, v in maps.items()},
                   capture_resource_mode="normal_imported_resources", current_capture_save_unchanged=True,
                   shell_fit_delta_y_m=config["shell_fit"]["delta_y"])
    latest = row["latest_revision"]
    latest.update(variant=REVISION, status="engineering_PASS_pending_user_art_review", after_ready=True,
                  comparison_page="../titan_neck_coverage_v2/index.html",
                  generation_record="../titan_runtime_v1/revisions/helmet_refinement_v7/generation_record.json",
                  selected_native_revision="helmet_refinement_v6", raster_generation_performed=False,
                  selected_native_head_sha256=maps["head"]["sha256"],
                  head_max_original_displacement_fraction=head["max_displacement_fraction_of_smallest_dimension"],
                  head_dimension_absolute_delta_fraction=head["dimension_delta_fraction"],
                  visor_projected_frontal_coverage_measured_fraction=projected,
                  max_wholebody_gray_1_minus_iou=max_iou, scene_sha256=manifest["current_scene_sha256"],
                  capture_summary_sha256=digest(capture_path), note=note)
    row["sources"] = [{"label": "Titan v7 露頸量／混搭前後與必要prompt", "path": "../titan_neck_coverage_v2/index.html"},
                      {"label": "後續必要露頸標準附錄", "path": "../titan_neck_coverage_v2/prompts/mandatory_limited_neck_exposure.txt"},
                      {"label": "當前v7正式after15 SHA索引", "path": after_index.relative_to(STYLE).as_posix()},
                      {"label": "上一交付系列頁固定快照（含沿用v5的15圖）", "path": series_snapshot.relative_to(STYLE).as_posix()},
                      *row["sources"]]
    for entry in row["sources"]:
        if entry["path"] == "../titan_runtime_v1/index.html":
            entry["label"] = "目前 Titan v7 素材入口"
        elif entry["path"] == "../titan_runtime_v1/manifest.json":
            entry["label"] = "目前 Titan v7 正式工程與素材 manifest"
    assert [r for r in comparison["armors"] if r["id"] != "titan"] == other_before
    comparison["date"] = datetime.now(timezone.utc).date().isoformat()
    write_json(comparison_path, comparison)
    inject_json(STYLE / "index.html", "comparison-data", comparison)
    return after_index


def publish_catalog(config, manifest, note):
    path = ROOT / "docs/art/original_armors_v1/c06_patchwork.json"
    armor = read(path)
    delivery = armor["runtime_delivery"]
    head = manifest["geometry"]["parts"]["ArmorHead_05"]
    delivery.update(selected_head_generation=REVISION, date=datetime.now(timezone.utc).date().isoformat(),
                    head_maximum_local_displacement_ratio=head["max_displacement_fraction_of_smallest_dimension"],
                    head_dimension_delta_fraction=head["dimension_delta_fraction"],
                    additional_uv_changes=0, projected_front_visor_fraction=manifest["visor_coverage_summary"]["projected_front_visor_fraction"],
                    raster_generation_performed=False, inherited_native_head_revision="helmet_refinement_v6",
                    engineering_status="PASS", art_review_status="pending_user_review")
    style = delivery["style_optimization"]
    style.update(stage=REVISION, latest_variant=REVISION, comparison_page="../titan_neck_coverage_v2/index.html",
                 note=note, added_uv_changes=0, helmet_prompt_requirements="../titan_neck_coverage_v2/prompts/mandatory_limited_neck_exposure.txt")
    addendum = "../titan_neck_coverage_v2/prompts/mandatory_limited_neck_exposure.txt"
    if addendum not in style["prompt_set"]:
        style["prompt_set"].append(addendum)
    armor["helmet_studies"].update(comparison_page="../titan_neck_coverage_v2/index.html",
                                   link_label="Titan v7 · 露頸比例與混搭前後 ↗", latest_variant=REVISION,
                                   scope="compact_shell_fit_with_protected_neck", note=note)
    write_json(path, armor)
    gallery = ROOT / "docs/art/original_armors_v1/index.html"
    text = gallery.read_text(encoding="utf-8")
    catalog = json.loads(re.search(r'<script id="catalog" type="application/json">(.*?)</script>', text, re.S).group(1))
    entry = next(row for row in catalog if row["design_id"] == "C-06")
    entry["runtime_delivery"] = delivery
    entry["helmet_studies"] = armor["helmet_studies"]
    inject_json(gallery, "catalog", catalog)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("coverage-before", "coverage-after", "mixed-capture", "mixed-test", "final-capture"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--coverage-log", required=True,
                        help="Actual paired Godot coverage log; any script/parse error rejects publication.")
    parser.add_argument("--visual-review", help="Optional actual inspection record; absence remains NOT RUN.")
    args = parser.parse_args()
    paths = {key: resource_path(getattr(args, key.replace("-", "_")))
             for key in ("coverage-before", "coverage-after", "mixed-capture", "mixed-test", "final-capture")}
    coverage_log = resource_path(args.coverage_log)
    config = read(WORK / "runtime_config.json")
    assert active_version(config) == 7
    source, target = read(WORK / "build/source.json"), read(WORK / "build/target.json")
    before_snapshot = verify_before(7)
    head_contract = verify_target(config, source, target, before_snapshot)
    verify_geometry(config, source, target)
    assets = ROOT / config["asset"]
    scene, target_record = describe(assets / "titan.scn"), describe(WORK / "build/target.json")
    maps = {k: describe(assets / name) for k, name in config["texture_files"].items()}
    verify_generation(config, {k: ROOT / v["path"] for k, v in maps.items()}, before_snapshot)
    tests, reports = {}, {}
    names = ("original_scene_invariants", "runtime_test", "roundtrip_test", "helmet_v7_glb_test",
             "helmet_v7_master_test", "helmet_v7_contract_and_guards_test", "helmet_v7_shell_fit_test",
             "helmet_v7_proportion_test", "helmet_v7_visor_coverage", "helmet_v7_lossless_import", "neck_contract_gate")
    for name in names:
        path = WORK / "review" / (name + ".json")
        reports[name] = bind_fresh(path, scene["sha256"], target_record["sha256"])
        tests[name] = {"file": describe(path), "status": "PASS"}
    loaded = {}
    for name, path in paths.items():
        if name == "coverage-before":
            loaded[name] = read(path)
        else:
            loaded[name] = bind_fresh(path, scene["sha256"], target_record["sha256"], require_pass=name != "final-capture")
        tests[name] = {"file": describe(path), "status": loaded[name].get("status", "UNVALIDATED_CAPTURE")}
    coverage, old_coverage = loaded["coverage-after"], loaded["coverage-before"]
    assert coverage["schema"] == old_coverage["schema"] == "armor_neck_exposure_v1"
    assert coverage["measurement_integrity"] == "PASS" and coverage["style_coverage"] == "PASS"
    assert not coverage["style_failures"] and len(coverage["candidate_measurements"]) == 348
    verify_surface_completeness(coverage)
    coverage_banner = verify_coverage_log(coverage_log, paths["coverage-after"])
    tests["coverage-log"] = {"file": describe(coverage_log), "status": "PASS"}
    assert old_coverage["measurement_integrity"] == "PASS", "Do not publish invalid/occluded baseline measurements"
    for frame in old_coverage["frames"]:
        assert digest(paths["coverage-before"].parent / frame["file"]) == frame["sha256"], "Changed frozen coverage-baseline PNG"
    row_key = lambda row: (row["body_id"], row["pose"], row["view"])
    expected_keys = {(body, pose, view) for body in range(29)
                     for pose in ("idle", "run", "reload") for view in ("front", "quarter", "side", "rear")}
    assert {row_key(row) for row in coverage["candidate_measurements"]} == expected_keys
    previous_keys = {row_key(row) for row in old_coverage["candidate_measurements"]}
    assert len(previous_keys) == len(old_coverage["candidate_measurements"])
    assert previous_keys <= expected_keys and len(previous_keys) >= 48
    assert coverage["thresholds"] == old_coverage["thresholds"], "Candidate cannot loosen frozen family thresholds"
    verify_reference_resources(coverage["reference_resource_sha256"], old_coverage["reference_resource_sha256"])
    assert coverage["reference_ids"] == old_coverage["reference_ids"] == list(range(5))
    assert coverage["thresholds_frozen_before_candidate_measurements"] is True
    assert len(coverage["reference_measurements"]) == len(old_coverage["reference_measurements"]) == 20
    peer_values = lambda report: {(row["head_id"], row["view"]): (row["visible_neck_pixels"], row["complete_head_pixels"])
                                  for row in report["reference_measurements"]}
    assert peer_values(coverage) == peer_values(old_coverage), "Fixed peer pixels changed after calibration"
    before_path_value = coverage.get("baseline_path")
    assert resource_path(before_path_value) == paths["coverage-before"]
    assert coverage["baseline_sha256"] == digest(paths["coverage-before"])
    for name in ("mixed-capture", "mixed-test"):
        assert len(loaded[name]["poses"]) == 261
        assert loaded[name]["save_unchanged"] and loaded[name]["gamestate_restored"]
    assert len(loaded["mixed-capture"]["frames"]) == 35
    assert len(loaded["mixed-test"]["negative_fixtures"]) >= 20
    assert len(loaded["mixed-test"].get("shared_gate_checks", [])) >= 24
    capture = loaded["final-capture"]
    assert len(capture["files"]) == 64 and capture["resource_mode"] == "normal_imported_resources"
    assert capture["scene_sha256_at_start"] == capture["runtime_scene_sha256"] == scene["sha256"]
    assert capture["target_sha256_at_start"] == capture["target_sha256"] == target_record["sha256"]
    assert capture["canonical_diffuse_sha256_at_start"] == {k: v["sha256"] for k, v in maps.items()}
    captures = []
    for raw in capture["files"]:
        file = resource_path(raw)
        assert digest(file) == capture["capture_sha256"][raw]
        captures.append(describe(file))
    capture_log = WORK / "review/helmet_v7_angle_capture.log"
    log_text = capture_log.read_text(encoding="utf-8-sig")
    banner = next(line for line in log_text.splitlines() if line.startswith("OpenGL API "))
    assert "ANGLE" in banner and "Direct3D11" in banner
    assert "ARMOR_CAPTURE_PASS files=64 save_unchanged=true" in log_text
    tests["final-capture"]["status"] = "PASS"
    assert reports["helmet_v7_visor_coverage"]["projected_front_visor_fraction"] >= .50
    assert len(reports["runtime_test"]["poses"]) == 15 and len(reports["roundtrip_test"]["poses"]) == 9
    assert reports["roundtrip_test"]["glb_sha256"] == digest(assets / "titan.glb")
    assert reports["roundtrip_test"]["head_atlas_pixels"]["max_rgb_error"] <= .05
    visual = {"status": "NOT RUN", "scope": "No inspection record supplied; engineering PASS is not artistic acceptance."}
    if args.visual_review:
        visual_path = resource_path(args.visual_review)
        visual = read(visual_path)
        assert visual["current_scene_sha256"] == scene["sha256"]
        visual["file"] = describe(visual_path)
    note = (f"圓面罩外殼整體下收{abs(config['shell_fit']['delta_y'])*1000:g} mm，另依明列profile小幅延伸下緣，"
            "24個原頸圈頂點固定；全部UV／拓樸／skin及五張原生PNG完全沿用v6。"
            f"以同家族頭盔門檻驗證{len(coverage['candidate_measurements'])}個露頸量取樣，另有29身甲×9姿勢及35張近拍；仍待使用者美術評價。")
    frozen_rows = {row["path"]: row for row in before_snapshot["files"]}
    assert old_coverage["resource_sha256"]["res://assets/armors/titan_v1/titan.scn"] == frozen_rows["assets/armors/titan_v1/titan.scn"]["sha256"], "Coverage baseline is not delivered Titan v6"
    historical = ROOT / frozen_rows["docs/art/titan_runtime_v1/manifest.json"]["snapshot"]
    manifest = read(historical)
    generation = read(ROOT / config["generation_record"])
    manifest.update(revision=REVISION, texture_surface_revision=REVISION, checked_at_utc=datetime.now(timezone.utc).isoformat(),
                    current_scene_sha256=scene["sha256"], before_revision_snapshot=describe(ROOT / config["before_revision_snapshot"]),
                    historical_manifest=describe(historical), geometry=read(WORK / "build/geometry.json"), tests=tests,
                    captures=captures, capture_summary=describe(paths["final-capture"]),
                    visor_coverage_summary=reports["helmet_v7_visor_coverage"],
                    proportion_summary=reports["helmet_v7_proportion_test"]["silhouettes"],
                    head_contract=head_contract, shell_fit=config["shell_fit"], visual_inspection=visual)
    manifest["source_validation_scope"]["actual_scn_original_array_report"] = tests["original_scene_invariants"]["file"]
    manifest["generation"].update(current_head=describe(ROOT / config["generation_record"]), head_output=maps["head"],
                                  native_archive=describe(ROOT / generation["archive_path"]), raster_generation_performed=False,
                                  source_generation_record=generation["source_generation_record"], all_five_diffuse_unchanged_from_v6=True)
    manifest["capture_driver_evidence"].update(renderer=capture["renderer"], renderer_banner=banner,
                                              file_count=64, save_unchanged=True, log=describe(capture_log))
    manifest["neck_mix_summary"] = {"body_ids": list(range(29)), "poses": 261, "captures": 35,
        "negative_fixtures": len(loaded["mixed-test"]["negative_fixtures"]),
        "shared_gate_checks": len(loaded["mixed-test"].get("shared_gate_checks", [])),
        "scope": "Source-interface and sampled-animation checks, separate from visible-neck style coverage."}
    manifest["neck_exposure_summary"] = {"file": describe(paths["coverage-after"]), "baseline": describe(paths["coverage-before"]),
        "engine_log": describe(coverage_log), "renderer_banner": coverage_banner,
        "candidate_measurements": len(coverage["candidate_measurements"]), "reference_ids": coverage["reference_ids"],
        "measurement_integrity": coverage["measurement_integrity"], "style_coverage": coverage["style_coverage"],
        "occluder_policy": coverage["occluder_policy"],
        "thresholds": coverage["thresholds"], "mandatory_prompt": describe(PAGE / "prompts/mandatory_limited_neck_exposure.txt")}
    manifest["residuals"] = ["A short visible neck seal may remain; sampled family coverage does not prove zero exposed cloth or zero clipping at every animation time/view.",
        "The original neck interface alone does not certify visual fit. This revision separately measures occluded visible-neck pixels.",
        "Actual user art acceptance, browser interaction, mobile performance and exported product smoke remain NOT RUN."]
    manifest["runtime_summary"].update(poses=15, save_unchanged=True, triangles=reports["runtime_test"]["triangles"])
    manifest["roundtrip_summary"].update(poses=9, save_unchanged=True,
        max_sample_rgb_error=reports["roundtrip_test"]["head_atlas_pixels"]["max_rgb_error"], all_five_embedded_glb_rgb_exact=True)
    series_snapshot = freeze_series()
    page_data = {"revision": REVISION, "note": note, "delta_y_m": config["shell_fit"]["delta_y"],
                 "scene_sha256": scene["sha256"], "source_geometry": describe(WORK / "build/geometry.json"),
                 "before": embedded_report(paths["coverage-before"], old_coverage),
                 "after": embedded_report(paths["coverage-after"], coverage),
                 "mixed": embedded_report(paths["mixed-capture"], loaded["mixed-capture"]),
                 "mixed_before": embedded_report(ROOT / frozen_rows["docs/art/titan_neck_mix_v1/review/after/capture.json"]["snapshot"],
                                                  read(ROOT / frozen_rows["docs/art/titan_neck_mix_v1/review/after/capture.json"]["snapshot"])),
                 "visual_inspection": visual, "browser_interaction": "NOT RUN", "user_art_acceptance": "NOT RUN"}
    template = (PAGE / "page_template.html").read_text(encoding="utf-8")
    assert template.count("__TITAN_V7_DATA__") == 1
    (PAGE / "index.html").write_text(template.replace("__TITAN_V7_DATA__", json.dumps(page_data, ensure_ascii=False).replace("</", "<\\/")), encoding="utf-8", newline="\n")
    manifest["review_page"] = describe(PAGE / "index.html")
    after_index = publish_series(config, manifest, coverage, paths["final-capture"], capture, series_snapshot, note)
    publish_catalog(config, manifest, note)
    redirect = '<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=../titan_neck_coverage_v2/index.html"><title>Titan v7 露頸比例</title><body><h1>Titan v7 · 頭盔與衣領貼合</h1><a href="../titan_neck_coverage_v2/index.html">開啟露頸量與混搭前後</a></body></html>\n'
    (WORK / "index.html").write_text(redirect, encoding="utf-8", newline="\n")
    readme = (f"# Titan · C-06 · 頭盔貼合 v7\n\n目前正式版本為 `{REVISION}`。{note}\n\n"
              "[目前露頸量與前後預覽](../titan_neck_coverage_v2/index.html)、[本輪說明與限制](../titan_neck_coverage_v2/README.md)、"
              "[後續必要露頸標準](../titan_neck_coverage_v2/prompts/mandatory_limited_neck_exposure.txt)。\n\n"
              "舊 v6 接口修復保留於 [歷史頁](../titan_neck_mix_v1/index.html)，其工程PASS不代表目前要求的露頸比例已達標。"
              "圓面罩原生PNG沿用v6，這次沒有重新生成圖片。原版20%形狀／尺寸上限、334UV／164頭部三角形與28骨骼維持。\n")
    (WORK / "README.md").write_text(readme, encoding="utf-8", newline="\n")
    manifest["files"] = [describe(path) for path in dict.fromkeys([
        assets / "titan.scn", assets / "titan.glb", WORK / "build/titan_master.blend", WORK / "build/source.json",
        WORK / "build/target.json", WORK / "build/geometry.json", WORK / "runtime_config.json", WORK / "README.md", WORK / "index.html",
        ROOT / config["generation_record"], PAGE / "index.html", PAGE / "page_template.html", PAGE / "README.md", PAGE / "prompts/mandatory_limited_neck_exposure.txt",
        ROOT / "docs/art/titan_neck_mix_v1/prompts/mandatory_neck_interface.txt", capture_log,
        coverage_log,
        series_snapshot, after_index, *[ROOT / row["path"] for row in maps.values()],
        *[ROOT / row["file"]["path"] for row in tests.values()],
        *[ROOT / "tools/armor_runtime_v1" / name for name in ("build.py", "shapes/titan.py", "update_titan_helmet.gd",
          "neck_contract.gd", "neck_source_contract.py", "neck_exposure_capture.gd", "neck_exposure_capture.tscn",
          "mixed_neck_capture.gd", "mixed_neck_capture.tscn", "validate_titan_helmet.py", "test_titan_v7_fit.py", "publish_titan_shell_fit.py")]])]
    write_json(WORK / "manifest.json", manifest)
    write_json(PAGE / "review/published_delivery.json", {"status": "PASS", "revision": REVISION,
        "current_scene_sha256": scene["sha256"], "inputs": {**{k: describe(v) for k, v in paths.items()}, "coverage-log": describe(coverage_log)},
        "manifest": describe(WORK / "manifest.json"), "preview": describe(PAGE / "index.html"),
        "series_archive": describe(series_snapshot), "series_after15": describe(after_index),
        "visual_inspection": visual.get("status", "NOT RUN"), "browser_interaction": "NOT RUN", "user_art_acceptance": "NOT RUN"})
    print("TITAN_SHELL_FIT_DELIVERY_PASS v7 / inherited v6 PNG / fresh exposure / 35 mixed / 261 poses / exact after15")


if __name__ == "__main__":
    main()
