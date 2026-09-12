extends RefCounted

## Pose variants share timing and a per-model socket, never a shared magazine.

static func frame(player) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var reference: Transform3D = player.reload_chest_references.get(player._reload_idle_animation(), Transform3D.IDENTITY)
	return skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 Spine1")) * reference.affine_inverse()

static func base_gun(player) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	return skeleton.get_bone_global_pose_no_override(skeleton.find_bone(player.gun_socket.bone_name)) * Transform3D(Basis(player.gun_mount_rest_rotation), player.gun_mount_rest_position)

static func weight(player, progress: float) -> float:
	var raise := smoothstep(0.0, 0.18, progress)
	var lower := 1.0 - smoothstep(0.84, 1.0, progress)
	if str(player.current_weapon.reload_style) == "shotgun_shell":
		if not player.reload_first_cycle:
			raise = 1.0
		if player.reload_start_rounds + 1 < int(player.current_weapon.magazine_size):
			lower = 1.0
	return raise * lower

static func outward(player) -> Vector3:
	return (player.gun_mount.get_node("WeaponVisual").global_basis * Vector3(player.current_weapon.reload_outward)).normalized()

static func prop_position(player, progress: float) -> Vector3:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var socket: Vector3 = player.reload_part_socket.global_position
	var chest := frame(player)
	var shoulder := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 L UpperArm")).origin
	var variant: int = player.active_reload_variant
	var pocket := skeleton.to_global(shoulder + chest.basis * Vector3(-0.04 - 0.025 * variant, -0.32, 0.04))
	var distance := float(player.current_weapon.reload_pull_distance)
	var extracted := socket + outward(player) * distance
	var drop := float(player.current_weapon.drop_fraction)
	var hand := float(player.current_weapon.hand_fraction)
	var insert := float(player.current_weapon.insert_fraction)
	var align := lerpf(hand, insert, 0.72 if variant == 0 else 0.62 if variant == 1 else 0.80)
	if drop >= 0.0 and progress < drop:
		return socket.lerp(extracted, smoothstep(drop * 0.45, drop, progress))
	if progress < hand:
		return extracted.lerp(pocket, smoothstep(maxf(0.0, drop), hand, progress))
	if progress < align:
		var travel := smoothstep(hand, align, progress)
		var arc := chest.basis.y * (0.035 + 0.035 * variant)
		if variant == 2:
			arc -= chest.basis.x * 0.06
		return pocket.lerp(extracted, travel) + skeleton.global_basis * arc * sin(travel * PI)
	return extracted.lerp(socket, smoothstep(align, insert, progress))

static func support_pose(player) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var left := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 L Hand"))
	var gun: Transform3D = skeleton.global_transform.affine_inverse() * player.gun_mount.global_transform
	return gun * base_gun(player).affine_inverse() * left

static func left_pose(player, progress: float) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var supported := support_pose(player)
	var target := supported
	var grasp := skeleton.to_local(prop_position(player, progress)) + supported.basis.x * 0.065
	var drop := float(player.current_weapon.drop_fraction)
	var hand := float(player.current_weapon.hand_fraction)
	var insert := float(player.current_weapon.insert_fraction)
	var reach := smoothstep(0.0, drop * 0.45 if drop > 0.0 else hand, progress)
	var release := smoothstep(insert + 0.015, 0.97, progress)
	target.origin = supported.origin.lerp(grasp, reach).lerp(supported.origin, release)
	return target

static func update(player, progress: float) -> void:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var hand := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 R Hand"))
	var shoulder := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 R UpperArm")).origin
	var chest := frame(player)
	var hand_to_gun := hand.affine_inverse() * base_gun(player)
	var variant: int = player.active_reload_variant
	var category := str(player.current_weapon.reload_category)
	var angles := Vector3(0.28, 0.16, -0.28)
	var wrist := Vector3(0.10, -0.24, -0.43)
	match category:
		"rifle":
			if variant == 1:
				angles = Vector3(0.43, 0.58, 0.18)
				wrist = Vector3(0.02, -0.22, -0.44)
			elif variant == 2:
				angles = Vector3(0.12, 0.80, -0.42)
				wrist = Vector3(0.03, -0.28, -0.43)
		"sniper":
			angles = Vector3(0.24, 0.24, -0.36) if variant == 0 else Vector3(0.12, 0.73, -0.15)
			wrist = Vector3(0.05, -0.25, -0.45)
		"shotgun":
			angles = Vector3(0.10, 0.42, -0.68) if variant == 0 else Vector3(0.42, 0.18, 0.30)
			wrist = Vector3(0.04, -0.23, -0.42)
		"grenade":
			angles = Vector3(0.20, 0.56, -0.48) if variant == 0 else Vector3(0.47, 0.90, -0.05)
			wrist = Vector3(0.00, -0.26, -0.44)
		"rocket":
			angles = Vector3(0.22, 0.58, -0.35) if variant == 0 else Vector3(0.48, 0.90, -0.06)
			wrist = Vector3(0.02, -0.24, -0.45)
	wrist += Vector3(player.current_weapon.get("reload_wrist_offset", Vector3.ZERO))
	var held_basis := chest.basis * Basis.from_euler(angles) * hand_to_gun.basis.inverse()
	var target := hand.interpolate_with(Transform3D(held_basis, shoulder + chest.basis * wrist), weight(player, progress))
	player.gun_mount.position = player.gun_mount_rest_position
	player.gun_mount.quaternion = player.gun_mount_rest_rotation
	player._solve_reload_arm_pose("R", target)
	player.gun_socket.transform = skeleton.get_bone_global_pose(skeleton.find_bone(player.gun_socket.bone_name))
	if is_instance_valid(player.attached_reload_part):
		var drop := float(player.current_weapon.drop_fraction)
		if drop > 0.0 and progress < drop:
			player.attached_reload_part.global_position = prop_position(player, progress)
		else:
			player.attached_reload_part.position = Vector3.ZERO
	player._solve_reload_arm_pose("L", left_pose(player, progress))
	player._update_reload_hand_prop()
