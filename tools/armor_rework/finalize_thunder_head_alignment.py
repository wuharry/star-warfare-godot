"""Bind fresh engine tests/captures and native generation to the delivered head."""
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/thunder_head_alignment_v1"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")


def main():
    geometry = read(WORK / "geometry_validate.json")
    scene = read(WORK / "scene_test.json")
    assert geometry["status"] == scene["status"] == "PASS"
    actual = ROOT / "assets/armors/thunder/thunder.scn"
    assert scene["current_scene_sha256"] == digest(actual)
    assert actual.read_bytes() == (ROOT / "assets/armors/thunder/thunder_sw2.scn").read_bytes()
    captures = read(WORK / "after/manifest.json")
    assert captures["runtime_scene_sha256"] == digest(actual)
    assert captures["failures"] == [] and captures["save_unchanged"]
    assert len(captures["frames"]) == 30
    for path, sha in captures["runtime_resource_sha256"].items():
        assert digest(ROOT / path.removeprefix("res://")) == sha, path
    images = []
    for frame in captures["frames"]:
        path = WORK / "after" / frame["file"]
        with Image.open(path) as image:
            image.load()
            assert image.size == (frame["width"], frame["height"])
        images.append({"path": "after/" + path.name, "sha256": digest(path),
                       "bytes": path.stat().st_size, **frame})
    tests = {}
    for key, log, needle in [
        ("default_runtime", "default_test", "THUNDER_ARMOR_PASS parts=4 triangles=12662"),
        ("alternate_prototype", "prototype_test", "THUNDER_ARMOR_PASS parts=4 triangles=39238"),
        ("compiler_guards", "compiler_guard", "THUNDER_COMPILER_VALIDATION_PASS cases=12"),
        ("normal_capture", "capture", "THUNDER_HELMET_CAPTURE_PASS stage=sw2 images=30 save_unchanged=true"),
        ("actual_scene", "scene_test", "THUNDER_HEAD_ALIGNMENT_PASS mode=compare errors=0"),
        ("blender_build", "build", "THUNDER_HEAD_ALIGNMENT_BUILD_PASS"),
        ("head_compile", "compile", "THUNDER_HEAD_ALIGNMENT_COMPILE_PASS"),
    ]:
        source = ROOT / f"test_output/thunder_head_alignment_{log}.log"
        contents = source.read_text(encoding="utf-8")
        assert needle in contents and "SCRIPT ERROR" not in contents and "FAIL" not in contents, key
        target = WORK / "logs" / source.name
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(source, target)
        tests[key] = {"status": "PASS", "log": "logs/" + target.name, "sha256": digest(target)}
    guard = read(ROOT / "test_output/thunder_head_alignment_checker_guard.json")
    assert guard["status"] == "PASS" and len(guard["rejected_cases"]) == 8
    write(WORK / "checker_guard.json", guard)
    generation = read(WORK / "generation.json")
    selected = generation["attempts"][-1]
    assert digest(ROOT / selected["selected_asset"]) == selected["selected_sha256"]
    assert digest(WORK / selected["native_archive"]) == selected["native_sha256"]
    snapshot = read(WORK / "before/snapshot.json")
    prototype = next(r for r in snapshot["records"] if r["path"] == "assets/armors/thunder/thunder_prototype.scn")
    assert digest(ROOT / prototype["path"]) == prototype["sha256"]
    report = {
        "status": "PASS", "date": "2026-10-07", "scope": "Thunder ID6 default head integration; current approved A before baseline",
        "runtime_scene_sha256": digest(actual), "head_revision": "thunder_head_alignment_v1",
        "geometry": geometry, "tests": tests, "captures": {"status": "PASS", "manifest": "after/manifest.json",
        "manifest_sha256": digest(WORK / "after/manifest.json"), "count": 30, "controlled_studio_and_pose": 27,
        "live_game_non_deterministic": 3, "save_unchanged": True, "images": images},
        "prototype_unchanged": prototype["sha256"], "generation_record_sha256": digest(WORK / "generation.json"),
        "not_run": ["User art acceptance", "Mobile performance", "Interactive browser QA", "Classic SW1 geometry equivalence"],
    }
    write(WORK / "validate.json", report)
    base = read(WORK / "before/resources/assets/armors/thunder/build_report_sw2.json")
    base["design"] = "Thunder v5 body / later C07 helmet alignment v1"
    base["head_revision"] = "thunder_head_alignment_v1"
    base["scope"] = "New head only; old approved body arrays/materials, UV/topology and 28 named binds unchanged"
    base["head_reference"] = {"path": "docs/art/fusion_v2_generated/c07_thunder_fusion.jpg",
                              "sha256": "c5e647dfc186e63bf529be00fd6796489c3819a74c76a469c6d1ec1907e7b4e1", "scope": "helmet_only"}
    base["head_alignment_report"] = {"path": "docs/art/thunder_head_alignment_v1/validate.json", "sha256": digest(WORK / "validate.json")}
    base["texture_sha256"]["helmet_aligned_albedo.png"] = selected["selected_sha256"]
    base["parts"][0]["bounds"] = read(WORK / "build_measure.json")["bounds_after"]
    for path in [ROOT / "assets/armors/thunder/build_report.json", ROOT / "assets/armors/thunder/build_report_sw2.json"]:
        write(path, base)
    print(json.dumps({"status": report["status"], "scene_sha256": digest(actual), "captures": len(images), "tests": len(tests)}))


if __name__ == "__main__":
    main()
