extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("RUN SHOOT ANIMATION TEST: " + message)

func _run() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	var player := world.player
	_check(player.recovered_animation_tree != null, "recovered avatar has no AnimationTree layer graph")

	var fly_bag_bone := player.recovered_skeleton.find_bone("fly_bag")
	var expected_bag_basis := player.recovered_skeleton.get_bone_global_rest(fly_bag_bone).basis.inverse() * Basis.from_scale(Vector3.ONE * 0.8)
	_check(player.backpack_visual.position.is_zero_approx(), "backpack is offset from the original fly_bag anchor")
	_check(player.backpack_visual.basis.is_equal_approx(expected_bag_basis), "backpack rest rotation/scale does not match AvatarBuilder parenting")

	# Reproduce the actual report: hold the same actions driven by W and the
	# left mouse button across several automatic fire cooldowns while sampling
	# a lower-body bone. The old full-body run_shoot_rifle clip changes this
	# thigh by only about 0.067 rad and therefore looked frozen.
	player.max_health = 100000.0
	player.health = player.max_health
	player.max_shield = 100000.0
	player.shield = player.max_shield
	player.equip_weapon("gun00", false)
	player.energy = player.max_energy
	var energy_before := player.energy
	var position_before := player.global_position
	var thigh_bone := player.recovered_skeleton.find_bone("Bip01 L Thigh")
	_check(thigh_bone >= 0, "recovered skeleton has no left thigh bone")
	var first_thigh_rotation := Quaternion.IDENTITY
	var max_thigh_angle := 0.0
	var layered_frames := 0
	Input.action_press("move_forward")
	Input.action_press("fire")
	for frame in range(90):
		await get_tree().physics_frame
		if frame < 10 or thigh_bone < 0:
			continue
		if player.recovered_animation_tree.active and player.recovered_animation_name == "run_shoot_rifle":
			layered_frames += 1
		var thigh_rotation := player.recovered_skeleton.get_bone_pose_rotation(thigh_bone)
		if frame == 10:
			first_thigh_rotation = thigh_rotation
		else:
			max_thigh_angle = maxf(max_thigh_angle, first_thigh_rotation.angle_to(thigh_rotation))
	Input.action_release("fire")
	Input.action_release("move_forward")
	var moved_distance := player.global_position.distance_to(position_before)
	var energy_spent := energy_before - player.energy
	_check(layered_frames >= 65, "held fire did not keep the layered run-shoot state alive")
	_check(max_thigh_angle > 0.35, "left thigh froze during held run-and-shoot (max angle %.3f rad)" % max_thigh_angle)
	_check(moved_distance > 2.0, "player did not keep moving during held fire")
	var minimum_shot_cost := int(player.current_weapon.energy) * 4
	_check(energy_spent >= minimum_shot_cost, "held fire did not cross at least four firing cooldowns")

	# Laser uses rifle locomotion under its upper-body clip. Machinegun is the
	# original exception and keeps its authored full-body run-shoot animation.
	player.equip_weapon("gun21", false)
	player.shoot_pose_left = 0.3
	player._update_recovered_animation(1.0)
	_check(player.recovered_animation_tree.active, "laser run-shoot did not use the upper-body layer")
	_check(player.recovered_locomotion_name == "run_rifle", "laser did not preserve rifle locomotion")
	_check(player.recovered_upper_body_name == "run_shoot_laser", "laser upper-body clip is incorrect")

	player.equip_weapon("gun24", false)
	player.shoot_pose_left = 0.3
	player._update_recovered_animation(1.0)
	_check(not player.recovered_animation_tree.active, "machinegun should keep its original full-body run-shoot clip")
	_check(player.recovered_animation_name == "run_shoot_machinegun", "machinegun run-shoot clip is incorrect")
	_check(player.recovered_animation_player.get_animation("run_shoot_machinegun").loop_mode == Animation.LOOP_LINEAR, "automatic machinegun run-shoot clip does not loop")

	# A second one-shot can land on the exact frame the previous pose expires.
	# Keep the layer active to reproduce that boundary and require a fresh seek.
	player.set_physics_process(false)
	player.equip_weapon("gun06", false)
	player.energy = player.max_energy
	player.shot_cooldown = 0.0
	player.shoot_pose_left = 0.0
	player._try_fire()
	player._update_recovered_animation(1.0)
	_check(player.recovered_animation_tree.active, "shotgun run-shoot did not use the upper-body layer")
	_check(player.recovered_upper_body_name == "run_shoot_shotgun", "shotgun upper-body clip is incorrect")
	player.recovered_animation_tree.advance(0.78)
	player.shot_cooldown = 0.0
	player.shoot_pose_left = 0.0
	player._try_fire()
	player._update_recovered_animation(1.0)
	var second_shot_seek := float(player.recovered_animation_tree.get("parameters/upper_seek/seek_request"))
	_check(is_zero_approx(second_shot_seek), "second one-shot did not restart its upper-body clip")

	# Sword is the other original full-body moving-attack exception, and its
	# non-automatic clip must restart rather than remaining on the last frame.
	player.equip_weapon("gun27", false)
	player.energy = player.max_energy
	player.shot_cooldown = 0.0
	player.shoot_pose_left = 0.0
	player._try_fire()
	player._update_recovered_animation(1.0)
	_check(not player.recovered_animation_tree.active, "sword should keep its original full-body run-shoot clip")
	_check(player.recovered_animation_name == "run_shoot_jian", "sword run-shoot clip is incorrect")
	_check(player.recovered_animation_player.current_animation_position <= 0.001, "sword one-shot clip did not restart from frame zero")
	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.15).timeout
	if failures.is_empty():
		print(
			"RUN_SHOOT_ANIMATION_TEST_PASS weapons=5 continuous=true thigh_angle=%.3f moved=%.2f energy_spent=%d"
			% [max_thigh_angle, moved_distance, energy_spent]
		)
		get_tree().quit(0)
	else:
		get_tree().quit(1)
