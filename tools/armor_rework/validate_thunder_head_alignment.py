"""Read-only verification of actual SCN dumps from thunder_head_alignment_test.gd.

The pinned baseline is the already integrated SW2 Thunder, not the classic SW1
head and not SW2's raw 775-coordinate mesh. Results are printed as JSON; this
tool never rewrites a model, texture, snapshot, import setting, or report.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/thunder_head_alignment_v1"
SNAPSHOT_SHA = "2ecb0ec87ae0e24172f2b3002c00c2d25155fa37d054cd5aaa157cfe1e2f8201"
BEFORE_SCENE_SHA = "9f939667c6516ee3e2335cb973abeb7805d6865fd4df6b97821303bcd2661df5"
BEFORE_SCENE = "docs/art/thunder_head_alignment_v1/before/resources/assets/armors/thunder/thunder.scn"
CURRENT_SCENE = "assets/armors/thunder/thunder.scn"
PART_NAMES = ("ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06")
HEAD = PART_NAMES[0]
SHAPE_LIMIT = 0.20
SEAM_TOLERANCE = 1e-6
VECTOR_ZERO_AREA_SQUARED = 1e-24
ARRAY_MAX = 13
MUTABLE_HEAD_CHANNELS = {0, 1, 2}  # Mesh vertex, normal, tangent.


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    def reject_constant(value: str) -> None:
        raise ValueError(f"Non-finite JSON constant: {value}")

    value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def repository_path(relative: str) -> Path:
    candidate = Path(relative.removeprefix("res://"))
    if candidate.is_absolute():
        raise ValueError(f"Expected a repository-relative path: {relative}")
    result = (ROOT / candidate).resolve()
    if not result.is_relative_to(ROOT):
        raise ValueError(f"Path leaves the project: {relative}")
    return result


def verify_snapshot() -> tuple[dict[str, Any], list[dict[str, str]]]:
    path = WORK / "before/snapshot.json"
    if digest(path) != SNAPSHOT_SHA:
        raise ValueError("Pinned before snapshot changed")
    snapshot = read_json(path)
    records = snapshot.get("records")
    if not isinstance(records, list) or len(records) != 112:
        raise ValueError("Frozen before snapshot must retain its 112 records")
    seen: set[str] = set()
    dependencies = []
    for record in records:
        name = record["path"]
        if name in seen:
            raise ValueError(f"Duplicated before snapshot record: {name}")
        seen.add(name)
        frozen = repository_path(record["snapshot"])
        if frozen.stat().st_size != record["bytes"] or digest(frozen) != record["sha256"]:
            raise ValueError(f"Frozen bytes changed: {name}")
        if name.startswith("assets/") and Path(name).suffix in {".png", ".res", ".gdshader"}:
            current = repository_path(name)
            if digest(current) != record["sha256"]:
                raise ValueError(f"Old shared dependency changed: {name}")
            dependencies.append({"path": name, "sha256": record["sha256"]})
    if digest(repository_path(BEFORE_SCENE)) != BEFORE_SCENE_SHA:
        raise ValueError("Pinned before SCN changed")
    return snapshot, dependencies


def numeric_list(values: Any, width: int, label: str) -> list[Any]:
    if not isinstance(values, list) or len(values) % width:
        raise ValueError(f"Invalid component count: {label}")
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in values):
        raise ValueError(f"Non-finite or non-number component: {label}")
    return values


def vectors(values: list[Any]) -> list[tuple[float, float, float]]:
    return [tuple(float(v) for v in values[i:i + 3]) for i in range(0, len(values), 3)]


def subtract(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, ...]:
    return tuple(x - y for x, y in zip(a, b))


def dot(a: tuple[float, ...], b: tuple[float, ...]) -> float:
    return sum(x * y for x, y in zip(a, b))


def cross(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, float, float]:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def bounds(points: list[tuple[float, float, float]]) -> dict[str, list[float]]:
    if not points:
        raise ValueError("Head measurement is empty")
    lower = [min(p[i] for p in points) for i in range(3)]
    upper = [max(p[i] for p in points) for i in range(3)]
    return {"minimum": lower, "maximum": upper, "size": [b - a for a, b in zip(lower, upper)]}


def part_map(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if document.get("schema_version") != 1 or not isinstance(document.get("parts"), list):
        raise ValueError("Expected actual-SCN scene_arrays schema_version 1")
    parts = document["parts"]
    if len(parts) != 4 or {p.get("name") for p in parts} != set(PART_NAMES):
        raise ValueError("Expected exactly the four unique Thunder parts")
    return {p["name"]: p for p in parts}


def uses_normal_map(surface: dict[str, Any]) -> bool:
    shader = surface["material"].get("storage_properties", {}).get("shader", {})
    path = shader.get("path", "")
    if not path:
        return False
    source = repository_path(path).read_text(encoding="utf-8")
    return re.search(r"\bNORMAL_MAP\s*=", source) is not None


def tangent_frame_error(normal: tuple[float, ...], tangent: tuple[float, ...], handedness: float) -> bool:
    return abs(math.sqrt(dot(tangent, tangent)) - 1) > 0.03 or abs(dot(tangent, normal)) > 0.03 or abs(abs(handedness) - 1) > 0.001


def unused_tangent_findings(parts: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    findings = []
    for name, part in parts.items():
        for surface in part["surfaces"]:
            if uses_normal_map(surface) or not surface["tangents"]:
                continue
            invalid = []
            maximum_dot = 0.0
            for index in range(len(surface["vertices"]) // 3):
                normal = tuple(surface["normals"][index * 3:index * 3 + 3])
                tangent = tuple(surface["tangents"][index * 4:index * 4 + 3])
                handedness = surface["tangents"][index * 4 + 3]
                maximum_dot = max(maximum_dot, abs(dot(normal, tangent)))
                if tangent_frame_error(normal, tangent, handedness):
                    invalid.append(index)
            if invalid:
                findings.append({"part": name, "surface": surface["surface"], "material": surface["material"].get("resource_name", ""), "shader_uses_normal_map": False, "non_orthonormal_frames": len(invalid), "first_vertex": invalid[0], "maximum_abs_normal_tangent_dot": maximum_dot, "scope": "Unused tangent data; preservation is verified by exact immutable array comparison"})
    return findings


def validate_part(part: dict[str, Any]) -> None:
    name = part["name"]
    if len(numeric_list(part["transform"], 12, name + "/transform")) != 12:
        raise ValueError(f"Invalid local transform: {name}")
    skin = part["skin"]
    if len(skin) != 28 or len({v["name"] for v in skin}) != 28 or any(not v["name"] for v in skin):
        raise ValueError(f"Expected 28 unique named game binds: {name}")
    for bind in skin:
        if len(numeric_list(bind["pose"], 12, name + "/bind_pose")) != 12:
            raise ValueError(f"Invalid named bind pose: {name}")
    if part["skeleton"] != ".." or not part["surfaces"]:
        raise ValueError(f"Invalid modular attachment or no surfaces: {name}")
    for sid, surface in enumerate(part["surfaces"]):
        label = f"{name}/surface{sid}"
        if surface["surface"] != sid or surface["primitive"] != 3:
            raise ValueError(f"Unexpected surface order or non-triangle primitive: {label}")
        positions = numeric_list(surface["vertices"], 3, label + "/vertices")
        n = len(positions) // 3
        if not n:
            raise ValueError(f"No vertices: {label}")
        for key, width in [("normals", 3), ("uv", 2), ("bones", 4), ("weights", 4)]:
            if len(numeric_list(surface[key], width, label + "/" + key)) != n * width:
                raise ValueError(f"Incomplete vertex attributes: {label}/{key}")
        tangents = numeric_list(surface["tangents"], 4, label + "/tangents")
        if tangents and len(tangents) != n * 4:
            raise ValueError(f"Incomplete tangent frames: {label}")
        normal_mapped = uses_normal_map(surface)
        if normal_mapped and len(tangents) != n * 4:
            raise ValueError(f"Normal-mapped surface lacks complete tangent frames: {label}")
        indices = numeric_list(surface["indices"], 3, label + "/indices")
        if any(int(index) != index or index < 0 or index >= n for index in indices):
            raise ValueError(f"Invalid triangle index: {label}")
        if not indices and n % 3:
            raise ValueError(f"Unrolled triangle vertex count is not integral: {label}")
        if len(surface["array_hashes"]) != ARRAY_MAX or len(surface["array_types"]) != ARRAY_MAX:
            raise ValueError(f"Incomplete native Mesh array fingerprints: {label}")
        for i in range(n):
            bone_ids = surface["bones"][i * 4:i * 4 + 4]
            weights = surface["weights"][i * 4:i * 4 + 4]
            if any(v != int(v) or v < 0 or v >= 28 for v in bone_ids) or any(v < 0 for v in weights) or abs(sum(weights) - 1) > 1e-4:
                raise ValueError(f"Invalid or unnormalized skin influences: {label}/{i}")
            normal = tuple(surface["normals"][i * 3:i * 3 + 3])
            if abs(math.sqrt(dot(normal, normal)) - 1) > 0.03:
                raise ValueError(f"Invalid vertex normal: {label}/{i}")
            if tangents and normal_mapped:
                tangent = tuple(tangents[i * 4:i * 4 + 3])
                if tangent_frame_error(normal, tangent, tangents[i * 4 + 3]):
                    raise ValueError(f"Invalid normal-map tangent frame: {label}/{i}")


def non_head_comparison(part: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(part)
    for surface in result["surfaces"]:
        material = surface["material"]
        if material.get("resource_path_kind") == "embedded":
            material.pop("resource_path", None)
    return result


def compare_scenes(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    old, current = part_map(before), part_map(after)
    for part in list(old.values()) + list(current.values()):
        validate_part(part)
    record: dict[str, Any] = {"baseline": "pinned already-integrated SW2 Thunder SCN", "geometry_limit_against_integrated_before": SHAPE_LIMIT, "seam_tolerance_m": SEAM_TOLERANCE, "unused_tangent_baseline_findings": unused_tangent_findings(old), "unused_tangent_current_findings": unused_tangent_findings(current), "normal_map_tangent_contract": "Complete finite orthonormal frames required on every surface whose actual shader assigns NORMAL_MAP; unchanged unused tangent defects are reported separately"}
    non_head = []
    for name in PART_NAMES:
        a, b = old[name], current[name]
        for key in ["transform", "skeleton", "skin"]:
            if a[key] != b[key]:
                errors.append(f"Transform/attachment/named skin changed: {name}/{key}")
        if name != HEAD:
            exact = non_head_comparison(a) == non_head_comparison(b)
            non_head.append({"part": name, "arrays_materials_skin_exact": exact})
            if not exact:
                errors.append(f"Non-head arrays or material properties changed: {name}")
    a, b = old[HEAD], current[HEAD]
    if len(a["surfaces"]) != len(b["surfaces"]):
        raise ValueError("Head surface count changed; cannot align unchanged surface order")
    points_before: list[tuple[float, float, float]] = []
    points_after: list[tuple[float, float, float]] = []
    seams: dict[tuple[float, float, float], tuple[float, float, float]] = {}
    max_move = max_gap = 0.0
    flips = new_degenerate = inherited_degenerate = 0
    triangles_before = triangles_after = uv_changed = 0
    surface_records = []
    for sid, (u, v) in enumerate(zip(a["surfaces"], b["surfaces"])):
        for field in ["surface", "primitive", "format", "uv", "bones", "weights", "indices", "array_types"]:
            if u[field] != v[field]:
                errors.append(f"Head immutable array changed: surface{sid}/{field}")
        for channel in range(ARRAY_MAX):
            if channel not in MUTABLE_HEAD_CHANNELS and u["array_hashes"][channel] != v["array_hashes"][channel]:
                errors.append(f"Head extra/immutable channel changed: surface{sid}/channel{channel}")
        p, q = vectors(u["vertices"]), vectors(v["vertices"])
        order_before = [int(i) for i in u["indices"]] if u["indices"] else list(range(len(p)))
        order_after = [int(i) for i in v["indices"]] if v["indices"] else list(range(len(q)))
        triangles_before += len(order_before) // 3
        triangles_after += len(order_after) // 3
        uv_changed += sum(u["uv"][i:i + 2] != v["uv"][i:i + 2] for i in range(0, min(len(u["uv"]), len(v["uv"])), 2))
        uv_changed += abs(len(u["uv"]) - len(v["uv"])) // 2
        points_before.extend(p)
        points_after.extend(q)
        surface_records.append({"surface": sid, "vertices_before": len(p), "vertices_after": len(q), "triangles_before": len(order_before) // 3, "triangles_after": len(order_after) // 3, "uv_exact": u["uv"] == v["uv"], "skin_arrays_exact": u["bones"] == v["bones"] and u["weights"] == v["weights"], "indices_exact": u["indices"] == v["indices"]})
        if len(p) != len(q):
            errors.append(f"Head vertex count changed: surface{sid}")
            continue
        for original, target in zip(p, q):
            distance = math.sqrt(dot(subtract(target, original), subtract(target, original)))
            max_move = max(max_move, distance)
            if original in seams:
                gap = subtract(target, seams[original])
                max_gap = max(max_gap, math.sqrt(dot(gap, gap)))
            else:
                seams[original] = target
        for i in range(0, len(order_before), 3):
            ia, ib, ic = order_before[i:i + 3]
            normal_before = cross(subtract(p[ib], p[ia]), subtract(p[ic], p[ia]))
            normal_after = cross(subtract(q[ib], q[ia]), subtract(q[ic], q[ia]))
            if dot(normal_before, normal_before) <= VECTOR_ZERO_AREA_SQUARED:
                inherited_degenerate += 1
            elif dot(normal_after, normal_after) <= VECTOR_ZERO_AREA_SQUARED:
                new_degenerate += 1
            elif dot(normal_before, normal_after) <= 0:
                flips += 1
    before_bounds, after_bounds = bounds(points_before), bounds(points_after)
    scale = min(before_bounds["size"])
    if scale <= 0:
        raise ValueError("Integrated before-head bounds have a zero axis")
    ratio = max_move / scale
    dimension_delta = [abs(new - old) / old for old, new in zip(before_bounds["size"], after_bounds["size"])]
    if ratio > SHAPE_LIMIT:
        errors.append("Head displacement exceeds integrated-before 20%")
    if any(delta > SHAPE_LIMIT for delta in dimension_delta):
        errors.append("Head dimensions exceed integrated-before 20%")
    if max_gap > SEAM_TOLERANCE:
        errors.append("UV-split physical vertices separate after deformation")
    if flips or new_degenerate:
        errors.append("Head introduces flipped or degenerate faces")
    record.update({"status": "PASS" if not errors else "FAIL", "errors": errors, "head_surfaces": surface_records, "head_vertices_before": len(points_before), "head_vertices_after": len(points_after), "head_added_vertices": len(points_after) - len(points_before), "head_triangles_before": triangles_before, "head_triangles_after": triangles_after, "head_added_triangles": triangles_after - triangles_before, "head_uv_changed_coordinates": uv_changed, "unique_before_physical_points": len(seams), "max_displacement_m": max_move, "before_smallest_axis_m": scale, "max_displacement_fraction": ratio, "dimension_delta_fraction": dimension_delta, "before_bounds": before_bounds, "after_bounds": after_bounds, "max_seam_gap_m": max_gap, "flipped_faces": flips, "new_degenerate_faces": new_degenerate, "inherited_degenerate_faces": inherited_degenerate, "non_head_parts": non_head, "named_game_skin_binds": 28})
    return record


def source_statistics(snapshot: dict[str, Any], current_triangles: int, current_coordinates: int) -> dict[str, Any]:
    source_path = "assets/armors/thunder/source_sw2/modern_head.json"
    record = next(r for r in snapshot["records"] if r["path"] == source_path)
    if digest(repository_path(source_path)) != record["sha256"]:
        raise ValueError("Raw SW2 source JSON changed")
    source = read_json(repository_path(record["snapshot"]))
    points = [tuple(float(v) for v in p) for p in source["positions_game"]]
    triangles = sum(len(s) for s in source["submeshes"])
    return {"scope": "Informational raw SW2 source comparison; different topology and rig from integrated head", "source": source_path, "sha256": record["sha256"], "raw_source_coordinates": len(points), "raw_source_triangles": triangles, "raw_source_named_binds": len(source["bone_names"]), "raw_source_bounds": bounds(points), "current_unrolled_surface_coordinates": current_coordinates, "current_integrated_triangles": current_triangles, "current_triangle_count_factor_vs_raw_sw2": current_triangles / triangles, "raw_source_geometry_budget_validation": "NOT APPLICABLE: no source-vertex lineage for added neck/respirator and prior shell subdivision", "classic_sw1_head_geometry_equivalence": "NOT RUN"}


def verify_engine_binding(report: dict[str, Any], before: Path, after: Path, comparison: dict[str, Any]) -> None:
    expected = {"status": "PASS", "mode": "compare", "before_scene_sha256": BEFORE_SCENE_SHA, "current_scene_sha256": digest(repository_path(CURRENT_SCENE)), "snapshot_sha256": SNAPSHOT_SHA, "before_arrays_sha256": digest(before), "after_arrays_sha256": digest(after), "real_save_unchanged": True}
    for field, value in expected.items():
        if report.get(field) != value:
            raise ValueError(f"Actual SceneTree report is missing or stale: {field}")
    if report.get("errors") != []:
        raise ValueError("Actual SceneTree test has errors")
    for field in ["max_displacement_m", "before_smallest_axis_m", "max_displacement_fraction", "max_seam_gap_m"]:
        if not math.isclose(report[field], comparison[field], rel_tol=1e-5, abs_tol=1e-7):
            raise ValueError(f"Independent geometry measurement differs from actual SceneTree: {field}")
    for field in ["flipped_faces", "new_degenerate_faces", "inherited_degenerate_faces"]:
        if report[field] != comparison[field]:
            raise ValueError(f"Independent face measurement differs from actual SceneTree: {field}")


def self_test() -> dict[str, Any]:
    normal = cross((0.4, 0.0, 0.1), (0.0, 0.4, 0.05))
    length = math.sqrt(dot(normal, normal))
    normal = tuple(v / length for v in normal)
    surface = {"surface": 0, "primitive": 3, "format": 0, "vertices": [0, 0, 0, 0.4, 0, 0.1, 0, 0.4, 0.05], "normals": list(normal) * 3, "tangents": [], "uv": [0, 0, 1, 0, 0, 1], "bones": [0, 0, 0, 0] * 3, "weights": [1, 0, 0, 0] * 3, "indices": [], "array_hashes": ["fixture"] * ARRAY_MAX, "array_types": [0] * ARRAY_MAX, "material": {"resource_path_kind": "embedded", "resource_path": "fixture::material", "storage_properties": {}}}
    skin = [{"name": f"fixture_bone_{i}", "bone": -1, "pose": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]} for i in range(28)]
    before = {"schema_version": 1, "parts": [{"name": name, "transform": skin[0]["pose"], "skeleton": "..", "skin": skin, "surfaces": [copy.deepcopy(surface)]} for name in PART_NAMES]}
    before["parts"][0]["surfaces"].append(copy.deepcopy(surface))
    before["parts"][0]["surfaces"][1]["surface"] = 1
    assert compare_scenes(before, copy.deepcopy(before))["status"] == "PASS"
    accepted = copy.deepcopy(before)
    for item in accepted["parts"][0]["surfaces"]:
        item["vertices"][0] += 1e-4
    assert compare_scenes(before, accepted)["status"] == "PASS"
    cases = []
    for name in ["uv_changed", "skin_changed", "physical_seam_split", "non_head_changed", "over_budget", "face_flipped", "duplicated_triangle", "lost_face"]:
        bad = copy.deepcopy(before)
        head = bad["parts"][0]["surfaces"][0]
        if name == "uv_changed":
            head["uv"][0] += 0.01
        elif name == "skin_changed":
            head["bones"][0] = 1
        elif name == "physical_seam_split":
            head["vertices"][0] += 0.001
        elif name == "non_head_changed":
            bad["parts"][1]["surfaces"][0]["uv"][0] += 0.01
        elif name == "over_budget":
            for s in bad["parts"][0]["surfaces"]:
                for i in range(2, len(s["vertices"]), 3):
                    s["vertices"][i] += 0.03
        elif name == "face_flipped":
            head["vertices"][6:9] = [0, -0.4, 0.05]
        elif name == "duplicated_triangle":
            head["indices"] = [0, 1, 2, 0, 1, 2]
        else:
            bad["parts"][0]["surfaces"].pop()
        try:
            result = compare_scenes(before, bad)
        except ValueError as error:
            result = {"status": "FAIL", "errors": [str(error)]}
        assert result["status"] == "FAIL", name
        cases.append({"mutation": name, "rejected": True, "errors": result["errors"]})
    return {"status": "PASS", "scope": "Synthetic corruption tests only, not a real engine or artwork validation", "valid_identity_and_consistent_motion_accepted": True, "rejected_cases": cases}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, default=WORK / "before/scene_arrays.json")
    parser.add_argument("--after", type=Path, default=WORK / "scene_arrays.json")
    parser.add_argument("--engine-report", type=Path, default=WORK / "scene_test.json")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            report = self_test()
        else:
            snapshot, dependencies = verify_snapshot()
            before, after = read_json(arguments.before), read_json(arguments.after)
            if before.get("scene_sha256") != BEFORE_SCENE_SHA or after.get("scene_sha256") != digest(repository_path(CURRENT_SCENE)):
                raise ValueError("Actual scene serialization is stale")
            if before.get("scene") != "res://" + BEFORE_SCENE or after.get("scene") != "res://" + CURRENT_SCENE:
                raise ValueError("Unexpected actual SCN source paths")
            if before.get("source_rig_sha256") != after.get("source_rig_sha256") or digest(repository_path(after["source_rig"])) != after["source_rig_sha256"]:
                raise ValueError("Original game rig source changed")
            report = compare_scenes(before, after)
            verify_engine_binding(read_json(arguments.engine_report), arguments.before, arguments.after, report)
            report.update({"scene_provenance": {"before_scene_sha256": BEFORE_SCENE_SHA, "current_scene_sha256": digest(repository_path(CURRENT_SCENE)), "snapshot_sha256": SNAPSHOT_SHA, "before_arrays_sha256": digest(arguments.before), "after_arrays_sha256": digest(arguments.after), "engine_report_sha256": digest(arguments.engine_report)}, "old_shared_dependencies": {"status": "PASS", "count": len(dependencies), "records": dependencies}, "original_sw2_source_statistics": source_statistics(snapshot, report["head_triangles_after"], report["head_vertices_after"]), "not_run": ["Artistic concept likeness", "Classic SW1 original-head geometry equivalence", "Animation/gameplay captures", "Mobile performance"]})
    except (AssertionError, KeyError, TypeError, ValueError, OSError, StopIteration) as error:
        report = {"status": "FAIL", "errors": [f"{type(error).__name__}: {error}"]}
    print(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
