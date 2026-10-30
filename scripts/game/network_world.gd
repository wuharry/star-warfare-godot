extends "res://scripts/game/game_world.gd"
## Real direct-connect game. Reuses recovered arena and presentation helpers,
## Rewards are host-owned receipts. campaign_progress=false prevents network
## wins from unlocking solo missions. Fixed boss Mithril is settled atomically.
const Rules = preload("res://scripts/core/match_rules.gd")
const NetPlayer = preload("res://scripts/network/network_player.gd")
const NetEnemy = preload("res://scripts/network/network_enemy.gd")
const NetBoss = preload("res://scripts/network/network_boss.gd")
const NetProjectile = preload("res://scripts/network/network_projectile.gd")
const NetGift = preload("res://scripts/network/network_gift.gd")
const NetPickup = preload("res://scripts/network/network_pickup.gd")
const NetHUD = preload("res://scripts/network/network_hud.gd")
const SurvivalMissions = preload("res://scripts/core/solo_missions.gd")
const SurvivalDirector = preload("res://scripts/game/mission_director.gd")
const NetworkActions = preload("res://scripts/network/network_actions.gd")

var rules := Rules.new()
var actors: Dictionary = {}
var enemies: Dictionary = {}
var projectiles: Dictionary = {}
var gifts: Dictionary = {}
var pickups: Dictionary = {}
var source_effects: Dictionary = {}
var source_effect_sequence := 0
var pickup_sequence := 0
var network_hud: CanvasLayer
var flag_visual: Node3D
var rules_view: Dictionary = {}
var test_arena := false
var tick_number := 0
var snapshot_left := 0.0
var wave_delay := 2.0
var enemy_sequence := 0
var projectile_sequence := 0
var last_vip := 0
var final_sent := false
var active := false
var network_director: Node
var network_actions: Node
var reward_ledgers: Dictionary = {}
var server_progress: Dictionary = {}
var settlement_result: Dictionary = {}
var local_receipt: Dictionary = {}
var career_before_result: Dictionary = {}
var career_after_result: Dictionary = {}

func _ready() -> void:
	if NetworkSession.phase != "loading":
		NetworkSession.leave("Host or join a room from the direct-connect lobby first.")
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
		return
	level_data = GameState.get_level_data(int(NetworkSession.room.level)).duplicate(true)
	pvp_arena = not Rules.is_coop(NetworkSession.room.mode)
	level_data.pvp = pvp_arena
	level_data.mode = "pvp" if pvp_arena else "pve"
	level_data.boss = NetworkSession.room.mode == "Boss"
	if bool(level_data.boss):
		level_data.resource_directory = "res://assets/models/boss_arenas/boss_%02d" % (int(NetworkSession.room.boss_index) + 1)
		if not test_arena and not FileAccess.file_exists(level_data.resource_directory + "/level.json"):
			NetworkSession.leave("Source Boss arena is missing. This encounter cannot start.")
			return
	arena_size = float(level_data.arena_size)
	difficulty_profile = GameState.get_difficulty_profile()
	max_attack_tokens = int(difficulty_profile.get("attack_slots", 99))
	rng.seed = 0x5A17 + NetworkSession.generation * 919
	if test_arena:
		_build_test_arena()
	else:
		_load_stage_metadata()
		_build_environment()
		_build_arena()
	rules.begin(NetworkSession.room, NetworkSession.roster)
	network_actions = NetworkActions.new()
	network_actions.name = "Actions"
	add_child(network_actions)
	network_actions.configure(self)
	var seat := 0
	for id: int in NetworkSession.roster:
		var actor := NetPlayer.new()
		actor.peer_id = id
		actor.profile = NetworkSession.roster[id]
		actor.local_control = id == NetworkSession.local_id()
		actor.network_world = self
		actor.position = spawn_for(seat)
		add_child(actor)
		actors[id] = actor
		network_actions.setup_actor(actor)
		reward_ledgers[id] = {"credits": 0, "experience": 0, "mithril": 0}
		var tracker := BattleProgressScript.new()
		tracker.start(null, {"multiplayer": true, "pve": not pvp_arena})
		server_progress[id] = tracker
		actor.damaged.connect(func(amount):
			if NetworkSession.is_host():
				server_progress[id].record_damage(amount)
				NetworkSession.send_progress(id, {"kind": "damage", "amount": amount})
		)
		if actor.local_control:
			player = actor
		seat += 1
	if player != null:
		player.camera.make_current()
	var flag_points := _marker_positions(stage_metadata.get("markers", {}).get("FlagSpawn", []))
	rules.flag_home = flag_points[0] if not flag_points.is_empty() else Vector3.ZERO
	rules.flag_position = rules.flag_home
	_build_objectives()
	NetworkSession.command_received.connect(_on_command)
	NetworkSession.snapshot_received.connect(_apply_snapshot)
	NetworkSession.effect_received.connect(_play_effect)
	NetworkSession.player_left.connect(_remove_player)
	NetworkSession.world_activated.connect(_activate)
	NetworkSession.progress_event.connect(_on_progress_event)
	network_hud = NetHUD.new()
	network_hud.world = self
	add_child(network_hud)
	if not test_arena:
		_start_music()
	rules_view = rules.snapshot()
	NetworkSession.mark_world_loaded.call_deferred()

func _process(_delta: float) -> void:
	pass

func _exit_tree() -> void:
	super._exit_tree()
	AudioDirector.stop_all_sfx()

func _build_test_arena() -> void:
	effects_root = Node3D.new()
	add_child(effects_root)
	_add_static_box("NetworkTestFloor", Vector3(50, 1, 50), Vector3(0, -0.5, 0), _material(Color.DARK_SLATE_GRAY, 1.0, 0.0))
	player_spawn_points = [Vector3(0, 0.1, 5), Vector3(0, 0.1, -5)]
	enemy_spawn_points = [Vector3(8, 0.1, 0), Vector3(-8, 0.1, 0)]
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 20, 0)
	add_child(light)

func spawn_for(index: int) -> Vector3:
	if not player_spawn_points.is_empty():
		return player_spawn_points[posmod(index, player_spawn_points.size())] + Vector3.UP * 0.1
	return Vector3(cos(index * PI) * 8.0, 0.1, sin(index * PI) * 8.0)

func _activate() -> void:
	active = true
	progress.start(GameState.career, {"level_key": "network:%s" % str(NetworkSession.room.mode), "multiplayer": not pvp_arena, "pve": not pvp_arena})
	if NetworkSession.is_host() and NetworkSession.room.mode == "Survival":
		# EnemySpawnScript.cs:93 selects the same stage's sixth table in coop.
		network_director = SurvivalDirector.new()
		add_child(network_director)
		network_director.round_started.connect(func(index, _difficulty): rules.wave = index + 1)
		network_director.mission_failed.connect(func(_reason): rules.finish("spawn_configuration_failed", false))
		if not network_director.configure(self, SurvivalMissions.get_mission(int(NetworkSession.room.level), 5)):
			rules.finish("spawn_configuration_failed", false)
	if NetworkSession.is_host() and NetworkSession.room.mode == "Boss":
		rules.wave = 1
		_spawn_network_enemy("boss", 0)
		if int(NetworkSession.room.boss_index) == 3:
			_spawn_network_enemy("boss", 1)
			var pair := enemies.values()
			if pair.size() == 2:
				pair[0].link_source_partner(pair[1])

func _physics_process(delta: float) -> void:
	if not active or NetworkSession.phase != "playing":
		return
	progress.advance(delta)
	if NetworkSession.is_host():
		for tracker: RefCounted in server_progress.values():
			tracker.advance(delta)
		tick_number += 1
		var revived := rules.tick(delta)
		for id: int in revived:
			if actors.has(id):
				actors[id].network_respawn(spawn_for(rng.randi_range(0, maxi(1, player_spawn_points.size() - 1))))
		if rules.vip_id != last_vip:
			last_vip = rules.vip_id
			if actors.has(last_vip):
				var vip = actors[last_vip]
				if vip.dead:
					vip.network_respawn(spawn_for(actors.keys().find(last_vip)))
				vip.health = vip.max_health
				vip.shield = vip.max_shield
		_tick_objectives(delta)
		rules_view = rules.snapshot()
		snapshot_left -= delta
		if rules.ended and not final_sent:
			final_sent = true
			completed = true
			NetworkSession.broadcast_snapshot(make_snapshot(), true)
		elif snapshot_left <= 0.0:
			snapshot_left = 1.0 / 15.0
			NetworkSession.broadcast_snapshot(make_snapshot())
	_update_objective_visual()

func _on_command(id: int, input: Dictionary) -> void:
	if actors.has(id):
		actors[id].command = input

func player_died(id: int, killer: int) -> void:
	var items: Node = actors[id].battle_items
	var has_aid := false
	for entry: Dictionary in items.get_slots():
		if entry.item.effects.has("revive_ratio") and items.inventory.get_prop_count(entry.key) > 0:
			has_aid = true
	rules.player_died(id, killer, actors[id].position, has_aid)

func _remove_player(id: int) -> void:
	var at := Vector3.ZERO
	if actors.has(id):
		at = actors[id].position
		actors[id].queue_free()
		actors.erase(id)
	rules.remove_player(id, at)

func nearest_player(at: Vector3) -> WarfarePlayer:
	var nearest: WarfarePlayer
	var distance := INF
	for actor: WarfarePlayer in actors.values():
		if not actor.dead and actor.position.distance_squared_to(at) < distance:
			nearest = actor
			distance = actor.position.distance_squared_to(at)
	return nearest

func nearest_damage_target(source: Node, at: Vector3) -> Node3D:
	var nearest: Node3D
	var distance := INF
	for candidate: Node in actors.values() + enemies.values():
		if not is_instance_valid(candidate) or candidate.dead or candidate == source:
			continue
		if "peer_id" in candidate and "peer_id" in source and not rules.can_damage(source.peer_id, candidate.peer_id):
			continue
		if not "peer_id" in source and not "peer_id" in candidate:
			continue
		var d := at.distance_squared_to(candidate.position)
		if d < distance:
			nearest = candidate
			distance = d
	return nearest

func _spawn_network_enemy(kind: String, index: int) -> void:
	var enemy = NetBoss.new() if kind == "boss" else NetEnemy.new()
	enemy_sequence += 1
	enemy.network_id = enemy_sequence
	var scale_factor := 1.0 + floorf(float(rules.wave) / 13.0) * 0.25
	if kind == "boss":
		if not enemy.configure_boss(player, int(NetworkSession.room.boss_index), index == 1):
			push_error(enemy.configuration_error)
			enemy.free()
			rules.finish("spawn_configuration_failed", false)
			return
	else:
		enemy.configure_recovered(player, kind, scale_factor)
	var points := boss_spawn_points if kind == "boss" and not boss_spawn_points.is_empty() else enemy_spawn_points
	enemy.position = points[index % points.size()] if not points.is_empty() else spawn_for(index + 1)
	if kind != "boss": enemy.position += Vector3(sin(index * 2.4), 0.12, cos(index * 2.4)) * 2.0
	enemy.apply_coop_scaling(actors.size())
	add_child(enemy)
	_register_enemy(enemy)

func spawn_mission_enemy(request: Dictionary) -> bool:
	if not NetworkSession.is_host() or rules.ended:
		return false
	var enemy := NetEnemy.new()
	if not enemy.configure_original(player, int(request.monster_id), 1.0, bool(request.get("elite", false)), int(request.get("difficulty", 0))):
		push_error(enemy.configuration_error)
		enemy.free()
		return false
	enemy_sequence += 1
	enemy.network_id = enemy_sequence
	enemy.position = _mission_spawn_position(int(request.get("spawn_from", 0))) if not test_arena else enemy_spawn_points[enemy_sequence % enemy_spawn_points.size()]
	enemy.apply_coop_scaling(actors.size())
	if int(request.get("spawn_from", 0)) == 0: enemy.spawn_left = 0.0
	add_child(enemy)
	_register_enemy(enemy)
	return true

func _register_enemy(enemy: Node) -> void:
	alive_enemies += 1
	enemies[enemy.network_id] = enemy
	enemy.source_effect_spawned.connect(func(effect: Node3D, description: Dictionary):
		_register_source_effect(effect, description, int(enemy.network_id))
	)
	enemy.source_loot_requested.connect(func(at: Vector3, kind: String, amount: int):
		spawn_pickup(at + Vector3.UP, kind, amount)
	)
	enemy.died.connect(func(unit, _at, _reward, _score):
		alive_enemies = maxi(0, alive_enemies - 1)
		var final_boss: bool = unit.is_boss_enemy()
		if final_boss:
			for other: Node in enemies.values():
				if is_instance_valid(other) and other != unit and other.is_boss_enemy() and not other.dead:
					final_boss = false
		_award_enemy(unit, final_boss)
		rules.enemy_killed(unit.last_attacker, final_boss)
	)
	enemy.tree_exiting.connect(func(): enemies.erase(enemy.network_id))

func _register_source_effect(effect: Node3D, description: Dictionary, enemy_id: int) -> void:
	source_effect_sequence += 1
	var id := source_effect_sequence
	source_effects[id] = {"node": effect, "description": description.duplicate(true), "enemy": enemy_id}
	effect.tree_exiting.connect(func(): source_effects.erase(id))

func spawn_pickup(at: Vector3, kind: String, amount: float) -> void:
	if not NetworkSession.is_host() or rules.ended: return
	var pickup := NetPickup.new()
	pickup_sequence += 1
	pickup.network_id = pickup_sequence
	pickup.configure(kind, amount)
	add_child(pickup)
	pickup.position = at
	pickups[pickup.network_id] = pickup
	pickup.tree_exiting.connect(func(): pickups.erase(pickup.network_id))

func collect_network_pickup(pickup: Node, actor: Node) -> void:
	if not actors.has(actor.peer_id) or rules.ended: return
	if pickup.pickup_kind == "credits":
		reward_ledgers[actor.peer_id].credits += int(pickup.amount)
	else:
		actor.restore(pickup.pickup_kind, pickup.amount)
	var effect := {"type": "pickup", "peer": actor.peer_id, "kind": pickup.pickup_kind}
	_play_effect(effect)
	NetworkSession.broadcast_effect(effect)

func _award_enemy(unit: Node, final_boss: bool) -> void:
	if not Rules.is_coop(NetworkSession.room.mode):
		return
	var recipients: Array = actors.keys() if final_boss else [int(unit.last_attacker)]
	if unit.is_boss_enemy() and not final_boss:
		return
	var source_id := int(unit.source_monster_id)
	# Paired mantises award the main encounter's cash/XP after both are dead.
	var base_cash := int(unit.reward)
	var base_exp := int(unit.experience_value)
	if final_boss and int(NetworkSession.room.boss_index) == 3:
		var main: Dictionary = unit.MonsterCatalog.get_monster(11)
		base_cash = int(float(main.credits) * ([1.0, 1.2, 1.5][clampi(actors.size() - 1, 0, 2)]))
		base_exp = int(main.experience)
	for id: int in recipients:
		if not actors.has(id):
			continue
		var tracker: RefCounted = server_progress[id]
		var category := int(unit.MonsterCatalog.ACHIEVEMENT_BOSS_CATEGORIES.get(source_id, -1))
		tracker.record_enemy_kill(category)
		var bonus := float(tracker.get_combo_bonus_rate())
		var skills: Dictionary = actors[id].armor_skills
		var cash := int(float(base_cash) * maxf(0.0, 1.0 + float(skills.get("money_boost", 0.0))))
		if final_boss:
			cash = int(float(cash) * pow(0.5, int(NetworkSession.boss_clears.get(NetworkSession.room.boss_index, 0))))
			reward_ledgers[id].mithril = 1
			if id != int(unit.last_attacker):
				rules.players[id].kills += 1
				rules.add_score(id, 100)
		reward_ledgers[id].credits += cash + int(float(base_cash) * bonus)
		reward_ledgers[id].experience += int(float(base_exp) * maxf(0.0, 1.0 + float(skills.get("exp_boost", 0.0)) + bonus))
		NetworkSession.send_progress(id, {"kind": "kill", "boss_category": category})
	if final_boss:
		var key := int(NetworkSession.room.boss_index)
		NetworkSession.boss_clears[key] = int(NetworkSession.boss_clears.get(key, 0)) + 1

func _on_progress_event(event: Dictionary) -> void:
	if event.kind == "kill":
		progress.record_enemy_kill(int(event.get("boss_category", -1)))
	elif event.kind == "damage":
		progress.record_damage(float(event.amount))

func fire_weapon(actor: WarfarePlayer, kind: String) -> void:
	if rules.ended or actor.dead:
		return
	var data: Dictionary = actor.current_weapon
	var reach := float(data.get("range", 100.0))
	var aim := actor.get_aim_solution(reach)
	var damage := actor._current_weapon_damage() * rules.damage_multiplier(actor.peer_id)
	if pvp_arena:
		damage = Rules.vs_damage(damage, "tracking" if str(data.kind) == "spring" else str(data.kind))
	var fire_effect := {"type": "fire", "peer": actor.peer_id, "from": actor.muzzle.global_position,
		"direction": aim.direction, "style": str(data.get("tracer_style", "legacy"))}
	_play_effect(fire_effect)
	NetworkSession.broadcast_effect(fire_effect)
	if kind == "sword":
		if actor.current_weapon_id == "gun33":
			# AdvancedSword.MakeExtraHit removes the melee-only VS x2 boost.
			_fire_projectile_pattern(actor, aim, "windblade", damage * (0.2 if pvp_arena else 0.4))
		for target: Node in actors.values() + enemies.values() + gifts.values():
			if not is_instance_valid(target) or target == actor:
				continue
			var offset: Vector3 = target.position + Vector3.UP - aim.origin
			if offset.length() <= maxf(2.5, reach) and offset.normalized().dot(aim.direction) > 0.3 and has_line_of_sight(aim.origin, target.position + Vector3.UP):
				damage_target(actor, target, damage, target.position)
		return
	if kind != "hitscan":
		_fire_projectile_pattern(actor, aim, kind, damage)
		return
	if str(data.kind) == "shockwave":
		_fire_impulse(actor, aim, damage)
		return
	for pellet in range(clampi(int(data.get("pellets", 1)), 1, 20)):
		var spread := float(data.get("spread", 0.0))
		var direction: Vector3 = (Vector3(aim.direction) + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))).normalized()
		var end: Vector3 = aim.origin + direction * reach
		var query := PhysicsRayQueryParameters3D.create(aim.origin, end, 7)
		query.exclude = [actor.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
			var first: Node = EnemyHitGeometry.resolve(hit.collider)
			var eligible := can_damage_target(actor, first)
			damage_target(actor, first, damage, end)
			if eligible and str(data.kind) == "reflection": _reflect_sniper(actor, first, damage)
		var effect := {"type": "shot", "from": actor.muzzle.global_position, "to": end, "peer": actor.peer_id,
			"style": str(data.get("tracer_style", "legacy")), "tint": data.get("color", Color.CYAN)}
		_play_effect(effect)
		NetworkSession.broadcast_effect(effect)

func can_damage_target(source: Node, target: Node) -> bool:
	if not NetworkSession.is_host() or rules.ended or not is_instance_valid(source) or not is_instance_valid(target) or not target.has_method("take_damage"):
		return false
	if target == source or ("dead" in target and target.dead): return false
	if "peer_id" in source and "peer_id" in target and not rules.can_damage(source.peer_id, target.peer_id):
		return false
	if not "peer_id" in source and not "peer_id" in target:
		return false
	return true

func damage_target(source: Node, target: Node, amount: float, at: Vector3, category: Variant = null) -> float:
	if not can_damage_target(source, target): return 0.0
	var before := (float(target.health) if "health" in target else 0.0) + (float(target.shield) if "shield" in target else 0.0)
	# Hits are synchronous. A stack preserves the saved shot category through
	# callbacks/reentrant damage while retaining the real actor for kill credit,
	# team checks and life-steal; no temporary actor or inventory is fabricated.
	var scoped := category != null and "damage_category_stack" in source
	if scoped: source.damage_category_stack.append(str(category))
	target.take_damage(amount, at, source)
	if scoped: source.damage_category_stack.pop_back()
	var after := (float(target.health) if "health" in target else 0.0) + (float(target.shield) if "shield" in target else 0.0)
	return maxf(0.0, before - after)

func _reflect_sniper(actor: Node3D, first: Node3D, damage: float) -> void:
	var nearest: Node3D
	var distance := INF
	var candidates: Array = actors.values() if "peer_id" in first else enemies.values()
	for target: Node3D in candidates:
		if target == first or not can_damage_target(actor, target): continue
		var separation := target.global_position.distance_squared_to(first.global_position)
		if separation < distance and has_line_of_sight(first.global_position + Vector3.UP, target.global_position + Vector3.UP):
			nearest = target
			distance = separation
	if nearest == null: return
	damage_target(actor, nearest, float(int(damage) / 2), nearest.global_position)
	var effect := {"type": "shot", "peer": actor.peer_id, "from": first.global_position + Vector3.UP,
		"to": nearest.global_position + Vector3.UP, "style": "sniper_legacy_hd", "tint": Color.VIOLET}
	_play_effect(effect)
	NetworkSession.broadcast_effect(effect)

func _fire_impulse(actor: Node3D, aim: Dictionary, damage: float) -> void:
	var totals := {}
	var data: Dictionary = actor.current_weapon
	var source_range := maxf(0.01, float(data.range))
	var spread := float(data.get("spread", 0.0))
	for pellet in 8:
		var direction := (Vector3(aim.direction) + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))).normalized()
		var endpoint: Vector3 = aim.origin + direction * 1000.0
		var query := PhysicsRayQueryParameters3D.create(aim.origin, endpoint, 7)
		query.exclude = [actor.get_rid()]
		var hit_ids := {}
		for intersection in 128:
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty(): break
			var target: Node = EnemyHitGeometry.resolve(hit.collider)
			if not is_instance_valid(target) or not target.has_method("take_damage"):
				endpoint = hit.position
				break
			var excluded := query.exclude
			excluded.append(hit.rid)
			query.exclude = excluded
			if hit_ids.has(target) or not can_damage_target(actor, target): continue
			hit_ids[target] = true
			var amount := float(int(damage))
			# AdvancedShotGun: enemies receive 1/8 per ray with range falloff;
			# VS players/gifts accumulate full ray damage then scale total .35.
			if not "peer_id" in target and not target in gifts.values():
				var distance := actor.global_position.distance_to(target.global_position)
				amount = float(int(damage * maxf(0.0, 1.0 - maxf(0.0, distance - source_range) * 0.5 / source_range) * 0.125))
			totals[target] = float(totals.get(target, 0.0)) + amount
		var effect := {"type": "shot", "peer": actor.peer_id, "from": actor.muzzle.global_position,
			"to": endpoint, "style": "shotgun", "tint": data.get("color", Color.VIOLET)}
		_play_effect(effect)
		NetworkSession.broadcast_effect(effect)
	for target: Node3D in totals:
		var amount := float(totals[target])
		if "peer_id" in target or target in gifts.values(): amount = float(int(amount * 0.35))
		damage_target(actor, target, amount, target.global_position)

func _fire_projectile_pattern(actor: Node3D, aim: Dictionary, kind: String, damage: float) -> void:
	var data: Dictionary = actor.current_weapon.duplicate()
	data.key = actor.current_weapon_id
	var direction: Vector3 = (Vector3(aim.target) - actor.muzzle.global_position).normalized()
	if kind == "grenade": direction = (direction + Vector3.UP * 0.18).normalized()
	var directions: Array[Vector3] = [direction]
	if data.key == "gun29":
		directions = [direction.rotated(Vector3.UP, deg_to_rad(5)), direction, direction.rotated(Vector3.UP, deg_to_rad(-5))]
	elif data.key == "gun42":
		directions = [direction.rotated(Vector3.UP, deg_to_rad(5 + rng.randi_range(0, 1))), direction.rotated(Vector3.UP, deg_to_rad(-5 + rng.randi_range(-2, -1))), direction.rotated(Vector3.RIGHT, deg_to_rad(5 + rng.randi_range(0, 1))), direction, direction.rotated(Vector3.RIGHT, deg_to_rad(-5 + rng.randi_range(-2, -1)))]
	var variant := 0
	if data.key == "gun41":
		var now := Time.get_ticks_msec()
		if not actor.has_meta("joke_poison_time"): actor.set_meta("joke_poison_time", now)
		if now - int(actor.get_meta("joke_poison_time")) >= 5000:
			variant = 2
			actor.set_meta("joke_poison_time", now)
		else: variant = 1 if rng.randi_range(0, 99) < 30 else 0
	var blast_radius := 3.0 if kind == "windblade" else float(data.get("splash", 0.0))
	if pvp_arena: blast_radius *= 0.5 if kind in ["arrow", "tracking", "spring"] else 0.67
	for travel: Vector3 in directions:
		launch_projectile(actor, actor.muzzle.global_position, travel, 30.0 if kind == "windblade" else float(data.get("speed", 25.0)), damage, blast_radius, kind, data, variant)

func launch_projectile(source: Node, origin: Vector3, direction: Vector3, speed: float, damage: float, splash: float, kind: String, weapon: Dictionary = {}, variant := 0) -> Node3D:
	var shot := NetProjectile.new()
	projectile_sequence += 1
	shot.network_id = projectile_sequence
	shot.position = origin
	var profile := weapon.duplicate()
	profile.pvp = pvp_arena
	shot.configure_network(source, direction, maxf(1.0, speed), damage, splash, kind, profile, variant)
	add_child(shot)
	projectiles[shot.network_id] = shot
	return shot

func apply_explosion(source: Node, at: Vector3, damage: float, radius: float, ignore_walls := false, category: Variant = null) -> void:
	for target: Node in actors.values() + enemies.values() + gifts.values():
		if not is_instance_valid(target):
			continue
		var center: Vector3 = target.position + Vector3.UP
		if center.distance_to(at) <= radius and (ignore_walls or has_line_of_sight(at + Vector3.UP * 0.05, center)):
			damage_target(source, target, damage, at, category)

func network_explosion(at: Vector3, radius: float) -> void:
	var effect := {"type": "explosion", "position": at, "radius": radius}
	_play_effect(effect)
	NetworkSession.broadcast_effect(effect)

func _play_effect(effect: Dictionary) -> void:
	if effect.type == "shot":
		spawn_tracer(effect.from, effect.to, effect.get("tint", Color.CYAN), str(effect.get("style", "legacy")))
	elif effect.type == "fire":
		spawn_muzzle_effect(effect.from, effect.direction, effect.style)
		if str(effect.style) == "machinegun": spawn_machinegun_muzzle_fx(effect.from, effect.direction)
		var id := int(effect.peer)
		if not NetworkSession.is_host() and actors.has(id):
			actors[id].shoot_pose_left = 0.15
			actors[id]._play_weapon_fire_sound()
	elif effect.type == "explosion":
		spawn_explosion(effect.position, Color.ORANGE, effect.radius)
	elif effect.type == "projectile_impact":
		var key := str(effect.get("weapon", ""))
		if OriginalWeaponEffect.catalog().has(key):
			var record: Array = OriginalWeaponEffect.catalog()[key]
			var visual := OriginalWeaponEffect.create(str(record[1]), true)
			if visual != null:
				add_child(visual)
				visual.global_position = effect.position
			if not str(record[3]).is_empty(): AudioDirector.play_3d(OriginalWeaponEffect.ROOT + "audio/" + str(record[3]), effect.position, -1.0)
		else:
			spawn_explosion(effect.position, effect.get("tint", Color.ORANGE), effect.radius)
	elif effect.type == "weapon_area":
		var visual := OriginalWeaponEffect.create("Effect/SatanMachine/joke_force", true)
		if visual != null:
			visual.lifetime = 4.0
			add_child(visual)
			visual.global_position = effect.position + Vector3.UP * 0.05
	elif effect.type == "telegraph" and enemies.has(int(effect.enemy)):
		enemies[int(effect.enemy)].source_telegraph(effect.position, effect.radius, effect.lifetime)
	elif effect.type == "pickup" and actors.has(int(effect.peer)):
		var actor: Node3D = actors[int(effect.peer)]
		var visual := preload("res://scripts/game/original_pickup_visual.gd").create("effect_pick_gold_001" if effect.kind == "credits" else "effect_pick_energy_001", true)
		actor.add_child(visual)
		visual.position = Vector3.UP
		AudioDirector.play_3d("pickup/pickup_money01.wav" if effect.kind == "credits" else "pickup/pickup_energy.wav", actor.global_position, -2.0)

func _build_objectives() -> void:
	if NetworkSession.room.mode in ["CTF_FFA", "CTF_TDM"]:
		flag_visual = Node3D.new()
		add_child(flag_visual)
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.12
		cylinder.bottom_radius = 0.12
		cylinder.height = 2.4
		mesh.mesh = cylinder
		mesh.position.y = 1.2
		mesh.material_override = _material(Color.GOLD, 0.5, 0.2, Color.YELLOW)
		flag_visual.add_child(mesh)
		var banner := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.3, 0.8, 0.06)
		banner.mesh = box
		banner.position = Vector3(0.65, 2.0, 0)
		banner.material_override = mesh.material_override
		flag_visual.add_child(banner)
	if NetworkSession.room.mode == "CMI":
		var points := _marker_positions(stage_metadata.get("markers", {}).get("GiftSpawn", []))
		if points.is_empty():
			points = _marker_positions(stage_metadata.get("markers", {}).get("FlagSpawn", []))
		if points.is_empty():
			points = [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4), Vector3.ZERO]
		for i in range(mini(15, points.size())):
			var gift := NetGift.new()
			gift.network_id = i
			gift.kind = i % 5
			gift.health = Rules.GIFT_HP[gift.kind]
			gift.position = points[i]
			add_child(gift)
			gifts[i] = gift

func _tick_objectives(delta: float) -> void:
	if rules.ended:
		return
	if rules.flag_carrier == 0 and rules.flag_respawn <= 0.0 and NetworkSession.room.mode in ["CTF_FFA", "CTF_TDM"]:
		for id: int in actors:
			if not actors[id].dead and actors[id].position.distance_to(rules.flag_position) < 2.0:
				if rules.pick_flag(id):
					break
	for gift: Node in gifts.values():
		gift.host_tick(delta)

func _update_objective_visual() -> void:
	if flag_visual != null:
		var carrier := int(rules_view.get("flag_carrier", 0))
		flag_visual.position = actors[carrier].position + Vector3.UP if actors.has(carrier) else Vector3(rules_view.get("flag_position", Vector3.ZERO))
		flag_visual.visible = float(rules_view.get("flag_respawn", 0.0)) <= 0.0
	for id: int in actors:
		var actor = actors[id]
		var prefix := "VIP • " if int(rules_view.get("vip_id", 0)) == id else ""
		actor.name_tag.text = prefix + str(actor.profile.name)

func make_snapshot() -> Dictionary:
	var actor_states := {}
	var enemy_states := {}
	var projectile_states := {}
	var gift_states := {}
	var effect_states := {}
	var pickup_states := {}
	for id: int in actors:
		actor_states[id] = actors[id].network_state()
		actor_states[id].actions = network_actions.snapshot_actor(actors[id])
	for id: int in enemies:
		if is_instance_valid(enemies[id]):
			enemy_states[id] = enemies[id].network_state()
	for id: int in projectiles:
		projectile_states[id] = projectiles[id].network_state()
	for id: int in gifts:
		gift_states[id] = gifts[id].network_state()
	for id: int in pickups:
		pickup_states[id] = pickups[id].network_state()
	for id: int in source_effects:
		var record: Dictionary = source_effects[id]
		var effect: Node3D = record.node
		if not is_instance_valid(effect): continue
		effect_states[id] = {"description": record.description, "enemy": record.enemy,
			"transform": effect.transform, "scale": effect.get_child(0).scale if effect.get_child_count() > 0 else Vector3.ONE}
	return {"tick": tick_number, "rules": rules.snapshot(), "actors": actor_states,
		"enemies": enemy_states, "projectiles": projectile_states, "gifts": gift_states,
		"source_effects": effect_states, "pickups": pickup_states,
		"rewards": reward_ledgers.duplicate(true), "run_id": "enet:%s:%d" % [NetworkSession.room_id, NetworkSession.generation]}

func _apply_snapshot(state: Dictionary) -> void:
	rules_view = state.rules
	if bool(rules_view.ended) and NetworkSession.phase == "finished":
		_prepare_settlement(state)
	if NetworkSession.is_host():
		return
	completed = bool(rules_view.ended)
	for id: int in actors.keys():
		if not state.actors.has(id):
			actors[id].queue_free()
			actors.erase(id)
		else:
			actors[id].apply_network_state(state.actors[id])
			network_actions.apply_actor_state(actors[id], state.actors[id].get("actions", {}))
	for id: int in state.enemies:
		var data: Dictionary = state.enemies[id]
		if not enemies.has(id) or not is_instance_valid(enemies[id]):
			if data.dead:
				continue
			var enemy = NetBoss.new() if data.has("boss_index") else NetEnemy.new()
			enemy.network_id = id
			if data.has("boss_index"):
				enemy.configure_boss(player, int(data.boss_index), bool(data.assist))
			else:
				if bool(data.get("original", false)):
					enemy.configure_original(player, int(data.source_id))
				else:
					enemy.configure(player, str(data.kind), float(data.maximum))
			enemy.position = data.position
			add_child(enemy)
			enemies[id] = enemy
		enemies[id].apply_network_state(data)
	for id: int in enemies.keys():
		if not state.enemies.has(id):
			if is_instance_valid(enemies[id]):
				enemies[id].queue_free()
			enemies.erase(id)
	for id: int in state.projectiles:
		var data: Dictionary = state.projectiles[id]
		if not projectiles.has(id):
			var shot := NetProjectile.new()
			shot.network_id = id
			shot.kind = data.kind
			shot.visual_variant = str(data.get("weapon", ""))
			shot.tint = data.get("tint", Color.ORANGE)
			shot.hostile = bool(data.get("hostile", false))
			shot.joke_variant = int(data.get("joke_variant", 0))
			shot.position = data.position
			add_child(shot)
			projectiles[id] = shot
		projectiles[id].apply_network_state(data)
	for id: int in projectiles.keys():
		if not state.projectiles.has(id):
			projectiles[id].queue_free()
			projectiles.erase(id)
	for id: int in state.gifts:
		if gifts.has(id):
			gifts[id].health = state.gifts[id].health
			gifts[id].respawn_left = state.gifts[id].respawn
			gifts[id].set_active(float(state.gifts[id].respawn) <= 0.0)
	_apply_source_effects(state.get("source_effects", {}))
	for id: int in state.get("pickups", {}):
		var data: Dictionary = state.pickups[id]
		if not pickups.has(id):
			var pickup := NetPickup.new()
			pickup.network_id = id
			pickup.configure(data.kind, data.amount)
			add_child(pickup)
			pickup.position = data.position
			pickups[id] = pickup
	for id: int in pickups.keys():
		if not state.get("pickups", {}).has(id):
			pickups[id].queue_free()
			pickups.erase(id)
	_update_objective_visual()

func _apply_source_effects(states: Dictionary) -> void:
	for id: int in states:
		var data: Dictionary = states[id]
		if not source_effects.has(id):
			var description: Dictionary = data.description
			var effect: Node3D
			match str(description.get("effect_type", "projectile")):
				"hazard": effect = preload("res://scripts/game/enemy_source_hazard.gd").new()
				"beam": effect = preload("res://scripts/game/enemy_source_beam.gd").new()
				_: effect = preload("res://scripts/game/enemy_source_projectile.gd").new()
			for key: String in description:
				if key not in ["position", "effect_type"]: effect.set(key, description[key])
			effect.source = enemies.get(int(data.enemy))
			add_child(effect)
			# Replicas only display the host's effect. They never simulate hits,
			# poison timers, slows, gift drops or independently expiring beams.
			effect.set_physics_process(false)
			source_effects[id] = {"node": effect}
		var effect: Node3D = source_effects[id].node
		effect.transform = data.transform
		if effect.get_child_count() > 0: effect.get_child(0).scale = data.scale
	for id: int in source_effects.keys():
		if not states.has(id):
			source_effects[id].node.queue_free()
			source_effects.erase(id)

func _prepare_settlement(state: Dictionary) -> void:
	if not local_receipt.is_empty() or not active:
		return
	if str(state.rules.result.get("reason", "")) == "spawn_configuration_failed": return
	var expected := "enet:%s:%d" % [NetworkSession.room_id, NetworkSession.generation]
	if str(state.get("run_id", "")) != expected:
		return
	var id := NetworkSession.local_id()
	var earned: Dictionary = state.get("rewards", {}).get(id, {})
	if earned.is_empty():
		return
	local_receipt = earned.duplicate()
	local_receipt.run_id = expected + ":%d" % id
	local_receipt.score = int(state.rules.players.get(id, {}).get("score", 0))
	local_receipt.kills = progress.kills
	local_receipt.time = float(state.rules.elapsed)
	local_receipt.max_combo = progress.max_combo
	local_receipt.campaign_progress = false
	local_receipt.boss_encounter = NetworkSession.room.mode == "Boss"
	local_receipt.victory = id in state.rules.result.winners and not bool(state.rules.result.draw)
	if GameState.settled_runs.has(local_receipt.run_id):
		settlement_result = GameState.settled_runs[local_receipt.run_id].duplicate(true)
		return
	career_before_result = GameState.career.serialize()
	progress.finish(id in state.rules.result.winners, int(local_receipt.score))
	career_after_result = GameState.career.serialize()
	GameState.career.load_data(career_before_result)
	settle_local_result()

func settle_local_result() -> void:
	if local_receipt.is_empty() or bool(settlement_result.get("saved", false)):
		return
	settlement_result = GameState.settle_solo_run(int(NetworkSession.room.level), -1, bool(local_receipt.victory), local_receipt, career_after_result)
