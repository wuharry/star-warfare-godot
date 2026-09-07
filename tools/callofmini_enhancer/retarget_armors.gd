extends SceneTree

# Rebuild the Collada skins from their authoritative inverse-bind matrices.
# The legacy Godot DAE import has weights but no Skin, and its bone rests are
# not suitable for animation. All output uses the existing Unity player rig.
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const AVATAR_PATH := "res://assets/models/player/animated/player.gltf"
const SOURCE_ROOT := "res://assets/callOfMini/enhanced/"
const PART_NAMES := ["ArmorHead", "ArmorBody", "ArmorHand", "ArmorFoot"]
const LOCAL_AXIS_BRIDGE := Basis(Vector3.UP, PI)

var target_skeleton: Skeleton3D
var target_bounds: Dictionary = {}
var source_bounds: Dictionary = {}
var target_parts: Dictionary = {}
var target_skin: Skin
var report: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var avatar := (load(AVATAR_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(avatar)
	target_skeleton = avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	target_skin = Skin.new()
	for bone in target_skeleton.get_bone_count():
		target_skin.add_named_bind(target_skeleton.get_bone_name(bone), target_skeleton.get_bone_global_rest(bone).affine_inverse())
	_measure_target(avatar)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Catalog.CALLOFMINI_GAMEPLAY_DIR))
	for index in Catalog.CALLOFMINI_MODELS.size():
		_build_set(index)
	var file := FileAccess.open(Catalog.CALLOFMINI_GAMEPLAY_DIR + "fit_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"reference": "Viper / Armor*_00", "method": "per-bone bind-space fit to Viper geometry", "sets": report}, "\t") + "\n")
	avatar.free()
	print("CALLOFMINI_RETARGET_PASS sets=%d parts=%d bones=%d" % [report.size(), report.size() * 4, target_skin.get_bind_count()])
	quit()


func _source_model(index: int) -> Dictionary:
	var set_id := Catalog.CALLOFMINI_FIRST_ID + index
	var stem: String = Catalog.CALLOFMINI_MODELS[index]
	var path: String = SOURCE_ROOT + Catalog.SET_NAMES[set_id] + "/" + stem
	var model := (load(path + ".tscn") as PackedScene).instantiate() as Node3D
	return {"model": model, "binds": _read_bind_matrices(path + ".dae")}


func _read_bind_matrices(path: String) -> Dictionary:
	var parser := XMLParser.new()
	assert(parser.open(path) == OK, "Could not read " + path)
	var names := PackedStringArray()
	var values := PackedFloat64Array()
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var element := parser.get_node_name()
		if element == "Name_array" and names.is_empty():
			parser.read()
			names = parser.get_node_data().strip_edges().split(" ", false)
		elif element == "float_array" and parser.get_named_attribute_value_safe("id").contains("bind_poses"):
			parser.read()
			for value in parser.get_node_data().strip_edges().split(" ", false):
				values.append(float(value))
			break
	assert(values.size() == names.size() * 16, "Incomplete inverse binds in " + path)
	var result := {}
	for index in names.size():
		var offset := index * 16
		var basis := Basis(
			Vector3(values[offset], values[offset + 4], values[offset + 8]),
			Vector3(values[offset + 1], values[offset + 5], values[offset + 9]),
			Vector3(values[offset + 2], values[offset + 6], values[offset + 10])
		)
		result[names[index]] = Transform3D(basis, Vector3(values[offset + 3], values[offset + 7], values[offset + 11]))
	return result


func _measure_target(avatar: Node3D) -> void:
	var part_votes := {}
	for part in range(4):
		var instance := avatar.find_child(PART_NAMES[part] + "_00", true, false) as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex in vertices.size():
				var influence := _strongest_influence(weights, vertex)
				var bind_index := bones[vertex * 4 + influence]
				var bone_name := String(instance.skin.get_bind_name(bind_index))
				var local := instance.skin.get_bind_pose(bind_index) * vertices[vertex]
				_extend_bounds(target_bounds, bone_name, local)
				if not part_votes.has(bone_name):
					part_votes[bone_name] = [0, 0, 0, 0]
				part_votes[bone_name][part] += 1
	for bone_name: String in part_votes:
		var votes: Array = part_votes[bone_name]
		target_parts[bone_name] = votes.find(votes.max())


func _measure_source(model: Node3D, binds: Dictionary) -> void:
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex in vertices.size():
				var influence := _strongest_influence(weights, vertex)
				var source_name := String(skeleton.get_bone_name(bones[vertex * 4 + influence]))
				var bone_name := _target_name(source_name)
				var local: Vector3 = LOCAL_AXIS_BRIDGE * (binds[source_name] * vertices[vertex])
				_extend_bounds(source_bounds, bone_name, local)


func _build_set(index: int) -> void:
	var source := _source_model(index)
	var model: Node3D = source.model
	source_bounds.clear()
	_measure_source(model, source.binds)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var output := Node3D.new()
	output.name = Catalog.CALLOFMINI_MODELS[index]
	var meshes: Array[ArrayMesh] = [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
	var input_triangles := 0
	var output_triangles := 0
	var raw_bounds := AABB()
	var has_raw_bounds := false
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		raw_bounds = raw_bounds.merge(instance.mesh.get_aabb()) if has_raw_bounds else instance.mesh.get_aabb()
		has_raw_bounds = true
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var fitted := PackedVector3Array()
			var fitted_normals := PackedVector3Array()
			var target_bones := PackedInt32Array()
			var parts := PackedInt32Array()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				var normal := Vector3.ZERO
				for influence in range(4):
					var weight := weights[vertex * 4 + influence]
					var source_name := String(skeleton.get_bone_name(bones[vertex * 4 + influence]))
					var target_name := _target_name(source_name)
					var target_bone := target_skeleton.find_bone(target_name)
					assert(target_bone >= 0 or weight == 0.0, "Unmapped weighted bone: " + source_name)
					target_bones.append(maxi(0, target_bone))
					if weight <= 0.0:
						continue
					var source_bind: Transform3D = source.binds[source_name]
					var local: Vector3 = LOCAL_AXIS_BRIDGE * (source_bind * vertices[vertex])
					var fit := _bone_fit(target_name)
					var rest := target_skeleton.get_bone_global_rest(target_bone)
					point += (rest * (fit * local)) * weight
					var normal_basis: Basis = rest.basis * fit.basis * LOCAL_AXIS_BRIDGE * source_bind.basis
					normal += normal_basis.inverse().transposed() * normals[vertex] * weight
				fitted.append(point)
				fitted_normals.append(normal.normalized())
				var strongest := _strongest_influence(weights, vertex)
				var strongest_name := _target_name(String(skeleton.get_bone_name(bones[vertex * 4 + strongest])))
				parts.append(int(target_parts.get(strongest_name, 1)))
			var part_indices: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
			for triangle in range(0, indices.size(), 3):
				var votes := [0, 0, 0, 0]
				for corner in range(3):
					votes[parts[indices[triangle + corner]]] += 1
				var part := votes.find(votes.max())
				for corner in range(3):
					part_indices[part].append(indices[triangle + corner])
			input_triangles += indices.size() / 3
			arrays[Mesh.ARRAY_VERTEX] = fitted
			arrays[Mesh.ARRAY_NORMAL] = fitted_normals
			arrays[Mesh.ARRAY_BONES] = target_bones
			# Imported tangents describe the old geometry; no material uses normal maps.
			arrays[Mesh.ARRAY_TANGENT] = null
			for part in range(4):
				if part_indices[part].is_empty():
					continue
				arrays[Mesh.ARRAY_INDEX] = part_indices[part]
				meshes[part].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact_arrays(arrays))
				meshes[part].surface_set_material(meshes[part].get_surface_count() - 1, instance.get_active_material(surface))
				output_triangles += part_indices[part].size() / 3
	var bounds := AABB()
	for part in range(4):
		assert(meshes[part].get_surface_count() > 0, "Missing armor part")
		var instance := MeshInstance3D.new()
		instance.name = "%s_%02d" % [PART_NAMES[part], Catalog.CALLOFMINI_FIRST_ID + index]
		instance.mesh = meshes[part]
		instance.skin = target_skin
		instance.custom_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 4, 4))
		output.add_child(instance)
		instance.owner = output
		bounds = bounds.merge(meshes[part].get_aabb()) if part > 0 else meshes[part].get_aabb()
	var packed := PackedScene.new()
	assert(packed.pack(output) == OK)
	var path := Catalog.gameplay_scene_path(Catalog.CALLOFMINI_FIRST_ID + index)
	assert(ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) == OK, "Could not save " + path)
	assert(input_triangles == output_triangles, "Retarget lost triangles")
	report.append({"name": output.name, "source_size": _vector_array(raw_bounds.size), "fitted_rest_size": _vector_array(bounds.size), "fitted_rest_min": _vector_array(bounds.position), "triangles": output_triangles})
	print("FITTED ", output.name, " source=", raw_bounds.size, " fitted=", bounds.size, " triangles=", output_triangles)
	output.free()
	model.free()


func _bone_fit(bone_name: String) -> Transform3D:
	if not source_bounds.has(bone_name) or not target_bounds.has(bone_name):
		return Transform3D.IDENTITY
	var source: AABB = source_bounds[bone_name]
	var target: AABB = target_bounds[bone_name]
	var scale_factor := Vector3.ONE
	for axis in range(3):
		if source.size[axis] > 0.001:
			scale_factor[axis] = target.size[axis] / source.size[axis]
	return Transform3D(Basis.from_scale(scale_factor), target.get_center() - source.get_center() * scale_factor)


func _target_name(source_name: String) -> String:
	if source_name == "UpBodyRotate":
		return "Bip01 Spine"
	return source_name.replace("_", " ")


func _strongest_influence(weights: PackedFloat32Array, vertex: int) -> int:
	var strongest := 0
	for influence in range(1, 4):
		if weights[vertex * 4 + influence] > weights[vertex * 4 + strongest]:
			strongest = influence
	return strongest


func _extend_bounds(collection: Dictionary, key: String, point: Vector3) -> void:
	collection[key] = (collection[key] as AABB).expand(point) if collection.has(key) else AABB(point, Vector3.ZERO)


func _compact_arrays(arrays: Array) -> Array:
	# Drop unused vertices from each split part so bounds and thumbnails measure
	# just that part, while keeping shared seam vertices numerically identical.
	var output := []
	output.resize(Mesh.ARRAY_MAX)
	output[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	output[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	output[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	output[Mesh.ARRAY_BONES] = PackedInt32Array()
	output[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()
	output[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var remap := {}
	for source_index: int in arrays[Mesh.ARRAY_INDEX]:
		if not remap.has(source_index):
			remap[source_index] = remap.size()
			for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
				output[slot].append(arrays[slot][source_index])
			for influence in range(4):
				output[Mesh.ARRAY_BONES].append(arrays[Mesh.ARRAY_BONES][source_index * 4 + influence])
				output[Mesh.ARRAY_WEIGHTS].append(arrays[Mesh.ARRAY_WEIGHTS][source_index * 4 + influence])
		output[Mesh.ARRAY_INDEX].append(remap[source_index])
	return output


func _vector_array(value: Vector3) -> Array[float]:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]
