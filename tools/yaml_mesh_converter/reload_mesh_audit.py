"""Inspect authored OBJ topology for per-weapon reload-part selection."""
from __future__ import annotations

import json
from pathlib import Path

IDS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 30, 34, 35, 40, 41, 43, 45]
ROOT = Path(__file__).resolve().parents[2]


def read_obj(path: Path) -> tuple[dict, list]:
    records = {"v": [], "vt": [], "vn": []}
    material = ""
    faces = []
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] in records:
            records[fields[0]].append(line)
        elif fields[0] == "usemtl":
            material = fields[1]
        elif fields[0] == "f":
            faces.append((material, tuple(tuple(map(int, token.split("/"))) for token in fields[1:])))
    return records, faces


def coordinates(records: dict) -> list:
    return [tuple(map(float, line.split()[1:])) for line in records["v"]]


def main() -> None:
    output = ROOT / "test_output/reload_catalog"
    output.mkdir(parents=True, exist_ok=True)
    result = {}
    for id in IDS:
        key = f"gun{id:02d}"
        records, faces = read_obj(ROOT / f"assets/models/weapons/{key}.obj")
        points = coordinates(records)
        groups = []
        # UV/normal seams duplicate source vertices. Join by rounded position
        # only for inspection; generated outputs retain the original indices.
        parent = list(range(len(faces)))
        seen = {}
        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for i, (material, face) in enumerate(faces):
            for corner in face:
                pos = tuple(round(x, 5) for x in points[corner[0] - 1])
                k = (material, pos)
                if k in seen:
                    parent[find(i)] = find(seen[k])
                else:
                    seen[k] = i
        buckets = {}
        for i in range(len(faces)):
            buckets.setdefault(find(i), []).append(i)
        for selected in sorted(buckets.values(), key=lambda ids: min(ids)):
            vertices = [points[c[0] - 1] for i in selected for c in faces[i][1]]
            groups.append({"faces": selected, "material": faces[selected[0]][0],
                           "min": [round(min(p[a] for p in vertices), 5) for a in range(3)],
                           "max": [round(max(p[a] for p in vertices), 5) for a in range(3)]})
        result[key] = groups
    (output / "components.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("RELOAD_MESH_AUDIT_DONE", len(result))


if __name__ == "__main__":
    main()
