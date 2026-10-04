"""Verify current armor delivery and explicit helmet-refinement contracts.

Immutable paint-only baselines remain unchanged. Tank's completed v2 remains
an independently verified paint-only history; its later head correction has
an original-total 20% budget and zero new UV edits. Fortune's separate head
correction retains its original 15% budget. Hydra, Strike and Titan are first
integrations checked against their own true originals, never a prior runtime
zero-geometry contract.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/armor_style_unification_v1"
LABELS = {"head", "body", "shoulder", "hand", "foot"}
SUFFIXES = [
    *(f"{mode}_{view}" for mode in ("diffuse", "head") for view in ("front", "quarter", "side", "rear")),
    "clay_front", "clay_side", "level_01_gameplay", "level_08_gameplay",
    "idle_rifle", "run_rifle", "reload_04",
]
EXPECTED_CAPTURE_NAMES = {
    *(f"{version}_{style}_{view}.png" for version in ["original", "new"] for style in ["clay", "painted", "diffuse"] for view in ["front", "quarter", "side", "rear"]),
    *(f"{version}_head_{view}.png" for version in ["original", "new"] for view in ["front", "quarter", "side", "rear"]),
    "family_original_01_front.png", "family_original_06_front.png",
    *(f"{version}_{pose}_rifle.png" for version in ["original", "new"] for pose in ["idle", "run"]),
    *(f"{version}_reload_{frame:02d}.png" for version in ["original", "new"] for frame in range(9)),
    *(f"{version}_level_{level}_{view}.png" for version in ["original", "new"] for level in ["01", "08"] for view in ["gameplay", "front"]),
}
FORTUNE_V7 = WORK / "revisions/fortune_head_v7_before_refinement"
TANK_BEFORE = ROOT / "docs/art/tank_runtime_v1/revisions/before_style_unification_v2"
TANK_SNAPSHOT_SHA256 = "5cc171e01d5e58663e0f5e93632da9f156f765c7ebc526e0eda126d98a8e5dbf"
TANK_USER_CEILING = .20
TANK_DELIVERY_LIMIT = .15
TANK_STYLE_V2 = ROOT / "docs/art/tank_runtime_v1/revisions/before_helmet_refinement_v3"
TANK_STYLE_V2_SNAPSHOT_SHA256 = "2235a24b261d60b58c1f0f87c115518cc0723f5406e3a24c4b2a3411b7eb157f"
TANK_SHARED_STYLE_V2 = WORK / "revisions/tank_style_v2_before_helmet_refinement"
TANK_SHARED_STYLE_V2_SNAPSHOT_SHA256 = "cca5d8ef43bce685a19be82e912e2d52776a36a3739d424addea64ca583d1390"
TANK_HELMET_BASE_SHA256 = "d85c8df4ed5129144bce91567967d8cd9bd901562a8d89da7521727847d67844"
TANK_SELECTED_HELMET_VARIANT = "helmet_refinement_v6"
FIRST_INTEGRATION_BASE_SHA256 = "45ce003f7eac9ab1464b44bc314eb5f7ab7cbe7985a6ab0480021110f68a4df9"
FIRST_NATIVE_RETRIES = {
    "hydra": {"head": ("original_integration_v2_head", "edit_target_previous_attempt")},
    "strike": {"head": ("original_integration_v3_head", "edit_target_original_attempt")},
    "titan": {"head": ("original_integration_v2_head", "edit_target_previous_attempt"),
              "hand": ("original_integration_v2_hand", "edit_target_previous_attempt")},
}
TITAN_FIRST_V1_SNAPSHOT_SHA256 = "9a04729f9df7c23134eb377bf22f9e0d9580e824dda7949992d65a400d860009"
FIRST_INTEGRATIONS = {
    "hydra": {"id": 3, "snapshot_sha256": "a7b7060b098baa898dd222317c435f3fca4101e13f105ed50b13292ea5004922",
              "node_index_sha256": "2fee186378990fb528b7ccfdddcf2dc555151a7a1804e0a407b767f88b680388",
              "triangles": 760, "coordinates": 726},
    "strike": {"id": 4, "snapshot_sha256": "e2f7bacad42e4525de219f682b12ddb75cdd32d22e14f394692ed7b1ebe51533",
               "node_index_sha256": "a91476b5e3afdca7aea1cf65462ffdd0b43a2276167caa21d7b5ae467bb4401e",
               "triangles": 722, "coordinates": 709},
    "titan": {"id": 5, "snapshot_sha256": "1d2883a7123e3297245ee9845569335981d82f26842b661ca98393fd6a3ff0cc",
              "node_index_sha256": "ec6be5fe46fc753ed75c850e95d088f5ed6e961af0170995af95cb2b00a116da",
              "triangles": 700, "coordinates": 1607},
}


def read(path: Path) -> dict | list:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_generation(name: str, runtime: Path, assets: Path, base: str,
                      baseline_atlases: Path | None = None) -> list[dict]:
    if name == "viper":
        generation = read(runtime / "revisions/style_unified_v9/generation_inputs.json")
        entries = generation["entries"]
    else:
        entries = [row for row in read(runtime / "generation_inputs.json") if row.get("selected")]
    assert len(entries) == 5 and {row["label"] for row in entries} == LABELS
    results = []
    for row in entries:
        label = row["label"]
        prompt = ROOT / row.get("prompt_path", row.get("prompt"))
        text = prompt.read_text(encoding="utf-8")
        declared_base = row.get("base_prompt", "docs/art/armor_style_unification_v1/base_prompt.txt")
        allowed_bases = {"docs/art/armor_style_unification_v1/base_prompt.txt"}
        if name == "fortune" and label == "head" and row.get("variant", "").startswith("helmet_refinement_"):
            allowed_bases.add("docs/art/armor_style_unification_v1/helmet_refinement_prompt.txt")
        tank_head_refinement = name == "tank" and label == "head" and row.get("variant") == TANK_SELECTED_HELMET_VARIANT
        if tank_head_refinement:
            allowed_bases = {"docs/art/armor_style_unification_v1/tank_helmet_refinement_prompt.txt"}
        assert declared_base in allowed_bases, f"{name}/{label}: unauthorized prompt contract"
        required = (ROOT / declared_base).read_text(encoding="utf-8")
        assert required in text, f"{name}/{label}: full mandatory prompt missing"
        if row.get("base_prompt_sha256"):
            assert digest(ROOT / declared_base) == row["base_prompt_sha256"]
        if row.get("prompt_sha256"):
            assert digest(prompt) == row["prompt_sha256"]
        if name == "tank":
            assert row["variant"] == (TANK_SELECTED_HELMET_VARIANT if tank_head_refinement else "style_unified_v2")
            assert row["base_prompt_sha256"] == digest(ROOT / declared_base)
            assert row["prompt_sha256"] == digest(prompt)
            assert row["additional_uv_changes"] == 0
            if not tank_head_refinement:
                assert row["additional_geometry_changes"] == 0
            assert row["user_authorized_engineering_limit"] == TANK_USER_CEILING
        assert "image_gen" in row.get("generator", row.get("tool", ""))
        archive = ROOT / row.get("output_path", row.get("archive"))
        canonical = assets / f"{label}_diffuse.png"
        native = Path(row.get("original_generation_path", row.get("generated_file")))
        expected = row.get("output_sha256", row.get("sha256"))
        assert digest(canonical) == digest(archive) == expected
        # The archived native output is portable; the generator's original
        # local path need not exist after cloning on another computer.
        if native.is_file():
            assert digest(native) == expected
        raw = canonical.read_bytes()
        assert raw[:8] == b"\x89PNG\r\n\x1a\n"
        dimensions = [int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big")]
        assert dimensions == row["dimensions"] and dimensions[0] == dimensions[1]
        baseline = (baseline_atlases or WORK / "before" / name / "atlases") / f"{label}_diffuse.png"
        assert digest(canonical) != digest(baseline), f"{name}/{label}: unchanged texture"
        if row.get("input_paths"):
            assert len(row["input_paths"]) == len(row["input_sha256"])
            for path, expected_input in zip(row["input_paths"], row["input_sha256"]):
                assert digest(ROOT / path) == expected_input
            target_digest = row["input_sha256"][0]
        else:
            for reference in row["references"]:
                assert digest(ROOT / Path(reference.get("snapshot", reference["path"]))) == reference["sha256"]
            target_digest = row["references"][0]["sha256"]
            if name == "tank":
                assert row["references"][0]["role"] == ("edit_target_previous_attempt" if tank_head_refinement else "edit_target")
                assert len(row["reference_images"]) == len(row["references"])
                assert all(reference["path"] == actual for reference, actual in zip(row["references"], row["reference_images"]))
        if name == "fortune" and label == "head" and row.get("variant", "").startswith("helmet_refinement_"):
            # Each refinement edits the previous rejected native atlas; verify
            # the actual full chain back to the frozen v7, not the old v6.
            all_entries = read(runtime / "generation_inputs.json")
            ancestors = {item["sha256"]: item for item in all_entries
                         if item.get("variant", "").startswith("helmet_refinement_")}
            v7_digest = digest(FORTUNE_V7 / "atlases/head_diffuse.png")
            seen = {expected}
            traversed_variants = []
            while target_digest != v7_digest:
                assert target_digest not in seen, "Cycle in helmet edit chain"
                seen.add(target_digest)
                parent = ancestors[target_digest]
                traversed_variants.append(parent["variant"])
                assert not parent.get("selected")
                assert parent["label"] == "head" and "image_gen" in parent["tool"]
                assert parent["base_prompt"] == declared_base
                assert parent["base_prompt_sha256"] == digest(ROOT / declared_base)
                assert digest(ROOT / parent["archive"]) == parent["sha256"]
                parent_native = Path(parent["generated_file"])
                if parent_native.is_file():
                    assert digest(parent_native) == parent["sha256"]
                parent_prompt = ROOT / parent["prompt"]
                assert required in parent_prompt.read_text(encoding="utf-8")
                assert digest(parent_prompt) == parent["prompt_sha256"]
                for reference in parent["references"]:
                    assert digest(Path(reference.get("snapshot", reference["path"]))) == reference["sha256"]
                target_digest = parent["references"][0]["sha256"]
            assert row["variant"] == "helmet_refinement_v11"
            assert traversed_variants == ["helmet_refinement_v10", "helmet_refinement_v9", "helmet_refinement_v8"]
        elif tank_head_refinement:
            assert row["base_prompt_sha256"] == TANK_HELMET_BASE_SHA256
            all_entries = read(runtime / "generation_inputs.json")
            for variant in ["helmet_refinement_v5", "helmet_refinement_v4", "helmet_refinement_v3"]:
                parents = [parent for parent in all_entries if parent.get("variant") == variant and parent["sha256"] == target_digest]
                assert len(parents) == 1, f"Tank v6 lineage missing {variant} native parent"
                parent = parents[0]
                assert parent["label"] == "head" and not parent.get("selected") and "image_gen" in parent["tool"]
                assert parent["base_prompt"] == declared_base and parent["base_prompt_sha256"] == TANK_HELMET_BASE_SHA256
                assert digest(ROOT / parent["archive"]) == parent["sha256"]
                native_parent = Path(parent["generated_file"])
                if native_parent.is_file():
                    assert digest(native_parent) == parent["sha256"]
                parent_prompt = ROOT / parent["prompt"]
                assert required in parent_prompt.read_text(encoding="utf-8") and digest(parent_prompt) == parent["prompt_sha256"]
                assert parent["references"][0]["role"] == ("edit_target" if variant == "helmet_refinement_v3" else "edit_target_previous_attempt")
                for reference in parent["references"]:
                    assert digest(ROOT / Path(reference.get("snapshot", reference["path"]))) == reference["sha256"]
                target_digest = parent["references"][0]["sha256"]
            assert target_digest == digest(TANK_STYLE_V2 / "atlases/head_diffuse.png"), "Tank v3 did not originate from immutable v2"
        else:
            assert target_digest == digest(baseline), f"{name}/{label}: wrong edit target"
        results.append({"label": label, "canonical_sha256": expected, "dimensions": dimensions,
                        "native_generator_path_available": native.is_file(),
                        "prompt": prompt.relative_to(ROOT).as_posix(), "postprocessing": "none; native PNG bytes"})
    return results


def verify_fortune_refinement(runtime: Path, target: dict) -> dict:
    """Independently measure the explicitly allowed head positions only."""
    previous = read(FORTUNE_V7 / "delivery/target.json")
    source = read(runtime / "build/source.json")
    before_manifest = read(WORK / "before/fortune/delivery/manifest.json")
    source_path = (runtime / "build/source.json").relative_to(ROOT).as_posix()
    assert digest(runtime / "build/source.json") == before_manifest["asset_sha256"][source_path]
    assert set(target["parts"]) == set(previous["parts"]) == set(source["parts"])
    changed = 0
    incremental_max = 0.0
    original_max = 0.0
    original_positions = []
    current_positions = []
    for part, authored in target["parts"].items():
        if part != "ArmorHead_01":
            assert authored == previous["parts"][part], f"{part}: changed outside head scope"
            continue
        old_surfaces = previous["parts"][part]["surfaces"]
        src_surfaces = source["parts"][part]["surfaces"]
        assert len(authored["surfaces"]) == len(old_surfaces) == len(src_surfaces) == 1
        for current, old, src in zip(authored["surfaces"], old_surfaces, src_surfaces):
            assert {k: v for k, v in current.items() if k != "positions"} == {k: v for k, v in old.items() if k != "positions"}
            assert len(current["positions"]) == len(old["positions"]) == len(src["positions"])
            assert current["uv"] == old["uv"], "Additional head UV edit"
            changed_uv = sum(math.dist(a, b) > 1e-6 for a, b in zip(current["uv"], src["uv"]))
            assert changed_uv == 22 and len(current["uv"]) == len(src["uv"]) == 157
            for point, before, original in zip(current["positions"], old["positions"], src["positions"]):
                distance = math.dist(point, before)
                changed += int(distance > 1e-6)
                incremental_max = max(incremental_max, distance)
                original_max = max(original_max, math.dist(point, original))
                original_positions.append(original)
                current_positions.append(point)
    sizes = lambda rows: [max(p[i] for p in rows) - min(p[i] for p in rows) for i in range(3)]
    original_sizes, current_sizes = sizes(original_positions), sizes(current_positions)
    total_fraction = original_max / min(original_sizes)
    dimension_fractions = [abs(b / a - 1) for a, b in zip(original_sizes, current_sizes)]
    assert changed > 0, "Requested shape refinement was not applied"
    assert total_fraction <= .15 and max(dimension_fractions) <= .15, "Original total geometry budget exceeded"
    geometry = read(runtime / "build/geometry.json")
    head = geometry["parts"]["ArmorHead_01"]
    assert head["uv_changed_count"] == 22 and head["uv_coordinate_count"] == 157
    assert head["uv_charts"] == head["original_uv_charts"] == 4
    assert head["uv_changed_fraction"] <= .15
    assert head["shape_quality"]["reversed_triangles"] == 0
    assert head["shape_quality"]["zero_area_triangles"] == 0
    assert head["shape_quality"]["coincident_seam_max_rest_gap"] < 2e-6
    assert abs(head["max_displacement_fraction_of_smallest_dimension"] - total_fraction) < 1e-5
    return {"scope": "head positions only; all additional UV edits forbidden", "added_geometry_changes": changed,
            "added_uv_changes": 0, "incremental_head_vertex_max_displacement_m": incremental_max,
            "original_head_vertex_max_displacement_fraction": total_fraction,
            "original_head_dimension_delta_fractions": dimension_fractions,
            "original_head_uv_changed_count": 22, "original_head_uv_count": 157,
            "target_parts_exactly_equal_prepass": False,
            "head_uv_and_non_head_parts_exactly_equal_v7": True}


def verify_tank_snapshots() -> dict:
    """Keep Tank's separate baseline fixed without widening the old 52/56 sets."""
    snapshot_path = TANK_BEFORE / "snapshot.json"
    assert digest(snapshot_path) == TANK_SNAPSHOT_SHA256, "Tank frozen path/SHA manifest changed"
    snapshot = read(snapshot_path)
    assert len(snapshot["files"]) == 319
    assert snapshot["current_user_authorized_ceiling"] == TANK_USER_CEILING
    for relative, row in snapshot["files"].items():
        frozen = TANK_BEFORE / relative
        assert frozen.resolve().is_relative_to(TANK_BEFORE.resolve())
        assert digest(frozen) == row["sha256"], f"Tank immutable file changed: {relative}"
        assert frozen.stat().st_size == row["bytes"]

    # Every shared comparison copy must match the independent runtime freeze,
    # rather than whatever happens to be in a live capture directory later.
    expected: dict[str, tuple[str, Path]] = {}
    for label in LABELS:
        expected[f"before/tank/atlases/{label}_diffuse.png"] = ("before", TANK_BEFORE / f"atlases/{label}_diffuse.png")
    for suffix in SUFFIXES:
        expected[f"before/tank/review/{suffix}.png"] = ("before", TANK_BEFORE / f"review/engine/new_{suffix}.png")
        expected[f"original/tank/review/{suffix}.png"] = ("original", TANK_BEFORE / f"review/engine/original_{suffix}.png")
    for filename in ["tank.scn", "tank.glb", "tank_master.blend", "target.json", "geometry.json", "manifest.json"]:
        frozen = TANK_BEFORE / ("manifest.json" if filename == "manifest.json" else f"delivery/{filename}")
        expected[f"before/tank/delivery/{filename}"] = ("before", frozen)
    for filename in ["runtime_test.json", "roundtrip_test.json", "proportion_test.json", "delivery_validate.json", "capture.json"]:
        frozen = TANK_BEFORE / ("review/engine/capture.json" if filename == "capture.json" else f"review/{filename}")
        expected[f"before/tank/reports/{filename}"] = ("reports", frozen)
    shared = read(WORK / "tank_baseline_snapshot.json")
    prefix = WORK.relative_to(ROOT).as_posix() + "/"
    assert len(shared["records"]) == len(expected) == 46
    assert {row["snapshot"] for row in shared["records"]} == {prefix + relative for relative in expected}
    assert shared["counts"] == {"before": 26, "original": 15, "reports": 5}
    for row in shared["records"]:
        kind, frozen = expected[row["snapshot"].removeprefix(prefix)]
        assert row["armor"] == "tank" and row["kind"] == kind
        assert digest(ROOT / row["snapshot"]) == row["sha256"] == digest(frozen)
        assert (ROOT / row["snapshot"]).stat().st_size == row["bytes"] == frozen.stat().st_size
    return {"runtime_snapshot_records_verified": 319, "shared_snapshot_records_verified": 46,
            "runtime_snapshot_sha256": TANK_SNAPSHOT_SHA256}


def verify_tank_original_budget(runtime: Path) -> dict:
    """Measure unchanged authored cages against the true original, not a revision."""
    for filename in ["source.json", "target.json", "geometry.json"]:
        assert (runtime / "build" / filename).read_bytes() == (TANK_BEFORE / "delivery" / filename).read_bytes(), f"Tank changed {filename} in a paint-only pass"
    source = read(runtime / "build/source.json")
    target = read(runtime / "build/target.json")
    geometry = read(runtime / "build/geometry.json")
    names = {f"Armor{part}_02" for part in ["Head", "Body", "Hand", "Foot"]}
    assert set(source["parts"]) == set(target["parts"]) == set(geometry["parts"]) == names
    assert target["id"] == 2 and target["revision"] == "tank_runtime_v1"
    assert len(source["bones"]) == 28
    measurements = []
    surface_count = triangle_count = coordinate_count = chart_count = 0
    for name, original in source["parts"].items():
        authored = target["parts"][name]
        assert len(original["surfaces"]) == len(authored["surfaces"])
        original_points, current_points = [], []
        part_count = part_changed = part_triangles = 0
        surface_rows = []
        for sid, (old, new) in enumerate(zip(original["surfaces"], authored["surfaces"])):
            assert len(old["positions"]) == len(new["positions"]) == len(old["uv"]) == len(new["uv"])
            assert all(len(p) == 3 and all(math.isfinite(value) for value in p) for p in old["positions"] + new["positions"])
            assert all(len(uv) == 2 and all(math.isfinite(value) for value in uv) for uv in old["uv"] + new["uv"])
            changed = sum(math.dist(a, b) > 1e-6 for a, b in zip(old["uv"], new["uv"]))
            fraction = changed / len(old["uv"])
            assert fraction <= TANK_DELIVERY_LIMIT, f"Tank {name}/{sid}: inherited UV budget exceeded"
            assert len(old["indices"]) % 3 == 0
            tris = len(old["indices"]) // 3
            surface_rows.append({"surface": sid, "label": new["label"], "uv_count": len(new["uv"]),
                                 "changed_original_uv_count": changed, "changed_original_uv_fraction": fraction})
            original_points.extend(old["positions"])
            current_points.extend(new["positions"])
            part_count += len(old["uv"])
            part_changed += changed
            part_triangles += tris
            surface_count += 1
        sizes = lambda rows: [max(p[axis] for p in rows) - min(p[axis] for p in rows) for axis in range(3)]
        old_size, new_size = sizes(original_points), sizes(current_points)
        assert min(old_size) > 0
        dimensions = [abs(after / before - 1) for before, after in zip(old_size, new_size)]
        maximum = max(math.dist(a, b) for a, b in zip(original_points, current_points))
        fraction = maximum / min(old_size)
        assert max(dimensions) <= TANK_DELIVERY_LIMIT and fraction <= TANK_DELIVERY_LIMIT
        measured = geometry["parts"][name]
        assert measured["uv_coordinate_count"] == measured["original_uv_coordinate_count"] == part_count
        assert measured["uv_changed_count"] == part_changed and measured["triangles"] == part_triangles
        assert measured["uv_charts"] == measured["original_uv_charts"]
        assert abs(measured["max_displacement_fraction_of_smallest_dimension"] - fraction) < 1e-7
        assert all(abs(a - b) < 1e-7 for a, b in zip(dimensions, measured["dimension_delta_fraction"]))
        assert len(measured["uv_by_surface"]) == len(surface_rows)
        for checked, reported in zip(surface_rows, measured["uv_by_surface"]):
            assert reported["surface"] == checked["surface"] and reported["label"] == checked["label"]
            assert reported["uv_coordinate_count"] == checked["uv_count"]
            assert reported["uv_changed_count"] == checked["changed_original_uv_count"]
            assert abs(reported["uv_changed_fraction"] - checked["changed_original_uv_fraction"]) < 1e-7
        measurements.append({"part": name, "original_max_rest_displacement_fraction": fraction,
                             "original_dimension_delta_fractions": dimensions, "surfaces": surface_rows})
        coordinate_count += part_count
        triangle_count += part_triangles
        chart_count += measured["uv_charts"]
    assert (surface_count, triangle_count, coordinate_count, chart_count) == (6, 796, 731, 20)
    return {"scope": "Tank texture painting only; all authored geometry and UV bytes exact to its own frozen runtime baseline",
            "user_authorized_original_ceiling": TANK_USER_CEILING,
            "actual_delivery_original_limit": TANK_DELIVERY_LIMIT,
            "added_geometry_changes": 0, "added_uv_changes": 0,
            "target_parts_exactly_equal_prepass": True, "triangles": triangle_count,
            "surfaces": surface_count, "uv_coordinates": coordinate_count, "uv_charts": chart_count,
            "original_measurements": measurements}


def uv_chart_count(surfaces: list[dict]) -> int:
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


def measure_original_geometry(source: dict, target: dict, geometry: dict,
                              limits: dict[str, float]) -> dict:
    """Measure each source surface directly; revision-to-revision budgets do not add."""
    assert set(source["parts"]) == set(target["parts"]) == set(geometry["parts"]) == set(limits)
    measurements = []
    triangles = coordinates = charts = surfaces = 0
    for name, original in source["parts"].items():
        authored = target["parts"][name]
        assert len(original["surfaces"]) == len(authored["surfaces"])
        points_before, points_after, edited_surfaces = [], [], []
        changed_count = part_coordinates = part_triangles = 0
        surface_rows = []
        for sid, (old, new) in enumerate(zip(original["surfaces"], authored["surfaces"])):
            count = len(old["positions"])
            assert count > 0 and count == len(new["positions"]) == len(old["uv"]) == len(new["uv"])
            assert all(len(p) == 3 and all(math.isfinite(value) for value in p) for p in old["positions"] + new["positions"])
            assert all(len(uv) == 2 and all(math.isfinite(value) for value in uv) for uv in old["uv"] + new["uv"])
            assert len(old["indices"]) % 3 == 0 and all(isinstance(index, int) and 0 <= index < count for index in old["indices"])
            changed = sum(math.dist(a, b) > 1e-6 for a, b in zip(old["uv"], new["uv"]))
            assert changed / count <= limits[name], f"{name}/{sid}: original-total UV limit exceeded"
            def area(coords, indices):
                a, b, c = [coords[index] for index in indices]
                return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            for start in range(0, len(old["indices"]), 3):
                indices = old["indices"][start:start + 3]
                before, after = area(old["uv"], indices), area(new["uv"], indices)
                assert abs(before) <= 1e-8 or before * after > 0, f"{name}/{sid}: folded UV triangle"
            surface_rows.append({"surface": sid, "label": new["label"], "uv_coordinate_count": count,
                                 "uv_changed_count": changed, "uv_changed_fraction": changed / count})
            points_before.extend(old["positions"])
            points_after.extend(new["positions"])
            edited_surfaces.append({**old, "uv": new["uv"]})
            changed_count += changed
            part_coordinates += count
            part_triangles += len(old["indices"]) // 3
            surfaces += 1
        dimensions = lambda rows: [max(point[i] for point in rows) - min(point[i] for point in rows) for i in range(3)]
        original_size, authored_size = dimensions(points_before), dimensions(points_after)
        assert min(original_size) > 0
        deltas = [abs(new / old - 1) for old, new in zip(original_size, authored_size)]
        max_displacement = max(math.dist(a, b) for a, b in zip(points_before, points_after))
        fraction = max_displacement / min(original_size)
        assert max(deltas) <= limits[name] and fraction <= limits[name], f"{name}: original-total shape limit exceeded"
        original_charts, current_charts = uv_chart_count(original["surfaces"]), uv_chart_count(edited_surfaces)
        assert original_charts == current_charts, f"{name}: UV chart count changed"
        reported = geometry["parts"][name]
        assert reported["triangles"] == part_triangles
        assert reported["uv_coordinate_count"] == reported["original_uv_coordinate_count"] == part_coordinates
        assert reported["uv_changed_count"] == changed_count
        assert reported["original_uv_charts"] == reported["uv_charts"] == original_charts
        assert abs(reported["uv_changed_fraction"] - changed_count / part_coordinates) < 1e-7
        assert abs(reported["max_displacement_fraction_of_smallest_dimension"] - fraction) < 1e-7
        assert len(reported["dimension_delta_fraction"]) == 3
        assert all(abs(a - b) < 1e-7 for a, b in zip(deltas, reported["dimension_delta_fraction"]))
        assert len(reported["uv_by_surface"]) == len(surface_rows)
        for measured, row in zip(surface_rows, reported["uv_by_surface"]):
            assert all(row[key] == value for key, value in measured.items() if key != "uv_changed_fraction")
            assert abs(row["uv_changed_fraction"] - measured["uv_changed_fraction"]) < 1e-7
        measurements.append({"part": name, "original_total_limit": limits[name],
                             "original_max_rest_displacement_fraction": fraction,
                             "original_dimension_delta_fractions": deltas,
                             "original_uv_changed_fraction": changed_count / part_coordinates,
                             "surfaces": surface_rows})
        triangles += part_triangles
        coordinates += part_coordinates
        charts += original_charts
    return {"original_measurements": measurements, "triangles": triangles,
            "surfaces": surfaces, "uv_coordinates": coordinates, "uv_charts": charts}


def verify_tank_head_refinement(runtime: Path) -> dict:
    source = read(runtime / "build/source.json")
    target = read(runtime / "build/target.json")
    previous = read(TANK_STYLE_V2 / "delivery/target.json")
    assert (runtime / "build/source.json").read_bytes() == (TANK_STYLE_V2 / "delivery/source.json").read_bytes() == (TANK_BEFORE / "delivery/source.json").read_bytes()
    assert len(source["bones"]) == 28
    assert {key: value for key, value in target.items() if key != "parts"} == {key: value for key, value in previous.items() if key != "parts"}
    assert set(target["parts"]) == set(previous["parts"])
    changed, incremental_max = 0, 0.0
    for name, current in target["parts"].items():
        old = previous["parts"][name]
        if name != "ArmorHead_02":
            assert current == old, f"Tank refinement changed {name} outside head scope"
            continue
        assert {key: value for key, value in current.items() if key != "surfaces"} == {key: value for key, value in old.items() if key != "surfaces"}
        assert len(current["surfaces"]) == len(old["surfaces"]) == 2
        assert current["surfaces"][1] == old["surfaces"][1], "Tank shared neck surface changed"
        head, old_head = current["surfaces"][0], old["surfaces"][0]
        assert {key: value for key, value in head.items() if key != "positions"} == {key: value for key, value in old_head.items() if key != "positions"}, "Tank additional UV/label edit"
        assert len(head["positions"]) == len(old_head["positions"]) == 149
        for point, before in zip(head["positions"], old_head["positions"]):
            delta = math.dist(point, before)
            changed += int(delta > 1e-6)
            incremental_max = max(incremental_max, delta)
    assert changed > 0, "Tank requested head shape refinement was not applied"
    geometry = read(runtime / "build/geometry.json")
    assert geometry["stage"] == "helmet_refinement_v3"
    assert geometry["user_authorized_original_total_head_limit"] == TANK_USER_CEILING
    limits = {name: TANK_USER_CEILING if name == "ArmorHead_02" else TANK_DELIVERY_LIMIT for name in source["parts"]}
    measured = measure_original_geometry(source, target, geometry, limits)
    assert (measured["surfaces"], measured["triangles"], measured["uv_coordinates"], measured["uv_charts"]) == (6, 796, 731, 20)
    return {"scope": "Tank head surface 0 positions/normals refinement; original-total head limit20%, all additional UV and non-head geometry edits forbidden",
            "user_authorized_original_ceiling": TANK_USER_CEILING,
            "actual_delivery_original_limit": TANK_USER_CEILING,
            "added_geometry_changes": changed, "added_uv_changes": 0,
            "incremental_head_vertex_max_displacement_m": incremental_max,
            "target_parts_exactly_equal_prepass": False,
            "head_uv_shared_neck_and_non_head_parts_exactly_equal_style_v2": True, **measured}


def verify_tank_style_v2_history() -> dict:
    """Verify the completed paint-only delivery as history, never as current."""
    index = TANK_STYLE_V2 / "snapshot.json"
    assert digest(index) == TANK_STYLE_V2_SNAPSHOT_SHA256, "Tank v2 immutable index changed"
    snapshot = read(index)
    assert len(snapshot["files"]) == 73
    assert snapshot["user_authorized_original_total_limit"] == TANK_USER_CEILING
    for relative, row in snapshot["files"].items():
        path = TANK_STYLE_V2 / relative
        assert path.resolve().is_relative_to(TANK_STYLE_V2.resolve())
        assert digest(path) == row["sha256"] and path.stat().st_size == row["bytes"]
    shared_index = TANK_SHARED_STYLE_V2 / "snapshot.json"
    assert digest(shared_index) == TANK_SHARED_STYLE_V2_SNAPSHOT_SHA256, "Tank v2 comparison history index changed"
    shared = read(shared_index)
    assert len(shared["records"]) == shared["record_count"] == 52
    assert shared["runtime_snapshot_sha256"] == TANK_STYLE_V2_SNAPSHOT_SHA256
    assert shared["added_geometry_changes"] == shared["added_uv_changes"] == 0
    for row in shared["records"]:
        path = TANK_SHARED_STYLE_V2 / row["snapshot"]
        assert path.resolve().is_relative_to(TANK_SHARED_STYLE_V2.resolve())
        assert digest(path) == row["sha256"] and path.stat().st_size == row["bytes"]
    for filename in ["source.json", "target.json", "geometry.json"]:
        assert (TANK_STYLE_V2 / "delivery" / filename).read_bytes() == (TANK_BEFORE / "delivery" / filename).read_bytes(), "Tank v2 history ceased to be paint-only"
    scene_sha = digest(TANK_STYLE_V2 / "delivery/tank.scn")
    target_sha = digest(TANK_STYLE_V2 / "delivery/target.json")
    source_sha = digest(TANK_STYLE_V2 / "delivery/source.json")
    geometry_sha = digest(TANK_STYLE_V2 / "delivery/geometry.json")
    master_sha = digest(TANK_STYLE_V2 / "delivery/tank_master.blend")
    image_sha = {label: digest(TANK_STYLE_V2 / f"atlases/{label}_diffuse.png") for label in LABELS}
    old_base = TANK_SHARED_STYLE_V2 / "prompts/base_prompt.txt"
    assert digest(old_base) == digest(WORK / "base_prompt.txt"), "Old common prompt changed"
    entries = [row for row in read(TANK_STYLE_V2 / "generation_inputs.json") if row.get("selected")]
    assert len(entries) == 5 and {row["label"] for row in entries} == LABELS
    for row in entries:
        label = row["label"]
        assert row["variant"] == "style_unified_v2" and "image_gen" in row["tool"]
        assert row["additional_geometry_changes"] == row["additional_uv_changes"] == 0
        prompt = TANK_STYLE_V2 / f"prompts/{label}_diffuse_style_unified_v2.txt"
        assert old_base.read_text(encoding="utf-8") in prompt.read_text(encoding="utf-8")
        assert digest(prompt) == row["prompt_sha256"] and row["base_prompt_sha256"] == digest(old_base)
        assert row["sha256"] == image_sha[label] == digest(TANK_STYLE_V2 / f"generated/{label}_diffuse_style_unified_v2.png")
        assert row["references"][0]["role"] == "edit_target"
        assert row["references"][0]["sha256"] == digest(TANK_BEFORE / f"atlases/{label}_diffuse.png")
        for reference in row["references"]:
            assert digest(ROOT / Path(reference.get("snapshot", reference["path"]))) == reference["sha256"]
        native = Path(row["generated_file"])
        if native.is_file():
            assert digest(native) == row["sha256"]
    reports = {name: read(TANK_STYLE_V2 / f"review/{name}.json") for name in [
        "style_pass_invariants", "style_pass_scene_invariants", "delivery_validate", "runtime_test", "roundtrip_test", "glb_images_test", "proportion_test"]}
    for name, report in reports.items():
        assert report["status"] == "PASS" and not report.get("errors", report.get("failures", [])), f"Tank v2 historical report failed: {name}"
    inv, scn = reports["style_pass_invariants"], reports["style_pass_scene_invariants"]
    for report, records_key in [(inv, "scene_records"), (scn, "records")]:
        assert report["current_scene_sha256"] == scene_sha
        assert report["before_scene_sha256"] == digest(TANK_BEFORE / "delivery/tank.scn")
        assert report["source_sha256"] == source_sha and report["target_sha256"] == target_sha and report["geometry_sha256"] == geometry_sha
        assert report["additional_vertex_position_changes"] == report["additional_uv_changes"] == 0
        assert report["material_parameters_preserved"]
        assert len(report[records_key]) == 4 and sum(row["surfaces"] for row in report[records_key]) == 6
        assert all(row["all_mesh_arrays_transform_skeleton_skin_material_parameters_exact"] for row in report[records_key])
    assert inv["master_sha256"] == master_sha and inv["baseline_snapshot_sha256"] == TANK_SNAPSHOT_SHA256
    assert inv["scene_invariants_sha256"] == digest(TANK_STYLE_V2 / "review/style_pass_scene_invariants.json")
    master = reports["delivery_validate"]
    assert master["master_sha256"] == master_sha and master["source_sha256"] == source_sha and master["target_sha256"] == target_sha
    assert master["uv_count_limit"] == master["local_geometry_change_limit"] == TANK_DELIVERY_LIMIT
    assert set(master["images"]) == LABELS
    for label, expected in image_sha.items():
        packed = master["images"][label]
        assert packed["canonical_sha256"] == packed["packed_sha256"] == expected and packed["byte_identical"]
        glb = reports["glb_images_test"]["images"][label]
        assert glb["canonical_sha256"] == expected and glb["pixels_equal"] and glb["max_channel_error_8bit"] == 0
    assert reports["glb_images_test"]["glb_sha256"] == reports["roundtrip_test"]["glb_sha256"] == digest(TANK_STYLE_V2 / "delivery/tank.glb")
    assert reports["glb_images_test"]["shared_head_hand_image_verified"]
    assert reports["runtime_test"]["runtime_scene_sha256"] == reports["roundtrip_test"]["runtime_scene_sha256"] == scene_sha
    assert reports["runtime_test"]["target_sha256"] == reports["roundtrip_test"]["target_sha256"] == target_sha
    assert len(reports["runtime_test"]["poses"]) == 15 and len(reports["roundtrip_test"]["poses"]) == 9
    assert reports["proportion_test"]["limit"] == TANK_DELIVERY_LIMIT
    assert reports["proportion_test"]["geometry"] == read(TANK_STYLE_V2 / "delivery/geometry.json")
    capture = read(TANK_STYLE_V2 / "review/capture.json")
    assert capture["scene_sha256_at_start"] == capture["runtime_scene_sha256"] == scene_sha
    assert capture["target_sha256_at_start"] == capture["target_sha256"] == target_sha
    assert capture["canonical_diffuse_sha256_at_start"] == image_sha and capture["resource_mode"] == "normal_imported_resources"
    assert len(capture["files"]) == len(capture["capture_sha256"]) == 64
    for suffix in SUFFIXES:
        source = f"res://docs/art/tank_runtime_v1/review/engine/new_{suffix}.png"
        assert digest(TANK_SHARED_STYLE_V2 / f"review/{suffix}.png") == capture["capture_sha256"][source]
    historical_after = read(TANK_SHARED_STYLE_V2 / "metadata/after_snapshot.json")
    assert len(historical_after["records"]) == 15 and {row["view"] for row in historical_after["records"]} == set(SUFFIXES)
    for row in historical_after["records"]:
        assert digest(TANK_SHARED_STYLE_V2 / f"review/{row['view']}.png") == row["sha256"]
    return {"runtime_records_verified": 73, "comparison_records_verified": 52,
            "status": "historical paint-only delivery verified", "added_geometry_changes": 0, "added_uv_changes": 0,
            "runtime_snapshot_sha256": TANK_STYLE_V2_SNAPSHOT_SHA256,
            "comparison_snapshot_sha256": TANK_SHARED_STYLE_V2_SNAPSHOT_SHA256}


def verify_titan_v1_history(runtime: Path) -> dict:
    """Keep the actual completed v1 immutable through head/hand atlas retries."""
    frozen = runtime / "revisions/first_integration_v1_before_head_hand_refinement"
    assert digest(frozen / "snapshot.json") == TITAN_FIRST_V1_SNAPSHOT_SHA256
    snapshot = read(frozen / "snapshot.json")
    expected = {
        "generation_inputs.json", "manifest.json", "README.md", "index.html", "runtime_config.json",
        *("delivery/" + name for name in ["titan.scn", "titan.glb", "source.json", "target.json", "geometry.json", "titan_master.blend", "glb_bind_aliases.json"]),
        *(f"delivery/{label}_diffuse.png" for label in LABELS),
        *("review/" + name for name in ["delivery_validate.json", "failed_scene_reencoding_history.json", "glb_images_test.json", "original_scene_invariants.json", "proportion_test.json", "roundtrip_test.json", "runtime_test.json", "original_integration_angle_capture.log"]),
        "review/engine/capture.json",
        *("review/engine/" + name for name in EXPECTED_CAPTURE_NAMES),
    }
    assert len(snapshot["files"]) == len(expected) == 90 and set(snapshot["files"]) == expected
    for relative, record in snapshot["files"].items():
        path = frozen / relative
        assert path.resolve().is_relative_to(frozen.resolve())
        assert digest(path) == record["sha256"] and path.stat().st_size == record["bytes"]
    # v2 is an atlas correction: the original v1 geometry and UV remain locked.
    for filename in ["source.json", "target.json", "geometry.json"]:
        assert digest(runtime / "build" / filename) == digest(frozen / "delivery" / filename)
    for label in ["body", "shoulder", "foot"]:
        assert digest(ROOT / f"assets/armors/titan_v1/{label}_diffuse.png") == digest(frozen / f"delivery/{label}_diffuse.png")
    return {"titan_first_v1_snapshot_records_verified": 90,
            "titan_first_v1_snapshot_sha256": TITAN_FIRST_V1_SNAPSHOT_SHA256,
            "titan_v2_additional_geometry_uv_changes": 0}


def verify_first_source(name: str) -> tuple[dict, dict]:
    """Validate each first integration against its own immutable true source."""
    spec = FIRST_INTEGRATIONS[name]
    runtime = ROOT / f"docs/art/{name}_runtime_v1"
    frozen = runtime / "revisions/original_source_v1"
    assert digest(frozen / "snapshot.json") == spec["snapshot_sha256"]
    snapshot = read(frozen / "snapshot.json")
    assert len(snapshot["files"]) == 13 and snapshot["runtime_id"] == spec["id"]
    expected_files = {"source.json", "runtime_config.json", "scripts/inspect_sources.gd",
                      *(f"atlases/{label}.png" for label in LABELS), *(f"guides/{label}_uv.svg" for label in LABELS)}
    assert set(snapshot["files"]) == expected_files
    for relative, record in snapshot["files"].items():
        path = frozen / relative
        assert path.resolve().is_relative_to(frozen.resolve())
        assert digest(path) == record["sha256"] and path.stat().st_size == record["bytes"]
    assert (runtime / "build/source.json").read_bytes() == (frozen / "source.json").read_bytes()
    source = read(frozen / "source.json")
    nodes = {f"Armor{part}_{spec['id']:02d}": 42 + (spec["id"] - 3) * 4 + index
             for index, part in enumerate(["Head", "Body", "Hand", "Foot"])}
    assert set(source["parts"]) == set(snapshot["used_nodes"]) == set(nodes)
    original = ROOT / source["original_scene"].removeprefix("res://")
    assert original == ROOT / "assets/models/player/animated/player.gltf"
    assert digest(original) == source["original_scene_sha256"] == snapshot["original_scene_sha256"]
    index_path = frozen / "source_node_index.json"
    assert digest(index_path) == spec["node_index_sha256"]
    index = read(index_path)
    assert index["original_source_snapshot_sha256"] == spec["snapshot_sha256"]
    assert index["runtime_id"] == spec["id"] and index["node_ids"] == nodes
    assert index["original_gltf_sha256"] == digest(original)
    gltf = read(original)
    for node, number in nodes.items():
        assert gltf["nodes"][number] == index["gltf_node_records"][node]
        assert gltf["nodes"][number]["name"] == node
        assert gltf["nodes"][number]["extras"]["armor_id"] == spec["id"]
    assert len(index["buffers"]) == len(gltf["buffers"])
    for buffer, descriptor in zip(index["buffers"], gltf["buffers"]):
        assert buffer["uri"] == descriptor["uri"] and buffer["byteLength"] == descriptor["byteLength"]
        path = original.parent / buffer["uri"]
        assert path.resolve().is_relative_to(original.parent.resolve())
        assert digest(path) == buffer["sha256"] and path.stat().st_size == buffer["byteLength"]
    bone_names = [bone["name"] for bone in source["bones"]]
    assert len(bone_names) == len(set(bone_names)) == 28
    for bone in source["bones"]:
        assert -1 <= bone["parent"] < 28
        assert len(bone["matrix"]) == 4 and all(len(row) == 4 and all(math.isfinite(v) for v in row) for row in bone["matrix"])
    for node, part in source["parts"].items():
        assert part["skin_binds"] == len(part["bind_records"])
        for surface in part["surfaces"]:
            count = len(surface["positions"])
            assert all(len(surface[field]) == count for field in ["uv", "weights", "bone_names", "bone_indices", "raw_positions", "normals"])
            for weights, names, indices in zip(surface["weights"], surface["bone_names"], surface["bone_indices"]):
                assert len(weights) == len(names) == len(indices) == 4
                # Original Godot arrays retain 16-bit weight quantization;
                # never normalize them and thereby change the source identity.
                assert all(math.isfinite(w) and 0 <= w <= 1 for w in weights) and abs(sum(weights) - 1) <= 4 / 65535 + 1e-6
                assert all(item in bone_names for item in names)
                assert all(isinstance(item, int) and 0 <= item < part["skin_binds"] for item in indices)
    config = read(runtime / "runtime_config.json")
    frozen_config = read(frozen / "runtime_config.json")
    for key in ["runtime_id", "parts", "original_triangles", "original_bones", "original_surface_count", "original_uv_coordinate_count", "texture_slots"]:
        assert config[key] == frozen_config[key]
    assert config["slug"] == name and config["runtime_id"] == spec["id"]
    assert config["original_node_ids"] == nodes and config["source_node_index_sha256"] == spec["node_index_sha256"]
    assert config["original_total_geometry_limit"] == config["original_total_uv_changed_fraction_per_surface_limit"] == .20
    assert config["original_triangles"] == spec["triangles"] and config["original_uv_coordinate_count"] == spec["coordinates"]
    assert config["original_bones"] == 28 and config["original_surface_count"] == 5
    assert set(config["texture_slots"]) == LABELS
    for label, slot in config["texture_slots"].items():
        surface = source["parts"][slot["node"]]["surfaces"][slot["surface"]]
        assert surface["texture"].removeprefix("res://") == slot["original_texture"]
        assert digest(ROOT / slot["original_texture"]) == digest(frozen / f"atlases/{label}.png") == slot["original_sha256"]
        assert len(surface["uv"]) == slot["coordinates"] and uv_chart_count([surface]) == slot["charts"]
        assert len(surface["indices"]) // 3 == slot["triangles"]
    history = verify_titan_v1_history(runtime) if name == "titan" else {}
    return source, {"original_source_snapshot_records_verified": 13,
                    "original_source_snapshot_sha256": spec["snapshot_sha256"],
                    "original_node_index_sha256": spec["node_index_sha256"], "used_node_ids": nodes, **history}


def verify_first_generation(name: str, runtime: Path, assets: Path) -> list[dict]:
    base_path = WORK / "armor_runtime_integration_prompt.txt"
    assert digest(base_path) == FIRST_INTEGRATION_BASE_SHA256, "First integration prompt contract changed"
    base = base_path.read_text(encoding="utf-8")
    rows = [row for row in read(runtime / "generation_inputs.json") if row.get("selected")]
    assert len(rows) == 5 and {row["label"] for row in rows} == LABELS
    images = []
    for row in rows:
        label = row["label"]
        retry = FIRST_NATIVE_RETRIES[name].get(label)
        expected_variant, target_role = retry or ("original_integration_v1", "edit_target")
        assert row["variant"] == expected_variant and "image_gen" in row["tool"]
        assert row["base_prompt"] == base_path.relative_to(ROOT).as_posix() and row["base_prompt_sha256"] == digest(base_path)
        prompt = ROOT / row["prompt"]
        assert base in prompt.read_text(encoding="utf-8") and digest(prompt) == row["prompt_sha256"]
        assert row["user_authorized_engineering_limit"] == .20
        assert row["references"][0]["role"] == target_role
        target_sha = row["references"][0]["sha256"]
        if retry:
            parents = [parent for parent in read(runtime / "generation_inputs.json")
                       if parent["label"] == label and parent["variant"] == "original_integration_v1" and parent["archive_sha256"] == target_sha]
            assert len(parents) == 1, f"{name}/{label}: retry missing rejected immutable v1 native parent"
            parent = parents[0]
            if name == "titan":
                assert parent["archive_sha256"] == digest(runtime / f"revisions/first_integration_v1_before_head_hand_refinement/delivery/{label}_diffuse.png")
            assert not parent.get("selected") and "image_gen" in parent["tool"]
            assert parent["base_prompt"] == row["base_prompt"] and parent["base_prompt_sha256"] == FIRST_INTEGRATION_BASE_SHA256
            assert parent["user_authorized_engineering_limit"] == .20
            assert digest(ROOT / parent["archive"]) == parent["archive_sha256"]
            parent_raw = (ROOT / parent["archive"]).read_bytes()
            assert parent_raw[:8] == b"\x89PNG\r\n\x1a\n"
            parent_dimensions = [int.from_bytes(parent_raw[16:20], "big"), int.from_bytes(parent_raw[20:24], "big")]
            assert parent_dimensions == parent["output_size"] and parent_dimensions[0] == parent_dimensions[1]
            parent_native = Path(parent["generated_file"])
            if parent_native.is_file():
                assert digest(parent_native) == parent["archive_sha256"]
            parent_prompt = ROOT / parent["prompt"]
            assert base in parent_prompt.read_text(encoding="utf-8") and digest(parent_prompt) == parent["prompt_sha256"]
            assert parent["references"][0]["role"] == "edit_target"
            assert len(parent["reference_images"]) == len(parent["references"])
            for reference, actual_path in zip(parent["references"], parent["reference_images"]):
                assert reference["path"] == actual_path
                assert digest(ROOT / Path(reference.get("snapshot", reference["path"]))) == reference["sha256"]
            target_sha = parent["references"][0]["sha256"]
        assert target_sha == digest(runtime / f"revisions/original_source_v1/atlases/{label}.png")
        if name == "strike" and label == "head":
            # v3 deliberately edits v1 again. Its rejected v2 is an actual
            # fourth reference, not an edit parent; keep both histories exact.
            assert row["archive_sha256"] == "07a4243cc973748b08417fabedc7150f3258de9c17f7b5d208a478c92c9cccbf"
            assert len(row["references"]) == 4 and row["references"][3]["role"] == "rejected_previous_attempt"
            rejected_rows = [candidate for candidate in read(runtime / "generation_inputs.json")
                             if candidate["label"] == "head" and candidate["variant"] == "original_integration_v2_head"]
            assert len(rejected_rows) == 1
            rejected = rejected_rows[0]
            assert not rejected.get("selected") and rejected["archive_sha256"] == row["references"][3]["sha256"]
            assert "image_gen" in rejected["tool"] and rejected["user_authorized_engineering_limit"] == .20
            assert rejected["base_prompt"] == row["base_prompt"] and rejected["base_prompt_sha256"] == FIRST_INTEGRATION_BASE_SHA256
            assert digest(ROOT / rejected["archive"]) == rejected["archive_sha256"]
            rejected_native = Path(rejected["generated_file"])
            if rejected_native.is_file():
                assert digest(rejected_native) == rejected["archive_sha256"]
            rejected_prompt = ROOT / rejected["prompt"]
            assert digest(rejected_prompt) == rejected["prompt_sha256"] and base in rejected_prompt.read_text(encoding="utf-8")
            assert rejected["references"][0]["role"] == "edit_target_previous_attempt"
            assert rejected["references"][0]["sha256"] == row["references"][0]["sha256"]
            assert len(rejected["references"]) == len(rejected["reference_images"])
            for reference, actual_path in zip(rejected["references"], rejected["reference_images"]):
                assert reference["path"] == actual_path
                assert digest(ROOT / Path(reference.get("snapshot", reference["path"]))) == reference["sha256"]
        assert len(row["reference_images"]) == len(row["references"])
        for reference, actual_path in zip(row["references"], row["reference_images"]):
            assert reference["path"] == actual_path
            assert digest(ROOT / Path(reference.get("snapshot", reference["path"]))) == reference["sha256"]
        canonical, archive, native = assets / f"{label}_diffuse.png", ROOT / row["archive"], Path(row["generated_file"])
        expected_sha = row["archive_sha256"]
        assert digest(canonical) == digest(archive) == expected_sha
        if "sha256" in row:
            assert row["sha256"] == expected_sha
        if native.is_file():
            assert digest(native) == expected_sha
        raw = canonical.read_bytes()
        assert raw[:8] == b"\x89PNG\r\n\x1a\n"
        dimensions = [int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big")]
        assert dimensions == row["output_size"] and dimensions[0] == dimensions[1]
        if "dimensions" in row:
            assert row["dimensions"] == dimensions
        assert digest(canonical) != digest(runtime / f"revisions/original_source_v1/atlases/{label}.png")
        images.append({"label": label, "canonical_sha256": expected_sha, "dimensions": dimensions,
                       "native_generator_path_available": native.is_file(), "prompt": row["prompt"],
                       "postprocessing": "none; native PNG bytes"})
    return images


def verify_first_integration(name: str) -> dict:
    """Shared current-delivery checks for a first integration, not a paint-only pass."""
    source, snapshot = verify_first_source(name)
    spec = FIRST_INTEGRATIONS[name]
    runtime, assets = ROOT / f"docs/art/{name}_runtime_v1", ROOT / f"assets/armors/{name}_v1"
    target, geometry = read(runtime / "build/target.json"), read(runtime / "build/geometry.json")
    assert target["id"] == spec["id"] and target["revision"] == f"{name}_runtime_v1"
    assert geometry["stage"] == "original_integration_v1" and geometry["user_authorized_original_total_limit"] == .20
    measured = measure_original_geometry(source, target, geometry, {part: .20 for part in source["parts"]})
    assert (measured["triangles"], measured["surfaces"], measured["uv_coordinates"]) == (spec["triangles"], 5, spec["coordinates"])
    images = verify_first_generation(name, runtime, assets)
    image_sha = {row["label"]: row["canonical_sha256"] for row in images}
    paths = {"scene": assets / f"{name}.scn", "glb": assets / f"{name}.glb", "source": runtime / "build/source.json",
             "target": runtime / "build/target.json", "geometry": runtime / "build/geometry.json", "master": runtime / f"build/{name}_master.blend"}
    hashes = {key: digest(path) for key, path in paths.items()}
    filenames = {"runtime": "runtime_test.json", "roundtrip": "roundtrip_test.json", "master": "delivery_validate.json",
                 "proportion": "proportion_test.json", "glb_images": "glb_images_test.json", "scene": "original_scene_invariants.json"}
    reports = {label: read(runtime / "review" / filename) for label, filename in filenames.items()}
    for label, report in reports.items():
        assert report["status"] == "PASS" and not report.get("errors", report.get("failures", [])), f"{name}: failed {label}"
    scene = reports["scene"]
    for label in ["source", "target", "geometry"]:
        assert scene[f"{label}_sha256"] == hashes[label]
    assert scene["current_scene_sha256"] == hashes["scene"]
    assert scene["original_source_snapshot_sha256"] == spec["snapshot_sha256"]
    assert scene["original_node_ids"] == snapshot["used_node_ids"] and scene["original_bones"] == 28
    assert len(scene["records"]) == 4 and {row["part"] for row in scene["records"]} == set(source["parts"])
    assert sum(row["surfaces"] for row in scene["records"]) == 5
    assert all(row["indices_skin_weights_bones_topology_exact"] and row["rest_position_uv_verified_against_target"] for row in scene["records"])
    master = reports["master"]
    for label in ["master", "source", "target", "geometry"]:
        assert master[f"{label}_sha256"] == hashes[label]
    assert master["original_source_snapshot_sha256"] == spec["snapshot_sha256"]
    assert master["original_node_ids"] == snapshot["used_node_ids"] and master["original_topology_indices_weights_rig_verified"]
    assert master["original_metrics"] == measured
    assert (master["mesh_count"], master["surface_count"], master["bone_count"], master["triangle_count"], master["packed_diffuse_count"]) == (4, 5, 28, spec["triangles"], 5)
    assert master["original_uv_coordinate_count"] == spec["coordinates"]
    assert master["uv_count_limit"] == master["local_geometry_change_limit"] == .20
    assert master["uv_count_scope"] == "per_material_surface" and set(master["images"]) == LABELS
    for label, expected in image_sha.items():
        packed = master["images"][label]
        assert packed["byte_identical"] and packed["canonical_sha256"] == packed["packed_sha256"] == expected
    runtime_report, roundtrip = reports["runtime"], reports["roundtrip"]
    for report in [runtime_report, roundtrip]:
        assert report["runtime_scene_sha256"] == hashes["scene"] and report["target_sha256"] == hashes["target"]
        assert report["save_unchanged"]
    assert len(runtime_report["poses"]) == 15 and len(roundtrip["poses"]) == 9
    assert runtime_report["limits"] == {"local_geometry_change_fraction": .20, "uv_changed_coordinate_fraction": .20, "uv_count_scope": "per_material_surface"}
    assert roundtrip["glb_sha256"] == hashes["glb"] and roundtrip["original_bones"] == 28 and roundtrip["bind_aliases"] == 0
    head = roundtrip["head_atlas_pixels"]
    assert head["status"] == "PASS" and head["canonical_sha256"] == image_sha["head"]
    assert head["codec_rgb_error_limit"] == .05 and head["max_rgb_error"] <= .05
    assert len(head["samples"]) == 30 and all(row["max_rgb_error"] <= .05 for row in head["samples"])
    glb = reports["glb_images"]
    assert glb["glb_sha256"] == hashes["glb"] and set(glb["images"]) == LABELS
    assert glb["source_sha256"] == hashes["source"] and glb["target_sha256"] == hashes["target"]
    assert glb["original_source_snapshot_sha256"] == spec["snapshot_sha256"] and glb["original_node_ids"] == snapshot["used_node_ids"]
    assert glb["original_bones"] == 28 and glb["original_topology_skin_weights_verified"]
    assert len(glb["primitives"]) == 5 and sum(row["original_triangle_count"] for row in glb["primitives"]) == spec["triangles"]
    assert {row["label"] for row in glb["primitives"]} == LABELS
    assert all(row["original_triangle_uv_skin_weight_identity_verified"] and row["max_uv_error"] <= 1e-6 and row["max_normalized_weight_error"] <= 2e-6 for row in glb["primitives"])
    for image in images:
        decoded = glb["images"][image["label"]]
        assert decoded["canonical_sha256"] == image["canonical_sha256"] and decoded["dimensions"] == image["dimensions"]
        assert decoded["pixels_equal"] and decoded["max_channel_error_8bit"] == 0
        assert decoded["compared_rgb_pixels"] == math.prod(image["dimensions"])
    proportion = reports["proportion"]
    assert proportion["geometry"] == geometry and proportion["limit"] == .20
    assert len(proportion["silhouettes"]) == 4 and {row["view"] for row in proportion["silhouettes"]} == {"front", "quarter", "side", "rear"}
    assert all(row["camera_identical"] and row["silhouette_changed_fraction"] <= .20 for row in proportion["silhouettes"])
    capture = read(runtime / "review/engine/capture.json")
    assert capture["runtime_scene_sha256"] == capture["scene_sha256_at_start"] == hashes["scene"]
    assert capture["target_sha256"] == capture["target_sha256_at_start"] == hashes["target"]
    assert capture["canonical_diffuse_sha256_at_start"] == image_sha
    assert capture["renderer"] == "gl_compatibility" and capture["save_unchanged"] and capture["resource_mode"] == "normal_imported_resources"
    assert capture["real_save_sha256_at_start"] == capture["real_save_sha256_at_end"]
    assert len(capture["real_save_sha256_at_start"]) == 64
    assert capture["isolated_save_path_at_end"] == f"user://{name}_v1_capture_profile.json"
    assert capture["real_save_path"] == "user://star_warfare_save.json"
    assert len(capture["files"]) == len(capture["capture_sha256"]) == 64 and set(capture["files"]) == set(capture["capture_sha256"])
    capture_prefix = f"res://docs/art/{name}_runtime_v1/review/engine/"
    assert set(capture["files"]) == {capture_prefix + filename for filename in EXPECTED_CAPTURE_NAMES}
    assert all(filename.startswith(capture_prefix) and digest(ROOT / filename.removeprefix("res://")) == capture["capture_sha256"][filename] for filename in capture["files"])
    log_path = runtime / "review/original_integration_angle_capture.log"
    log = log_path.read_text(encoding="utf-8-sig")
    assert "ANGLE" in log and "Direct3D11" in log and "ARMOR_CAPTURE_PASS files=64 save_unchanged=true" in log
    captures = []
    for suffix in SUFFIXES:
        for version, folder in [("original", "original"), ("new", "after")]:
            current, copy = runtime / f"review/engine/{version}_{suffix}.png", WORK / f"{folder}/{name}/review/{suffix}.png"
            assert digest(current) == digest(copy) == capture["capture_sha256"][capture_prefix + f"{version}_{suffix}.png"]
        captures.append({"view": suffix, "sha256": digest(WORK / f"after/{name}/review/{suffix}.png")})
    return {"name": name, "scope": "first approved-concept integration against true original source; positions/normals/UV permitted within original-total20%; topology, indices, skin, weights and 28-bone rig preserved",
            "user_authorized_original_ceiling": .20, "actual_delivery_original_limit": .20,
            "prior_runtime_zero_geometry_contract_applies": False, **snapshot, **measured,
            "images": images, "reports": {label: (runtime / "review" / filename).relative_to(ROOT).as_posix() for label, filename in filenames.items()},
            "captures": captures, "capture_execution": log_path.relative_to(ROOT).as_posix()}


def verify_tank_delivery(refinement: bool = False) -> dict:
    """Require current native images, exact cages, packed/GLB pixels and captures."""
    runtime = ROOT / "docs/art/tank_runtime_v1"
    assets = ROOT / "assets/armors/tank_v1"
    snapshots = verify_tank_snapshots()
    history = verify_tank_style_v2_history() if refinement else None
    scope = verify_tank_head_refinement(runtime) if refinement else verify_tank_original_budget(runtime)
    images = verify_generation("tank", runtime, assets, (WORK / "base_prompt.txt").read_text(encoding="utf-8"), TANK_BEFORE / "atlases")
    if refinement:
        for label in LABELS - {"head"}:
            assert digest(assets / f"{label}_diffuse.png") == digest(TANK_STYLE_V2 / f"atlases/{label}_diffuse.png"), "Tank non-head atlas changed during helmet refinement"
    invariants_filename = "helmet_refinement_invariants.json" if refinement else "style_pass_invariants.json"
    scene_filename = "helmet_refinement_scene_invariants.json" if refinement else "style_pass_scene_invariants.json"
    before_root = TANK_STYLE_V2 if refinement else TANK_BEFORE
    before_snapshot_sha = TANK_STYLE_V2_SNAPSHOT_SHA256 if refinement else TANK_SNAPSHOT_SHA256
    delivery_limit = TANK_USER_CEILING if refinement else TANK_DELIVERY_LIMIT
    reports = {}
    report_data = {}
    for label, filename in [("runtime", "runtime_test.json"), ("roundtrip", "roundtrip_test.json"),
                            ("master", "delivery_validate.json"), ("proportion", "proportion_test.json"),
                            ("invariants", invariants_filename), ("scene", scene_filename),
                            ("glb_images", "glb_images_test.json")]:
        path = runtime / "review" / filename
        row = read(path)
        assert row["status"] == "PASS" and not row.get("errors", row.get("failures", [])), f"Tank stale/failed {filename}"
        reports[label] = path.relative_to(ROOT).as_posix()
        report_data[label] = row
    current_sha = {"current_scene_sha256": digest(assets / "tank.scn"), "master_sha256": digest(runtime / "build/tank_master.blend"),
                   "source_sha256": digest(runtime / "build/source.json"), "target_sha256": digest(runtime / "build/target.json"),
                   "geometry_sha256": digest(runtime / "build/geometry.json")}
    before_sha = digest(before_root / "delivery/tank.scn")
    invariants, scene = report_data["invariants"], report_data["scene"]
    assert invariants["baseline_snapshot_sha256"] == before_snapshot_sha
    assert invariants["baseline_master_sha256"] == digest(before_root / "delivery/tank_master.blend")
    assert invariants["before_target_sha256"] == digest(before_root / "delivery/target.json")
    assert invariants["scene_invariants_sha256"] == digest(runtime / "review" / scene_filename)
    for key, expected in current_sha.items():
        assert invariants[key] == expected, f"Tank stale invariant {key}"
        if key != "master_sha256":
            assert scene[key] == expected, f"Tank stale scene {key}"
    expected_names = {f"Armor{part}_02" for part in ["Head", "Body", "Hand", "Foot"]}
    for report, key in [(invariants, "scene_records"), (scene, "records")]:
        assert report["before_scene_sha256"] == before_sha
        assert report["additional_uv_changes"] == 0
        if refinement:
            assert report["additional_vertex_position_changes"] > 0
            assert report["positions_changed_parts"] == ["ArmorHead_02"]
            assert report["allowed_geometry_scope"] == "ArmorHead_02 surface 0 positions and normals only"
        else:
            assert report["additional_vertex_position_changes"] == 0
        assert report["material_parameters_preserved"]
        assert len(report[key]) == 4 and {row["part"] for row in report[key]} == expected_names
        assert sum(row["surfaces"] for row in report[key]) == 6
        for row in report[key]:
            if refinement and row["part"] == "ArmorHead_02":
                assert row["head_surface0_positions_normals_only"] and row["head_surface1_all_arrays_exact"]
                assert row["uv_indices_weights_bone_arrays_skin_transform_material_parameters_exact"]
            else:
                assert row["all_mesh_arrays_transform_skeleton_skin_material_parameters_exact"]
    assert (invariants["packed_meshes"], invariants["packed_rigs"]) == (4, 1)
    if refinement:
        measured_head = next(row for row in scope["original_measurements"] if row["part"] == "ArmorHead_02")
        assert invariants["original_total_limit"] == TANK_USER_CEILING
        assert abs(invariants["original_max_rest_displacement_fraction"] - measured_head["original_max_rest_displacement_fraction"]) < 1e-7
        assert len(invariants["original_dimension_delta_fraction"]) == 3
        assert all(abs(a - b) < 1e-7 for a, b in zip(invariants["original_dimension_delta_fraction"], measured_head["original_dimension_delta_fractions"]))
    master = report_data["master"]
    for key in ["master_sha256", "source_sha256", "target_sha256"]:
        assert master[key] == current_sha[key]
    assert (master["mesh_count"], master["surface_count"], master["bone_count"], master["triangle_count"], master["packed_diffuse_count"]) == (4, 6, 28, 796, 5)
    assert master["uv_count_limit"] == master["local_geometry_change_limit"] == delivery_limit
    assert master["uv_count_scope"] == "per_material_surface" and set(master["images"]) == LABELS
    for image in images:
        packed = master["images"][image["label"]]
        assert packed["byte_identical"] and packed["canonical_sha256"] == packed["packed_sha256"] == image["canonical_sha256"]
    runtime_report = report_data["runtime"]
    assert runtime_report["runtime_scene_sha256"] == current_sha["current_scene_sha256"]
    assert runtime_report["target_sha256"] == current_sha["target_sha256"]
    assert len(runtime_report["poses"]) == 15 and runtime_report["save_unchanged"]
    assert runtime_report["limits"] == {"local_geometry_change_fraction": delivery_limit,
                                         "uv_changed_coordinate_fraction": delivery_limit, "uv_count_scope": "per_material_surface"}
    roundtrip = report_data["roundtrip"]
    assert roundtrip["glb_sha256"] == digest(assets / "tank.glb")
    assert roundtrip["runtime_scene_sha256"] == current_sha["current_scene_sha256"]
    assert roundtrip["target_sha256"] == current_sha["target_sha256"]
    assert len(roundtrip["poses"]) == 9 and roundtrip["original_bones"] == 28 and roundtrip["bind_aliases"] == 0
    assert roundtrip["save_unchanged"]
    assert roundtrip["head_atlas_pixels"]["status"] == "PASS"
    assert roundtrip["head_atlas_pixels"]["canonical_sha256"] == digest(assets / "head_diffuse.png")
    assert roundtrip["head_atlas_pixels"]["codec_rgb_error_limit"] == .05
    assert roundtrip["head_atlas_pixels"]["max_rgb_error"] <= .05
    assert len(roundtrip["head_atlas_pixels"]["samples"]) == 30
    assert all(sample["max_rgb_error"] <= .05 for sample in roundtrip["head_atlas_pixels"]["samples"])
    glb = report_data["glb_images"]
    assert glb["glb_sha256"] == digest(assets / "tank.glb") and set(glb["images"]) == LABELS
    assert glb["shared_head_hand_image_verified"]
    for image in images:
        packed = glb["images"][image["label"]]
        assert packed["canonical_sha256"] == image["canonical_sha256"]
        assert packed["dimensions"] == image["dimensions"]
        assert packed["pixels_equal"] and packed["max_channel_error_8bit"] == 0
        assert packed["compared_rgb_pixels"] == math.prod(image["dimensions"])
    proportion = report_data["proportion"]
    assert proportion["geometry"] == read(runtime / "build/geometry.json") and proportion["limit"] == delivery_limit
    assert len(proportion["silhouettes"]) == 4 and {row["view"] for row in proportion["silhouettes"]} == {"front", "side", "rear", "quarter"}
    assert all(row["silhouette_changed_fraction"] <= delivery_limit and row["camera_identical"] for row in proportion["silhouettes"])
    capture = read(runtime / "review/engine/capture.json")
    assert capture["runtime_scene_sha256"] == current_sha["current_scene_sha256"]
    assert capture["target_sha256"] == current_sha["target_sha256"]
    assert capture["scene_sha256_at_start"] == current_sha["current_scene_sha256"]
    assert capture["target_sha256_at_start"] == current_sha["target_sha256"]
    assert capture["canonical_diffuse_sha256_at_start"] == {image["label"]: image["canonical_sha256"] for image in images}
    assert capture["renderer"] == "gl_compatibility" and capture["save_unchanged"]
    assert capture["resource_mode"] == "normal_imported_resources"
    if refinement:
        assert capture["real_save_sha256_at_start"] == capture["real_save_sha256_at_end"]
        assert len(capture["real_save_sha256_at_start"]) == 64
        assert capture["isolated_save_path_at_end"] == "user://tank_v1_capture_profile.json"
        assert capture["real_save_path"] == "user://star_warfare_save.json"
    log_path = runtime / "review" / ("helmet_refinement_angle_capture.log" if refinement else "final_angle_capture.log")
    log = log_path.read_text(encoding="utf-8-sig")
    assert "ANGLE" in log and "Direct3D11" in log and "TANK_CAPTURE_PASS files=64" in log
    reports["capture_execution"] = log_path.relative_to(ROOT).as_posix()
    capture_prefix = (runtime / "review/engine").relative_to(ROOT).as_posix() + "/"
    assert len(capture["files"]) == len(EXPECTED_CAPTURE_NAMES) == 64
    assert set(capture["files"]) == {"res://" + capture_prefix + filename for filename in EXPECTED_CAPTURE_NAMES}
    assert set(capture["capture_sha256"]) == set(capture["files"])
    for filename in capture["files"]:
        assert digest(ROOT / filename.removeprefix("res://")) == capture["capture_sha256"][filename]
    captures = []
    for suffix in SUFFIXES:
        current = runtime / "review/engine" / f"new_{suffix}.png"
        copied = WORK / "after/tank/review" / f"{suffix}.png"
        assert digest(current) == digest(copied), f"Tank shared after view is stale: {suffix}"
        captures.append({"view": suffix, "sha256": digest(copied)})
    return {"name": "tank", **scope, **snapshots, "historical_style_v2": history, "images": images, "reports": reports, "captures": captures,
            "actual_scene_invariant_scope": scene["scope"], "scene_invariants": reports["scene"]}


def main() -> None:
    snapshot = read(WORK / "baseline_snapshot.json")
    expected_baseline = {
        f"docs/art/armor_style_unification_v1/before/{name}/{category}/{filename}"
        for name in ("viper", "fortune")
        for category, filenames in (
            ("atlases", [f"{label}_diffuse.png" for label in LABELS]),
            ("review", [f"{suffix}.png" for suffix in SUFFIXES]),
            ("delivery", [f"{name}.scn", f"{name}.glb", f"{name}_master.blend", "target.json", "geometry.json", "manifest.json"]),
        )
        for filename in filenames
    }
    assert len(snapshot["records"]) == 52
    assert {row["snapshot"] for row in snapshot["records"]} == expected_baseline
    for row in snapshot["records"]:
        assert digest(ROOT / row["snapshot"]) == row["sha256"], "Modified pre-pass snapshot"
    revision_snapshot = read(FORTUNE_V7 / "snapshot.json")
    expected_v7 = {
        f"{category}/{filename}"
        for category, filenames in (
            ("review", [f"{suffix}.png" for suffix in SUFFIXES]),
            ("delivery", ["fortune.scn", "fortune.glb", "fortune_master.blend", "target.json", "geometry.json", "glb_bind_aliases.json", "source_summary.json", "manifest.json"]),
            ("atlases", [f"{label}_diffuse.png" for label in LABELS]),
            ("prompts", ["head_diffuse_style_v7.txt", "body_diffuse_style_v3.txt", "shoulder_diffuse_style_v2.txt", "hand_diffuse_style_v2.txt", "foot_diffuse_style_v2.txt", "base_prompt_paint_only_v1.txt"]),
            ("reports", [
                "runtime_test.json", "roundtrip_test.json", "delivery_validate.json", "proportion_test.json", "glb_images_test.json", "style_pass_invariants.json", "style_visual_review.json", "final_angle_capture.log", "style_pass_invariants.log", "style_unified_build.log", "style_unified_compile.log", "style_unified_import.log", "style_unified_glb_import.log", "style_unified_runtime.log", "style_unified_roundtrip.log", "style_unified_capture.log", "style_unified_master_validate.log", "capture.json", "style_unification_validate.json", "fortune_scene_invariants.json", "comparison_before_refinement.json", "browser_validate_before_refinement.json",
            ]),
        )
        for filename in filenames
    }
    assert len(revision_snapshot["records"]) == revision_snapshot["record_count"] == 56
    assert {row["snapshot"] for row in revision_snapshot["records"]} == expected_v7
    for row in revision_snapshot["records"]:
        assert digest(FORTUNE_V7 / row["snapshot"]) == row["sha256"], "Modified Fortune v7 snapshot"
    base = (WORK / "base_prompt.txt").read_text(encoding="utf-8")
    armors = []
    for name, directory in (("viper", "viper_v2"), ("fortune", "fortune_v1")):
        runtime = ROOT / "docs/art" / ("viper_runtime_v2" if name == "viper" else "fortune_runtime_v1")
        assets = ROOT / "assets/armors" / directory
        before = read(WORK / "before" / name / "delivery/target.json")
        target = read(runtime / "build/target.json")
        if name == "fortune":
            scope = verify_fortune_refinement(runtime, target)
        else:
            assert before["parts"] == target["parts"], f"{name}: added geometry/UV changes"
            scope = {"scope": "texture surface painting only", "added_geometry_changes": 0,
                     "added_uv_changes": 0, "target_parts_exactly_equal_prepass": True}
        images = verify_generation(name, runtime, assets, base)
        reports = {}
        for label, filename in (("runtime", "runtime_test.json"), ("roundtrip", "roundtrip_test.json"),
                                ("master", "delivery_validate.json"), ("proportion", "proportion_test.json")):
            report = read(runtime / "review" / filename)
            assert report["status"] == "PASS", f"{name}/{label}: failed delivery"
            reports[label] = (runtime / "review" / filename).relative_to(ROOT).as_posix()
        runtime_report = read(runtime / "review/runtime_test.json")
        assert runtime_report["runtime_scene_sha256"] == digest(assets / f"{name}.scn")
        assert runtime_report["target_sha256"] == digest(runtime / "build/target.json")
        master_report = read(runtime / "review/delivery_validate.json")
        assert master_report["master_sha256"] == digest(runtime / "build" / f"{name}_master.blend")
        assert master_report["source_sha256"] == digest(runtime / "build/source.json")
        assert master_report["target_sha256"] == digest(runtime / "build/target.json")
        assert set(master_report["images"]) == LABELS
        for row in images:
            packed = master_report["images"][row["label"]]
            assert packed["canonical_sha256"] == packed["packed_sha256"] == row["canonical_sha256"]
            assert packed["byte_identical"]
        proportion = read(runtime / "review/proportion_test.json")
        assert proportion["geometry"] == read(runtime / "build/geometry.json")
        assert proportion["limit"] == .15
        assert all(row["silhouette_changed_fraction"] <= .15 for row in proportion["silhouettes"])
        roundtrip = read(runtime / "review/roundtrip_test.json")
        if name == "fortune":
            assert roundtrip["glb_sha256"] == digest(assets / f"{name}.glb")
            invariants_path = runtime / "review/helmet_refinement_invariants.json"
        else:
            # Viper's existing pose report has no hashes; its independently
            # decoded GLB atlas report fingerprints the current export.
            atlas_report = read(runtime / "revisions/style_unified_v9/glb_atlas_validation.json")
            assert atlas_report["status"] == "PASS"
            assert atlas_report["glb_sha256"] == digest(assets / "viper.glb")
            invariants_path = runtime / "revisions/style_unified_v9/mesh_invariants.json"
        invariants = read(invariants_path)
        assert invariants["status"] == "PASS" and not invariants.get("failures", invariants.get("errors", []))
        assert invariants["current_scene_sha256"] == digest(assets / f"{name}.scn")
        scene_before = FORTUNE_V7 / "delivery/fortune.scn" if name == "fortune" else WORK / "before" / name / "delivery" / f"{name}.scn"
        assert invariants["before_scene_sha256"] == digest(scene_before)
        if name == "fortune":
            assert invariants["master_sha256"] == master_report["master_sha256"]
            assert invariants["source_sha256"] == master_report["source_sha256"]
            assert invariants["target_sha256"] == master_report["target_sha256"]
            assert invariants["positions_changed"] == ["ArmorHead_01"]
            assert invariants["additional_uv_changes"] == 0
        capture = read(runtime / "review/engine/capture.json")
        scene_at_capture = capture.get("runtime_scene_sha256", capture.get("scene_sha256_at_start"))
        assert scene_at_capture == digest(assets / f"{name}.scn")
        maps_at_capture = capture.get("texture_sha256", capture.get("canonical_diffuse_sha256_at_start"))
        assert maps_at_capture == {row["label"]: row["canonical_sha256"] for row in images}
        captures = []
        for suffix in SUFFIXES:
            current = runtime / "review/engine" / f"new_{suffix}.png"
            copied = WORK / "after" / name / "review" / f"{suffix}.png"
            assert digest(current) == digest(copied), f"{name}/{suffix}: wrong after capture"
            captures.append({"view": suffix, "sha256": digest(copied)})
        armors.append({"name": name, **scope, "images": images,
                       "actual_scene_invariant_scope": invariants.get("scope", "all arrays, skin and material modes exact"),
                       "scene_invariants": invariants_path.relative_to(ROOT).as_posix(),
                       "reports": reports, "captures": captures})
    tank_selected = [row for row in read(ROOT / "docs/art/tank_runtime_v1/generation_inputs.json") if row.get("selected") and row["label"] == "head"]
    assert len(tank_selected) == 1
    tank_refinement = tank_selected[0]["variant"] == TANK_SELECTED_HELMET_VARIANT
    assert tank_selected[0]["variant"] in {"style_unified_v2", TANK_SELECTED_HELMET_VARIANT}
    armors.append(verify_tank_delivery(tank_refinement))
    for name in FIRST_INTEGRATIONS:
        armors.append(verify_first_integration(name))
    result = {"status": "PASS", "baseline_snapshots_verified": len(snapshot["records"]),
              "fortune_v7_snapshot_records_verified": len(revision_snapshot["records"]),
              "base_prompt_sha256": digest(WORK / "base_prompt.txt"), "armors": armors,
              "art_review": "runtime-verified first pass; pending user preference review; no objective style score"}
    historical_combined = WORK / "revisions/combined_before_first_integrations/validate.json"
    assert digest(historical_combined) == "260e4d1552092283c22c461a5b004fb766d92970f49d36125a9624b9a583da26"
    result["superseded_historical_combined_report"] = historical_combined.relative_to(ROOT).as_posix()
    result["superseded_historical_combined_report_sha256"] = digest(historical_combined)
    pending_combined = WORK / "revisions/combined_pending_first_integrations/validate.json"
    assert read(pending_combined)["status"] == "PENDING"
    result["prior_pending_combined_report"] = pending_combined.relative_to(ROOT).as_posix()
    result["prior_pending_combined_report_sha256"] = digest(pending_combined)
    (WORK / "validate.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tank_scope = "Tank head refinement within original20%, zero additional UV, immutable v2 paint-only history" if tank_refinement else "Tank paint only within original15%, user20% ceiling"
    print(f"ARMOR_DELIVERY_VALIDATE_PASS: Viper paint only; Fortune head refinement within original15%; {tank_scope}; Hydra/Strike/Titan first integration within original20%; 90 current comparison captures")


if __name__ == "__main__":
    main()
