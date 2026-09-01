extends Node3D

func _ready() -> void:
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
