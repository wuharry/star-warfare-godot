extends "res://tools/armor_runtime_v1/mixed_neck_capture.gd"
## Negative fixtures modify only ephemeral arrays and ImageTextures in memory.
## No generated artwork, source scene, runtime mesh or authored target is edited.

const BEFORE_HEAD_PNG := "res://docs/art/titan_neck_mix_v1/revisions/before_neck_fix/assets/armors/titan_v1/titan_head_diffuse.png"
const BEFORE_HEAD_SHA256 := "4fc63720e6fccd8a11e904ebb8afa4896bd9947c3f8d8fe4e01212405d9ba66f"
const SharedCompiler = preload("res://tools/armor_runtime_v1/compile.gd")

func _wants_images() -> bool:
	return false

func _run_negative_checks(delivered_head: MeshInstance3D) -> void:
	_check(source_component.vertex_ids.size() == 24 and source_component.triangle_ids.size() == 12,
		"NECK_SOURCE: independently derived Titan source component differs from 24 vertices / 12 triangles")
	# The production candidate may already fail. Build a known-valid ORIGINAL
	# mesh with an ephemeral dark/opaque material before corrupting each channel,
	# so an existing delivery error cannot make a broken negative test look green.
	var head: MeshInstance3D = _fixture(original_head, original_head.mesh.surface_get_arrays(0))
	var valid_material := delivered_head.get_active_material(0).duplicate() as BaseMaterial3D
	valid_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	valid_material.albedo_color = Color.WHITE
	valid_material.uv1_scale = Vector3.ONE
	valid_material.uv1_offset = Vector3.ZERO
	valid_material.vertex_color_use_as_albedo = false
	var valid_pixels := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	valid_pixels.fill(Color(0.025, 0.025, 0.025, 1))
	valid_material.albedo_texture = ImageTexture.create_from_image(valid_pixels)
	head.set_surface_override_material(0, valid_material)
	var valid_result: Dictionary = Contract.verify(original_head, head)
	_check(valid_result.errors.is_empty(), "NECK_FIXTURE: original dark/opaque positive control failed")
	var interface_ids: Array = source_component.lower_interface_ids
	_check(not interface_ids.is_empty(), "NECK_SOURCE: no original body-interface anchors")
	if interface_ids.is_empty():
		head.free()
		return
	var vertex: int = int(interface_ids[0])
	var arrays: Array = head.mesh.surface_get_arrays(0).duplicate(true)
	arrays[Mesh.ARRAY_VERTEX][vertex] += Vector3(0.003, 0, 0)
	_reject(_fixture(head, arrays), "shift_interface_3mm", "NECK_POSITION:")
	arrays = head.mesh.surface_get_arrays(0).duplicate(true)
	arrays[Mesh.ARRAY_TEX_UV][vertex] += Vector2(0.01, 0)
	_reject(_fixture(head, arrays), "shift_interface_uv", "NECK_UV:")
	arrays = head.mesh.surface_get_arrays(0).duplicate(true)
	# Keep normalized weights, but attach one lower anchor to the Head bind.
	var head_bind := -1
	for bind: int in head.skin.get_bind_count():
		if head.skin.get_bind_name(bind) == "Bip01 Head": head_bind = bind
	_check(head_bind >= 0, "NECK_SOURCE: Head bind missing")
	arrays[Mesh.ARRAY_BONES][vertex * 4] = head_bind
	arrays[Mesh.ARRAY_WEIGHTS][vertex * 4] = 1.0
	for influence: int in range(1, 4): arrays[Mesh.ARRAY_WEIGHTS][vertex * 4 + influence] = 0.0
	_reject(_fixture(head, arrays), "rebind_interface_to_head", "NECK_WEIGHT:")
	arrays = head.mesh.surface_get_arrays(0).duplicate(true)
	var raw: Array = original_head.mesh.surface_get_arrays(0)
	var triangle: int = int(source_component.triangle_ids[0]) * 3
	var original_indices: PackedInt32Array = raw[Mesh.ARRAY_INDEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var filtered := PackedInt32Array()
	var removed := false
	for offset: int in range(0, indices.size(), 3):
		var is_target: bool = indices[offset] == original_indices[triangle] and indices[offset + 1] == original_indices[triangle + 1] and indices[offset + 2] == original_indices[triangle + 2]
		if is_target and not removed:
			removed = true
			continue
		filtered.append_array(indices.slice(offset, offset + 3))
	_check(removed, "NECK_FIXTURE: source neck face not found in real delivered mesh")
	arrays[Mesh.ARRAY_INDEX] = filtered
	_reject(_fixture(head, arrays), "remove_actual_neck_triangle", "NECK_FACE:")
	arrays = head.mesh.surface_get_arrays(0).duplicate(true)
	var extended: PackedInt32Array = arrays[Mesh.ARRAY_INDEX].duplicate()
	extended.append_array(original_indices.slice(triangle, triangle + 3))
	arrays[Mesh.ARRAY_INDEX] = extended
	_reject(_fixture(head, arrays), "duplicate_actual_neck_triangle", "NECK_FACE:")
	arrays = head.mesh.surface_get_arrays(0).duplicate(true)
	extended = arrays[Mesh.ARRAY_INDEX].duplicate()
	extended.append_array(PackedInt32Array([vertex, int(source_component.vertex_ids[0]), 0]))
	arrays[Mesh.ARRAY_INDEX] = extended
	_reject(_fixture(head, arrays), "add_bridge_touching_neck_interface", "NECK_FACE:")
	arrays = head.mesh.surface_get_arrays(0).duplicate(true)
	var a: int = arrays[Mesh.ARRAY_INDEX][triangle + 1]
	arrays[Mesh.ARRAY_INDEX][triangle + 1] = arrays[Mesh.ARRAY_INDEX][triangle + 2]
	arrays[Mesh.ARRAY_INDEX][triangle + 2] = a
	_reject(_fixture(head, arrays), "reverse_actual_neck_triangle", "NECK_FACE:")
	for row: Dictionary in [{"name": "gray_neck_pixels", "color": Color(0.65, 0.65, 0.65, 1), "error": "NECK_CHARCOAL:"},
			{"name": "transparent_neck_pixels", "color": Color(0.02, 0.02, 0.02, 0), "error": "NECK_OPACITY:"}]:
		var modified: MeshInstance3D = _fixture(head, head.mesh.surface_get_arrays(0))
		var material := head.get_active_material(0).duplicate() as BaseMaterial3D
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		image.fill(row.color)
		material.albedo_texture = ImageTexture.create_from_image(image)
		modified.set_surface_override_material(0, material)
		_reject(modified, str(row.name), str(row.error))
	# Reject the ACTUAL frozen gray-neck artwork on valid original geometry,
	# independently of the historical position defect. Read PNG bytes directly;
	# never depend on an imported-resource cache or recolor this source artwork.
	_check(_hash(BEFORE_HEAD_PNG) == BEFORE_HEAD_SHA256, "NECK_FIXTURE: frozen before head atlas changed")
	_pin(BEFORE_HEAD_PNG)
	var before_pixels: Image = Image.load_from_file(ProjectSettings.globalize_path(BEFORE_HEAD_PNG))
	_check(before_pixels != null and not before_pixels.is_empty(), "NECK_FIXTURE: frozen before head atlas cannot decode")
	if before_pixels != null and not before_pixels.is_empty():
		var before_head: MeshInstance3D = _fixture(head, head.mesh.surface_get_arrays(0))
		var before_material := delivered_head.get_active_material(0).duplicate() as BaseMaterial3D
		before_material.albedo_texture = ImageTexture.create_from_image(before_pixels)
		before_head.set_surface_override_material(0, before_material)
		_reject(before_head, "actual_frozen_v5_gray_atlas_on_valid_geometry", "NECK_CHARCOAL:")
	_nonfinite_checks(head, vertex)
	_shared_interface_checks(head)
	head.free()

func _nonfinite_checks(control: MeshInstance3D, vertex: int) -> void:
	for channel: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV]:
		var arrays: Array = control.mesh.surface_get_arrays(0).duplicate(true)
		if channel == Mesh.ARRAY_VERTEX:
			arrays[channel][vertex] = Vector3(NAN, arrays[channel][vertex].y, arrays[channel][vertex].z)
		else:
			arrays[channel][vertex] = Vector2(NAN, arrays[channel][vertex].y)
		var modified: MeshInstance3D = _fixture(control, arrays)
		var decoded: Array = modified.mesh.surface_get_arrays(0)
		var retained: bool = is_nan(float(decoded[channel][vertex].x))
		var name_key: String = "actual_nan_vertex" if channel == Mesh.ARRAY_VERTEX else "actual_nan_uv"
		_check(retained, "NECK_FIXTURE: ArrayMesh did not retain " + name_key)
		_reject(modified, name_key, "NECK_FINITE:")
		negatives[-1].actual_decoded_nan_retained = retained
	# Weight storage may be quantized by the engine. Exercise the EXACT real
	# pre-upload validator, while a real PackedFloat32Array still retains NaN.
	var weight_arrays: Array = control.mesh.surface_get_arrays(0).duplicate(true)
	weight_arrays[Mesh.ARRAY_WEIGHTS][vertex * 4] = NAN
	var weight_retained: bool = is_nan(float(weight_arrays[Mesh.ARRAY_WEIGHTS][vertex * 4]))
	var weight_errors: Array[String] = Contract.validate_channels(weight_arrays, control.skin, "candidate-before-upload")
	var weight_rejected := false
	for message: String in weight_errors:
		if message.begins_with("NECK_FINITE:"): weight_rejected = true
	_check(weight_retained and weight_rejected, "NECK_FIXTURE: real NaN weight was not rejected before GPU quantization")
	negatives.append({"fixture": "real_packed_nan_weight_before_upload", "expected_error": "NECK_FINITE:",
		"stage": "same validate_channels called before ArrayMesh upload in both production compilers",
		"actual_packed_nan_retained": weight_retained, "rejected_for_independent_reason": weight_rejected, "errors": weight_errors})
	for field: String in ["mount", "skin_bind", "material_tint", "material_uv", "material_pixel"]:
		var modified: MeshInstance3D = _fixture(control, control.mesh.surface_get_arrays(0))
		var retained := false
		if field == "mount":
			var transform: Transform3D = modified.transform
			transform.origin.x = NAN
			modified.transform = transform
			retained = is_nan(modified.transform.origin.x)
		elif field == "skin_bind":
			modified.skin = control.skin.duplicate() as Skin
			var pose: Transform3D = modified.skin.get_bind_pose(0)
			pose.origin.x = NAN
			modified.skin.set_bind_pose(0, pose)
			retained = is_nan(modified.skin.get_bind_pose(0).origin.x)
		else:
			var material := control.get_active_material(0).duplicate() as BaseMaterial3D
			if field == "material_tint":
				material.albedo_color = Color(NAN, 1, 1, 1)
				retained = is_nan(material.albedo_color.r)
			elif field == "material_uv":
				material.uv1_offset = Vector3(NAN, 0, 0)
				retained = is_nan(material.uv1_offset.x)
			else:
				var pixels := Image.create(64, 64, false, Image.FORMAT_RGBAF)
				pixels.fill(Color(NAN, 0.02, 0.02, 1))
				material.albedo_texture = ImageTexture.create_from_image(pixels)
				retained = is_nan(material.albedo_texture.get_image().get_pixel(1, 1).r)
			modified.set_surface_override_material(0, material)
		_check(retained, "NECK_FIXTURE: real NaN was sanitized in " + field)
		_reject(modified, "actual_nan_" + field, "NECK_FINITE:")
		negatives[-1].actual_nan_retained = retained
	# A corrupt authority must fail too; it cannot redefine the accepted cage.
	for channel: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV]:
		var arrays: Array = control.mesh.surface_get_arrays(0).duplicate(true)
		if channel == Mesh.ARRAY_VERTEX: arrays[channel][vertex] = Vector3(NAN, 0, 0)
		else: arrays[channel][vertex] = Vector2(NAN, 0)
		var bad_source: MeshInstance3D = _fixture(control, arrays)
		var retained: bool = is_nan(float(bad_source.mesh.surface_get_arrays(0)[channel][vertex].x))
		var result: Dictionary = Contract.verify(bad_source, control)
		var rejected := false
		for message: String in result.errors:
			if message.begins_with("NECK_FINITE:") and "true-original" in message: rejected = true
		_check(retained and rejected, "NECK_FIXTURE: malformed original source was accepted")
		negatives.append({"fixture": "source_nan_vertex" if channel == Mesh.ARRAY_VERTEX else "source_nan_uv",
			"expected_error": "NECK_FINITE: true-original", "actual_decoded_nan_retained": retained,
			"rejected_for_independent_reason": rejected, "errors": result.errors})
		bad_source.free()

func _shared_interface_checks(control: MeshInstance3D) -> void:
	# The original Tank stores its cloth tube on surface ONE, while Titan uses
	# surface zero. Search all original surfaces rather than baking Titan IDs.
	for id: int in range(21):
		var part: MeshInstance3D = source.find_child("ArmorHead_%02d" % id, true, false)
		var result: Dictionary = Contract.verify_interface(part, part)
		_check(result.errors.is_empty(), "SHARED_NECK_SOURCE: valid original interface rejected for head %d" % id)
		var surfaces: Array[int] = []
		for component: Dictionary in result.components: surfaces.append(int(component.source_component.surface))
		if id == 2: _check(surfaces == [1], "SHARED_NECK_SOURCE: Tank tube must be discovered on surface one")
		shared_gate_checks.append({"check": "original_head_%02d_positive" % id,
			"accepted": result.errors.is_empty(), "source_neck_surfaces": surfaces,
			"opaque_required": result.opaque_required, "charcoal_required": result.charcoal_required})
	var pale: MeshInstance3D = _fixture(control, control.mesh.surface_get_arrays(0))
	var material := control.get_active_material(0).duplicate() as BaseMaterial3D
	var pixels := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.65, 0.65, 0.65, 1))
	material.albedo_texture = ImageTexture.create_from_image(pixels)
	pale.set_surface_override_material(0, material)
	var palette: Dictionary = Contract.verify_interface(original_head, pale)
	_check(palette.errors.is_empty(), "SHARED_NECK_PALETTE: generic opaque interface must allow a separately reviewed non-black palette")
	shared_gate_checks.append({"check": "opaque_palette_without_charcoal_optin", "accepted": palette.errors.is_empty()})
	var strict: Dictionary = Contract.verify(original_head, pale)
	_check(not strict.errors.is_empty(), "SHARED_NECK_PALETTE: Titan strict charcoal policy was weakened")
	pixels.fill(Color(0.02, 0.02, 0.02, 0))
	material.albedo_texture = ImageTexture.create_from_image(pixels)
	var alpha: Dictionary = Contract.verify_interface(original_head, pale)
	var alpha_rejected := false
	for message: String in alpha.errors:
		if message.begins_with("NECK_OPACITY:"): alpha_rejected = true
	_check(alpha_rejected, "SHARED_NECK_OPACITY: generic palette opt-out must never permit transparency")
	shared_gate_checks.append({"check": "transparent_pixels_without_charcoal_optin", "rejected": alpha_rejected})
	pale.free()
	_check_writer_rejects_before_save(control)

func _check_writer_rejects_before_save(control: MeshInstance3D) -> void:
	var arrays: Array = control.mesh.surface_get_arrays(0).duplicate(true)
	var vertex: int = int(source_component.lower_interface_ids[0])
	arrays[Mesh.ARRAY_VERTEX][vertex] = Vector3(NAN, arrays[Mesh.ARRAY_VERTEX][vertex].y, arrays[Mesh.ARRAY_VERTEX][vertex].z)
	var bad: MeshInstance3D = _fixture(control, arrays)
	var nan_retained: bool = is_nan(float(bad.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][vertex].x))
	_check(nan_retained, "SHARED_NECK_WRITER: decoded ArrayMesh must retain the NaN fixture")
	bad.name = "ArmorHead_05"
	var candidate := Node3D.new()
	candidate.add_child(bad)
	bad.owner = candidate
	var prefix := "user://armor_neck_writer_guard_%d" % Time.get_ticks_usec()
	var existing_path: String = prefix + "_existing.scn"
	var missing_path: String = prefix + "_missing.scn"
	if FileAccess.file_exists(existing_path) or FileAccess.file_exists(missing_path):
		_fail("SHARED_NECK_WRITER: unique temporary fixture path already exists")
		candidate.free()
		return
	var sentinel := FileAccess.open(existing_path, FileAccess.WRITE)
	_check(sentinel != null, "SHARED_NECK_WRITER: cannot create temporary sentinel")
	if sentinel == null:
		candidate.free()
		return
	sentinel.store_string("Original neck writer regression sentinel; must not be overwritten.\n")
	sentinel.close()
	var sentinel_hash: String = _hash(existing_path)
	var existing: Dictionary = SharedCompiler.save_checked_candidate(source, candidate,
		"ArmorHead_05", existing_path)
	var missing: Dictionary = SharedCompiler.save_checked_candidate(source, candidate,
		"ArmorHead_05", missing_path)
	var preserved: bool = not existing.wrote_scene and existing.status == "FAIL" and _hash(existing_path) == sentinel_hash
	var absent: bool = not missing.wrote_scene and missing.status == "FAIL" and not FileAccess.file_exists(missing_path)
	_check(preserved, "SHARED_NECK_WRITER: corrupt candidate overwrote an existing destination")
	_check(absent, "SHARED_NECK_WRITER: corrupt candidate created a new destination")
	shared_gate_checks.append({"check": "production_writer_rejects_corrupt_interface_before_save",
		"actual_decoded_nan_vertex_retained": nan_retained,
		"existing_destination_preserved": preserved, "missing_destination_stays_missing": absent,
		"existing_report": existing, "missing_report": missing})
	# Remove only files created at the two unique, already-checked fixture paths.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(existing_path))
	if FileAccess.file_exists(missing_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(missing_path))
	candidate.free()

func _fixture(head: MeshInstance3D, first_surface: Array) -> MeshInstance3D:
	var modified := MeshInstance3D.new()
	modified.transform = head.transform
	modified.skin = head.skin
	var mesh := ArrayMesh.new()
	for surface: int in head.mesh.get_surface_count():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			first_surface if surface == 0 else head.mesh.surface_get_arrays(surface))
		mesh.surface_set_material(surface, head.get_active_material(surface))
	modified.mesh = mesh
	return modified

func _reject(modified: MeshInstance3D, name_key: String, expected_error: String) -> void:
	var result: Dictionary = Contract.verify(original_head, modified)
	var caught := false
	for message: String in result.errors:
		if message.begins_with(expected_error): caught = true
		else: _fail("NECK_NEGATIVE: unrelated error in isolated fixture " + name_key + ": " + message)
	negatives.append({"fixture": name_key, "expected_error": expected_error,
		"rejected_for_independent_reason": caught, "errors": result.errors})
	_check(caught, "NECK_NEGATIVE: did not reject " + name_key + " for " + expected_error)
	modified.free()
