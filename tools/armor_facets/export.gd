extends SceneTree

const OUT := "res://test_output/armor_facets/"
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const PREFIXES := ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var entries: Array[Dictionary] = []
	for id: int in Catalog.SET_NAMES.size():
		if id == 6:
			continue
		var source_path := "res://assets/armors/viper/viper.scn" if id == 0 else "res://assets/equipment_refined/armors/armor_%02d.scn" % id
		var source := (load(source_path) as PackedScene).instantiate()
		var parts: Array[Dictionary] = []
		for prefix: String in PREFIXES:
			var part := source.find_child(prefix + "%02d" % id, true, false) as MeshInstance3D
			assert(part != null and part.skin != null, "Missing accepted baseline part")
			parts.append(_mesh(part))
		entries.append({"key": "armor_%02d" % id, "kind": "armor", "id": id, "name": Catalog.SET_NAMES[id], "source": source_path, "parts": parts})
		source.free()
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	var reference_parts: Array[Dictionary] = []
	for prefix: String in PREFIXES:
		reference_parts.append(_mesh(original.find_child(prefix + "06", true, false) as MeshInstance3D))
	original.free()
	var file := FileAccess.open(OUT + "sources.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"entries": entries, "reference": {"id": 6, "reference_only": true, "source": "res://assets/models/player/animated/player.gltf", "parts": reference_parts}}, "\t"))
	file.close()
	print("ANGULAR_EXPORT_PASS sets=%d" % entries.size())
	quit()


func _mesh(part: MeshInstance3D) -> Dictionary:
	var surfaces: Array[Dictionary] = []
	for surface: int in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var flat: Dictionary = {}
		for index: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			if arrays[index] == null:
				continue
			var values: Array = []
			for value: Variant in arrays[index]:
				values.append(_json_value(value))
			flat[str(index)] = values
		for index: int in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
			if arrays[index] != null:
				flat[str(index)] = Array(arrays[index])
		var material := part.get_active_material(surface)
		var parameters: Dictionary = {}
		var texture_path := ""
		if material is ShaderMaterial:
			for uniform: Dictionary in material.shader.get_shader_uniform_list():
				parameters[uniform.name] = _json_value(material.get_shader_parameter(uniform.name))
			for parameter: String in ["albedo_texture", "base_texture", "texture_albedo", "diffuse_texture"]:
				var value: Variant = material.get_shader_parameter(parameter)
				if value is Texture2D:
					texture_path = value.resource_path
					break
		elif material is BaseMaterial3D:
			for property: Dictionary in material.get_property_list():
				if int(property.usage) & PROPERTY_USAGE_STORAGE:
					parameters[property.name] = _json_value(material.get(property.name))
			if material.albedo_texture != null:
				texture_path = material.albedo_texture.resource_path
		surfaces.append({"arrays": flat, "material": material.resource_name if material != null else "", "texture": texture_path, "material_class": material.get_class() if material != null else "", "shader": material.shader.resource_path if material is ShaderMaterial else "", "parameters": parameters})
	var binds: Array[Dictionary] = []
	for bind: int in part.skin.get_bind_count():
		binds.append({"index": bind, "name": str(part.skin.get_bind_name(bind)), "bone": part.skin.get_bind_bone(bind)})
	return {"name": str(part.name), "surfaces": surfaces, "binds": binds}


func _json_value(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Resource:
		return value.resource_path
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return str(value)
