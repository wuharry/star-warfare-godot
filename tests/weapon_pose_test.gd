extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("WEAPON POSE TEST: " + message)

func _run() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	for _frame in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame

	var player := world.player
	_check(is_instance_valid(player.gun_socket), "animated avatar has no recovered weapon socket")
	if is_instance_valid(player.gun_socket):
		_check(player.gun_socket.bone_name == "r hand gun", "weapon is not attached to the original r hand gun bone")
		_check(player.gun_mount.get_parent() == player.gun_socket, "recoil pivot is not below the animated weapon socket")

	for weapon_id in ["gun00", "gun06", "gun11", "gun24", "gun34"]:
		player.equip_weapon(weapon_id, false)
		player.shot_cooldown = 0.0
		player.shoot_pose_left = 0.0
		for _frame in range(3):
			await get_tree().process_frame
			await get_tree().physics_frame
		var idle_direction := -player.gun_mount.global_transform.basis.z.normalized()
		var character_forward := -player.model.global_transform.basis.z.normalized()
		var idle_dot := idle_direction.dot(character_forward)
		_check(idle_dot > 0.45, "%s idle weapon points away from character aim (dot %.3f)" % [weapon_id, idle_dot])

		player._try_fire()
		await get_tree().process_frame
		await get_tree().physics_frame
		var fire_direction := -player.gun_mount.global_transform.basis.z.normalized()
		var fire_dot := fire_direction.dot(character_forward)
		_check(fire_dot > 0.55, "%s firing weapon points away from character aim (dot %.3f)" % [weapon_id, fire_dot])
		_check("shoot" in player.recovered_animation_name.to_lower(), "%s did not enter its recovered firing animation" % weapon_id)
		print("WEAPON_POSE %s idle_dot=%.3f fire_dot=%.3f animation=%s" % [weapon_id, idle_dot, fire_dot, player.recovered_animation_name])

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("WEAPON_POSE_TEST_PASS weapons=5 socket=r_hand_gun")
		get_tree().quit(0)
	else:
		print("WEAPON_POSE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
