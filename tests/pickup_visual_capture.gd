extends Node3D

func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 4, 12)
	add_child(camera)
	camera.look_at(Vector3(0, 2, 0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.045, 0.065)
	add_child(environment)
	for index in 2:
		var drop := WarfarePickup.new()
		drop.configure("credits" if index == 0 else "energy", 1.0)
		drop.position = Vector3(-3.5 + index * 7, 3.5, 0)
		add_child(drop)
		drop._process(0.5)
		drop.set_process(false)
		_label("MONEY + WHITE HALO" if index == 0 else "ENERGY + WHITE HALO", drop.position + Vector3.UP)
		var effect := OriginalPickupVisual.create("effect_pick_gold_001" if index == 0 else "effect_pick_energy_001", true)
		effect.position = Vector3(-3.5 + index * 7, 0.5, 0)
		add_child(effect)
		effect.set_process(false)
		effect.advance(0.25)
		_label("GOLD PICKUP" if index == 0 else "BLUE PICKUP", effect.position + Vector3.UP * 1.5)
		# Warm up the actual particle renderer while holding the original ring pose.
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("PICKUP_VISUAL_CAPTURE requires the real GL Compatibility renderer")
		get_tree().quit(1)
		return
	var result := get_viewport().get_texture().get_image().save_png("res://test_output/pickup_preview.png")
	print("PICKUP_VISUAL_CAPTURE_PASS" if result == OK else "PICKUP_VISUAL_CAPTURE_FAIL")
	get_tree().quit(0 if result == OK else 1)

func _label(text_value: String, position_value: Vector3) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = 48
	label.position = position_value
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
