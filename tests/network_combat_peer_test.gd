extends "res://tests/network_peer_test.gd"
## Bounded real ENet regression, source projectile behavior on the host and
## matching harmless replicas/HP/waves on the client. No extra player bots.
var combat_started := false
var combat_finished := false
var complete_received := false
var seen_kinds: Dictionary = {}
var seen_robot := false
var seen_ufo_altitude := false
var seen_wave := false
var seen_wave_growth := false
var seen_poison := false
var seen_health_change := false
var checked_replica_authority := false
var previous_health: Dictionary = {}
var checks := 0
var shooter: Node3D
var opponent: Node3D

func _ready() -> void:
	super._ready()
	NetworkSession.snapshot_received.connect(_observe_combat)
	NetworkSession.effect_received.connect(func(effect: Dictionary):
		if str(effect.get("type", "")) == "weapon_area": seen_poison = true
		if str(effect.get("type", "")) == "combat_test_complete": complete_received = true
	)

func _process(delta: float) -> void:
	if done: return
	elapsed += delta
	if elapsed > 40.0:
		_finish(false, "combat regression timeout phase=%s checks=%d" % [NetworkSession.phase, checks])
		return
	if not is_instance_valid(world) or not world.is_node_ready() or world.player == null: return
	world.player.automation_command = {"move": Vector2.ZERO, "aim": Vector2.ZERO, "buttons": 0, "slot": 0}
	if NetworkSession.phase != "playing": return
	if role == "client" and not checked_replica_authority and not world.projectiles.is_empty():
		var shot: Node3D = world.projectiles.values()[0]
		var before := float(world.player.health)
		shot._impact(world.player.position, world.player)
		if not _check(not shot.is_queued_for_deletion() and is_equal_approx(world.player.health, before), "replica executed impact/damage"): return
		checked_replica_authority = true
	if role == "host" and not combat_started:
		combat_started = true
		_exercise_combat.call_deferred()
	elif role == "client" and complete_received:
		var expected := ["arrow", "spring", "windblade", "tracking", "ricochet", "grenade", "fly_grenade"]
		for kind: String in expected:
			if not _check(seen_kinds.has(kind), "client missed projectile %s" % kind): return
		if not _check(checked_replica_authority and seen_robot and seen_ufo_altitude and seen_wave and seen_wave_growth and seen_poison and seen_health_change, "missing robot/UFO/wave/poison/HP replication"): return
		print("NETWORK_COMBAT_PASS role=client actualENet source visuals, robot/UFO, growing wave, slime, HP; replicas cannot damage")
		_finish(true, "combat replica assertions=%d" % checks)

func _observe_combat(state: Dictionary) -> void:
	if role != "client" or done: return
	for row: Dictionary in state.get("projectiles", {}).values():
		seen_kinds[str(row.kind)] = true
		seen_robot = seen_robot or bool(row.get("robot", false))
		seen_ufo_altitude = seen_ufo_altitude or (row.kind == "fly_grenade" and Vector3(row.position).y > 6.0)
	for id: int in state.get("actors", {}):
		var row: Dictionary = state.actors[id]
		seen_health_change = seen_health_change or (previous_health.has(id) and float(previous_health[id]) > float(row.health))
		previous_health[id] = row.health
		for visual: Dictionary in row.get("actions", {}).get("power", {}).get("visuals", []):
			if str(visual.kind) == "impact":
				seen_wave = true
				seen_wave_growth = seen_wave_growth or Vector3(visual.get("scale", Vector3.ZERO)).x > 0.55

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value: _finish(false, message)
	return value

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _clear_projectiles() -> void:
	for shot: Node in world.projectiles.values(): shot.queue_free()
	world.projectiles.clear()

func _launch(kind: String, at: Vector3, travel: Vector3, key: String, amount := 10.0, radius := 1.5, variant := 0) -> Node3D:
	return world.launch_projectile(shooter, at, travel, 12.0, amount, radius, kind, {"key": key}, variant)

func _exercise_combat() -> void:
	shooter = world.actors[1]
	for id: int in world.actors:
		if id != 1: opponent = world.actors[id]
	for actor: Node in world.actors.values():
		actor.set_physics_process(false)
		actor.max_health = 100000.0
		actor.health = 100000.0
		actor.shield = 0.0
		actor.invulnerable_left = 0.0
		actor.armor_skills = {}
	shooter.position = Vector3(0, 0, 8)
	opponent.position = Vector3(0, 0, -12)
	await _wait(0.1)
	for spec: Array in [["gun29", "arrow", 3], ["gun42", "spring", 5], ["gun33", "sword", 1]]:
		shooter.equip_weapon(spec[0], false)
		world.fire_weapon(shooter, spec[1])
		if not _check(world.projectiles.size() == spec[2], "source multi-shot/windblade missing: %s" % spec[0]): return
		for shot: Node in world.projectiles.values():
			if not _check(shot is WarfareProjectile and shot.visual_variant == spec[0], "projectile did not reuse source class/visual"): return
			if spec[0] == "gun33" and not _check(is_equal_approx(shot.damage, MatchRules.vs_damage(shooter._current_weapon_damage(), "sword") * 0.2), "windblade retained melee-only VS damage boost"): return
			if spec[0] == "gun42" and not _check(is_equal_approx(shot.damage, MatchRules.vs_damage(shooter._current_weapon_damage(), "tracking")), "Spring omitted source TrackingGun VS multiplier"): return
			if spec[0] == "gun42" and not _check(is_equal_approx(shot.splash_radius, float(shooter.current_weapon.splash) * 0.5) and shooter._weapon_skill_key() == "tracking_boost", "Spring lost source TrackingGun radius/armor bonus"): return
		await _wait(0.25)
		_clear_projectiles()
	opponent.position = Vector3(2, 0, -12)
	var tracking := _launch("tracking", Vector3(0, 1, 0), Vector3.FORWARD, "gun36")
	await _wait(0.75)
	if not _check(is_instance_valid(tracking) and tracking.speed > 13.0 and tracking.direction.x > 0.0 and tracking.homing_target == opponent, "tracking did not lock/accelerate/steer"): return
	_clear_projectiles()
	opponent.position = Vector3(-12, 0, -12)
	world._add_static_box("CombatBounceWall", Vector3(0.5, 20, 40), Vector3(3, 9, 0), world._material(Color.GRAY, 1.0, 0.0))
	for kind: String in ["ricochet", "spring"]:
		var bounce := _launch(kind, Vector3(0, 5, 0), Vector3(1, 0, -1).normalized(), "gun37" if kind == "ricochet" else "gun42")
		await _wait(0.45)
		if not _check(is_instance_valid(bounce) and bounce.direction.x < 0.0 and bounce.bounces_left == 2, "%s did not reflect on actual wall" % kind): return
		_clear_projectiles()
	var grenade := _launch("grenade", Vector3(0, 10, 0), Vector3.RIGHT, "gun14")
	await _wait(0.2)
	if not _check(is_instance_valid(grenade) and grenade.wall_fuse > 0.0 and grenade.grenade_velocity.x < 0.0, "grenade wall bounce/fuse missing"): return
	await _wait(1.3)
	if not _check(not is_instance_valid(grenade), "grenade did not detonate after VS wall fuse"): return
	world.get_node("CombatBounceWall").queue_free()
	opponent.position = Vector3(0, 0, -2)
	await _wait(0.1)
	var before := float(opponent.health)
	var blade := _launch("windblade", Vector3(0, 1, 0), Vector3.FORWARD, "gun33")
	await _wait(0.3)
	if not _check(is_instance_valid(blade) and opponent.health < before, "windblade stopped at first target or failed damage"): return
	_clear_projectiles()
	# Persistent zones reject team damage through the same production route.
	world.rules.players[opponent.peer_id].team = 0
	before = opponent.health
	var friendly := _launch("fly_grenade", Vector3(0, 8, -2), Vector3.FORWARD, "gun45")
	friendly._impact(Vector3(0, 0, -2), null)
	await _wait(1.0)
	if not _check(is_equal_approx(opponent.health, before), "rain damaged a teammate"): return
	world.rules.players[opponent.peer_id].team = 1
	opponent.position = Vector3(0, 0, -8)
	before = opponent.health
	_launch("fly_grenade", Vector3(0, 1, 0), Vector3.FORWARD, "gun45", 10.0, 4.0)
	await _wait(3.5)
	if not _check(is_equal_approx(before - opponent.health, 40.0), "UFO did not ascend and apply exactly four rain hits: %f" % (before - opponent.health)): return
	_clear_projectiles()
	opponent.position = Vector3(0, 0, -4)
	shooter.profile.weapon_levels = {"gun41": 4}
	await _wait(0.1)
	before = opponent.health
	var robot := _launch("grenade", Vector3(0, 0.2, 0), Vector3.DOWN, "gun41", 10.0, 3.0, 2)
	await _wait(0.1)
	if not _check(is_instance_valid(robot) and robot.joke_robot, "Joke grenade did not become source robot on floor"): return
	await _wait(4.5)
	if not _check(is_equal_approx(before - opponent.health, 34.0), "Joke impact plus six level-4 VS slime ticks incorrect: %f" % (before - opponent.health)): return
	var area := preload("res://scripts/network/network_weapon_area.gd").new()
	area.source = shooter
	area.kind = "slime"
	area.radius = 3.5
	area.damage = 4.0
	area.ticks_left = 1
	area.delay = 0.1
	area.position = opponent.position + Vector3(3.4, 0, 0)
	world.add_child(area)
	before = opponent.health
	await _wait(0.15)
	if not _check(is_equal_approx(before - opponent.health, 4.0), "slime lost original 3.5-unit collider boundary"): return
	# Source impact box is narrower than the old 3-unit sphere. Hold its
	# movement still to exercise resize and 0.3 s re-hit on one real player.
	var power: Node = shooter.armor_power_controller
	power.available_skill_indices.assign([6, 7])
	opponent.position = Vector3(2.6, 0, 6.7)
	before = opponent.health
	if not _check(power.activate_authoritative(6), "host impact activation rejected"): return
	power._waves[0].speed = 0.0
	await _wait(0.25)
	if not _check(is_equal_approx(before, opponent.health), "impact still uses oversized 3-unit sphere"): return
	opponent.position.x = 1.0
	await _wait(0.15)
	var first := float(opponent.health)
	if not _check(first < before, "source impact box missed intersecting opponent"): return
	await _wait(0.45)
	if not _check(opponent.health < first and float(power._waves[0].source_scale) > 0.55, "impact growth/repeated source penetration missing"): return
	if not capture_path.is_empty():
		await _capture()
	power.cancel_all_active(true)
	opponent.position = Vector3(0, 0, 4)
	before = opponent.health
	var speed_before := float(opponent.move_speed)
	if not _check(power.activate_authoritative(7), "host track activation rejected"): return
	await _wait(0.5)
	if not _check(is_equal_approx(before - opponent.health, 1.0) and opponent.move_speed < speed_before and power._waves.is_empty(), "Track must damage once for 1, mark, and disappear"): return
	power.cancel_all_active(true)
	await _exercise_review_cases()
	if done: return
	await _wait(0.3)
	print("NETWORK_COMBAT_PASS role=host checks=%d spread, steering, reflection, penetration, wall fuse, UFO rain, robot/slime, friendly fire, source wave shape/re-hit/mark" % checks)
	NetworkSession.broadcast_effect({"type": "combat_test_complete"})
	for frame in 90:
		if saw_disconnect: break
		await get_tree().process_frame
	if not _check(saw_disconnect, "client did not confirm combat snapshots"): return
	_finish(true, "combat assertions=%d and client disconnect" % checks)

func _make_collision_enemy(at: Vector3) -> Node3D:
	# Real network enemy/damage/replica, with a broad test collider so the eight
	# zero-spread rays test damage arithmetic independently of animation poses.
	world._spawn_network_enemy("crawler", 0)
	var enemy: Node3D = world.enemies.values().back()
	enemy.set_physics_process(false)
	enemy.position = at
	enemy.health = 100000.0
	enemy.max_health = enemy.health
	enemy.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 1)
	shape.shape = box
	shape.position.y = 1.5
	enemy.add_child(shape)
	return enemy

func _exercise_review_cases() -> void:
	shooter.equip_weapon("gun11", false)
	opponent.position = Vector3(0, 0, 1)
	opponent.armor_skills = {"rpg_defence": -0.75, "grenade_defence": -0.5, "assault_defence": 0.0}
	await _wait(0.1)
	var before := float(opponent.health)
	_launch("rocket", Vector3(0, 1, 3), Vector3.FORWARD, "gun11", 80.0, 0.0)
	shooter.equip_weapon("gun00", false)
	await _wait(0.25)
	if not _check(is_equal_approx(before - opponent.health, 20.0), "in-flight weapon switch changed RPG resistance category"): return
	var spring := _launch("spring", Vector3(0, 10, 0), Vector3.FORWARD, "gun42")
	if not _check(spring.damage_category == "tracking_defence", "Spring lost original TrackingGun damage type"): return
	_clear_projectiles()
	var area := preload("res://scripts/network/network_weapon_area.gd").new()
	area.source = shooter
	area.kind = "slime"
	area.radius = 3.5
	area.damage = 8.0
	area.ticks_left = 1
	area.delay = 0.1
	area.position = opponent.position
	world.add_child(area)
	before = opponent.health
	await _wait(0.15)
	if not _check(is_equal_approx(before - opponent.health, 4.0), "persistent area used newly equipped rifle resistance"): return
	opponent.armor_skills.assault_defence = -1.0
	before = opponent.health
	shooter.armor_power_controller._deal_enemy_damage(opponent, 100.0, "attack_shield")
	if not _check(is_equal_approx(before - opponent.health, MatchRules.vs_damage(100.0, "armor_power")) and shooter.damage_category_stack.is_empty(), "armor skill inherited equipped weapon defence or leaked category scope"): return
	opponent.armor_skills = {}
	opponent.position = Vector3(15, 0, 0)
	var first := _make_collision_enemy(Vector3(0, 0, 2))
	var second := _make_collision_enemy(Vector3(0, 0, -12))
	shooter.equip_weapon("gun31", false)
	shooter.current_weapon.kind = "shockwave"
	shooter.current_weapon.range = 10.0
	shooter.current_weapon.spread = 0.0
	var aim := {"origin": Vector3(0, 1, 8), "direction": Vector3.FORWARD}
	await _wait(0.1)
	world._fire_impulse(shooter, aim, 80.0)
	if not _check(is_equal_approx(100000.0 - first.health, 80.0) and is_equal_approx(100000.0 - second.health, 40.0), "IMPULSE eight rays must penetrate enemies, total 1x near and distance falloff far"): return
	world._add_static_box("CombatShotWall", Vector3(8, 10, 0.5), Vector3(0, 4, -4), world._material(Color.GRAY, 1.0, 0.0))
	await _wait(0.1)
	before = second.health
	world._fire_impulse(shooter, aim, 80.0)
	if not _check(is_equal_approx(second.health, before), "IMPULSE passed through terrain"): return
	world.get_node("CombatShotWall").queue_free()
	await _wait(0.1)
	shooter.equip_weapon("gun43", false)
	shooter.current_weapon.spread = 0.0
	var reflected := float(int(MatchRules.vs_damage(shooter._current_weapon_damage(), "reflection")) / 2)
	before = second.health
	world.fire_weapon(shooter, "hitscan")
	if not _check(is_equal_approx(before - second.health, reflected), "Reflection did not strike nearest visible second enemy for half damage"): return
	world._add_static_box("CombatShotWall", Vector3(8, 10, 0.5), Vector3(0, 4, -4), world._material(Color.GRAY, 1.0, 0.0))
	await _wait(0.1)
	before = second.health
	world.fire_weapon(shooter, "hitscan")
	if not _check(is_equal_approx(second.health, before), "Reflection crossed wall"): return
	world.get_node("CombatShotWall").queue_free()
	# Real second peer can be put on the host's team without another process.
	world.rules.players[opponent.peer_id].team = 0
	opponent.position = Vector3(0, 0, 4)
	before = opponent.health
	await _wait(0.1)
	world.fire_weapon(shooter, "hitscan")
	world._fire_impulse(shooter, aim, 80.0)
	if not _check(is_equal_approx(opponent.health, before), "special hitscan damaged teammate"): return
	world.rules.players[opponent.peer_id].team = 1
	before = opponent.health
	shooter.current_weapon.spread = 0.0
	world._fire_impulse(shooter, aim, 80.0)
	if not _check(is_equal_approx(before - opponent.health, float(int(80.0 * 8.0 * 0.35))), "IMPULSE VS total must apply source .35 after eight full ray hits"): return
	opponent.position = Vector3(20, 0, 0)
	first.position = Vector3(0, 0, -1)
	second.position = Vector3(7, 0, -1)
	world._add_static_box("CombatSearchWall", Vector3(2, 20, 0.5), Vector3(0, 9, 1), world._material(Color.GRAY, 1.0, 0.0))
	await _wait(0.1)
	var ufo := _launch("fly_grenade", Vector3(0, 8, 3), Vector3.FORWARD, "gun45")
	await _wait(0.25)
	if not _check(is_instance_valid(ufo) and ufo.homing_target == second, "UFO let nearest occluded enemy hide a farther visible target"): return
	_clear_projectiles()
	world.get_node("CombatSearchWall").queue_free()
	for enemy: Node in world.enemies.values(): enemy.queue_free()
	world.enemies.clear()
