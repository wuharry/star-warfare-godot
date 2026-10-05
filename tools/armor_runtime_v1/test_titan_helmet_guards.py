"""Run Titan's real refinement contract and safe first-integration refusals.

The five commands run sequentially. Refusal text is part of the expectation:
an unrelated exit 1, parser failure or engine crash cannot pass a guard.
Only this test's revision-specific JSON report is written by this wrapper.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"
LABELS = ("head", "body", "shoulder", "hand", "foot")
REVISIONS = {"helmet_refinement_v3": 3, "helmet_refinement_v4": 4}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resource_paths(config):
    assets = ROOT / config["asset"]
    paths = {
        assets / "titan.scn", assets / "titan.glb",
        WORK / "build/titan_master.blend", ROOT / config["source"],
        WORK / "build/source.json", WORK / "build/target.json",
        WORK / "build/geometry.json", WORK / "runtime_config.json",
        WORK / "manifest.json", WORK / "README.md", WORK / "index.html",
        WORK / "generation_inputs.json", ROOT / config["generation_record"],
    }
    for label in LABELS:
        paths.add(assets / config.get("texture_files", {}).get(label, label + "_diffuse.png"))
    # Historical aliases and attempt records must also survive these refusals.
    paths.update(assets.glob("*.png"))
    paths.update((WORK / "revisions").glob("*/generation_record*.json"))
    return paths


def resource_hashes(config):
    return {path.relative_to(ROOT).as_posix(): digest(path)
            for path in sorted(resource_paths(config)) if path.is_file()}


def output_text(value):
    if value is None:
        return ""
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value


def run_check(command, expected_code, expected_marker):
    row = {"command": command, "expected_exit_code": expected_code,
           "expected_marker": expected_marker, "timeout_seconds": 90}
    try:
        actual = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=90)
        row.update(exit_code=actual.returncode, stdout=actual.stdout, stderr=actual.stderr,
                   timed_out=False)
    except subprocess.TimeoutExpired as error:
        row.update(exit_code=None, stdout=output_text(error.stdout),
                   stderr=output_text(error.stderr), timed_out=True)
    except OSError as error:
        row.update(exit_code=None, stdout="", stderr=str(error), timed_out=False,
                   invocation_error=True)
    combined = row["stdout"] + "\n" + row["stderr"]
    row["expected_marker_present"] = expected_marker in combined
    faults = re.findall(r"(?im)^.*(?:Traceback \(most recent call last\)|SCRIPT ERROR:|"
                        r"Parse Error:|AssertionError|Segmentation fault|crash_handler|fatal error).*$",
                        combined)
    # The compiler's one deliberate push_error is the expected guard refusal.
    faults.extend(line for line in combined.splitlines()
                  if re.match(r"\s*ERROR:", line) and expected_marker not in line)
    row["unexpected_runtime_errors"] = faults
    row["status"] = "PASS" if (row["exit_code"] == expected_code
                                    and row["expected_marker_present"] and not faults
                                    and not row["timed_out"]) else "FAIL"
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Path to the existing Godot executable.")
    args = parser.parse_args()
    if not any(character in args.godot for character in ("/", "\\")):
        parser.error("--godot must specify an executable path, not a PATH command name")
    godot = Path(args.godot).expanduser()
    godot = godot.resolve() if godot.is_absolute() else (ROOT / godot).resolve()
    if not godot.is_file():
        parser.error("Godot executable does not exist: " + str(godot))
    config = json.loads((WORK / "runtime_config.json").read_text(encoding="utf-8"))
    revision = config.get("active_helmet_revision")
    if revision not in REVISIONS:
        parser.error("Only helmet_refinement_v3 and helmet_refinement_v4 are supported")
    if not config.get("head_refinement"):
        parser.error("Titan refinement guard requires the existing head_refinement contract")

    before = resource_hashes(config)
    commands = [
        ([sys.executable, "tools/armor_runtime_v1/adopt.py", "--armor=titan"], 1,
         "First-integration adoption would restore the old head PNG. Use the active helmet generation_record.json and README workflow."),
        ([sys.executable, "tools/armor_runtime_v1/provenance.py", "--armor=titan"], 1,
         "First-integration provenance does not certify the refined head. Use validate_titan_helmet.py and the active revision manifest."),
        ([sys.executable, "tools/armor_runtime_v1/review.py", "--armor=titan"], 1,
         f"The first-integration review template assumes unchanged UVs. Open revisions/{revision}/index.html for the active helmet review."),
        ([str(godot), "--headless", "--path", str(ROOT), "--script",
          "res://tools/armor_runtime_v1/compile.gd", "--", "--armor=titan"], 1,
         "Titan visor subdivision uses update_titan_helmet.gd; the first-integration compiler cannot replace its expanded head."),
        ([str(godot), "--headless", "--path", str(ROOT), "--script",
          "res://tests/armor_head_refinement_contract_test.gd"], 0,
         "ARMOR_HEAD_REFINEMENT_CONTRACT_PASS valid_asset / changed_weights_rejected / duplicate_and_lost_faces_rejected"),
    ]
    checks = [run_check(*command) for command in commands]
    after = resource_hashes(config)
    changed = [path for path in sorted(before.keys() | after.keys())
               if before.get(path) != after.get(path)]
    unchanged = before == after
    passed = unchanged and all(row["status"] == "PASS" for row in checks)
    report = {"status": "PASS" if passed else "FAIL", "revision": revision,
              "resource_files_unchanged": unchanged, "checked_resource_sha256": before,
              "checked_resource_sha256_after": after, "changed_resource_files": changed,
              "checks": checks,
              "scope": "Five actual sequential subprocesses; exact refusal/PASS markers and resource before/after hashes. No expectation or refinement contract is rewritten."}
    output = WORK / f"review/helmet_v{REVISIONS[revision]}_contract_and_guards_test.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"TITAN_HELMET_GUARDS_{report['status']} revision={revision} checks=5 resources_unchanged={str(unchanged).lower()}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
