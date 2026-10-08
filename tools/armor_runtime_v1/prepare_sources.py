"""Freeze Atom/Pegasus engine-exported true source before any art generation.

Run inspect_sources.gd -- --armor=atom first. This command copies source
bytes and writes technical SVG wire guides; it never edits a raster image.
An existing frozen snapshot is an error, not a new baseline to overwrite.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[2]
ARMORS = {"atom": (7, "C-08", "Atom"), "pegasus": (8, "C-09", "Pegasus")}
LABELS = {"head", "body", "shoulder", "hand", "foot"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def texture_label(texture):
    name = Path(texture).name.lower().removeprefix("09_")
    prefix = name.split("_", 1)[0]
    label = {"head": "head", "body": "body", "jian": "shoulder", "hand": "hand", "foot": "foot"}.get(prefix)
    if label is None:
        raise ValueError("Unrecognized true-original texture slot: " + texture)
    return label


def chart_count(surface):
    adjacency = {}
    keys = [tuple(round(value, 6) for value in point) for point in surface["uv"]]
    for offset in range(0, len(surface["indices"]), 3):
        triangle = [keys[index] for index in surface["indices"][offset:offset + 3]]
        for key in triangle:
            adjacency.setdefault(key, set()).update(triangle)
    unseen, count = set(adjacency), 0
    while unseen:
        count += 1
        stack = [unseen.pop()]
        while stack:
            for neighbor in adjacency[stack.pop()]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    stack.append(neighbor)
    return count


def uv_svg(surface):
    polygons = []
    for offset in range(0, len(surface["indices"]), 3):
        points = [surface["uv"][index] for index in surface["indices"][offset:offset + 3]]
        polygons.append('<polygon points="' + " ".join(f"{u*1024:.6f},{v*1024:.6f}" for u, v in points)
                        + '" fill="none" stroke="#9ad9e8" stroke-width="1"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            '<rect width="1024" height="1024" fill="#17222d"/>' + "".join(polygons) + "</svg>\n")


def semantics(surface):
    """Technical position bins; these are aids, never an artistic acceptance."""
    points = surface["positions"]
    low = [min(p[axis] for p in points) for axis in range(3)]
    high = [max(p[axis] for p in points) for axis in range(3)]
    rows, polygons = [], []
    colors = {"front_lower": "#b7e4c7", "front_upper": "#ffdc92", "rear": "#809bce", "crown": "#e7b2d9", "side": "#a4dee8"}
    for offset in range(0, len(surface["indices"]), 3):
        indices = surface["indices"][offset:offset + 3]
        center = [sum(points[i][axis] for i in indices) / 3 for axis in range(3)]
        y = (center[1] - low[1]) / (high[1] - low[1])
        z = (center[2] - low[2]) / (high[2] - low[2])
        region = "crown" if y > .82 else ("front_lower" if y < .48 else "front_upper") if z < .34 else "rear" if z > .68 else "side"
        rows.append({"triangle": offset // 3, "region": region, "indices": indices, "rest_centroid": center})
        uv = [surface["uv"][i] for i in indices]
        polygons.append('<polygon points="' + " ".join(f"{u*1024:.6f},{v*1024:.6f}" for u, v in uv)
                        + f'" fill="{colors[region]}" stroke="#253848" stroke-width="1"/>')
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
           '<rect width="1024" height="1024" fill="#17222d"/>' + "".join(polygons) + "</svg>\n")
    return svg, {"status": "TECHNICAL_POSITION_BINS_REQUIRES_3D_VIEW_REVIEW", "front_axis": "-Z", "colors": colors,
                 "warning": "Rest-position heuristics only. Mirrored/overlapping UVs may cover more than one region; confirm on actual original model before painting face details.",
                 "triangles": rows}


def prepare(slug):
    armor_id, design_id, name = ARMORS[slug]
    work = ROOT / f"docs/art/{slug}_runtime_v1"
    source_path = work / "build/source.json"
    frozen = work / "revisions/original_source_v1"
    if frozen.exists():
        raise FileExistsError("Original snapshot already exists; refuse to rebaseline: " + str(frozen))
    source = read(source_path)
    original = ROOT / "assets/models/player/animated/player.gltf"
    assert source["original_scene"] == "res://assets/models/player/animated/player.gltf"
    assert source["original_scene_sha256"] == digest(original), "Engine export is stale"
    gltf = read(original)
    names = [f"Armor{part}_{armor_id:02d}" for part in ["Head", "Body", "Hand", "Foot"]]
    assert set(source["parts"]) == set(names) and len(source["bones"]) == 28
    nodes = {node["name"]: index for index, node in enumerate(gltf["nodes"]) if node.get("name") in names}
    assert set(nodes) == set(names)
    assert all(gltf["nodes"][number]["extras"]["armor_id"] == armor_id for number in nodes.values())
    parts, slots = {}, {}
    for node, part in source["parts"].items():
        parts[node] = []
        for sid, surface in enumerate(part["surfaces"]):
            label = texture_label(surface["texture"])
            assert label not in slots, "Each original atlas must have one slot"
            parts[node].append(label)
            texture = ROOT / surface["texture"].removeprefix("res://")
            assert texture.resolve().is_relative_to(original.parent.resolve())
            slots[label] = {"node": node, "surface": sid, "original_texture": texture.relative_to(ROOT).as_posix(),
                            "snapshot": (frozen / f"atlases/{label}.png").relative_to(ROOT).as_posix(),
                            "original_sha256": digest(texture), "coordinates": len(surface["uv"]),
                            "charts": chart_count(surface), "triangles": len(surface["indices"]) // 3}
    assert set(slots) == LABELS
    config = {"runtime_id": armor_id, "design_id": design_id, "name": name, "slug": slug,
              "work": work.relative_to(ROOT).as_posix(), "asset": f"assets/armors/{slug}_v1",
              "source": source_path.relative_to(ROOT).as_posix(),
              "original_source_snapshot": (frozen / "snapshot.json").relative_to(ROOT).as_posix(),
              "source_node_index": (frozen / "source_node_index.json").relative_to(ROOT).as_posix(),
              "original_node_ids": nodes, "parts": parts, "texture_slots": slots,
              "original_triangles": sum(row["triangles"] for row in slots.values()),
              "original_bones": 28, "original_surface_count": 5,
              "original_uv_coordinate_count": sum(row["coordinates"] for row in slots.values()),
              "original_total_geometry_limit": .20, "original_total_uv_changed_fraction_per_surface_limit": .20,
              "shape_file": f"tools/armor_runtime_v1/shapes/{slug}.py", "preserve_all_geometry": True,
              "accepted_art_status": "not_generated_not_integrated",
              "geometry_authoring": "Texture-only first integration: all original position, UV, index, bone and weight arrays must remain exact.",
              "art_residuals": ["尚未生成或驗收；實際貼圖和頭盔設計須在遊戲模型及動作中核對。"]}
    frozen.mkdir(parents=True)
    for directory in ["build", "guides", "generated", "prompts", "review", "input_snapshots"]:
        (work / directory).mkdir(exist_ok=True)
    files = {}

    def copy_record(path, relative):
        destination = frozen / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
        files[relative] = {"source": path.relative_to(ROOT).as_posix(), "sha256": digest(destination), "bytes": destination.stat().st_size}

    copy_record(source_path, "source.json")
    copy_record(ROOT / "tools/armor_runtime_v1/inspect_sources.gd", "scripts/inspect_sources.gd")
    for label, slot in slots.items():
        copy_record(ROOT / slot["original_texture"], f"atlases/{label}.png")
        surface = source["parts"][slot["node"]]["surfaces"][slot["surface"]]
        guide = work / f"guides/{label}_uv.svg"
        guide.write_text(uv_svg(surface), encoding="utf-8")
        copy_record(guide, f"guides/{label}_uv.svg")
        if label == "head":
            semantic_svg, semantic_data = semantics(surface)
            (work / "guides/head_semantics.svg").write_text(semantic_svg, encoding="utf-8")
            write(work / "guides/head_semantics.json", semantic_data)
    write(work / "runtime_config.json", config)
    copy_record(work / "runtime_config.json", "runtime_config.json")
    snapshot = {"status": "FROZEN_TRUE_ORIGINAL_SOURCE", "created_at_utc": datetime.now(timezone.utc).isoformat(),
                "runtime_id": armor_id, "used_nodes": names, "original_scene": source["original_scene"],
                "original_scene_sha256": digest(original), "files": files, "texture_slots": slots}
    assert len(files) == 13
    write(frozen / "snapshot.json", snapshot)
    buffers = []
    for row in gltf["buffers"]:
        path = original.parent / row["uri"]
        assert path.resolve().is_relative_to(original.parent.resolve()) and path.stat().st_size == row["byteLength"]
        buffers.append({**row, "sha256": digest(path)})
    index = {"status": "FROZEN_ORIGINAL_NODE_INDEX_SUPPLEMENT", "runtime_id": armor_id,
             "original_source_snapshot_sha256": digest(frozen / "snapshot.json"),
             "original_gltf_sha256": digest(original), "node_ids": nodes,
             "gltf_node_records": {node: gltf["nodes"][number] for node, number in nodes.items()}, "buffers": buffers}
    write(frozen / "source_node_index.json", index)
    config["original_source_snapshot_sha256"] = digest(frozen / "snapshot.json")
    config["source_node_index_sha256"] = digest(frozen / "source_node_index.json")
    write(work / "runtime_config.json", config)
    print(f"{slug.upper()}_SOURCE_PREPARED frozen=13 textures=5 triangles={config['original_triangles']} uv={config['original_uv_coordinate_count']} runtime_art=NOT_RUN")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--armor", choices=ARMORS, required=True)
    prepare(parser.parse_args().armor)


if __name__ == "__main__":
    main()
