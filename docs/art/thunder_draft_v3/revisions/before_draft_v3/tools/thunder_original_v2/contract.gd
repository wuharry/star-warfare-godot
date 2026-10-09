extends RefCounted

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


static func check_pins(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for pair: Array in [["source_scene", "source_scene_sha256"], ["source_buffer", "source_buffer_sha256"], ["original_head_texture", "original_head_texture_sha256"], ["before_scene", "before_scene_sha256"]]:
		var path := str(config[pair[0]])
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(config[pair[1]]):
			errors.append("Pinned source changed or absent: " + path)
	for path: String in config.protected_alternates:
		if FileAccess.get_sha256(path) != str(config.protected_alternates[path]):
			errors.append("Protected alternate changed: " + path)
	for path: String in config.get("inherited_body_resource_sha256", {}):
		if FileAccess.get_sha256(path) != str(config.inherited_body_resource_sha256[path]):
			errors.append("Inherited body texture/shader bytes changed: " + path)
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
