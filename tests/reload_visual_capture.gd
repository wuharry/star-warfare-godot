extends Node

const OUTPUT_DIR := "/tmp/star_warfare_reload_visuals"
const FR28A_OUTPUT_DIR := "res://test_output/fr28a"
const FR28A_CAPTURE_FPS := 30
const FR28A_STAGES := {
	"start": 0.0,
	"raise": 0.18,
	"extracted": 0.28,
	"handnew": 0.56,
	"beforeinsert": 0.70,
	"afterinsert": 0.76,
	"settle": 0.90,
	"end": 1.0,
}
const FR28A_VIEWS := {
	"front": Vector3(-2.0, 1.65, -2.0),
	"right_front": Vector3(2.0, 1.65, -2.0),
	"side": Vector3(-2.8, 1.65, 0.15),
	"rear": Vector3(-1.5, 1.75, 2.2),
}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--fr28a" in OS.get_cmdline_user_args():
		await _capture_fr28a()
		return
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

func _capture_fr28a() -> void:
	if not _make_fr28a_capture_dir(FR28A_OUTPUT_DIR):
		get_tree().quit(1)
		return
	var capture_sequence := "--sequence" in OS.get_cmdline_user_args()
	var capture_moving := "--moving" in OS.get_cmdline_user_args()
	if capture_sequence and not _make_fr28a_capture_dir(FR28A_OUTPUT_DIR + "/sequence"):
		get_tree().quit(1)
		return
	GameState.selected_weapon = "gun00"
	var stage := Node3D.new()
	add_child(stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.055, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.9
	environment_node.environment = environment
	stage.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -35.0, 0.0)
	light.light_energy = 1.5
	stage.add_child(light)
	var player := WarfarePlayer.new()
	stage.add_child(player)
	player.set_physics_process(false)
	player.visible = false
	var weapon := player.gun_mount.get_node("WeaponVisual").duplicate() as Node3D
	stage.add_child(weapon)
	weapon.transform = Transform3D.IDENTITY
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.9
	camera.position = Vector3(2.0, 0.18, -0.3)
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.08, -0.3), Vector3.UP)
	camera.current = true
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.5, 1.0, -0.5)
	fill.omni_range = 5.0
	fill.light_energy = 3.0
	stage.add_child(fill)
	var attachment := weapon.get_node("ReloadPartSocket/AttachedReloadPart") as Node3D
	var prefix := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	if capture_moving:
		prefix += "_moving"
	for state in ["assembled", "removed"]:
		attachment.visible = state == "assembled"
		var path := "%s/%s_%s.png" % [FR28A_OUTPUT_DIR, prefix, state]
		if not await _save_fr28a_capture(path):
			stage.free()
			AudioDirector.stop_all_sfx()
			get_tree().quit(1)
			return
	weapon.free()
	player.visible = true
	if capture_moving:
		# Both mixers must use manual time so rendering another camera cannot
		# advance the legs or replace the procedural pose between screenshots.
		player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_advance_fr28a_moving_animation(player, 0.1)
	else:
		# Freeze the imported idle at its starting pose on purpose: stationary
		# captures isolate reload motion from idle breathing or engine wall time.
		player._play_recovered_animation("idle_rifle", 0.0, true)
		player.recovered_animation_player.advance(0.0)
		player.recovered_animation_player.pause()
	# BoneAttachment3D needs the skeleton update and a frame to reach the
	# paused idle pose before _start_reload records the hands' starting points.
	player.recovered_skeleton.force_update_all_bone_transforms()
	await get_tree().process_frame
	camera.size = 2.0
	player._set_magazine_rounds(0)
	player._start_reload()
	if capture_moving:
		_advance_fr28a_moving_animation(player, 0.0)
		player._update_reload_pose()
	var duration := player.reload_total
	var samples: Array[Dictionary] = []
	for stage_name: String in FR28A_STAGES:
		samples.append({"time": duration * float(FR28A_STAGES[stage_name]), "stage": stage_name})
	for progress: float in [0.18, 0.56, 0.72, 0.76]:
		samples.append({"time": duration * progress, "legacy": roundi(progress * 100.0)})
	if capture_sequence:
		var frame_count := ceili(duration * FR28A_CAPTURE_FPS) + 1
		for frame_index: int in range(frame_count):
			samples.append({
				"time": minf(float(frame_index) / FR28A_CAPTURE_FPS, duration),
				"frame": frame_index,
			})
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	var elapsed := 0.0
	var manifest := {
		"weapon": "gun00", "prefix": prefix, "duration": duration,
		"fps": FR28A_CAPTURE_FPS, "viewport": [get_viewport().size.x, get_viewport().size.y],
		"renderer": RenderingServer.get_current_rendering_method(),
		"base_animation": "run_rifle legs + idle_rifle upper body (manual time)" if capture_moving else "idle_rifle paused at 0",
		"moving_in_place": capture_moving, "captures": [],
	}
	var capture_ok := true
	for sample: Dictionary in samples:
		var target_elapsed := float(sample.time)
		# Keep one continuous simulation for every camera and stage. The
		# previous frame's rotation is preserved so accumulated tilt is visible.
		# Own elapsed separately because finishing a reload resets reload_elapsed.
		while elapsed < target_elapsed - 0.000001:
			var delta := minf(1.0 / 60.0, target_elapsed - elapsed)
			player._update_reload(delta)
			player._update_body_facing(delta, Vector3.FORWARD if capture_moving else Vector3.ZERO)
			player._update_combat_aim_pose(delta)
			if capture_moving:
				_advance_fr28a_moving_animation(player, delta)
			player._update_reload_pose()
			elapsed += delta
		if target_elapsed == duration and player.reload_left > 0.0:
			# Consume a possible floating-point remainder so "end" really shows
			# the finished cycle, whose state deliberately resets to elapsed 0.
			player._update_reload(player.reload_left)
			player._update_body_facing(0.0, Vector3.FORWARD if capture_moving else Vector3.ZERO)
			player._update_combat_aim_pose(0.0)
			if capture_moving:
				_advance_fr28a_moving_animation(player, 0.0)
			player._update_reload_pose()
		if sample.has("legacy"):
			_set_fr28a_capture_view(camera, fill, "front", true)
			var path := "%s/%s_reload_%02d.png" % [FR28A_OUTPUT_DIR, prefix, sample.legacy]
			capture_ok = await _save_fr28a_capture(path)
		else:
			for view_name: String in FR28A_VIEWS:
				_set_fr28a_capture_view(camera, fill, view_name)
				var relative_path: String
				if sample.has("stage"):
					relative_path = "%s_%s_%s.png" % [prefix, view_name, sample.stage]
				else:
					relative_path = "sequence/%s_%s_%03d.png" % [prefix, view_name, sample.frame]
				capture_ok = await _save_fr28a_capture(FR28A_OUTPUT_DIR + "/" + relative_path)
				if not capture_ok:
					break
				var record := {"path": relative_path, "view": view_name,
					"time": target_elapsed, "progress": target_elapsed / duration}
				if sample.has("stage"):
					record["stage"] = sample.stage
				else:
					record["frame"] = sample.frame
				manifest.captures.append(record)
		if not capture_ok:
			break
	if capture_ok:
		var manifest_path := "%s/%s_frames.json" % [FR28A_OUTPUT_DIR, prefix]
		var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
		if manifest_file == null:
			push_error("FR28A manifest failed: %s" % error_string(FileAccess.get_open_error()))
			capture_ok = false
		else:
			manifest_file.store_string(JSON.stringify(manifest, "\t"))
			manifest_file.flush()
			if manifest_file.get_error() != OK:
				push_error("FR28A manifest write failed: %s" % error_string(manifest_file.get_error()))
				capture_ok = false
			manifest_file.close()
			if capture_ok:
				print("FR28A_RELOAD_MANIFEST %s" % manifest_path)
	player._cancel_reload()
	stage.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	get_tree().quit(0 if capture_ok else 1)

func _advance_fr28a_moving_animation(player: WarfarePlayer, delta: float) -> void:
	# Exercise the runtime selector, including entering the reload layer and
	# returning to full-body running at completion. Translation stays at zero
	# to keep the four camera compositions comparable throughout the cycle.
	player._update_recovered_animation(1.0, Vector2(0.0, -1.0))
	if player.recovered_animation_tree.active:
		player.recovered_animation_tree.advance(delta)
	else:
		player.recovered_animation_player.advance(delta)
	player.recovered_skeleton.force_update_all_bone_transforms()

func _make_fr28a_capture_dir(path: String) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error != OK:
		push_error("FR28A directory failed for %s: %s" % [path, error_string(error)])
		return false
	return true

func _set_fr28a_capture_view(camera: Camera3D, fill: OmniLight3D, view_name: String, legacy := false) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if legacy else Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 42.0
	camera.position = Vector3(FR28A_VIEWS[view_name])
	camera.look_at(Vector3(0.0, 1.15, -0.1), Vector3.UP)
	fill.position = camera.position

func _save_fr28a_capture(path: String) -> bool:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("FR28A capture produced no image: %s" % path)
		return false
	var error := image.save_png(path)
	if error != OK:
		push_error("FR28A capture failed for %s: %s" % [path, error_string(error)])
		return false
	print("FR28A_RELOAD_CAPTURE %s" % path)
	return true
