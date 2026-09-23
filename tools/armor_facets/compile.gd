extends SceneTree

const OUT := "res://assets/armors/angular/"
const WORK := "res://test_output/armor_facets/"
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const PREFIXES := ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]
const PAINT_SHADERS := ["res://assets/equipment_refined/painted_equipment.gdshader", "res://assets/armors/viper/painted_armor.gdshader"]
var meshes: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var input_path := WORK + "meshes.json"
	var selected: Array[int] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="):
			input_path = argument.trim_prefix("--input=")
		if argument.begins_with("--ids="):
			for value: String in argument.trim_prefix("--ids=").split(","):
				if not value.is_valid_int() or int(value) < 0 or int(value) >= Catalog.SET_NAMES.size() or int(value) == 6:
					_abort("Invalid armor id: " + value)
					return
				selected.append(int(value))
	if not FileAccess.file_exists(input_path):
		_abort("Generate meshes.json before compilation: " + input_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if not parsed is Dictionary:
		_abort("Generated geometry must be a JSON dictionary")
		return
	meshes = parsed
	# Validate every selected set before saving any scene. A helper assertion
	# only exits that helper in Godot and must never stand in for this gate.
	if not _preflight(selected):
		quit(1)
		return
	var compiled := 0
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) != OK:
		_abort("Cannot create output directory")
		return
	for id: int in Catalog.SET_NAMES.size():
		if id == 6 or (not selected.is_empty() and id not in selected):
			continue
		var source_path := "res://assets/armors/viper/viper.scn" if id == 0 else "res://assets/equipment_refined/armors/armor_%02d.scn" % id
		var source := (load(source_path) as PackedScene).instantiate()
		var container := Node3D.new()
		container.name = "AngularArmor%02d" % id
		for prefix: String in PREFIXES:
			var original := source.find_child(prefix + "%02d" % id, true, false) as MeshInstance3D
			var replacement := MeshInstance3D.new()
			replacement.name = original.name
			replacement.transform = original.transform
			replacement.skin = original.skin
			replacement.skeleton = NodePath("..")
			replacement.extra_cull_margin = maxf(original.extra_cull_margin, 1.0)
			replacement.mesh = _compile(original)
			replacement.set_meta("armor_rework", "angular_armor_v1")
			container.add_child(replacement)
			replacement.owner = container
		var packed := PackedScene.new()
		var error := packed.pack(container)
		if error == OK:
			error = ResourceSaver.save(packed, OUT + "armor_%02d.scn" % id)
		container.free()
		source.free()
		if error != OK:
			_abort("Failed to save armor %02d: %s" % [id, error_string(error)])
			return
		compiled += 1
	print("ANGULAR_COMPILE_PASS sets=%d" % compiled)
	quit()


func _preflight(selected: Array[int]) -> bool:
	for id: int in Catalog.SET_NAMES.size():
		if id == 6 or (not selected.is_empty() and id not in selected):
			continue
		var path := "res://assets/armors/viper/viper.scn" if id == 0 else "res://assets/equipment_refined/armors/armor_%02d.scn" % id
		var packed := load(path) as PackedScene
		if packed == null:
			return _invalid("Cannot load accepted baseline: " + path)
		var baseline := packed.instantiate()
		for prefix: String in PREFIXES:
			var key := prefix + "%02d" % id
			var original := baseline.find_child(key, true, false) as MeshInstance3D
			if original == null or original.mesh == null or original.skin == null:
				baseline.free()
				return _invalid("Missing accepted baseline part: " + key)
			if not meshes.has(key) or not meshes[key] is Array or meshes[key].size() != original.mesh.get_surface_count():
				baseline.free()
				return _invalid("Missing geometry or changed surface count: " + key)
			for surface: int in original.mesh.get_surface_count():
				if not _valid_surface(meshes[key][surface], original.skin.get_bind_count(), "%s surface %d" % [key, surface]):
					baseline.free()
					return false
		baseline.free()
	return true


func _valid_surface(source: Variant, bind_count: int, label: String) -> bool:
	if not source is Dictionary:
		return _invalid(label + " is not a surface dictionary")
	for attribute: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if not source.has(str(attribute)) or not source[str(attribute)] is Array:
			return _invalid(label + " lacks required vertex attributes")
	var count: int = source[str(Mesh.ARRAY_VERTEX)].size()
	if count == 0:
		return _invalid(label + " has no vertices")
	for key: Variant in source:
		if not key is String or not key.is_valid_int():
			return _invalid(label + " has an invalid attribute key")
		var attribute := int(key)
		if not source[key] is Array:
			return _invalid(label + " has a non-array attribute")
		var values: Array = source[key]
		var width := 0
		if attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
			width = 3
		elif attribute in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			width = 2
		elif attribute == Mesh.ARRAY_COLOR:
			width = 4
		if width > 0:
			if values.size() != count:
				return _invalid(label + " has mismatched vertex attributes")
			for value: Variant in values:
				if not value is Array or value.size() != width:
					return _invalid(label + " has malformed vector attributes")
				for component: Variant in value:
					if not _finite_number(component):
						return _invalid(label + " has non-finite vector attributes")
				if attribute == Mesh.ARRAY_NORMAL and absf(Vector3(value[0], value[1], value[2]).length() - 1.0) > 0.03:
					return _invalid(label + " has unnormalized normals")
		elif attribute in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_TANGENT]:
			if values.size() != count * 4:
				return _invalid(label + " has mismatched skin/tangent attributes")
			for value: Variant in values:
				if not _finite_number(value):
					return _invalid(label + " has non-finite skin/tangent attributes")
				if attribute == Mesh.ARRAY_BONES and (value != floor(value) or value < 0 or value >= bind_count):
					return _invalid(label + " has an invalid skin bind index")
				if attribute == Mesh.ARRAY_WEIGHTS and value < 0:
					return _invalid(label + " has negative skin weights")
		elif attribute == Mesh.ARRAY_INDEX:
			if values.size() % 3 != 0:
				return _invalid(label + " has incomplete triangle indices")
			for value: Variant in values:
				if not _finite_number(value) or value != floor(value) or value < 0 or value >= count:
					return _invalid(label + " has an invalid triangle index")
		else:
			return _invalid(label + " has an unsupported attribute")
	if (not source.has(str(Mesh.ARRAY_INDEX)) or source[str(Mesh.ARRAY_INDEX)].is_empty()) and count % 3 != 0:
		return _invalid(label + " has incomplete unindexed triangles")
	var weights: Array = source[str(Mesh.ARRAY_WEIGHTS)]
	for vertex: int in count:
		var total := 0.0
		for influence: int in 4:
			total += float(weights[vertex * 4 + influence])
		if absf(total - 1.0) > 0.0001:
			return _invalid(label + " has unnormalized skin weights")
	return true


func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _invalid(message: String) -> bool:
	push_error("ANGULAR_COMPILE_FAIL: " + message)
	return false


func _abort(message: String) -> void:
	_invalid(message)
	quit(1)


func _compile(original: MeshInstance3D) -> ArrayMesh:
	var key := str(original.name)
	var result := ArrayMesh.new()
	result.resource_name = original.mesh.resource_name
	for surface: int in original.mesh.get_surface_count():
		var source: Dictionary = meshes[key][surface]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		for attribute: String in source:
			var index := int(attribute)
			if index in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
				var values := PackedVector3Array()
				for value: Array in source[attribute]:
					values.append(Vector3(value[0], value[1], value[2]))
				arrays[index] = values
			elif index in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				var values := PackedVector2Array()
				for value: Array in source[attribute]:
					values.append(Vector2(value[0], value[1]))
				arrays[index] = values
			elif index == Mesh.ARRAY_COLOR:
				var values := PackedColorArray()
				for value: Array in source[attribute]:
					values.append(Color(value[0], value[1], value[2], value[3]))
				arrays[index] = values
			elif index in [Mesh.ARRAY_BONES, Mesh.ARRAY_INDEX]:
				arrays[index] = PackedInt32Array(source[attribute])
			elif index in [Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_TANGENT]:
				arrays[index] = PackedFloat32Array(source[attribute])
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, _material(original.get_active_material(surface)))
	return result


func _material(source: Material) -> Material:
	if source == null:
		return null
	var texture: Texture2D
	var tint := Color.WHITE
	if source is ShaderMaterial:
		if source.shader == null or source.shader.resource_path not in PAINT_SHADERS:
			# Specialized additive/animated materials retain their authored behavior.
			return source
		texture = source.get_shader_parameter("albedo_texture") as Texture2D
		var value: Variant = source.get_shader_parameter("albedo_tint")
		if value is Color:
			tint = value
	elif source is BaseMaterial3D:
		if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			return source
		texture = source.albedo_texture
		tint = source.albedo_color
	else:
		return source
	var material := ShaderMaterial.new()
	material.resource_name = source.resource_name
	material.shader = load(OUT + "armor_surface.gdshader")
	material.render_priority = source.render_priority
	material.next_pass = source.next_pass
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("albedo_tint", tint)
	material.set_shader_parameter("use_texture", texture != null)
	material.set_shader_parameter("readable_fill", 0.20)
	material.set_shader_parameter("surface_roughness", 0.64)
	material.set_shader_parameter("surface_specular", 0.28)
	return material
