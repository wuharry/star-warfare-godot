extends Node3D

func _ready() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--family="):
			await _capture_family(argument.trim_prefix("--family="))
			return
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.028, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.78, 0.94)
	environment.ambient_light_energy = 1.7
	environment_node.environment = environment
	add_child(environment_node)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	key_light.light_energy = 2.5
	add_child(key_light)

	var bow_player := WarfarePlayer.new()
	add_child(bow_player)
	bow_player.position = Vector3(-0.9, 0.0, 0.0)
	bow_player.equip_weapon("gun22", false)
	var glove_player := WarfarePlayer.new()
	add_child(glove_player)
	glove_player.position = Vector3(0.9, 0.0, 0.0)
	glove_player.equip_weapon("gun23", false)
	for _frame in range(5):
		await get_tree().process_frame
		await get_tree().physics_frame
	for player in [bow_player, glove_player]:
		player.set_physics_process(false)
		player.camera.current = false
	bow_player._play_recovered_animation("idle_bow", 0.0)
	glove_player._play_recovered_animation("idle_fist", 0.0)

	var camera := Camera3D.new()
	camera.position = Vector3(4.3, 2.15, -5.2)
	camera.fov = 38.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	camera.current = true
	for _frame in range(8):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/special_weapon_restoration_preview.png")
	if error == OK:
		print("SPECIAL_WEAPON_VISUAL_CAPTURE_PASS bow=gun22 glove=gun23")
		get_tree().quit(0)
	else:
		push_error("Could not save special weapon preview: %s" % error_string(error))
		get_tree().quit(1)


func _capture_family(family: String) -> void:
	var families := {
		"machinegun": ["gun24", "gun25", "gun39"],
		"bow": ["gun22", "gun29", "gun44"],
		"blade": ["gun27", "gun28", "gun33"],
		"fist": ["gun23", "gun36"],
		"bag": ["armor_bag_01", "armor_bag_14", "armor_bag_21"],
	}
	if not families.has(family) or DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.028, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.78, 0.94)
	environment.ambient_light_energy = 0.12 if family == "bag" else 1.4
	var environment_node := WorldEnvironment.new()
	environment_node.environment = environment
	add_child(environment_node)
	if family != "bag":
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-42, -28, 0)
		light.light_energy = 2.0
		add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(1.8, 2.1, -7.0)
	camera.fov = 36.0
	camera.look_at(Vector3(0, 1.15, 0))
	camera.current = true
	var stage := "after"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-stage="):
			stage = argument.trim_prefix("--review-stage=").get_file()
	var ids: Array = families[family]
	var players: Array[WarfarePlayer] = []
	for index in ids.size():
		var player := WarfarePlayer.new()
		if family == "bag":
			GameState.equipped_armor.bag = ids[index]
		add_child(player)
		player.set_physics_process(false)
		player.position.x = (float(index) - float(ids.size() - 1) * 0.5) * 2.5
		if family == "bag" or "--back-review" in OS.get_cmdline_user_args():
			player.rotation.y = PI
		if family != "bag":
			player.equip_weapon(ids[index], false)
		var clip := "idle_" + str(player.current_weapon.animation)
		player._play_recovered_animation(clip, 0.0)
		player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.recovered_animation_player.advance(0.0)
		player.camera.current = false
		players.append(player)
		var label := Label3D.new()
		label.text = str(ids[index])
		label.position = Vector3(player.position.x, -0.12, 0)
		label.font_size = 38
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		await get_tree().process_frame
	camera.current = true
	var firing := "--fire-review" in OS.get_cmdline_user_args()
	var slashes: Array[WeaponVfxPolish] = []
	var sample_step := 0.012
	if firing:
		for player in players:
			player.shot_cooldown = 0.0
			player._try_fire()
			var clip_name := "stand_shoot_" + str(player.current_weapon.animation)
			var rate := player._shoot_animation_rate(clip_name)
			player._play_recovered_animation(clip_name, 0.0, true, rate)
			player.recovered_animation_player.advance(0.0)
			var clip := player.recovered_animation_player.get_animation(player.recovered_animation_name)
			sample_step = clip.length / rate / 8.0
		for effect: WeaponVfxPolish in get_tree().get_nodes_in_group(WeaponVfxPolish.GROUP):
			if effect.mode == "slash":
				effect.set_process(false)
				slashes.append(effect)
	for frame in 8:
		if firing:
			for player in players:
				player.recovered_animation_player.advance(sample_step)
		await get_tree().process_frame
		if firing:
			for slash in slashes:
				if is_instance_valid(slash) and not slash.is_queued_for_deletion():
					slash._process(sample_step)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://test_output/weapon_%s_%s_frame%02d.png" % [family, stage, frame])
	var path := "res://test_output/weapon_%s_%s.png" % [family, stage]
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("SPECIAL_WEAPON_FAMILY_CAPTURE %s %s" % [family, path])
	AudioDirector.stop_all_sfx()
	get_tree().quit(0 if error == OK else 1)
