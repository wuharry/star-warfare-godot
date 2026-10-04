"""Verify generation and current delivery evidence before writing the manifest."""
import hashlib
import json
import struct
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/fortune_runtime_v1"
ASSETS = ROOT / "assets/armors/fortune_v1"
LABELS = ("head", "body", "shoulder", "hand", "foot")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def main() -> None:
    generation = read(WORK / "generation_inputs.json")
    selected = {}
    for row in generation:
        if row.get("selected"):
            assert row["label"] not in selected, "Multiple selected generations for one material"
            selected[row["label"]] = row
    assert set(selected) == set(LABELS)
    base_prompt = ROOT / "docs/art/armor_style_unification_v1/base_prompt.txt"
    before = ROOT / "docs/art/armor_style_unification_v1/before/fortune/delivery"
    # Style paint is a separate pass: its accepted geometry/UV state is locked,
    # rather than spending another 15% allowance relative to the prior version.
    for filename in ("target.json", "geometry.json"):
        assert (WORK / "build" / filename).read_bytes() == (before / filename).read_bytes(), f"Style pass changed {filename}"
    baseline_manifest = read(before / "manifest.json")
    source_path = WORK / "build/source.json"
    assert sha(source_path) == baseline_manifest["asset_sha256"][relative(source_path)]
    images = {}
    for label in LABELS:
        path = ASSETS / f"{label}_diffuse.png"
        row = selected[label]
        assert row["variant"].startswith("style_unified_")
        prompt = ROOT / row["prompt"]
        assert sha(prompt) == row["prompt_sha256"]
        assert sha(base_prompt) == row["base_prompt_sha256"]
        assert prompt.read_text(encoding="utf-8").startswith(base_prompt.read_text(encoding="utf-8"))
        digest = sha(path)
        assert digest == row["sha256"] == sha(ROOT / row["archive"]), f"{label}: selected generation differs from canonical map"
        raw = path.read_bytes()
        assert raw[:8] == b"\x89PNG\r\n\x1a\n"
        dimensions = list(struct.unpack(">II", raw[16:24]))
        assert dimensions == row["dimensions"]
        for reference in row.get("references", []):
            assert sha(Path(reference.get("snapshot", reference["path"]))) == reference["sha256"], f"{label}: changed generation input snapshot"
        images[label] = {"path": relative(path), "sha256": digest, "dimensions": dimensions,
                         "generation": row["archive"], "prompt": row["prompt"],
                         "tool": row["tool"], "postprocessing": row["postprocessing"],
                         "variant": row["variant"], "prompt_sha256": row["prompt_sha256"]}
    master = WORK / "build/fortune_master.blend"
    scene = ASSETS / "fortune.scn"
    glb = ASSETS / "fortune.glb"
    target = WORK / "build/target.json"
    source = WORK / "build/source.json"
    style_invariants = read(WORK / "review/style_pass_invariants.json")
    assert style_invariants["status"] == "PASS"
    assert style_invariants["master_sha256"] == sha(master)
    assert style_invariants["source_sha256"] == sha(source)
    assert style_invariants["target_sha256"] == sha(target)
    assert style_invariants["geometry_sha256"] == sha(WORK / "build/geometry.json")
    reports = {label: read(WORK / "review" / filename)
               for label, filename in [("runtime", "runtime_test.json"), ("roundtrip", "roundtrip_test.json"),
                                       ("proportion", "proportion_test.json"), ("master", "delivery_validate.json")]}
    assert all(report["status"] == "PASS" for report in reports.values())
    assert reports["runtime"]["target_sha256"] == sha(target)
    assert reports["runtime"]["runtime_scene_sha256"] == sha(scene)
    assert reports["roundtrip"]["runtime_scene_sha256"] == sha(scene)
    assert reports["roundtrip"]["glb_sha256"] == sha(glb)
    atlas_pixels = reports["roundtrip"]["head_atlas_pixels"]
    assert atlas_pixels["status"] == "PASS" and atlas_pixels["canonical_sha256"] == images["head"]["sha256"]
    assert len(atlas_pixels["samples"]) >= 30 and atlas_pixels["max_rgb_error"] <= .05
    glb_images = read(WORK / "review/glb_images_test.json")
    assert glb_images["status"] == "PASS" and glb_images["glb_sha256"] == sha(glb)
    for label, record in glb_images["images"].items():
        assert record["canonical_sha256"] == images[label]["sha256"] and record["pixels_equal"]
        assert record["max_channel_error_8bit"] == 0
    assert reports["master"]["master_sha256"] == sha(master)
    assert reports["master"]["source_sha256"] == sha(source)
    assert reports["master"]["target_sha256"] == sha(target)
    for label, image in images.items():
        assert reports["master"]["images"][label]["canonical_sha256"] == image["sha256"]
    capture = read(WORK / "review/engine/capture.json")
    assert capture["scene_sha256_at_start"] == sha(scene)
    assert capture["canonical_diffuse_sha256_at_start"] == {label: image["sha256"] for label, image in images.items()}
    assert capture["save_unchanged"] and reports["runtime"]["save_unchanged"] and reports["roundtrip"]["save_unchanged"]
    startup_log = WORK / "review/final_angle_capture.log"
    startup = startup_log.read_text(encoding="utf-8")
    renderer_banner = next(line for line in startup.splitlines() if line.startswith("OpenGL API "))
    assert "ANGLE" in renderer_banner and "Direct3D11" in renderer_banner
    assert "FORTUNE_CAPTURE_PASS files=64 save_unchanged=true" in startup and len(capture["files"]) == 64
    capture_hashes = {}
    for resource in capture["files"]:
        assert resource.startswith("res://docs/art/fortune_runtime_v1/review/engine/")
        image_path = ROOT / resource.removeprefix("res://")
        capture_hashes[relative(image_path)] = sha(image_path)
    geometry = read(WORK / "build/geometry.json")
    assets = {relative(path): sha(path) for path in (master, scene, glb, source, target)}
    manifest = {
        "revision": "fortune_runtime_v1", "game_visual_id": 1, "concept_design_id": "C-02",
        "name": "Fortune", "status": "runtime_integrated_pending_user_art_review",
        "texture_surface_revision": "style_unified_head_v7_body_v3_shoulder_hand_foot_v2",
        "style_pass": {
            "scope": "Diffuse surface painting only; accepted helmet v6/body v2 identity retained.",
            "baseline": "docs/art/armor_style_unification_v1/before/fortune",
            "baseline_manifest_sha256": sha(before / "manifest.json"),
            "target_and_geometry_bytes_equal_to_baseline": True,
            "additional_uv_changes": 0, "additional_vertex_position_changes": 0,
            "source_positions_indices_weights_bones_unchanged": True,
            "packed_master_invariants": "review/style_pass_invariants.json",
            "base_prompt": relative(base_prompt), "base_prompt_sha256": sha(base_prompt),
            "art_acceptance": "pending user review; engineering checks do not prove style similarity",
        },
        "concept": "docs/art/fortune_runtime_v1/approved_helmet_reference.png",
        "concept_sha256": sha(WORK / "approved_helmet_reference.png"),
        "historical_concept": "docs/art/fusion_v2_generated/c02_fortune_fusion.jpg",
        "original_scene": "assets/models/player/animated/player.gltf",
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "limits": {"uv_changed_coordinate_fraction_per_material": .15,
                   "local_geometry_fraction": .15, "silhouette_changed_fraction": .15,
                   "coordinate_and_chart_counts": "exactly original",
                   "note": "Limits measure UV counts and geometry against original. Texture repaint area and concept likeness are separate."},
        "topology": {"triangles": 720, "modular_parts": 4, "surfaces": 5, "bones": 28,
                     "uv_coordinates": 673, "uv_charts": 19, "weights_and_indices": "original unchanged"},
        "geometry": geometry, "diffuse_maps": images, "asset_sha256": assets,
        "reports": {label: {"status": report["status"], "path": "review/" + filename}
                    for label, filename, report in [("runtime", "runtime_test.json", reports["runtime"]),
                                                    ("roundtrip", "roundtrip_test.json", reports["roundtrip"]),
                                                    ("proportion", "proportion_test.json", reports["proportion"]),
                                                    ("master", "delivery_validate.json", reports["master"])]},
        "glb_embedded_images": {"status": glb_images["status"], "path": "review/glb_images_test.json"},
        "capture": {"path": "review/engine/capture.json", "renderer": capture["renderer"],
                    "driver": "opengl3_angle", "driver_evidence": {"path": "review/final_angle_capture.log",
                    "sha256": sha(startup_log), "renderer_banner": renderer_banner},
                    "engine_arguments": capture["engine_arguments"],
                    "argument_note": "Godot OS.get_cmdline_args omits parsed engine flags; driver is verified from this capture's startup banner.",
                    "images": len(capture["files"]), "save_unchanged": capture["save_unchanged"]},
        "capture_sha256": capture_hashes,
        "drafts": ["review/first_material", "review/head_v2_preview", "review/head_v2_body_v2_preview", "review/head_v3_before_shape", "review/head_v3_shape_v1_preview", "review/head_v3_chin_uv_preview", "review/head_v4_shape_preview", "review/head_v4_material_preview", "review/head_v5_material_preview", "review/head_v5_flat_visor_preview", "review/head_v6_material_preview"],
    }
    (WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = read(WORK / "build/source_summary.json")
    summary["stage"] = "runtime built and verified; user art review pending"
    (WORK / "build/source_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("FORTUNE_PROVENANCE_PASS five selected generations and all current delivery evidence verified")


if __name__ == "__main__":
    main()
