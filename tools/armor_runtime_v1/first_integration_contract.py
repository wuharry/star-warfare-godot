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
TEXTURE_HISTORY_SHA256 = {"atom":"b11f3dbef7eb700e02dfef178703d1828e700f06c4d51aa1332211e169db1d6d",
                         "pegasus":"5f750a59cfbf2c5093f7701e89e25b9de430cfef5a0e4b7fe5a8d51dd1879f23"}
REFINEMENT_HISTORY_SHA256 = {"atom":"dceb6a0fc6706e3a82aaf97ac9f0b50ae0a9d613902be7626a8223c7b0a358fb",
                            "pegasus":"30d280ef5defb7d5f30b2b48fa5b97f6315e0d9f203f49943452fa54b49a6252"}
REFINEMENT_HISTORY_COMMIT = "3ed1c2911e1eea5162e30d0bab331fd41a1d29f9"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_texture_history(slug):
    """Freeze the previous delivery independently of the true-source baseline."""
    frozen=ROOT/f"docs/art/{slug}_runtime_v1/revisions/before_draft_refinement_v2"
    index=frozen/"snapshot.json"
    assert digest(index)==TEXTURE_HISTORY_SHA256[slug], "Frozen previous delivery index changed"
    snapshot=read(index)
    assert snapshot["source_commit"]=="f94323e40b3e7002268b39944bdcb58c2737c41f"
    assert snapshot["status"]=="FROZEN_TEXTURE_ONLY_BASELINE" and len(snapshot["files"])==96
    assert len({row["original_path"] for row in snapshot["files"]})==96
    for row in snapshot["files"]:
        path=ROOT/row["snapshot_path"]
        assert path.resolve().is_relative_to(frozen.resolve())
        assert path.stat().st_size==row["bytes"] and digest(path)==row["sha256"], "Frozen previous delivery bytes changed: "+row["snapshot_path"]
    return {"path":index.relative_to(ROOT).as_posix(),"sha256":digest(index),"files_verified":96,"source_commit":snapshot["source_commit"]}


def verify_refinement_history(slug):
    """Append a pinned v2-model delivery without replacing the f943 history."""
    previous=ROOT/f"docs/art/{slug}_runtime_v1/revisions/before_draft_refinement_v2/snapshot.json"
    assert digest(previous)==TEXTURE_HISTORY_SHA256[slug], "Frozen texture-only index changed"
    original_paths={row["original_path"] for row in read(previous)["files"]}
    frozen=ROOT/f"docs/art/{slug}_runtime_v1/revisions/before_draft_refinement_v3"
    index=frozen/"snapshot.json"
    assert digest(index)==REFINEMENT_HISTORY_SHA256[slug], "Frozen v2 refinement index changed"
    snapshot=read(index)
    assert snapshot["source_commit"]==REFINEMENT_HISTORY_COMMIT
    assert snapshot["status"]=="FROZEN_DRAFT_REFINEMENT_V2_BASELINE" and len(snapshot["files"])==96
    assert len(original_paths)==96 and {row["original_path"] for row in snapshot["files"]}==original_paths
    for row in snapshot["files"]:
        path=ROOT/row["snapshot_path"]
        assert row["snapshot_path"]==(frozen/row["original_path"]).relative_to(ROOT).as_posix()
        assert path.resolve().is_relative_to(frozen.resolve())
        assert path.stat().st_size==row["bytes"] and digest(path)==row["sha256"], "Frozen v2 refinement bytes changed: "+row["snapshot_path"]
    return {"path":index.relative_to(ROOT).as_posix(),"sha256":digest(index),"files_verified":96,"source_commit":snapshot["source_commit"]}


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

    Each edge must refer to exactly one earlier, retained native output. A
    rejected retry may retain its selected ancestor when that ancestor is
    restored, but a selected retry and its ancestor cannot both be selected. The
    earlier-only rule also prevents self-links, forward links and cycles.
    Full prompt/reference/native-file hashes are verified for every row by
    verify_first_generation; this function establishes their edit ancestry.
    """
    current = row
    selected_descendant = bool(row.get("selected"))
    current_index = next(index for index, candidate in enumerate(rows) if candidate is row)
    while True:
        target = current["references"][0]
        if target["role"] == "edit_target":
            assert target["sha256"] == original_hash, "Edit lineage does not end at the true original atlas"
            return
        assert target["role"] == "edit_target_previous_attempt", "Unknown edit-target lineage role"
        parents = [(index, candidate) for index, candidate in enumerate(rows)
                   if candidate["label"] == row["label"]
                   and candidate["archive_sha256"] == target["sha256"]]
        assert len(parents) == 1, "Retry must have one retained native parent of the same label"
        parent_index, parent = parents[0]
        assert parent_index < current_index, "Retry parent must precede its child; self-links, forward links and cycles are invalid"
        assert not (selected_descendant and parent.get("selected")), "Selected retry and ancestor cannot both be selected"
        selected_descendant = selected_descendant or bool(parent.get("selected"))
        current, current_index = parent, parent_index


def _legacy():
    spec = importlib.util.spec_from_file_location("independent_original_geometry", ROOT / "tools/armor_style_unification_v1/validate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def geometry_parts(config, source_parts):
    """Return explicitly movable source parts; old texture-only stays strict."""
    if config is None or config.get("preserve_all_geometry") is True:
        assert config is None or config.get("geometry_mode", "texture_only") == "texture_only"
        return set()
    assert config.get("preserve_all_geometry") is False
    assert config.get("geometry_mode") == "original_source_bounded_refinement", "Unknown geometry contract"
    parts = config.get("geometry_parts")
    assert isinstance(parts, list) and parts and len(parts) == len(set(parts))
    assert set(parts) <= set(source_parts), "Geometry contract contains a non-original part"
    return set(parts)


def _sub(a, b):
    return [x - y for x, y in zip(a, b)]


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def _unit(v):
    length = math.sqrt(_dot(v, v))
    assert length > 1e-12, "Zero direction in authored normal/tangent frame"
    return [value / length for value in v]


def bind_normal_frames(original, positions):
    """Recalculate bind-space frames, retaining original hard-normal groups.

    Original UV islands/indices are inputs, never edited. Coincident original
    positions with the same original normal share area-weighted normals;
    different source normals retain the original hard edge.
    """
    count = len(positions)
    assert count == len(original["raw_positions"]) == len(original["normals"]) == len(original["uv"])
    keys = [tuple(round(v, 7) for v in point + normal)
            for point, normal in zip(original["raw_positions"], original["normals"])]
    sums = {key: [0.0, 0.0, 0.0] for key in keys}
    tangent_sum = [[0.0]*3 for _ in positions]
    bitangent_sum = [[0.0]*3 for _ in positions]
    indices = original["indices"]
    for offset in range(0, len(indices), 3):
        i, j, k = indices[offset:offset+3]
        edge1, edge2 = _sub(positions[j], positions[i]), _sub(positions[k], positions[i])
        normal = _cross(edge1, edge2)
        original_sum = [sum(original["normals"][v][axis] for v in [i,j,k]) for axis in range(3)]
        if _dot(normal, original_sum) < 0:
            normal = [-value for value in normal]
        for vertex in [i,j,k]:
            sums[keys[vertex]] = [a+b for a,b in zip(sums[keys[vertex]], normal)]
        uv1, uv2 = _sub(original["uv"][j], original["uv"][i]), _sub(original["uv"][k], original["uv"][i])
        determinant = uv1[0]*uv2[1]-uv1[1]*uv2[0]
        if abs(determinant) > 1e-12:
            tangent = [(uv2[1]*a-uv1[1]*b)/determinant for a,b in zip(edge1,edge2)]
            bitangent = [(uv1[0]*b-uv2[0]*a)/determinant for a,b in zip(edge1,edge2)]
            for vertex in [i,j,k]:
                tangent_sum[vertex] = [a+b for a,b in zip(tangent_sum[vertex],tangent)]
                bitangent_sum[vertex] = [a+b for a,b in zip(bitangent_sum[vertex],bitangent)]
    normals, tangents = [], []
    for index, key in enumerate(keys):
        total = sums[key]
        normal = _unit(total) if _dot(total,total) > 1e-20 else _unit(original["normals"][index])
        raw = tangent_sum[index]
        tangent = [a-b*_dot(normal,raw) for a,b in zip(raw,normal)]
        if _dot(tangent,tangent) <= 1e-20:
            axis = [1.0,0.0,0.0] if abs(normal[0]) < .9 else [0.0,1.0,0.0]
            tangent = [a-b*_dot(normal,axis) for a,b in zip(axis,normal)]
        tangent = _unit(tangent)
        handedness = -1.0 if _dot(_cross(normal,tangent),bitangent_sum[index]) < 0 else 1.0
        normals.append(normal)
        tangents.append(tangent + [handedness])
    return normals, tangents


def part_shape_quality(original_surfaces, authored_surfaces):
    reversed_triangles = new_degenerate_triangles = inherited_degenerate_triangles = 0
    groups, minimum_cosine = {}, 1.0
    for original, authored in zip(original_surfaces, authored_surfaces):
        for old, new in zip(original["positions"], authored["positions"]):
            groups.setdefault(tuple(old), []).append(new)
        for offset in range(0, len(original["indices"]), 3):
            indices = original["indices"][offset:offset+3]
            old = [original["positions"][i] for i in indices]
            new = [authored["positions"][i] for i in indices]
            a, b = _cross(_sub(old[1],old[0]),_sub(old[2],old[0])), _cross(_sub(new[1],new[0]),_sub(new[2],new[0]))
            length_a, length_b = math.sqrt(_dot(a,a)), math.sqrt(_dot(b,b))
            if length_a <= 1e-10:
                inherited_degenerate_triangles += 1
                continue
            if length_b <= 1e-10:
                new_degenerate_triangles += 1
                continue
            cosine = _dot(a,b)/(length_a*length_b)
            minimum_cosine = min(minimum_cosine,cosine)
            reversed_triangles += cosine < 0
    seam = max((math.dist(a,b) for points in groups.values() for a in points for b in points), default=0.0)
    return {"reversed_triangles": reversed_triangles, "new_degenerate_triangles": new_degenerate_triangles,
            "inherited_degenerate_triangles": inherited_degenerate_triangles,
            "coincident_seam_max_rest_gap": seam, "min_triangle_normal_cosine_from_original": minimum_cosine}


def measure_original_geometry(source, target, geometry, limits, config=None):
    movable = geometry_parts(config, source["parts"])
    assert set(target["parts"]) == set(source["parts"]), "Original modular parts changed"
    if config is not None and movable:
        assert target["geometry_mode"] == config["geometry_mode"]
        assert target["geometry_parts"] == config["geometry_parts"]
    assert all(value == .20 for value in limits.values()), "True-original geometry limit must remain 20%"
    quality = {}
    for name, part in source["parts"].items():
        assert len(part["surfaces"]) == len(target["parts"][name]["surfaces"])
        for old, new in zip(part["surfaces"], target["parts"][name]["surfaces"]):
            if name not in movable:
                assert old["positions"] == new["positions"], name + ": texture-only original positions changed"
            assert old["uv"] == new["uv"], name + ": original UV changed"
            assert not any(key in new for key in ["added_vertices", "triangle_parents"]), "Unexpected topology refinement"
            for key in ["indices", "weights", "bone_indices", "bone_names"]:
                assert key not in new or new[key] == old[key], name + ": original topology/skin field changed: " + key
            assert len(new["positions"]) == len(old["positions"]), name + ": original vertex count changed"
            changed = any(math.dist(a,b) > 1e-6 for a,b in zip(old["positions"],new["positions"]))
            if movable:
                assert new.get("geometry_changed") is changed, name + ": false geometry-change declaration"
            if changed:
                assert name in movable and len(new["raw_positions"]) == len(new["normals"]) == len(new["tangents"]) == len(old["positions"])
                for key, width in [("raw_positions",3),("normals",3),("tangents",4)]:
                    assert all(len(value)==width and all(math.isfinite(component) for component in value) for value in new[key]), name + ": invalid authored geometry frame"
                bones = {row["name"]: row["matrix"] for row in source["bones"]}
                for index, (before, after) in enumerate(zip(old["raw_positions"],new["raw_positions"])):
                    delta = _sub(after,before)
                    rest_delta = [0.0]*3
                    for bind, weight in zip(old["bone_indices"][index],old["weights"][index]):
                        record = part["bind_records"][bind]
                        bone, pose = bones[record["name"]], record["matrix"]
                        basis = [[sum(bone[i][k]*pose[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
                        for axis in range(3):
                            rest_delta[axis] += sum(basis[axis][j]*delta[j] for j in range(3))*weight
                    expected = [a+b for a,b in zip(old["positions"][index],rest_delta)]
                    assert math.dist(expected,new["positions"][index]) < 2e-6, name + ": raw bind positions differ from authored rest target"
                expected_normals, expected_tangents = bind_normal_frames(old,new["raw_positions"])
                for actual, expected in zip(new["normals"]+new["tangents"],expected_normals+expected_tangents):
                    assert math.dist(actual,expected) < 1e-6, name + ": authored normal/tangent frame changed"
        quality[name] = part_shape_quality(part["surfaces"],target["parts"][name]["surfaces"])
        assert quality[name]["reversed_triangles"] == quality[name]["new_degenerate_triangles"] == 0, name + ": reversed or new degenerate triangle"
        assert quality[name]["coincident_seam_max_rest_gap"] <= 1e-6, name + ": original coincident seam split"
    measured = _legacy().measure_original_geometry(source, target, geometry, limits)
    measured["geometry_mode"] = "original_source_bounded_refinement" if movable else "texture_only"
    measured["movable_parts"] = sorted(movable)
    measured["shape_quality"] = quality
    return measured


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
    geometry_parts(config, source["parts"])
    history=verify_texture_history(slug) if config.get("geometry_mode")=="original_source_bounded_refinement" else None
    refinement_history=verify_refinement_history(slug) if config.get("geometry_mode")=="original_source_bounded_refinement" else None
    assert config["original_triangles"] == ORIGINAL_TRIANGLES[slug]
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
                    "original_node_index_sha256": digest(index_path), "used_node_ids": nodes,"previous_texture_only_delivery":history,
                    "previous_draft_refinement_delivery":refinement_history}


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
