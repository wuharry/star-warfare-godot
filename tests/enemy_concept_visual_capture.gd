extends Node3D

const OUTPUT_DIR := "res://test_output/enemy_concept_runtime"
const VIEWPORT_SIZE := Vector2i(1280, 720)
const CLIP_FRACTIONS := {"idle": 0.0, "run": 0.4, "attack": 0.4, "dead": 0.78}

var stage: Node3D
var specimens: Array[WarfareEnemy] = []
var camera: Camera3D
var caption: Label
var captures: Array[Dictionary] = []
var keep_open := false
var framing_size := 4.2
var focus := Vector3(0.0, 1.0, 0.0)
var failed := false
var interactive_ready := false
var interactive_clip := "idle"
var interactive_paused := false


func _ready() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	GameState.apply_viewport_quality()
	keep_open = "--keep-open" in OS.get_cmdline_user_args()
	get_window().size = VIEWPORT_SIZE
	get_window().content_scale_size = VIEWPORT_SIZE
	call_deferred("_run")


func _pose(enemy: WarfareEnemy, clip: String, fraction: float) -> void:
	var animator := enemy.recovered_animation_player
	if animator == null or not animator.has_animation(clip):
		push_error("Comparison specimen is missing animation: " + clip)
		failed = true
		return
	animator.play(clip, 0.0)
	animator.advance(0.0)
	animator.seek(animator.get_animation(clip).length * fraction, true)
	animator.pause()
	for node in enemy.model.find_children("*", "Skeleton3D", true, false):
		(node as Skeleton3D).force_update_all_bone_transforms()
	if enemy.animated_hitbox:
		enemy.animated_hitbox.sync_pose()


func _make_specimen(concept: bool) -> WarfareEnemy:
	var enemy := WarfareEnemy.new()
	enemy.use_concept_visuals = concept
	enemy.configure_recovered(null, "crawler")
	stage.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.spawn_left = 0.0
	enemy.model.position = Vector3.ZERO
	_hide_spawn_effect(enemy)
	_pose(enemy, "idle", 0.0)
	return enemy


func _hide_spawn_effect(enemy: WarfareEnemy) -> void:
	var dust := enemy.get_node_or_null("RecoveredGraveSmoke") as GPUParticles3D
	if dust:
		dust.emitting = false
		dust.visible = false
	if enemy.voice:
		enemy.voice.stop()
		enemy.voice.stream = null


func _release_scene(node: Node) -> void:
	for audio in node.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	for audio in node.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
		audio.stream = null
	node.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "NeutralComparisonStage"
	add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.085, 0.105, 0.13)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.75, 0.8, 0.88)
	settings.ambient_light_energy = 0.8
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -30, 0)
	key.light_energy = 1.8
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 145, 0)
	fill.light_energy = 0.6
	stage.add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(35, 35)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.2, 0.23)
	material.roughness = 0.95
	plane.material = material
	floor.mesh = plane
	stage.add_child(floor)
	specimens = [_make_specimen(false), _make_specimen(true)]
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = framing_size
	stage.add_child(camera)
	camera.current = true
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(24, 18)
	caption.add_theme_font_size_override("font_size", 21)
	caption.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	caption.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(caption)


func _save(filename: String, details: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	if shot.get_size() != VIEWPORT_SIZE:
		push_error("Expected 1280x720 capture; got %s" % shot.get_size())
		failed = true
		return
	var error := shot.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		push_error("Could not save %s: %s" % [filename, error_string(error)])
		failed = true
		return
	details["file"] = filename
	captures.append(details)


func _run() -> void:
	var concept_path := "res://assets/models/enemies/concept/warrior/warrior.gltf"
	if not ResourceLoader.exists(concept_path):
		push_error("Import warrior.gltf before capture; cannot capture fallback as new art")
		get_tree().quit(1)
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Use --rendering-method gl_compatibility for this capture")
		get_tree().quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if directory_error != OK:
		push_error("Cannot create capture directory")
		get_tree().quit(1)
		return
	_build_stage()
	if failed or specimens[1].recovered_enemy == null or specimens[1].recovered_enemy.scene_file_path != concept_path:
		push_error("Concept comparison specimen was not instantiated correctly")
		get_tree().quit(1)
		return
	# One framing envelope for both assets and all sampled poses makes the
	# before/after scale comparison meaningful instead of auto-zooming each bug.
	var envelope := AABB()
	var first := true
	for enemy in specimens:
		if enemy.recovered_animation_player == null:
			push_error("Missing AnimationPlayer on comparison specimen")
			get_tree().quit(1)
			return
		for clip: String in CLIP_FRACTIONS:
			if not enemy.recovered_animation_player.has_animation(clip):
				push_error("Cannot capture missing clip: " + clip)
				get_tree().quit(1)
				return
		for clip: String in CLIP_FRACTIONS:
			_pose(enemy, clip, float(CLIP_FRACTIONS[clip]))
			var bounds := EnemyHitGeometry.posed_bounds(enemy.model)
			envelope = bounds if first else envelope.merge(bounds)
			first = false
	framing_size = maxf(envelope.size.y, maxf(envelope.size.x, envelope.size.z) / (1280.0 / 720.0)) * 1.24
	framing_size = maxf(framing_size, 3.1)
	focus = envelope.get_center()
	camera.size = framing_size
	for index in range(specimens.size()):
		var enemy := specimens[index]
		var variant := "before" if index == 0 else "after"
		for other in specimens:
			other.visible = other == enemy
		for clip: String in CLIP_FRACTIONS:
			var fraction := float(CLIP_FRACTIONS[clip])
			_pose(enemy, clip, fraction)
			for view: String in ["front", "side"]:
				camera.position = focus + (Vector3(0, 0.9, -12) if view == "front" else Vector3(12, 0.9, 0))
				camera.look_at(focus, Vector3.UP)
				caption.text = "%s  |  crawler / warrior  |  %s %.0f%%  |  %s" % ["ORIGINAL BASELINE" if index == 0 else "CONCEPT PROTOTYPE", clip, fraction * 100.0, view.to_upper()]
				await _save("%s_%s_%s.png" % [variant, clip, view], {"variant": variant, "clip": clip, "fraction": fraction, "view": view, "scene": enemy.recovered_enemy.scene_file_path, "orthographic_size": framing_size})
	specimens.clear()
	await _release_scene(stage)
	await _capture_gameplay()
	await get_tree().process_frame
	_build_stage()
	for index in range(specimens.size()):
		var enemy := specimens[index]
		# Looking from -Z toward +Z puts world +X on screen-left.
		enemy.position.x = 2.4 if index == 0 else -2.4
		_pose(enemy, "idle", 0.0)
	camera.size = maxf(framing_size, (envelope.size.x + 4.8) / (1280.0 / 720.0) * 1.16)
	camera.position = Vector3(0, 2.05, -12)
	camera.look_at(Vector3(0, 1.15, 0), Vector3.UP)
	caption.text = "ORIGINAL (left)  /  CONCEPT PROTOTYPE (right)\nSame 2 m posed height; new texture, body silhouette and articulated scythes."
	await _save("comparison_front.png", {"view": "comparison_front", "left": "original", "right": "concept", "orthographic_size": camera.size})
	var file := FileAccess.open(OUTPUT_DIR.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write capture manifest")
		failed = true
	else:
		file.store_string(JSON.stringify({"viewport": [1280, 720], "renderer": RenderingServer.get_current_rendering_method(), "quality": "high", "captures": captures, "visual_review": "pending human image inspection", "postprocessing": "none; direct Godot viewport PNGs"}, "\t"))
	AudioDirector.stop_all_sfx()
	if not failed:
		print("ENEMY_CONCEPT_VISUAL_CAPTURE_PASS frames=%d directory=%s" % [captures.size(), OUTPUT_DIR])
	if not keep_open or failed:
		specimens.clear()
		await _release_scene(stage)
		await get_tree().create_timer(0.15).timeout
		get_tree().quit(1 if failed else 0)
	else:
		interactive_ready = true
		_start_interactive_clip("idle")


func _start_interactive_clip(clip: String) -> void:
	interactive_clip = clip
	interactive_paused = false
	for enemy in specimens:
		var animator := enemy.recovered_animation_player
		animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in ["idle", "run"] else Animation.LOOP_NONE
		animator.play(clip, 0.0)
		animator.seek(0.0, true)
	_update_interactive_caption()


func _update_interactive_caption() -> void:
	caption.text = "ORIGINAL (left) / CONCEPT (right)  |  %s  |  %s\n1 Idle  2 Run  3 Attack  4 Death (replay)  |  Space Pause / Resume" % [interactive_clip.to_upper(), "PAUSED" if interactive_paused else "PLAYING"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not interactive_ready or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			_start_interactive_clip("idle")
		KEY_2:
			_start_interactive_clip("run")
		KEY_3:
			_start_interactive_clip("attack")
		KEY_4:
			_start_interactive_clip("dead")
		KEY_SPACE:
			interactive_paused = not interactive_paused
			for enemy in specimens:
				if interactive_paused:
					enemy.recovered_animation_player.pause()
				else:
					enemy.recovered_animation_player.play()
			_update_interactive_caption()
		_:
			return
	get_viewport().set_input_as_handled()


func _capture_gameplay() -> void:
	seed(1633)
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	world.completed = true
	world.elapsed_time = 0.0
	world.rng.seed = 1633
	world.player.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# Level 1 has fixed baked lighting, not a day/night clock. Start at its
	# authored Respawn[0], then try only the first two enemy markers if needed.
	var anchors: Array[Vector3] = [world.player.global_position]
	for index in range(mini(2, world.enemy_spawn_points.size())):
		anchors.append(world.enemy_spawn_points[index])
	var fixed_spawn := Vector3.INF
	var fixed_camera := Vector3.INF
	var space := world.get_world_3d().direct_space_state
	for anchor in anchors:
		var grounded := world._snap_enemy_spawn_to_ground(anchor)
		if grounded == Vector3.INF:
			continue
		for offset in [Vector3(3.4, 2.3, -6.0), Vector3(-3.4, 2.3, -6.0), Vector3(0.0, 2.4, -7.0)]:
			var origin: Vector3 = grounded + offset
			var clear := true
			for target_offset in [Vector3(0, 0.35, 0), Vector3(0, 1.1, 0), Vector3(0, 1.9, 0), Vector3(1.2, 1.1, 0), Vector3(-1.2, 1.1, 0)]:
				var query := PhysicsRayQueryParameters3D.create(origin, grounded + target_offset, 1)
				query.collide_with_areas = false
				query.exclude = [world.player.get_rid()]
				if not space.intersect_ray(query).is_empty():
					clear = false
					break
			if clear:
				fixed_spawn = grounded
				fixed_camera = origin
				break
		if fixed_spawn != Vector3.INF:
			break
	if fixed_spawn == Vector3.INF:
		push_error("Level 1 capture has no unobstructed fixed-marker angle; adjust this scene's camera offsets")
		failed = true
		world.free()
		AudioDirector.stop_all_sfx()
		return
	var enemy := world._spawn_enemy("crawler", false, fixed_spawn)
	if enemy == null:
		push_error("Level 1 crawler spawn failed")
		failed = true
		world.free()
		return
	enemy.set_physics_process(false)
	enemy.spawn_left = 0.0
	enemy.model.position = Vector3.ZERO
	_hide_spawn_effect(enemy)
	enemy.rotation = Vector3.ZERO
	_pose(enemy, "idle", 0.0)
	world.hud.visible = false
	world.player.visible = false
	var game_camera := Camera3D.new()
	game_camera.fov = 48.0
	world.add_child(game_camera)
	game_camera.global_position = fixed_camera
	game_camera.look_at(enemy.global_position + Vector3.UP * 1.0, Vector3.UP)
	game_camera.current = true
	await _save("after_level01_gameplay.png", {"variant": "after", "view": "live_game_world_closeup", "level": 1, "spawn_api": "WarfareGameWorld._spawn_enemy", "scene": enemy.recovered_enemy.scene_file_path, "seed": 1633, "scene_time_seconds": 0.0, "lighting": "level01_fixed_baked_lighting", "spawn_position": [enemy.global_position.x, enemy.global_position.y, enemy.global_position.z], "camera_position": [fixed_camera.x, fixed_camera.y, fixed_camera.z]})
	await _release_scene(world)
