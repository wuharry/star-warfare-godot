extends Node3D

const Catalog = preload("res://scripts/core/monster_catalog.gd")
const NormalBrain = preload("res://scripts/game/enemy_source_brain.gd")
const Projectile = preload("res://scripts/game/enemy_source_projectile.gd")

class Target extends WarfarePlayer:
	var received: Array[float] = []
	var knock_steps: Array[float] = []
	func get_enemy_knockback_forward() -> Vector3:
		return Vector3.FORWARD.rotated(Vector3.UP, body_yaw)
	func apply_enemy_knockback(source_step: float) -> void:
		knock_steps.append(source_step)
	func _ready() -> void:
		health = 1000000.0
		max_health = health
		collision_layer = 4
		collision_mask = 1
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.46
		capsule.height = 1.82
		shape.shape = capsule
		shape.position.y = 0.91
		add_child(shape)
		set_physics_process(false)
	func take_damage(amount: float, _point := Vector3.ZERO, _attacker: Node = null) -> void:
		received.append(amount)
		health -= amount

class KnockBasisTarget extends Node3D:
	var dead := false
	var knock_steps: Array[float] = []
	func apply_enemy_knockback(source_step: float) -> void:
		knock_steps.append(source_step)

# Small deterministic fixture isolates normal state timing from animation length.
# Actual source model/animation loading is tested separately for every identity.
class LogicActor extends CharacterBody3D:
	var hits: Array[float] = []
	var shots: Array[int] = []
	var direction := Vector3.FORWARD
	var in_cone := true
	func source_clip_length(_clip: String, fallback: float) -> float: return fallback
	func source_target_direction() -> Vector3: return direction
	func _face_planar_direction(_direction: Vector3) -> void: pass
	func source_has_rush_clearance() -> bool: return true
	func source_target_in_cone(_reach: float, _angle: float) -> bool: return in_cone
	func source_damage_target(amount: float) -> void: hits.append(amount)
	func source_normal_shot(_profile: Dictionary, id: int) -> void: shots.append(id)

var failures: Array[String] = []
var checks := 0
var victim: Target


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("ENEMY SOURCE: " + message)


func _run() -> void:
	if not GameState.save_path.begins_with("user://star_warfare_test_"):
		push_error("Run with -- --test-profile=enemy_source_runtime_<unique_name>")
		get_tree().quit(1)
		return
	GameState.settings.difficulty = "recruit"
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	collision.shape = box
	collision.position.y = -0.5
	floor_body.add_child(collision)
	add_child(floor_body)
	victim = Target.new()
	victim.position = Vector3(0.0, 0.0, -2.0)
	add_child(victim)
	await get_tree().physics_frame
	_test_catalog()
	_test_legacy_contract()
	_test_restored_models()
	_test_normal_logic()
	_test_melee_and_boomer()
	_test_knockback_contract()
	await _test_projectiles()
	_test_dragon()
	_test_mantis_and_twins()
	_test_ground_bosses()
	_test_machine()
	await _test_hazards()
	# These deterministic tests execute several deaths in a single frame. Let
	# newly queued one-shots enter AudioServer before stopping their players.
	await get_tree().create_timer(0.1).timeout
	for audio in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	AudioDirector.stop_all_sfx()
	# Allow queued AudioStreamPlayer3D updates and the audio mixer to drain
	# after stopping, before destroying the SceneTree's stream references.
	await get_tree().physics_frame
	await get_tree().create_timer(0.25).timeout
	print("ENEMY_SOURCE_RUNTIME_TEST_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_catalog() -> void:
	_check(Catalog.normal_entries().size() == 8, "all eight normal species are represented")
	_check(Catalog.normal_entries(true).size() == 8, "all normal models are exported")
	for id in range(15):
		var spec := Catalog.runtime_spec(id)
		_check(spec.id == id and Catalog.id_for_kind(str(spec.kind)) == id, "numeric identity round trip %d" % id)
		_check(spec.source_enemy_type == id and spec.table_row_id == id, "Enemy.LoadConfig uses EnemyType as table row %d" % id)
		_check(bool(spec.spawnable) and spec.blockers.is_empty(), "availability must be honest for %d" % id)
	_check(Catalog.for_kind("typo").is_empty() and Catalog.runtime_spec(-1).is_empty() and Catalog.runtime_spec(15).is_empty(), "invalid identity cannot become drone")
	var first := Catalog.runtime_spec(0, 1)
	_check(first.hp == 56 and first.damage == 77 and first.credits == 96 and first.experience == 11, "difficulty 1 applies source coefficients with integer truncation")
	var second := Catalog.runtime_spec(0, 2)
	_check(second.hp == 69 and second.damage == 85 and second.credits == 103 and second.experience == 12, "difficulty 2 multiplies rather than adds")
	var capped := Catalog.runtime_spec(0, 50)
	_check(capped.hp == 3600 and capped.damage == 4900, "source HP and damage caps")
	var elite := Catalog.runtime_spec(0, 0, true)
	_check(elite.hp == 135 and elite.speed == 6.0 and elite.damage == 140 and elite.credits == 270 and elite.experience == 30, "source elite modifiers")
	_check(elite.spawnable and str(elite.model_path).contains("_elite"), "elite must not silently borrow normal skin")
	var tank := Catalog.runtime_spec(4, 0, true)
	_check(not tank.elite and tank.damage == 250 and tank.attack_profiles[0].damage == 200, "source spawn excludes Tank from elite roll")
	var dragon := Catalog.runtime_spec(10, 30)
	_check(Catalog.get_monster(10).hp == 80000 and dragon.hp == 360000 and dragon.damage == 3500 and dragon.credits == 224999, "boss loadParameters and solo reward override table")
	var encounters := Catalog.boss_encounters()
	_check(encounters.size() == 6 and encounters[3].monster_ids == [11, 12], "twins form one encounter with two identities")
	_check(Catalog.runtime_spec(12).credits == 0 and Catalog.runtime_spec(12).experience == 0, "assistant has no independent reward")
	_check(Catalog.runtime_spec(9).achievement_boss_category == 0 and Catalog.runtime_spec(8).achievement_boss_category == 1 and Catalog.runtime_spec(10).achievement_boss_category == 2, "three original achievement categories")
	_check(Catalog.runtime_spec(11).achievement_boss_category == 0 and Catalog.runtime_spec(12).achievement_boss_category == 0 and Catalog.runtime_spec(13).achievement_boss_category == 1 and Catalog.runtime_spec(14).achievement_boss_category == 1, "later bosses preserve inherited/explicit KillBoss category")
	for encounter: Dictionary in encounters:
		_check(encounter.spawnable and encounter.arena_available and encounter.arena_path.contains("boss_arenas"), "dedicated recovered boss arena: " + str(encounter.key))
	# Returned nested dictionaries must not mutate a later spawn's definition.
	first.attack_profiles[0].damage = -1
	_check(Catalog.runtime_spec(0).attack_profiles[0].damage == 70, "catalog callers own independent copies")


func _test_legacy_contract() -> void:
	var expected := {"crawler": [0, 45, 4, 70, 90], "spitter": [2, 35, 3, 100, 160], "brute": [3, 25, 6, 300, 130], "boss": [10, 80000, 3, 700, 299999]}
	for kind: String in expected:
		var enemy := WarfareEnemy.new()
		enemy.configure_recovered(victim, kind)
		var row: Array = expected[kind]
		_check(enemy.source_monster_id == row[0] and enemy.health == row[1] and enemy.speed == row[2] and enemy.attack_damage == row[3] and enemy.reward == row[4] and not enemy.original_runtime, "legacy four-kind stats: " + kind)
		enemy.free()


func _test_restored_models() -> void:
	var models := ["bug01", "bug02", "bug03", "bug07", "bug08", "bug05", "bug04", "bug06", "boss03", "boss02", "boss01", "boss02", "boss02-1", "boss05", "boss06"]
	for id in range(15):
		var enemy := _spawn(id)
		_check(enemy.source_spec.model == models[id], "GameWorld.GetEnemyTypeID prefab mapping %d" % id)
		_check(enemy.recovered_animation_player != null and enemy.recovered_animation_player.has_animation("idle"), "source animation player %d" % id)
		_check(enemy.recovered_animation_player.has_animation("death" if id == 14 else "dead"), "source death animation %d" % id)
		enemy.free()
	for id: int in Catalog.ELITE_IDS:
		var enemy := WarfareEnemy.new()
		_check(enemy.configure_original(victim, id, 1.0, true, 2), "5 percent source elite can spawn %d" % id)
		enemy.spawn_left = 0.0
		add_child(enemy)
		enemy.set_physics_process(false)
		_check(enemy.recovered_enemy != null and enemy.source_spec.model_path.contains("_elite"), "actual elite prefab loaded %d" % id)
		enemy.free()
	var invalid := WarfareEnemy.new()
	_check(not invalid.configure_original(victim, 99) and not invalid.configuration_error.is_empty(), "unknown ID rejects without wrong-art fallback")
	invalid.free()


func _spawn(id: int) -> WarfareEnemy:
	var enemy := WarfareEnemy.new()
	_check(enemy.configure_original(victim, id), "configure source enemy %d: %s" % [id, enemy.configuration_error])
	enemy.spawn_left = 0.0
	add_child(enemy)
	enemy.set_physics_process(false)
	_check(is_instance_valid(enemy.recovered_enemy), "source model loaded for %d" % id)
	return enemy


func _test_normal_logic() -> void:
	var actor := LogicActor.new()
	add_child(actor)
	var worm := NormalBrain.new()
	worm.configure(Catalog.runtime_spec(7))
	_check(worm.damage_received(99, false) == 9.0 and worm.damage_received(9, false) == 0.0 and not worm.stagger(0.2), "rolled Worm integer defense and stagger immunity")
	worm.state = "attack"
	_check(worm.damage_received(99, false) == 99.0 and worm.stagger(0.2), "Worm exposed while striking")
	_check(worm.damage_received(999, true) == 0.0, "normal enemy is immune in grave")
	var tank := NormalBrain.new()
	tank.configure(Catalog.runtime_spec(4))
	tank.step(actor, 0.1, 12.0, Vector3.FORWARD, true)
	_check(tank.state == "rush_windup" and not tank.stagger(0.2), "Tank telegraphs rush without being staggered")
	tank.step(actor, 1.0, 12.0, Vector3.FORWARD, true)
	var rush := tank.step(actor, 0.1, 1.5, Vector3.FORWARD, true)
	tank.step(actor, 0.1, 1.5, Vector3.FORWARD, true)
	_check(rush.length() == 12.0 and actor.hits == [200.0], "Tank rush speed/damage and single contact")
	tank.step(actor, 5.0, 20.0, Vector3.FORWARD, true)
	_check(tank.state == "chase", "Tank rush terminates without hitting target")
	actor.hits.clear()
	var zergling := NormalBrain.new()
	zergling.configure(Catalog.runtime_spec(1))
	for seed_value in range(1, 100):
		zergling.rng.seed = seed_value
		if zergling.rng.randi_range(0, 99) >= 10:
			zergling.rng.seed = seed_value
			break
	zergling.step(actor, 0.01, 10.0, Vector3.FORWARD, true)
	_check(zergling.state == "jump", "Zergling enters its jump window at 5..15m")
	var jump := zergling.step(actor, 0.3, 1.0, Vector3.FORWARD, true)
	zergling.step(actor, 0.1, 1.0, Vector3.FORWARD, true)
	_check(jump.length() == 20.0 and actor.hits == [130.0], "Zergling jump movement and one hit")
	var reaver := NormalBrain.new()
	reaver.configure(Catalog.runtime_spec(5))
	_check(not reaver.stagger(0.2), "Reaver resists initial hit reaction")
	reaver.step(actor, 11.01, 30.0, Vector3.FORWARD, true)
	_check(reaver.stagger(0.2), "Reaver hit reaction opens after 11s")
	for id in [2, 5, 6]:
		var ranged := NormalBrain.new()
		ranged.configure(Catalog.runtime_spec(id))
		ranged.step(actor, 0.0, 10.0, Vector3.FORWARD, true)
		ranged.step(actor, 0.59, 10.0, Vector3.FORWARD, true)
		_check(not actor.shots.has(id), "ranged attack cannot fire before 60%%: %d" % id)
		ranged.step(actor, 0.02, 10.0, Vector3.FORWARD, true)
		ranged.step(actor, 0.1, 10.0, Vector3.FORWARD, true)
		_check(actor.shots.count(id) == 1, "ranged attack fires once at 60%%: %d" % id)
	actor.free()


func _test_melee_and_boomer() -> void:
	victim.position = Vector3(0.0, 0.0, -2.0)
	victim.received.clear()
	var drone := _spawn(0)
	drone._face_planar_direction(Vector3.FORWARD)
	drone.source_brain.step(drone, 0.0, 2.0, Vector3.FORWARD, true)
	drone.source_brain.step(drone, 0.39, 2.0, Vector3.FORWARD, true)
	_check(victim.received.is_empty(), "source drone has an animation windup")
	drone.source_brain.step(drone, 0.02, 2.0, Vector3.FORWARD, true)
	drone.source_brain.step(drone, 0.1, 2.0, Vector3.FORWARD, true)
	_check(victim.received == [70.0], "source drone bites once at 40%")
	drone.free()
	victim.received.clear()
	var boomer := _spawn(3)
	var rewards: Array[int] = []
	boomer.died.connect(func(_enemy: WarfareEnemy, _position: Vector3, cash: int, _score: int): rewards.append(cash))
	boomer.source_brain.step(boomer, 0.0, 2.0, Vector3.FORWARD, true)
	boomer.source_explode(300, 4.0)
	boomer.take_damage(1000)
	_check(boomer.dead and victim.received == [300.0] and rewards == [130], "self-detonation applies damage and reward once")
	boomer.free()
	victim.received.clear()
	boomer = _spawn(3)
	boomer.take_damage(1000)
	_check(boomer.dead and victim.received.is_empty(), "killed Boomer does not perform attack-trigger explosion damage")
	boomer.free()


func _test_projectiles() -> void:
	var scorpion := _spawn(2)
	victim.position = Vector3(0.0, 0.0, -12.0)
	scorpion.source_normal_shot(Catalog.runtime_spec(2).attack_profiles[0], 2)
	var shots := get_tree().get_nodes_in_group("enemy_source_projectiles")
	_check(shots.size() == 1, "Scorpion emits one projectile")
	var shot := shots[0]
	shot.set_physics_process(false)
	var aim := victim.global_position + Vector3.UP * 1.5
	var flight_time := aim.length() / 12.0
	var arrival: Vector3 = shot.global_position + shot.travel_velocity * flight_time + Vector3.DOWN * 9.81 * flight_time * flight_time * 0.5
	_check(arrival.distance_to(aim) < 0.001 and shot.gravity_strength == 9.81 and shot.area_damage == 0.0, "Scorpion arc reaches aim with no invented acid area")
	await get_tree().physics_frame
	victim.received.clear()
	for index in range(40):
		if shot.resolved: break
		shot._physics_process(0.05)
	_check(shot.resolved and victim.received == [100.0], "Scorpion swept projectile actually collides with player")
	scorpion.free()
	var source := _spawn(10)
	source._face_planar_direction(Vector3.FORWARD)
	source.recovered_animation_player.play("attack")
	source.recovered_animation_player.seek(source.source_clip_length("attack", 1.0) * 0.52, true)
	source.recovered_animation_player.pause()
	source.source_dragon_shot(false)
	shots = get_tree().get_nodes_in_group("enemy_source_projectiles").filter(func(node: Node): return not node.is_queued_for_deletion())
	_check(shots.size() == 5, "Dragon ground fan has five shots")
	for node: Node3D in shots:
		_check(is_equal_approx(node.travel_velocity.length(), 22.0) and node.direct_damage == 700 and node.area_damage == 2100 and node.area_radius == 5.0, "Dragon ground projectile fields")
		node.set_physics_process(false)
	var central = shots[2]
	_check(central.global_position.distance_to(source.source_muzzle()) < 0.001 and central.collision_radius == 0.5, "Dragonball uses source mouth and sphere collider")
	await get_tree().physics_frame
	victim.received.clear()
	for index in range(30):
		if central.resolved: break
		central._physics_process(0.05)
	_check(central.resolved and victim.received == [700.0, 2100.0], "Dragon ground central projectile hits a standing player on flat ground")
	for node in shots: node.free()
	victim.received.clear()
	var splash := Projectile.new()
	splash.target = victim
	splash.direct_damage = 70
	splash.area_damage = 30
	splash.area_radius = 3
	add_child(splash)
	splash.global_position = victim.global_position
	splash.detonate(victim)
	splash.detonate(victim)
	_check(victim.received == [70.0, 30.0], "Sputtering applies direct plus full area exactly once")
	source.free()


func _test_knockback_contract() -> void:
	var boss := _spawn(9)
	victim.position = Vector3(0, 0, -2)
	victim.rotation.y = 0.0
	victim.body_yaw = 0.0
	victim.knock_steps.clear()
	boss.source_damage_target(100.0, 0.16)
	victim.body_yaw = PI
	boss.source_damage_target(100.0, 0.16)
	_check(victim.knock_steps == [-0.16, 0.16] and victim.rotation.y == 0.0, "CheckKnocked uses player facing API when body yaw differs from the unrotated root")
	victim.body_yaw = 0.0
	var fallback := KnockBasisTarget.new()
	add_child(fallback)
	fallback.position = Vector3(0, 0, -2)
	boss.source_knock_player(fallback, 0.16)
	fallback.rotation.y = PI
	boss.source_knock_player(fallback, 0.16)
	_check(fallback.knock_steps == [-0.16, 0.16], "CheckKnocked retains root basis fallback for targets without facing API")
	fallback.free()
	boss.free()


func _test_dragon() -> void:
	var dragon := _spawn(10)
	var brain = dragon.source_brain
	_check(dragon.is_boss_enemy() and dragon.max_health == 360000 and dragon.spawn_left == 0.0, "source dragon uses boss stats/intro, no grave rise")
	victim.position = Vector3(0, 0, -20)
	brain.step(dragon, 2.01, 20.0, Vector3.FORWARD, true)
	_check(brain.state == "intro" and dragon.recovered_animation_name == "rage", "dragon intro uses recovered rage clip")
	brain.step(dragon, brain.duration + 0.01, 20.0, Vector3.FORWARD, true)
	_check(brain.state == "takeoff", "intro transitions into takeoff")
	brain.step(dragon, brain.duration + 0.01, 20.0, Vector3.FORWARD, true)
	_check(brain.airborne and brain.state == "fly_idle", "takeoff transitions to air phase")
	brain.phase_elapsed = 20.1
	brain.step(dragon, 0.01, 20.0, Vector3.FORWARD, true)
	_check(brain.state == "landing", "air phase lands after 20 seconds")
	brain.step(dragon, brain.duration + 0.01, 20.0, Vector3.FORWARD, true)
	_check(not brain.airborne and brain.state == "ground_idle", "landing resets ground phase")
	brain.phase_elapsed = 12.1
	brain.step(dragon, 0.01, 20.0, Vector3.FORWARD, true)
	_check(brain.state == "takeoff", "ground phase takes off after 12 seconds")
	brain.airborne = false
	brain.start_action(dragon, "ground_idle")
	brain.phase_elapsed = 0.0
	dragon.take_damage(dragon.max_health * 0.16)
	_check(brain.state == "stagger" and not brain.enraged, "15% loss starts hit reaction, not premature rage")
	dragon.take_damage(dragon.max_health * 0.45)
	brain.step(dragon, brain.duration + 0.01, 20.0, Vector3.FORWARD, true)
	_check(brain.enraged and brain.state == "rage", "more than 60% loss starts one-way rage")
	brain.airborne = true
	brain.start_action(dragon, "fly_shot")
	for volley in range(3):
		brain.step(dragon, brain.duration + 0.01, 20.0, Vector3.FORWARD, true)
	_check(brain.state == "fly_idle" and get_tree().get_nodes_in_group("enemy_source_projectiles").filter(func(node: Node): return not node.is_queued_for_deletion()).size() == 3, "enraged aerial shot repeats exactly three times")
	for node in get_tree().get_nodes_in_group("enemy_source_projectiles"):
		if not node.is_queued_for_deletion(): node.free()
	brain.airborne = false
	brain.start_action(dragon, "rush_start")
	brain.step(dragon, brain.duration + 0.01, 20.0, Vector3.FORWARD, true)
	_check(brain.state == "rush", "far attack has a windup before rush")
	var locked: Vector3 = brain.locked_direction
	victim.position = Vector3(15, 0, -20)
	var movement: Vector3 = brain.step(dragon, 0.1, 25.0, Vector3.FORWARD, true)
	_check(movement.is_equal_approx(locked * 32.0), "rush commits direction so sidestepping is possible")
	brain.step(dragon, 5.1, 25.0, Vector3.FORWARD, true)
	_check(brain.state == "rush_end", "rush always has a bounded recovery")
	var reports: Array[bool] = []
	dragon.health_reported.connect(func(_hp: float, _max_hp: float, boss: bool): reports.append(boss))
	dragon.take_damage(dragon.max_health)
	_check(dragon.dead and reports == [true], "numeric dragon reports boss HUD signal on death")
	dragon.free()


func _clear_source_effects() -> void:
	for group in ["enemy_source_projectiles", "enemy_source_effects"]:
		for node in get_tree().get_nodes_in_group(group):
			if not node.is_queued_for_deletion(): node.free()


func _live_shots() -> Array[Node]:
	return get_tree().get_nodes_in_group("enemy_source_projectiles").filter(func(node: Node): return not node.is_queued_for_deletion())


func _test_mantis_and_twins() -> void:
	victim.position = Vector3(0, 0, -16)
	var mantis := _spawn(9)
	var brain = mantis.source_brain
	brain.step(mantis, brain.duration + 0.01, 16.0, Vector3.FORWARD, true)
	_check(brain.state == "intro", "Mantis waits before its rage introduction")
	brain.step(mantis, brain.duration + 0.01, 16.0, Vector3.FORWARD, true)
	_check(brain.state == "takeoff", "Mantis finishes the introduction before takeoff")
	brain.step(mantis, brain.duration + 0.01, 16.0, Vector3.FORWARD, true)
	_check(brain.flying and brain.state == "fly_idle", "Mantis intro/takeoff enters aerial phase")
	brain.phase_elapsed = 18.1
	brain.step(mantis, 1.01, 16.0, Vector3.FORWARD, true)
	_check(brain.state == "landing", "Mantis normal flight expires at 18 seconds")
	brain.enraged = true
	brain.start_action(mantis, "shot")
	for volley in range(3): brain.step(mantis, brain.duration + 0.01, 16.0, Vector3.FORWARD, true)
	_check(_live_shots().size() == 9 and brain.state == "fly_idle", "Mantis rage shoots three salvos of three blades")
	for shot in _live_shots():
		_check(shot.direct_damage == 800.0 and is_equal_approx(shot.travel_velocity.length(), 22.0), "Mantis blade uses source speed and damage")
	_clear_source_effects()
	brain.start_action(mantis, "boomerang")
	brain.step(mantis, brain.duration * 0.53, 16.0, Vector3.FORWARD, true)
	_check(_live_shots().size() == 2, "Mantis has two differently timed boomerangs")
	var blades := _live_shots()
	if blades.size() == 2:
		_check(blades[0].homing_delay == 1.2 and blades[1].homing_delay == 1.0 and blades[0].homing_speed == 24.0 and blades[1].homing_speed == 30.0, "boomerang rise/homing parameters")
		var blade = blades[0]
		blade.set_physics_process(false)
		blade.global_position = Vector3(0, 12, 0)
		blade._physics_process(1.21)
		var lock: Vector3 = blade.locked_target
		victim.position.x = 6.0
		blade._physics_process(0.01)
		_check(blade.locked_target == lock, "boomerang locks once after rising and can be dodged")
	_clear_source_effects()
	mantis.free()
	var main := _spawn(11)
	var assist := _spawn(12)
	_check(main.link_source_partner(assist), "twins pair through explicit actor API")
	assist.source_brain.start_action(assist, "watch")
	var hp := assist.health
	assist.take_damage(100)
	_check(assist.health == hp, "assistant balcony is initially unhittable")
	main.take_damage(main.max_health * 0.21)
	_check(assist.source_brain.assist_active and assist.source_brain.state == "assist_idle", "20 percent main damage activates assistant support")
	hp = assist.health
	assist.take_damage(100)
	assist.source_brain.start_action(assist, "assist_shot")
	assist.take_damage(100)
	_check(assist.health == hp, "assistant support remains immune until join finishes")
	main.take_damage(main.max_health * 0.40)
	_check(main.source_brain.coop_pending and assist.source_brain.coop_pending, "60 percent main damage requests cooperation")
	main.source_brain.rage_pending = false
	main.source_brain._decide(main, 16.0, true)
	_check(main.source_brain.state == "coop_join" and assist.source_brain.state == "coop_join", "cooperative join is issued to both members")
	for unit in [main, assist]: unit.source_brain.step(unit, unit.source_brain.duration + 0.01, 16.0, Vector3.FORWARD, true)
	for unit in [main, assist]:
		_check(unit.source_brain.state == "coop_move", "twin flies to source cooperation waypoint")
		unit.global_position = unit.source_brain.COOP_POINTS[unit.source_brain.coop_point] + Vector3.UP * 0.5
		unit.source_brain.step(unit, 0.01, 16.0, Vector3.FORWARD, true)
	main.source_brain.step(main, 0.2, 16.0, Vector3.FORWARD, true)
	_check(main.source_brain.state == "coop_dive_start" and assist.source_brain.state == "coop_dive_start", "twins start the coordinated dive together")
	assist.take_damage(assist.max_health * 0.16)
	_check(main.source_brain.coop_attacks_left == 0 and main.source_brain.coop_dive_left == 0 and assist.source_brain.coop_attacks_left == 0, "assistant stagger cancels both cooperation counters")
	assist.source_brain.step(assist, assist.source_brain.duration + 0.01, 16.0, Vector3.FORWARD, true)
	# The partner may finish its committed dive before reaching coop_idle.
	main.source_brain.start_action(main, "coop_idle")
	main.source_brain.step(main, 0.2, 16.0, Vector3.FORWARD, true)
	_check(not main.source_brain.state.begins_with("coop_") and not assist.source_brain.state.begins_with("coop_"), "both twins recover after cooperation is interrupted")
	_check(assist.source_brain.joined_combat and not assist.source_brain.assist_active, "joining permanently ends assistant balcony support")
	assist.source_brain.phase_elapsed = 18.1
	assist.source_brain.step(assist, 1.01, 16.0, Vector3.FORWARD, true)
	_check(assist.source_brain.state == "landing", "joined assistant returns to normal timed flight and landing")
	assist.source_brain.flying = false
	main.take_damage(main.max_health)
	_check(assist.source_brain.enraged and assist.source_brain.defend_left == 30.0, "survivor enrages and gains 30 second defense")
	hp = assist.health
	assist.take_damage(99)
	_check(assist.health == hp - 9.0, "survivor defense applies source integer divide by ten")
	main.free()
	assist.free()


func _test_ground_bosses() -> void:
	victim.position = Vector3(0, 0, -10)
	var beetle := _spawn(8)
	var brain = beetle.source_brain
	brain.start_action(beetle, "jump_start")
	var initial_jump: Vector3 = brain.jump_velocity
	_check(is_equal_approx(initial_jump.y, 20.0) and is_equal_approx(initial_jump.z * (20.0 / (9.81 * 4.0)), -10.0), "Beetle jump reaches the locked horizontal target at apex")
	brain.step(beetle, brain.duration * 0.55, 10.0, Vector3.FORWARD, true)
	_check(brain.state == "jump_up" and brain.vertical_control, "Beetle launches at 54 percent of jump01")
	beetle.global_position.y = 5.0
	brain.step(beetle, 0.52, 10.0, Vector3.FORWARD, true)
	_check(brain.state == "jump_hover", "Beetle enters brief apex hover")
	brain.step(beetle, 0.31, 10.0, Vector3.FORWARD, true)
	_check(brain.state == "jump_down", "Beetle apex releases after 0.3 seconds")
	beetle.global_position = Vector3(0, 0.05, -10)
	victim.position = Vector3(0, 0, -12)
	victim.received.clear()
	brain.step(beetle, 0.02, 2.0, Vector3.FORWARD, true)
	_check(victim.received == [3600.0] and brain.state == "jump_end", "Beetle landing deals one inner shockwave hit")
	beetle.global_position = Vector3.ZERO
	brain.start_action(beetle, "continuous")
	brain.step(beetle, brain.duration * 0.26, 12.0, Vector3.FORWARD, true)
	_check(_live_shots().is_empty(), "continuous spit respects its windup")
	brain.step(beetle, brain.duration * 0.02, 12.0, Vector3.FORWARD, true)
	_check(_live_shots().size() == 1 and _live_shots()[0].direct_damage == 1760.0, "Beetle continuous spit starts after 27 percent")
	_clear_source_effects()
	beetle.free()
	var worm := _spawn(13)
	brain = worm.source_brain
	brain._decide(worm, 40.0, true)
	_check(brain.state == "rush_start", "Earthworm beyond startDrillDistance chooses source rush, not drill")
	brain.start_action(worm, "super_start")
	brain.step(worm, brain.duration + 0.01, 40.0, Vector3.FORWARD, true)
	brain.step(worm, 2.6, 40.0, Vector3.FORWARD, true)
	_check(brain.state == "super_rush" and brain.super_count == 1, "super rush movement timeout uses real seconds despite 2x animation")
	for pass_index in range(3):
		worm.global_position = brain.rush_target
		brain.step(worm, 0.2, 40.0, Vector3.FORWARD, true)
		if pass_index < 2:
			_check(brain.state == "super_start" and brain.vertical_control, "outside-arena super rush transition preserves height")
			brain.step(worm, brain.duration + 0.01, 40.0, Vector3.FORWARD, true)
	_check(brain.state == "super_end" and brain.super_count == 0 and worm.collision_mask == 1, "Earthworm super rush completes exactly three passes and restores walls")
	worm.global_position = Vector3.ZERO
	brain.start_action(worm, "drill_in")
	brain.step(worm, brain.duration, 12.0, Vector3.FORWARD, true)
	_check(brain.state == "drill_idle" and not worm.model.visible, "Earthworm drills below the arena")
	var hp := worm.health
	worm.take_damage(10000)
	_check(worm.health == hp, "submerged Earthworm cannot be hit")
	brain.step(worm, 4.41, 12.0, Vector3.FORWARD, true)
	_check(brain.state == "drill_out" and worm.model.visible, "Earthworm returns after its 4.4 second underground wait")
	victim.global_position = worm.global_position + Vector3(0, 0, -2)
	victim.received.clear()
	brain.touch_left = 0.0
	brain.step(worm, brain.duration * 0.43, 2.0, Vector3.FORWARD, true)
	brain.step(worm, brain.duration * 0.10, 2.0, Vector3.FORWARD, true)
	_check(victim.received == [7200.0], "Earthworm emergence inner/outer rings share one touch cooldown")
	brain.start_action(worm, "idle")
	worm.take_damage(worm.max_health * 0.46)
	brain.step(worm, brain.duration + 0.01, 12.0, Vector3.FORWARD, true)
	_check(brain.state == "rage" and brain.enraged, "Earthworm rage threshold is 45 percent HP loss")
	worm.free()


func _test_machine() -> void:
	victim.position = Vector3(0, 0, -10)
	var machine := _spawn(14)
	var brain = machine.source_brain
	brain.start_action(machine, "missile_a")
	brain.step(machine, brain.duration * 0.65, 10.0, Vector3.FORWARD, true)
	_check(_live_shots().size() == 12, "machine six launch events emit twelve missiles even at low frame rate")
	for shot in _live_shots():
		_check(shot.area_damage == 4000.0 and shot.area_radius == 1.0 and shot.homing_turn_rate == 2.0 and shot.homing_speed == 18.0, "machine missile prefab parameters")
	_clear_source_effects()
	victim.received.clear()
	brain.start_action(machine, "stomp")
	brain.step(machine, brain.duration * 0.26, 10.0, Vector3.FORWARD, true)
	brain.step(machine, brain.duration, 10.0, Vector3.FORWARD, true)
	_check(victim.received == [10000.0] and brain.state == "laser", "machine stomp hits once and chains into laser")
	brain.step(machine, brain.duration * 0.43, 10.0, Vector3.FORWARD, true)
	var beams := get_tree().get_nodes_in_group("enemy_source_effects")
	_check(beams.size() == 1 and beams[0].damage == 10000.0 and beams[0].lifetime == 1.3, "machine laser source damage/lifetime")
	_clear_source_effects()
	machine.health = machine.max_health * 0.79
	brain.attacked = false
	brain._decide(machine, 10.0)
	_check(brain.enraged and brain.state == "rage" and brain.rage_bands.has(3), "machine triggers one-time 80 percent HP band")
	brain.start_action(machine, "ball")
	brain.step(machine, brain.duration * 0.06, 10.0, Vector3.FORWARD, true)
	_check(_live_shots().size() == 8 and _live_shots()[0].hazard.damage == 1000.0 and _live_shots()[0].area_damage == 5000.0, "rage tosses eight poison balls with gas on detonation")
	_clear_source_effects()
	brain.rage_attacks = 2
	brain.start_action(machine, "whirl_end")
	brain.step(machine, brain.duration + 0.01, 10.0, Vector3.FORWARD, true)
	_check(brain.state == "rage_end" and not brain.enraged, "two rage attacks restore normal machine mode")
	machine.free()


func _test_hazards() -> void:
	victim.position = Vector3(0, 0, -8)
	victim.received.clear()
	var worm := _spawn(13)
	var params := {"radius": 3.0, "damage": 660.0, "interval": 0.6, "shared_timer": true, "slow_multiplier": 0.3}
	var first = worm.source_spawn_hazard(victim.global_position, params)
	var second = worm.source_spawn_hazard(victim.global_position, params)
	first.set_physics_process(false)
	second.set_physics_process(false)
	first._physics_process(0.3)
	second._physics_process(0.3)
	_check(victim.received == [660.0], "overlapping source slime pools share owner damage timer")
	_check(is_equal_approx(float(victim.get_meta("enemy_move_multiplier", 1.0)), 0.3), "Earthworm slime publishes the source slow multiplier")
	first.free()
	_check(is_equal_approx(float(victim.get_meta("enemy_move_multiplier", 1.0)), 0.3), "removing one overlap keeps the remaining pool's slow")
	second.free()
	_check(is_equal_approx(float(victim.get_meta("enemy_move_multiplier", 1.0)), 1.0), "last poison pool removal restores movement")
	victim.armor_skills = {"fly": 1.0}
	first = worm.source_spawn_hazard(victim.global_position, params)
	first.set_physics_process(false)
	first._physics_process(0.3)
	_check(float(victim.get_meta("enemy_move_multiplier", 1.0)) == 1.0 and victim.received == [660.0], "flying armor avoids ground slime damage and slow")
	first.free()
	victim.armor_skills = {}
	worm.free()
	await get_tree().physics_frame
