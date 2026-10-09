"""Archive unchanged native Thunder atlas bytes and exact prepared provenance."""
import argparse
import hashlib
import json
import shutil
import sys
from datetime import date
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/armor_runtime_v1"))
from prepare_generation import BASE
from first_integration_contract import BASE_PROMPT_SHA256

WORK = ROOT / "docs/art/thunder_draft_v3"
OUTPUT = ROOT / "assets/armors/thunder/textures/draft_head_v3.png"


def describe(path):
    path = Path(path)
    if not path.is_absolute():
        path = ROOT / path
    data = path.read_bytes()
    out = {"path": path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path),
           "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    if path.suffix.lower() == ".png":
        with Image.open(path) as image:
            out.update(dimensions=list(image.size), mode=image.mode)
    return out


def register(native):
    plan = json.loads((WORK / "generation_plan.json").read_text(encoding="utf-8"))[0]
    history_path = WORK / "generation_inputs.json"
    history = json.loads(history_path.read_text(encoding="utf-8")) if history_path.exists() else []
    attempt = len(history) + 1
    assert attempt == plan["attempt"] and plan["label"] == "head"
    prompt = ROOT / plan["prompt"]
    base = ROOT / plan["base_prompt"]
    assert describe(prompt)["sha256"] == plan["prompt_sha256"]
    assert base.resolve() == BASE.resolve()
    assert describe(base)["sha256"] == plan["base_prompt_sha256"] == BASE_PROMPT_SHA256
    full = prompt.read_text(encoding="utf-8")
    assert base.read_text(encoding="utf-8") in full
    references = []
    assert len(plan["references"]) == len(plan["reference_images"])
    for row, actual in zip(plan["references"], plan["reference_images"]):
        assert actual == row["snapshot"]
        original = describe(row["path"])
        snapshot = describe(row["snapshot"])
        assert original["sha256"] == snapshot["sha256"] == row["sha256"]
        references.append({"input": original, "snapshot": snapshot, "role": row["role"]})
    assert len(references) == len(plan["references"]) >= 2
    native = Path(native).resolve()
    info = describe(native)
    assert info["dimensions"][0] == info["dimensions"][1] and info["dimensions"][0] >= 512
    assert info["mode"] in ["RGB", "RGBA"]
    archive = WORK / f"generated/head_attempt_{attempt:02}.png"
    assert not archive.exists()
    archive.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(native, archive)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(native, OUTPUT)
    assert describe(archive)["sha256"] == describe(OUTPUT)["sha256"] == info["sha256"]
    for row in history:
        row["selected"] = False
    history.append({"label": "head", "attempt": attempt, "selected": True, "date": str(date.today()),
                    "variant": "thunder_draft_v3", "tool": "builtin.image_gen",
                    "generated_file": str(native), "native_generator_path_available": True,
                    "archive": describe(archive), "canonical": describe(OUTPUT),
                    "prompt": describe(prompt), "base_prompt": describe(base), "full_prompt": full,
                    "references": references,
                    "postprocessing": "none; native PNG copied byte-for-byte to archive and canonical",
                    "status": "native_generated_pending_runtime_visual_review",
                    "scope": "true-original Thunder head only, exact UV/topology/skin; source position and dimension limit20%; body inherits frozen3ed unchanged, no original-whole-suit percentage"})
    history_path.write_text(json.dumps(history, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("THUNDER_DRAFT_V3_NATIVE_ARCHIVED " + info["sha256"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--native", type=Path, required=True)
    register(parser.parse_args().native)
