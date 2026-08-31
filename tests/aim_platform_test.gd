extends Node

const POSITION_TOLERANCE := 2.0

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("AIM/PLATFORM TEST: " + message)

func _named_control(root: Node, control_name: String) -> Control:
	return root.find_child(control_name, true, false) as Control

func _check_center(control: Control, expected: Vector2, label: String) -> void:
	if not is_instance_valid(control):
		_check(false, "%s is missing on desktop" % label)
		return
	var actual := control.get_global_rect().get_center()
	_check(
		actual.distance_to(expected) <= POSITION_TOLERANCE,
		"desktop %s center does not match the shared recovered layout (%s vs %s)" % [label, actual, expected]
	)

func _run() -> void:
	var original_touch_setting := bool(GameState.settings.show_touch_controls)
	GameState.settings.show_touch_controls = true
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"

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
	_check(world.hud.find_children("*", "WarfareVirtualJoystick", true, false).is_empty(), "desktop HUD contains one of the mobile joysticks")
	var pause_button := _named_control(world.hud, "PauseButton")
	var weapon_selector := _named_control(world.hud, "WeaponSelector")
	var skill_button := _named_control(world.hud, "SkillButton")
	var player_hp := _named_control(world.hud, "PlayerHP")
	var ammo_bar := _named_control(world.hud, "AmmoBar")
	var boss_state := _named_control(world.hud, "BossState")
	_check(is_instance_valid(skill_button), "desktop removed the shared SkillButton together with the mobile joysticks")
	_check(is_instance_valid(boss_state), "desktop is missing the shared centered boss bar")
	_check(_named_control(world.hud, "EnemyProgress") == null, "the removed top-center level progress bar is back")
	_check_center(pause_button, Vector2(56.25, 45.0), "PauseButton")
	_check_center(player_hp, Vector2(230.625, 61.875), "PlayerHP")
	_check_center(ammo_bar, Vector2(1055.0, 61.875), "AmmoBar")
	_check_center(weapon_selector, Vector2(1201.25, 180.0), "WeaponSelector")
	if is_instance_valid(boss_state):
		_check(absf(boss_state.get_global_rect().get_center().x - 640.0) <= POSITION_TOLERANCE, "desktop boss bar is not centered")
	_check(world.player.camera_rig.position.is_equal_approx(Vector3(0.0, 1.683712, 0.0)), "camera yaw pivot is not on the player's recovered centerline")
	_check(world.player.pitch_node.position.is_equal_approx(Vector3(0.6, 0.0, 0.0)), "recovered right-shoulder offset is not below the yaw pivot")
	_check(is_zero_approx(world.player.camera_pitch), "camera does not start at the original horizontal pitch")
	_check(is_equal_approx(world.player.camera_distance, 2.2), "normal camera distance is not the recovered 2.2")
	_check(is_equal_approx(world.player.camera.fov, 60.0), "normal camera FOV is not 60 degrees")
	_check(is_zero_approx(world.player.camera.position.x) and is_zero_approx(world.player.camera.position.y), "camera has an extra lateral offset in addition to the shoulder pivot")
	var viewport_center := world.get_viewport().get_visible_rect().get_center()
	var reticle_center := world.hud.crosshair.get_global_rect().get_center()
	_check(reticle_center.distance_to(viewport_center) < 1.0, "reticle is not centered on the camera ray (%s vs %s)" % [reticle_center, viewport_center])
	var aim_solution := world.player.get_aim_solution(40.0)
	var point_on_aim_ray: Vector3 = aim_solution.origin + aim_solution.direction * 20.0
	var projected_aim := world.player.camera.unproject_position(point_on_aim_ray)
	_check(projected_aim.distance_to(reticle_center) < 1.0, "camera aim ray does not pass through the visible reticle (%s vs %s)" % [projected_aim, reticle_center])

	# The recovered +0.6 offset was authored in player-local space. At a
	# quarter turn it must rotate onto the camera's right axis instead of
	# remaining fixed on world X and sliding the character under the reticle.
	world.player.camera_yaw = PI * 0.5
	world.player.camera_rig.rotation.y = world.player.camera_yaw
	await get_tree().physics_frame
	var pivot_center := world.player.global_position + Vector3.UP * 1.683712
	var shoulder_offset := world.player.pitch_node.global_position - pivot_center
	var expected_offset := world.player.camera.global_transform.basis.x.normalized() * 0.6
	_check(shoulder_offset.distance_to(expected_offset) < 0.001, "right-shoulder offset did not rotate with 90-degree yaw (%s vs %s)" % [shoulder_offset, expected_offset])
	var player_center_on_screen := world.player.camera.unproject_position(pivot_center)
	_check(player_center_on_screen.x < reticle_center.x - 1.0, "90-degree yaw no longer keeps the player to the left of the reticle (%s vs %s)" % [player_center_on_screen, reticle_center])

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
		print("AIM_PLATFORM_TEST_PASS shoulder=true reticles=true shared_hud=true desktop_touch=false")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
