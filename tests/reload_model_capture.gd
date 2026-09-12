extends Node3D

const IDS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 30, 34, 35, 40, 41, 43, 45]

func _ready() -> void:
	var directory := "res://test_output/reload_catalog/models"
	DirAccess.make_dir_recursive_absolute(directory)
	var ignore := FileAccess.open("res://test_output/reload_catalog/.gdignore", FileAccess.WRITE)
	ignore.close()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.1
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -45, 0)
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(3, 1, 0)
	fill.light_energy = 3
	fill.omni_range = 8
	add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.95
	add_child(camera)
	camera.current = true
	var label := Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 26)
	add_child(label)
	var helper := WarfarePlayer.new()
	for id in IDS:
		var key := "gun%02d" % id
		label.text = key + " / " + str(GameState.WEAPONS[key].name)
		var mesh := MeshInstance3D.new()
		mesh.mesh = load("res://assets/models/weapons/" + key + ".obj")
		mesh.rotation_degrees = helper._weapon_authored_rotation(id) + Vector3(90, 0, 0)
		var bounds := mesh.mesh.get_aabb()
		mesh.scale *= 1.55 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		mesh.position = -(mesh.basis * bounds.get_center())
		helper._repair_recovered_weapon_materials(mesh, id)
		add_child(mesh)
		var data: Dictionary = GameState.WEAPONS[key]
		for view in ["side", "angle"]:
			camera.position = Vector3(3, 0, 0) if view == "side" else Vector3(3, 1.4, -1.0)
			camera.look_at(Vector3.ZERO)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var error := get_viewport().get_texture().get_image().save_png(directory + "/" + key + "_" + view + ".png")
			if error != OK:
				get_tree().quit(1)
				return
		if data.has("reload_body_model"):
			mesh.mesh = load("res://assets/models/weapons/" + str(data.reload_body_model) + ".obj")
			for surface in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(surface, null)
			helper._repair_recovered_weapon_materials(mesh, id)
			var part := MeshInstance3D.new()
			part.mesh = load("res://assets/models/weapons/" + str(data.prop_model) + ".obj")
			part.transform = mesh.transform
			var highlight := StandardMaterial3D.new()
			highlight.albedo_color = Color(0.10, 0.95, 0.75)
			highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			part.material_override = highlight
			add_child(part)
			if key == "gun45":
				camera.position = Vector3(-3, 1.4, -1)
				camera.look_at(Vector3.ZERO)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(directory + "/" + key + "_part.png")
			part.position += mesh.basis * Vector3(data.reload_outward) * 0.25
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(directory + "/" + key + "_exploded.png")
			part.free()
		else:
			var port := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.026
			sphere.height = 0.052
			port.mesh = sphere
			port.position = mesh.transform * Vector3(data.reload_port)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.10, 0.95, 0.75)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			port.material_override = material
			add_child(port)
			camera.position = Vector3(-3, -0.6, -1)
			camera.look_at(Vector3.ZERO)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(directory + "/" + key + "_part.png")
			port.free()
		mesh.free()
	helper.free()
	print("RELOAD_MODELS_CAPTURE_PASS count=24")
	get_tree().quit()
