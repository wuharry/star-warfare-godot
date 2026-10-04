"""Validate actual generation records and record the final Tank delivery.

Read-only for assets; writes manifest.json after fresh runtime/Blender checks.
"""
import hashlib
import json
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
            canonical = describe(row["output"])
            assert canonical["sha256"] == archive["sha256"]
            entry["canonical"] = canonical
            entry["runtime_label"] = runtime_label(row)
        generation.append(entry)
    tests = {}
    for name in ["runtime_test", "roundtrip_test", "proportion_test", "delivery_validate"]:
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
    roundtrip=json.loads((WORK / "review/roundtrip_test.json").read_text(encoding="utf-8"))
    assert roundtrip["glb_sha256"] == describe("assets/armors/tank_v1/tank.glb")["sha256"]
    geometry = json.loads((WORK / "build/geometry.json").read_text(encoding="utf-8"))
    files = [describe(WORK / "build/tank_master.blend"),
             describe("assets/armors/tank_v1/tank.scn"),
             describe("assets/armors/tank_v1/tank.glb")]
    files += [describe(f"assets/armors/tank_v1/{label}_diffuse.png") for label in sorted(LABELS)]
    captures = [describe(str(path).removeprefix("res://")) for path in capture["files"]]
    manifest = {"schema_version": 1, "design_id": "C-03", "runtime_id": 2,
                "name": "Tank", "revision": "tank_runtime_v1",
                "status": "runtime_integrated_pending_user_art_review",
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
