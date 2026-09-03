extends SceneTree

const ENHANCED_ROOT := "res://assets/callOfMini/enhanced"
const PREVIEW_PATH := "res://tests/callofmini_enhanced_preview.png"
const TILE_SIZE := Vector2i(512, 512)
const COLUMNS := 4
const ARMOR_MODELS := [
	["ASSAULT ARMOR", "Assault Armor", "AssaultArmor.tscn"],
	["COMBAT SUIT", "Combat Suit", "CombatSuit.tscn"],
	["DRILLMASTER", "Drillmaster", "Drillmaster.tscn"],
	["HEAVY BATTLESUIT", "Heavy Battlesuit", "HeavyBattlesuit.tscn"],
	["MARK-6 117R", "Mark-6 117R", "Mark6117R.tscn"],
	["RECON SUIT", "Recon Suit", "ReconSuit.tscn"],
	["SANGUINE CHAOS", "Sanguine Chaos", "Sanguine.tscn"],
	["TRAINING SUIT", "Training Suit", "TrainingSuit.tscn"],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rows := ceili(float(ARMOR_MODELS.size()) / float(COLUMNS))
	var contact_sheet := Image.create(TILE_SIZE.x * COLUMNS, TILE_SIZE.y * rows, false, Image.FORMAT_RGBA8)
	contact_sheet.fill(Color("081018"))

	for armor_index in ARMOR_MODELS.size():
		var armor_entry: Array = ARMOR_MODELS[armor_index]
		var tile := await _render_armor(String(armor_entry[0]), String(armor_entry[1]), String(armor_entry[2]))
		var tile_position := Vector2i(
			(armor_index % COLUMNS) * TILE_SIZE.x,
			(armor_index / COLUMNS) * TILE_SIZE.y
		)
		contact_sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, TILE_SIZE), tile_position)

	var save_error: Error = contact_sheet.save_png(ProjectSettings.globalize_path(PREVIEW_PATH))
	assert(save_error == OK, "Could not save Call of Mini armor preview: " + error_string(save_error))
	print("CALLOFMINI_PREVIEW_READY path=%s armors=%d size=%s" % [PREVIEW_PATH, ARMOR_MODELS.size(), contact_sheet.get_size()])
	quit(0)


func _render_armor(label_text: String, armor_folder: String, model_name: String) -> Image:
	var viewport := SubViewport.new()
	viewport.size = TILE_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)

	var stage := Node3D.new()
	viewport.add_child(stage)
	_add_environment(stage)
	_add_lights(stage)

	var model_path := ENHANCED_ROOT.path_join(armor_folder).path_join(model_name)
	var packed := load(model_path) as PackedScene
	assert(packed != null, "Could not load preview model: " + model_path)
	var model := packed.instantiate() as Node3D
	assert(model != null, "Armor preview root is not Node3D: " + model_path)
	stage.add_child(model)
	model.rotation_degrees.y = -18.0
	_prepare_preview_materials(model)

	var bounds := _model_bounds(model)
	assert(bounds.size.length_squared() > 0.0, "Armor preview has empty bounds: " + model_path)
	var focus := bounds.get_center()
	var radius := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 0.5
	var camera := Camera3D.new()
	camera.fov = 32.0
	stage.add_child(camera)
	var distance := maxf(1.0, radius / tan(deg_to_rad(camera.fov * 0.5)) * 1.28)
	var view_focus := focus + Vector3(0.0, radius * 0.12, 0.0)
	camera.position = view_focus + Vector3(0.0, radius * 0.03, distance)
	camera.look_at(view_focus, Vector3.UP)

	var label := Label.new()
	label.text = label_text
	label.position = Vector2(22, 20)
	label.z_index = 100
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color("bcecff"))
	label.add_theme_color_override("font_outline_color", Color("071018"))
	label.add_theme_constant_override("outline_size", 6)
	viewport.add_child(label)

	# The headless display driver does not emit frame_post_draw on every host.
	# Advancing several scene frames is enough for a SubViewport UPDATE_ALWAYS
	# target and keeps the preview job deterministic in CI.
	await process_frame
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image


func _add_environment(stage: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("081018")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("90b8c8")
	environment.ambient_light_energy = 0.62
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)


func _add_lights(stage: Node3D) -> void:
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color("d8f1ff")
	key_light.light_energy = 1.45
	key_light.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	stage.add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color("6fa8ff")
	rim_light.light_energy = 0.72
	rim_light.rotation_degrees = Vector3(28.0, 150.0, 0.0)
	stage.add_child(rim_light)


func _model_bounds(model: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	var bounds := AABB()
	var has_bounds := false
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if not has_bounds:
			bounds = mesh_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(mesh_bounds)
	return bounds


func _prepare_preview_materials(model: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var imported := mesh_instance.mesh.surface_get_material(surface_index) as BaseMaterial3D
			if imported == null:
				continue
			var preview_material := imported.duplicate() as BaseMaterial3D
			preview_material.albedo_color = Color.WHITE
			# These legacy atlases already contain their key/fill shading. An unshaded
			# preview evaluates UV placement directly and avoids platform-dependent
			# legacy Collada normal orientation from hiding the texture work.
			preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			preview_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mesh_instance.set_surface_override_material(surface_index, preview_material)


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, output)
