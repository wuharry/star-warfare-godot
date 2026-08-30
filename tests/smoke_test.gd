extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE TEST: " + message)

func _run() -> void:
	GameState.selected_level = 1
	var packed := load("res://scenes/game.tscn") as PackedScene
	_check(packed != null, "game scene could not be loaded")
	if packed == null:
		get_tree().quit(1)
		return

	var world := packed.instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(is_instance_valid(world.player), "player was not created")
	_check(is_instance_valid(world.hud), "HUD was not created")
	_check(world.get_node_or_null("OriginalUnityLevel01") != null, "original Unity level art was not created")
	_check(world.get_node_or_null("OriginalUnityColliders") != null, "original Unity level collisions were not created")
	_check(world.player.is_in_group("player"), "player collision group is missing")
	_check(is_instance_valid(world.player.recovered_skeleton), "original player skeleton was not loaded")
	_check(world.player.recovered_skeleton.get_bone_count() == 28, "original player attachment skeleton is incomplete")
	_check(is_instance_valid(world.player.recovered_animation_player), "original AnimationPlayer was not loaded")
	_check(world.player.recovered_animation_player.get_animation_list().size() == 44, "original action library is incomplete")
	_check(world.player.gun_socket is BoneAttachment3D, "original animated weapon socket was not created")
	if world.player.gun_socket is BoneAttachment3D:
		_check(world.player.gun_socket.bone_name == "r hand gun", "weapon is not attached to the original r hand gun bone")
		_check(world.player.gun_mount.get_parent() == world.player.gun_socket, "weapon recoil pivot is outside the animated socket")
	_check(world.player.backpack_socket is BoneAttachment3D, "original animated backpack socket was not created")
	if world.player.backpack_socket is BoneAttachment3D:
		_check(world.player.backpack_socket.bone_name == "fly_bag", "backpack is not attached to the original fly_bag bone")
		_check(world.player.backpack_visual.get_parent() == world.player.backpack_socket, "backpack is outside the animated socket")
		world.player.recovered_animation_player.play("run_rifle")
		world.player.recovered_animation_player.seek(0.0, true)
		await get_tree().process_frame
		var backpack_pose_start := world.player.backpack_socket.global_transform
		world.player.recovered_animation_player.seek(0.28, true)
		await get_tree().process_frame
		var backpack_pose_later := world.player.backpack_socket.global_transform
		_check(not backpack_pose_start.is_equal_approx(backpack_pose_later), "backpack does not follow the running skeleton animation")
	world.player.equip_weapon("gun00", false)
	world.player.shoot_pose_left = 0.2
	world.player.recovered_animation_name = ""
	world.player._update_recovered_animation(0.0)
	_check(world.player.recovered_animation_name == "stand_shoot_rifle", "rifle firing does not select the original animation")

	var shield_before := world.player.shield
	world.player.take_damage(17.0)
	_check(is_equal_approx(world.player.shield, shield_before - 17.0), "shield damage is incorrect")
	world.player.restore("shield", 17.0)
	_check(is_equal_approx(world.player.shield, shield_before), "energy pickup restore is incorrect")
	world.player.set_touch_move(Vector2(0.5, -0.25))
	_check(world.player.touch_move.is_equal_approx(Vector2(0.5, -0.25)), "touch movement input was not accepted")

	for weapon_id in GameState.WEAPONS:
		world.player.equip_weapon(weapon_id, false)
		_check(world.player.current_weapon_id == weapon_id, "%s could not be equipped" % weapon_id)
		world.player.energy = world.player.max_energy
		var energy_before := world.player.energy
		world.player.shot_cooldown = 0.0
		world.player.reload_left = 0.0
		world.player._try_fire()
		_check(world.player.energy == energy_before - int(GameState.WEAPONS[weapon_id].energy), "%s did not consume original energy cost" % weapon_id)
	world.player.equip_weapon(GameState.selected_weapon, false)

	world._spawn_enemy("crawler", false)
	await get_tree().process_frame
	var enemy := get_tree().get_first_node_in_group("enemies") as WarfareEnemy
	_check(is_instance_valid(enemy), "enemy could not be spawned")
	if is_instance_valid(enemy):
		var alive_before := world.alive_enemies
		enemy.take_damage(enemy.max_health + 1.0)
		_check(world.alive_enemies == alive_before - 1, "enemy death did not update the wave counter")

	world.hud.show_result(true, {"score": 1200, "kills": 7, "credits": 42, "time": 95.0})
	_check(is_instance_valid(world.hud.result_overlay), "victory result overlay was not created")
	_check(get_tree().paused, "result screen does not suspend gameplay")
	get_tree().paused = false

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.2).timeout
	if failures.is_empty():
		print("SMOKE_TEST_PASS")
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
