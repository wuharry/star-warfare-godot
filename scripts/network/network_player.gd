extends "res://scripts/game/player.gd"
## Each process owns visuals. Only the host simulates combat and remote input.
## Input prediction never grants health, ammunition, score or objective ownership.

var peer_id := 0
var profile: Dictionary = {}
var local_control := false
var network_world: Node3D
var command := {"move": Vector2.ZERO, "aim": Vector2.ZERO, "buttons": 0, "slot": 0}
var input_sequence := 0
var desired_slot := 0
var last_buttons := 0
var invulnerable_left := 2.0
var name_tag: Label3D
var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var has_snapshot := false
var automation_command: Dictionary = {}
var personal_team_skills: Dictionary = {}
var damage_category_stack: Array[String] = []

func get_damage_category() -> String:
	return damage_category_stack.back() if not damage_category_stack.is_empty() else super.get_damage_category()

func network_damage_category_for_kind(weapon_kind: String) -> String:
	return _weapon_skill_key_for_kind(weapon_kind).trim_suffix("_boost") + "_defence"

func _weapon_skill_key() -> String:
	# Spring.cs reports TrackingGun, including its armor bonus.
	return "tracking_boost" if str(current_weapon.get("kind", "")) == "spring" else super._weapon_skill_key()

func _ready() -> void:
	name = "Peer_%d" % peer_id
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.6
	_apply_armor_stats(true)
	_build_collision()
	_build_visual()
	_build_camera()
	camera.current = local_control
	_build_audio()
	weapon_order.assign(profile.get("weapons", ["gun00"]))
	equip_weapon(weapon_order[0], false)
	name_tag = Label3D.new()
	name_tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_tag.text = str(profile.get("name", "PLAYER"))
	name_tag.position.y = 2.7
	name_tag.font_size = 34
	name_tag.pixel_size = 0.008
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.visible = not local_control
	name_tag.modulate = Color.CYAN if int(profile.get("team", 0)) == 0 else Color.ORANGE_RED
	add_child(name_tag)
	if local_control:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("mobile") else Input.MOUSE_MODE_CAPTURED

func _equipped_key(part: String) -> String:
	return str(profile.get("outfit", {}).get(part, GameState.ArmorCatalogData.item_key(GameState.ArmorCatalogData.PART_KEYS.find(part), 0)))

func _armor_item(key: String) -> Dictionary:
	var item: Dictionary = GameState.ARMOR_ITEMS.get(key, {}).duplicate(true)
	if item.get("source_game", "") == "com":
		var level := int(profile.get("armor_levels", {}).get(str(item.set_id), 1))
		var multiplier := GameState.UpgradeRules.armor_multiplier(int(item.set_id), level)
		item.skills.hp *= multiplier
		item.skills.shield *= multiplier
	return item

func _apply_armor_stats(restore_full := false) -> void:
	# Every actor uses the host-validated profile, including that peer's upgrades.
	armor_skills = GameState.ArmorCatalogData.empty_skills()
	for part: String in GameState.ArmorCatalogData.PART_KEYS:
		GameState.ArmorCatalogData.merge_skills(armor_skills, _armor_item(_equipped_key(part)).get("skills", {}))
	var set_id := GameState._armor_set_id_for(profile.get("outfit", {}))
	if GameState.ARMOR_SET_BONUSES.has(set_id):
		GameState.ArmorCatalogData.merge_skills(armor_skills, GameState.ARMOR_SET_BONUSES[set_id].skills)
	max_health = maxf(1.0, float(armor_skills.get("hp", 0.0)))
	if not MatchRules.is_coop(NetworkSession.room.mode):
		max_health = MatchRules.vs_health(max_health)
		for skill: String in ["hp_auto_recovery", "team_hp_recovery"]:
			armor_skills[skill] = float(armor_skills.get(skill, 0.0)) / 8.0
		armor_skills["hp_on_kill"] = float(armor_skills.get("hp_on_kill", 0.0)) * 4.0
	max_shield = maxf(0.0, float(armor_skills.get("shield", 100.0)))
	var source_set: Dictionary = GameState.ArmorCatalogData.CoMSource.ARMOR_SETS.get(str(set_id), {})
	if not source_set.is_empty():
		source_shield_profile = {"delay": float(source_set.shield_delay), "fraction": float(source_set.shield_recovery_fraction)}
		source_shield_delay_left = float(source_shield_profile.delay)
	for key: String in ["team_hp_recovery", "team_attack_boost", "team_damage_reduce"]:
		personal_team_skills[key] = float(armor_skills.get(key, 0.0))
	move_speed = maxf(3.5, 8.2 + float(armor_skills.get("speed_boost", 0.0)))
	if restore_full:
		health = max_health
		shield = max_shield

func equip_weapon(weapon_id: String, _persist_selection := true) -> void:
	super.equip_weapon(weapon_id, false)
	current_weapon = GameState.WEAPONS.get(weapon_id, {}).duplicate(true)
	current_weapon.damage *= GameState.UpgradeRules.weapon_multiplier(int(profile.get("weapon_levels", {}).get(weapon_id, 1)))
	if not MatchRules.is_coop(NetworkSession.room.mode):
		if int(current_weapon.get("type", 0)) in [1, 23]:
			current_weapon.cooldown *= 0.75
		elif int(current_weapon.get("type", 0)) == 5:
			current_weapon.cooldown *= 0.65

func restore(kind: String, amount: float) -> void:
	if not NetworkSession.is_host():
		return
	if kind == "health" and not MatchRules.is_coop(NetworkSession.room.mode):
		amount /= 12.0
	super.restore(kind, amount)

func _update_armor_effects(delta: float) -> void:
	# GameWorld.CreateTeamSkills combines the strongest living allied aura.
	# Free-for-all only receives the wearer's own aura.
	for key: String in personal_team_skills:
		var combined := float(personal_team_skills[key])
		for other: Node in network_world.actors.values():
			if other == self or other.dead: continue
			if not MatchRules.is_coop(NetworkSession.room.mode):
				if not MatchRules.is_team(NetworkSession.room.mode) or other.profile.team != profile.team: continue
			var bonus := float(other.personal_team_skills.get(key, 0.0))
			combined = minf(combined, bonus) if key == "team_damage_reduce" else maxf(combined, bonus)
		armor_skills[key] = combined
	super._update_armor_effects(delta)

func cycle_weapon(direction: int) -> void:
	desired_slot = posmod(desired_slot + direction, weapon_order.size())

func _unhandled_input(event: InputEvent) -> void:
	if local_control and NetworkSession.phase == "playing":
		super._unhandled_input(event)

func is_fire_input_active() -> bool:
	return (int(command.buttons) & 1) != 0

func is_combat_aim_active() -> bool:
	return is_fire_input_active() or (local_control and Input.is_action_pressed("aim"))

func _physics_process(delta: float) -> void:
	if NetworkSession.phase != "playing":
		return
	if local_control:
		_collect_input(delta)
	if NetworkSession.is_host():
		if not NetworkSession.command_is_current(peer_id):
			command.move = Vector2.ZERO
			command.buttons = 0
		_simulate(delta, true)
	elif local_control:
		_simulate(delta, false)
		if has_snapshot:
			var difference := target_position - position
			if difference.length() > 4.0:
				position = target_position
			else:
				position += difference * minf(1.0, delta * 9.0)
			target_position += target_velocity * delta
	else:
		if has_snapshot:
			position = position.lerp(target_position, minf(1.0, delta * 18.0))
			velocity = target_velocity
		if enemy_knockback_left > 0.0:
			enemy_knockback_left = maxf(0.0, enemy_knockback_left - delta)
			_play_recovered_animation(enemy_knockback_animation)
		else:
			_update_visual_animation(delta, clampf(Vector2(velocity.x, velocity.z).length() / move_speed, 0.0, 1.0))

func _collect_input(delta: float) -> void:
	_update_camera_controller(delta)
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length_squared() > move.length_squared():
		move = touch_move
	var buttons := 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("fire") or touch_fire:
		buttons |= 1
	if Input.is_action_pressed("reload") or touch_reload_requested:
		buttons |= 2
	if Input.is_action_pressed("dash") or touch_dash_requested:
		buttons |= 4
	for slot in range(mini(4, weapon_order.size())):
		if Input.is_action_just_pressed("weapon_%d" % (slot + 1)):
			desired_slot = slot
	command = {"move": move, "aim": Vector2(camera_yaw, camera_pitch), "buttons": buttons, "slot": desired_slot}
	if not automation_command.is_empty():
		command = automation_command.duplicate()
	input_sequence += 1
	NetworkSession.submit_command(input_sequence, command.move, command.aim, command.buttons, command.slot)
	touch_reload_requested = false
	touch_dash_requested = false

func _simulate(delta: float, authoritative: bool) -> void:
	if dead:
		return
	if _advance_enemy_knockback(delta):
		return
	invulnerable_left = maxf(0.0, invulnerable_left - delta)
	var buttons := int(command.buttons)
	if not local_control:
		camera_yaw = command.aim.x
		camera_pitch = command.aim.y
	camera_rig.rotation.y = camera_yaw
	pitch_node.rotation.x = camera_pitch
	var input: Vector2 = command.move
	var forward := Vector3(-sin(command.aim.x), 0.0, -cos(command.aim.x))
	var right := Vector3(cos(command.aim.x), 0.0, -sin(command.aim.x))
	var desired := right * input.x - forward * input.y
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	if (buttons & 4) != 0 and (last_buttons & 4) == 0 and dash_cooldown_left <= 0.0:
		dash_direction = desired.normalized() if desired.length_squared() > 0.01 else forward
		dash_time = dash_duration
		dash_cooldown_left = dash_cooldown
	dash_time = maxf(0.0, dash_time - delta)
	var power_speed := float(armor_power_controller.get_speed_bonus()) if is_instance_valid(armor_power_controller) else 0.0
	var item_speed := battle_items.get_bonus("speed_boost") if is_instance_valid(battle_items) else 0.0
	var speed := maxf(3.5, move_speed + float(current_weapon.get("speed_drag", 0.0)) + power_speed + item_speed + (float(armor_skills.get("speed_on_hit", 0.0)) if speed_on_hit_left > 0.0 else 0.0))
	speed *= maxf(0.0, float(current_weapon.get("move_speed_multiplier", 1.0))) * float(get_meta("enemy_move_multiplier", 1.0))
	var motion := dash_direction * dash_speed if dash_time > 0.0 else desired * speed
	velocity.x = motion.x
	velocity.z = motion.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	_update_body_facing(delta, desired)
	shoot_pose_left = maxf(0.0, shoot_pose_left - delta)
	hurt_pose_left = maxf(0.0, hurt_pose_left - delta)
	if authoritative:
		shot_cooldown = maxf(0.0, shot_cooldown - delta)
		_update_reload(delta)
		_update_armor_effects(delta)
		var next_weapon := str(weapon_order[int(command.slot)])
		if next_weapon != current_weapon_id:
			equip_weapon(next_weapon, false)
		if (buttons & 2) != 0:
			_start_reload()
		if auto_reload_left >= 0.0:
			auto_reload_left -= delta
			if auto_reload_left <= 0.0:
				auto_reload_left = -1.0
				_start_reload()
		if (buttons & 1) != 0 and (bool(current_weapon.get("automatic", false)) or (last_buttons & 1) == 0):
			_try_fire()
		else:
			_stop_continuous_weapon_audio()
		if position.y < -100.0:
			_die()
	last_buttons = buttons
	_update_visual_animation(delta, clampf(Vector2(velocity.x, velocity.z).length() / move_speed, 0.0, 1.0), input)
	_update_combat_aim_pose(delta)
	_update_reload_pose()

func get_aim_solution(maximum_range := 180.0) -> Dictionary:
	var yaw := float(command.aim.x)
	var pitch := float(command.aim.y)
	var direction := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)).normalized()
	var origin := global_position + Vector3.UP * 1.65
	# Local camera gives the shoulder-reticle target; server derives it from aim,
	# then traces from the body so a camera around a corner cannot shoot through it.
	var camera_origin := origin + Vector3(cos(yaw), 0.0, -sin(yaw)) * 0.6 - direction * 2.2
	var query := PhysicsRayQueryParameters3D.create(camera_origin, camera_origin + direction * maximum_range, 7)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit.get("position", camera_origin + direction * maximum_range)
	return {"origin": origin, "direction": (target - origin).normalized(), "target": target,
		"collider": hit.get("collider")}

func _fire_hitscan() -> void:
	if NetworkSession.is_host():
		network_world.fire_weapon(self, "hitscan")

func _fire_projectile(kind: String) -> void:
	if NetworkSession.is_host():
		network_world.fire_weapon(self, kind)

func _fire_melee() -> void:
	if NetworkSession.is_host():
		network_world.fire_weapon(self, "sword")

func take_damage(amount: float, hit_position := Vector3.ZERO, source: Node = null) -> void:
	if not NetworkSession.is_host() or NetworkSession.phase != "playing" or network_world.rules.ended or dead or invulnerable_left > 0.0:
		return
	if source != null and "peer_id" in source and not network_world.rules.can_damage(int(source.peer_id), peer_id):
		return
	super.take_damage(amount, hit_position, source)

func _die(killer: Node = null) -> void:
	if dead or not NetworkSession.is_host():
		return
	dead = true
	enemy_knockback_left = 0.0
	enemy_knockback_velocity = Vector3.ZERO
	if is_instance_valid(armor_power_controller): armor_power_controller.cancel_all_active(false)
	_cancel_reload()
	_stop_continuous_weapon_audio()
	collision_layer = 0
	if recovered_animation_player and recovered_animation_player.has_animation("dead"):
		_play_recovered_animation("dead", 0.05, true)
	var killer_id := int(killer.peer_id) if killer != null and "peer_id" in killer else 0
	network_world.player_died(peer_id, killer_id)
	if killer_id != 0 and killer_id != peer_id:
		killer.on_enemy_defeated()
	died.emit()

func revive(health_ratio: float = 1.0) -> bool:
	if not NetworkSession.is_host() or NetworkSession.phase != "playing" or not network_world.rules.can_revive(peer_id):
		return false
	var old_mouse := Input.mouse_mode
	if not super.revive(health_ratio): return false
	if not local_control: Input.mouse_mode = old_mouse
	collision_layer = 4
	invulnerable_left = 2.0
	network_world.rules.complete_revival(peer_id)
	return true

func network_respawn(at: Vector3) -> void:
	dead = false
	enemy_knockback_left = 0.0
	enemy_knockback_velocity = Vector3.ZERO
	position = at
	target_position = at
	velocity = Vector3.ZERO
	health = max_health
	shield = max_shield
	energy = max_energy
	weapon_magazines.clear()
	_ensure_magazine_state()
	_cancel_reload()
	invulnerable_left = 2.0
	collision_layer = 4
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE
	recovered_animation_name = ""
	health_changed.emit(health, shield)

func network_state() -> Dictionary:
	return {"position": position, "velocity": velocity, "yaw": model.rotation.y,
		"aim": command.aim, "health": health, "shield": shield, "dead": dead,
		"weapon": current_weapon_id, "ammo": _magazine_rounds(), "energy": energy,
		"reload": reload_left, "reload_total": reload_total, "reload_elapsed": reload_elapsed,
		"shoot": shoot_pose_left, "invulnerable": invulnerable_left,
		"knockback_left": enemy_knockback_left, "knockback_velocity": enemy_knockback_velocity,
		"knockback_animation": enemy_knockback_animation}

func apply_network_state(state: Dictionary) -> void:
	target_position = state.position
	target_velocity = state.velocity
	if not has_snapshot or dead != bool(state.dead):
		position = target_position
	has_snapshot = true
	health = state.health
	shield = state.shield
	dead = state.dead
	collision_layer = 0 if dead else 4
	if current_weapon_id != str(state.weapon):
		equip_weapon(state.weapon, false)
	_set_magazine_rounds(int(state.ammo))
	energy = int(state.energy)
	if float(state.get("knockback_left", 0.0)) > 0.0:
		# Cancel prediction before replacing reload fields: _cancel_reload needs
		# the old local state to release its pose, prop and audio. Preserve the
		# host's knockback timer/direction rather than starting a new impact.
		_cancel_reload()
		_stop_continuous_weapon_audio()
		dash_time = 0.0
		touch_dash_requested = false
		restart_shoot_animation_requested = false
	reload_left = state.reload
	reload_total = state.reload_total
	reload_elapsed = state.reload_elapsed
	shoot_pose_left = state.shoot
	invulnerable_left = state.invulnerable
	enemy_knockback_left = float(state.get("knockback_left", 0.0))
	enemy_knockback_velocity = state.get("knockback_velocity", Vector3.ZERO)
	enemy_knockback_animation = str(state.get("knockback_animation", "attacked"))
	if not local_control:
		model.rotation.y = state.yaw
		command.aim = state.aim
	if dead:
		_play_recovered_animation("dead", 0.1)
	_emit_ammo()
	health_changed.emit(health, shield)


func _apply_recovered_armor_visibility() -> void:
	if not is_instance_valid(recovered_avatar):
		return
	var equipped_ids := {
		"head": int(_armor_item(_equipped_key("head")).get("visual_id", 0)),
		"body": int(_armor_item(_equipped_key("body")).get("visual_id", 0)),
		"hand": int(_armor_item(_equipped_key("arms")).get("visual_id", 0)),
		"foot": int(_armor_item(_equipped_key("legs")).get("visual_id", 0))
	}
	preload("res://scripts/game/armor_visuals.gd").ensure_parts(recovered_avatar, equipped_ids)
	for candidate in recovered_avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		var lower_name := mesh_instance.name.to_lower()
		var part_name := ""
		for possible_part in equipped_ids:
			if (
				lower_name.begins_with("armor%s_" % possible_part)
				or lower_name.ends_with("_%s" % possible_part)
				or lower_name.begins_with("%s_" % possible_part)
			):
				part_name = possible_part
				break
		if part_name.is_empty():
			continue
		var visual_id := _armor_visual_id_from_name(lower_name)
		if visual_id >= 0:
			mesh_instance.visible = visual_id == int(equipped_ids[part_name])



func _add_recovered_backpack() -> void:
	var bag_key := _equipped_key("bag")
	var bag_id := int(_armor_item(bag_key).get("visual_id", 0))
	var backpack_path := "res://assets/models/player/animated/bags/ArmorBag_%02d/ArmorBag_%02d.obj" % [bag_id, bag_id]
	if not ResourceLoader.exists(backpack_path):
		backpack_path = "res://assets/models/player/animated/bag_%02d.obj" % bag_id
	if not ResourceLoader.exists(backpack_path):
		backpack_path = "res://assets/models/player/animated/bag.obj"
	if not ResourceLoader.exists(backpack_path) or not recovered_skeleton:
		return
	var fly_bag_bone := recovered_skeleton.find_bone("fly_bag")
	if fly_bag_bone < 0:
		return
	backpack_socket = BoneAttachment3D.new()
	backpack_socket.name = "RecoveredBackpackSocket"
	backpack_socket.bone_name = "fly_bag"
	recovered_skeleton.add_child(backpack_socket)

	backpack_visual = MeshInstance3D.new()
	backpack_visual.name = "RecoveredBackpack"
	backpack_visual.mesh = load(backpack_path)
	preload("res://scripts/game/armor_visuals.gd").restore_starter_backpack(backpack_visual, bag_id)
	# AvatarBuilder placed the independent Bag prefab at fly_bag in world space
	# before parenting it. Its prefab root rotation is already baked into the
	# recovered OBJ, so cancel the socket's rest basis instead of applying the
	# unrelated embedded Player.prefab Bag rotation a second time.
	var fly_bag_rest := recovered_skeleton.get_bone_global_rest(fly_bag_bone)
	var body_key := _equipped_key("body")
	var body_id := int(_armor_item(body_key).get("visual_id", 0))
	var unity_scale := float({14: 1.2, 15: 1.2, 16: 1.2, 17: 1.2, 18: 1.1, 19: 1.2, 20: 1.2}.get(bag_id, 1.0))
	var authored_scale := unity_scale if body_id == 5 else unity_scale * 0.8
	backpack_visual.transform = Transform3D(
		fly_bag_rest.basis.inverse() * Basis.from_scale(Vector3.ONE * authored_scale),
		Vector3.ZERO
	)
	backpack_socket.add_child(backpack_visual)
	if bag_id == 0 and "--armor-style=cartoon" in OS.get_cmdline_user_args():
		backpack_visual.mesh = load("res://assets/armors/cartoon_viper/backpack.res")
		backpack_visual.material_override = null
		# The new bag is authored in the same complete bind pose as the suit.
		backpack_visual.transform = fly_bag_rest.affine_inverse()
