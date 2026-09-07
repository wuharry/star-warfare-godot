extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("RELOAD SYSTEM TEST: " + message)

func _keyed_stream_path(key: String) -> String:
	var audio: Node = AudioDirector._keyed_players.get(key)
	if not is_instance_valid(audio):
		return ""
	var stream: AudioStream = audio.get("stream") as AudioStream
	return stream.resource_path if stream != null else ""

func _run() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	var player := world.player
	player.set_physics_process(false)
	_check(ResourceLoader.exists("res://assets/original/audio/combat/reload_eject.wav"), "reload eject audio is missing")
	_check(ResourceLoader.exists("res://assets/original/audio/combat/reload_insert.wav"), "reload insert audio is missing")

	var cases := {
		"gun00": {"style": "rifle", "capacity": 30, "drops": true, "eject": true},
		"gun35": {"style": "sniper", "capacity": 5, "drops": true, "eject": true},
		"gun06": {"style": "shotgun_shell", "capacity": 6, "drops": false, "eject": false},
		"gun11": {"style": "rocket", "capacity": 1, "drops": true, "eject": true},
		"gun14": {"style": "grenade_drum", "capacity": 4, "drops": true, "eject": true},
	}
	var styles: Dictionary = {}
	for weapon_id: String in cases:
		var expected: Dictionary = cases[weapon_id]
		player.equip_weapon(weapon_id, false)
		if weapon_id == "gun00":
			_check_fr28a_parts(player)
		_check(str(player.current_weapon.resource_model) == "magazine", "%s has no magazine resource model" % weapon_id)
		_check(str(player.current_weapon.reload_style) == str(expected.style), "%s uses the wrong reload style" % weapon_id)
		styles[str(player.current_weapon.reload_style)] = true
		_check(player._magazine_rounds() == int(expected.capacity), "%s did not start with a full magazine" % weapon_id)
		player.shot_cooldown = 0.0
		var energy_before := player.energy
		player._try_fire()
		_check(player._magazine_rounds() == int(expected.capacity) - 1, "%s did not consume one magazine round" % weapon_id)
		_check(player.energy < energy_before, "%s stopped consuming the recovered Energy value" % weapon_id)

		player._set_magazine_rounds(0)
		var debris_before := get_tree().get_nodes_in_group("reload_debris").size()
		AudioDirector.stop_all_sfx()
		player._start_reload()
		_check(player.reload_left > 0.0, "%s did not begin reloading" % weapon_id)
		_check(
			_keyed_stream_path("player_reload_action").ends_with("reload_eject.wav") == bool(expected.eject),
			"%s used the wrong magazine eject audio behavior" % weapon_id
		)
		player._update_reload(player.reload_total * 0.50)
		var debris_after := get_tree().get_nodes_in_group("reload_debris").size()
		_check(debris_after == debris_before + (1 if bool(expected.drops) else 0), "%s spawned the wrong dropped reload prop count" % weapon_id)
		_check(is_instance_valid(player.reload_hand_prop), "%s did not put a fresh reload prop in motion" % weapon_id)
		if weapon_id == "gun00":
			_check(not player.attached_reload_part.visible, "FR28a magazine remained on the gun after removal")
			var hand_mesh := player.reload_hand_prop.get_node("OriginalMagazine") as MeshInstance3D
			var debris := get_tree().get_nodes_in_group("reload_debris").back() as RigidBody3D
			var dropped_mesh := debris.get_node("ReloadDebrisVisual/OriginalMagazine") as MeshInstance3D
			_check(hand_mesh.mesh == player.reload_prop_mesh and dropped_mesh.mesh == hand_mesh.mesh, "FR28a hand/drop use different magazine geometry")
			_check(hand_mesh.transform.is_equal_approx(dropped_mesh.transform), "FR28a dropped magazine changed size or origin")
			for child in debris.get_children():
				if child is CollisionShape3D:
					var box := child.shape as BoxShape3D
					_check(box != null and box.size.is_equal_approx(hand_mesh.mesh.get_aabb().size * player.reload_prop_scale), "FR28a collision still uses the oversized placeholder")
		var insert_fraction := float(player.current_weapon.get("insert_fraction", 0.75))
		player._update_reload(player.reload_total * (insert_fraction - 0.48))
		var expected_insert := "ShotgunCock02.wav" if str(expected.style) == "shotgun_shell" else "reload_insert.wav"
		_check(_keyed_stream_path("player_reload_action").ends_with(expected_insert), "%s did not play its magazine insert sound" % weapon_id)
		player._update_reload(player.reload_total)
		if weapon_id == "gun00":
			_check(player.attached_reload_part.visible and not is_instance_valid(player.reload_hand_prop), "FR28a did not restore its single attached magazine")
			_check_fr28a_parts(player)
		if str(expected.style) == "shotgun_shell":
			_check(player._magazine_rounds() == 1, "shotgun did not insert exactly one shell per cycle")
			_check(player.reload_left > 0.0, "shotgun did not continue its per-shell reload")
			player._cancel_reload()
		else:
			_check(player._magazine_rounds() == int(expected.capacity), "%s did not refill its magazine" % weapon_id)
			_check(is_zero_approx(player.reload_left), "%s reload did not finish" % weapon_id)

	_check(styles.size() == 5, "the vertical slice does not expose five distinct reload actions")

	player.equip_weapon("gun06", false)
	player._set_magazine_rounds(2)
	player.shot_cooldown = 0.0
	player._start_reload()
	player.touch_fire_started = true
	player._handle_weapon_input()
	_check(is_zero_approx(player.reload_left), "shotgun fire did not interrupt per-shell reload")
	_check(player._magazine_rounds() == 1, "shotgun interrupt did not immediately fire the loaded shell")
	_check(_keyed_stream_path("player_reload_action").is_empty(), "shotgun interrupt left reload audio playing")

	player.equip_weapon("gun00", false)
	player._set_magazine_rounds(0)
	player._start_reload()
	player._update_reload(player.reload_total * 0.5)
	player._cancel_reload()
	_check(player.attached_reload_part.visible and not is_instance_valid(player.reload_hand_prop), "FR28a cancelled reload left a missing or duplicate magazine")
	player._start_reload()
	player.equip_weapon("gun35", false)
	_check(is_zero_approx(player.reload_left), "weapon switching did not cancel reload")
	_check(_keyed_stream_path("player_reload_action").is_empty(), "weapon switching left reload audio playing")
	await _check_fr28a_reload_pose(player)
	await _check_fr28a_running_reload(player)

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.15).timeout
	if failures.is_empty():
		print("RELOAD_SYSTEM_TEST_PASS weapons=5 styles=5 infinite_reserve=true physical_drops=true mechanical_audio=true staged_fr28a_pose=true")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _check_fr28a_reload_pose(player: WarfarePlayer) -> void:
	player.equip_weapon("gun00", false)
	player.shoot_pose_left = 0.0
	player.touch_fire = false
	player.velocity = Vector3.ZERO
	player.body_yaw = 0.0
	player.model.rotation.y = 0.0
	player._play_recovered_animation("idle_rifle", 0.0, true)
	player.recovered_animation_player.advance(0.0)
	player.recovered_animation_player.pause()
	var skeleton := player.recovered_skeleton
	skeleton.clear_bones_global_pose_override()
	skeleton.force_update_all_bone_transforms()
	await get_tree().process_frame
	var hand_index := skeleton.find_bone("Bip01 R Hand")
	var left_hand_index := skeleton.find_bone("Bip01 L Hand")
	_check(hand_index >= 0 and left_hand_index >= 0, "FR28a reload pose has no recovered hands")
	if hand_index < 0 or left_hand_index < 0:
		return
	var rest_gun := player.gun_mount.global_transform
	var rest_hand := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	var rest_grip := rest_hand.affine_inverse() * rest_gun
	var rest_direction := -rest_gun.basis.z.normalized()
	player._set_magazine_rounds(0)
	player._start_reload()
	for progress in [0.15, 0.21]:
		await _advance_fr28a_reload_pose(player, progress)
		_check_fr28a_magazine_contact(player, left_hand_index, player.attached_reload_part, progress)

	# Sample the actual arm, weapon, and prop after the runtime frame sequence.
	# A local gun rotation alone can pass a tilt test while leaving the grip
	# detached from the hand, so compare their complete relative transform.
	await _advance_fr28a_reload_pose(player, 0.28)
	var held_gun := player.gun_mount.global_transform
	var held_hand := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	var held_direction := -held_gun.basis.z.normalized()
	_check(held_direction.y > 0.05 and held_direction.y > rest_direction.y + 0.10, "FR28a reload did not raise the barrel above its idle direction")
	_check(held_hand.origin.y > rest_hand.origin.y + 0.03, "FR28a reload did not lift the gun with its right hand")
	_check_transform_near(held_hand.affine_inverse() * held_gun, rest_grip, "FR28a raised gun slipped out of its right-hand grip")
	var left_hand_before := skeleton.get_bone_global_pose(left_hand_index).origin
	for progress in [0.38, 0.62, 0.64, 0.72]:
		await _advance_fr28a_reload_pose(player, progress)
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
		_check_transform_near(player.gun_mount.global_transform, held_gun, "FR28a gun did not hold steady during magazine exchange")
		_check_transform_near(hand.affine_inverse() * player.gun_mount.global_transform, rest_grip, "FR28a magazine exchange detached the right-hand grip")
		_check_fr28a_magazine_contact(player, left_hand_index, player.reload_hand_prop, progress)
		if is_equal_approx(progress, 0.38):
			_check(is_instance_valid(player.reload_hand_prop), "FR28a staged reload has no magazine in the left hand")
			if is_instance_valid(player.reload_hand_prop):
				var held_prop := player.model.global_transform.affine_inverse() * player.reload_hand_prop.global_transform
				var gun_in_body := player.model.global_transform.affine_inverse() * player.gun_mount.global_transform
				player.body_yaw = PI * 0.5
				player.model.rotation.y = player.body_yaw
				player._update_combat_aim_pose(1.0 / 60.0)
				player._update_reload_pose()
				await get_tree().process_frame
				_check_transform_near(player.model.global_transform.affine_inverse() * player.gun_mount.global_transform, gun_in_body, "FR28a turn changed its reload pose relative to the body")
				_check_transform_near(player.model.global_transform.affine_inverse() * player.reload_hand_prop.global_transform, held_prop, "FR28a reload magazine target stayed in world space while the body turned")
				player.body_yaw = 0.0
				player.model.rotation.y = 0.0
	_check(skeleton.get_bone_global_pose(left_hand_index).origin.distance_to(left_hand_before) > 0.06, "FR28a hold also froze the hand exchanging the magazine")

	await _advance_fr28a_reload_pose(player, 0.99)
	_check_transform_near(player.gun_mount.global_transform, rest_gun, "FR28a reload failed to lower the gun smoothly before completion", 0.01, 0.02)
	player._update_reload(player.reload_total)
	player._update_combat_aim_pose(1.0 / 60.0)
	skeleton.force_update_all_bone_transforms()
	await get_tree().process_frame
	_check_transform_near(player.gun_mount.global_transform, rest_gun, "FR28a completed reload left the weapon raised")
	_check(player.attached_reload_part.visible and not is_instance_valid(player.reload_hand_prop), "FR28a staged pose changed magazine completion behavior")

func _check_fr28a_magazine_contact(player: WarfarePlayer, hand_index: int, magazine: Node3D, progress: float) -> void:
	_check(is_instance_valid(magazine), "FR28a reload lost its magazine at progress %.3f" % progress)
	if not is_instance_valid(magazine):
		return
	var hand_position := player.recovered_skeleton.to_global(player.recovered_skeleton.get_bone_global_pose(hand_index).origin)
	var contact_distance := hand_position.distance_to(magazine.global_position)
	# The recovered wrist sits behind the palm. Allow the hand's physical
	# length, but reject an unreachable target that leaves it visibly floating.
	_check(contact_distance < 0.10, "FR28a wrist cannot reach its magazine at progress %.3f (distance %.3f)" % [progress, contact_distance])

func _check_fr28a_running_reload(player: WarfarePlayer) -> void:
	player.equip_weapon("gun00", false)
	player.shoot_pose_left = 0.0
	player.hurt_pose_left = 0.0
	player.touch_fire = false
	player.armor_skills["fly"] = 0.0
	player.max_health = 100000.0
	player.health = player.max_health
	player.max_shield = 100000.0
	player.shield = player.max_shield
	player._set_magazine_rounds(0)
	player._start_reload()
	player._update_recovered_animation(1.0, Vector2(0.0, -1.0))
	var skeleton := player.recovered_skeleton
	var left_hand_index := skeleton.find_bone("Bip01 L Hand")
	var thigh_index := skeleton.find_bone("Bip01 L Thigh")
	_check(thigh_index >= 0, "FR28a running reload has no recovered thigh")
	if thigh_index < 0:
		player._cancel_reload()
		return
	var first_thigh_rotation := Quaternion.IDENTITY
	var max_thigh_angle := 0.0
	var position_before := player.global_position
	var sample_fractions: Array[float] = [0.15, 0.21, 0.38, 0.64, 0.72]
	var sample_index := 0
	# Run normal player physics and AnimationTree callbacks together. The
	# full-body run clip can pull a shoulder beyond magazine reach even when
	# the same procedural reload passes every stationary-pose assertion.
	Input.action_press("move_forward")
	player.set_physics_process(true)
	for frame in range(150):
		await get_tree().physics_frame
		await get_tree().process_frame
		# Exclude the initial idle-to-run transition: a single pose change
		# must not satisfy the requirement that the legs keep animating.
		if frame == 10:
			first_thigh_rotation = skeleton.get_bone_pose_rotation(thigh_index)
		elif frame > 10:
			max_thigh_angle = maxf(max_thigh_angle, first_thigh_rotation.angle_to(skeleton.get_bone_pose_rotation(thigh_index)))
		if player.reload_left <= 0.0:
			break
		var progress := player.reload_elapsed / player.reload_total
		if sample_index >= sample_fractions.size() or progress < sample_fractions[sample_index]:
			continue
		_check(player.recovered_animation_tree.active and player.recovered_locomotion_name == "run_rifle" and player.recovered_upper_body_name == "idle_rifle", "FR28a moving reload did not retain running legs and rifle upper body")
		var magazine := player.attached_reload_part if sample_index < 2 else player.reload_hand_prop
		_check_fr28a_magazine_contact(player, left_hand_index, magazine, progress)
		sample_index += 1
	Input.action_release("move_forward")
	player.set_physics_process(false)
	var moved_distance := player.global_position.distance_to(position_before)
	_check(sample_index == sample_fractions.size(), "FR28a running reload did not reach all magazine contact samples")
	_check(max_thigh_angle > 0.35, "FR28a reload froze its running legs (thigh angle %.3f rad)" % max_thigh_angle)
	_check(moved_distance > 1.5, "FR28a reload stopped actual movement (distance %.3f)" % moved_distance)
	print("FR28A_RUNNING_RELOAD thigh_angle=%.3f moved_distance=%.3f contact_samples=%d" % [max_thigh_angle, moved_distance, sample_index])
	player._cancel_reload()

func _advance_fr28a_reload_pose(player: WarfarePlayer, progress: float) -> void:
	var target_elapsed := player.reload_total * progress
	while player.reload_elapsed < target_elapsed - 0.000001:
		var delta := minf(1.0 / 60.0, target_elapsed - player.reload_elapsed)
		player._update_reload(delta)
		player._update_body_facing(delta, Vector3.ZERO)
		player._update_combat_aim_pose(delta)
		player._update_reload_pose()
		# BoneAttachment3D publishes the solved bone transform at frame end.
		await get_tree().process_frame

func _check_transform_near(actual: Transform3D, expected: Transform3D, message: String, position_tolerance := 0.003, angle_tolerance := 0.01) -> void:
	var position_error := actual.origin.distance_to(expected.origin)
	var angle_error := actual.basis.orthonormalized().get_rotation_quaternion().angle_to(expected.basis.orthonormalized().get_rotation_quaternion())
	_check(position_error < position_tolerance and angle_error < angle_tolerance, "%s (position %.4f, angle %.3f degrees)" % [message, position_error, rad_to_deg(angle_error)])

func _mesh_triangles(mesh: Mesh) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	# get_faces() additionally snaps coordinates to a grid. Inspect the actual
	# imported vertex/index buffers so rounding cannot move a matching corner.
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for offset in range(0, indices.size(), 3):
			result.append(PackedVector3Array([vertices[indices[offset]], vertices[indices[offset + 1]], vertices[indices[offset + 2]]]))
	return result

func _same_triangle(first: PackedVector3Array, second: PackedVector3Array, tolerance: float) -> bool:
	for rotation in range(3):
		var matches := true
		for corner in range(3):
			if first[corner].distance_to(second[(corner + rotation) % 3]) > tolerance:
				matches = false
				break
		if matches:
			return true
	return false

func _check_fr28a_parts(player: WarfarePlayer) -> void:
	var body := player.gun_mount.get_node("WeaponVisual/Recovered_gun00") as MeshInstance3D
	var magazine := player.attached_reload_part.get_node_or_null("OriginalMagazine") as MeshInstance3D
	_check(magazine != null, "FR28a still uses the generated box magazine")
	if magazine == null:
		return
	_check(magazine.global_transform.is_equal_approx(body.global_transform), "FR28a magazine no longer matches the gun's original coordinates/scale")
	var source := load("res://assets/models/weapons/gun00.obj") as Mesh
	var source_faces := _mesh_triangles(source)
	var remaining := _mesh_triangles(body.mesh) + _mesh_triangles(magazine.mesh)
	# Position compression uses 16 bits within each mesh's own AABB. The sum
	# of both quantization bounds accounts for different part bounds, not gaps.
	var tolerance := (source.get_aabb().size.length() + maxf(body.mesh.get_aabb().size.length(), magazine.mesh.get_aabb().size.length())) / 65535.0 + 0.0000001
	for triangle in source_faces:
		var found := -1
		for index in remaining.size():
			if _same_triangle(triangle, remaining[index], tolerance):
				found = index
				break
		_check(found >= 0, "FR28a split lost an original triangle")
		if found >= 0:
			remaining.remove_at(found)
	_check(remaining.size() == 2, "FR28a split should add only the two magazine cap triangles")
	for extra in remaining:
		for triangle in source_faces:
			_check(not _same_triangle(extra, triangle, tolerance), "FR28a split duplicated an original triangle")
	_check(body.mesh.surface_get_material(0).albedo_texture == magazine.mesh.surface_get_material(0).albedo_texture, "FR28a magazine does not share the original texture")
