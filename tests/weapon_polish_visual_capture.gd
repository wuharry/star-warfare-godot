extends Node3D

func _ready() -> void:
	GameState.settings.quality = "high"
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	world.completed = true
	world.player.set_physics_process(false)
	world.player.camera.current = false
	world.effects_root.reparent(self)
	for child in world.get_children():
		if child is Node3D: child.visible = false
		elif child is CanvasLayer: child.visible = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.5
	camera.position = Vector3(0, 1, 15)
	add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.04, 0.065)
	add_child(environment)
	camera.environment = environment.environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -25, 0)
	add_child(light)
	_label("BLUE LASER / ENERGY FLOW", Vector3(-4, 4.0, 0))
	_label("PLASMA / CURVED AFTERIMAGE", Vector3(-4, 1.7, 0))
	_label("RPG / HOT EXHAUST TRAIL", Vector3(-4, -0.7, 0))
	var bolts: Array[WarfareProjectile] = []
	for index in 2:
		var bolt := WarfareProjectile.new()
		bolt.configure(world.player, Vector3.RIGHT, 12, 10, 1, Color(0.08, 1, 0.5) if index == 0 else Color(1, 0.38, 0.08), false, "plasma" if index == 0 else "rocket", "", "gun20" if index == 0 else "gun11")
		bolt.position = Vector3(-4, 0.8 - index * 2.4, 0)
		add_child(bolt)
		bolt.set_physics_process(false)
		bolts.append(bolt)
	for frame in 30:
		for index in 2:
			bolts[index].position.x = -4.0 + frame * 0.18
			if index == 0:
				bolts[index].position.y = 0.6 + sin(frame * 0.14) * 0.32
		await get_tree().create_timer(0.016).timeout
	world.spawn_tracer(Vector3(-5.2, 3.0, 0), Vector3(5.2, 3.0, 0), Color(0.08, 0.7, 1), "laser")
	world.spawn_impact(Vector3(5.2, 3.0, 0), Vector3.LEFT, Color(0.08, 0.7, 1), "laser")
	# Hold a readable beam pose while the real particle renderer warms up.
	for tween in get_tree().get_processed_tweens(): tween.pause()
	for effect in get_tree().get_nodes_in_group("weapon_vfx_polish"):
		effect._process(0.025)
		effect.set_process(false)
	await get_tree().create_timer(0.06).timeout
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("Weapon capture requires a real renderer")
		get_tree().quit(1)
		return
	var suffix := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	var result := get_viewport().get_texture().get_image().save_png("res://test_output/weapon_polish_%s.png" % suffix)
	print("WEAPON_POLISH_CAPTURE_PASS " + suffix if result == OK else "WEAPON_POLISH_CAPTURE_FAIL")
	get_tree().quit(0 if result == OK else 1)

func _label(value: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.font_size = 32
	label.modulate = Color(0.65, 0.8, 0.95)
	add_child(label)
