extends Node3D

func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position.z = 10
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0.018, 0.026, 0.045)
	add_child(camera)
	camera.current = true
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 4.8, 0.4)
	wall.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.14, 0.16, 0.2)
	wall.material_override = material
	wall.position.z = 1
	add_child(wall)
	var beam := WeaponVfxPolish.beam(self, Vector3(-4.8, 1, 0), Vector3(4.8, 1, 0), Color(0.08, 0.65, 1))
	beam._process(0.035)
	beam.set_process(false)
	var source := Node3D.new()
	add_child(source)
	var trail := WeaponVfxPolish.trail(source, Color(0.08, 1, 0.45), "plasma")
	trail.set_process(false)
	for step in 40:
		source.position = Vector3(-4.8 + step * 0.24, -1 + sin(step * 0.12) * 0.4, 0)
		trail._process(0.005)
	var burst := WeaponVfxPolish.burst(self, Vector3(4.8, 1, 0), Vector3.BACK, Color(0.08, 0.65, 1), 0.8)
	burst._process(0.1)
	burst.set_process(false)
	await get_tree().create_timer(0.1).timeout
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	var capture := get_viewport().get_texture().get_image()
	var covered := camera.unproject_position(Vector3(0, 1, 0))
	var visible_beam := camera.unproject_position(Vector3(-2, 1, 0))
	var wall_color := capture.get_pixelv(Vector2i(covered))
	var beam_color := capture.get_pixelv(Vector2i(visible_beam))
	var passed := beam_color.b > wall_color.b + 0.15
	passed = capture.save_png("res://test_output/weapon_polish_occlusion.png") == OK and passed
	print("WEAPON_POLISH_OCCLUSION_PASS" if passed else "WEAPON_POLISH_OCCLUSION_FAIL")
	get_tree().quit(0 if passed else 1)
