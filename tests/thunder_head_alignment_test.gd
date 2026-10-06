extends SceneTree

const WORK := "res://docs/art/thunder_head_alignment_v1/"
const SNAPSHOT := WORK + "before/snapshot.json"
const SNAPSHOT_SHA := "2ecb0ec87ae0e24172f2b3002c00c2d25155fa37d054cd5aaa157cfe1e2f8201"
const BEFORE_SCENE := WORK + "before/resources/assets/armors/thunder/thunder.scn"
const BEFORE_SCENE_SHA := "9f939667c6516ee3e2335cb973abeb7805d6865fd4df6b97821303bcd2661df5"
const CURRENT_SCENE := "res://assets/armors/thunder/thunder.scn"
const ORIGINAL_RIG := "res://assets/models/player/animated/player.gltf"
const BEFORE_ARRAYS := WORK + "before/scene_arrays.json"
const AFTER_ARRAYS := WORK + "scene_arrays.json"
const REPORT := WORK + "scene_test.json"
const PART_NAMES := ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"]
const HEAD := "ArmorHead_06"
const SHAPE_LIMIT := 0.20
const SEAM_TOLERANCE := 0.000001

var failures: Array[String] = []
var real_save_path := ""
var real_save_sha := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("THUNDER_HEAD_ALIGNMENT: " + message)


func _digest(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _file_hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"


func _current_save_path() -> String:
	var state := root.get_node_or_null("GameState")
	return str(state.get("save_path")) if state != null else "user://star_warfare_save.json"


func _run() -> void:
	real_save_path = _current_save_path()
	real_save_sha = _file_hash(real_save_path)
	var baseline_only := "--baseline-only" in OS.get_cmdline_user_args()
	var snapshot := _verify_frozen_snapshot()
	if not failures.is_empty():
		_finish({"mode": "baseline_only" if baseline_only else "compare"})
		return
	var original := (load(ORIGINAL_RIG) as PackedScene).instantiate()
	var skeletons := original.find_children("*", "Skeleton3D", true, false)
	_check(skeletons.size() == 1, "Original rig must contain one Skeleton3D")
	if skeletons.size() != 1:
		original.free()
		_finish({})
		return
	var skeleton := skeletons[0] as Skeleton3D
	_check(skeleton.get_bone_count() == 28, "Original game rig must have 28 bones")
	var before := _serialize_scene(BEFORE_SCENE, skeleton)
	if baseline_only:
		if failures.is_empty():
			if FileAccess.file_exists(BEFORE_ARRAYS):
				_check(_frozen_arrays_match(before), "Frozen scene-array serialization already exists with different content")
			else:
				_write_json(BEFORE_ARRAYS, before)
		original.free()
		_finish({"mode": "baseline_only", "before_scene_sha256": BEFORE_SCENE_SHA, "before_arrays": BEFORE_ARRAYS, "before_arrays_sha256": _file_hash(BEFORE_ARRAYS), "parts": before.get("parts", []), "snapshot_sha256": SNAPSHOT_SHA}, false)
		return
	_check(FileAccess.file_exists(BEFORE_ARRAYS), "Run --baseline-only before changing Thunder assets")
	if FileAccess.file_exists(BEFORE_ARRAYS):
		if not _frozen_arrays_match(before):
			_write_json("res://test_output/thunder_reloaded_before_scene_arrays.json", before)
		_check(_frozen_arrays_match(before), "Frozen actual-SCN array serialization no longer matches its pinned scene")
	_verify_old_dependencies(snapshot)
	var after := _serialize_scene(CURRENT_SCENE, skeleton)
	var comparison := _compare_scenes(before, after)
	_write_json(AFTER_ARRAYS, after)
	original.free()
	comparison["mode"] = "compare"
	comparison["scope"] = "Actual current SCN versus the pinned integrated SW2 Thunder before SCN; no classic SW1 geometry equivalence claim"
	comparison["before_scene_sha256"] = BEFORE_SCENE_SHA
	comparison["current_scene_sha256"] = _file_hash(CURRENT_SCENE)
	comparison["snapshot_sha256"] = SNAPSHOT_SHA
	comparison["before_arrays_sha256"] = _file_hash(BEFORE_ARRAYS)
	comparison["after_arrays_sha256"] = _file_hash(AFTER_ARRAYS)
	comparison["source_rig_sha256"] = _file_hash(ORIGINAL_RIG)
	_finish(comparison)


func _verify_frozen_snapshot() -> Dictionary:
	_check(_file_hash(SNAPSHOT) == SNAPSHOT_SHA, "Pinned before snapshot changed")
	_check(_file_hash(BEFORE_SCENE) == BEFORE_SCENE_SHA, "Pinned before SCN changed")
	if not failures.is_empty():
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	_check(data is Dictionary and data.get("records") is Array, "Invalid before snapshot schema")
	if not data is Dictionary or not data.get("records") is Array:
		return {}
	_check(data.records.size() == 112, "Frozen before snapshot record count changed")
	for record: Dictionary in data.records:
		var path := "res://" + str(record.snapshot)
		_check(FileAccess.file_exists(path), "Missing frozen file " + path)
		if not FileAccess.file_exists(path):
			continue
		_check(_file_hash(path) == str(record.sha256), "Frozen bytes changed " + path)
		var file := FileAccess.open(path, FileAccess.READ)
		_check(file != null and file.get_length() == int(record.bytes), "Frozen byte count changed " + path)
	return data


func _verify_old_dependencies(snapshot: Dictionary) -> void:
	# Frozen SCNs still reference their original res:// texture/shader paths.
	# Check raw old dependencies too, so loading both scenes cannot hide changes.
	for record: Dictionary in snapshot.records:
		var path := str(record.path)
		if path.begins_with("assets/") and path.get_extension() in ["png", "res", "gdshader"]:
			_check(_file_hash("res://" + path) == str(record.sha256), "Old shared dependency changed " + path)


func _transform_data(value: Transform3D) -> Array:
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z, value.basis.y.x, value.basis.y.y, value.basis.y.z, value.basis.z.x, value.basis.z.y, value.basis.z.z, value.origin.x, value.origin.y, value.origin.z]


func _vector_data(value: Variant) -> Array:
	var result: Array = []
	if value == null:
		return result
	for point: Variant in value:
		result.append(float(point.x))
		result.append(float(point.y))
		if point is Vector3:
			result.append(float(point.z))
	return result


func _scalar_data(value: Variant) -> Array:
	return [] if value == null else Array(value)


func _value_signature(value: Variant) -> Dictionary:
	if value is Texture2D:
		var texture := value as Texture2D
		var image := texture.get_image()
		var result := {"type": "Texture2D", "path": texture.resource_path, "name": texture.resource_name, "file_sha256": _file_hash(texture.resource_path)}
		if image != null:
			result["image_size"] = [image.get_width(), image.get_height()]
			result["image_format"] = image.get_format()
			result["mipmaps"] = image.has_mipmaps()
			result["image_data_sha256"] = _digest(image.get_data())
		return result
	if value is Shader:
		var shader := value as Shader
		return {"type": "Shader", "path": shader.resource_path, "file_sha256": _file_hash(shader.resource_path), "code_sha256": _digest(shader.code.to_utf8_buffer())}
	if value is Resource:
		var resource := value as Resource
		return {"type": resource.get_class(), "path": resource.resource_path, "name": resource.resource_name, "file_sha256": _file_hash(resource.resource_path)}
	return {"type": typeof(value), "value_sha256": _digest(var_to_bytes(value))}


func _material_data(material: Material) -> Dictionary:
	if material == null:
		return {"missing": true}
	var properties: Dictionary = {}
	for entry: Dictionary in material.get_property_list():
		if (int(entry.usage) & PROPERTY_USAGE_STORAGE) != 0:
			var key := str(entry.name)
			properties[key] = _value_signature(material.get(key))
	return {"class": material.get_class(), "resource_name": material.resource_name, "resource_path": material.resource_path, "resource_path_kind": "embedded" if material.resource_path.contains("::") else "external", "storage_properties": properties}


func _serialize_scene(path: String, skeleton: Skeleton3D) -> Dictionary:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check(packed != null, "Cannot load actual SCN " + path)
	if packed == null:
		return {}
	var scene := packed.instantiate()
	var result := {"schema_version": 1, "scope": "actual Godot SCN arrays; Y up, facing -Z; flat vector components in surface vertex order", "scene": path, "scene_sha256": _file_hash(path), "source_rig": ORIGINAL_RIG, "source_rig_sha256": _file_hash(ORIGINAL_RIG), "parts": []}
	_check(scene.get_child_count() == 4, "Thunder SCN must have four exchangeable parts")
	for name: String in PART_NAMES:
		var part := scene.find_child(name, true, false) as MeshInstance3D
		_check(part != null and part.mesh != null and part.skin != null, "Missing mesh or skin " + name)
		if part == null or part.mesh == null or part.skin == null:
			continue
		_check(part.skin.get_bind_count() == 28, name + " must retain 28 named skin binds")
		var skin: Array = []
		var bind_names: Dictionary = {}
		for bind: int in part.skin.get_bind_count():
			var bind_name := str(part.skin.get_bind_name(bind))
			var bone := skeleton.find_bone(bind_name)
			_check(not bind_name.is_empty() and not bind_names.has(bind_name) and bone >= 0, name + " has invalid or duplicated named bind")
			bind_names[bind_name] = true
			if bone >= 0:
				_check((skeleton.get_bone_global_rest(bone) * part.skin.get_bind_pose(bind)).is_equal_approx(Transform3D.IDENTITY), name + " changes the original game bind rest")
			skin.append({"name": bind_name, "bone": part.skin.get_bind_bone(bind), "pose": _transform_data(part.skin.get_bind_pose(bind))})
		var record := {"name": name, "transform": _transform_data(part.transform), "skeleton": str(part.skeleton), "skin": skin, "surfaces": []}
		for surface: int in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var hashes: Array = []
			var types: Array = []
			for channel: int in Mesh.ARRAY_MAX:
				hashes.append(_digest(var_to_bytes(arrays[channel])))
				types.append(typeof(arrays[channel]))
			var material := part.get_active_material(surface)
			record.surfaces.append({"surface": surface, "primitive": part.mesh.surface_get_primitive_type(surface), "format": part.mesh.surface_get_format(surface), "vertices": _vector_data(arrays[Mesh.ARRAY_VERTEX]), "normals": _vector_data(arrays[Mesh.ARRAY_NORMAL]), "tangents": _scalar_data(arrays[Mesh.ARRAY_TANGENT]), "uv": _vector_data(arrays[Mesh.ARRAY_TEX_UV]), "bones": _scalar_data(arrays[Mesh.ARRAY_BONES]), "weights": _scalar_data(arrays[Mesh.ARRAY_WEIGHTS]), "indices": _scalar_data(arrays[Mesh.ARRAY_INDEX]), "array_hashes": hashes, "array_types": types, "material": _material_data(material)})
		result.parts.append(record)
	scene.free()
	return result


func _by_name(parts: Array) -> Dictionary:
	var result: Dictionary = {}
	for part: Dictionary in parts:
		result[str(part.name)] = part
	return result


func _point(values: Array, index: int) -> Vector3:
	return Vector3(float(values[index * 3]), float(values[index * 3 + 1]), float(values[index * 3 + 2]))


func _non_head_comparison_data(part: Dictionary) -> Dictionary:
	var result := part.duplicate(true)
	for surface: Dictionary in result.surfaces:
		# A packed material receives its container SCN path when loaded. Saving
		# the same content in another SCN changes that location, not its finish.
		if surface.material.get("resource_path_kind", "") == "embedded":
			surface.material.erase("resource_path")
	return result


func _compare_scenes(before: Dictionary, after: Dictionary) -> Dictionary:
	var report := {"head_uv_changed_coordinates": 0, "head_added_vertices": 0, "head_added_triangles": 0, "non_head_parts_exact": [], "seam_tolerance_m": SEAM_TOLERANCE, "shape_limit_against_integrated_before": SHAPE_LIMIT}
	if not before.has("parts") or not after.has("parts"):
		_check(false, "Missing serialized actual-scene parts")
		return report
	var old := _by_name(before.parts)
	var current := _by_name(after.parts)
	var groups: Dictionary = {}
	var maximum_move := 0.0
	var maximum_seam_gap := 0.0
	var old_bounds := AABB()
	var new_bounds := AABB()
	var started := false
	var head_vertices := 0
	var head_triangles := 0
	var flips := 0
	var new_degenerate := 0
	var inherited_degenerate := 0
	for name: String in PART_NAMES:
		_check(old.has(name) and current.has(name), "Missing actual serialized part " + name)
		if not old.has(name) or not current.has(name):
			continue
		var a: Dictionary = old[name]
		var b: Dictionary = current[name]
		_check(a.transform == b.transform and a.skeleton == b.skeleton and a.skin == b.skin, "Transform/attachment/named skin changed " + name)
		_check(a.surfaces.size() == b.surfaces.size(), "Surface count changed " + name)
		if a.surfaces.size() != b.surfaces.size():
			continue
		if name != HEAD:
			var exact := _non_head_comparison_data(a) == _non_head_comparison_data(b)
			_check(exact, "Non-head arrays or material properties changed " + name)
			report.non_head_parts_exact.append({"part": name, "exact": exact})
			continue
		for surface: int in a.surfaces.size():
			var u: Dictionary = a.surfaces[surface]
			var v: Dictionary = b.surfaces[surface]
			_check(u.primitive == Mesh.PRIMITIVE_TRIANGLES and v.primitive == u.primitive, "Head primitive changed")
			for field: String in ["surface", "format", "uv", "bones", "weights", "indices", "array_types"]:
				_check(u[field] == v[field], "Head immutable array changed: " + field)
			for channel: int in Mesh.ARRAY_MAX:
				if channel not in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]:
					_check(u.array_hashes[channel] == v.array_hashes[channel], "Head extra/immutable channel changed: " + str(channel))
			_check(u.vertices.size() == v.vertices.size() and u.vertices.size() % 3 == 0, "Head vertex count changed")
			if u.vertices.size() != v.vertices.size():
				continue
			var count: int = u.vertices.size() / 3
			head_vertices += count
			_check(v.normals.size() == count * 3 and v.uv.size() == count * 2 and v.bones.size() == count * 4 and v.weights.size() == count * 4, "Head vertex channels incomplete")
			for index: int in count:
				var p := _point(u.vertices, index)
				var q := _point(v.vertices, index)
				_check(p.is_finite() and q.is_finite(), "Head position is non-finite")
				maximum_move = maxf(maximum_move, p.distance_to(q))
				if groups.has(p):
					maximum_seam_gap = maxf(maximum_seam_gap, q.distance_to(groups[p]))
				else:
					groups[p] = q
				old_bounds = old_bounds.expand(p) if started else AABB(p, Vector3.ZERO)
				new_bounds = new_bounds.expand(q) if started else AABB(q, Vector3.ZERO)
				started = true
			var order: Array = u.indices if not u.indices.is_empty() else range(count)
			_check(order.size() % 3 == 0, "Head triangle count is not integral")
			head_triangles += order.size() / 3
			for face: int in order.size() / 3:
				var ia := int(order[face * 3])
				var ib := int(order[face * 3 + 1])
				var ic := int(order[face * 3 + 2])
				var n := (_point(u.vertices, ib) - _point(u.vertices, ia)).cross(_point(u.vertices, ic) - _point(u.vertices, ia))
				var m := (_point(v.vertices, ib) - _point(v.vertices, ia)).cross(_point(v.vertices, ic) - _point(v.vertices, ia))
				if n.length_squared() <= 1e-24:
					inherited_degenerate += 1
				elif m.length_squared() <= 1e-24:
					new_degenerate += 1
				elif n.dot(m) <= 0.0:
					flips += 1
	_check(started, "Head position measurement is empty")
	var scale := minf(old_bounds.size.x, minf(old_bounds.size.y, old_bounds.size.z))
	_check(scale > 0.0, "Before head bounds have a zero axis")
	var displacement_ratio := maximum_move / scale if scale > 0.0 else INF
	var size_delta: Array = []
	for axis: int in 3:
		var delta := absf(new_bounds.size[axis] - old_bounds.size[axis]) / old_bounds.size[axis] if old_bounds.size[axis] > 0.0 else INF
		size_delta.append(delta)
		_check(delta <= SHAPE_LIMIT, "Head dimension exceeds integrated-before 20% on axis " + str(axis))
	_check(displacement_ratio <= SHAPE_LIMIT, "Head displacement exceeds integrated-before 20%")
	_check(maximum_seam_gap <= SEAM_TOLERANCE, "UV-split physical vertices separate after deformation")
	_check(flips == 0 and new_degenerate == 0, "Head introduces flipped or degenerate faces")
	report.merge({"head_vertices": head_vertices, "head_triangles": head_triangles, "unique_before_physical_points": groups.size(), "max_displacement_m": maximum_move, "before_smallest_axis_m": scale, "max_displacement_fraction": displacement_ratio, "dimension_delta_fraction": size_delta, "max_seam_gap_m": maximum_seam_gap, "flipped_faces": flips, "new_degenerate_faces": new_degenerate, "inherited_degenerate_faces": inherited_degenerate}, true)
	return report


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Cannot write actual scene serialization " + path)
	if file != null:
		file.store_string(JSON.stringify(data, "\t", true, true) + "\n")


func _frozen_arrays_match(data: Dictionary) -> bool:
	# JSON.parse converts numbers to floats and loses native typed-array kinds.
	# Compare the full-precision canonical bytes produced by actual SCN loading
	# instead; every stored value, native array hash and resource binding remains.
	var reloaded := (JSON.stringify(data, "\t", true, true) + "\n").to_utf8_buffer()
	return FileAccess.get_file_as_bytes(BEFORE_ARRAYS) == reloaded


func _finish(report: Dictionary, write_report: bool = true) -> void:
	_check(_current_save_path() == real_save_path and _file_hash(real_save_path) == real_save_sha, "Real user save changed during read-only scene validation")
	report["status"] = "PASS" if failures.is_empty() else "FAIL"
	report["errors"] = failures
	report["real_save_unchanged"] = _file_hash(real_save_path) == real_save_sha
	report["not_run"] = ["Artistic concept likeness", "Classic SW1 original-head geometry equivalence", "Animation/gameplay captures", "Mobile performance"]
	if write_report:
		_write_json(REPORT, report)
	print("THUNDER_HEAD_ALIGNMENT_%s mode=%s errors=%d" % [report.status, report.get("mode", "unknown"), failures.size()])
	quit(0 if failures.is_empty() else 1)
