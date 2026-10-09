"""Pure-Python source/target failure guards; this does not certify engine output."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

LIMIT = 0.20
ROOT = Path(__file__).resolve().parents[2]


class HeadContractError(ValueError):
    pass


def _difference(a: list[float], b: list[float]) -> list[float]:
    return [a[i] - b[i] for i in range(3)]


def _length(v: list[float]) -> float:
    return math.sqrt(sum(x * x for x in v))


def _cross(a: list[float], b: list[float]) -> list[float]:
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def _points(value: Any, label: str) -> list[list[float]]:
    if not isinstance(value, list) or not value:
        raise HeadContractError(f"{label} must be a nonempty array")
    for row in value:
        if not isinstance(row, list) or len(row) != 3 or any(isinstance(x, bool) or not isinstance(x, (float, int)) or not math.isfinite(x) for x in row):
            raise HeadContractError(f"{label} must contain finite triples")
    return value


def geometry_metrics(source: list[list[float]], edited: list[list[float]], indices: list[int]) -> dict[str, Any]:
    source = _points(source, "source positions")
    edited = _points(edited, "target positions")
    if len(source) != len(edited):
        raise HeadContractError("original vertex count changed")
    if len(indices) % 3 or any(type(x) is not int or x < 0 or x >= len(source) for x in indices):
        raise HeadContractError("invalid original triangle indices")
    original_size = [max(p[i] for p in source) - min(p[i] for p in source) for i in range(3)]
    target_size = [max(p[i] for p in edited) - min(p[i] for p in edited) for i in range(3)]
    normalizer = min(original_size)
    if normalizer <= 0:
        raise HeadContractError("original smallest dimension is zero")
    max_displacement = max(_length(_difference(a, b)) for a, b in zip(source, edited))
    fraction = max_displacement / normalizer
    dimensions = [abs(target_size[i] / original_size[i] - 1) for i in range(3)]
    if fraction > LIMIT + 1e-6:
        raise HeadContractError("original-head displacement exceeds 20%")
    if max_displacement <= 1e-6:
        raise HeadContractError("no actual head geometry refinement")
    if max(dimensions) > LIMIT + 1e-6:
        raise HeadContractError("original-head dimension change exceeds 20%")
    flips, degenerate, seams = [], [], []
    for offset in range(0, len(indices), 3):
        i, j, k = indices[offset:offset + 3]
        a = _cross(_difference(source[j], source[i]), _difference(source[k], source[i]))
        b = _cross(_difference(edited[j], edited[i]), _difference(edited[k], edited[i]))
        if sum(x * x for x in a) > 1e-12:
            if sum(x * x for x in b) <= 1e-12:
                degenerate.append(offset // 3)
            elif sum(x * y for x, y in zip(a, b)) <= 0:
                flips.append(offset // 3)
    for first in range(len(source)):
        for second in range(first):
            if _length(_difference(source[first], source[second])) <= 1e-7 and _length(_difference(edited[first], edited[second])) > 1e-6:
                seams.append([second, first])
    if flips or degenerate or seams:
        raise HeadContractError(f"triangle flips={flips}; new degenerate={degenerate}; split seams={seams}")
    return {
        "normalizer_original_smallest_dimension_m": normalizer,
        "max_rest_displacement": max_displacement,
        "max_displacement_fraction_of_smallest_dimension": fraction,
        "dimension_change_fractions": dimensions,
        "max_dimension_change_fraction": max(dimensions),
        "flipped_triangles": flips,
        "new_degenerate_triangles": degenerate,
        "seam_breaks": seams,
    }


def validate_target(source: dict[str, Any], target: dict[str, Any]) -> dict[str, Any]:
    if target.get("revision") != "thunder_draft_v3" or target.get("geometry_mode") != "bounded_original_head_only" or target.get("geometry_limit") != LIMIT:
        raise HeadContractError("invalid revision / geometry mode / fixed original limit")
    if len(source["positions"]) != 147 or len(source["indices"]) != 196 * 3 or len(source["uv"]) != 147 or len(source["binds"]) != 28:
        raise HeadContractError("true original head counts changed")
    if target.get("source_positions") != source["positions"]:
        raise HeadContractError("original source positions were rebased")
    for field in ["uv", "indices", "bone_indices", "weights", "binds", "source_scene", "source_scene_sha256", "source_buffer_sha256", "original_texture", "original_texture_sha256", "node"]:
        if target.get(field) != source.get(field):
            raise HeadContractError(f"original {field} changed")
    if target.get("uv_count") != 147 or target.get("triangle_count") != 196 or target.get("uv_changed_fraction") != 0:
        raise HeadContractError("original UV/topology summary changed")
    metrics = geometry_metrics(source["positions"], target["positions"], source["indices"])
    if abs(target.get("normalizer_original_smallest_dimension_m", -1) - metrics["normalizer_original_smallest_dimension_m"]) > 1e-6:
        raise HeadContractError("target normalizer was rebased")
    if abs(target.get("max_cumulative_source_displacement_fraction", -1) - metrics["max_displacement_fraction_of_smallest_dimension"]) > 1e-5:
        raise HeadContractError("target displacement metadata does not describe actual source-relative positions")
    if "physical_positions" in target and target["physical_positions"] != [[p[0], -p[2], p[1]] for p in target["positions"]]:
        raise HeadContractError("raw [x,depth,-height] / physical [x,height,depth] disagree")
    return metrics


def validate_files(config_path: Path) -> dict[str, Any]:
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    def check(path: str, expected: str) -> Path:
        resolved = ROOT / path.removeprefix("res://")
        if not expected or not resolved.is_file() or hashlib.sha256(resolved.read_bytes()).hexdigest() != expected:
            raise HeadContractError(f"pinned bytes changed or absent: {path}")
        return resolved
    for key in ["source_scene", "source_buffer", "original_head_texture", "before_scene", "before_snapshot", "head_source_json", "head_target", "native_generated_png"]:
        check(config[key], config[key + "_sha256"])
    for group in ["protected_alternates", "inherited_body_resource_sha256"]:
        for path, expected in config[group].items():
            check(path, expected)
    source = json.loads((ROOT / config["head_source_json"].removeprefix("res://")).read_text(encoding="utf-8-sig"))
    target = json.loads((ROOT / config["head_target"].removeprefix("res://")).read_text(encoding="utf-8-sig"))
    for field in ["source_scene", "source_scene_sha256", "source_buffer_sha256"]:
        if source[field] != config[field]:
            raise HeadContractError(f"frozen source pin mismatch: {field}")
    if source["original_texture"] != config["original_head_texture"] or source["original_texture_sha256"] != config["original_head_texture_sha256"]:
        raise HeadContractError("frozen source atlas pin mismatch")
    return validate_target(source, target)


if __name__ == "__main__":
    result = validate_files(ROOT / "docs/art/thunder_draft_v3/runtime_config.json")
    print(json.dumps({"scope": "PURE_PYTHON_SOURCE_TARGET_GUARDS_ONLY_ENGINE_NOT_RUN", "geometry": result}, indent=2))
