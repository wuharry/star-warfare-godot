extends Node

func _ready() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	for _frame in range(8):
		await get_tree().process_frame

	world.hud.hit_marker.show_hit(10.0)
	world.hud.hit_marker.elapsed = WarfareHitMarker.HIT_DURATION * 0.22
	world.hud.hit_marker.queue_redraw()
	await get_tree().process_frame
	var hit_image := get_viewport().get_texture().get_image()
	var hit_error := hit_image.save_png("res://test_output/hit_marker_hit.png")

	world.hud.hit_marker.show_kill()
	world.hud.hit_marker.elapsed = WarfareHitMarker.KILL_DURATION * 0.22
	world.hud.hit_marker.queue_redraw()
	await get_tree().process_frame
	var kill_image := get_viewport().get_texture().get_image()
	var kill_error := kill_image.save_png("res://test_output/hit_marker_kill.png")

	world.hud.hit_marker.visible = false
	world.player.body_yaw = 0.0
	world.player.model.rotation.y = 0.0
	world.player.camera_yaw = PI
	world.player.camera_rig.rotation.y = PI
	await get_tree().process_frame
	var front_image := get_viewport().get_texture().get_image()
	var front_error := front_image.save_png("res://test_output/camera_front_orbit.png")

	world.player.set_physics_process(false)
	Input.action_press("fire")
	world.player._update_body_facing(1.0 / 60.0, Vector3.ZERO)
	world.player.shoot_pose_left = 0.2
	world.player._update_visual_animation(1.0 / 60.0, 0.0)
	world.player._update_combat_aim_pose(1.0 / 60.0)
	world.player.shot_fired.emit(world.player.current_weapon)
	await get_tree().process_frame
	var front_fire_image := get_viewport().get_texture().get_image()
	var front_fire_error := front_fire_image.save_png("res://test_output/camera_front_fire.png")
	Input.action_release("fire")

	world.completed = true
	world.free()
	AudioDirector.stop_all_sfx()
	if hit_error == OK and kill_error == OK and front_error == OK and front_fire_error == OK:
		print("HIT_MARKER_VISUAL_CAPTURE_PASS")
		get_tree().quit(0)
	else:
		push_error("Visual capture failed: %s / %s / %s / %s" % [error_string(hit_error), error_string(kill_error), error_string(front_error), error_string(front_fire_error)])
		get_tree().quit(1)
