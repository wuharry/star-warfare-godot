extends Node3D

# Fixed camera and animation times make the original Viper and all eight
# additions comparable at their actual gameplay scale.
const SET_IDS := [0, 21, 22, 23, 24, 25, 26, 27, 28]
const TILE_SIZE := Vector2i(426, 240)
var output_dir := "res://test_output/armor_lighting/armor"
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) != OK:
		push_error("Could not create armor capture directory")
		get_tree().quit(1)
		return
	GameState.save_path = "user://callofmini_visual_capture_profile.json"
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	GameState.apply_viewport_quality()
	GameState.credits = 1000000
	GameState.owned_armor.assign(["armor_head_00", "armor_body_00", "armor_arms_00", "armor_legs_00", "armor_bag_00"])
	GameState.equipped_armor = {"head": "armor_head_00", "body": "armor_body_00", "arms": "armor_arms_00", "legs": "armor_legs_00", "bag": "armor_bag_00"}
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17202a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b3c6dc")
	environment.ambient_light_energy = 0.8
	world_environment.environment = environment
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -35, 0)
	light.light_energy = 1.0
	add_child(light)
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	var label := Label.new()
	label.position = Vector2(28, 24)
	label.add_theme_font_size_override("font_size", 24)
	add_child(label)
	var sheet := Image.create_empty(TILE_SIZE.x * 3, TILE_SIZE.y * SET_IDS.size(), false, Image.FORMAT_RGBA8)
	var captures: Array[Dictionary] = []
	for index in SET_IDS.size():
		var set_id: int = SET_IDS[index]
		for part: String in ["head", "body", "arms", "legs"]:
			var key := "armor_%s_%02d" % [part, set_id]
			if not GameState.is_armor_owned(key):
				_check(GameState.purchase_armor(key) == "purchased", "Could not purchase " + key)
		_check(GameState.equip_armor_set(set_id), "Could not equip set %d" % set_id)
		if not failures.is_empty():
			break
		var player := WarfarePlayer.new()
		add_child(player)
		player.set_physics_process(false)
		player.position = Vector3.ZERO
		player.camera.current = false
		camera.make_current()
		for view_index in 3:
			var pose := "run_rifle" if view_index == 2 else "idle_rifle"
			player._play_recovered_animation(pose, 0.0, true)
			player.recovered_animation_player.seek(0.18 if view_index == 2 else 0.0, true)
			player.recovered_animation_player.pause()
			camera.position = Vector3(-3.1, 1.65, 3.4) if view_index == 1 else Vector3(3.1, 1.65, -3.4)
			camera.look_at(Vector3(0.0, 1.05, 0.0))
			var view_name: String = ["front", "back", "run"][view_index]
			var item: Dictionary = GameState.get_armor_item("armor_head_%02d" % set_id)
			label.text = "%s | %s | fixed camera" % [str(item.get("name", set_id)), view_name]
			for _frame in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			var filename := "set_%02d_%s.png" % [set_id, view_name]
			_check(shot.save_png(output_dir.path_join(filename)) == OK, "Could not save " + filename)
			captures.append({"set_id": set_id, "view": view_name, "file": filename})
			shot.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_LANCZOS)
			shot.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i(view_index * TILE_SIZE.x, index * TILE_SIZE.y))
		player.free()
		await get_tree().process_frame
	_check(sheet.save_png(output_dir.path_join("armor_comparison.png")) == OK, "Could not save armor comparison")
	label.hide()
	world_environment.queue_free()
	await get_tree().process_frame
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	menu._show_armory("store")
	var shell: UnityEquipmentShell = menu.equipment_shell
	shell._select_category("head", false)
	for set_id: int in SET_IDS.slice(1):
		_check(GameState.equip_armor_set(set_id), "Could not equip store preview set %d" % set_id)
		shell._select_item("armor_head_%02d" % set_id, false)
		for _frame in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var filename := "store_set_%02d.png" % set_id
		_check(get_viewport().get_texture().get_image().save_png(output_dir.path_join(filename)) == OK, "Could not save " + filename)
		captures.append({"set_id": set_id, "view": "store", "file": filename})
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	var manifest := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
	_check(manifest != null, "Could not save armor manifest")
	if manifest != null:
		manifest.store_string(JSON.stringify({"viewport": [get_viewport().size.x, get_viewport().size.y], "renderer": RenderingServer.get_current_rendering_method(), "captures": captures, "failures": failures}, "\t"))
	print("CALLOFMINI_VISUAL_CAPTURE_PASS sets=%d" % SET_IDS.size() if failures.is_empty() else "CALLOFMINI_VISUAL_CAPTURE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CALLOFMINI VISUAL CAPTURE: " + message)
