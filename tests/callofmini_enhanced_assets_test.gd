extends SceneTree

const ENHANCED_ROOT := "res://assets/callOfMini/enhanced"
const OUTPUT_SIZE := Vector2i(1024, 1024)
const TEXTURE_NAMES := ["armor.png", "equip.png", "helmet.png"]
const ARMOR_MODELS := {
	"Assault Armor": "AssaultArmor.dae",
	"Combat Suit": "CombatSuit.dae",
	"Drillmaster": "Drillmaster.dae",
	"Heavy Battlesuit": "HeavyBattlesuit.dae",
	"Mark-6 117R": "Mark6117R.dae",
	"Recon Suit": "ReconSuit.dae",
	"Sanguine Chaos": "Sanguine.dae",
	"Training Suit": "TrainingSuit.dae",
}


func _initialize() -> void:
	for armor_name: String in ARMOR_MODELS:
		_validate_armor(armor_name, ARMOR_MODELS[armor_name])
	print("CALLOFMINI_ENHANCED_ASSETS_TEST_PASS armors=%d textures=%d resolution=%s" % [
		ARMOR_MODELS.size(),
		ARMOR_MODELS.size() * TEXTURE_NAMES.size(),
		OUTPUT_SIZE,
	])
	quit(0)


func _validate_armor(armor_name: String, model_name: String) -> void:
	var armor_root := ENHANCED_ROOT.path_join(armor_name)
	for texture_name: String in TEXTURE_NAMES:
		var texture_path := armor_root.path_join(texture_name)
		var source_path := armor_root.path_join("source").path_join(texture_name)
		assert(FileAccess.file_exists(texture_path), "Missing enhanced texture: " + texture_path)
		assert(FileAccess.file_exists(source_path), "Missing preserved source texture: " + source_path)

		var image := Image.load_from_file(ProjectSettings.globalize_path(texture_path))
		assert(not image.is_empty(), "Could not decode enhanced texture: " + texture_path)
		assert(image.get_size() == OUTPUT_SIZE, "%s is %s instead of %s" % [texture_path, image.get_size(), OUTPUT_SIZE])
		assert(image.get_format() == Image.FORMAT_RGBA8, "Enhanced texture lost RGBA format: " + texture_path)

		var imported_texture := load(texture_path) as Texture2D
		assert(imported_texture != null, "Godot did not import enhanced texture: " + texture_path)
		assert(imported_texture.get_size() == Vector2(OUTPUT_SIZE), "Imported texture size drifted: " + texture_path)

		var import_text := FileAccess.get_file_as_string(texture_path + ".import")
		assert(import_text.contains("compress/mode=2"), "Texture is not using the armor VRAM compression profile: " + texture_path)
		assert(import_text.contains("mipmaps/generate=true"), "Texture is missing 3D mipmaps: " + texture_path)
		_validate_source_alpha(texture_path, source_path)

	var model_path := armor_root.path_join(model_name)
	assert(FileAccess.file_exists(model_path), "Missing enhanced armor model: " + model_path)
	var imported_dae := load(model_path) as PackedScene
	assert(imported_dae != null, "Godot did not import enhanced armor DAE: " + model_path)
	var ready_path := model_path.get_basename() + ".tscn"
	assert(FileAccess.file_exists(ready_path), "Missing Godot-ready armor scene: " + ready_path)
	var model_scene := load(ready_path) as PackedScene
	assert(model_scene != null, "Godot did not load enhanced armor scene: " + ready_path)
	var model := model_scene.instantiate()
	root.add_child(model)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	assert(not meshes.is_empty(), "Enhanced armor has no renderable meshes: " + model_path)
	var textured_surfaces := 0
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				assert(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Ready scene lost baked-lighting material mode: " + ready_path)
				assert(material.cull_mode == BaseMaterial3D.CULL_DISABLED, "Ready scene material is not double-sided: " + ready_path)
				assert(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "Ready scene lost anisotropic texture filtering: " + ready_path)
				textured_surfaces += 1
	assert(textured_surfaces >= 3, "%s did not retain all three texture bindings" % ready_path)
	model.queue_free()


func _validate_source_alpha(texture_path: String, source_path: String) -> void:
	var final_image := Image.load_from_file(ProjectSettings.globalize_path(texture_path))
	var source_image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	source_image.convert(Image.FORMAT_RGBA8)
	source_image.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	for y in range(0, OUTPUT_SIZE.y, 31):
		for x in range(0, OUTPUT_SIZE.x, 31):
			assert(
				is_equal_approx(final_image.get_pixel(x, y).a, source_image.get_pixel(x, y).a),
				"Enhanced texture alpha escaped its source UV mask at %s (%d, %d)" % [texture_path, x, y]
			)


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, output)
