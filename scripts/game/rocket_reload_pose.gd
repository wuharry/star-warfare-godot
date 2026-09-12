extends RefCounted

## Two presentation variants for RPG-21, sharing its actual front-loaded warhead.
## Arms carry the weapon; no extra translation is applied to the weapon mount.

static func weight(progress: float) -> float:
	return smoothstep(0.0, 0.22, progress) * (1.0 - smoothstep(0.86, 1.0, progress))

static func chest_frame(player) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	return skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 Spine1")) * player.rocket_reference_chest_pose.affine_inverse()

static func base_gun_pose(player) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	return skeleton.get_bone_global_pose_no_override(skeleton.find_bone(player.gun_socket.bone_name)) * Transform3D(Basis(player.gun_mount_rest_rotation), player.gun_mount_rest_position)

static func support_pose(player) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var left := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 L Hand"))
	var gun: Transform3D = skeleton.global_transform.affine_inverse() * player.gun_mount.global_transform
	return gun * base_gun_pose(player).affine_inverse() * left

static func rocket_position(player, progress: float) -> Vector3:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var socket: Marker3D = player.reload_part_socket
	var shoulder := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 L UpperArm")).origin
	var frame := chest_frame(player)
	var pocket := skeleton.to_global(shoulder + frame.basis * Vector3(-0.06, -0.34, 0.05))
	var outward := -socket.global_basis.z.normalized()
	var aligned := socket.global_position + outward * 0.16
	var hand := float(player.current_weapon.hand_fraction)
	var insert := float(player.current_weapon.insert_fraction)
	var align_fraction := 0.61 if player.active_rocket_reload_variant == 0 else 0.65
	if progress <= hand:
		return pocket
	if progress < align_fraction:
		var travel := smoothstep(hand, align_fraction, progress)
		return pocket.lerp(aligned, travel) + skeleton.global_basis * frame.basis.y * sin(travel * PI) * 0.06
	return aligned.lerp(socket.global_position, smoothstep(align_fraction, insert, progress))

static func left_hand_pose(player, progress: float) -> Transform3D:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var supported := support_pose(player)
	var target := supported
	# The wrist sits just below the warhead; its center stays in the palm.
	var grasp := skeleton.to_local(rocket_position(player, progress)) + supported.basis.x * 0.065
	var hand := float(player.current_weapon.hand_fraction)
	var insert := float(player.current_weapon.insert_fraction)
	if progress < hand:
		target.origin = supported.origin.lerp(grasp, smoothstep(0.04, hand, progress))
	else:
		target.origin = grasp.lerp(supported.origin, smoothstep(insert + 0.02, 0.96, progress))
	return target

static func update(player, progress: float) -> void:
	var skeleton: Skeleton3D = player.recovered_skeleton
	var hand := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 R Hand"))
	var shoulder := skeleton.get_bone_global_pose_no_override(skeleton.find_bone("Bip01 R UpperArm")).origin
	var frame := chest_frame(player)
	var hand_to_gun := hand.affine_inverse() * base_gun_pose(player)
	var upright: bool = player.active_rocket_reload_variant == 1
	var angles := Vector3(0.98, 0.45, -0.08) if upright else Vector3(0.25, 1.05, -0.12)
	var wrist_offset := Vector3(0.06, -0.39, -0.34) if upright else Vector3(0.04, -0.20, -0.50)
	var held_basis := frame.basis * Basis.from_euler(angles) * hand_to_gun.basis.inverse()
	var held_wrist := shoulder + frame.basis * wrist_offset
	var target := hand.interpolate_with(Transform3D(held_basis, held_wrist), weight(progress))
	player.gun_mount.position = player.gun_mount_rest_position
	player.gun_mount.quaternion = player.gun_mount_rest_rotation
	player._solve_reload_arm_pose("R", target)
	player.gun_socket.transform = skeleton.get_bone_global_pose(skeleton.find_bone(player.gun_socket.bone_name))
	player._solve_reload_arm_pose("L", left_hand_pose(player, progress))
	player._update_reload_hand_prop()
