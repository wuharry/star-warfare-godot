"""Bounded Thunder head refinement from the immutable SW1 vertex source.

Only original head positions change. This module neither edits textures nor runs
an engine, importer, Blender, or asset compiler. The raw source uses
``[x, depth, -height]``; all design calculations use ``[x, height, depth]``.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/thunder_draft_v3"
SOURCE = WORK / "revisions/before_draft_v3/docs/art/thunder_original_v2/head_source.json"
LIVE_SOURCE = ROOT / "docs/art/thunder_original_v2/head_source.json"
DESIGN = ROOT / "docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png"
LIMIT = 0.20


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return min(high, max(low, value))


def raw_to_physical(point: list[float]) -> list[float]:
    x, depth, negative_height = point
    return [x, -negative_height, depth]


def physical_to_raw(point: list[float]) -> list[float]:
    x, height, depth = point
    return [x, depth, -height]


def transform_physical(point: list[float]) -> list[float]:
    """Evaluate the full displacement directly from one ORIGINAL position.

    Lower the single old fin, and raise its neighboring dome panels toward a
    broad ellipsoid. The combination leaves a shallow continuous center ridge
    rather than a clipped tall spike. A modest brow lift opens the frame while
    shortening the front jaw. Coincident source vertices receive identical
    mapping regardless of their UV or normal splits.
    """
    x, y, z = point
    xx, yy, zz = x, y, z
    sign = 1.0 if x > 0.0 else -1.0 if x < 0.0 else 0.0

    # The original fin peak is triplicated at exactly the same source position.
    # Its displacement is 0.09914m, below the source-width 0.10436m ceiling.
    if y > 1.96:
        return [x, y - 0.098, z - 0.015]

    cap = clamp((y - 1.69) / 0.095)
    if cap > 0.0:
        radius = max(0.0, 1.0 - (x / 0.285) ** 2 - ((z + 0.030) / 0.400) ** 2)
        round_height = 1.646 + 0.273 * math.sqrt(radius)
        yy += clamp(round_height - y, -0.035, 0.088) * cap
        xx += sign * 0.017 * cap * clamp((abs(x) - 0.060) / 0.120)

    front = clamp((-z - 0.070) / 0.200)
    jaw = clamp((1.520 - y) / 0.160) * front
    yy += 0.058 * jaw
    zz += 0.026 * jaw

    # Lift the lowest center of the old V brow, leaving its outer ear junction.
    # This is a geometric frame change, not a painted-glass coverage claim.
    brow = clamp((-z - 0.250) / 0.100)
    brow *= clamp(1.0 - abs(y - 1.620) / 0.120)
    brow *= clamp((0.190 - abs(x)) / 0.190)
    yy += 0.035 * brow
    zz += 0.008 * brow
    return [xx, yy, zz]


def subtract(a: list[float], b: list[float]) -> list[float]:
    return [a[i] - b[i] for i in range(3)]


def dot(a: list[float], b: list[float]) -> float:
    return sum(a[i] * b[i] for i in range(3))


def length(vector: list[float]) -> float:
    return math.sqrt(dot(vector, vector))


def cross(a: list[float], b: list[float]) -> list[float]:
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def bounds(points: list[list[float]]) -> dict:
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return {"min": lo, "max": hi, "size": subtract(hi, lo)}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build() -> tuple[dict, dict]:
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert sha(SOURCE) == sha(LIVE_SOURCE), "Frozen and live original vertex records differ"
    assert len(source["positions"]) == len(source["uv"]) == 147
    assert len(source["indices"]) == 196 * 3 and len(source["binds"]) == 28
    before = [raw_to_physical(p) for p in source["positions"]]
    after = [transform_physical(p) for p in before]
    before_bounds, after_bounds = bounds(before), bounds(after)
    normalizer = min(source["rest_bounds"]["size"])
    distances = [length(subtract(a, b)) for a, b in zip(after, before)]
    dimension_delta = [abs(after_bounds["size"][i] - before_bounds["size"][i]) / before_bounds["size"][i] for i in range(3)]
    flipped, degenerate = [], []
    min_cosine, min_area_ratio = 1.0, 1.0
    for tri in range(196):
        indices = source["indices"][tri * 3 : tri * 3 + 3]
        a, b, c = [before[i] for i in indices]
        aa, bb, cc = [after[i] for i in indices]
        old_cross = cross(subtract(b, a), subtract(c, a))
        new_cross = cross(subtract(bb, aa), subtract(cc, aa))
        old_area, new_area = length(old_cross), length(new_cross)
        if new_area < 1e-10:
            degenerate.append(tri)
        if old_area > 1e-10 and new_area > 1e-10:
            cosine = dot(old_cross, new_cross) / (old_area * new_area)
            min_cosine = min(min_cosine, cosine)
            min_area_ratio = min(min_area_ratio, new_area / old_area)
            if cosine <= 0.0:
                flipped.append(tri)
    pairs, new_gap = 0, 0.0
    for i in range(len(before)):
        for j in range(i + 1, len(before)):
            if length(subtract(before[i], before[j])) < 1e-5:
                pairs += 1
                new_gap = max(new_gap, length(subtract(after[i], after[j])))
    assert max(distances) / normalizer <= LIMIT, "Original cumulative head limit exceeded"
    assert max(dimension_delta) <= LIMIT, "Original head axis dimension limit exceeded"
    assert not flipped and not degenerate, "Invalid triangle orientation/area"
    assert new_gap <= 1e-6, "Coincident original surface seam opened"

    target = copy.deepcopy(source)
    target["source_positions"] = copy.deepcopy(source["positions"])
    target["positions"] = [physical_to_raw(p) for p in after]
    target["physical_positions"] = after
    target["source_rest_bounds"] = copy.deepcopy(source["rest_bounds"])
    target["rest_bounds"] = after_bounds
    target.update({
        "revision": "thunder_draft_v3",
        "geometry_mode": "bounded_original_head_only",
        "source_vertex_record": SOURCE.relative_to(ROOT).as_posix(),
        "source_vertex_record_sha256": sha(SOURCE),
        "shape_file": Path(__file__).resolve().relative_to(ROOT).as_posix(),
        "shape_sha256": sha(Path(__file__)),
        "design_authority": DESIGN.relative_to(ROOT).as_posix(),
        "design_authority_sha256": sha(DESIGN),
        "geometry_limit": LIMIT,
        "normalizer_original_smallest_dimension_m": normalizer,
        "max_cumulative_source_displacement_fraction": max(distances) / normalizer,
        "uv_changed_fraction": 0.0,
        "uv_count": 147,
        "triangle_count": 196,
    })
    peak = max(range(len(before)), key=lambda i: before[i][1])
    neighbors = [1, 10, 33, 41, 55, 74]
    summary = {
        "status": "PURE_PYTHON_SOURCE_GEOMETRY_PASSED_ENGINE_AND_ART_REVIEW_PENDING",
        "revision": target["revision"],
        "source": {"path": target["source_vertex_record"], "sha256": sha(SOURCE)},
        "shape": {"path": target["shape_file"], "sha256": target["shape_sha256"]},
        "design_authority": {"path": target["design_authority"], "sha256": target["design_authority_sha256"]},
        "raw_coordinate_convention": "[x, depth, -height]",
        "physical_coordinate_convention": "[x, height, depth], front is negative depth",
        "normalizer_original_smallest_dimension_m": normalizer,
        "original_bounds": before_bounds,
        "target_bounds": after_bounds,
        "max_cumulative_source_displacement_m": max(distances),
        "max_cumulative_source_displacement_fraction": max(distances) / normalizer,
        "maximum_displacement_vertex_ids": [i for i, d in enumerate(distances) if abs(d - max(distances)) < 1e-9],
        "head_dimension_absolute_delta_fraction": dimension_delta,
        "changed_vertices": sum(d > 1e-7 for d in distances),
        "flipped_triangles": flipped,
        "degenerate_triangles": degenerate,
        "minimum_normal_cosine": min_cosine,
        "minimum_triangle_area_ratio": min_area_ratio,
        "original_near_coincident_pairs_checked": pairs,
        "maximum_new_near_coincident_pair_gap_m": new_gap,
        "triangles": 196,
        "uv_coordinates": 147,
        "skin_binds": 28,
        "preserved_channels": ["uv", "indices", "bone_indices", "weights", "binds"],
        "crown_peak_before_m": before[peak],
        "crown_peak_after_m": after[peak],
        "peak_above_highest_neighbor_shell_before_m": before[peak][1] - max(before[i][1] for i in neighbors),
        "peak_above_highest_neighbor_shell_after_m": after[peak][1] - max(after[i][1] for i in neighbors),
        "design_changes": [
            "Lower original central fin 98mm and move it forward 15mm; raise/widen original adjacent cap planes into a broad ellipsoid without adding topology.",
            "Lift compact front jaw 58mm maximum and retract it 26mm; slightly lift the old center V-brow frame from original physical points.",
            "Keep the source ear geometry and all UV, index, bone, weight and bind arrays; inherited body is outside this module and must remain frozen.",
        ],
        "limits": [
            "This measures only the true-original head; the inherited bef5b833 body is not covered by a whole-original 20% claim.",
            "Low-poly triangles cannot exactly reconstruct the B concept dome curvature; this candidate requires actual engine front/side/quarter review.",
            "Geometric brow displacement is not a painted visor size or concept-fidelity measurement.",
            "No engine, Blender, texture modification, or asset compile was executed by this pure Python module.",
        ],
    }
    return target, summary


if __name__ == "__main__":
    candidate, analysis = build()
    output = WORK / "build"
    output.mkdir(parents=True, exist_ok=True)
    target_path = output / "head_target.json"
    target_path.write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    analysis["target"] = {"path": target_path.relative_to(ROOT).as_posix(), "sha256": sha(target_path)}
    (output / "shape_analysis.json").write_text(json.dumps(analysis, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({key: analysis[key] for key in ["status", "max_cumulative_source_displacement_fraction", "head_dimension_absolute_delta_fraction", "flipped_triangles", "degenerate_triangles", "maximum_new_near_coincident_pair_gap_m", "peak_above_highest_neighbor_shell_after_m", "target"]}, ensure_ascii=False))
