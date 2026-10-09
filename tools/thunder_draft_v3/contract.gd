extends RefCounted

const GEOMETRY_LIMIT := 0.20
const SOURCE_VERTEX_COUNT := 147
const SOURCE_TRIANGLE_COUNT := 196


static func target_points(target: Dictionary, key := "positions") -> PackedVector3Array:
	var result := PackedVector3Array()
	var rows: Variant = target.get(key, [])
	if not rows is Array:
		return result
	for row: Variant in rows:
		if not row is Array or row.size() != 3:
			return PackedVector3Array()
		for value: Variant in row:
			if not value is float and not value is int:
				return PackedVector3Array()
		var point := Vector3(row[0], row[1], row[2])
		if not point.is_finite():
			return PackedVector3Array()
		result.append(point)
	return result


static func point_bounds(points: PackedVector3Array) -> AABB:
	var result := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		result = result.expand(point)
	return result


# All displacement is measured from live original source vertices, never 3ed.
static func geometry_report(source: PackedVector3Array, edited: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var errors: Array[String] = []
	if source.is_empty() or edited.size() != source.size():
		return {"errors": ["Head target vertex count changed"]}
	var source_bounds := point_bounds(source)
	var target_bounds := point_bounds(edited)
	var normalizer := minf(source_bounds.size.x, minf(source_bounds.size.y, source_bounds.size.z))
	if normalizer <= 0.0:
		return {"errors": ["Original head smallest dimension is zero"]}
	var max_displacement := 0.0
	for index: int in source.size():
		max_displacement = maxf(max_displacement, source[index].distance_to(edited[index]))
	var fraction := max_displacement / normalizer
	var dimension_changes: Array[float] = []
	for axis: int in 3:
		dimension_changes.append(absf(target_bounds.size[axis] / source_bounds.size[axis] - 1.0))
	if fraction > GEOMETRY_LIMIT + 0.000001:
		errors.append("Head displacement exceeds original 20% smallest-dimension limit")
	if max_displacement <= 0.000001:
		errors.append("Draft refinement has no actual head position changes")
	for axis: int in 3:
		if dimension_changes[axis] > GEOMETRY_LIMIT + 0.000001:
			errors.append("Head dimension exceeds original 20% limit on axis " + str(axis))
	var flips: Array[int] = []
	var degenerate: Array[int] = []
	for tri: int in indices.size() / 3:
		var a: int = indices[tri * 3]
		var b: int = indices[tri * 3 + 1]
		var c: int = indices[tri * 3 + 2]
		var original_normal := (source[b] - source[a]).cross(source[c] - source[a])
		var edited_normal := (edited[b] - edited[a]).cross(edited[c] - edited[a])
		if original_normal.length_squared() > 0.000000000001:
			if edited_normal.length_squared() <= 0.000000000001:
				degenerate.append(tri)
			elif original_normal.dot(edited_normal) <= 0.0:
				flips.append(tri)
	var seam_breaks: Array = []
	for first: int in source.size():
		for second: int in range(first):
			if source[first].distance_to(source[second]) <= 0.0000001 and edited[first].distance_to(edited[second]) > 0.000001:
				seam_breaks.append([second, first])
	if not flips.is_empty():
		errors.append("Head target flips triangles: " + str(flips))
	if not degenerate.is_empty():
		errors.append("Head target creates degenerate triangles: " + str(degenerate))
	if not seam_breaks.is_empty():
		errors.append("Head target splits original duplicate-position seams: " + str(seam_breaks))
	return {"errors": errors, "normalizer_original_smallest_dimension_m": normalizer, "max_rest_displacement": max_displacement, "max_displacement_fraction_of_smallest_dimension": fraction, "max_dimension_change_fraction": dimension_changes.max(), "dimension_change_fractions": dimension_changes, "flipped_triangles": flips, "new_degenerate_triangles": degenerate, "seam_breaks": seam_breaks}


static func validate_target(original: MeshInstance3D, target: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if original == null or original.mesh == null or original.mesh.get_surface_count() != 1:
		return ["Missing true original single-surface head"]
	var arrays := original.mesh.surface_get_arrays(0)
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var edited := target_points(target)
	if source.size() != SOURCE_VERTEX_COUNT or arrays[Mesh.ARRAY_INDEX].size() != SOURCE_TRIANGLE_COUNT * 3:
		errors.append("True original head counts are not 147 vertices / 196 triangles")
	if str(target.get("revision", "")) != "thunder_draft_v3" or str(target.get("geometry_mode", "")) != "bounded_original_head_only":
		errors.append("Wrong head target revision or geometry mode")
	if float(target.get("geometry_limit", -1)) != GEOMETRY_LIMIT:
		errors.append("Target must declare the fixed original-head 20% limit")
	if target_points(target, "source_positions") != source:
		errors.append("Target original positions do not match live original source")
	if edited.size() != source.size():
		errors.append("Target positions are not 147 finite original-indexed vertices")
		return errors
	var target_uv := PackedVector2Array()
	for row: Array in target.get("uv", []):
		if row.size() != 2:
			errors.append("Malformed target UV")
			break
		target_uv.append(Vector2(row[0], row[1]))
	if target_uv != arrays[Mesh.ARRAY_TEX_UV]:
		errors.append("Target changed original UV coordinates")
	if PackedInt32Array(target.get("indices", [])) != arrays[Mesh.ARRAY_INDEX]:
		errors.append("Target changed original triangle indices")
	if PackedInt32Array(target.get("bone_indices", [])) != arrays[Mesh.ARRAY_BONES]:
		errors.append("Target changed original bone indices")
	if PackedFloat32Array(target.get("weights", [])) != arrays[Mesh.ARRAY_WEIGHTS]:
		errors.append("Target changed original bone weights")
	if original.skin == null or original.skin.get_bind_count() != 28:
		errors.append("True original head Skin binds changed")
	else:
		var bind_rows: Array = target.get("binds", [])
		if bind_rows.size() != 28:
			errors.append("Target Skin bind count changed")
		else:
			for bind: int in 28:
				if str(bind_rows[bind].get("name", "")) != str(original.skin.get_bind_name(bind)) or int(bind_rows[bind].get("bone", -999)) != original.skin.get_bind_bone(bind) or str_to_var(str(bind_rows[bind].get("pose", ""))) != original.skin.get_bind_pose(bind):
					errors.append("Target changed original Skin bind " + str(bind))
	var metrics := geometry_report(source, edited, arrays[Mesh.ARRAY_INDEX])
	errors.append_array(metrics.errors)
	if metrics.has("normalizer_original_smallest_dimension_m") and absf(float(target.get("normalizer_original_smallest_dimension_m", -1)) - float(metrics.normalizer_original_smallest_dimension_m)) > 0.000001:
		errors.append("Target displacement normalizer was rebased")
	if metrics.has("max_displacement_fraction_of_smallest_dimension") and absf(float(target.get("max_cumulative_source_displacement_fraction", -1)) - float(metrics.max_displacement_fraction_of_smallest_dimension)) > 0.00001:
		errors.append("Target displacement metadata disagrees with original-source measurement")
	if int(target.get("uv_count", -1)) != 147 or int(target.get("triangle_count", -1)) != 196 or float(target.get("uv_changed_fraction", -1)) != 0.0:
		errors.append("Target original UV/topology summary changed")
	return errors


static func compare_head(original: MeshInstance3D, after: MeshInstance3D, target: Dictionary) -> Array[String]:
	var errors := validate_target(original, target)
	if after == null or after.mesh == null or after.mesh.get_surface_count() != 1:
		errors.append("Missing delivered single-surface head")
		return errors
	if original.transform != after.transform or original.skeleton != after.skeleton:
		errors.append("Original head transform or skeleton path changed")
	if original.skin == null or after.skin == null or original.skin.get_bind_count() != after.skin.get_bind_count():
		errors.append("Original head Skin bind count changed")
		return errors
	for bind: int in original.skin.get_bind_count():
		if original.skin.get_bind_name(bind) != after.skin.get_bind_name(bind) or original.skin.get_bind_bone(bind) != after.skin.get_bind_bone(bind) or original.skin.get_bind_pose(bind) != after.skin.get_bind_pose(bind):
			errors.append("Original head Skin bind changed at " + str(bind))
	var first := original.mesh.surface_get_arrays(0)
	var second := after.mesh.surface_get_arrays(0)
	if second[Mesh.ARRAY_VERTEX] != target_points(target):
		errors.append("Delivered head positions do not match the pinned target")
	for channel: int in Mesh.ARRAY_MAX:
		if channel not in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL] and first[channel] != second[channel]:
			errors.append(str(original.name) + ": native array channel %d changed at surface 0" % channel)
	var raw_first: Dictionary = (original.mesh.get("_surfaces") as Array)[0]
	var raw_second: Dictionary = (after.mesh.get("_surfaces") as Array)[0]
	var first_fixed := raw_first.duplicate(true)
	var second_fixed := raw_second.duplicate(true)
	for key: String in ["vertex_data", "aabb", "bone_aabbs", "material"]:
		first_fixed.erase(key)
		second_fixed.erase(key)
	if first_fixed != second_fixed:
		errors.append("Original head serialized UV/index/Skin/format buffers changed")
	if int(raw_first.format) != int(raw_second.format) or int(raw_first.vertex_count) != int(raw_second.vertex_count):
		errors.append("Original head serialized format or vertex count changed")
		return errors
	var old_bytes: PackedByteArray = raw_first.vertex_data
	var new_bytes: PackedByteArray = raw_second.vertex_data
	if old_bytes.size() != new_bytes.size():
		errors.append("Original head serialized vertex buffer size changed")
		return errors
	var count: int = raw_first.vertex_count
	var stride := RenderingServer.mesh_surface_get_format_vertex_stride(raw_first.format, count)
	var normal_offset := RenderingServer.mesh_surface_get_format_offset(raw_first.format, count, Mesh.ARRAY_NORMAL)
	var normal_stride := 8 if first[Mesh.ARRAY_TANGENT] != null and first[Mesh.ARRAY_TANGENT].size() > 0 else 4
	for index: int in old_bytes.size():
		var position_byte := index < count * stride
		var relative := index - normal_offset
		var normal_byte := relative >= 0 and relative < count * normal_stride and relative % normal_stride < 4
		if not position_byte and not normal_byte and old_bytes[index] != new_bytes[index]:
			errors.append("Original head immutable serialized vertex byte changed at " + str(index))
			break
	return errors

# Compare actual serialized surfaces, not a remeshed approximation.
static func compare_part(before: MeshInstance3D, after: MeshInstance3D, allow_material_change := false) -> Array[String]:
	var errors: Array[String] = []
	if before == null or after == null:
		errors.append("Missing compared mesh instance")
		return errors
	var label := str(before.name)
	if before.transform != after.transform:
		errors.append(label + ": transform changed")
	if before.skin == null or after.skin == null:
		errors.append(label + ": missing Skin")
		return errors
	if before.skin.get_bind_count() != after.skin.get_bind_count():
		errors.append(label + ": Skin bind count changed")
		return errors
	for bind: int in before.skin.get_bind_count():
		if before.skin.get_bind_name(bind) != after.skin.get_bind_name(bind) or before.skin.get_bind_bone(bind) != after.skin.get_bind_bone(bind) or before.skin.get_bind_pose(bind) != after.skin.get_bind_pose(bind):
			errors.append(label + ": Skin bind changed at " + str(bind))
	if before.mesh == null or after.mesh == null:
		errors.append(label + ": missing mesh")
		return errors
	if before.mesh.get_surface_count() != after.mesh.get_surface_count():
		errors.append(label + ": surface count changed")
		return errors
	var raw_before: Array = before.mesh.get("_surfaces")
	var raw_after: Array = after.mesh.get("_surfaces")
	for sid: int in before.mesh.get_surface_count():
		var first: Dictionary = raw_before[sid].duplicate()
		var second: Dictionary = raw_after[sid].duplicate()
		first.erase("material")
		second.erase("material")
		if first != second:
			errors.append(label + ": serialized surface buffers changed at " + str(sid))
		var a := before.mesh.surface_get_arrays(sid)
		var b := after.mesh.surface_get_arrays(sid)
		for channel: int in Mesh.ARRAY_MAX:
			if a[channel] != b[channel]:
				errors.append(label + ": native array channel %d changed at surface %d" % [channel, sid])
		if not allow_material_change and material_record(before.get_active_material(sid)) != material_record(after.get_active_material(sid)):
			errors.append(label + ": material stored properties changed at " + str(sid))
	if not allow_material_change:
		if before.get_meta("armor_rework", "") != after.get_meta("armor_rework", ""):
			errors.append(label + ": inherited revision changed")
		if before.extra_cull_margin != after.extra_cull_margin:
			errors.append(label + ": inherited cull margin changed")
	return errors


static func material_record(resource: Resource) -> Dictionary:
	if resource == null:
		return {"null": true}
	var result := {"class": resource.get_class(), "properties": {}}
	var keys: Array[String] = []
	for property: Dictionary in resource.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE and str(property.name) not in ["resource_path", "resource_scene_unique_id"]:
			keys.append(str(property.name))
	keys.sort()
	for key: String in keys:
		var value: Variant = resource.get(key)
		if value is Resource:
			var nested := value as Resource
			if not nested.resource_path.is_empty() and not nested.resource_path.contains("::"):
				result.properties[key] = {"path": nested.resource_path, "sha256": FileAccess.get_sha256(nested.resource_path) if FileAccess.file_exists(nested.resource_path) else "IMPORTED_RESOURCE"}
			else:
				result.properties[key] = material_record(nested)
		else:
			result.properties[key] = var_to_str(value)
	return result


static func check_pins(config: Dictionary, require_target := false) -> Array[String]:
	var errors: Array[String] = []
	for pair: Array in [["source_scene", "source_scene_sha256"], ["source_buffer", "source_buffer_sha256"], ["original_head_texture", "original_head_texture_sha256"], ["before_scene", "before_scene_sha256"], ["head_source_json", "head_source_json_sha256"], ["before_snapshot", "before_snapshot_sha256"]]:
		var path := str(config[pair[0]])
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(config[pair[1]]):
			errors.append("Pinned source changed or absent: " + path)
	for path: String in config.protected_alternates:
		if FileAccess.get_sha256(path) != str(config.protected_alternates[path]):
			errors.append("Protected alternate changed: " + path)
	for path: String in config.get("inherited_body_resource_sha256", {}):
		if FileAccess.get_sha256(path) != str(config.inherited_body_resource_sha256[path]):
			errors.append("Inherited body texture/shader bytes changed: " + path)
	if require_target:
		for pair: Array in [["head_target", "head_target_sha256"], ["native_generated_png", "native_generated_png_sha256"]]:
			var path := str(config.get(pair[0], ""))
			if not FileAccess.file_exists(path) or str(config.get(pair[1], "")).is_empty() or FileAccess.get_sha256(path) != str(config.get(pair[1], "")):
				errors.append("Pinned generation target/native PNG changed or absent: " + path)
		if FileAccess.file_exists(str(config.head_target)):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(config.head_target)))
			if not parsed is Dictionary:
				errors.append("Invalid head target JSON")
			else:
				for key: String in ["source_scene", "source_scene_sha256", "source_buffer_sha256", "original_texture_sha256"]:
					var config_key := "original_head_texture_sha256" if key == "original_texture_sha256" else key
					if str(parsed.get(key, "")) != str(config.get(config_key, "")):
						errors.append("Target source pin mismatch: " + key)
	return errors


static func posed_bounds(part: MeshInstance3D, skeleton: Skeleton3D, rest := false) -> AABB:
	var transforms: Array[Transform3D] = []
	for bind: int in part.skin.get_bind_count():
		var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
		var pose := skeleton.get_bone_global_rest(bone) if rest else skeleton.get_bone_global_pose(bone)
		transforms.append(pose * part.skin.get_bind_pose(bind))
	var bounds := AABB()
	var started := false
	for sid: int in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(sid)
		for vertex: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for influence: int in 4:
				var offset := vertex * 4 + influence
				point += (transforms[arrays[Mesh.ARRAY_BONES][offset]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * arrays[Mesh.ARRAY_WEIGHTS][offset]
			bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return bounds


static func triangle_count(part: MeshInstance3D) -> int:
	var count := 0
	for sid: int in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(sid)
		count += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count
