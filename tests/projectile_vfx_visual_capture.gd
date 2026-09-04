extends Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.settings.quality = "high"
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	world.completed = true
	world.player.camera.current = false
	world.effects_root.reparent(self)
	for child in world.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = false

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.0, 13.0)
	camera.fov = 48.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)
	camera.current = true

	var backdrop := MeshInstance3D.new()
	var backdrop_mesh := QuadMesh.new()
	backdrop_mesh.size = Vector2(16.0, 10.0)
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop_material.albedo_color = Color(0.012, 0.018, 0.032)
	backdrop_mesh.material = backdrop_material
	backdrop.mesh = backdrop_mesh
	backdrop.position = Vector3(0.0, 2.0, -0.5)
	add_child(backdrop)
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(0.82, 0.9, 1.0)
	key_light.light_energy = 2.2
	key_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	add_child(key_light)

	_add_label("RIFLE • 1 IN 3", Vector3(-6.7, 5.1, 0.0), Color(1.0, 0.72, 0.18))
	_add_label("MACHINEGUN • 1 IN 5", Vector3(-6.7, 3.0, 0.0), Color(1.0, 0.82, 0.3))
	_add_label("BLUE LASER • EVERY SHOT", Vector3(-6.7, 0.9, 0.0), Color(0.18, 0.82, 1.0))
	_add_label("ORIGINAL UNITY RPG • HD", Vector3(-6.7, -1.2, 0.0), Color(0.7, 0.92, 0.3))
	var starts := [Vector3(-5.7, 4.35, 0.0), Vector3(-5.7, 2.25, 0.0), Vector3(-5.7, 0.15, 0.0)]
	var ends := [Vector3(5.7, 4.35, 0.0), Vector3(5.7, 2.25, 0.0), Vector3(5.7, 0.15, 0.0)]
	world.spawn_muzzle_effect(starts[0], Vector3.RIGHT, "rifle")
	world.spawn_tracer(starts[0], ends[0], Color(1.0, 0.64, 0.08), "rifle")
	world.spawn_impact(ends[0], Vector3.LEFT, Color(1.0, 0.64, 0.08), "rifle")
	world.spawn_muzzle_effect(starts[1], Vector3.RIGHT, "machinegun")
	world.spawn_machinegun_muzzle_fx(starts[1], Vector3.RIGHT)
	world.spawn_tracer(starts[1], ends[1], Color(1.0, 0.72, 0.08), "machinegun")
	world.spawn_impact(ends[1], Vector3.LEFT, Color(1.0, 0.72, 0.08), "machinegun")
	world.spawn_muzzle_effect(starts[2], Vector3.RIGHT, "laser")
	world.spawn_tracer(starts[2], ends[2], Color(0.08, 0.78, 1.0), "laser")
	world.spawn_impact(ends[2], Vector3.LEFT, Color(0.08, 0.78, 1.0), "laser")
	var rocket := WarfareProjectile.new()
	rocket.configure(world.player, Vector3.RIGHT, 12.0, 10.0, 1.0, Color(1.0, 0.55, 0.15), false, "rocket", "", "gun11")
	rocket.position = Vector3(-0.8, -1.95, 0.0)
	rocket.scale = Vector3.ONE * 1.55
	add_child(rocket)
	rocket.set_physics_process(false)
	for tween in get_tree().get_processed_tweens():
		tween.pause()
	# Fixed frame waits work in both interactive and headless renderers. Waiting
	# for frame_post_draw can stall forever while a new particle shader compiles.
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		print("PROJECTILE_VFX_VISUAL_CAPTURE_SKIP renderer=headless")
		get_tree().quit(0)
		return
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/projectile_vfx_preview.png")
	if error == OK:
		print("PROJECTILE_VFX_VISUAL_CAPTURE_PASS")
		get_tree().quit(0)
	else:
		push_error("Could not save projectile VFX preview: %s" % error_string(error))
		get_tree().quit(1)

func _add_label(text_value: String, position_value: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = 38
	label.modulate = color
	label.outline_size = 8
	label.position = position_value
	label.no_depth_test = true
	add_child(label)
