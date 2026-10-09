extends "res://tools/armor_runtime_v1/neck_exposure_capture.gd"
## Rendered negative control: an opaque blocker must really occlude the red
## source tube. A pixel count from a flat UV/position AABB cannot pass this.

func _regression_checks() -> void:
	_nonindexed_surface_regressions()
	_baseline_decode_regressions()
	_equip("current", CANDIDATE_ID, 0)
	_pose("idle")
	_camera("quarter")
	_build_diagnostic(false)
	var exposed: Image = await _image()
	var visible: int = _red_pixels(exposed)
	# Make an independent positive geometry control even if a future good
	# helmet already hides every neck pixel. Only the actual red tube remains.
	for part: MeshInstance3D in diagnostic:
		var diagnostic_material := part.mesh.surface_get_material(0) as BaseMaterial3D
		if diagnostic_material.albedo_color == Color.BLACK: part.hide()
	var unoccluded: Image = await _image()
	var tube_pixels: int = _red_pixels(unoccluded)
	_save_image(unoccluded, "regression_isolated_actual_neck.png", "positive_actual_neck_without_opaque_occluders")
	_check(tube_pixels > 0, "EXPOSURE_NEGATIVE: actual red tube positive control is empty")
	_check(visible <= tube_pixels, "EXPOSURE_NEGATIVE: opaque geometry increased the visible neck area")
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 0.05)
	blocker.mesh = box
	blocker.layers = DIAGNOSTIC_LAYER
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.BLACK
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	blocker.material_override = material
	fixture.add_child(blocker)
	blocker.global_transform = fixture.view_camera.global_transform
	blocker.global_position -= fixture.view_camera.global_basis.z
	var occluded: Image = await _image()
	var occluded_count: int = _red_pixels(occluded)
	_save_image(occluded, "regression_opaque_blocker.png", "negative_depth_occlusion_control")
	_check(occluded_count == 0, "EXPOSURE_NEGATIVE: opaque depth blocker did not hide the red neck")
	blocker.free()
	_restore_diagnostic()
	_build_diagnostic(true)
	var mask: Image = await _image()
	var full_head: int = _red_pixels(mask)
	_restore_diagnostic()
	_check(full_head > 100, "EXPOSURE_NEGATIVE: denominator must be an actual full-head render")
	_check(visible <= full_head, "EXPOSURE_NEGATIVE: visible neck cannot exceed full head")
	# Check the acceptance function with actual render-derived values, without
	# changing any frozen production threshold or claiming fixture art approval.
	var prior: Array[String] = style_failures.duplicate()
	var test_row := {"body_id": 0, "pose": "negative", "view": "quarter",
		"visible_neck_fraction": 1.0, "visible_neck_percent": 100.0}
	_accept(test_row)
	_check(test_row.style_coverage == "FAIL", "EXPOSURE_NEGATIVE: full exposure must fail the frozen peer threshold")
	style_failures.assign(prior)
	regressions.append({"check": "real_depth_occlusion_and_rendered_denominator", "actual_visible_neck_pixels": visible,
		"actual_isolated_red_tube_pixels": tube_pixels, "independent_positive_tube_nonempty": tube_pixels > 0,
		"opaque_blocker_red_pixels": occluded_count, "actual_complete_head_pixels": full_head,
		"depth_occlusion_pass": occluded_count == 0, "denominator_nonempty": full_head > 100,
		"full_exposure_rejected_without_changing_threshold": test_row.style_coverage == "FAIL"})

func _baseline_decode_regressions() -> void:
	if baseline_path.is_empty():
		_check(false, "EXPOSURE_BASELINE_TEST: render test requires a real frozen --baseline")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	var positive: Array[String] = baseline_validation_errors(parsed)
	_check(positive.is_empty(), "EXPOSURE_BASELINE_TEST: actual JSON-decoded float IDs were rejected")
	if not parsed is Dictionary or not positive.is_empty(): return
	var rejected: Array[Dictionary] = []
	for kind: String in ["string_id", "fractional_id", "reordered_ids", "reference_rows_not_array", "scalar_reference_row", "pins_not_dictionary", "missing_source_pin", "threshold_not_dictionary", "nonfinite_threshold", "candidate_widened_threshold", "clipped_reference"]:
		var bad: Dictionary = parsed.duplicate(true)
		match kind:
			"string_id": bad.reference_ids[0] = "0"
			"fractional_id": bad.reference_ids[0] = 0.25
			"reordered_ids": bad.reference_ids[0] = 1
			"reference_rows_not_array": bad.reference_measurements = "invalid"
			"scalar_reference_row": bad.reference_measurements[0] = 3
			"pins_not_dictionary": bad.reference_resource_sha256 = []
			"missing_source_pin": bad.reference_resource_sha256.erase("res://assets/models/player/animated/player.gltf")
			"threshold_not_dictionary": bad.thresholds.quarter = 0.05
			"nonfinite_threshold": bad.thresholds.quarter.maximum_fraction = NAN
			"candidate_widened_threshold": bad.thresholds.quarter.maximum_fraction += 0.01
			"clipped_reference": bad.reference_measurements[0].complete_head_unclipped = false
		var errors: Array[String] = baseline_validation_errors(bad)
		_check(not errors.is_empty(), "EXPOSURE_BASELINE_TEST: malformed baseline accepted " + kind)
		rejected.append({"fixture": kind, "rejected": not errors.is_empty(), "errors": errors})
	regressions.append({"check": "actual_json_float_id_normalization_and_strict_baseline_validation",
		"actual_frozen_json_accepted": positive.is_empty(), "negative_fixtures": rejected})

func _nonindexed_surface_regressions() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.1, 0, 0), Vector3(0.1, 0, 0), Vector3(0, 0.1, 0)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var decoded: Array = mesh.surface_get_arrays(0)
	var raw: Variant = decoded[Mesh.ARRAY_INDEX]
	var actual_nonindexed: bool = raw == null or (raw is PackedInt32Array and raw.is_empty())
	var valid: Dictionary = diagnostic_triangle_indices(decoded, mesh.surface_get_primitive_type(0))
	var sequence: PackedInt32Array = valid.indices
	var accepted: bool = actual_nonindexed and valid.errors.is_empty() and sequence.size() == 3 and sequence[0] == 0 and sequence[1] == 1 and sequence[2] == 2
	_check(accepted, "EXPOSURE_TOPOLOGY_TEST: actual nonindexed triangle mesh must generate exact 0..N-1 indices")
	var bad: Array = decoded.duplicate(true)
	bad[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	var short: Dictionary = diagnostic_triangle_indices(bad, Mesh.PRIMITIVE_TRIANGLES)
	var primitive: Dictionary = diagnostic_triangle_indices(decoded, Mesh.PRIMITIVE_LINES)
	bad = decoded.duplicate(true)
	bad[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 99])
	var outside: Dictionary = diagnostic_triangle_indices(bad, Mesh.PRIMITIVE_TRIANGLES)
	_check(not short.errors.is_empty(), "EXPOSURE_TOPOLOGY_TEST: nonindexed two-vertex triangle accepted")
	_check(not primitive.errors.is_empty(), "EXPOSURE_TOPOLOGY_TEST: nontriangle primitive accepted")
	_check(not outside.errors.is_empty(), "EXPOSURE_TOPOLOGY_TEST: out-of-bounds triangle accepted")
	regressions.append({"check": "actual_nonindexed_triangle_surface_and_invalid_topology",
		"actual_nonindexed_arraymesh": actual_nonindexed, "exact_explicit_sequence_accepted": accepted,
		"invalid_vertex_multiple_rejected": not short.errors.is_empty(), "nontriangle_primitive_rejected": not primitive.errors.is_empty(),
		"out_of_bounds_triangle_rejected": not outside.errors.is_empty()})
