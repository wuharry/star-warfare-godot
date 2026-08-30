extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("AIM/PLATFORM TEST: " + message)

func _run() -> void:
	var original_touch_setting := bool(GameState.settings.show_touch_controls)
	GameState.settings.show_touch_controls = true
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	GameState.selected_level = 1

	var packed := load("res://scenes/game.tscn") as PackedScene
	_check(packed != null, "game scene could not be loaded")
	if packed == null:
		get_tree().quit(1)
		return
	var world := packed.instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	_check(world.hud.touch_root == null, "desktop created mobile touch controls")
	_check(world.player.camera_rig.position.is_equal_approx(Vector3(0.6, 1.683712, 0.0)), "camera pivot is not at the recovered right-shoulder position")
	_check(is_equal_approx(world.player.camera_distance, 2.2), "normal camera distance is not the recovered 2.2")
	_check(is_equal_approx(world.player.camera.fov, 60.0), "normal camera FOV is not 60 degrees")
	_check(is_zero_approx(world.player.camera.position.x) and is_zero_approx(world.player.camera.position.y), "camera has an extra lateral offset in addition to the shoulder pivot")
	var viewport_center := world.get_viewport().get_visible_rect().get_center()
	var reticle_center := world.hud.crosshair.get_global_rect().get_center()
	_check(reticle_center.distance_to(viewport_center) < 1.0, "reticle is not centered on the camera ray (%s vs %s)" % [reticle_center, viewport_center])

	world.player.equip_weapon("gun00", false)
	await get_tree().process_frame
	var rifle_size := world.hud.crosshair.texture.get_size()
	world.player.equip_weapon("gun06", false)
	await get_tree().process_frame
	var shotgun_size := world.hud.crosshair.texture.get_size()
	_check(int(world.player.current_weapon.aim_id) == 2, "test shotgun did not load original AimID 2")
	_check(not rifle_size.is_equal_approx(shotgun_size), "weapon AimID did not change the original HUD reticle sprite")
	_check(world.hud.crosshair.modulate.is_equal_approx(Color(0.0, 1.0, 1.0, 0.8)), "reticle does not use the original cyan UIConstant.COLOR_AIM")

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	GameState.settings.show_touch_controls = original_touch_setting
	await get_tree().create_timer(0.2).timeout

	if failures.is_empty():
		print("AIM_PLATFORM_TEST_PASS shoulder=true reticles=true desktop_touch=false")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
