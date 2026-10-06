"""Produce a geometry-only Titan v4 review target, leaving gameplay assets intact.

Ear and lip offsets are inferred from the single approved quarter-view concept.
They are small edits in the original Godot rest-space units, not pixel-match
measurements. The original model, current UVs, topology and weights stay fixed.
"""
import copy
import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"
OUT = WORK / "review/draft_alignment_20261006"
HEAD = "ArmorHead_05"
# Representative ORIGINAL IDs identify physical positions on both mirrored
# halves and every duplicated UV seam. Negative x offsets move toward centre.
# Inferred: reduce the ear's low corner, then tuck the protruding lower lip.
OFFSETS = {
    126: (-.012, .024, .020), 129: (-.004, .030, .025),
    130: (-.010, 0, .010), 128: (-.007, 0, .007),
    136: (-.007, 0, .007), 194: (0, 0, .015),
    80: (0, 0, .012), 84: (0, 0, .012), 81: (0, 0, .008),
}


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def key(point):
    return tuple(round(abs(v) if i == 0 else v, 4) for i, v in enumerate(point))


def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def subtract(a, b):
    return [x-y for x, y in zip(a, b)]


def main():
    config = read(WORK / "runtime_config.json")
    assert config["active_helmet_revision"] == "helmet_refinement_v4"
    source_path, target_path = WORK / "build/source.json", WORK / "build/target.json"
    original = read(source_path)["parts"][HEAD]["surfaces"][0]
    target = read(target_path)
    row = target["parts"][HEAD]["surfaces"][0]
    assert len(row["positions"]) == 334 and len(row["indices"]) == 164*3
    before = copy.deepcopy(row["positions"])
    offsets = {key(original["positions"][i]): delta for i, delta in OFFSETS.items()}
    for i, point in enumerate(original["positions"]):
        if key(point) not in offsets:
            continue
        dx, dy, dz = offsets[key(point)]
        row["positions"][i] = [before[i][0] + dx*(1 if point[0] > 0 else -1)
                               if abs(point[0]) > 1e-5 else before[i][0],
                               before[i][1]+dy, before[i][2]+dz]
    for added in row["added_vertices"]:
        i = added["index"]
        a, b = added["parents"]
        row["positions"][i] = [before[i][j] + ((row["positions"][a][j]-before[a][j])
                                              + (row["positions"][b][j]-before[b][j]))/2
                               for j in range(3)]
        added["bend"] = [row["positions"][i][j] - (row["positions"][a][j]+row["positions"][b][j])/2
                         for j in range(3)]
    cosines = []
    for triangle in range(len(row["indices"])//3):
        ids = row["indices"][triangle*3:triangle*3+3]
        start = row["triangle_parents"][triangle]*3
        old = [original["positions"][i] for i in original["indices"][start:start+3]]
        new = [row["positions"][i] for i in ids]
        a = cross(subtract(old[1], old[0]), subtract(old[2], old[0]))
        b = cross(subtract(new[1], new[0]), subtract(new[2], new[0]))
        length = lambda v: math.sqrt(sum(x*x for x in v))
        assert length(b) > 1e-10, "Collapsed candidate face"
        cosines.append(sum(x*y for x, y in zip(a, b))/(length(a)*length(b)))
    normalizer = min(max(p[j] for p in original["positions"])-min(p[j] for p in original["positions"])
                     for j in range(3))
    maximum = max(math.dist(a, b) for a, b in zip(row["positions"], row["baseline_positions"]))/normalizer
    assert min(cosines) >= 0 and maximum <= config["original_total_geometry_limit"]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "candidate_target.json").write_text(json.dumps(target, indent=2)+"\n", encoding="utf-8")
    records = {
        "scope": "Geometry-only review candidate; active scene not changed",
        "source": "Current v4 target and original rest-space source",
        "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        "active_target_sha256": hashlib.sha256(target_path.read_bytes()).hexdigest(),
        "original_representative_vertex_deltas": OFFSETS,
        "max_original_displacement_fraction": maximum,
        "minimum_parent_normal_cosine": min(cosines), "triangles": 164,
        "uv_coordinates": 334, "uv_charts": 3, "texture_changes": False,
    }
    (OUT / "adjustments.json").write_text(json.dumps(records, indent=2)+"\n", encoding="utf-8")
    if "--master" in sys.argv:
        import bpy
        assert Path(bpy.data.filepath).resolve() == (WORK / "build/titan_master.blend").resolve()
        head = bpy.data.objects[HEAD]
        assert len(head.data.vertices) == len(row["positions"])
        for vertex, (x, y, z) in zip(head.data.vertices, row["positions"]):
            vertex.co = (-x, z, y)
        head.data.update()
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "candidate_master.blend"))
    print("TITAN_ALIGNMENT_TARGET_PASS unchanged UV/topology/weights; separate review target")


if __name__ == "__main__":
    main()
