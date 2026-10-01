"""Measure raw legacy meshes and compose unpainted reference/review sheets.

Pillow is used only to lay out existing captures/crops, never to repaint assets.
Run capture_legacy_style.gd first. No Blender or generated trial is a baseline.
"""
from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/art/armor_runtime_v1/style_base_v1"
CAPTURES = ROOT / "test_output/armor_style_base"
IDS = (0, 2, 3, 4, 7, 9, 10, 11, 12)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(points: list | set) -> dict:
    axes = [[min(v[i] for v in points), max(v[i] for v in points)] for i in range(3)]
    return {"min_max_xyz": axes, "width_height_depth": [b - a for a, b in axes]}


def geometry(arrays_list: list[dict]) -> tuple[list, list]:
    vertices, faces = [], []
    for arrays in arrays_list:
        offset = len(vertices)
        # The exporter staging convention is (x, z, -y); measurements use Y-up.
        vertices.extend(tuple(round(c, 5) for c in (v[0], -v[2], v[1])) for v in arrays["0"])
        indices = arrays.get("12", list(range(len(arrays["0"]))))
        assert len(indices) % 3 == 0
        faces.extend(tuple(offset + i for i in indices[k:k + 3]) for k in range(0, len(indices), 3))
    return vertices, faces


def components(vertices: list, faces: list) -> list[dict]:
    # Weld positions across UV/normal seams solely for analysis; source untouched.
    parent = {v: v for v in set(vertices)}

    def root(v: tuple) -> tuple:
        while parent[v] != v:
            parent[v] = parent[parent[v]]
            v = parent[v]
        return v

    for face in faces:
        for i in face[1:]:
            parent[root(vertices[i])] = root(vertices[face[0]])
    groups = defaultdict(set)
    counts = Counter()
    for vertex in vertices:
        groups[root(vertex)].add(vertex)
    for face in faces:
        counts[root(vertices[face[0]])] += 1
    return [{"triangles": counts[r], "position_count": len(points), **bounds(points)}
            for r, points in sorted(groups.items(), key=lambda pair: -counts[pair[0]])]


def sheet(ids: tuple, filename: str, columns: int, views: tuple = ("quarter",)) -> None:
    tiles = [(id, view) for id in ids for view in views]
    rows = (len(tiles) + columns - 1) // columns
    image = Image.new("RGB", (columns * 400, rows * 480), "#0c1013")
    draw = ImageDraw.Draw(image)
    for i, (id, view) in enumerate(tiles):
        x, y = (i % columns) * 400, (i // columns) * 480
        with Image.open(CAPTURES / f"original_{id:02d}_{view}.png") as source:
            assert source.size == (640, 720)
            tile = source.convert("RGB").resize((400, 450), Image.Resampling.LANCZOS)
            image.paste(tile, (x, y + 30))
        draw.text((x + 14, y + 8), f"ORIGINAL {id:02d}  {NAMES[id]} / {view}", fill="#dce2e9")
    image.save(OUT / "references" / filename)


def main() -> None:
    (OUT / "references").mkdir(parents=True, exist_ok=True)
    source_path = ROOT / "test_output/armor_facets/sources.json"
    source = json.loads(source_path.read_text())
    entries = {e["id"]: e for e in source["entries"]}
    report = {
        "date": "2026-10-01",
        "source": "assets/models/player/animated/player.gltf",
        "source_sha256": digest(ROOT / "assets/models/player/animated/player.gltf"),
        "staging_sha256": digest(source_path),
        "measurement": "raw_surfaces only; bind-space Y-up; weld round(position, 5); largest connected head component is a proxy for main shell, not an anatomical head count",
        "selected_originals": [],
    }
    for id in IDS:
        entry = entries[id]
        all_vertices, counts, textures = [], {}, []
        for part in entry["parts"]:
            raw = part["raw_surfaces"]
            vertices, faces = geometry([s["arrays"] for s in raw])
            all_vertices.extend(vertices)
            counts[part["name"]] = len(faces)
            for surface in raw:
                path = ROOT / surface["texture"].removeprefix("res://")
                with Image.open(path) as image:
                    size = list(image.size)
                textures.append({"part": part["name"], "path": str(path.relative_to(ROOT)),
                                 "sha256": digest(path), "imported_pixels": size,
                                 "legacy_source_pixels_inferred_from_export_scale_2": [n // 2 for n in size],
                                 "tint": surface["parameters"].get("albedo_color")})
        head_vertices, head_faces = geometry([s["arrays"] for s in entry["parts"][0]["raw_surfaces"]])
        head_components = components(head_vertices, head_faces)
        height = bounds(all_vertices)["width_height_depth"][1]
        main_height = head_components[0]["width_height_depth"][1]
        report["selected_originals"].append({
            "id": id, "name": entry["name"], "part_triangles": counts,
            "triangles": sum(counts.values()), "complete_armor": bounds(all_vertices),
            "head_with_attachments": bounds(head_vertices), "head_components": head_components,
            "armor_height_div_main_connected_head_height": height / main_height,
            "textures": textures,
        })
    trial_path = ROOT / "test_output/armor_concept_runtime/repaired_armor_arrays.json"
    trial = json.loads(trial_path.read_text())["ArmorHead_11"]
    vertices, faces = geometry(trial)
    trial_components = components(vertices, faces)
    original = next(e for e in report["selected_originals"] if e["id"] == 11)
    original_width = original["head_components"][0]["width_height_depth"][0]
    trial_width = trial_components[0]["width_height_depth"][0]
    report["rejected_v4_comparison"] = {
        "source": str(trial_path.relative_to(ROOT)), "source_sha256": digest(trial_path),
        "components": trial_components,
        "original_main_shell_width": original_width, "v4_main_shell_width": trial_width,
        "width_increase_percent": 100 * (trial_width / original_width - 1),
        "warning": "Equal outer bounds hid a wider and shorter main shell. Numeric bounds do not certify visual fidelity.",
    }
    (OUT / "mesh_measurements.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    sheet((0, 2, 3, 9, 10, 11), "original_style_sheet.png", 3)
    sheet((11,), "original_cygni_views.png", 3, ("front", "quarter", "side"))
    concept = ROOT / "docs/art/original_armors_v1/images/c12_concept.png"
    with Image.open(concept) as image:
        image.crop((320, 0, 840, 470)).save(OUT / "references/approved_helmet_motifs_only.png")
    shutil.copy2(CAPTURES / "original_11_front.png", OUT / "references/original_cygni_front.png")
    shutil.copy2(CAPTURES / "original_11_side.png", OUT / "references/original_cygni_side.png")
    capture = json.loads((CAPTURES / "capture.json").read_text())
    capture["script_sha256"] = digest(Path(__file__).with_name("capture_legacy_style.gd"))
    capture["analysis_script_sha256"] = digest(Path(__file__))
    (OUT / "capture_record.json").write_text(json.dumps(capture, indent=2, ensure_ascii=False) + "\n")
    print(f"LEGACY_STYLE_ANALYSIS_PASS originals={len(IDS)} cygni_main_shell_width_drift={report['rejected_v4_comparison']['width_increase_percent']:.2f}%")


NAMES = {0: "Viper", 2: "Tank", 3: "Hydra", 4: "Strike", 7: "Atom", 9: "Draco", 10: "Phoenix", 11: "Cygni", 12: "Andromedae"}

if __name__ == "__main__":
    main()
