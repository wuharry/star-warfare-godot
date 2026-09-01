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

	var pose_weapons := ["gun00", "gun06", "gun11", "gun22", "gun23", "gun24", "gun29", "gun34", "gun36", "gun37", "gun44"]
	for weapon_id in pose_weapons:
		player.equip_weapon(weapon_id, false)
		var weapon_index := int(weapon_id.trim_prefix("gun"))
		var expected_socket: Node = player.left_gun_socket if weapon_index in [22, 29, 44] else player.gun_socket
		_check(player.gun_mount.get_parent() == expected_socket, "%s uses the wrong Unity hand socket" % weapon_id)
		_check(player.gun_mount.get_node_or_null("WeaponVisual") != null, "%s has no recovered weapon visual" % weapon_id)
		player.shot_cooldown = 0.0
		player.shoot_pose_left = 0.0
		for _frame in range(3):
			await get_tree().process_frame
			await get_tree().physics_frame
		_assert_special_weapon_materials(player, weapon_id)
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
		print("WEAPON_POSE_TEST_PASS meshes=47 poses=%d sockets=both_hands" % pose_weapons.size())
		get_tree().quit(0)
	else:
		print("WEAPON_POSE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

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
