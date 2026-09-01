extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ENEMY ANIMATION TEST: " + message)

func _run() -> void:
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	for kind in ["crawler", "spitter", "brute", "boss"]:
		world._spawn_enemy(kind, false)
		await get_tree().process_frame
		var candidates := get_tree().get_nodes_in_group("enemies")
		var enemy: WarfareEnemy
		for candidate in candidates:
			if candidate is WarfareEnemy and (candidate as WarfareEnemy).enemy_kind == kind:
				enemy = candidate
				break
		_check(is_instance_valid(enemy), "%s was not spawned" % kind)
		if is_instance_valid(enemy):
			_check(is_instance_valid(enemy.recovered_animation_player), "%s has no recovered AnimationPlayer" % kind)
			if is_instance_valid(enemy.recovered_animation_player):
				var animations := enemy.recovered_animation_player.get_animation_list()
				_check(animations.has("idle") or animations.has("fly_idle"), "%s has no idle animation" % kind)
				_check(animations.has("run") or animations.has("fly_walk"), "%s has no run animation" % kind)
				_check(animations.has("attack") or animations.has("fly_attack"), "%s has no attack animation" % kind)
				_check(animations.has("dead"), "%s has no death animation" % kind)
			_check(enemy.spawn_left > 0.0 and enemy.model.position.y < 0.0, "%s has no grave-spawn rise" % kind)
			enemy._face_planar_direction(Vector3(0.7, 0.0, -0.7))
			var expected_forward := Vector3(0.7, 0.0, -0.7).normalized()
			var actual_forward := -enemy.global_transform.basis.z.normalized()
			_check(actual_forward.dot(expected_forward) > 0.999, "%s faces opposite its movement direction" % kind)
			if is_instance_valid(enemy.recovered_animation_player):
				enemy.spawn_left = 0.0
				enemy.attack_cooldown = enemy.attack_interval
				enemy.take_damage(1.0)
				var attacked_name := "fly_attacked" if kind == "boss" else "attacked"
				_check(enemy.recovered_animation_name == attacked_name, "%s did not enter its hit reaction" % kind)
				enemy.recovered_animation_player.stop()
				enemy._update_animation(0.016, 1.0)
				_check(enemy.recovered_animation_name == attacked_name, "%s attack cooldown overwrote its hit reaction" % kind)
				_check(not enemy.recovered_animation_player.is_playing(), "%s restarted a finished hit clip every frame" % kind)
				enemy.hit_reaction_left = 0.0
				enemy._update_animation(0.016, 1.0)
				_check(enemy.recovered_animation_name == ("fly_attack" if kind == "boss" else "attack"), "%s did not leave its hit reaction" % kind)
	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.15).timeout
	if failures.is_empty():
		print("ENEMY_ANIMATION_TEST_PASS enemies=4")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
