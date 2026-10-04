"""Build the offline three-version review from root-owned comparison data."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/armor_style_unification_v1"
TEMPLATE = Path(__file__).with_name("review_template.html")
SUFFIXES = (
    "diffuse_front", "diffuse_quarter", "diffuse_side", "diffuse_rear",
    "head_front", "head_quarter", "head_side", "head_rear",
    "clay_front", "clay_side", "level_01_gameplay", "level_08_gameplay",
    "idle_rifle", "run_rifle", "reload_04",
)


def image_entry(relative_path: str) -> dict[str, str | bool]:
    path = (WORK / relative_path).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError(f"Capture must stay inside the repository: {relative_path}")
    exists = path.is_file()
    revision = hashlib.sha256(path.read_bytes()).hexdigest()[:16] if exists else "pending"
    return {"path": relative_path, "exists": exists, "revision": revision}


def main() -> None:
    data = json.loads((WORK / "comparison.json").read_text(encoding="utf-8-sig"))
    armors = data["armors"]
    armor_ids = [armor["id"] for armor in armors]
    if (
        not {"viper", "fortune"}.issubset(armor_ids)
        or not set(armor_ids).issubset({"viper", "fortune", "tank", "hydra", "strike", "titan"})
        or len(armor_ids) != len(set(armor_ids))
    ):
        raise ValueError("Review must preserve Viper and Fortune, with distinct authorized armor entries.")
    runtime_dirs = {
        "viper": "viper_runtime_v2",
        "fortune": "fortune_runtime_v1",
        "tank": "tank_runtime_v1",
        "hydra": "hydra_runtime_v1",
        "strike": "strike_runtime_v1",
        "titan": "titan_runtime_v1",
    }
    for armor in armors:
        armor_id = armor["id"]
        runtime_dir = armor.get("runtime_dir", runtime_dirs[armor_id])
        prefixes = {
            "original": armor.get("original_prefix", f"../{runtime_dir}/review/engine/original_"),
            "before": armor.get("before_prefix", f"before/{armor_id}/review/"),
            "after": armor.get("after_prefix", f"after/{armor_id}/review/"),
        }
        if armor.get("comparison_mode") == "first_runtime":
            prefixes.pop("before")
        explicit = armor.get("captures", {})
        armor["capture_images"] = {
            suffix: {
                version: image_entry(explicit.get(suffix, {}).get(version, f"{prefix}{suffix}.png"))
                for version, prefix in prefixes.items()
            }
            for suffix in SUFFIXES
        }
        if armor.get("reference_art"):
            armor["reference_image"] = image_entry(armor["reference_art"]["path"])
        if armor.get("after_ready") is False:
            for versions in armor["capture_images"].values():
                versions["after"]["exists"] = False
                versions["after"]["revision"] = "pending"
    template = TEMPLATE.read_text(encoding="utf-8")
    if template.count("__COMPARISON_JSON__") != 1:
        raise ValueError("Expected one embedded comparison data marker.")
    embedded = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    embedded = embedded.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    output = WORK / "index.html"
    output.write_text(template.replace("__COMPARISON_JSON__", embedded), encoding="utf-8")
    complete = sum(
        entry["exists"]
        for armor in armors
        for versions in armor["capture_images"].values()
        for entry in versions.values()
    )
    total = sum(
        len(versions)
        for armor in armors
        for versions in armor["capture_images"].values()
    )
    print(f"Review written: {output.relative_to(ROOT)}; available actual captures: {complete}/{total}")


if __name__ == "__main__":
    main()
