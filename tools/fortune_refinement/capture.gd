extends Node3D

const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const OUT := "res://test_output/fortune_refinement/"
var fixture: Node3D
var files: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(900, 1000)
	get_window().content_scale_size = Vector2i(900, 1000)
	fixture = Fixture.new()
	add_child(fixture)
	fixture.setup()
	fixture.label.hide()
	fixture.player.backpack_socket.hide()
	fixture.player.gun_socket.hide()
	fixture.player.left_gun_socket.hide()
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.fill.light_energy = .8
	for child in fixture.get_children():
		if child is DirectionalLight3D: child.light_energy = 1.0
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	Visuals._restore_original_materials(original)
	var current := (load("res://assets/equipment_refined/armors/armor_01.scn") as PackedScene).instantiate()
	for version in ["original", "previous", "current", "viper"]:
		if version == "previous" and not FileAccess.file_exists(OUT + "baseline/24d26eb90e3d.png"): continue
		_set_armor(0 if version == "viper" else 1)
		fixture.player._apply_recovered_armor_visibility()
		if version != "viper":
			for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
				var name_key := prefix + "01"
				var part := fixture.player.recovered_avatar.find_child(name_key, true, false) as MeshInstance3D
				var template := (original if version == "original" else current).find_child(name_key, true, false) as MeshInstance3D
				for surface in part.get_surface_override_material_count(): part.set_surface_override_material(surface, null)
				part.mesh = template.mesh
				part.skin = template.skin
				part.transform = template.transform
				for surface in part.mesh.get_surface_count():
					var material := template.get_active_material(surface)
					if version == "previous":
						material = material.duplicate() as ShaderMaterial
						var texture: Texture2D = material.get_shader_parameter("albedo_texture")
						var image := Image.load_from_file(ProjectSettings.globalize_path(OUT + "baseline/" + texture.resource_path.get_file()))
						material.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(image))
					part.set_surface_override_material(surface, material)
		fixture.player._play_recovered_animation("idle_rifle", 0, true)
		fixture.player.recovered_animation_player.advance(0)
		fixture.player.recovered_skeleton.force_update_all_bone_transforms()
		for framing in ["full", "close"]:
			fixture.view_camera.size = 2.25 if framing == "full" else 1.25
			for view in ["front", "side", "rear"]:
				fixture.set_view(view)
				fixture.view_camera.look_at(Vector3(0, 1.0 if framing == "full" else 1.43, 0))
				await _save(version + "_" + framing + "_" + view)
	original.free()
	current.free()
	# Restore current Fortune after original/previous comparison overrides.
	_set_armor(1)
	fixture.player._apply_recovered_armor_visibility()
	for part: MeshInstance3D in fixture.player.recovered_avatar.find_children("Armor*_01", "MeshInstance3D", true, false):
		for surface in part.get_surface_override_material_count(): part.set_surface_override_material(surface, null)
	fixture.player.gun_socket.show()
	fixture.player.left_gun_socket.show()
	fixture.view_camera.size = 2.25
	for fraction in [.2, .52, .85]:
		fixture.begin("gun00", 0, true)
		fixture.advance_to(fixture.duration * fraction)
		for view in ["front", "side", "rear"]:
			fixture.set_view(view)
			fixture.view_camera.look_at(Vector3(0, 1.0, 0))
			await _save("reload_%02d_%s" % [roundi(fraction * 100), view])
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	GameState.settings.show_touch_controls = false
	for level in [1, 3]:
		_set_armor(1)
		GameState.selected_level = level
		GameState.selected_weapon = "gun00"
		GameState.battle_weapons.assign(["gun00"])
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate()
		add_child(world)
		for tick in 12: await get_tree().process_frame
		await _save("game_%d" % level)
		world.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(OUT + "captures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(files, "\t"))
	file.close()
	print("FORTUNE_CAPTURE_PASS images=", files.size())
	get_tree().quit()

func _set_armor(id: int) -> void:
	for part in 4: GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, id)

func _save(stem: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(OUT + stem + ".png") == OK)
	files.append(stem + ".png")
