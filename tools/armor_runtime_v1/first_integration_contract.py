"""Portable true-source and native-image contract for Atom/Pegasus only.

Existing Hydra/Strike/Titan validators retain their pinned historical contracts.
This module reuses only their independent geometry measurement, not a new
entry in their historical manifest or an altered expectation for old assets.
"""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[2]
LABELS = {"head", "body", "shoulder", "hand", "foot"}
IDS = {"atom": 7, "pegasus": 8}
ORIGINAL_TRIANGLES = {"atom": 860, "pegasus": 1128}
BASE_PROMPT_SHA256 = "45ce003f7eac9ab1464b44bc314eb5f7ab7cbe7985a6ab0480021110f68a4df9"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_reference(reference, passed_path, root=None):
    """Bind the actual imagegen path to its recorded immutable bytes.

    Generation may pass the source itself or the frozen input snapshot. Keep
    those different path roles explicit; never rewrite provenance to claim
    that a different filename was actually submitted to imagegen.
    """
    assert passed_path in [reference["path"], reference["snapshot"]], "Actual reference path was not the recorded source or snapshot"
    root = ROOT if root is None else Path(root)
    source, snapshot, passed = (root / value for value in [reference["path"], reference["snapshot"], passed_path])
    expected = reference["sha256"]
    assert digest(source) == expected, "Original reference bytes changed: " + reference["path"]
    assert digest(snapshot) == expected, "Frozen reference bytes changed: " + reference["snapshot"]
    assert digest(passed) == expected, "Actual imagegen reference bytes differ: " + passed_path


def verify_edit_lineage(row, rows, original_hash):
    """Follow every retained retry back to this label's true original atlas.

    Each edge must refer to exactly one earlier, rejected native output. The
    earlier-only rule also prevents self-links, forward links and cycles.
    Full prompt/reference/native-file hashes are verified for every row by
    verify_first_generation; this function establishes their edit ancestry.
    """
    current = row
    current_index = next(index for index, candidate in enumerate(rows) if candidate is row)
    while True:
        target = current["references"][0]
        if target["role"] == "edit_target":
            assert target["sha256"] == original_hash, "Edit lineage does not end at the true original atlas"
            return
        assert target["role"] == "edit_target_previous_attempt", "Unknown edit-target lineage role"
        parents = [(index, candidate) for index, candidate in enumerate(rows)
                   if not candidate.get("selected") and candidate["label"] == row["label"]
                   and candidate["archive_sha256"] == target["sha256"]]
        assert len(parents) == 1, "Retry must have one retained, rejected native parent of the same label"
        parent_index, parent = parents[0]
        assert parent_index < current_index, "Retry parent must precede its child; self-links, forward links and cycles are invalid"
        current, current_index = parent, parent_index


def _legacy():
    spec = importlib.util.spec_from_file_location("independent_original_geometry", ROOT / "tools/armor_style_unification_v1/validate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def measure_original_geometry(source, target, geometry, limits):
    # Texture-only first integration has an additional exact-position/UV gate.
    for name, part in source["parts"].items():
        for old, new in zip(part["surfaces"], target["parts"][name]["surfaces"]):
            assert old["positions"] == new["positions"], name + ": texture-only original positions changed"
            assert old["uv"] == new["uv"], name + ": original UV changed"
            assert not any(key in new for key in ["added_vertices", "triangle_parents"]), "Unexpected topology refinement"
    return _legacy().measure_original_geometry(source, target, geometry, limits)


def verify_first_source(slug):
    armor_id = IDS[slug]
    work = ROOT / f"docs/art/{slug}_runtime_v1"
    config = read(work / "runtime_config.json")
    frozen = work / "revisions/original_source_v1"
    snapshot_path = frozen / "snapshot.json"
    assert config["original_source_snapshot"] == snapshot_path.relative_to(ROOT).as_posix()
    assert digest(snapshot_path) == config["original_source_snapshot_sha256"]
    snapshot = read(snapshot_path)
    expected = {"source.json", "runtime_config.json", "scripts/inspect_sources.gd",
                *(f"atlases/{label}.png" for label in LABELS), *(f"guides/{label}_uv.svg" for label in LABELS)}
    assert snapshot["status"] == "FROZEN_TRUE_ORIGINAL_SOURCE" and snapshot["runtime_id"] == armor_id
    assert set(snapshot["files"]) == expected
    for relative, record in snapshot["files"].items():
        path = frozen / relative
        assert path.resolve().is_relative_to(frozen.resolve())
        assert digest(path) == record["sha256"] and path.stat().st_size == record["bytes"], "Frozen original bytes changed: " + relative
    source = read(frozen / "source.json")
    assert (work / "build/source.json").read_bytes() == (frozen / "source.json").read_bytes()
    assert source["original_scene"] == "res://assets/models/player/animated/player.gltf"
    original = ROOT / source["original_scene"].removeprefix("res://")
    assert digest(original) == source["original_scene_sha256"] == snapshot["original_scene_sha256"]
    gltf = read(original)
    expected_names = [f"Armor{part}_{armor_id:02d}" for part in ["Head", "Body", "Hand", "Foot"]]
    nodes = {node["name"]: index for index, node in enumerate(gltf["nodes"]) if node.get("name") in expected_names}
    assert set(nodes) == set(source["parts"]) == set(snapshot["used_nodes"]) == set(expected_names)
    index_path = frozen / "source_node_index.json"
    assert config["source_node_index"] == index_path.relative_to(ROOT).as_posix()
    assert digest(index_path) == config["source_node_index_sha256"]
    index = read(index_path)
    assert index["original_source_snapshot_sha256"] == digest(snapshot_path)
    assert index["original_gltf_sha256"] == digest(original) and index["runtime_id"] == armor_id
    assert index["node_ids"] == nodes == config["original_node_ids"]
    for node, number in nodes.items():
        assert index["gltf_node_records"][node] == gltf["nodes"][number]
        assert gltf["nodes"][number]["extras"]["armor_id"] == armor_id
    assert len(index["buffers"]) == len(gltf["buffers"])
    for row, original_row in zip(index["buffers"], gltf["buffers"]):
        assert row["uri"] == original_row["uri"] and row["byteLength"] == original_row["byteLength"]
        path = original.parent / row["uri"]
        assert path.resolve().is_relative_to(original.parent.resolve())
        assert digest(path) == row["sha256"] and path.stat().st_size == row["byteLength"]
    bone_names = [row["name"] for row in source["bones"]]
    assert len(bone_names) == len(set(bone_names)) == 28
    for row in source["bones"]:
        assert -1 <= row["parent"] < 28 and len(row["matrix"]) == 4
        assert all(len(values) == 4 and all(math.isfinite(v) for v in values) for values in row["matrix"])
    for node, part in source["parts"].items():
        assert part["skin_binds"] == len(part["bind_records"])
        for surface in part["surfaces"]:
            count = len(surface["positions"])
            assert count > 0 and len(surface["indices"]) % 3 == 0
            assert all(isinstance(i, int) and 0 <= i < count for i in surface["indices"])
            assert all(len(surface[key]) == count for key in ["uv", "weights", "bone_names", "bone_indices", "raw_positions", "normals"])
            for weights, names, binds in zip(surface["weights"], surface["bone_names"], surface["bone_indices"]):
                assert len(weights) == len(names) == len(binds) == 4
                assert all(math.isfinite(w) and 0 <= w <= 1 for w in weights) and abs(sum(weights) - 1) <= 4 / 65535 + 1e-6
                assert all(name in bone_names for name in names)
                assert all(isinstance(i, int) and 0 <= i < part["skin_binds"] for i in binds)
    old_config = read(frozen / "runtime_config.json")
    for key in ["runtime_id", "slug", "parts", "texture_slots", "original_triangles", "original_bones", "original_surface_count", "original_uv_coordinate_count"]:
        assert config[key] == old_config[key]
    assert config["slug"] == slug and config["runtime_id"] == armor_id
    assert config["preserve_all_geometry"] is True and config["original_triangles"] == ORIGINAL_TRIANGLES[slug]
    assert config["original_bones"] == 28 and config["original_surface_count"] == 5
    assert config["original_total_geometry_limit"] == config["original_total_uv_changed_fraction_per_surface_limit"] == .20
    assert set(config["texture_slots"]) == LABELS
    legacy = _legacy()
    coordinate_count = triangle_count = 0
    for label, slot in config["texture_slots"].items():
        surface = source["parts"][slot["node"]]["surfaces"][slot["surface"]]
        assert config["parts"][slot["node"]][slot["surface"]] == label
        assert surface["texture"].removeprefix("res://") == slot["original_texture"]
        assert digest(ROOT / slot["original_texture"]) == digest(frozen / f"atlases/{label}.png") == slot["original_sha256"]
        assert len(surface["uv"]) == slot["coordinates"] and legacy.uv_chart_count([surface]) == slot["charts"]
        assert len(surface["indices"]) // 3 == slot["triangles"]
        coordinate_count += slot["coordinates"]
        triangle_count += slot["triangles"]
    assert coordinate_count == config["original_uv_coordinate_count"] and triangle_count == config["original_triangles"]
    return source, {"original_source_snapshot_records_verified": 13, "original_source_snapshot_sha256": digest(snapshot_path),
                    "original_node_index_sha256": digest(index_path), "used_node_ids": nodes}


def verify_first_generation(slug, work, assets):
    assert slug in IDS
    base_path = ROOT / "docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt"
    assert digest(base_path) == BASE_PROMPT_SHA256, "Shared required prompt contract changed"
    base = base_path.read_text(encoding="utf-8")
    rows = read(work / "generation_inputs.json")
    selected = [row for row in rows if row.get("selected")]
    assert len(selected) == 5 and {row["label"] for row in selected} == LABELS
    images = []
    for row in rows:
        assert row["label"] in LABELS and "image_gen" in row["tool"]
        assert row["base_prompt"] == base_path.relative_to(ROOT).as_posix() and row["base_prompt_sha256"] == BASE_PROMPT_SHA256
        assert row["user_authorized_engineering_limit"] == .20
        prompt = ROOT / row["prompt"]
        assert base in prompt.read_text(encoding="utf-8") and digest(prompt) == row["prompt_sha256"]
        assert len(row["references"]) == len(row["reference_images"]) >= 2
        for ref, passed_path in zip(row["references"], row["reference_images"]):
            verify_reference(ref, passed_path)
        original_hash = digest(work / f"revisions/original_source_v1/atlases/{row['label']}.png")
        verify_edit_lineage(row, rows, original_hash)
        archive, native = ROOT / row["archive"], Path(row["generated_file"])
        expected_hash = row["archive_sha256"]
        assert digest(archive) == expected_hash and expected_hash != original_hash
        if native.is_file():
            assert digest(native) == expected_hash
        raw = archive.read_bytes()
        assert raw[:8] == b"\x89PNG\r\n\x1a\n"
        dimensions = list(struct.unpack(">II", raw[16:24]))
        assert dimensions == row["output_size"] and dimensions[0] == dimensions[1] and dimensions[0] >= 512
        if row.get("selected"):
            canonical = assets / f"{row['label']}_diffuse.png"
            assert digest(canonical) == expected_hash
            if row["label"] == "head":
                assert any("design_authority" in ref["role"] for ref in row["references"])
            if row["label"] == "body":
                assert any(ref["role"] in ["approved_design", "approved_body_design"] for ref in row["references"])
            images.append({"label": row["label"], "canonical_sha256": expected_hash, "dimensions": dimensions,
                           "native_generator_path_available": native.is_file(), "prompt": row["prompt"], "postprocessing": "none; native PNG bytes"})
    return images
