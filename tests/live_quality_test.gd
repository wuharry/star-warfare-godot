extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("LIVE QUALITY: " + message)

func _run() -> void:
	var original_save := GameState.save_path
	var original_settings := GameState.settings.duplicate(true)
	var original_level := GameState.selected_level
	var original_mode := GameState.selected_game_mode
	var original_paused := get_tree().paused
	var isolated_save := "user://live_quality_%d.json" % Time.get_ticks_usec()
	GameState.save_path = isolated_save
	GameState.selected_game_mode = "singleplayer"
	for level_number in [13, 3]:
		GameState.selected_level = level_number
		GameState.set_setting("quality", "high")
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		add_child(world)
		await get_tree().process_frame
		get_tree().paused = true
		var world_id := world.get_instance_id()
		var player_id := world.player.get_instance_id()
		var hud_id := world.hud.get_instance_id()
		var player_transform := world.player.global_transform
		var elapsed := world.elapsed_time
		var score := world.score
		var current_wave := world.current_wave
		var environment: Environment
		for child in world.get_children():
			if child is WorldEnvironment:
				environment = child.environment
		var key_light := world.get_node("KeyLight") as DirectionalLight3D
		var stage := world.get_node("OriginalUnityLevel%02d" % level_number) as MeshInstance3D
		var stage_id := stage.get_instance_id()
		var environment_id := environment.get_instance_id()
		var effect_root := world.get_node("OriginalUnitySceneEffects") as Node3D
		var effect_id := effect_root.get_instance_id()
		var particle_ids: Array[int] = []
		var particle_transforms: Array[Transform3D] = []
		for particles: CPUParticles3D in effect_root.get_children():
			particle_ids.append(particles.get_instance_id())
			particle_transforms.append(particles.transform)
		var lightmaps: Array[ShaderMaterial] = []
		for surface_index in stage.mesh.get_surface_count():
			var material := stage.get_active_material(surface_index) as ShaderMaterial
			if material != null and material.get_shader_parameter("dynamic_light_strength") != null:
				lightmaps.append(material)
		_check(not lightmaps.is_empty(), "level %d fixture lacks restored lightmap uniforms" % level_number)
		_check(effect_root.get_child_count() == (1 if level_number == 13 else 5), "source emitter count changed")
		var source_fog: bool = bool(world.stage_metadata.render_settings.get("fog_enabled", true))
		for quality: String in ["low", "medium", "high", "low", "high"]:
			GameState.set_setting("quality", quality)
			var low := quality == "low"
			var expected_scale := 0.7 if low else (0.85 if quality == "medium" else 1.0)
			var expected_msaa := Viewport.MSAA_DISABLED if low else (Viewport.MSAA_2X if quality == "medium" else Viewport.MSAA_4X)
			_check(is_equal_approx(get_viewport().scaling_3d_scale, expected_scale) and get_viewport().msaa_3d == expected_msaa, "root viewport did not update: " + quality)
			_check(environment.glow_enabled == not low and environment.fog_enabled == (not low and source_fog), "environment did not honor current quality/source fog: " + quality)
			_check(key_light.shadow_enabled == not low, "shadows did not update: " + quality)
			var strength := 0.0 if low else (0.06 if quality == "medium" else 0.14)
			for material: ShaderMaterial in lightmaps:
				_check(is_equal_approx(float(material.get_shader_parameter("dynamic_light_strength")), strength), "lightmap response did not update: " + quality)
			var expected_amount := (38 if low else 75) if level_number == 13 else (3 if low else 6)
			for index in effect_root.get_child_count():
				var particles := effect_root.get_child(index) as CPUParticles3D
				_check(particles.amount == expected_amount, "particles did not recover their source capacity: " + quality)
				_check(particles.get_instance_id() == particle_ids[index] and particles.transform.is_equal_approx(particle_transforms[index]), "quality rebuilt/moved a source emitter")
			_check(world.get_instance_id() == world_id and world.player.get_instance_id() == player_id and world.hud.get_instance_id() == hud_id, "quality reentered the room")
			_check(stage.get_instance_id() == stage_id and environment.get_instance_id() == environment_id and effect_root.get_instance_id() == effect_id, "quality rebuilt the level/environment")
			_check(world.elapsed_time == elapsed and world.score == score and world.current_wave == current_wave and world.player.global_transform.is_equal_approx(player_transform), "quality changed paused gameplay state")
		# A disabled source fog remains disabled; a fog-enabled source can toggle live.
		world.stage_metadata.render_settings.fog_enabled = true
		GameState.set_setting("quality", "low")
		_check(not environment.fog_enabled, "low quality enabled source fog")
		GameState.set_setting("quality", "high")
		_check(environment.fog_enabled, "high quality did not restore enabled source fog")
		# Unrelated settings must not reapply a cached quality profile.
		var first_particles := effect_root.get_child(0) as CPUParticles3D
		first_particles.amount = 2
		GameState.set_setting("sfx", 0.4)
		_check(first_particles.amount == 2, "audio settings reapplied particle quality")
		GameState.set_setting("quality", "low")
		GameState.set_setting("quality", "high")
		_check(first_particles.amount == (75 if level_number == 13 else 6), "quality did not recover after unrelated settings")
		get_tree().paused = false
		world.completed = true
		for audio in world.find_children("*", "AudioStreamPlayer", true, false):
			audio.stop()
		for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
		world.free()
		AudioDirector.stop_all_sfx()
		await get_tree().process_frame
	GameState.settings = original_settings
	GameState._apply_audio_settings()
	GameState.apply_viewport_quality()
	GameState.selected_level = original_level
	GameState.selected_game_mode = original_mode
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(isolated_save + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameState.save_path = original_save
	get_tree().paused = original_paused
	await get_tree().create_timer(0.2).timeout
	print("LIVE_QUALITY_TEST_PASS checks=%d levels=13,3" % checks if failures.is_empty() else "LIVE_QUALITY_TEST_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)
