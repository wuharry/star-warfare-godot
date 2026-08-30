extends Node3D

func _ready() -> void:
	GameState.selected_weapon = "gun00"
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.045, 0.055)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.82, 0.92)
	environment.ambient_light_energy = 1.8
	environment_node.environment = environment
	add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -35, 0)
	light.light_energy = 2.4
	add_child(light)

	var player := WarfarePlayer.new()
	add_child(player)
	for _frame in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	player.camera.current = false
	player._play_recovered_animation("idle_rifle", 0.0)

	var camera := Camera3D.new()
	camera.position = Vector3(3.1, 1.65, -3.4)
	camera.fov = 40.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	camera.current = true
	for _frame in range(6):
		await get_tree().process_frame
	var idle_error := get_viewport().get_texture().get_image().save_png("res://tests/weapon_pose_idle_preview.png")

	player.set_physics_process(true)
	player.shot_cooldown = 0.0
	player._try_fire()
	for _frame in range(3):
		await get_tree().process_frame
		await get_tree().physics_frame
	player.set_physics_process(false)
	var fire_error := get_viewport().get_texture().get_image().save_png("res://tests/weapon_pose_fire_preview.png")
	if idle_error == OK and fire_error == OK:
		print("WEAPON_POSE_VISUAL_CAPTURE_PASS")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
