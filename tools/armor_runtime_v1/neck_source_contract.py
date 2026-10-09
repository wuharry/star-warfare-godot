"""Protect a helmet's original neck connection independently of shape budgets.

Neck vertices are discovered from the true original mesh, never from an authored
target or from hard-coded vertex IDs. Position-welded triangle components which
contain both head and torso/neck bone influences own the connection, including
all UV seam duplicates. This contract does not prove rendered body coverage.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
WELD_TOLERANCE = 1e-5


def bone_role(name):
    """Recognize named head/torso joints without relying on bind indices."""
    token = re.sub(r"[^a-z0-9]", "", str(name).lower().split()[-1])
    if token.endswith("head"):
        return "head"
    if re.search(r"(?:spine|neck|chest)\d*$", token):
        return "torso"
    return "other"


def _float32_equal(a, b):
    return len(a) == len(b) and struct.pack("<" + "f" * len(a), *a) == struct.pack("<" + "f" * len(b), *b)


def discover_neck(original):
    """Return physical components, UV IDs and original faces of the neck."""
    positions, indices = original["positions"], original["indices"]
    count = len(positions)
    assert count and len(indices) % 3 == 0, "Invalid original head topology"
    assert all(len(p) == 3 and all(math.isfinite(v) for v in p) for p in positions)
    assert all(type(i) is int and 0 <= i < count for i in indices)
    assert len(original["bone_names"]) == len(original["weights"]) == count
    parents = list(range(count))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parents[max(a, b)] = min(a, b)

    # Neighbouring spatial cells avoid rounding-boundary misses. Welding only
    # identifies connectivity: every original duplicate remains protected.
    cells = defaultdict(list)
    for i, point in enumerate(positions):
        cell = tuple(math.floor(v / WELD_TOLERANCE) for v in point)
        for x in (-1, 0, 1):
            for y in (-1, 0, 1):
                for z in (-1, 0, 1):
                    for j in cells[(cell[0]+x, cell[1]+y, cell[2]+z)]:
                        if math.dist(point, positions[j]) <= WELD_TOLERANCE:
                            union(i, j)
        cells[cell].append(i)
    welded = [find(i) for i in range(count)]
    for start in range(0, len(indices), 3):
        a, b, c = indices[start:start+3]
        union(a, b)
        union(a, c)
    components = defaultdict(list)
    for i in range(count):
        components[find(i)].append(i)
    selected = []
    for ids in components.values():
        roles = {bone_role(name) for i in ids
                 for name, weight in zip(original["bone_names"][i], original["weights"][i])
                 if weight > 1e-6}
        if {"head", "torso"} <= roles:
            selected.append(ids)
    assert selected, "No original head-to-torso neck component found"
    vertex_ids = sorted(i for component in selected for i in component)
    chosen = set(vertex_ids)
    triangle_ids = [i // 3 for i in range(0, len(indices), 3)
                    if any(v in chosen for v in indices[i:i+3])]
    assert all(all(v in chosen for v in indices[i*3:i*3+3]) for i in triangle_ids)
    return {
        "discovery": "true-original position-welded triangle components with active named head and torso/neck bones",
        "weld_tolerance_m": WELD_TOLERANCE,
        "components": sorted(selected, key=lambda ids: ids[0]),
        "vertex_ids": vertex_ids,
        "physical_vertex_count": len({welded[i] for i in vertex_ids}),
        "triangle_ids": triangle_ids,
        "physical_points": [positions[i] for i in vertex_ids],
    }


def matching_neck_point(point, neck):
    """Match original physical positions, including every duplicate UV ID."""
    candidates = [p for p in neck["physical_points"] if math.dist(point, p) <= WELD_TOLERANCE]
    return min(candidates, key=lambda p: math.dist(point, p)) if candidates else None


def evaluate_neck(original, authored):
    """Measure actual authored channels; do not silently accept a new baseline."""
    neck = discover_neck(original)
    errors = []
    ids = neck["vertex_ids"]
    positions = authored.get("positions", [])
    moved = []
    for i in ids:
        if i >= len(positions) or not _float32_equal(positions[i], original["positions"][i]):
            moved.append(i)
    if moved:
        errors.append("Original neck positions changed: " + ",".join(map(str, moved)))
    channel_changes = {}
    for field in ("uv", "bone_indices", "bone_names", "weights"):
        actual = authored.get(field, original[field])
        changed = [i for i in ids if i >= len(actual) or actual[i] != original[field][i]]
        channel_changes[field] = changed
        if changed:
            errors.append("Original neck " + field + " changed: " + ",".join(map(str, changed)))
    if "raw_positions" in authored:
        changed = [i for i in ids if i >= len(authored["raw_positions"])
                   or not _float32_equal(authored["raw_positions"][i], original["raw_positions"][i])]
        channel_changes["raw_positions"] = changed
        if changed:
            errors.append("Original neck raw_positions changed: " + ",".join(map(str, changed)))
    source_faces = Counter(tuple(original["indices"][i*3:i*3+3]) for i in neck["triangle_ids"])
    chosen = set(ids)
    actual_indices = authored.get("indices", original["indices"])
    actual_faces = Counter(tuple(actual_indices[i:i+3]) for i in range(0, len(actual_indices), 3)
                           if any(v in chosen for v in actual_indices[i:i+3]))
    faces_exact = source_faces == actual_faces
    if not faces_exact:
        errors.append("Original neck triangles changed, duplicated, removed or connected to new faces")
    maximum = max((math.dist(positions[i], original["positions"][i])
                   for i in ids if i < len(positions)), default=0.0)
    return {
        "status": "FAIL" if errors else "PASS",
        "errors": errors,
        "scope": "Original neck position/UV/topology/named-skin interface only; rendered mixed-body coverage is a separate requirement",
        "discovery": neck["discovery"], "weld_tolerance_m": neck["weld_tolerance_m"],
        "component_count": len(neck["components"]),
        "physical_vertex_count": neck["physical_vertex_count"],
        "vertex_ids": ids, "triangle_ids": neck["triangle_ids"],
        "moved_vertex_ids": moved, "max_neck_displacement_m": maximum,
        "channel_changes": channel_changes, "neck_triangles_exact": faces_exact,
    }


def verify_neck(original, authored):
    report = evaluate_neck(original, authored)
    assert report["status"] == "PASS", "; ".join(report["errors"])
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--armor", default="titan", choices=("titan",))
    args = parser.parse_args()
    work = ROOT / f"docs/art/{args.armor}_runtime_v1"
    source_path = work / "revisions/original_source_v1/source.json"
    target_path = work / "build/target.json"
    source = json.loads(source_path.read_text(encoding="utf-8-sig"))
    target = json.loads(target_path.read_text(encoding="utf-8-sig"))
    original = source["parts"]["ArmorHead_05"]["surfaces"][0]
    authored = target["parts"]["ArmorHead_05"]["surfaces"][0]
    report = evaluate_neck(original, authored)
    report.update(original_source_sha256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
                  target_sha256=hashlib.sha256(target_path.read_bytes()).hexdigest())
    print(json.dumps(report, indent=2))
    print("ARMOR_NECK_SOURCE_CONTRACT_" + report["status"])
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
