extends Node3D

const EquipmentRefinement = preload("res://scripts/core/equipment_refinement.gd")

# Audit the actual equipped models before assigning optics in weapon_optics.gd.
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Optics model audit requires a real renderer")
		get_tree().quit(1)
		return
	var directory := "res://test_output/scope_aim/models"
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open("res://test_output/scope_aim/.gdignore", FileAccess.WRITE).close()
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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.2
	add_child(camera)
	camera.current = true
	camera.position = Vector3(3, 1.0, -0.7)
	camera.look_at(Vector3.ZERO)
	var label := Label.new()
	label.position = Vector2(18, 12)
	label.add_theme_font_size_override("font_size", 24)
	add_child(label)
	var helper := WarfarePlayer.new()
	var sheet := Image.create(1920, 1440, false, Image.FORMAT_RGB8)
	var rear_sheet := Image.create(1920, 1440, false, Image.FORMAT_RGB8)
	for id in 47:
		camera.position = Vector3(3, 1.0, -0.7)
		camera.look_at(Vector3.ZERO)
		var key := "gun%02d" % id
		label.text = key + " / " + str(GameState.WEAPONS[key].name)
		var mesh := MeshInstance3D.new()
		mesh.mesh = EquipmentRefinement.weapon_mesh(key)
		mesh.rotation_degrees = helper._weapon_authored_rotation(id) + Vector3(90, 0, 0)
		var bounds := EquipmentRefinement.authored_bounds(mesh.mesh)
		mesh.scale *= 1.55 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		mesh.position = -(mesh.basis * bounds.get_center())
		helper._repair_recovered_weapon_materials(mesh, id)
		# Neutral, unshaded inspection exposes the actual texture and geometry;
		# these material copies are local to the audit, not runtime asset edits.
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source:
				var material := source.duplicate() as StandardMaterial3D
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.albedo_color = Color.WHITE
				mesh.set_surface_override_material(surface, material)
		add_child(mesh)
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var capture := get_viewport().get_texture().get_image()
		if capture.save_png(directory + "/" + key + ".png") != OK:
			get_tree().quit(1)
			return
		capture.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		capture.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(capture, Rect2i(0, 0, 320, 180), Vector2i(id % 6, id / 6) * Vector2i(320, 180))
		camera.position = Vector3(1.0, 0.7, 3.0)
		camera.look_at(Vector3.ZERO)
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var rear := get_viewport().get_texture().get_image()
		if rear.save_png(directory + "/" + key + "_rear.png") != OK:
			get_tree().quit(1)
			return
		rear.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		rear.convert(Image.FORMAT_RGB8)
		rear_sheet.blit_rect(rear, Rect2i(0, 0, 320, 180), Vector2i(id % 6, id / 6) * Vector2i(320, 180))
		mesh.free()
	helper.free()
	var error := sheet.save_png(directory + "/all_weapons.png")
	if rear_sheet.save_png(directory + "/all_weapons_rear.png") != OK:
		error = FAILED
	print("WEAPON_OPTICS_MODEL_CAPTURE_PASS" if error == OK else "WEAPON_OPTICS_MODEL_CAPTURE_FAIL")
	get_tree().quit(0 if error == OK else 1)
