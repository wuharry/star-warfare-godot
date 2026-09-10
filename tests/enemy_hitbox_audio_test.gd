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
		var heard_flesh := false
		var heard_confirm := false
		for audio in AudioDirector.get_children():
			if audio is AudioStreamPlayer3D and audio.stream != null:
				heard_flesh = heard_flesh or audio.stream.resource_path.ends_with("enemy_hit_light.wav")
			elif audio is AudioStreamPlayer and audio.stream != null:
				heard_confirm = heard_confirm or audio.stream.resource_path.ends_with("enemies_smash2.wav")
		_check(heard_flesh, "%s damage did not play a positional flesh impact" % kind)
		_check(heard_confirm, "%s damage did not play local hit confirmation" % kind)
		AudioDirector.stop_all_sfx()
		enemy.flesh_hit_cooldown = 0.0
		enemy._play_flesh_impact(maxf(40.0, enemy.max_health * 0.20), enemy.global_position + Vector3.UP)
		var heard_heavy := false
		for audio in AudioDirector.get_children():
			if audio is AudioStreamPlayer3D and audio.stream != null:
				heard_heavy = heard_heavy or audio.stream.resource_path.ends_with("enemy_hit_heavy_or_lethal.wav")
		_check(heard_heavy, "%s heavy hit did not play the thick flesh impact" % kind)
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
		print("ENEMY_HITBOX_AUDIO_TEST_PASS enemies=4 animated_shapes=true light_heavy_flesh=true reload_assets=true")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
