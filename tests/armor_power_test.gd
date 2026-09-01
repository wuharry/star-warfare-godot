extends Node3D

const ControllerScript = preload("res://scripts/game/armor_power_controller.gd")

const EXPECTED_DURATIONS := [10.0, 30.0, 5.0, 15.0, 10.0, 10.0, 1.0, 1.0, 10.0, 1.0]
const EXPECTED_COOLDOWNS := [30.0, 90.0, 40.0, 100.0, 120.0, 55.0, 60.0, 30.0, 60.0, 90.0]

var failures: Array[String] = []
var harness_player: FakePlayer
var harness_enemy: FakeEnemy
var controller: ArmorPowerController


class FakePlayer extends CharacterBody3D:
	var armor_skills: Dictionary = {}
	var health := 50.0
	var max_health := 100.0
	var dead := false
	var aim_target: Node3D
	var armor_power_controller: Node

	func set_armor_power_controller(value: Node) -> void:
		armor_power_controller = value

	func heal_from_armor_power(amount: float) -> float:
		var before := health
		health = minf(max_health, health + maxf(0.0, amount))
		return health - before

	func on_damage_dealt(actual_damage: float) -> void:
		if is_instance_valid(armor_power_controller):
			armor_power_controller.on_damage_dealt(actual_damage)

	func get_aim_solution(maximum_range := 180.0) -> Dictionary:
		var origin := global_position + Vector3.UP
		var fallback := origin + Vector3.FORWARD * maximum_range
		return {
			"origin": origin,
			"direction": Vector3.FORWARD,
			"target": aim_target.global_position + Vector3.UP if is_instance_valid(aim_target) else fallback,
			"collider": aim_target if is_instance_valid(aim_target) else null,
		}


class FakeEnemy extends CharacterBody3D:
	var health := 300.0
	var speed := 10.0
	var dead := false

	func _ready() -> void:
		add_to_group("enemies")
		collision_layer = 2
		collision_mask = 0
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.55
		capsule.height = 2.8
		collision.shape = capsule
		collision.position.y = 1.4
		add_child(collision)

	func take_damage(amount: float, _hit_position := Vector3.ZERO, source: Node = null) -> void:
		if dead:
			return
		var before := health
		health = maxf(0.0, health - maxf(0.0, amount))
		var actual := before - health
		if actual > 0.0 and is_instance_valid(source) and source.has_method("on_damage_dealt"):
			source.on_damage_dealt(actual)
		dead = health <= 0.0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("ARMOR POWER TEST: " + message)


func _approx(actual: float, expected: float, tolerance := 0.02) -> bool:
	return absf(actual - expected) <= tolerance


func _run() -> void:
	_build_harness()
	await get_tree().physics_frame
	_test_metadata_and_timers()
	_test_stat_powers()
	await _test_attack_shield()
	await _test_impact_wave()
	await _test_track_wave()
	_test_hurt_health()
	_test_gravity_force()
	await _test_world_and_hud_ownership()

	if failures.is_empty():
		print("ARMOR_POWER_TEST_PASS checks=10")
		get_tree().quit(0)
	else:
		print("ARMOR_POWER_TEST_FAIL %d: %s" % [failures.size(), ", ".join(failures)])
		get_tree().quit(1)


func _build_harness() -> void:
	harness_player = FakePlayer.new()
	harness_player.name = "HarnessPlayer"
	for skill_key in ControllerScript.SKILL_KEYS:
		harness_player.armor_skills[skill_key] = 1.0
	add_child(harness_player)

	harness_enemy = FakeEnemy.new()
	harness_enemy.name = "HarnessEnemy"
	harness_enemy.position = Vector3(0.0, 0.0, -4.0)
	add_child(harness_enemy)
	harness_player.aim_target = harness_enemy

	controller = ControllerScript.new()
	controller.name = "HarnessArmorPowerController"
	controller.configure(harness_player, self)
	harness_player.set_armor_power_controller(controller)
	harness_player.add_child(controller)
	# Deterministic unit stepping; wave collision queries still use the real
	# PhysicsServer on each awaited physics frame.
	controller.set_physics_process(false)


func _reset_harness() -> void:
	controller.cancel_all_active(true)
	harness_player.health = 50.0
	harness_player.dead = false
	harness_enemy.health = 300.0
	harness_enemy.speed = 10.0
	harness_enemy.dead = false
	harness_enemy.position = Vector3(0.0, 0.0, -4.0)


func _test_metadata_and_timers() -> void:
	_check(controller.get_available_skill_indices().size() == 10, "all ten equipped active powers must be exposed")
	for skill_index in range(10):
		var state := controller.get_skill_state(skill_index)
		_check(_approx(float(state.duration), EXPECTED_DURATIONS[skill_index]), "skill %d duration differs from Unity" % skill_index)
		_check(_approx(float(state.cooldown), EXPECTED_COOLDOWNS[skill_index]), "skill %d cooldown differs from Unity" % skill_index)

	_reset_harness()
	_check(controller.activate_authoritative(0), "THUNDER ALL UP should activate")
	_check(_approx(controller.modify_outgoing_damage(100.0), 150.0), "THUNDER must multiply outgoing damage by 1.5")
	_check(_approx(controller.get_speed_bonus(), 2.0), "THUNDER must add two movement units")
	controller.advance_simulation(10.1)
	_check(not controller.is_skill_active(0), "THUNDER must expire after ten seconds")
	_check(_approx(float(controller.get_skill_state(0).cooldown_left), 19.9), "cooldown must include the active interval like Unity")
	controller.advance_simulation(20.0)
	_check(controller.is_skill_ready(0), "THUNDER must become ready after its 30 second total cooldown")


func _test_stat_powers() -> void:
	_reset_harness()
	_check(controller.activate_authoritative(1), "FLY SPEED UP should activate")
	_check(_approx(controller.get_speed_bonus(), 2.0), "FLY SPEED UP must add two movement units")

	_reset_harness()
	_check(controller.activate_authoritative(2), "DEFENCE UP should activate")
	_check(_approx(controller.modify_incoming_damage(100.0), 15.0), "DEFENCE UP must reduce incoming damage by 85 percent")

	_reset_harness()
	harness_player.health = 10.0
	_check(controller.activate_authoritative(3), "ANDROMEDA UP should activate")
	_check(_approx(harness_player.health, 100.0), "ANDROMEDA must restore the normalized 100 HP")
	_check(_approx(controller.get_speed_bonus(), 1.0), "ANDROMEDA must add one movement unit")
	_check(_approx(controller.modify_incoming_damage(100.0), 70.0), "ANDROMEDA must reduce incoming damage by 30 percent")

	_reset_harness()
	harness_player.health = 40.0
	_check(controller.activate_authoritative(4), "HEALTH STEAL should activate")
	_check(_approx(controller.modify_outgoing_damage(100.0), 65.0), "HEALTH STEAL must apply Unity's 65 percent damage tradeoff")
	controller.on_damage_dealt(12.0)
	_check(_approx(harness_player.health, 52.0), "HEALTH STEAL must heal only actual damage dealt")


func _test_attack_shield() -> void:
	_reset_harness()
	harness_enemy.health = 10.0
	harness_enemy.position = Vector3(0.0, 0.0, -2.0)
	await get_tree().physics_frame
	_check(controller.activate_authoritative(5), "ATTACK SHIELD should activate")
	controller.advance_simulation(0.25)
	_check(_approx(harness_enemy.health, 9.0), "ATTACK SHIELD must deal normalized pulse damage every 0.25 seconds")


func _test_impact_wave() -> void:
	_reset_harness()
	harness_player.health = 20.0
	await get_tree().physics_frame
	_check(controller.activate_authoritative(6), "IMPACT WAVE should activate")
	for _step in range(12):
		controller.advance_simulation(0.05)
		await get_tree().physics_frame
		if harness_enemy.health < 300.0:
			break
	_check(_approx(harness_enemy.health, 80.0), "IMPACT WAVE must deal normalized 220 penetrating damage")
	_check(_approx(harness_player.health, 100.0), "IMPACT WAVE must heal half of actual damage, capped at max HP")


func _test_track_wave() -> void:
	_reset_harness()
	harness_enemy.health = 100.0
	await get_tree().physics_frame
	_check(controller.activate_authoritative(7), "TRACK WAVE should activate")
	for _step in range(12):
		controller.advance_simulation(0.05)
		await get_tree().physics_frame
		if harness_enemy.speed < 10.0:
			break
	_check(_approx(harness_enemy.health, 99.0), "TRACK WAVE must deal its authored one damage")
	_check(_approx(harness_enemy.speed, 7.0), "TRACK WAVE must apply the five second 30 percent slow")
	controller.advance_simulation(5.1)
	_check(_approx(harness_enemy.speed, 10.0), "TRACK WAVE must restore the enemy's authored speed")


func _test_hurt_health() -> void:
	_reset_harness()
	_check(controller.activate_authoritative(8), "HURT HEALTH should activate")
	_check(_approx(controller.modify_incoming_damage(100.0), -60.0), "HURT HEALTH must convert a hit to 60 percent healing")


func _test_gravity_force() -> void:
	_reset_harness()
	harness_enemy.position = Vector3(0.0, 0.0, -12.0)
	var before := harness_enemy.global_position.distance_to(harness_player.global_position)
	_check(controller.activate_authoritative(9), "GRAVITY FORCE should activate against the aimed enemy")
	controller.advance_simulation(0.25)
	var after := harness_enemy.global_position.distance_to(harness_player.global_position)
	_check(after < before - 4.9, "GRAVITY FORCE must pull its target at 20 movement units per second")


func _test_world_and_hud_ownership() -> void:
	await _cleanup_harness()

	GameState.selected_level = 1
	var packed := load("res://scenes/game.tscn") as PackedScene
	var game_world := packed.instantiate() as WarfareGameWorld
	add_child(game_world)
	game_world.completed = true
	await get_tree().process_frame
	_check(is_instance_valid(game_world.armor_power_controller), "GameWorld must own an armor power controller without relying on HUD")
	_check(game_world.player.armor_power_controller == game_world.armor_power_controller, "player must use GameWorld's authoritative controller")
	_check(game_world.hud.power_controller == game_world.armor_power_controller, "HUD must bind to the gameplay-owned controller")

	var original_skills := game_world.player.armor_skills
	game_world.player.armor_skills = {"power_up": 1.0}
	game_world.armor_power_controller.refresh_available_skills()
	await get_tree().process_frame
	_check(game_world.hud.power_buttons.has(0), "HUD must build a touch button for an equipped active power")
	game_world.hud._activate_armor_power(0)
	_check(game_world.armor_power_controller.is_skill_active(0), "HUD activation must route through controller.request_activate")
	game_world.player.armor_skills = original_skills
	game_world.completed = true
	game_world.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().process_frame
	# Give headless audio/text servers one short idle window to release playback
	# and shaped-text RIDs before the test process exits.
	await get_tree().create_timer(0.1).timeout


func _cleanup_harness() -> void:
	controller.cancel_all_active(true)
	harness_player.queue_free()
	harness_enemy.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
