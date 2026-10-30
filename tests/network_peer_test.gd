extends Node
## Launch this scene in two OS processes, --role=host and --role=client.
## The input fixture traverses production ENet, movement, weapon ray, damage,
## respawn, score, final result and disconnect code. No bots are added to rooms.
const World = preload("res://scripts/game/network_world.gd")
var role := "host"
var mode := "VS_FFA"
var port := 24621
var world: Node3D
var elapsed := 0.0
var battle_time := 0.0
var saw_damage := false
var saw_movement := false
var saw_enemies := false
var saw_result := false
var final_wait := 0.0
var initial_position := Vector3.ZERO
var saw_disconnect := false
var done := false
var saw_objective := false
var credits_before := 0
var mithril_before := 0
var unlocked_before := 0
var boss_index := 0
var source_arena := false
var exercise_actions := false
var actions_seeded := false
var action_steps: Dictionary = {}
var heal_sequence := -1
var actions_verified := false
var capture_path := ""
var capture_started := false
var exercise_knockback := false
var sent_knockback := false
var saw_knockback := false
var knockback_prediction_seeded := false
var knockback_actions_canceled := false
var knockback_ended := false
var knockback_recovery_frames := 0
var knockback_recovery_verified := false

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--boss-index="): boss_index = int(arg.trim_prefix("--boss-index="))
		if arg == "--source-arena": source_arena = true
		if arg == "--actions": exercise_actions = true
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		if arg == "--knockback": exercise_knockback = true
	NetworkSession.auto_change_scene = false
	if exercise_knockback and role == "client":
		# Run before the world's production snapshot consumer, then inspect the
		# resulting actor after it. The packet itself remains untouched.
		NetworkSession.snapshot_received.connect(_seed_knockback_prediction)
	credits_before = GameState.credits
	mithril_before = GameState.mithril
	unlocked_before = GameState.unlocked_level
	NetworkSession.match_started.connect(_build_world)
	NetworkSession.lobby_changed.connect(_lobby_changed)
	NetworkSession.player_left.connect(func(_id): saw_disconnect = true)
	NetworkSession.session_closed.connect(func(reason):
		if not done and role == "client" and saw_result:
			_finish(true, reason)
	)
	var profile := {"name": role.to_upper(), "weapons": ["gun00"], "outfit": {
		"head": "armor_head_00", "body": "armor_body_00", "arms": "armor_arms_00", "legs": "armor_legs_00", "bag": "armor_bag_00"}}
	if exercise_actions:
		GameState.battle_weapons.assign(["gun00"])
		GameState.weapon_levels.gun00 = 3
		for part: String in ["head", "body", "arms", "legs"]:
			var key := GameState.ArmorCatalogData.item_key(GameState.ArmorCatalogData.PART_KEYS.find(part), 6)
			GameState.equipped_armor[part] = key
			if not GameState.owned_armor.has(key): GameState.owned_armor.append(key)
		GameState.equipped_armor.bag = "armor_bag_02"
		if not GameState.owned_armor.has("armor_bag_02"): GameState.owned_armor.append("armor_bag_02")
		GameState.owned_props = {"prop00": 3, "prop07": 3, "prop05": 3}
		GameState.package_slots.assign(["gun00", "prop00", "prop07", "prop05"])
		profile = NetworkSession.profile_from_local()
		profile.name = role.to_upper()
	var error := NetworkSession.host_room({"mode": mode, "level": 1 if mode in ["Survival", "Boss"] else 13, "boss_index": boss_index, "score_limit": 100}, port, profile) if role == "host" else NetworkSession.join_room("127.0.0.1", port, profile)
	if error != OK:
		_finish(false, "open failed %d" % error)

func _lobby_changed() -> void:
	if NetworkSession.phase != "lobby": return
	var id := NetworkSession.local_id()
	if NetworkSession.roster.has(id) and not NetworkSession.roster[id].ready:
		NetworkSession.set_ready(true, 0 if role == "host" else 1)
	if role == "host" and NetworkSession.roster.size() == 2 and NetworkSession.start_problem().is_empty():
		NetworkSession.start_match.call_deferred()

func _build_world() -> void:
	world = World.new()
	world.test_arena = not source_arena
	if exercise_knockback and role == "client":
		world.ready.connect(func(): NetworkSession.snapshot_received.connect(_check_knockback_snapshot))
	add_child.call_deferred(world)

func _process(delta: float) -> void:
	if done: return
	elapsed += delta
	if elapsed > 65.0:
		_finish(false, "timeout phase=%s damage=%s move=%s result=%s" % [NetworkSession.phase, saw_damage, saw_movement, saw_result])
		return
	if world == null or not world.is_node_ready() or world.player == null:
		return
	if NetworkSession.phase == "playing":
		battle_time += delta
		var actor = world.player
		if exercise_knockback:
			if role == "host" and battle_time > 1.0 and not sent_knockback:
				sent_knockback = true
				for unit: Node in world.actors.values(): unit.apply_enemy_knockback(0.2)
			for unit: Node in world.actors.values():
				saw_knockback = saw_knockback or unit.enemy_knockback_left > 0.0
			if role == "client" and knockback_ended and not knockback_recovery_verified:
				knockback_recovery_frames += 1
				if actor.dash_time > 0.0 or actor.touch_dash_requested:
					_finish(false, "canceled dash resumed after authoritative knockback ended")
					return
				if knockback_recovery_frames >= 3:
					if Vector2(actor.velocity.x, actor.velocity.z).length() > 0.01:
						_finish(false, "idle prediction surged after knockback ended")
						return
					knockback_recovery_verified = true
					print("NETWORK_KNOCKBACK_PASS role=client actualENet dash/touch/reload/fire canceled; idle recovery")
		if exercise_actions: _exercise_actions()
		if not capture_path.is_empty() and not capture_started and battle_time > 2.8:
			capture_started = true
			_capture.call_deferred()
		if initial_position == Vector3.ZERO:
			initial_position = actor.position
		if actor.position.distance_to(initial_position) > 0.3:
			saw_movement = true
		for unit: Node in world.actors.values():
			if unit.health < unit.max_health:
				saw_damage = true
		var target: Node3D
		for id: int in world.actors:
			if id != actor.peer_id:
				target = world.actors[id]
		if mode in ["Survival", "Boss"]:
			for enemy: Node in world.enemies.values():
				if is_instance_valid(enemy) and not enemy.dead:
					target = enemy
					saw_enemies = true
		if mode == "CMI" and role == "host":
			for gift: Node in world.gifts.values():
				if gift.respawn_left <= 0.0:
					target = gift
					break
		if mode == "CMI":
			for gift: Node in world.gifts.values():
				if gift.respawn_left > 0.0:
					saw_objective = true
		elif mode in ["CTF_FFA", "CTF_TDM"]:
			saw_objective = saw_objective or int(world.rules_view.get("flag_carrier", 0)) != 0
			if role == "host" and int(world.rules.flag_carrier) == 1:
				world.rules.flag_left = minf(world.rules.flag_left, 2.0)
		elif mode == "VIP":
			saw_objective = saw_objective or int(world.rules_view.get("vip_id", 0)) == 1
			if role == "host" and battle_time > 8.0:
				world.rules.vip_left = minf(world.rules.vip_left, 1.0)
		var aim := Vector2.ZERO
		if target != null:
			var yaw := float(actor.command.aim.x)
			var forward := Vector3(-sin(yaw), 0, -cos(yaw))
			var camera_at: Vector3 = actor.position + Vector3.UP * 1.65 + Vector3(cos(yaw), 0, -sin(yaw)) * 0.6 - forward * 2.2
			var offset: Vector3 = target.position + Vector3.UP - camera_at
			aim = Vector2(atan2(-offset.x, -offset.z), atan2(offset.y, Vector2(offset.x, offset.z).length()))
		var moving := battle_time < 0.7
		var buttons := 1 if battle_time > 3.0 and (role == "host" or battle_time < 4.0) else 0
		actor.automation_command = {"move": Vector2.RIGHT if moving else Vector2.ZERO, "aim": aim, "buttons": buttons, "slot": 0}
		if mode in ["CTF_FFA", "CTF_TDM"] and role == "host":
			var offset: Vector3 = world.rules.flag_position - actor.position
			offset.y = 0.0
			if offset.length() > 0.6 and world.rules.flag_carrier == 0:
				var right := Vector3(cos(aim.x), 0, -sin(aim.x))
				var forward := Vector3(-sin(aim.x), 0, -cos(aim.x))
				actor.automation_command.move = Vector2(offset.normalized().dot(right), -offset.normalized().dot(forward))
			else:
				actor.automation_command.move = Vector2.ZERO
		if mode in ["Survival", "Boss"] and battle_time > (12.0 if exercise_actions else 8.0):
			if not saw_enemies:
				_finish(false, "coop enemies not replicated")
				return
			if role == "host":
				if mode == "Survival":
					for unit: Node in world.actors.values():
						unit.invulnerable_left = 0.0
						unit.take_damage((unit.health + unit.shield) * 3.0, unit.position)
				else:
					# Assert production boss death/reward handling after observing
					# real replicas. Weapon collision itself is exercised by VS_FFA.
					for enemy: Node in world.enemies.values():
						if is_instance_valid(enemy) and enemy.is_boss_enemy() and not enemy.dead:
							world.damage_target(actor, enemy, enemy.max_health * 100.0, enemy.position)
	elif NetworkSession.phase == "finished":
		if not saw_result:
			saw_result = true
			var result: Dictionary = world.rules_view.result
			if mode == "Survival" and not result.winners.is_empty():
				_finish(false, "all-dead survival should lose")
				return
			if mode != "Survival" and not 1 in result.winners:
				_finish(false, "host missing from final winners")
				return
			if mode in ["CTF_FFA", "CTF_TDM", "VIP", "CMI"] and not saw_objective:
				_finish(false, "objective state was never replicated")
				return
			if not bool(world.settlement_result.get("saved", false)) or GameState.unlocked_level != unlocked_before:
				_finish(false, "receipt not saved or solo progress changed")
				return
			if exercise_actions and not actions_verified:
				_finish(false, "network action checks incomplete")
				return
			if exercise_knockback and not saw_knockback:
				_finish(false, "host knockback was not replicated")
				return
			if exercise_knockback and role == "client" and not knockback_recovery_verified:
				_finish(false, "knockback prediction cancellation/recovery was not verified")
				return
			var banked := GameState.credits
			world._prepare_settlement(NetworkSession.last_snapshot)
			world.settle_local_result()
			if GameState.credits != banked:
				_finish(false, "duplicate receipt paid twice")
				return
			if GameState.mithril - mithril_before != (1 if mode == "Boss" else 0):
				_finish(false, "incorrect Mithril encounter award")
				return
			if mode == "VS_FFA" and (not saw_damage or not saw_movement or int(world.rules_view.players[1].score) != 100):
				_finish(false, "missing movement/damage/100 score")
				return
		final_wait += delta
		if role == "client" and final_wait > 1.0:
			done = true
			NetworkSession.leave("integration client clean exit")
			_finish(true, "final state received and client exited")
		elif role == "host" and saw_disconnect and NetworkSession.roster.size() == 1:
			_finish(true, "damage/score/result/disconnect confirmed")

func _seed_knockback_prediction(state: Dictionary) -> void:
	if done or knockback_prediction_seeded or not is_instance_valid(world) or world.player == null:
		return
	var actor: Node = world.player
	var row: Dictionary = state.get("actors", {}).get(actor.peer_id, {})
	if float(row.get("knockback_left", 0.0)) <= 0.0:
		return
	knockback_prediction_seeded = true
	actor._set_magazine_rounds(0)
	actor._start_reload()
	actor.reload_event_mask = 1
	actor.dash_time = actor.dash_duration
	actor.dash_direction = Vector3.RIGHT
	actor.touch_dash_requested = true
	actor.shoot_pose_left = 0.3
	actor.restart_shoot_animation_requested = true
	actor.weapon_audio_active = true

func _check_knockback_snapshot(state: Dictionary) -> void:
	if done or not knockback_prediction_seeded:
		return
	var actor: Node = world.player
	var row: Dictionary = state.get("actors", {}).get(actor.peer_id, {})
	if float(row.get("knockback_left", 0.0)) <= 0.0:
		knockback_ended = knockback_actions_canceled
		return
	if actor.dash_time > 0.0 or actor.touch_dash_requested:
		_finish(false, "authoritative knockback did not cancel predicted/touch dash")
		return
	if actor.reload_left > 0.0 or actor.reload_total > 0.0 or actor.reload_elapsed > 0.0 or actor.reload_event_mask != 0:
		_finish(false, "authoritative knockback left local reload state active")
		return
	if actor.shoot_pose_left > 0.0 or actor.restart_shoot_animation_requested or actor.weapon_audio_active:
		_finish(false, "authoritative knockback left fire pose/audio active")
		return
	if not is_equal_approx(actor.enemy_knockback_left, float(row.knockback_left)) or actor.enemy_knockback_velocity != row.knockback_velocity or actor.enemy_knockback_animation != row.knockback_animation:
		_finish(false, "snapshot cancellation restarted or altered authoritative knockback")
		return
	knockback_actions_canceled = true

func _exercise_actions() -> void:
	if done: return
	var actor: Node = world.player
	if role == "host" and battle_time > 1.0 and not actions_seeded:
		actions_seeded = true
		for unit: Node in world.actors.values():
			unit.health = unit.max_health * 0.4
			unit.shield = 0.0
			unit.invulnerable_left = 100.0
	if battle_time > 2.0 and not action_steps.has("heal"):
		action_steps.heal = true
		heal_sequence = world.network_actions.request_action("prop", 1)
	if battle_time > 2.3 and not action_steps.has("skill"):
		action_steps.skill = true
		var available: Array = actor.armor_power_controller.get_available_skill_indices()
		if available.is_empty():
			_finish(false, "source Thunder profile has no skill")
			return
		world.network_actions.request_action("skill", int(available[0]))
	if battle_time > 2.6 and not action_steps.has("boost"):
		action_steps.boost = true
		world.network_actions.request_action("prop", 2)
	if battle_time > 3.0 and not action_steps.has("duplicate"):
		action_steps.duplicate = true
		if role == "host": NetworkSession._accept_action(1, NetworkSession.room_id, NetworkSession.generation, heal_sequence, "prop", 1)
		else: NetworkSession._action_request.rpc_id(1, NetworkSession.room_id, NetworkSession.generation, heal_sequence, "prop", 1)
	if battle_time > 3.2 and role == "host" and not action_steps.has("down"):
		action_steps.down = true
		for id: int in world.actors:
			if id != 1: world.actors[id]._die()
	var row: Dictionary = world.rules_view.get("players", {}).get(NetworkSession.local_id(), {})
	if role == "client" and actor.dead and float(row.get("death_elapsed", 0.0)) > 4.1 and not action_steps.has("revive"):
		action_steps.revive = true
		world.network_actions.request_action("prop", 3)
	if battle_time > 10.0 and not actions_verified:
		var expected_aid := 3 if role == "host" else 2
		if actor.dead or GameState.get_prop_count("prop00") != 2 or GameState.get_prop_count("prop07") != 2 or GameState.get_prop_count("prop05") != expected_aid:
			_finish(false, "healing/assist/revival RPC or one-time local inventory failed")
			return
		if actor.battle_items.get_bonus("speed_boost") <= 0.0 or actor.armor_power_controller.get_available_skill_indices().is_empty():
			_finish(false, "active buff/skill replica missing")
			return
		var id := NetworkSession.local_id()
		if NetworkSession.roster[id].package_slots[1] != "" or NetworkSession.roster[id].package_slots[2] != "":
			_finish(false, "consumed roster refilled before rematch")
			return
		actions_verified = true
		print("NETWORK_ACTIONS_PEER_PASS role=%s actualRPC heal assist skill revive duplicate" % role)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	if shot.save_png(capture_path) != OK:
		_finish(false, "rendered network HUD capture failed")
	else:
		print("NETWORK_HUD_CAPTURE_PASS %s" % capture_path)

func _finish(success: bool, message: String) -> void:
	done = true
	print("NETWORK_PEER_%s role=%s mode=%s %s" % ["PASS" if success else "FAIL", role, mode, message])
	NetworkSession.leave()
	if is_instance_valid(world):
		world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	get_tree().quit(0 if success else 1)
