extends Node3D

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.025, 0.035, 0.055)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.54, 0.62, 0.76)
	settings.ambient_light_energy = 1.2
	environment.environment = settings
	add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	key.light_energy = 2.0
	key.shadow_enabled = true
	add_child(key)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(18.0, 10.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.08, 0.11, 0.14)
	floor_material.roughness = 0.8
	floor_mesh.material = floor_material
	floor.mesh = floor_mesh
	add_child(floor)

	var target := WarfarePlayer.new()
	target.process_mode = Node.PROCESS_MODE_DISABLED
	target.position = Vector3(0.0, 0.0, -8.0)
	add_child(target)
	target.visible = false

	var kinds := ["crawler", "spitter", "brute", "boss"]
	var positions := [
		Vector3(-4.2, 0.0, 0.0),
		Vector3(-1.5, 0.0, 0.0),
		Vector3(1.5, 0.0, 0.0),
		Vector3(4.5, 0.0, 0.8),
	]
	for index in range(kinds.size()):
		var enemy := WarfareEnemy.new()
		enemy.configure(target, kinds[index], 100.0)
		enemy.position = positions[index]
		add_child(enemy)
		enemy.spawn_left = 0.0
		enemy.model.position.y = 0.0
		enemy._play_recovered_animation("fly_idle" if kinds[index] == "boss" else "idle", 0.0)
		enemy._face_planar_direction(Vector3(0.0, 0.0, -1.0))
		enemy.process_mode = Node.PROCESS_MODE_DISABLED

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.2, -12.0)
	camera.fov = 52.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.55, 0.25), Vector3.UP)
	camera.current = true

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/enemy_direction_preview.png")
	if error == OK:
		print("ENEMY_DIRECTION_VISUAL_CAPTURE_PASS")
		get_tree().quit(0)
	else:
		push_error("Could not save enemy direction preview: %s" % error_string(error))
		get_tree().quit(1)
