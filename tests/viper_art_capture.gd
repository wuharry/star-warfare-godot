extends Node3D

const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const OUT := "res://test_output/armor_rework/"
var fixture: Node3D
var manifest: Array[Dictionary] = []
var clip_durations := {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(800, 900)
	get_window().content_scale_size = Vector2i(800, 900)
	fixture = Fixture.new()
	add_child(fixture)
	fixture.setup()
	fixture.label.visible = false
	fixture.player.backpack_socket.visible = false
	fixture.player.gun_socket.visible = false
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.view_camera.size = 2.12
	fixture.fill.light_energy = 0.8
	for child in fixture.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 1.0
			child.shadow_enabled = true
	fixture.player.recovered_animation_tree.active = false
	fixture.player.recovered_animation_player.stop()
	fixture.player.recovered_skeleton.reset_bone_poses()
	fixture.player.recovered_skeleton.force_update_all_bone_transforms()
	for view in ["front", "side", "rear"]:
		fixture.set_view(view)
		fixture.view_camera.look_at(Vector3(0, 0.97, 0))
		await _save("godot_" + view)
	# Compare both real meshes using identical pose, framing and lighting.
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate() as Node3D
	preload("res://scripts/game/armor_visuals.gd")._restore_original_materials(original)
	var new_parts := {}
	for prefix: String in preload("res://scripts/game/armor_visuals.gd").ORIGINAL_PART_PREFIXES:
		var part := fixture.player.recovered_avatar.find_child(prefix + "00", true, false) as MeshInstance3D
		new_parts[part.name] = {"mesh": part.mesh, "skin": part.skin}
	for version in ["original", "viper"]:
		for part_name: String in new_parts:
			var part := fixture.player.recovered_avatar.find_child(part_name, true, false) as MeshInstance3D
			var old_part := original.find_child(part_name, true, false) as MeshInstance3D
			part.mesh = old_part.mesh if version == "original" else new_parts[part_name].mesh
			part.skin = old_part.skin if version == "original" else new_parts[part_name].skin
			for surface in part.mesh.get_surface_count():
				part.set_surface_override_material(surface, old_part.get_active_material(surface) if version == "original" else null)
		for frame in range(24):
			var angle := TAU * frame / 24.0
			fixture.view_camera.position = Vector3(sin(angle) * 3.8, 1.6, -cos(angle) * 3.8)
			fixture.view_camera.look_at(Vector3(0, 0.97, 0))
			fixture.fill.position = fixture.view_camera.position
			await _save("%s_turn_%02d" % [version, frame])
	original.free()
	fixture.player.gun_socket.visible = true
	for key in ["gun00", "gun11"]:
		for variant in range(3 if key == "gun00" else 2):
			fixture.begin(key, variant)
			clip_durations["%s_%d" % [key, variant]] = fixture.duration
			fixture.set_view("front")
			fixture.view_camera.look_at(Vector3(0, 0.97, 0))
			for frame in range(30):
				fixture.advance_to(fixture.duration * frame / 29.0)
				await _save("%s_%d_%02d" % [key, variant, frame])
	for mode in ["run", "fly"]:
		fixture.player.armor_skills["fly"] = 1.0 if mode == "fly" else 0.0
		fixture.begin("gun00", 1, true)
		fixture.advance_to(fixture.duration * 0.52)
		for view in ["front", "side", "rear"]:
			fixture.set_view(view)
			fixture.view_camera.look_at(Vector3(0, 0.97, 0))
			await _save(mode + "_" + view)
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	for level in [1, 3]:
		GameState.selected_level = level
		GameState.selected_weapon = "gun00"
		GameState.equipped_armor = GameState._default_armor_equipment()
		GameState.settings.show_touch_controls = false
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		add_child(world)
		for tick in range(12):
			await get_tree().process_frame
		await _save("game_stage_%d" % level)
		world.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(OUT + "capture_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": "gl_compatibility", "clip_durations": clip_durations, "frames": manifest}, "\t"))
	file.close()
	print("VIPER_ART_CAPTURE_PASS")
	get_tree().quit()


func _save(stem: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OUT + stem + ".png")
	manifest.append({"name": stem, "width": get_viewport().get_texture().get_width(), "height": get_viewport().get_texture().get_height()})
	if error != OK:
		push_error("Viper capture failed: " + stem)
		get_tree().quit(1)
