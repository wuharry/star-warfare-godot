extends Node

const OUT := "res://test_output/armor_concept_runtime/"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var real_save := GameState.save_path
	var before := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "missing"
	GameState.save_path = "user://cygni_game_capture_profile.json"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	GameState.equipped_armor = {"head":"armor_head_11", "body":"armor_body_11", "arms":"armor_arms_11", "legs":"armor_legs_11", "bag":"armor_bag_00"}
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	var files: Array[String] = []
	for level: int in [1, 8]:
		seed(1633)
		GameState.selected_level = level
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		add_child(world)
		world.completed = true
		world.player.set_physics_process(false)
		for frame: int in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := OUT + "cygni_level_%02d_gameplay.png" % level
		if get_viewport().get_texture().get_image().save_png(path) != OK:
			push_error("Cannot save Cygni game capture")
			get_tree().quit(1)
			return
		files.append(path)
		world.hud.hide()
		# The player camera lives under SpringArm3D, which repositions its child
		# even with the player's physics callback disabled. Use a separate review
		# camera to retain the intended frontal composition in the actual map.
		var front := Camera3D.new()
		world.add_child(front)
		front.fov = 40.0
		front.global_position = world.player.global_position + Vector3(3.1, 1.8, -3.4)
		front.look_at(world.player.global_position + Vector3(0, 1.05, 0))
		front.make_current()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		path = OUT + "cygni_level_%02d_front.png" % level
		if get_viewport().get_texture().get_image().save_png(path) != OK:
			push_error("Cannot save Cygni frontal game capture")
			get_tree().quit(1)
			return
		files.append(path)
		world.free()
		AudioDirector.stop_all_sfx()
		await get_tree().process_frame
	var after := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "missing"
	GameState.save_path = real_save
	var report := FileAccess.open(OUT + "painted_game_capture.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"viewport": get_viewport().size, "renderer": RenderingServer.get_current_rendering_method(), "files": files, "real_save_unchanged": before == after, "status": "captured_requires_visual_review"}, "\t"))
	print("CYGNI_GAME_CAPTURE_%s real_save_unchanged=%s" % ["PASS" if before == after else "FAIL", str(before == after)])
	get_tree().quit(0 if before == after else 1)
