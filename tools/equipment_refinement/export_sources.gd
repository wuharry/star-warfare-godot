extends SceneTree

const OUT := "res://test_output/equipment_refinement/"
const Catalog = preload("res://scripts/core/armor_catalog.gd")
var entries: Array = []
var textures: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var avatar := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(avatar)
	for id in range(1, Catalog.SET_NAMES.size()):
		var source: Node = avatar
		if id >= Catalog.CALLOFMINI_FIRST_ID:
			source = (load(Catalog.gameplay_scene_path(id)) as PackedScene).instantiate()
		var parts: Array = []
		for prefix in ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]:
			var part := source.find_child(prefix + "%02d" % id, true, false) as MeshInstance3D
			assert(part != null, prefix + str(id))
			parts.append(_mesh(part.mesh, str(part.name), "armor_%02d" % id, part))
		entries.append({"key": "armor_%02d" % id, "kind": "armor", "id": id, "name": Catalog.SET_NAMES[id], "parts": parts})
		if source != avatar:
			source.free()
	var state := root.get_node("GameState")
	var models := {}
	for key: String in state.WEAPONS:
		var data: Dictionary = state.WEAPONS[key]
		var model_entries: Array = []
		for field in ["model", "reload_body_model", "prop_model"]:
			if not data.has(field):
				continue
			var model := str(data[field])
			var path := "res://assets/models/weapons/%s.obj" % model
			if not ResourceLoader.exists(path):
				continue
			if not models.has(model):
				models[model] = _mesh(load(path) as Mesh, model, key)
			model_entries.append({"role": field, "model": model})
		entries.append({"key": key, "kind": "weapon", "id": data.id, "name": data.get("name", key), "models": model_entries})
	var output := {"entries": entries, "weapon_meshes": models, "textures": textures}
	var file := FileAccess.open(OUT + "sources.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output))
	file.close()
	avatar.free()
	print("EQUIPMENT_SOURCE_PASS entries=%d meshes=%d textures=%d" % [entries.size(), models.size(), textures.size()])
	quit()

func _mesh(mesh: Mesh, mesh_name: String, owner_key: String, instance: MeshInstance3D = null) -> Dictionary:
	var surfaces: Array = []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var material := instance.get_active_material(surface) if instance != null else mesh.surface_get_material(surface)
		var texture: Texture2D
		if material is BaseMaterial3D:
			texture = material.albedo_texture
		elif material is ShaderMaterial:
			for parameter in ["albedo_texture", "base_texture", "texture_albedo", "diffuse_texture"]:
				var value: Variant = material.get_shader_parameter(parameter)
				if value is Texture2D:
					texture = value
					break
		var texture_path := texture.resource_path if texture != null else ""
		if not texture_path.is_empty():
			if not textures.has(texture_path):
				textures[texture_path] = {"owners": [], "materials": []}
			if not owner_key in textures[texture_path].owners:
				textures[texture_path].owners.append(owner_key)
			if material != null and not material.resource_name in textures[texture_path].materials:
				textures[texture_path].materials.append(material.resource_name)
		var flat: Dictionary = {}
		for index in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			if arrays[index] == null:
				continue
			var values: Array = []
			for value: Variant in arrays[index]:
				if value is Vector3:
					values.append([value.x, value.y, value.z])
				elif value is Vector2:
					values.append([value.x, value.y])
				elif value is Color:
					values.append([value.r, value.g, value.b, value.a])
			flat[str(index)] = values
		for index in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
			if arrays[index] != null:
				flat[str(index)] = Array(arrays[index])
		surfaces.append({"arrays": flat, "material": material.resource_name if material else "", "texture": texture_path})
	return {"name": mesh_name, "surfaces": surfaces}
