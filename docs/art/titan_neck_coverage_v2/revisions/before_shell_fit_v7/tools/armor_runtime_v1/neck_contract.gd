extends RefCounted
## A head's original cloth tube is an equipment interface, not face geometry.
## Derive it from the ORIGINAL mesh/Skin. Never accept authored target metadata
## as evidence that the head still joins an unrelated chest correctly.

const POSITION_EPSILON := 0.000002
const MEAN_LUMINANCE_LIMIT := 0.14
const P95_CHANNEL_LIMIT := 0.26
const ALPHA_MINIMUM := 0.999

static func _finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()

static func _finite_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)

static func validate_channels(arrays: Array, skin: Skin, label: String) -> Array[String]:
	## Run before ArrayMesh upload as well as on decoded delivered arrays. GPU
	## normalized weight encoding must not sanitize NaN before it is rejected.
	var errors: Array[String] = []
	if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null or skin == null:
		return ["NECK_MESH: %s vertex channels/Skin missing" % label]
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	if count == 0 or arrays[Mesh.ARRAY_TEX_UV] == null or arrays[Mesh.ARRAY_TEX_UV].size() != count or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_BONES].size() != count * 4 or arrays[Mesh.ARRAY_WEIGHTS] == null or arrays[Mesh.ARRAY_WEIGHTS].size() != count * 4 or arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_INDEX].size() % 3 != 0:
		return ["NECK_MESH: %s incomplete UV/bone/weight/index channels" % label]
	for vertex: int in count:
		if not (arrays[Mesh.ARRAY_VERTEX][vertex] as Vector3).is_finite():
			errors.append("NECK_FINITE: %s position %d is non-finite" % [label, vertex])
		if not (arrays[Mesh.ARRAY_TEX_UV][vertex] as Vector2).is_finite():
			errors.append("NECK_FINITE: %s UV %d is non-finite" % [label, vertex])
		for influence: int in 4:
			var offset: int = vertex * 4 + influence
			if not is_finite(float(arrays[Mesh.ARRAY_WEIGHTS][offset])):
				errors.append("NECK_FINITE: %s weight %d is non-finite" % [label, offset])
			if arrays[Mesh.ARRAY_BONES][offset] < 0 or arrays[Mesh.ARRAY_BONES][offset] >= skin.get_bind_count():
				errors.append("NECK_SKIN: %s bind index %d is outside original Skin" % [label, offset])
	for index: int in arrays[Mesh.ARRAY_INDEX]:
		if index < 0 or index >= count: errors.append("NECK_MESH: %s face index outside vertex buffer" % label)
	for bind: int in skin.get_bind_count():
		if not _finite_transform(skin.get_bind_pose(bind)):
			errors.append("NECK_FINITE: %s Skin bind %d is non-finite" % [label, bind])
	return errors

static func identify(original: MeshInstance3D, surface: int = 0,
		upper_bone: String = "Bip01 Head", lower_bone: String = "Bip01 Spine1") -> Dictionary:
	var errors: Array[String] = []
	if original == null or original.mesh == null or original.skin == null:
		return {"errors": ["NECK_SOURCE: original mesh/Skin missing"]}
	if surface < 0 or surface >= original.mesh.get_surface_count():
		return {"errors": ["NECK_SOURCE: original material surface missing"]}
	var arrays: Array = original.mesh.surface_get_arrays(surface)
	errors.append_array(validate_channels(arrays, original.skin, "true-original"))
	if not _finite_transform(original.transform): errors.append("NECK_FINITE: true-original mount is non-finite")
	if not errors.is_empty(): return {"errors": errors}
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var welded: Dictionary = {}
	var physical: Array[String] = []
	var adjacent: Dictionary = {}
	for point: Vector3 in positions:
		var key := "%.4f,%.4f,%.4f" % [point.x, point.y, point.z]
		physical.append(key)
		welded[key] = true
	for offset: int in range(0, indices.size(), 3):
		for corner: int in 3:
			var a: String = physical[indices[offset + corner]]
			var b: String = physical[indices[offset + (corner + 1) % 3]]
			if not adjacent.has(a): adjacent[a] = {}
			if not adjacent.has(b): adjacent[b] = {}
			adjacent[a][b] = true
			adjacent[b][a] = true
	var candidates: Array[Dictionary] = []
	var unseen: Dictionary = welded.duplicate()
	while not unseen.is_empty():
		var first: String = str(unseen.keys()[0])
		var pending: Array[String] = [first]
		var component: Dictionary = {}
		unseen.erase(first)
		while not pending.is_empty():
			var key: String = pending.pop_back()
			component[key] = true
			for neighbor: String in adjacent.get(key, {}):
				if unseen.has(neighbor):
					unseen.erase(neighbor)
					pending.append(neighbor)
		var vertex_ids: Array[int] = []
		var lower_ids: Array[int] = []
		var used_bones: Dictionary = {}
		for vertex: int in positions.size():
			if not component.has(physical[vertex]): continue
			vertex_ids.append(vertex)
			for influence: int in 4:
				var offset: int = vertex * 4 + influence
				if arrays[Mesh.ARRAY_WEIGHTS][offset] <= 0.00001: continue
				var name_key: String = original.skin.get_bind_name(arrays[Mesh.ARRAY_BONES][offset])
				used_bones[name_key] = true
				if name_key == lower_bone: lower_ids.append(vertex)
		if used_bones.size() != 2 or not used_bones.has(upper_bone) or not used_bones.has(lower_bone): continue
		var triangles: Array[int] = []
		for offset: int in range(0, indices.size(), 3):
			if component.has(physical[indices[offset]]): triangles.append(offset / 3)
		candidates.append({"surface": surface, "vertex_ids": vertex_ids,
			"lower_interface_ids": lower_ids, "triangle_ids": triangles,
			"physical_vertices": component.size(), "upper_bone": upper_bone,
			"lower_bone": lower_bone})
	if candidates.size() != 1:
		errors.append("NECK_SOURCE: expected one isolated upper/lower bone tube, found %d" % candidates.size())
		return {"errors": errors, "candidate_count": candidates.size()}
	var result: Dictionary = candidates[0]
	result.errors = errors
	result.scope = "Original welded connected component with Head/Spine1 influences; no target metadata or vertex-ID whitelist"
	return result

static func verify(original: MeshInstance3D, actual: MeshInstance3D) -> Dictionary:
	# Keep Titan's reviewed surface-zero, opaque-charcoal policy unchanged.
	var descriptor: Dictionary = identify(original)
	return _verify_component(original, actual, descriptor, true)

static func verify_interface(original: MeshInstance3D, actual: MeshInstance3D,
		check_charcoal: bool = false) -> Dictionary:
	## Generic first-integration policy: discover every source surface, retain
	## every original tube and require opacity. Palette is a design-specific opt-in.
	var errors: Array[String] = []
	var reports: Array[Dictionary] = []
	if original == null or original.mesh == null or original.skin == null:
		errors.append("NECK_SOURCE: original mesh/Skin missing")
	else:
		for surface: int in original.mesh.get_surface_count():
			var descriptor: Dictionary = identify(original, surface)
			if int(descriptor.get("candidate_count", -1)) == 0: continue
			var component: Dictionary = _verify_component(original, actual, descriptor, check_charcoal)
			reports.append(component)
			errors.append_array(component.errors)
		if reports.is_empty(): errors.append("NECK_SOURCE: no original head-to-torso tube on any source surface; define the original interface before delivery")
	return {"status": "PASS" if errors.is_empty() else "FAIL", "errors": errors,
		"components": reports, "opaque_required": true, "charcoal_required": check_charcoal,
		"scope": "All original head surfaces are searched independently. Source tube geometry/UV/faces/named Skin and actual pixel opacity are mandatory; charcoal is a design-specific opt-in."}

static func _verify_component(original: MeshInstance3D, actual: MeshInstance3D,
		descriptor: Dictionary, check_charcoal: bool) -> Dictionary:
	var errors: Array[String] = []
	errors.assign(descriptor.errors)
	var report := {"errors": errors, "source_component": descriptor,
		"position_epsilon_m": POSITION_EPSILON, "material": {},
		"scope": "Original neck tube geometry, UV, topology, Skin and sampled opaque charcoal pixels. This does not replace mixed-pose visual inspection." if check_charcoal else "Original neck tube geometry, UV, topology, Skin and sampled opaque pixels. Palette measurements are descriptive; mixed-pose visual inspection is still required."}
	if not errors.is_empty(): return report
	if actual == null or actual.mesh == null or actual.skin == null:
		errors.append("NECK_MESH: equipped mesh/Skin missing")
		return report
	var surface: int = int(descriptor.surface)
	if surface >= actual.mesh.get_surface_count():
		errors.append("NECK_MESH: original neck material surface missing")
		return report
	var source_arrays: Array = original.mesh.surface_get_arrays(surface)
	var arrays: Array = actual.mesh.surface_get_arrays(surface)
	errors.append_array(validate_channels(arrays, actual.skin, "actual"))
	if not _finite_transform(actual.transform): errors.append("NECK_FINITE: actual mount is non-finite")
	if not errors.is_empty(): return report
	if actual.skin.get_bind_count() != original.skin.get_bind_count():
		errors.append("NECK_SKIN: original bind count changed")
	else:
		for bind: int in original.skin.get_bind_count():
			if actual.skin.get_bind_name(bind) != original.skin.get_bind_name(bind) or actual.skin.get_bind_bone(bind) != original.skin.get_bind_bone(bind) or not actual.skin.get_bind_pose(bind).is_equal_approx(original.skin.get_bind_pose(bind)):
				errors.append("NECK_SKIN: original bind/name/pose changed")
				break
	if not actual.transform.is_equal_approx(original.transform): errors.append("NECK_TRANSFORM: original mount changed")
	var maximum := 0.0
	var interface_maximum := 0.0
	for vertex: int in descriptor.vertex_ids:
		if vertex >= arrays[Mesh.ARRAY_VERTEX].size():
			errors.append("NECK_VERTEX: source tube vertex missing")
			continue
		var displacement: float = arrays[Mesh.ARRAY_VERTEX][vertex].distance_to(source_arrays[Mesh.ARRAY_VERTEX][vertex])
		maximum = maxf(maximum, displacement)
		if vertex in descriptor.lower_interface_ids: interface_maximum = maxf(interface_maximum, displacement)
		if displacement > POSITION_EPSILON: errors.append("NECK_POSITION: original tube vertex moved: %d" % vertex)
		if arrays[Mesh.ARRAY_TEX_UV][vertex].distance_to(source_arrays[Mesh.ARRAY_TEX_UV][vertex]) > 0.000001:
			errors.append("NECK_UV: original tube sampling changed: %d" % vertex)
		for influence: int in 4:
			var offset: int = vertex * 4 + influence
			if arrays[Mesh.ARRAY_BONES][offset] != source_arrays[Mesh.ARRAY_BONES][offset] or absf(arrays[Mesh.ARRAY_WEIGHTS][offset] - source_arrays[Mesh.ARRAY_WEIGHTS][offset]) > 0.000001:
				errors.append("NECK_WEIGHT: original tube deformation changed: %d" % vertex)
				break
	var actual_faces: Dictionary = {}
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for offset: int in range(0, indices.size(), 3):
		var key: String = _face_key(indices[offset], indices[offset + 1], indices[offset + 2])
		actual_faces[key] = int(actual_faces.get(key, 0)) + 1
	var source_indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
	var expected_neck_faces: Dictionary = {}
	for triangle: int in descriptor.triangle_ids:
		var offset: int = triangle * 3
		var key: String = _face_key(source_indices[offset], source_indices[offset + 1], source_indices[offset + 2])
		expected_neck_faces[key] = true
		if int(actual_faces.get(key, 0)) != 1: errors.append("NECK_FACE: original tube triangle missing/duplicated/reversed: %d" % triangle)
	for offset: int in range(0, indices.size(), 3):
		if indices[offset] not in descriptor.vertex_ids and indices[offset + 1] not in descriptor.vertex_ids and indices[offset + 2] not in descriptor.vertex_ids: continue
		var key: String = _face_key(indices[offset], indices[offset + 1], indices[offset + 2])
		if not expected_neck_faces.has(key): errors.append("NECK_FACE: new/changed triangle touches the original tube: %d" % (offset / 3))
	var material: Dictionary = _material_report(actual.get_active_material(surface), source_arrays, descriptor, check_charcoal)
	report.material = material
	errors.append_array(material.errors)
	report.maximum_original_tube_displacement_m = maximum
	report.maximum_original_body_interface_displacement_m = interface_maximum
	report.status = "PASS" if errors.is_empty() else "FAIL"
	return report

static func _face_key(a: int, b: int, c: int) -> String:
	if a <= b and a <= c: return "%d/%d/%d" % [a, b, c]
	if b <= a and b <= c: return "%d/%d/%d" % [b, c, a]
	return "%d/%d/%d" % [c, a, b]

static func _material_report(value: Material, arrays: Array, descriptor: Dictionary,
		check_charcoal: bool = true) -> Dictionary:
	var errors: Array[String] = []
	var report := {"errors": errors, "samples": 0, "mean_luminance_limit": MEAN_LUMINANCE_LIMIT,
		"p95_max_rgb_limit": P95_CHANNEL_LIMIT, "alpha_minimum": ALPHA_MINIMUM,
		"charcoal_required": check_charcoal,
		"sampling": "Actual equipped texture pixels at a 9-step barycentric grid inside every original neck UV triangle; both raw atlas and tinted albedo must remain charcoal, so tint cannot conceal gray paint" if check_charcoal else "Actual equipped texture pixels at a 9-step barycentric grid inside every original neck UV triangle; opacity is mandatory and raw/tinted palette measurements are descriptive"}
	var material := value as BaseMaterial3D
	if material == null or material.albedo_texture == null:
		errors.append("NECK_MATERIAL: readable BaseMaterial3D diffuse required")
		return report
	if not _finite_color(material.albedo_color) or not material.uv1_scale.is_finite() or not material.uv1_offset.is_finite():
		errors.append("NECK_FINITE: material tint/UV transform is non-finite")
		return report
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_color.a < ALPHA_MINIMUM:
		errors.append("NECK_OPACITY: material permits transparent neck")
	if material.uv1_scale != Vector3.ONE or material.uv1_offset != Vector3.ZERO or material.vertex_color_use_as_albedo:
		errors.append("NECK_SAMPLING: unsupported UV transform or vertex-color multiplier")
	var image: Image = material.albedo_texture.get_image()
	if image == null or image.is_empty():
		errors.append("NECK_MATERIAL: equipped diffuse cannot be decoded")
		return report
	if image.is_compressed() and image.decompress() != OK:
		errors.append("NECK_MATERIAL: equipped diffuse decompression failed")
		return report
	var logical := Vector2i(material.albedo_texture.get_size())
	if logical.x <= 0 or logical.y <= 0 or image.get_width() < logical.x or image.get_height() < logical.y:
		errors.append("NECK_MATERIAL: invalid decoded/logical texture dimensions")
		return report
	var samples: Dictionary = {}
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for triangle: int in descriptor.triangle_ids:
		var offset: int = triangle * 3
		for a: int in range(1, 9):
			for b: int in range(1, 10 - a):
				var c: int = 10 - a - b
				var point: Vector2 = (uv[indices[offset]] * a + uv[indices[offset + 1]] * b + uv[indices[offset + 2]] * c) / 10.0
				var pixel := Vector2i(clampi(roundi(point.x * (logical.x - 1)), 0, logical.x - 1), clampi(roundi(point.y * (logical.y - 1)), 0, logical.y - 1))
				samples[pixel] = true
	var channels: Array[float] = []
	var raw_channels: Array[float] = []
	var luminance_total := 0.0
	var raw_luminance_total := 0.0
	var minimum_alpha := 1.0
	for pixel: Vector2i in samples:
		var raw_color: Color = image.get_pixelv(pixel)
		var color: Color = raw_color * material.albedo_color
		if not _finite_color(raw_color) or not _finite_color(color):
			errors.append("NECK_FINITE: sampled material pixel is non-finite")
			return report
		channels.append(maxf(color.r, maxf(color.g, color.b)))
		raw_channels.append(maxf(raw_color.r, maxf(raw_color.g, raw_color.b)))
		luminance_total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
		raw_luminance_total += raw_color.r * 0.2126 + raw_color.g * 0.7152 + raw_color.b * 0.0722
		minimum_alpha = minf(minimum_alpha, color.a)
	channels.sort()
	raw_channels.sort()
	if channels.is_empty():
		errors.append("NECK_MATERIAL: no original triangle-interior samples")
		return report
	var mean: float = luminance_total / channels.size()
	var raw_mean: float = raw_luminance_total / raw_channels.size()
	var p95: float = channels[mini(channels.size() - 1, floori(channels.size() * 0.95))]
	var raw_p95: float = raw_channels[mini(raw_channels.size() - 1, floori(raw_channels.size() * 0.95))]
	if minimum_alpha < ALPHA_MINIMUM: errors.append("NECK_OPACITY: sampled tube pixels are transparent")
	if check_charcoal and (maxf(mean, raw_mean) > MEAN_LUMINANCE_LIMIT or maxf(p95, raw_p95) > P95_CHANNEL_LIMIT): errors.append("NECK_CHARCOAL: sampled tube is too light/gray for the black undersuit")
	report.samples = channels.size()
	report.logical_texture_size = [logical.x, logical.y]
	report.mean_luminance = mean
	report.p95_max_rgb = p95
	report.raw_mean_luminance = raw_mean
	report.raw_p95_max_rgb = raw_p95
	report.minimum_alpha = minimum_alpha
	report.texture_path = material.albedo_texture.resource_path
	return report

static func posed_vertices(part: MeshInstance3D, skeleton: Skeleton3D, vertex_ids: Array) -> PackedVector3Array:
	var arrays: Array = part.mesh.surface_get_arrays(0)
	var transforms: Array[Transform3D] = []
	for bind: int in part.skin.get_bind_count():
		var bone: int = skeleton.find_bone(part.skin.get_bind_name(bind))
		transforms.append(skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
	var result := PackedVector3Array()
	for vertex: int in vertex_ids:
		var point := Vector3.ZERO
		for influence: int in 4:
			var offset: int = vertex * 4 + influence
			point += (transforms[arrays[Mesh.ARRAY_BONES][offset]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * arrays[Mesh.ARRAY_WEIGHTS][offset]
		result.append(part.transform * point)
	return result

static func snapshot_state(state: Node) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in state.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var value: Variant = state.get(str(property.name))
		result[str(property.name)] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

static func restore_state(state: Node, snapshot: Dictionary) -> void:
	for key: String in snapshot:
		var value: Variant = snapshot[key]
		state.set(key, value.duplicate(true) if value is Dictionary or value is Array else value)
