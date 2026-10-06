"""Read-only checks for the current Titan helmet refinement and preserved parts.

python3 tools/armor_runtime_v1/validate_titan_helmet.py
Blender -b <titan_master.blend> --python-exit-code 1 --python <this file>
Historical first-integration hashes remain historical; no baseline is rewritten.
"""
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/titan_runtime_v1"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


REVISIONS = {"helmet_refinement_v3": 3, "helmet_refinement_v4": 4}
LABELS = {"head", "body", "shoulder", "hand", "foot"}
SOURCE_INDEX_SHA = "1d2883a7123e3297245ee9845569335981d82f26842b661ca98393fd6a3ff0cc"
FIRST_INDEX_SHA = "9a04729f9df7c23134eb377bf22f9e0d9580e824dda7949992d65a400d860009"
BEFORE_INDEX_SHA = {
    3: "2c1ada36a339d4b2e10d9795dd572d54692571fccc6be9e2ba19204fdeebd66e",
    4: "0328e353a7843e0e5f85e8bd5c9b54b274860b2fc7668b62988882a7170562c3",
}
CAPTURE_NAMES = {
    *(f"{version}_{kind}_{view}.png" for version in ("original", "new")
      for kind in ("diffuse", "painted", "clay", "head") for view in ("front", "quarter", "side", "rear")),
    *(f"{version}_{clip}.png" for version in ("original", "new") for clip in ("idle_rifle", "run_rifle")),
    *(f"{version}_reload_{i:02d}.png" for version in ("original", "new") for i in range(9)),
    *(f"{version}_level_{level}_{view}.png" for version in ("original", "new")
      for level in ("01", "08") for view in ("front", "gameplay")),
    "family_original_01_front.png", "family_original_06_front.png",
}
TEXT_SUFFIXES = {".json", ".py", ".gd", ".md", ".txt", ".html", ".log", ".svg", ".gltf"}
# Only known historical text identities may use reversible EOL reconstruction.
# Active native prompts, PNGs, GLBs, SCNs and Blender files always use raw bytes.
HISTORICAL_TEXT_SHA = {
    WORK / "revisions/before_helmet_refinement_v3/snapshot.json": {BEFORE_INDEX_SHA[3]},
    WORK / "revisions/original_source_v1/snapshot.json": {SOURCE_INDEX_SHA},
    WORK / "revisions/first_integration_v1_before_head_hand_refinement/snapshot.json": {FIRST_INDEX_SHA},
    WORK / "revisions/original_source_v1/source_node_index.json": {"ec6be5fe46fc753ed75c850e95d088f5ed6e961af0170995af95cb2b00a116da"},
    WORK / "generation_inputs.json": {"25a0078673105bd26bc338985a8b45e0f706552836781f9218b8e56d80c966be"},
    WORK / "revisions/helmet_refinement_v3/generation_record.json": {"bcaf97951aa0116171b96dc7be21b03300fccca2b140d07cad427a528f6dea56"},
    WORK / "revisions/helmet_refinement_v3/head_diffuse_prompt_attempt_04.txt": {"0a3f6b96a47490a35b6a1354888d1553acf2307ef6a5046f8cf6ea3956d40579"},
}


def matched_bytes(path, expected, historical=False):
    """Return the exact hashed representation, never a blanket normalized hash."""
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() == expected:
        return raw
    allowed = HISTORICAL_TEXT_SHA.get(path.resolve(), set())
    assert historical and expected in allowed and path.suffix.lower() in TEXT_SUFFIXES, f"Raw SHA mismatch: {path}"
    raw.decode("utf-8-sig")  # Binary data cannot enter this historical text exception.
    lf = raw.replace(b"\r\n", b"\n")
    for variant in (lf, lf.replace(b"\n", b"\r\n")):
        if hashlib.sha256(variant).hexdigest() == expected:
            return variant
    raise AssertionError(f"Historical text differs beyond exact LF/CRLF: {path}")


def hash_matches(path, expected, historical=False):
    matched_bytes(path, expected, historical)
    return True


def _authorize_text(path, expected):
    if path.suffix.lower() in TEXT_SUFFIXES:
        HISTORICAL_TEXT_SHA.setdefault(path.resolve(), set()).add(expected)


def _snapshot_records(path, expected_sha, expected_paths, listed=False):
    index_payload = matched_bytes(path, expected_sha, historical=True)
    index_lf = index_payload.replace(b"\r\n", b"\n")
    for variant in (index_lf, index_lf.replace(b"\n", b"\r\n")):
        _authorize_text(path, hashlib.sha256(variant).hexdigest())
    data = read(path)
    if listed:
        rows = data["files"]
        assert len(rows) == len(expected_paths) and {r["path"] for r in rows} == expected_paths
        pairs = [(ROOT / r["snapshot"], r) for r in rows]
    else:
        assert len(data["files"]) == len(expected_paths) and set(data["files"]) == expected_paths
        pairs = [(path.parent / name, row) for name, row in data["files"].items()]
    for file, row in pairs:
        assert file.resolve().is_relative_to(path.parent.resolve()), f"Escaping snapshot path: {file}"
        _authorize_text(file, row["sha256"])
        if listed:
            _authorize_text(ROOT / row["path"], row["sha256"])
        payload = matched_bytes(file, row["sha256"], historical=True)
        assert len(payload) == row["bytes"], f"Historical byte count mismatch: {file}"
        if file.suffix.lower() in TEXT_SUFFIXES:
            # Derive only the two exact EOL forms from already pinned bytes.
            # This also recognizes Mac report hashes of a Windows snapshot.
            lf = payload.replace(b"\r\n", b"\n")
            for variant in (lf, lf.replace(b"\n", b"\r\n")):
                sha = hashlib.sha256(variant).hexdigest()
                _authorize_text(file, sha)
                if listed:
                    _authorize_text(ROOT / row["path"], sha)
    return data


def verify_baselines():
    original = WORK / "revisions/original_source_v1/snapshot.json"
    original_paths = {"source.json", "runtime_config.json", "scripts/inspect_sources.gd",
                      *(f"atlases/{label}.png" for label in LABELS), *(f"guides/{label}_uv.svg" for label in LABELS)}
    first_paths = {
        "generation_inputs.json", "manifest.json", "README.md", "index.html", "runtime_config.json",
        *("delivery/" + name for name in ("titan.scn", "titan.glb", "source.json", "target.json", "geometry.json", "titan_master.blend", "glb_bind_aliases.json")),
        *(f"delivery/{label}_diffuse.png" for label in LABELS),
        *("review/" + name for name in ("delivery_validate.json", "failed_scene_reencoding_history.json", "glb_images_test.json", "original_scene_invariants.json", "proportion_test.json", "roundtrip_test.json", "runtime_test.json", "original_integration_angle_capture.log")),
        "review/engine/capture.json", *("review/engine/" + name for name in CAPTURE_NAMES),
    }
    assert len(original_paths) == 13 and len(first_paths) == 90
    _snapshot_records(original, SOURCE_INDEX_SHA, original_paths)
    _snapshot_records(WORK / "revisions/first_integration_v1_before_head_hand_refinement/snapshot.json", FIRST_INDEX_SHA, first_paths)
    index_path = WORK / "revisions/original_source_v1/source_node_index.json"
    matched_bytes(index_path, "ec6be5fe46fc753ed75c850e95d088f5ed6e961af0170995af95cb2b00a116da", historical=True)
    index = read(index_path)
    source = read(original.parent / "source.json")
    original_scene = ROOT / source["original_scene"].removeprefix("res://")
    assert source["original_scene_sha256"] == index["original_gltf_sha256"]
    # Git may check out the live text glTF with LF while this fixed Windows
    # snapshot pins CRLF. Accept only an exact reconstruction of that pinned
    # text; node records and binary mesh buffers remain independently exact.
    _authorize_text(original_scene, source["original_scene_sha256"])
    hash_matches(original_scene, source["original_scene_sha256"], historical=True)
    assert index["node_ids"] == {"ArmorHead_05": 50, "ArmorBody_05": 51, "ArmorHand_05": 52, "ArmorFoot_05": 53}
    assert index["original_source_snapshot_sha256"] == SOURCE_INDEX_SHA and index["runtime_id"] == 5
    gltf = read(original_scene)
    for name, node in index["node_ids"].items():
        assert gltf["nodes"][node] == index["gltf_node_records"][name] and gltf["nodes"][node]["extras"]["armor_id"] == 5
    assert len(index["buffers"]) == len(gltf["buffers"])
    for record, descriptor in zip(index["buffers"], gltf["buffers"]):
        file = original_scene.parent / record["uri"]
        assert file.resolve().is_relative_to(original_scene.parent.resolve())
        assert record["uri"] == descriptor["uri"] and record["byteLength"] == descriptor["byteLength"] == file.stat().st_size
        assert digest(file) == record["sha256"]


def verify_before(version):
    prefix = "docs/art/titan_runtime_v1/"
    if version == 3:
        paths = {*("assets/armors/titan_v1/" + name for name in (
            "titan.scn", "titan.glb", *(f"{label}_diffuse.png" for label in LABELS),
            *(f"titan_{label}_diffuse.png" for label in LABELS))),
            "tools/armor_runtime_v1/shapes/titan.py",
            *(prefix + name for name in ("runtime_config.json", "manifest.json", "README.md", "build/source.json", "build/target.json", "build/geometry.json", "build/titan_master.blend"))}
    else:
        assert version == 4
        paths = {*("assets/armors/titan_v1/" + name for name in (
            "titan.scn", "titan.glb", "titan_head_diffuse.png", *(f"{label}_diffuse.png" for label in LABELS - {"head"}))),
            "tools/armor_runtime_v1/shapes/titan.py",
            *(prefix + name for name in ("runtime_config.json", "manifest.json", "build/source.json", "build/target.json", "build/geometry.json", "build/titan_master.blend")),
            *(prefix + "review/" + name for name in ("runtime_test.json", "roundtrip_test.json", "original_scene_invariants.json", "helmet_v3_glb_test.json", "helmet_v3_master_test.json", "helmet_v3_contract_and_guards_test.json")),
            prefix + "review/helmet_v3_final/capture.json",
            *(prefix + "review/helmet_v3_final/" + name for name in CAPTURE_NAMES)}
    assert len(paths) == (20 if version == 3 else 85)
    return _snapshot_records(WORK / f"revisions/before_helmet_refinement_v{version}/snapshot.json", BEFORE_INDEX_SHA[version], paths, listed=True)


def active_version(config):
    revision = config.get("active_helmet_revision")
    assert revision in REVISIONS, f"Unsupported Titan helmet revision: {revision}"
    version = REVISIONS[revision]
    assert config["slug"] == "titan" and config["work"] == "docs/art/titan_runtime_v1" and config["asset"] == "assets/armors/titan_v1"
    assert config["source"] == "docs/art/titan_runtime_v1/build/source.json"
    assert config["original_source_snapshot"] == "docs/art/titan_runtime_v1/revisions/original_source_v1/snapshot.json"
    original_config = read(WORK / "revisions/original_source_v1/runtime_config.json")
    assert config["parts"] == original_config["parts"] and config["texture_slots"] == original_config["texture_slots"]
    assert config["original_node_ids"] == {"ArmorHead_05": 50, "ArmorBody_05": 51, "ArmorHand_05": 52, "ArmorFoot_05": 53}
    assert config["source_node_index_sha256"] == "ec6be5fe46fc753ed75c850e95d088f5ed6e961af0170995af95cb2b00a116da"
    budget = config["head_refinement"]
    ceiling = .10 if version == 3 else .35
    assert budget["count_growth_ceiling"] == ceiling, "Only the explicitly authorized revision count ceiling is allowed"
    assert type(budget["vertices"]) is int and type(budget["triangles"]) is int
    if version == 3:
        assert (budget["vertices"], budget["triangles"]) == (302, 132)
    else:
        assert 302 <= budget["vertices"] <= math.floor(294 * 1.35)
        assert 132 <= budget["triangles"] <= math.floor(124 * 1.35)
        verify_user_constraints()
    assert config["generation_record"] == f"docs/art/titan_runtime_v1/revisions/{revision}/generation_record.json"
    assert config["before_revision_snapshot"] == f"docs/art/titan_runtime_v1/revisions/before_helmet_refinement_v{version}/snapshot.json"
    assert config["original_total_geometry_limit"] == config["original_total_uv_changed_fraction_per_surface_limit"] == .20
    assert (config["runtime_id"], config["original_triangles"], config["original_bones"], config["original_surface_count"], config["original_uv_coordinate_count"]) == (5, 700, 28, 5, 1607)
    assert config["texture_files"] == {label: ("titan_head_diffuse.png" if label == "head" else f"{label}_diffuse.png") for label in LABELS}
    return version


def _area(coords, ids):
    a, b, c = (coords[i] for i in ids)
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def verify_user_constraints():
    path = WORK / "revisions/helmet_refinement_v4/user_constraints.json"
    data = read(path)
    assert data["source"] == "Direct user instruction in current chat"
    assert data["request"] == ["不對 還是不夠圓", "面罩至少要佔據50%的面積的那種", "要跟草稿圖完全一致 這邊可以改多一點UV 但是不能變成1.6-2倍", "看看能不能達成"]
    assert data["chosen_implementation_budget"] == {
        "original_total_shape_limit": .20, "original_head_count_growth_ceiling": .35,
        "original_uv_changed_fraction_per_material": .20, "original_uv_chart_count": 3,
        "front_projected_visor_minimum_fraction": .50,
    }, "User constraint evidence does not match this explicitly authorized scope"
    assert isinstance(data["interpretation"], str) and data["interpretation"]
    return {"user_constraints": path.relative_to(ROOT).as_posix(), "user_constraints_sha256": digest(path),
            "head_count_growth_ceiling": .35, "front_projected_visor_minimum_fraction": .50}


def verify_head_contract(original, authored, budget):
    """Independent counterpart of refined_head_contract.gd, plus edge ownership."""
    old_count = len(original["positions"])
    count, triangles = len(authored["positions"]), len(authored["indices"]) // 3
    old_triangles = len(original["indices"]) // 3
    assert (old_count, old_triangles, count, triangles) == (294, 124, budget["vertices"], budget["triangles"])
    ceiling = budget["count_growth_ceiling"]
    assert ceiling in (.10, .35), "Unreviewed head count ceiling"
    assert count / old_count <= 1 + ceiling and triangles / old_triangles <= 1 + ceiling
    assert len(authored["indices"]) % 3 == 0 and len(authored["triangle_parents"]) == triangles
    for field in ("positions", "uv", "weights", "bone_indices", "bone_names", "baseline_positions"):
        assert len(authored[field]) == count, f"Head {field} count mismatch"
    assert all(len(p) == 3 and all(math.isfinite(v) for v in p) for p in authored["positions"])
    assert all(len(uv) == 2 and all(math.isfinite(v) for v in uv) for uv in authored["uv"])
    for field in ("weights", "bone_indices", "bone_names"):
        assert authored[field][:old_count] == original[field], f"Original head {field} prefix changed"
    baseline_uv, baseline_positions = list(original["uv"]), list(original["positions"])
    added = authored["added_vertices"]
    assert len(added) == count - old_count
    parent_edges = {}
    for row in added:
        index, (a, b) = row["index"], row["parents"]
        assert index == len(baseline_uv) and isinstance(a, int) and isinstance(b, int) and 0 <= a < old_count and 0 <= b < old_count and a != b
        assert any({a, b} <= set(original["indices"][i:i + 3]) for i in range(0, len(original["indices"]), 3)), "Added vertex parents are not an original edge"
        for field in ("weights", "bone_indices", "bone_names"):
            assert authored[field][index] == original[field][a] == original[field][b], f"Arc vertex changed parent {field}"
        baseline_uv.append([(u + v) / 2 for u, v in zip(original["uv"][a], original["uv"][b])])
        baseline_positions.append([(u + v) / 2 for u, v in zip(original["positions"][a], original["positions"][b])])
        assert authored["uv"][index] == [(u + v) / 2 for u, v in zip(authored["uv"][a], authored["uv"][b])]
        parent_edges[index] = {a, b}
    assert all(math.dist(a, b) < 1e-12 for a, b in zip(baseline_positions, authored["baseline_positions"]))
    covered, seen = [0.0] * old_triangles, set()
    for i, parent in enumerate(authored["triangle_parents"]):
        assert isinstance(parent, int) and 0 <= parent < old_triangles
        ids, original_ids = authored["indices"][i * 3:i * 3 + 3], original["indices"][parent * 3:parent * 3 + 3]
        assert all(isinstance(v, int) and 0 <= v < count for v in ids) and len(set(ids)) == 3
        assert all(({v} if v < old_count else parent_edges[v]) <= set(original_ids) for v in ids), "Subdivision crossed its original face"
        key = (parent, tuple(sorted(ids)))
        assert key not in seen, "Duplicated subdivision face"
        seen.add(key)
        area, before = _area(baseline_uv, ids), _area(baseline_uv, original_ids)
        assert area * before >= -1e-10, "Reversed subdivision"
        assert abs(before) <= 1e-8 or _area(authored["uv"], ids) * before > 0, "Folded authored UV"
        covered[parent] += area
    assert all(abs(covered[i] - _area(baseline_uv, original["indices"][i * 3:i * 3 + 3])) <= 1e-7 for i in range(old_triangles)), "Missing/lost original face coverage"
    changed = sum(math.dist(a, b) > 1e-6 for a, b in zip(original["uv"], authored["uv"][:old_count]))
    assert changed / old_count <= .20
    return {"original_head_vertices": old_count, "head_vertices": count, "original_head_triangles": old_triangles,
            "head_triangles": triangles, "changed_original_head_uv": changed, "original_head_uv_fraction": changed / old_count}


def verify_target(config, source, target, snapshot):
    assert target["id"] == 5 and target["revision"] == config["active_helmet_revision"]
    assert len(source["bones"]) == 28 and len({b["name"] for b in source["bones"]}) == 28
    assert set(target["parts"]) == set(source["parts"]) == set(config["parts"])
    previous = read(next(ROOT / row["snapshot"] for row in snapshot["files"] if row["path"].endswith("build/target.json")))
    result = {}
    for name, part in target["parts"].items():
        assert len(part["surfaces"]) == len(source["parts"][name]["surfaces"])
        for current, original in zip(part["surfaces"], source["parts"][name]["surfaces"]):
            if name == "ArmorHead_05":
                result = verify_head_contract(original, current, config["head_refinement"])
            else:
                assert len(current["positions"]) == len(original["positions"])
                assert all(struct.pack("<3f", *a) == struct.pack("<3f", *b) for a, b in zip(current["positions"], original["positions"])), f"Non-head geometry changed: {name}"
                assert current["uv"] == original["uv"], f"Non-head UV changed: {name}"
                for field in ("indices", "weights", "bone_indices", "bone_names", "normals"):
                    if field in current:
                        assert current[field] == original[field], f"Non-head {field} changed: {name}"
                assert part == previous["parts"][name], f"Non-head target changed from prior revision: {name}"
    if active_version(config) == 4:
        head = target["parts"]["ArmorHead_05"]["surfaces"][0]
        previous_head = previous["parts"]["ArmorHead_05"]["surfaces"][0]
        result["additional_uv_changes"] = sum(math.dist(a, b) > 1e-6 for a, b in zip(previous_head["uv"][:294], head["uv"][:294]))
        result["additional_head_uv_coordinates"] = len(head["uv"]) - len(previous_head["uv"])
        result["additional_head_triangles"] = len(head["indices"]) // 3 - len(previous_head["indices"]) // 3
        result.update(verify_user_constraints())
    else:
        result["additional_uv_changes"] = result["changed_original_head_uv"]
    return result


def _charts(surfaces):
    adjacency = {}
    for surface in surfaces:
        keys = [tuple(round(value, 6) for value in uv) for uv in surface["uv"]]
        for start in range(0, len(surface["indices"]), 3):
            triangle = [keys[index] for index in surface["indices"][start:start + 3]]
            for vertex in triangle:
                adjacency.setdefault(vertex, set()).update(triangle)
    unseen, charts = set(adjacency), 0
    while unseen:
        charts += 1
        pending = [unseen.pop()]
        while pending:
            for neighbor in adjacency[pending.pop()]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    pending.append(neighbor)
    return charts


def _normal(points, ids):
    a, b, c = (points[i] for i in ids)
    u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    return [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]


def verify_geometry(config, source, target):
    """Measure from the true original cage, including midpoint vertices."""
    geometry = read(WORK / "build/geometry.json")
    assert geometry["stage"] == config["active_helmet_revision"] and geometry["user_authorized_original_total_limit"] == .20
    assert set(geometry["parts"]) == set(source["parts"])
    measurements = []
    for name, original in source["parts"].items():
        authored = target["parts"][name]
        old_points = [p for s in original["surfaces"] for p in s["positions"]]
        new_points = [p for s in authored["surfaces"] for p in s["positions"]]
        baseline = [p for old, new in zip(original["surfaces"], authored["surfaces"]) for p in new.get("baseline_positions", old["positions"])]
        assert len(new_points) == len(baseline)
        dimensions = lambda rows: [max(p[i] for p in rows) - min(p[i] for p in rows) for i in range(3)]
        before, after = dimensions(old_points), dimensions(new_points)
        deltas = [abs(a / b - 1) for a, b in zip(after, before)]
        maximum = max(math.dist(a, b) for a, b in zip(baseline, new_points))
        fraction = maximum / min(before)
        assert max(deltas) <= .20 and fraction <= .20, f"{name}: true original-total20% exceeded"
        row = geometry["parts"][name]
        assert abs(row["max_rest_displacement"] - maximum) < 1e-7
        assert abs(row["max_displacement_fraction_of_smallest_dimension"] - fraction) < 1e-7
        assert len(row["dimension_delta_fraction"]) == 3 and all(abs(a - b) < 1e-7 for a, b in zip(row["dimension_delta_fraction"], deltas))
        assert row["triangles"] == sum(len(s.get("indices", old["indices"])) // 3 for old, s in zip(original["surfaces"], authored["surfaces"]))
        assert row["original_uv_coordinate_count"] == sum(len(s["uv"]) for s in original["surfaces"])
        assert row["uv_coordinate_count"] == sum(len(s["uv"]) for s in authored["surfaces"])
        changed = sum(math.dist(a, b) > 1e-6 for old, new in zip(original["surfaces"], authored["surfaces"]) for a, b in zip(old["uv"], new["uv"]))
        assert row["uv_changed_count"] == changed and abs(row["uv_changed_fraction"] - changed / row["original_uv_coordinate_count"]) < 1e-7
        expanded = [{**old, **new} for old, new in zip(original["surfaces"], authored["surfaces"])]
        charts = _charts(original["surfaces"])
        assert _charts(expanded) == row["uv_charts"] == row["original_uv_charts"] == charts
        assert len(row["uv_by_surface"]) == len(original["surfaces"])
        for sid, (old, new, surface_report) in enumerate(zip(original["surfaces"], authored["surfaces"], row["uv_by_surface"])):
            moved = sum(math.dist(a, b) > 1e-6 for a, b in zip(old["uv"], new["uv"]))
            assert moved / len(old["uv"]) <= .20
            assert surface_report["surface"] == sid and surface_report["label"] == new["label"]
            assert surface_report["uv_coordinate_count"] == len(new["uv"]) and surface_report["uv_changed_count"] == moved
            assert abs(surface_report["uv_changed_fraction"] - moved / len(old["uv"])) < 1e-7
        if name == "ArmorHead_05":
            quality = row["shape_quality"]
            assert quality["reversed_triangles"] == quality["zero_area_triangles"] == 0
            assert quality["coincident_seam_max_rest_gap"] <= 1e-6 and quality["min_triangle_normal_cosine_from_original"] > 0
            head = authored["surfaces"][0]
            old = original["surfaces"][0]
            assert charts == 3
            for i, parent in enumerate(head["triangle_parents"]):
                normal = _normal(head["positions"], head["indices"][3 * i:3 * i + 3])
                previous = _normal(old["positions"], old["indices"][3 * parent:3 * parent + 3])
                assert math.sqrt(sum(v * v for v in normal)) > 1e-12, "Actual zero-area head triangle"
                assert sum(a * b for a, b in zip(normal, previous)) > 0, "Actual reversed head triangle"
            seams = {}
            for i, position in enumerate(old["positions"]):
                seams.setdefault(tuple(position), []).append(i)
            for ids in seams.values():
                assert all(math.dist(head["positions"][ids[0]], head["positions"][i]) <= 1e-6 for i in ids), "Actual coincident head seam opened"
        measurements.append({"part": name, "original_max_rest_displacement_fraction": fraction,
                             "original_dimension_delta_fractions": deltas, "original_uv_changed_count": changed})
    return {"original_measurements": measurements,
            "triangles": 700 - 124 + config["head_refinement"]["triangles"], "surfaces": 5,
            "uv_coordinates": 1607 - 294 + config["head_refinement"]["vertices"]}


def verify_generation(config, textures, snapshot):
    from PIL import Image
    version = active_version(config)
    generation_path = ROOT / config["generation_record"]
    if version == 3:
        matched_bytes(generation_path, "bcaf97951aa0116171b96dc7be21b03300fccca2b140d07cad427a528f6dea56", historical=True)
    generation = read(generation_path)
    assert generation["model_revision"] == config["active_helmet_revision"] and generation["tool"] == "image_gen.imagegen"
    assert generation["use_case"] == "precise-object-edit"
    matched_bytes(ROOT / generation["prompt_path"], generation["prompt_sha256"], historical=version == 3)
    assert generation["canonical_path"] == "assets/armors/titan_v1/titan_head_diffuse.png"
    assert generation["archive_path"].startswith(f"docs/art/titan_runtime_v1/revisions/{config['active_helmet_revision']}/")
    for ref in generation["references"]:
        assert digest(ROOT / ref["snapshot"]) == ref["sha256"]
    assert digest(textures["head"]) == digest(ROOT / generation["archive_path"]) == generation["native_output_sha256"]
    native = Path(generation["native_output_path"])
    if native.is_file():
        assert digest(native) == generation["native_output_sha256"]
    if version == 4:
        assert generation["attempt"] in (1, 2), "Unreviewed Titan v4 generation attempt"
        initial = generation
        if generation["attempt"] == 2:
            previous_record = WORK / "revisions/helmet_refinement_v4/generation_record_attempt_01.json"
            assert generation["previous_attempt_record"] == previous_record.relative_to(ROOT).as_posix()
            assert digest(previous_record) == "ab49080983a1ce12e7168ede6720758bd243aeab1c69cb690963cf6c4c28e1a7"
            initial = read(previous_record)
            assert [r["role"] for r in generation["references"]] == ["edit_target", "actual_runtime_diagnostic", "approved_helmet_design"]
            assert generation["references"][0]["sha256"] == initial["native_output_sha256"]
            assert generation["references"][2]["sha256"] == initial["references"][1]["sha256"]
            assert generation["native_output_sha256"] == "feef79c197fdb4970c362132e14c6387418015d2f6af53806be8f73f0fc19179"
            assert generation["references"][1]["sha256"] == "49a8ccbaa62029a27c3762974fefcab715092da38f265a656450f4b002555209"
            assert digest(ROOT / initial["prompt_path"]) == initial["prompt_sha256"]
            assert digest(ROOT / initial["archive_path"]) == initial["native_output_sha256"]
            for ref in initial["references"]:
                assert digest(ROOT / ref["snapshot"]) == ref["sha256"]
        assert initial["tool"] == "image_gen.imagegen" and initial["model_revision"] == "helmet_refinement_v4" and initial["attempt"] == 1
        assert initial["native_output_sha256"] == "ae479ea82fa99a9ffb7ec7fd70b2c6a2166933f72e1ca1f731e756a0e50aedb4"
        assert [r["role"] for r in initial["references"]] == ["edit_target", "approved_helmet_design", "actual_runtime_diagnostic", "technical_uv_semantics"]
        parent = next(r for r in snapshot["files"] if r["path"] == generation["canonical_path"])
        assert initial["references"][0]["sha256"] == parent["sha256"] == "5f628b7172b3cb43954b7810824d603dc827fa953bec60bda76e465b69d5450d"
        diagnostic = next(r for r in snapshot["files"] if r["path"].endswith("helmet_v3_final/new_head_front.png"))
        assert initial["references"][2]["sha256"] == diagnostic["sha256"]
        prior_generation = read(WORK / "revisions/helmet_refinement_v3/generation_record.json")
        matched_bytes(WORK / "revisions/helmet_refinement_v3/generation_record.json", "bcaf97951aa0116171b96dc7be21b03300fccca2b140d07cad427a528f6dea56", historical=True)
        matched_bytes(ROOT / prior_generation["prompt_path"], prior_generation["prompt_sha256"], historical=True)
        assert digest(ROOT / prior_generation["archive_path"]) == parent["sha256"]
        assert initial["references"][1]["sha256"] == prior_generation["references"][1]["sha256"]
        assert initial["references"][3]["sha256"] == prior_generation["references"][2]["sha256"]
        for ref in prior_generation["references"]:
            assert digest(ROOT / ref["snapshot"]) == ref["sha256"]
    with Image.open(textures["head"]) as image:
        assert list(image.size) == generation["dimensions"] and image.size[0] == image.size[1]
        assert image.convert("RGBA").getextrema()[3] == (255, 255) and generation["alpha_extrema"] == [255, 255]
    # The four inherited maps retain their actual v1/v2 native generation chain.
    matched_bytes(WORK / "generation_inputs.json", "25a0078673105bd26bc338985a8b45e0f706552836781f9218b8e56d80c966be", historical=True)
    rows = read(WORK / "generation_inputs.json")
    base = ROOT / "docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt"
    assert digest(base) == "45ce003f7eac9ab1464b44bc314eb5f7ab7cbe7985a6ab0480021110f68a4df9"
    for row in rows:
        _authorize_text(ROOT / row["prompt"], row["prompt_sha256"])
        matched_bytes(ROOT / row["prompt"], row["prompt_sha256"], historical=True)
        assert base.read_text(encoding="utf-8") in (ROOT / row["prompt"]).read_text(encoding="utf-8")
        assert row["base_prompt_sha256"] == digest(base) and row["user_authorized_engineering_limit"] == .20
        assert "image_gen" in row["tool"] and digest(ROOT / row["archive"]) == row["archive_sha256"]
        for ref in row["references"]:
            assert digest(ROOT / ref["snapshot"]) == ref["sha256"]
        if row["variant"] == "original_integration_v1":
            assert row["references"][0]["role"] == "edit_target"
            assert row["references"][0]["sha256"] == digest(WORK / f"revisions/original_source_v1/atlases/{row['label']}.png")
        else:
            assert row["variant"] in {"original_integration_v2_head", "original_integration_v2_hand"}
            parent = next(p for p in rows if p["label"] == row["label"] and p["variant"] == "original_integration_v1")
            assert row["references"][0]["role"] == "edit_target_previous_attempt" and row["references"][0]["sha256"] == parent["archive_sha256"]
            assert parent["archive_sha256"] == digest(WORK / f"revisions/first_integration_v1_before_head_hand_refinement/delivery/{row['label']}_diffuse.png")
    images = [{"label": "head", "canonical_sha256": digest(textures["head"]), "dimensions": generation["dimensions"], "prompt": generation["prompt_path"], "postprocessing": "none; native PNG bytes"}]
    for label in sorted(LABELS - {"head"}):
        row = next(r for r in rows if r["label"] == label and r.get("selected"))
        assert row["variant"] == ("original_integration_v2_hand" if label == "hand" else "original_integration_v1")
        prior = next(r for r in snapshot["files"] if ROOT / r["path"] == textures[label])
        assert digest(textures[label]) == prior["sha256"] == row["archive_sha256"], label + " was modified"
        images.append({"label": label, "canonical_sha256": digest(textures[label]), "dimensions": row["output_size"], "prompt": row["prompt"], "postprocessing": "none; inherited native PNG bytes"})
    return images


def inputs():
    config = read(WORK / "runtime_config.json")
    version = active_version(config)
    verify_baselines()
    snapshot = verify_before(version)
    if version == 3:
        # The fixed Windows pre-v4 archive anchors the original Mac v3 text
        # report identities in both exact EOL forms; no new v3 pins are made.
        verify_before(4)
    source, target = read(WORK / "build/source.json"), read(WORK / "build/target.json")
    assert (WORK / "build/source.json").read_bytes() == (WORK / "revisions/original_source_v1/source.json").read_bytes()
    assert source == read(next(ROOT / row["snapshot"] for row in snapshot["files"] if row["path"].endswith("build/source.json")))
    verify_target(config, source, target, snapshot)
    verify_geometry(config, source, target)
    scene_check = read(WORK / "review/original_scene_invariants.json")
    assert scene_check["status"] == "PASS" and not scene_check["errors"]
    assert scene_check["current_scene_sha256"] == digest(ROOT / config["asset"] / "titan.scn")
    for key in ("source", "target", "geometry"):
        hash_matches(WORK / f"build/{key}.json", scene_check[f"{key}_sha256"], historical=version == 3)
    hash_matches(WORK / "revisions/original_source_v1/snapshot.json", scene_check["original_source_snapshot_sha256"], historical=True)
    assert scene_check["original_node_ids"] == config["original_node_ids"] and scene_check["original_bones"] == 28
    assert len(scene_check["records"]) == 4 and {r["part"] for r in scene_check["records"]} == set(config["parts"])
    assert sum(r["surfaces"] for r in scene_check["records"]) == 5
    for row in scene_check["records"]:
        assert row["rest_position_uv_verified_against_target"] and row["max_rest_error_m"] < 1e-6
        if row["part"] == "ArmorHead_05":
            assert row["refinement_contract_verified"] is True
        else:
            assert row["body_limbs_all_arrays_exact"] is True and row["indices_skin_weights_bones_topology_exact"] is True
    textures = {label: ROOT / config["asset"] / filename for label, filename in config["texture_files"].items()}
    verify_generation(config, textures, snapshot)
    return config, source, target, textures


def verify_master(config, source, target, textures):
    import bpy
    from mathutils import Matrix, Vector
    master = WORK / "build/titan_master.blend"
    assert Path(bpy.data.filepath).resolve() == master.resolve()
    meshes = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    assert set(meshes) == set(config["parts"])
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    assert len(rigs) == 1
    rig = rigs[0]
    names = {bone["name"] for bone in source["bones"]}
    assert {bone.name for bone in rig.data.bones} == names and len(names) == 28
    conversion = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    for original in source["bones"]:
        bone = rig.data.bones[original["name"]]
        parent = source["bones"][original["parent"]]["name"] if original["parent"] >= 0 else None
        assert (bone.parent.name if bone.parent else None) == parent
        rest = conversion @ Matrix(original["matrix"])
        assert (bone.head_local - rest.translation).length < 1e-6
        assert (bone.tail_local - rest.translation - rest.to_3x3() @ Vector((0, .06, 0))).length < 1e-6
    triangles = 0
    for name, obj in meshes.items():
        assert obj.parent == rig and any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)
        offset = 0
        faces, slots = [], []
        for sid, (original, authored) in enumerate(zip(source["parts"][name]["surfaces"], target["parts"][name]["surfaces"])):
            topology = authored.get("indices", original["indices"])
            for start in range(0, len(topology), 3):
                faces.append(tuple(offset + i for i in reversed(topology[start:start + 3])))
                slots.append(sid)
            for i, position in enumerate(authored["positions"]):
                vertex = obj.data.vertices[offset + i]
                x, y, z = position
                assert (vertex.co - Vector((-x, z, y))).length < 1e-6
                expected = {}
                for bone, weight in zip(authored.get("bone_names", original["bone_names"])[i], authored.get("weights", original["weights"])[i]):
                    if weight > 0:
                        expected[bone] = expected.get(bone, 0) + weight
                actual = {obj.vertex_groups[group.group].name: group.weight for group in vertex.groups if group.weight > 0}
                assert set(actual) == set(expected)
                assert all(abs(actual[bone] - weight) < 1e-6 for bone, weight in expected.items())
            offset += len(authored["positions"])
        assert len(obj.data.vertices) == offset
        assert [tuple(poly.vertices) for poly in obj.data.polygons] == faces
        assert [poly.material_index for poly in obj.data.polygons] == slots
        uv = [p for row in target["parts"][name]["surfaces"] for p in row["uv"]]
        for loop, actual in zip(obj.data.loops, obj.data.uv_layers.active.data):
            expected = uv[loop.vertex_index]
            assert math.dist((actual.uv.x, 1 - actual.uv.y), expected) < 1e-6
        for sid, label in enumerate(config["parts"][name]):
            images = [node.image for node in obj.data.materials[sid].node_tree.nodes if node.type == "TEX_IMAGE"]
            assert len(images) == 1 and images[0].packed_file
            assert hashlib.sha256(bytes(images[0].packed_file.data)).hexdigest() == digest(textures[label])
        triangles += len(faces)
    assert triangles == 700 - 124 + config["head_refinement"]["triangles"]
    return {"master_sha256": digest(master), "triangles": triangles, "bones": 28,
            "authored_uv_indices_weights_verified": True, "five_packed_native_pngs_exact": True}


def verify_glb(config, source, target, textures):
    import io
    from PIL import Image, ImageChops
    from validate_glb_images import read_accessor
    path = ROOT / config["asset"] / "titan.glb"
    data = path.read_bytes()
    assert data[:4] == b"glTF" and struct.unpack_from("<II", data, 4) == (2, len(data))
    chunks, cursor = {}, 12
    while cursor < len(data):
        length, kind = struct.unpack_from("<II", data, cursor)
        chunks[kind] = data[cursor + 8:cursor + 8 + length]
        cursor += 8 + length
    assert cursor == len(data)
    gltf, binary = json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]
    assert len(gltf["meshes"]) == 4 and len(gltf["images"]) == 5
    records = {}
    for name, labels in config["parts"].items():
        node = next(node for node in gltf["nodes"] if node.get("name") == name)
        joints = [gltf["nodes"][i]["name"] for i in gltf["skins"][node["skin"]]["joints"]]
        assert len(joints) == len(set(joints)) == 28 and set(joints) == {b["name"] for b in source["bones"]}
        primitives = gltf["meshes"][node["mesh"]]["primitives"]
        assert len(primitives) == len(labels)
        for sid, (label, primitive) in enumerate(zip(labels, primitives)):
            original = source["parts"][name]["surfaces"][sid]
            uv = read_accessor(gltf, binary, primitive["attributes"]["TEXCOORD_0"])
            indices = [r[0] for r in read_accessor(gltf, binary, primitive["indices"])]
            authored = target["parts"][name]["surfaces"][sid]
            topology = authored.get("indices", original["indices"])
            assert len(uv) == len(authored["uv"]) and len(indices) == len(topology)
            assert all(math.dist(a, b) < 1e-6 for a, b in zip(uv, authored["uv"]))
            assert all(indices[i:i + 3] == list(reversed(topology[i:i + 3])) for i in range(0, len(indices), 3))
            binds = read_accessor(gltf, binary, primitive["attributes"]["JOINTS_0"])
            weights = read_accessor(gltf, binary, primitive["attributes"]["WEIGHTS_0"])
            assert len(binds) == len(weights) == len(uv)
            for i, (bones, values) in enumerate(zip(binds, weights)):
                expected, actual = {}, {}
                source_weights = authored.get("weights", original["weights"])[i]
                for bone, value in zip(authored.get("bone_names", original["bone_names"])[i], source_weights):
                    if value > 0:
                        expected[bone] = expected.get(bone, 0) + value / sum(source_weights)
                for bone, value in zip(bones, values):
                    if value > 0:
                        actual[joints[bone]] = actual.get(joints[bone], 0) + value
                assert set(actual) == set(expected) and abs(sum(values) - 1) < 1e-5
                assert all(abs(actual[bone] - value) < 2e-6 for bone, value in expected.items())
            material = gltf["materials"][primitive["material"]]
            texture = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            image = gltf["images"][gltf["textures"][texture]["source"]]
            assert image["mimeType"] == "image/png" and "bufferView" in image
            view = gltf["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            embedded = Image.open(io.BytesIO(binary[start:start + view["byteLength"]])).convert("RGB")
            canonical = Image.open(textures[label]).convert("RGB")
            assert embedded.size == canonical.size and ImageChops.difference(embedded, canonical).getbbox() is None
            records[label] = {"canonical_sha256": digest(textures[label]), "dimensions": list(canonical.size), "rgb_exact": True}
    return {"glb_sha256": digest(path), "authored_triangle_uv_normalized_skin_verified": True, "images": records}


def main():
    config, source, target, textures = inputs()
    version = active_version(config)
    try:
        import bpy
    except ImportError:
        mode, checks = "glb", verify_glb(config, source, target, textures)
    else:
        mode, checks = "master", verify_master(config, source, target, textures)
    report = {"status": "PASS", "revision": config["active_helmet_revision"],
              "scope": "Current revision; exact source snapshot, actual SCN original-array check, preserved non-head textures and native generation provenance. Historical integration hashes are not recertified.",
              "source_sha256": digest(WORK / "build/source.json"), "target_sha256": digest(WORK / "build/target.json"),
              "geometry_sha256": digest(WORK / "build/geometry.json"),
              "current_scene_sha256": digest(ROOT / config["asset"] / "titan.scn"),
              "original_source_snapshot_sha256": SOURCE_INDEX_SHA,
              "before_revision_snapshot_sha256": BEFORE_INDEX_SHA[version],
              "canonical_diffuse_sha256": {label: digest(path) for label, path in textures.items()},
              "head_contract": verify_target(config, source, target, verify_before(version)),
              "original_metrics": verify_geometry(config, source, target), **checks}
    (WORK / f"review/helmet_v{version}_{mode}_test.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"TITAN_HELMET_V{version}_{mode.upper()}_PASS")


if __name__ == "__main__":
    main()
