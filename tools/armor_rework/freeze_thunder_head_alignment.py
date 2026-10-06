"""Freeze the actual default Thunder A before any helmet changes (byte copies)."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/art/thunder_head_alignment_v1/before"


def main():
    index = DEST / "snapshot.json"
    if index.exists():
        raise SystemExit("Frozen baseline already exists; do not replace it")
    files = set((ROOT / "assets/armors/thunder").rglob("*"))
    files = {p for p in files if p.is_file() and not p.name.endswith(".import")}
    files.update(ROOT / p for p in [
        "docs/art/armor_rework/thunder.blend",
        "docs/art/armor_rework/thunder_prototype.blend",
        "assets/equipment_refined/textures/f8d96c60d30f.png",
        "docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png",
        "docs/art/fusion_v2_generated/c07_thunder_fusion.jpg",
        "test_output/armor_rework/thunder_sw2_meshes.json",
        "test_output/thunder_current_default_test.log",
        "test_output/thunder_current_prototype_test.log",
        "test_output/thunder_current_sw2_capture.log",
        "tools/armor_rework/build_thunder.py",
        "tools/armor_rework/thunder_helmet.py",
        "tools/armor_rework/thunder_body.py",
        "tools/armor_rework/compile_thunder.gd",
        "tools/thunder_helmet_comparison/capture.gd",
        "tools/thunder_helmet_comparison/framing.json",
        "tests/thunder_armor_test.gd",
        "scripts/game/armor_visuals.gd",
    ])
    files.update((ROOT / "test_output/thunder_helmet_comparison/sw2").glob("*"))
    entries = []
    for source in sorted(files):
        relative = source.relative_to(ROOT).as_posix()
        target = DEST / "resources" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        entries.append({"path": relative, "snapshot": target.relative_to(ROOT).as_posix(),
                        "bytes": source.stat().st_size,
                        "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    index.write_text(json.dumps({
        "schema": "thunder-head-snapshot-v1", "date": "2026-10-07",
        "baseline": "approved current default Thunder A (SW2-derived), not classic SW1",
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "records": entries,
    }, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"snapshot": index.relative_to(ROOT).as_posix(), "records": len(entries),
                      "sha256": hashlib.sha256(index.read_bytes()).hexdigest()}))


if __name__ == "__main__":
    main()
