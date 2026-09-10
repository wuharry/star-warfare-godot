extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ENEMY HITBOX / AUDIO TEST: " + message)

func _run() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	world.completed = true
	var player := world.player
	player.set_physics_process(false)

	for index in range(4):
		var kind: String = ["crawler", "spitter", "brute", "boss"][index]
		var enemy := world._spawn_enemy(kind, false)
		enemy.set_physics_process(false)
		enemy.spawn_left = 0.0
		enemy.model.position.y = 0.0
		# Reuse an isolated firing lane after freeing the previous specimen. Keeping
		# the lane fixed also makes the test independent of each level's arena bounds.
		enemy.global_position = Vector3(0.0, 0.05, -12.0)
		await get_tree().physics_frame
		_check(is_instance_valid(enemy.animated_hitbox) and not enemy.animated_hitbox.parts.is_empty(), "%s has no animated damage shapes" % kind)

		AudioDirector.stop_all_sfx()
		enemy.take_damage(4.0, enemy.global_position + Vector3.UP, player)
		_check_only_impact("enemy_hit_light.wav", kind + " player hit")
		AudioDirector.stop_all_sfx()
		enemy.take_damage(0.0, enemy.global_position, player)
		_check(not AudioDirector.is_playing("local_hit_confirm"), "zero damage played hit confirmation")
		enemy.max_health = 200.0
		enemy.health = 200.0
		enemy.take_damage(60.0, enemy.global_position + Vector3.UP, player)
		_check(not enemy.dead, "%s nonlethal damage killed the test enemy" % kind)
		_check_only_impact("enemy_hit_light.wav", kind + " nonlethal heavy damage")
		# Kill confirmation must replace the light sound even in the same frame.
		enemy.take_damage(enemy.health + 1.0, enemy.global_position + Vector3.UP, player)
		_check(enemy.dead, "%s lethal damage failed to kill" % kind)
		_check_only_impact("enemy_hit_heavy_or_lethal.wav", kind + " HUD kill")
		enemy.take_damage(10.0, enemy.global_position + Vector3.UP, player)
		_check_only_impact("enemy_hit_heavy_or_lethal.wav", kind + " already dead")
		AudioDirector.stop_all_sfx()
		enemy.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame

	for path in [
		"res://assets/audio/non_original/enemy_hit_light.wav",
		"res://assets/audio/non_original/enemy_hit_heavy_or_lethal.wav",
		"res://assets/audio/non_original/weapon_reload_magazine_eject.wav",
		"res://assets/audio/non_original/weapon_reload_magazine_insert.wav",
	]:
		_check(ResourceLoader.exists(path), "combat audio is missing: " + path)

	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.1).timeout
	if failures.is_empty():
		print("ENEMY_HITBOX_AUDIO_TEST_PASS enemies=4 animated_shapes=true local_hit_light=true hud_kill_heavy=true no_duplicate_audio=true reload_assets=true")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _check_only_impact(expected_file: String, context: String) -> void:
	# Check the full audio mix, including accidental 3D copies and old UI cues.
	var playing_count := 0
	for audio in AudioDirector.get_children():
		if (audio is AudioStreamPlayer or audio is AudioStreamPlayer3D) and audio.playing and audio.stream != null:
			playing_count += 1
			_check(audio is AudioStreamPlayer, "%s confirmation must be non-positional" % context)
			_check(audio.stream.resource_path.ends_with(expected_file), "%s played unexpected audio: %s" % [context, audio.stream.resource_path])
	_check(playing_count == 1, "%s should play exactly one impact, got %d" % [context, playing_count])
