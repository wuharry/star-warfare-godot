"""Inventory all ORIGINAL armor meshes/textures; compose references without repainting.

Run capture_original_corpus.gd first. CoM source files are byte-checked against ZIPs.
No enhanced texture or replacement mesh is a style source. Pillow only lays out images.
"""
from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/art/legacy_armor_base_v2"
CAP = ROOT / "test_output/armor_original_corpus"
NAMES = ["Viper", "Fortune", "Tank", "Hydra", "Strike", "Titan", "Thunder", "Atom", "Pegasus", "Draco", "Phoenix", "Cygni", "Andromedae", "Perseus", "Chaos", "DEC.24", "Knight", "R.O.M.E", "Black Hole", "X-Field", "Wrath", "Assault Armor", "Combat Suit", "Drillmaster", "Heavy Battlesuit", "Mark-6 117R", "Recon Suit", "Sanguine Chaos", "Training Suit"]
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 19)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def box(points: list) -> list[float]:
    return [round(max(p[i] for p in points) - min(p[i] for p in points), 5) for i in range(3)]


def components(points: list, faces: list) -> list[dict]:
    points = [tuple(round(n, 5) for n in p) for p in points]
    parent = {p: p for p in points}

    def root(v):
        while parent[v] != v:
            parent[v] = parent[parent[v]]
            v = parent[v]
        return v

    for a, b, c in faces:
        parent[root(points[b])] = root(points[a])
        parent[root(points[c])] = root(points[a])
    groups = defaultdict(list)
    tris = Counter()
    for p in points:
        groups[root(p)].append(p)
    for a, _, _ in faces:
        tris[root(points[a])] += 1
    return [{"triangles": tris[k], "width_height_depth": box(v)} for k, v in sorted(groups.items(), key=lambda kv: -tris[kv[0]])]


def texture(path: Path) -> dict:
    with Image.open(path) as src:
        image = src.convert("RGBA")
        alpha = image.getchannel("A")
        size = list(image.size)
        extrema = list(alpha.getextrema())
        nonopaque = sum(alpha.histogram()[:255]) / (image.width * image.height)
    return {"path": str(path.relative_to(ROOT)), "sha256": sha(path), "pixels": size, "alpha_range": extrema, "nonopaque_fraction": round(nonopaque, 6)}


def read_sw() -> list[dict]:
    path = ROOT / "assets/models/player/animated/player.gltf"
    data = json.loads(path.read_text())
    buffers = [(path.parent / b["uri"]).read_bytes() for b in data["buffers"]]

    def accessor(index):
        a = data["accessors"][index]
        b = data["bufferViews"][a["bufferView"]]
        code = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[a["componentType"]]
        length = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
        fmt = "<" + code * length
        start = a.get("byteOffset", 0) + b.get("byteOffset", 0)
        stride = b.get("byteStride", struct.calcsize(fmt))
        return [struct.unpack_from(fmt, buffers[b["buffer"]], start + i * stride) for i in range(a["count"])]

    entries = []
    for id in range(21):
        parts, textures, all_points, head = [], [], [], None
        for prefix in ("ArmorHead", "ArmorBody", "ArmorHand", "ArmorFoot"):
            mesh = next(m for m in data["meshes"] if m["name"] == f"{prefix}_{id:02}")
            points, faces = [], []
            for primitive in mesh["primitives"]:
                assert primitive.get("mode", 4) == 4
                offset = len(points)
                # player.gltf root rotates its mesh bind space +90 degrees about X.
                points.extend((v[0], -v[2], v[1]) for v in accessor(primitive["attributes"]["POSITION"]))
                indices = [i[0] for i in accessor(primitive["indices"])]
                assert len(indices) % 3 == 0
                faces.extend(tuple(offset + n for n in indices[i:i + 3]) for i in range(0, len(indices), 3))
                mat = data["materials"][primitive["material"]]
                pbr = mat["pbrMetallicRoughness"]
                image = data["textures"][pbr["baseColorTexture"]["index"]]["source"]
                t = texture(path.parent / data["images"][image]["uri"])
                t.update(part=prefix, material=mat["name"], tint=pbr.get("baseColorFactor", [1, 1, 1, 1]), native_pixels=[n // 2 for n in t["pixels"]], native_basis="export.py TEXTURE_EXPORT_SCALE=2; inferred from exported dimensions")
                textures.append(t)
            parts.append({"name": prefix, "triangles": len(faces), "width_height_depth": box(points)})
            all_points.extend(points)
            if prefix == "ArmorHead":
                head = components(points, faces)
        entries.append({"id": id, "name": NAMES[id], "family": "Star Warfare", "source": str(path.relative_to(ROOT)), "source_sha256": sha(path), "triangles": sum(p["triangles"] for p in parts), "parts": parts, "width_height_depth": box(all_points), "head_components": head, "height_div_main_head_component": round(box(all_points)[1] / head[0]["width_height_depth"][1], 3), "textures": textures})
    return entries


def read_com() -> list[dict]:
    entries = []
    for id in range(21, 29):
        path = ROOT / "assets/callOfMini" / f"Mobile - Call of Mini_ Infinity - Armors - {NAMES[id]}.zip"
        with zipfile.ZipFile(path) as archive:
            dae = next(n for n in archive.namelist() if n.endswith(".dae"))
            source = path.parent / "enhanced" / dae
            assert archive.read(dae) == source.read_bytes(), source
            tree = ET.fromstring(archive.read(dae))
            ns = {"c": tree.tag.split("}")[0][1:]}
            parts = [{"name": g.get("name"), "triangles": sum(int(t.get("count")) for t in g.findall(".//c:triangles", ns))} for g in tree.findall(".//c:geometry", ns)]
            textures = []
            for name in ("helmet.png", "equip.png", "armor.png"):
                member = f"{NAMES[id]}/{name}"
                source_png = path.parent / "enhanced" / NAMES[id] / "source" / name
                assert archive.read(member) == source_png.read_bytes(), source_png
                t = texture(source_png)
                t.update(zip_member=member, zip_bytes_equal=True, native_pixels=t["pixels"])
                textures.append(t)
        entries.append({"id": id, "name": NAMES[id], "family": "Call of Mini", "source": str(path.relative_to(ROOT)), "source_sha256": sha(path), "dae": str(source.relative_to(ROOT)), "dae_sha256": sha(source), "dae_zip_bytes_equal": True, "triangles": sum(p["triangles"] for p in parts), "parts": parts, "textures": textures, "proportion_note": "Raw DAE captured separately. Not the retargeted/refined gameplay scene; no cross-game world-unit measurement asserted."})
    return entries


def fit(path: Path, size: tuple[int, int]) -> Image.Image:
    with Image.open(path) as source:
        image = source.convert("RGBA")
        image.thumbnail(size, Image.Resampling.LANCZOS)
        return image.copy()


def sheets(entries: list[dict]) -> None:
    refs = OUT / "references"
    refs.mkdir(parents=True, exist_ok=True)
    # Original atlas pixels, no tint, correction, smoothing or generated detail added.
    for page, start in enumerate(range(0, 29, 7), 1):
        group = entries[start:start + 7]
        canvas = Image.new("RGB", (1260, len(group) * 260 + 45), "#192024")
        d = ImageDraw.Draw(canvas)
        d.text((12, 10), "ORIGINAL CORPUS / full body + ALL atlases / diffuse inspection", font=FONT, fill="white")
        for row, entry in enumerate(group):
            top = 45 + row * 260
            d.text((12, top), f'{entry["id"]:02} {entry["name"]} | {entry["triangles"]} tris', font=FONT, fill="#eee8d7")
            body = fit(CAP / f'original_{entry["id"]:02}_quarter.png', (200, 225))
            canvas.paste(body, (5, top + 30), body)
            unique_textures = list({t["path"]: t for t in entry["textures"]}.values())
            for col, t in enumerate(unique_textures):
                tile = fit(ROOT / t["path"], (195, 195))
                x = 220 + col * 205
                canvas.paste(tile, (x, top + 30), tile)
                label = re.sub(r"_[0-9a-f]{12}_2x$", "", Path(t["path"]).stem)
                d.text((x, top + 228), label + " " + "x".join(map(str, t["native_pixels"])), font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15), fill="#aeb8bf")
        canvas.save(refs / f"corpus_{page:02}.jpg", quality=94)
    for key, ids in [("sw_family", range(21)), ("com_family", range(21, 29))]:
        columns = 7 if key == "sw_family" else 4
        canvas = Image.new("RGB", (columns * 240, ((len(ids) + columns - 1) // columns) * 310), "#0c1013")
        d = ImageDraw.Draw(canvas)
        for i, id in enumerate(ids):
            x, y = i % columns * 240, i // columns * 310
            tile = fit(CAP / f"original_{id:02}_quarter.png", (240, 270))
            canvas.paste(tile, (x, y + 30), tile)
            d.text((x + 5, y + 8), f"{id:02} {NAMES[id]}", font=FONT, fill="#e5ebec")
        canvas.save(refs / f"{key}.png")
    for id in (0, 3, 7, 11, 25):
        canvas = Image.new("RGB", (1280, 400), "#0c1013")
        d = ImageDraw.Draw(canvas)
        for i, view in enumerate(("front", "quarter", "side", "rear")):
            tile = fit(CAP / f"original_{id:02}_{view}.png", (320, 360))
            canvas.paste(tile, (i * 320, 35), tile)
            d.text((i * 320 + 8, 8), f"{NAMES[id]} / {view}", font=FONT, fill="white")
        canvas.save(refs / f"original_{id:02}_views.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    entries = read_sw() + read_com()
    assert len(entries) == 29 and sum(len(e["textures"]) for e in entries) == 130
    assert len({t["path"] for e in entries for t in e["textures"]}) == 129
    gallery_path = ROOT / "docs/art/original_armors_v1/index.html"
    catalog = json.loads(re.search(r'<script[^>]*id="catalog"[^>]*>(.*?)</script>', gallery_path.read_text(), re.S).group(1))
    mappings = []
    for item in catalog:
        if item["kind"] != "armor":
            continue
        candidate = item.get("user_review", {}).get("preferred_art") or item["images"]["concept"]
        if isinstance(candidate, dict):
            candidate = candidate["path"]
        assert isinstance(candidate, str), candidate
        path = (gallery_path.parent / candidate).resolve()
        assert path.is_file(), path
        mappings.append({"id": item["legacy_id"], "name": item["legacy_name"], "concept": str(path.relative_to(ROOT)), "sha256": sha(path), "status": item["status"], "design_rules": item.get("fusion", {}), "user_review": item.get("user_review", {})})
    capture = json.loads((CAP / "capture.json").read_text())
    report = {"date": "2026-10-02", "scope": "All original armor: 21 SW + 8 CoM; weapons, enemies, backpacks are separate families", "source_binary_sha256": sha(ROOT / "assets/models/player/animated/player.bin"), "analysis_script_sha256": sha(Path(__file__)), "capture_script_sha256": sha(Path(__file__).with_name("capture_original_corpus.gd")), "measurement": "SW bind-space transformed by root +90deg X; largest welded head component is NOT anatomical head count; dimensions include attached fins if connected", "texture_warning": "atlas padding and original material tint affect perceived color; no universal average-luminance target imposed", "capture": capture, "entries": entries, "concepts": mappings}
    (OUT / "inventory.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    sheets(entries)
    print("ORIGINAL_CORPUS_ANALYSIS_PASS sets=29 material_texture_slots=130 texture_files=129 captures=116")
    for e in entries:
        print(e["id"], e["name"], e["triangles"], e.get("height_div_main_head_component"), [(t["native_pixels"], t["alpha_range"]) for t in e["textures"]])


if __name__ == "__main__":
    main()
