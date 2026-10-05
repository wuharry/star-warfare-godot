extends Node

var failures: Array[String] = []
var check_count := 0
var bow_combat_samples := 0
var rifle_return_samples := 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
		push_error("WEAPON POSE TEST: " + message)

func _run() -> void:
	GameState.save_path = "user://equipment_weapon_pose_test.json"
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	# This isolated test must not inherit the real profile's equipped bag.
	GameState.equipped_armor.bag = "armor_bag_00"
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
	_check(is_instance_valid(player.left_gun_socket), "animated avatar has no recovered left-hand bow socket")
	if is_instance_valid(player.left_gun_socket):
		_check(player.left_gun_socket.bone_name == "l hand gun", "bow socket is not attached to the original l hand gun bone")
	_check(is_instance_valid(player.backpack_visual), "equipped Unity backpack was not attached")
	if is_instance_valid(player.backpack_visual) and player.backpack_visual.mesh:
		_check(
			"ArmorBag_00" in player.backpack_visual.mesh.resource_path,
			"player is still using the obsolete fallback backpack"
		)

	# Exercise the real runtime selector, not only the glTF's default flags.
	# This catches naming changes such as ArmorHead_20 that previously left the
	# starter mesh visible no matter what the player equipped.
	var original_armor: Dictionary = GameState.equipped_armor.duplicate(true)
	GameState.equipped_armor["head"] = "armor_head_20"
	GameState.equipped_armor["body"] = "armor_body_19"
	GameState.equipped_armor["arms"] = "armor_arms_18"
	GameState.equipped_armor["legs"] = "armor_legs_17"
	player._apply_recovered_armor_visibility()
	for expected_name in ["ArmorHead_20", "ArmorBody_19", "ArmorHand_18", "ArmorFoot_17"]:
		var expected_mesh := player.recovered_avatar.find_child(expected_name, true, false) as MeshInstance3D
		_check(expected_mesh != null and expected_mesh.visible, "%s was not selected at runtime" % expected_name)
	for hidden_name in ["ArmorHead_00", "ArmorBody_00", "ArmorHand_00", "ArmorFoot_00"]:
		var hidden_mesh := player.recovered_avatar.find_child(hidden_name, true, false) as MeshInstance3D
		_check(hidden_mesh != null and not hidden_mesh.visible, "%s remained visible after equipping another part" % hidden_name)
	GameState.equipped_armor = original_armor
	player._apply_recovered_armor_visibility()

	# AvatarBuilder uses each bag prefab's own Unity scale and omits the usual
	# 0.8 body multiplier only for body 05.
	GameState.equipped_armor["body"] = "armor_body_05"
	GameState.equipped_armor["bag"] = "armor_bag_14"
	player._refresh_recovered_backpack()
	_check(player.backpack_visual.basis.get_scale().is_equal_approx(Vector3.ONE * 1.2), "bag 14 lost its Unity scale on body 05")
	GameState.equipped_armor["body"] = "armor_body_00"
	player._refresh_recovered_backpack()
	_check(player.backpack_visual.basis.get_scale().is_equal_approx(Vector3.ONE * 0.96), "bag 14 default body multiplier is incorrect")
	GameState.equipped_armor = original_armor
	player._refresh_recovered_backpack()
	for bag_index in range(25):
		GameState.equipped_armor.bag = "armor_bag_%02d" % bag_index
		player._refresh_recovered_backpack()
		var bag := player.backpack_visual
		_check(bag != null and bag.mesh != null, "bag %d did not attach" % bag_index)
		if bag == null or bag.mesh == null:
			continue
		for surface in bag.mesh.get_surface_count():
			var material := bag.get_active_material(surface) as BaseMaterial3D
			var source := bag.mesh.surface_get_material(surface) as BaseMaterial3D
			_check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "bag %d surface %d still darkens indoors" % [bag_index, surface])
			_check(material != null and material.albedo_color.is_equal_approx(Color.WHITE), "bag %d surface %d retained the gray tint" % [bag_index, surface])
			_check(material != null and source != null and material.albedo_texture == source.albedo_texture, "bag %d surface %d lost its own texture" % [bag_index, surface])
	GameState.equipped_armor = original_armor
	player._refresh_recovered_backpack()

	# A smaller bag limits the live combat selector without deleting the saved
	# loadout, so re-equipping a larger pack restores the hidden slots.
	var original_loadout: Array[String] = GameState.battle_weapons.duplicate()
	GameState.battle_weapons.assign(["gun00", "gun01", "gun02", "gun03", "gun04", "gun05", "gun06", "gun07"])
	GameState.equipped_armor["bag"] = "armor_bag_00"
	player._refresh_weapon_order_for_bag()
	_check(player.weapon_order.size() == 3, "starter bag exposes more than its three combat weapon slots")
	_check(GameState.battle_weapons.size() == 8, "small bag destructively removed saved loadout slots")
	GameState.battle_weapons = original_loadout
	GameState.equipped_armor = original_armor
	player._refresh_weapon_order_for_bag()
	player._refresh_recovered_backpack()

	for weapon_index in range(47):
		var weapon_path := "res://assets/models/weapons/gun%02d.obj" % weapon_index
		_check(ResourceLoader.exists(weapon_path), "gun%02d has no recovered Unity mesh" % weapon_index)
		if ResourceLoader.exists(weapon_path):
			var weapon_mesh := load(weapon_path) as Mesh
			_check(weapon_mesh != null and weapon_mesh.get_surface_count() > 0, "gun%02d mesh did not import" % weapon_index)

	# The old weapon's flash timeout must not turn off a newly equipped gun's
	# light when the player switches during the 45 ms muzzle flash.
	player.equip_weapon("gun00", false)
	player.energy = player.max_energy
	player.shot_cooldown = 0.0
	player._try_fire()
	player.equip_weapon("gun06", false)
	var replacement_muzzle_light := player.muzzle_light
	replacement_muzzle_light.light_energy = 7.0
	await get_tree().create_timer(0.06).timeout
	_check(is_equal_approx(replacement_muzzle_light.light_energy, 7.0), "old muzzle-flash timeout modified the newly equipped weapon")

	var pose_weapons := ["gun00", "gun06", "gun11", "gun22", "gun23", "gun24", "gun25", "gun27", "gun28", "gun29", "gun33", "gun34", "gun36", "gun37", "gun39", "gun44"]
	for weapon_id in pose_weapons:
		player.equip_weapon(weapon_id, false)
		var weapon_index := int(weapon_id.trim_prefix("gun"))
		var expected_socket: Node = player.left_gun_socket if weapon_index in [22, 29, 44] else player.gun_socket
		_check(player.gun_mount.get_parent() == expected_socket, "%s uses the wrong Unity hand socket" % weapon_id)
		_check(player.gun_mount.get_node_or_null("WeaponVisual") != null, "%s has no recovered weapon visual" % weapon_id)
		player.shot_cooldown = 0.0
		player.shoot_pose_left = 0.0
		# Let the real 80 ms weapon-switch animation blend finish before
		# measuring the destination pose's bow plane and barrel direction.
		for _frame in range(8):
			await get_tree().process_frame
			await get_tree().physics_frame
		_assert_special_weapon_materials(player, weapon_id)
		var idle_direction := -player.gun_mount.global_transform.basis.z.normalized()
		var character_forward := -player.model.global_transform.basis.z.normalized()
		var idle_dot := idle_direction.dot(character_forward)
		if str(player.current_weapon.kind) != "sword":
			_check(idle_dot > 0.45, "%s idle weapon points away from character aim (dot %.3f)" % [weapon_id, idle_dot])
		_assert_special_weapon_geometry(player, weapon_id)

		player._try_fire()
		if str(player.current_weapon.animation) in ["jian", "bow", "fist"]:
			_check(player.gun_mount.position.is_equal_approx(player.gun_mount_rest_position), "%s still uses firearm kickback" % weapon_id)
			_check(is_zero_approx(player.muzzle_light.light_energy), "%s still flashes like a firearm" % weapon_id)
		await get_tree().process_frame
		await get_tree().physics_frame
		var fire_direction := -player.gun_mount.global_transform.basis.z.normalized()
		var fire_dot := fire_direction.dot(character_forward)
		if str(player.current_weapon.kind) != "sword":
			_check(fire_dot > 0.55, "%s firing weapon points away from character aim (dot %.3f)" % [weapon_id, fire_dot])
		_check("shoot" in player.recovered_animation_name.to_lower(), "%s did not enter its recovered firing animation" % weapon_id)
		print("WEAPON_POSE %s idle_dot=%.3f fire_dot=%.3f animation=%s" % [weapon_id, idle_dot, fire_dot, player.recovered_animation_name])

	world.completed = true
	await _assert_bow_combat_poses(player)
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("WEAPON_POSE_TEST_PASS meshes=47 poses=%d sockets=both_hands bow_combat_samples=%d rifle_return_samples=%d checks=%d" % [pose_weapons.size(), bow_combat_samples, rifle_return_samples, check_count])
		get_tree().quit(0)
	else:
		print("WEAPON_POSE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _assert_bow_combat_poses(player: WarfarePlayer) -> void:
	# Freeze autonomous input/AI, but keep the imported clips, layer selector,
	# BoneAttachment3D updates and the real combat-aim/fire methods in use.
	player.set_physics_process(false)
	player.set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.set_process(false)
	var saved_skills: Dictionary = player.armor_skills.duplicate(true)
	var saved_aim_pressed := Input.is_action_pressed("aim")
	var saved_fire_pressed := Input.is_action_pressed("fire")
	Input.action_release("aim")
	Input.action_release("fire")
	player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# The catalog loop leaves enemy colliders near the player. Direction-only
	# samples need an unobstructed camera ray, not a target inside the bow.
	player.global_position += Vector3.UP * 1000.0
	await get_tree().physics_frame
	await get_tree().process_frame
	player.hurt_pose_left = 0.0
	player.velocity = Vector3.ZERO
	player.body_yaw = 0.0
	player.model.rotation.y = 0.0
	player.camera_yaw = 0.0
	player.camera_rig.rotation.y = 0.0
	var phases: Array[float] = [0.0, 0.35, 0.75]
	var pitches: Array[float] = [0.0, -25.0, 25.0]
	for weapon_id: String in ["gun22", "gun29", "gun44"]:
		for movement: String in ["standing", "running", "flying"]:
			for pitch: float in pitches:
				player.camera_pitch = deg_to_rad(pitch)
				player.pitch_node.rotation.x = player.camera_pitch
				var rifle_reference: Array[Basis] = []
				player.equip_weapon("gun00", false)
				for phase: float in phases:
					await _sample_combat_pose(player, movement, phase, false)
					var reference_mesh := player.gun_mount.get_node("WeaponVisual/Recovered_gun00") as MeshInstance3D
					rifle_reference.append(reference_mesh.global_basis.orthonormalized())
					_assert_rifle_aim(player, "%s before %s pitch=%.1f phase=%.2f" % [weapon_id, movement, pitch, phase])
				player.equip_weapon(weapon_id, false)
				for firing: bool in [false, true]:
					for phase: float in phases:
						var context := "%s %s pitch=%.1f phase=%.2f %s" % [weapon_id, movement, pitch, phase, "fire" if firing else "aim_only"]
						await _sample_combat_pose(player, movement, phase, firing)
						_check(player.is_combat_aim_active(), context + " did not activate actual combat aim")
						_check(player.is_focus_aiming() == (not firing), context + " used the wrong aim/fire input fixture")
						_check(player.gun_mount.get_parent() == player.left_gun_socket, context + " lost the left-hand socket")
						_assert_special_weapon_geometry(player, weapon_id, context)
						var mesh := player.gun_mount.get_node("WeaponVisual/Recovered_" + weapon_id) as MeshInstance3D
						var arrow_axis := -mesh.global_basis.z.normalized()
						var aim := player.get_aim_solution(float(player.current_weapon.range))
						var muzzle_aim := (Vector3(aim.target) - player.muzzle.global_position).normalized()
						var muzzle_dot := arrow_axis.dot(muzzle_aim)
						var target_distance := player.muzzle.global_position.distance_to(Vector3(aim.target))
						_check(arrow_axis.dot(-player.muzzle.global_basis.z.normalized()) > 0.99, context + " arrow axis diverges from the muzzle marker")
						_check(muzzle_dot > 0.99, "%s arrow axis diverges from the actual muzzle-to-target ray (dot %.6f, target distance %.3f)" % [context, muzzle_dot, target_distance])
						_check(player.gun_mount.position.is_equal_approx(player.gun_mount_rest_position), context + " introduced firearm recoil at the grip")
						_check(is_zero_approx(player.muzzle_light.light_energy), context + " introduced a firearm muzzle flash")
						_check((player.shoot_pose_left > 0.0) == firing, context + " did not preserve the requested firing state")
						bow_combat_samples += 1
				player.equip_weapon("gun00", false)
				for phase_index: int in phases.size():
					var phase := phases[phase_index]
					var context := "gun00 after %s %s pitch=%.1f phase=%.2f" % [weapon_id, movement, pitch, phase]
					await _sample_combat_pose(player, movement, phase, false)
					_assert_rifle_aim(player, context)
					var mesh := player.gun_mount.get_node("WeaponVisual/Recovered_gun00") as MeshInstance3D
					var reference := rifle_reference[phase_index]
					var up_dot := mesh.global_basis.y.normalized().dot(reference.y)
					_check(up_dot > 0.99, "%s retained the bow roll instead of the original rifle orientation (up dot %.6f, right-hand socket basis %s)" % [context, up_dot, player.gun_socket.global_basis])
					rifle_return_samples += 1
	_check(bow_combat_samples == 162, "bow combat matrix did not cover all 162 samples")
	_check(rifle_return_samples == 81, "rifle return matrix did not cover all 81 samples")
	player.armor_skills = saved_skills
	player.touch_aim = false
	player.touch_fire = false
	if saved_aim_pressed:
		Input.action_press("aim")
	if saved_fire_pressed:
		Input.action_press("fire")
	print("BOW_COMBAT_POSE_MATRIX samples=%d rifle_returns=%d clips=standing/running/flying phases=0/0.35/0.75 camera_pitch=0/-25/+25 aim_only_and_fire=true" % [bow_combat_samples, rifle_return_samples])

func _sample_combat_pose(player: WarfarePlayer, movement: String, phase: float, firing: bool) -> void:
	var moving := movement != "standing"
	var flying := movement == "flying"
	player.armor_skills["fly"] = 1.0 if flying else 0.0
	player._cancel_reload(false)
	player.energy = player.max_energy
	player.shot_cooldown = 0.0
	player.shoot_pose_left = 0.0
	player.restart_shoot_animation_requested = false
	player.touch_aim = not firing
	player.touch_fire = firing
	player.recovered_animation_tree.active = false
	player.recovered_animation_player.stop()
	player.recovered_animation_name = ""
	player.recovered_skeleton.clear_bones_global_pose_override()
	player.upper_body_aim_override_active = false
	# Live physics resolves aim, then firing, then the recovered animation.
	player._update_body_facing(1.0 / 60.0, Vector3.FORWARD if moving else Vector3.ZERO)
	player._update_combat_aim_pose(1.0 / 60.0)
	if firing:
		player._try_fire()
	player._update_recovered_animation(1.0 if moving else 0.0, Vector2(0.0, -1.0) if moving else Vector2.ZERO)
	var pose := str(player.current_weapon.animation)
	var expected_clip := ("run_" if moving else "idle_") + pose
	if firing:
		expected_clip = ("run_shoot_" if moving else "stand_shoot_") + pose
	if flying and not firing:
		expected_clip = "fly_" + pose
	_check(player.recovered_animation_name == expected_clip, "%s %s %s selected %s instead of original %s" % [player.current_weapon_id, movement, "fire" if firing else "aim_only", player.recovered_animation_name, expected_clip])
	_check(player.recovered_animation_tree.active == (flying or (moving and firing)), "%s %s lost its original animation layering" % [player.current_weapon_id, movement])
	var clip := player.recovered_animation_player.get_animation(expected_clip)
	_check(clip != null and clip.length > 0.0, "missing original animation " + expected_clip)
	if clip == null or clip.length <= 0.0:
		return
	var rate := player._shoot_animation_rate(expected_clip) if firing else 1.0
	if player.recovered_animation_tree.active:
		player.recovered_animation_tree.advance(0.0)
		player.recovered_animation_tree.advance(clip.length * phase / rate)
	else:
		player.recovered_animation_player.advance(0.0)
		player.recovered_animation_player.seek(clip.length * phase, true)
	player.recovered_skeleton.force_update_all_bone_transforms()
	# Allow the real BoneAttachment3D nodes to consume this clip phase before
	# the next frame's combat-aim update; never repair their transforms here.
	await get_tree().process_frame
	player._update_combat_aim_pose(1.0 / 60.0)
	# Measure at the same point where _try_fire consumes the resolved muzzle.
	# Another process/physics frame would change the camera or parent pose
	# before the next aim update, mixing measurements from two frames.

func _assert_rifle_aim(player: WarfarePlayer, context: String) -> void:
	_check(player.gun_mount.get_parent() == player.gun_socket, context + " did not return to the right-hand socket")
	var mesh := player.gun_mount.get_node("WeaponVisual/Recovered_gun00") as MeshInstance3D
	var barrel := -mesh.global_basis.z.normalized()
	var aim := player.get_aim_solution(float(player.current_weapon.range))
	var expected_direction := (Vector3(aim.target) - player.muzzle.global_position).normalized()
	_check(barrel.dot(-player.gun_mount.global_basis.z.normalized()) > 0.99, context + " barrel diverges from its aiming pivot")
	var target_dot := barrel.dot(expected_direction)
	var target_distance := player.muzzle.global_position.distance_to(Vector3(aim.target))
	_check(target_dot > 0.99, "%s barrel diverges from its actual muzzle-to-target ray (dot %.6f, target distance %.3f)" % [context, target_dot, target_distance])
	var expected_up := (Vector3.UP - barrel * Vector3.UP.dot(barrel)).normalized()
	var up_dot := mesh.global_basis.y.normalized().dot(expected_up)
	_check(up_dot > 0.99, "%s inherited a horizontal bow roll (up dot %.6f, right-hand socket basis %s)" % [context, up_dot, player.gun_socket.global_basis])

func _assert_special_weapon_geometry(player: WarfarePlayer, weapon_id: String, context := "") -> void:
	var mesh := player.gun_mount.get_node("WeaponVisual/Recovered_" + weapon_id) as MeshInstance3D
	var bounds := preload("res://scripts/core/equipment_refinement.gd").authored_bounds(mesh.mesh)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * mesh.scale.x
	if weapon_id in ["gun24", "gun25", "gun39"]:
		var barrel := -mesh.global_basis.z.normalized()
		var aim := -player.gun_mount.global_basis.z.normalized()
		_check(barrel.dot(aim) > 0.99, "%s barrel and aiming marker diverge" % weapon_id)
		var muzzle_local := mesh.to_local(player.muzzle.global_position)
		_check(is_equal_approx(muzzle_local.z, bounds.position.z), "%s fires from its stock instead of its barrel" % weapon_id)
	if weapon_id in ["gun22", "gun29", "gun44"]:
		var label := weapon_id if context.is_empty() else context
		var limb_up_dot := absf(mesh.global_basis.y.normalized().dot(Vector3.UP))
		_check(limb_up_dot < 0.3, "%s bow lost its horizontal hold (world-UP dot %.3f)" % [label, limb_up_dot])
		_check((-mesh.global_basis.z.normalized()).dot(-player.gun_mount.global_basis.z.normalized()) > 0.99, "%s bow arrow axis diverges from the aiming marker" % label)
		var grip := mesh.to_global(Vector3(bounds.get_center().x, 0, 0))
		_check(grip.distance_to(player.gun_mount.global_position) < 0.01, "%s grip floats away from the left hand" % label)
		_check(longest <= 1.46, "%s still uses a rifle size" % label)
	if weapon_id in ["gun23", "gun36"]:
		_check(longest <= 0.49, "%s fist weapon is longer than the forearm" % weapon_id)
		var wrist := mesh.to_global(Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z - 0.08))
		_check(wrist.distance_to(player.gun_mount.global_position) < 0.01, "%s cuff is detached from the hand" % weapon_id)
	var sheath := player.recovered_avatar.find_child("WeaponScabbard", true, false)
	_check(sheath == null, "%s retained the removed procedural scabbard" % weapon_id)

func _assert_special_weapon_materials(player: WarfarePlayer, weapon_id: String) -> void:
	var cases := {
		"gun22": {"effects": [1, 2], "solid": 0, "blend": BaseMaterial3D.BLEND_MODE_MIX},
		"gun23": {"effects": [0, 1], "solid": 2, "blend": BaseMaterial3D.BLEND_MODE_ADD},
		"gun37": {"effects": [1, 2], "solid": 0, "blend": BaseMaterial3D.BLEND_MODE_ADD},
	}
	if not cases.has(weapon_id):
		return
	var visual_root := player.gun_mount.get_node_or_null("WeaponVisual")
	var recovered: MeshInstance3D = null
	if visual_root != null:
		recovered = visual_root.find_child("Recovered_*", true, false) as MeshInstance3D
	_check(recovered != null, "%s has no recovered mesh for material validation" % weapon_id)
	if recovered == null:
		return
	var material_case: Dictionary = cases[weapon_id]
	for surface_index: int in material_case.effects:
		var effect := recovered.get_surface_override_material(surface_index) as BaseMaterial3D
		_check(effect != null and effect.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "%s effect surface %d lacks alpha blending" % [weapon_id, surface_index])
		_check(effect != null and effect.blend_mode == int(material_case.blend), "%s effect surface %d uses the wrong blend mode" % [weapon_id, surface_index])
	var solid := recovered.get_surface_override_material(int(material_case.solid)) as BaseMaterial3D
	_check(solid != null and solid.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "%s solid surface became transparent" % weapon_id)
	_check(solid != null and solid.albedo_color.r > 0.99 and solid.albedo_color.g > 0.99 and solid.albedo_color.b > 0.99, "%s solid surface retained the imported black tint" % weapon_id)
