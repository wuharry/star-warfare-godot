extends "res://tests/rocket_reload_preview.gd"

var failures: Array[String] = []
var max_contact_error := 0.0

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ROCKET RELOAD TEST: " + message)

func _ready() -> void:
	await super._ready()
	set_process(false)
	var skeleton := player.recovered_skeleton
	var right := skeleton.find_bone("Bip01 R Hand")
	var left := skeleton.find_bone("Bip01 L Hand")
	var directions: Array[Vector3] = []
	var body := player.gun_mount.get_node("WeaponVisual/Recovered_gun11") as MeshInstance3D
	var rocket := player.attached_reload_part.get_node("OriginalMagazine") as MeshInstance3D
	_check(rocket.global_transform.is_equal_approx(body.global_transform), "assembled rocket changed original origin or scale")
	_check(body.mesh.resource_path.ends_with("gun11_body.obj") and rocket.mesh.resource_path.ends_with("gun11_rocket.obj"), "launcher still uses whole mesh or fabricated rocket")
	for variant in range(2):
		for walking in [false, true]:
			moving = walking
			_restart(variant)
			var grip := (skeleton.global_transform * skeleton.get_bone_global_pose(right)).affine_inverse() * player.gun_mount.global_transform
			var debris := get_tree().get_nodes_in_group("reload_debris").size()
			_check(not player.attached_reload_part.visible, "empty launcher still shows its fired warhead")
			player.rocket_reload_variant = 1 - variant
			player.camera_yaw = 1.2
			var original_yaw := player.body_yaw
			for progress in [0.22, 0.32, 0.48, 0.61, 0.65, 0.79, 0.83, 0.94]:
				while elapsed < progress * player.reload_total - 0.000001:
					_advance(minf(1.0 / 60.0, progress * player.reload_total - elapsed))
				await get_tree().process_frame
				_check(player.active_rocket_reload_variant == variant, "variant changed midway through reload")
				_check(is_equal_approx(player.camera_yaw, 1.2) and is_equal_approx(player.body_yaw, original_yaw), "stationary reload locked camera or turned body toward camera")
				var current_grip := (skeleton.global_transform * skeleton.get_bone_global_pose(right)).affine_inverse() * player.gun_mount.global_transform
				_check(current_grip.origin.distance_to(grip.origin) < 0.003 and current_grip.basis.is_equal_approx(grip.basis), "launcher slipped out of right-hand grip")
				_check(player._magazine_rounds() == 0, "ammo credited before reload completion")
				if progress >= 0.32 and progress <= 0.79:
					_check(is_instance_valid(player.reload_hand_prop) and not player.attached_reload_part.visible, "expected exactly one held rocket")
					if is_instance_valid(player.reload_hand_prop):
						var contact := skeleton.to_global(skeleton.get_bone_global_pose(left).origin).distance_to(player.reload_hand_prop.global_position)
						max_contact_error = maxf(max_contact_error, contact)
						_check(contact < 0.10, "left wrist missed rocket: variant=%d moving=%s progress=%.2f distance=%.3f" % [variant, walking, progress, contact])
				else:
					_check(not is_instance_valid(player.reload_hand_prop), "held rocket survived before pickup or after seating")
				if progress >= 0.83:
					_check(player.attached_reload_part.visible, "seated rocket missing")
				if progress == 0.48 and not walking:
					directions.append(-player.gun_mount.global_basis.z.normalized())
			_check(get_tree().get_nodes_in_group("reload_debris").size() == debris, "reload ejected a live rocket")
			_advance(player.reload_left)
			_check(player._magazine_rounds() == 1 and player.attached_reload_part.visible, "reload did not finish with exactly one loaded rocket")
			_check(not is_instance_valid(player.reload_hand_prop), "completion left a held rocket")
	_check(directions.size() == 2 and directions[0].angle_to(directions[1]) > 0.6, "two variants do not have distinct launcher angles")
	await _check_running_physics()
	for variant in range(2):
		for progress in [0.5, 0.85]:
			_restart(variant)
			_advance(player.reload_total * progress)
			player._cancel_reload()
			_check(not player.attached_reload_part.visible and not is_instance_valid(player.reload_hand_prop) and player._magazine_rounds() == 0, "cancel left a phantom loaded rocket")
	_restart(0)
	_advance(player.reload_total * 0.5)
	player.equip_weapon("gun00", false)
	_check(player.reload_left == 0.0 and not is_instance_valid(player.reload_hand_prop), "weapon switch left rocket reload active")
	player.equip_weapon("gun11", false)
	player._set_magazine_rounds(1)
	player.shot_cooldown = 0.0
	player._try_fire()
	_check(player._magazine_rounds() == 0 and not player.attached_reload_part.visible, "firing did not hide spent warhead")
	player._cancel_reload()
	player.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("ROCKET_RELOAD_TEST_PASS variants=2 moving_layers=true cancellation=true original_mesh=true max_wrist_distance=%.4f" % max_contact_error)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_running_physics() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	add_child(floor_body)
	player.armor_skills["fly"] = 0.0
	player.camera_yaw = 0.0
	player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	for variant in range(2):
		_restart(variant)
		var before := player.position
		var skeleton := player.recovered_skeleton
		var thigh := skeleton.find_bone("Bip01 L Thigh")
		var left := skeleton.find_bone("Bip01 L Hand")
		var baseline := Quaternion.IDENTITY
		var max_angle := 0.0
		var contacts := 0
		Input.action_press("move_forward")
		player.set_physics_process(true)
		for frame in range(180):
			await get_tree().physics_frame
			await get_tree().process_frame
			if frame == 10:
				baseline = skeleton.get_bone_pose_rotation(thigh)
			elif frame > 10:
				max_angle = maxf(max_angle, baseline.angle_to(skeleton.get_bone_pose_rotation(thigh)))
			if player.reload_left <= 0.0:
				break
			var progress := player.reload_elapsed / player.reload_total
			if progress > 0.35 and progress < 0.80 and is_instance_valid(player.reload_hand_prop):
				var contact := skeleton.to_global(skeleton.get_bone_global_pose(left).origin).distance_to(player.reload_hand_prop.global_position)
				max_contact_error = maxf(max_contact_error, contact)
				_check(contact < 0.10, "running physics detached hand: variant=%d distance=%.3f" % [variant, contact])
				_check(player.recovered_locomotion_name == "run_bazinga" and player.recovered_upper_body_name == "idle_bazinga", "moving reload lost launcher animation layers")
				contacts += 1
		Input.action_release("move_forward")
		player.set_physics_process(false)
		_check(contacts > 10 and max_angle > 0.35 and player.position.distance_to(before) > 1.5, "reload froze movement or running legs")
		print("ROCKET_RUNNING variant=%d contacts=%d thigh_angle=%.3f distance=%.3f" % [variant, contacts, max_angle, player.position.distance_to(before)])
		player._cancel_reload()
	player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
