extends Node

const OUTPUT_DIR := "/tmp/star_warfare_reload_visuals"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	var player := world.player
	player.set_physics_process(false)
	player.max_health = 999999.0
	player.health = player.max_health

	var capture_camera := Camera3D.new()
	capture_camera.name = "ReloadCaptureCamera"
	capture_camera.fov = 42.0
	world.add_child(capture_camera)
	capture_camera.current = true
	var capture_light := OmniLight3D.new()
	capture_light.omni_range = 9.0
	capture_light.light_energy = 4.0
	capture_light.light_color = Color(0.72, 0.88, 1.0)
	world.add_child(capture_light)

	for weapon_id in ["gun00", "gun35", "gun06", "gun11", "gun14"]:
		player.equip_weapon(weapon_id, false)
		player._set_magazine_rounds(0)
		player._start_reload()
		player._update_reload(player.reload_total * 0.56)
		player._update_recovered_animation(0.0)
		player._update_reload_pose()
		capture_camera.global_position = player.global_position + Vector3(-3.0, 1.55, -3.3)
		capture_camera.look_at(player.global_position + Vector3(0.0, 1.25, 0.0), Vector3.UP)
		capture_light.global_position = player.global_position + Vector3(-1.3, 2.8, -1.8)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var output_path := "%s/%s_reload.png" % [OUTPUT_DIR, weapon_id]
		image.save_png(output_path)
		print("RELOAD_VISUAL_CAPTURE %s" % output_path)
		player._cancel_reload()

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)
