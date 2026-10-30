extends Node3D

const Actions = preload("res://scripts/network/network_actions.gd")
const Inventory = preload("res://scripts/network/network_inventory.gd")
const Power = preload("res://scripts/network/network_armor_power.gd")
const State = preload("res://scripts/core/game_state.gd")
const SAVE := "user://network_actions_behavior_test.json"

var failures: Array[String] = []
var world: FixtureWorld
var actions: Node
var actor: FixtureActor
var last_ack: Dictionary = {}


class FixtureWorld extends "res://scripts/game/network_world.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass


class FixtureActor extends CharacterBody3D:
	var peer_id := 1
	var profile: Dictionary = {}
	var local_control := false
	var health := 100.0
	var max_health := 10000.0
	var dead := false
	var move_speed := 10.0
	var armor_skills: Dictionary = {}
	var battle_items: WarfareBattleItems
	var armor_power_controller: Node
	var aim_target: Node3D

	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.height = 2.0
		shape.shape = capsule
		shape.position.y = 1.0
		add_child(shape)

	func set_armor_power_controller(controller: Node) -> void:
		armor_power_controller = controller

	func restore(_kind: String, amount: float) -> void:
		health = minf(max_health, health + amount)

	func revive(ratio: float) -> bool:
		if not dead or not get_parent().rules.can_revive(peer_id): return false
		dead = false
		health = max_health * ratio
		return get_parent().rules.complete_revival(peer_id)

	func heal_from_armor_power(amount: float) -> float:
		var before := health
		health = minf(max_health, health + amount)
		return health - before

	func on_damage_dealt(amount: float) -> void:
		if is_instance_valid(armor_power_controller): armor_power_controller.on_damage_dealt(amount)

	func take_damage(amount: float, _at: Vector3, source: Node) -> void:
		var before := health
		health = maxf(0.0, health - amount)
		if is_instance_valid(source): source.on_damage_dealt(before - health)

	func get_aim_solution(reach: float = 180.0) -> Dictionary:
		return {"target": aim_target.global_position if is_instance_valid(aim_target) else global_position + Vector3.FORWARD * reach,
			"collider": aim_target}


class RuntimeActor extends "res://scripts/network/network_player.gd":
	# Production take_damage/revive and their base-player implementations, with
	# only mesh/animation/input setup omitted from this headless fixture.
	func _ready() -> void:
		model = Node3D.new()
		add_child(model)
		pitch_node = Node3D.new()
		add_child(pitch_node)
		hurt_audio = AudioStreamPlayer3D.new()
		add_child(hurt_audio)
		_build_collision()
		collision_layer = 4
		collision_mask = 0
		invulnerable_left = 0.0

	func _physics_process(_delta: float) -> void: pass
	func _update_visual_animation(_delta: float, _movement: float, _movement_input := Vector2.ZERO) -> void: pass


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("NETWORK_ACTIONS: " + message)


func _run() -> void:
	NetworkSession.auto_change_scene = false
	GameState.save_path = SAVE
	_cleanup_save()
	GameState.owned_props = {"prop00": 5, "prop05": 5, "prop06": 5, "prop07": 5}
	if not GameState.owned_armor.has("armor_bag_02"): GameState.owned_armor.append("armor_bag_02")
	GameState.equipped_armor.bag = "armor_bag_02" # Source SP-04-IV has four cells.
	GameState.battle_weapons.assign(["gun00"])
	GameState.package_slots.assign(["gun00", "prop00", "prop05", "prop06"])
	var error := NetworkSession.host_room({"mode": "Survival"}, 24649)
	if error != OK:
		check(false, "Could not start isolated test host: %s" % error)
		_finish()
		return
	NetworkSession.phase = "playing"
	NetworkSession.generation = 1
	NetworkSession.action_ack.connect(func(data: Dictionary): last_ack = data.duplicate(true))
	world = FixtureWorld.new()
	add_child(world)
	world.rules.begin(NetworkSession.room, NetworkSession.roster)
	actions = Actions.new()
	world.add_child(actions)
	actions.configure(world)
	actions.set_process(false)
	actor = _add_actor(1, 0)
	for key: String in Power.SKILL_KEYS: actor.armor_skills[key] = 1.0
	actor.armor_power_controller.refresh_available_skills()
	actor.local_control = true
	_test_props()
	_test_revival()
	_test_validation()
	await _test_powers()
	await _test_runtime_shield_and_revival()
	_test_save_retry()
	_test_reconnect_debt()
	_test_replica()
	world.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	_finish()


func _add_actor(id: int, team: int) -> FixtureActor:
	if not NetworkSession.roster.has(id):
		NetworkSession.roster[id] = NetworkSession._clean_profile(NetworkSession.profile_from_local())
	NetworkSession.roster[id].team = team
	if not world.rules.players.has(id):
		world.rules.players[id] = {"alive": true, "team": team, "respawn": 0.0, "boost": 0.0}
	var unit := FixtureActor.new()
	unit.peer_id = id
	unit.profile = {"package_slots": ["prop04"], "prop_counts": {"prop04": 99}}
	world.add_child(unit)
	world.actors[id] = unit
	actions.setup_actor(unit)
	unit.armor_power_controller.set_physics_process(false)
	return unit


func _request(kind: String, index: int) -> int:
	# Exercise production sequence validation without sleeping for rate limits.
	NetworkSession.action_times.clear()
	last_ack = {"accepted": false}
	return actions.request_action(kind, index)


func _equip(key: String) -> void:
	GameState.package_slots.assign(["gun00", key, "", ""])
	GameState.owned_props[key] = 5
	NetworkSession.roster[1].package_slots = GameState.get_package_slots()
	NetworkSession.roster[1].prop_counts = GameState.owned_props.duplicate()
	# Each fixture loadout is a new match; production never refills the roster.
	NetworkSession.generation += 1
	actor.battle_items.inventory.profile = NetworkSession.roster[1]


func _test_props() -> void:
	check(actor.battle_items.get_slots().size() == 3, "setup must use validated roster, not actor-supplied profile")
	actor.health = actor.max_health
	_request("prop", 1)
	check(not last_ack.accepted and GameState.get_prop_count("prop00") == 5, "Full health request spent an item")
	actor.health = 100.0
	var sequence := _request("prop", 1)
	check(last_ack.accepted and actor.health == 900.0, "Accepted prop did not apply source healing")
	check(GameState.get_prop_count("prop00") == 4 and GameState.get_package_slots()[1] == "", "ACK did not persist exactly one local use")
	check(NetworkSession.roster[1].prop_counts.prop00 == 4 and NetworkSession.roster[1].package_slots[1] == "", "Host roster did not retain consumed cell")
	actions._on_action_ack(last_ack)
	NetworkSession._accept_action(1, NetworkSession.room_id, NetworkSession.generation, sequence, "prop", 1)
	check(GameState.get_prop_count("prop00") == 4 and actor.health == 900.0, "Replayed request/ack spent or healed twice")
	var rematch_inventory := Inventory.new()
	rematch_inventory.configure(1, NetworkSession.roster[1])
	check(rematch_inventory.get_package_slots()[1] == "" and not rematch_inventory.consume_package_prop(1), "Rematch replenished a used slot")
	rematch_inventory.free()
	var loaded := State.new()
	loaded.save_path = SAVE
	add_child(loaded)
	check(loaded.get_prop_count("prop00") == 4 and loaded.get_package_slots()[1] == "", "Reload/reconnect replenished a consumed item")
	loaded.free()
	var remote := _add_actor(2, 0)
	var before := GameState.owned_props.duplicate()
	check(remote.battle_items.inventory.consume_package_prop(2), "Host could not consume a remote peer item")
	check(before == GameState.owned_props, "Remote spend changed host permanent inventory")
	remote.queue_free()
	world.actors.erase(2)
	world.rules.players.erase(2)
	NetworkSession.roster.erase(2)


func _test_revival() -> void:
	NetworkSession.room.mode = "Boss"
	for key: String in ["prop05", "prop06"]:
		_equip(key)
		world.rules.begin(NetworkSession.room, NetworkSession.roster)
		actor.dead = true
		actor.health = 0.0
		world.rules.player_died(1, 0, actor.position, true)
		check(not world.rules.ended, "Single-player Boss ended before its first-aid window")
		world.rules.tick(3.99)
		_request("prop", 1)
		check(not last_ack.accepted and GameState.get_prop_count(key) == 5, "First-aid was usable before the four-second death animation")
		world.rules.tick(0.02)
		_request("prop", 1)
		var ratio := 0.3 if key == "prop05" else 1.0
		check(last_ack.accepted and not actor.dead and is_equal_approx(actor.health, actor.max_health * ratio), "First-aid ratio incorrect: " + key)
		check(world.rules.players[1].deaths == 1 and world.rules.players[1].alive, "Paid revival changed the recorded death count")
	_equip("prop05")
	_request("prop", 1)
	check(not last_ack.accepted, "Living actor used first-aid")
	world.rules.begin(NetworkSession.room, NetworkSession.roster)
	actor.dead = true
	world.rules.player_died(1, 0, actor.position, true)
	world.rules.tick(8.99)
	check(not world.rules.ended and world.rules.can_revive(1), "Final player lost the five-second aid window")
	world.rules.tick(0.02)
	check(world.rules.ended, "Expired all-down aid window failed to end Boss")
	_request("prop", 1)
	check(actor.dead and GameState.get_prop_count("prop05") == 5, "Terminal all-down match allowed revival")
	world.rules.begin(NetworkSession.room, NetworkSession.roster)
	world.rules.player_died(1, 0, actor.position, false)
	world.rules.tick(4.01)
	check(world.rules.ended, "No-kit Boss did not end after its death animation")
	# Paid PvP revival wins before automatic respawn, retaining exactly one death.
	_equip("prop05")
	NetworkSession.room.mode = "VS_FFA"
	world.rules.begin(NetworkSession.room, NetworkSession.roster)
	world.rules.player_died(1, 0, actor.position, true)
	world.rules.tick(4.01)
	_request("prop", 1)
	check(last_ack.accepted and not actor.dead and GameState.get_prop_count("prop05") == 4, "PvP first-aid was incorrectly blocked")
	check(not world.rules.tick(30.0).has(1) and world.rules.players[1].deaths == 1, "Automatic respawn repeated a paid revival")
	# If automatic respawn wins first, even a stale actor.dead view cannot spend.
	_equip("prop05")
	world.rules.begin(NetworkSession.room, NetworkSession.roster)
	actor.dead = true
	world.rules.player_died(1, 0, actor.position, true)
	check(world.rules.tick(30.0).has(1), "PvP expired aid window failed to reach automatic respawn")
	_request("prop", 1)
	check(not last_ack.accepted and GameState.get_prop_count("prop05") == 5, "Late aid spent a copy after automatic respawn")
	actor.dead = false
	NetworkSession.room.mode = "Survival"
	world.rules.begin(NetworkSession.room, NetworkSession.roster)


func _test_validation() -> void:
	_equip("prop07")
	var before: Dictionary = NetworkSession.roster[1].duplicate(true)
	actions._on_action_requested(999, 900, "prop", 1)
	NetworkSession._accept_action(1, "wrong-room", NetworkSession.generation, 901, "prop", 1)
	NetworkSession._accept_action(1, NetworkSession.room_id, NetworkSession.generation - 1, 902, "prop", 1)
	NetworkSession._accept_action(1, NetworkSession.room_id, NetworkSession.generation, 903, "prop", -1)
	check(before == NetworkSession.roster[1], "Invalid peer/room/generation/index mutated inventory")
	_request("prop", 1)
	check(actor.battle_items.get_bonus("speed_boost") == 2.0, "Source booster not applied")
	actor.battle_items.advance(31.0)
	check(actor.battle_items.get_bonus("speed_boost") == 0.0, "Booster failed to expire")
	_request("skill", 0)
	check(last_ack.accepted, "Equipped skill rejected")
	_request("skill", 0)
	check(not last_ack.accepted, "Skill cooldown bypassed")
	actor.dead = true
	_request("skill", 1)
	check(not last_ack.accepted, "Dead actor activated a skill")
	actor.dead = false
	actor.armor_skills.erase("speed_up")
	actor.armor_power_controller.refresh_available_skills()
	_request("skill", 1)
	check(not last_ack.accepted, "Unequipped skill activated")
	actor.armor_skills.speed_up = 1.0
	actor.armor_power_controller.refresh_available_skills()


func _test_powers() -> void:
	var power: Node = actor.armor_power_controller
	power.cancel_all_active(true)
	NetworkSession.room.mode = "VS_TDM"
	world.rules.config.mode = "VS_TDM"
	world.pvp_arena = true
	var ally := _add_actor(2, 0)
	var enemy := _add_actor(3, 1)
	ally.position = Vector3(1, 0, -2)
	enemy.position = Vector3(-1, 0, -2)
	ally.health = 10000.0
	enemy.health = 10000.0
	await get_tree().physics_frame
	power.activate_authoritative(5)
	power.advance_simulation(0.25)
	check(ally.health == 10000.0 and enemy.health < 10000.0, "Shield did not damage opponent only through world rules")
	power.cancel_all_active(true)
	actor.aim_target = ally
	power.activate_authoritative(9)
	power.advance_simulation(0.25)
	check(ally.position == Vector3(1, 0, -2) and power._gravity_target == null, "Gravity selected a teammate")
	power.cancel_all_active(true)
	actor.aim_target = enemy
	enemy.position = Vector3(0, 0, -12)
	power.activate_authoritative(9)
	power.advance_simulation(0.25)
	check(enemy.position.z > -8.0, "Host gravity did not pull an opponent")
	power._apply_tracking_mark(enemy)
	check(is_equal_approx(enemy.move_speed, 7.0), "Host track did not slow opponent")
	power._apply_tracking_mark(ally)
	check(ally.move_speed == 10.0, "Track slowed a teammate")
	var second := Power.new()
	second.configure(actor, world)
	actor.add_child(second)
	second.set_physics_process(false)
	second._apply_tracking_mark(enemy)
	power.cancel_all_active(true)
	check(is_equal_approx(enemy.move_speed, 7.0), "First expired mark cancelled another caster's slow")
	second.cancel_all_active(true)
	check(is_equal_approx(enemy.move_speed, 10.0), "Final mark failed to restore source speed")
	second.free()
	var expected_impact := MatchRules.vs_damage(Power.IMPACT_WAVE_DAMAGE, "armor_power") * 2.5
	var dealt: float = power._deal_enemy_damage(enemy, Power.IMPACT_WAVE_DAMAGE, "impact")
	check(is_equal_approx(dealt, expected_impact), "PvP impact wave omitted source 2.5 damage multiplier")
	# Run real wave/PhysicsServer intersection and the production world damage
	# route, including the damage callback used for life steal.
	enemy.health = 50000.0
	enemy.position = Vector3(0, 0, -4)
	actor.health = 100.0
	actor.max_health = 50000.0
	await get_tree().physics_frame
	power.activate_authoritative(4)
	power.activate_authoritative(6)
	var before_enemy := enemy.health
	for step in 12:
		power.advance_simulation(0.05)
		await get_tree().physics_frame
		if enemy.health < before_enemy: break
	var actual := before_enemy - enemy.health
	check(actual > 0.0 and is_equal_approx(actor.health - 100.0, actual), "Impact + life steal did not heal actual damage exactly once")
	check(ally.health == 10000.0, "Penetrating wave hit an ally")
	power.cancel_all_active(true)
	actor.health = 100.0
	before_enemy = enemy.health
	power.activate_authoritative(6)
	for step in 12:
		power.advance_simulation(0.05)
		await get_tree().physics_frame
		if enemy.health < before_enemy: break
	actual = before_enemy - enemy.health
	check(actual > 0.0 and is_equal_approx(actor.health - 100.0, actual * 0.5), "Impact without life steal did not heal half of actual damage")
	power.cancel_all_active(true)
	world.pvp_arena = false
	NetworkSession.room.mode = "Survival"
	world.rules.config.mode = "Survival"
	for index in Power.SKILL_KEYS.size():
		power.cancel_all_active(true)
		check(power.activate_authoritative(index), "Active power missing: %d" % index)
		check(is_equal_approx(power.cooldown_left[index], Power.COOLDOWNS[index]), "Source cooldown changed: %d" % index)
	power.cancel_all_active(true)
	actor.health = 100.0
	actor.max_health = 20000.0
	power.activate_authoritative(3)
	check(actor.health == 10100.0, "Andromeda source healing missing")
	actor.health = 100.0
	power.activate_authoritative(4)
	power.on_damage_dealt(35.0)
	check(actor.health == 135.0, "Life steal must heal actual damage once")
	power.cancel_all_active(true)


func _test_save_retry() -> void:
	_equip("prop00")
	actor.health = 100.0
	GameState.save_path = "user://missing_network_actions_directory/profile.json"
	_request("prop", 1)
	check(last_ack.accepted and GameState.get_prop_count("prop00") == 5, "Failed save must roll back local inventory")
	check(not NetworkSession.get_meta("pending_prop_consumptions", {}).is_empty(), "Failed save discarded the confirmed debt")
	check(actions.request_action("prop", 1) == -1, "Unsettled consumption allowed more item use")
	GameState.save_path = SAVE
	actions._retry_consumptions()
	check(GameState.get_prop_count("prop00") == 4 and NetworkSession.get_meta("pending_prop_consumptions", {}).is_empty(), "Confirmed consumption failed to retry")
	actions._on_action_ack(last_ack)
	check(GameState.get_prop_count("prop00") == 4, "Retry and duplicated ack spent twice")
	for stored in [false, true]:
		_equip("prop00")
		actor.health = 100.0
		GameState.save_path = "user://missing_network_actions_directory/profile.json"
		_request("prop", 1)
		check(last_ack.accepted, "Rearrangement fixture did not confirm a use")
		var delayed: Dictionary = last_ack.duplicate(true)
		GameState.save_path = SAVE
		GameState.owned_props.prop07 = 5
		var rearranged: Array[String] = []
		rearranged.assign(["gun00", "prop07", "prop05", "prop06"] if stored else ["gun00", "prop07", "prop00", ""])
		check(GameState.set_package(rearranged, GameState.get_package_storage()), "Recovered disk could not save the rearranged package")
		# A new world gets a new adapter; only session receipts survive leaving.
		actions.free()
		actions = Actions.new()
		world.add_child(actions)
		actions.configure(world)
		actions.set_process(false)
		for unit: Node in world.actors.values(): unit.armor_power_controller.actions = actions
		check(GameState.get_prop_count("prop00") == 4 and GameState.get_prop_count("prop07") == 5, "Rearranged retry spent the wrong item or failed to settle")
		check(GameState.get_package_slots()[1] == "prop07" and (stored or GameState.get_package_slots()[2] == ""), "Retry overwrote an unrelated bag cell")
		check(NetworkSession.get_meta("pending_prop_consumptions", {}).is_empty(), "Rearranged retry left items permanently blocked")
		actions._on_action_ack(delayed)
		check(GameState.get_prop_count("prop00") == 4, "Delayed receipt after rearrangement spent twice")
		var loaded := State.new()
		loaded.save_path = SAVE
		add_child(loaded)
		check(loaded.get_prop_count("prop00") == 4 and loaded.get_package_slots()[1] == "prop07", "Rearranged consumption was not persisted")
		loaded.free()


func _test_runtime_shield_and_revival() -> void:
	NetworkSession.room.mode = "VS_TDM"
	world.rules.config.mode = "VS_TDM"
	world.pvp_arena = true
	var target := RuntimeActor.new()
	target.peer_id = 4
	target.profile = NetworkSession._clean_profile(NetworkSession.profile_from_local())
	target.profile.team = 1
	target.network_world = world
	world.add_child(target)
	world.actors[4] = target
	world.rules.players[4] = {"team": 1, "alive": true, "respawn": 0.0, "boost": 0.0, "deaths": 0, "kills": 0, "score": 0}
	target.position = Vector3(20, 0, -4)
	target.max_health = 10000.0
	target.health = 10000.0
	target.max_shield = 100000.0
	target.shield = 100000.0
	target.armor_skills = {}
	actor.position = Vector3(20, 0, 0)
	actor.aim_target = target
	actor.max_health = 50000.0
	actor.health = 100.0
	var power: Node = actor.armor_power_controller
	power.cancel_all_active(true)
	await get_tree().physics_frame
	power.activate_authoritative(6)
	for step in 12:
		power.advance_simulation(0.05)
		await get_tree().physics_frame
		if target.shield < target.max_shield: break
	check(target.health == target.max_health and target.shield < target.max_shield, "Production shield-only impact did not hit")
	check(is_equal_approx(actor.health - 100.0, (target.max_shield - target.shield) * 0.5), "Shield-only impact did not heal half the actual damage once")
	power.cancel_all_active(true)
	power.activate_authoritative(7)
	var speed_before := target.move_speed
	for step in 12:
		power.advance_simulation(0.05)
		await get_tree().physics_frame
		if target.move_speed < speed_before: break
	check(target.health == target.max_health and target.move_speed < speed_before, "Shield-only track hit failed to mark/slow a real NetworkPlayer")
	power.cancel_all_active(true)
	check(is_equal_approx(target.move_speed, speed_before), "Real NetworkPlayer speed was not restored")
	target.dead = true
	target.health = 0.0
	world.rules.player_died(4, 0, target.position, true)
	check(not target.revive(0.3), "Real NetworkPlayer revived before the death animation")
	world.rules.tick(4.01)
	check(target.revive(0.3) and target.health == 3000.0 and target.shield == 0.0, "Real NetworkPlayer did not apply first-aid revival")
	check(not world.rules.tick(30.0).has(4) and not target.revive(1.0), "Real NetworkPlayer revived twice after paid aid")
	target.dead = true
	world.rules.player_died(4, 0, target.position, true)
	check(world.rules.tick(20.01).has(4), "Real player did not reach scheduled PvP respawn")
	check(not target.revive(0.3), "Real NetworkPlayer accepted late aid after automatic respawn")
	target.hurt_audio.stop()
	target.queue_free()
	world.actors.erase(4)
	world.rules.players.erase(4)
	actor.position = Vector3.ZERO
	actor.aim_target = null
	NetworkSession.room.mode = "Survival"
	world.rules.config.mode = "Survival"
	world.pvp_arena = false
	await get_tree().process_frame


func _test_reconnect_debt() -> void:
	_equip("prop00")
	GameState.owned_props.prop00 = 1
	NetworkSession.roster[1].prop_counts.prop00 = 1
	actor.health = 100.0
	GameState.save_path = "user://missing_network_actions_directory/profile.json"
	_request("prop", 1)
	check(last_ack.accepted and GameState.get_prop_count("prop00") == 1, "Last-copy fixture did not retain a failed-save debt")
	NetworkSession.leave()
	var rejected: Error = NetworkSession.host_room({"mode": "Survival"}, 24649)
	check(rejected != OK and NetworkSession.phase == "offline", "New room admitted a profile with an unsettled consumption")
	if rejected == OK: NetworkSession.leave()
	GameState.save_path = SAVE
	var reopened: Error = NetworkSession.host_room({"mode": "Survival"}, 24649)
	check(reopened == OK, "Recovered storage could not reopen a room")
	if reopened != OK: return
	check(GameState.get_prop_count("prop00") == 0 and NetworkSession.roster[1].package_slots[1] == "" and int(NetworkSession.roster[1].prop_counts.get("prop00", 0)) == 0, "Rejoin roster advertised the last already-consumed copy")
	NetworkSession.phase = "playing"
	world.rules.begin(NetworkSession.room, NetworkSession.roster)
	actor.battle_items.inventory.configure(1, NetworkSession.roster[1])
	for id: int in world.actors.keys():
		if id != 1:
			world.actors[id].queue_free()
			world.actors.erase(id)
	var before := actor.health
	check(actions.request_action("prop", 1) == -1 and actor.health == before, "Rejoined host granted another use of its final copy")
	check(NetworkSession.get_meta("pending_prop_consumptions", {}).is_empty(), "Rejoin generated another unsatisfiable debt")


func _test_replica() -> void:
	var power: Node = actor.armor_power_controller
	power.cancel_all_active(true)
	_equip("prop07")
	# Withhold the reliable acknowledgement to verify snapshot recovery. Later
	# replaying that acknowledgement must not consume the same copy twice.
	NetworkSession.action_ack.disconnect(actions._on_action_ack)
	_request("prop", 1)
	var withheld: Dictionary = last_ack.duplicate(true)
	NetworkSession.action_ack.connect(actions._on_action_ack)
	check(GameState.get_prop_count("prop07") == 5 and withheld.accepted, "Fixture did not withhold the spend acknowledgement")
	power.activate_authoritative(5)
	power.activate_authoritative(6)
	power.activate_authoritative(7)
	var state: Dictionary = actions.snapshot_actor(actor)
	# Preserve the last authoritative state, then switch this process to a client.
	NetworkSession.peer.close()
	NetworkSession.peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var before := actor.health
	var replica := FixtureActor.new()
	replica.peer_id = 0
	world.add_child(replica)
	NetworkSession.roster[0] = NetworkSession.roster[1].duplicate(true)
	actions.setup_actor(replica)
	replica.armor_skills = actor.armor_skills.duplicate()
	replica.armor_power_controller.refresh_available_skills()
	actions.apply_actor_state(replica, state)
	check(GameState.get_prop_count("prop07") == 4 and GameState.get_package_slots()[1] == "", "Snapshot failed to recover a lost acknowledgement")
	actions._on_action_ack(withheld)
	check(GameState.get_prop_count("prop07") == 4, "Late acknowledgement duplicated a snapshot spend")
	var controller: Node = replica.armor_power_controller
	check(controller._active_auras.has(5) and controller._replica_visuals.size() == 2, "Snapshot omitted aura/wave VFX")
	check(controller._waves.is_empty() and controller._tracked_targets.is_empty(), "Replica created authoritative simulation objects")
	controller.advance_simulation(10.0)
	controller._heal_player(1000.0)
	check(not controller.activate_authoritative(3) and replica.health == 100.0 and actor.health == before, "Client ran authoritative healing/activation")
	check(not replica.battle_items.inventory.consume_package_prop(2), "Client directly consumed match inventory")
	var current_count := GameState.get_prop_count("prop00")
	actions.apply_actor_state(replica, state)
	check(GameState.get_prop_count("prop00") == current_count, "Cumulative snapshot duplicated acknowledged spend")
	power.cancel_all_active(true)
	state.power = power.snapshot()
	actions.apply_actor_state(replica, state)
	check(controller._active_auras.is_empty() and controller._replica_visuals.is_empty(), "Expired host VFX survived on replica")
	NetworkSession.phase = "offline"


func _finish() -> void:
	if NetworkSession.peer != null: NetworkSession.leave()
	_cleanup_save()
	if failures.is_empty(): print("NETWORK_ACTIONS_TEST_PASS props=revival=authority=cooldown=rematch=save_retry=vfx=PASS")
	get_tree().quit(0 if failures.is_empty() else 1)


func _cleanup_save() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE + suffix))
