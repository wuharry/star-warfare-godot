extends Node

# Behavioural coverage for the three combat tiers. "recruit" must stay on the
# original beeline AI byte for byte, while "veteran" and "elite" must actually
# flank, throttle their attacks through the squad token pool, and telegraph
# melee strikes so the player can dodge them.

var failures: Array[String] = []
var world: WarfareGameWorld

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ENEMY AI TEST: " + message)

func _make_world(difficulty: String) -> void:
	GameState.settings.difficulty = difficulty
	GameState.selected_level = 1
	world = (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame

func _teardown() -> void:
	if not is_instance_valid(world):
		return
	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame

func _spawn(kind: String) -> WarfareEnemy:
	world._spawn_enemy(kind, false)
	await get_tree().process_frame
	var newest: WarfareEnemy
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate is WarfareEnemy and (candidate as WarfareEnemy).enemy_kind == kind:
			newest = candidate
	# Skip the grave-rise so the AI branches are reachable immediately.
	if is_instance_valid(newest):
		newest.spawn_left = 0.0
		newest.reaction_left = 0.0
	return newest

func _run() -> void:
	await _test_recruit_keeps_legacy_ai()
	await _test_tactical_profiles_apply()
	await _test_attack_token_pool()
	await _test_melee_is_telegraphed()
	await _test_telegraph_can_be_dodged()
	await _test_ranged_fire_leads_target()
	await _test_flanking_leaves_the_direct_line()
	await _test_token_released_on_death()
	if failures.is_empty():
		print("ENEMY_AI_TEST_PASS checks=8")
		get_tree().quit(0)
	else:
		print("ENEMY_AI_TEST_FAIL %d" % failures.size())
		get_tree().quit(1)

func _test_recruit_keeps_legacy_ai() -> void:
	await _make_world("recruit")
	var enemy := await _spawn("crawler")
	_check(is_instance_valid(enemy), "recruit crawler was not spawned")
	if is_instance_valid(enemy):
		_check(not enemy.tactical, "recruit must not enable the tactical brain")
		_check(enemy.melee_windup == 0.0, "recruit melee must have no wind-up")
		_check(world.max_attack_tokens >= 99, "recruit must not throttle attackers")
		# The legacy path damages the player the instant the range check passes.
		var player := world.player
		player.global_position = enemy.global_position + Vector3(0.6, 0.0, 0.0)
		var before := player.health + player.shield
		enemy.attack_cooldown = 0.0
		var desired := enemy._legacy_step(0.6, Vector3(0.6, 0.0, 0.0))
		_check(desired == Vector3.ZERO, "recruit should stop to swing in range")
		_check(player.health + player.shield < before, "recruit melee must damage immediately")
	await _teardown()

func _test_tactical_profiles_apply() -> void:
	for tier in ["veteran", "elite"]:
		await _make_world(tier)
		var enemy := await _spawn("crawler")
		if is_instance_valid(enemy):
			_check(enemy.tactical, "%s must enable the tactical brain" % tier)
			_check(enemy.melee_windup > 0.0, "%s melee must telegraph" % tier)
			_check(enemy.flank_spread > 0.0, "%s must flank" % tier)
			_check(enemy.sight_check, "%s must gate attacks on line of sight" % tier)
			_check(world.max_attack_tokens < 99, "%s must throttle simultaneous attackers" % tier)
		await _teardown()

func _test_attack_token_pool() -> void:
	await _make_world("veteran")
	var cap := world.max_attack_tokens
	var holders: Array[WarfareEnemy] = []
	for i in range(cap + 3):
		var enemy := await _spawn("crawler")
		if is_instance_valid(enemy):
			holders.append(enemy)
	var granted := 0
	for enemy in holders:
		if enemy._claim_attack_token():
			granted += 1
	_check(granted == cap, "token pool granted %d, expected the cap of %d" % [granted, cap])
	# Releasing one must free exactly one slot for a waiting enemy.
	if granted > 0 and holders.size() > cap:
		holders[0]._release_attack_token()
		_check(holders[cap]._claim_attack_token(), "a freed token must be reusable")
	await _teardown()

func _test_melee_is_telegraphed() -> void:
	await _make_world("veteran")
	var enemy := await _spawn("crawler")
	if is_instance_valid(enemy):
		var player := world.player
		player.global_position = enemy.global_position + Vector3(0.6, 0.0, 0.0)
		var before := player.health + player.shield
		enemy.attack_cooldown = 0.0
		var desired := enemy._tactical_melee(0.6, Vector3(0.6, 0.0, 0.0), true)
		_check(desired == Vector3.ZERO, "a committed strike should root the enemy")
		_check(enemy.windup_left > 0.0, "committing must start a wind-up")
		_check(player.health + player.shield == before, "damage must not land during the wind-up")
		# Resolving while the player is still inside the lunge lands the hit.
		enemy.windup_left = 0.0
		enemy._resolve_melee_windup()
		_check(player.health + player.shield < before, "the strike must land after the wind-up")
	await _teardown()

func _test_telegraph_can_be_dodged() -> void:
	await _make_world("veteran")
	var enemy := await _spawn("crawler")
	if is_instance_valid(enemy):
		var player := world.player
		player.global_position = enemy.global_position + Vector3(0.6, 0.0, 0.0)
		enemy.attack_cooldown = 0.0
		enemy._tactical_melee(0.6, Vector3(0.6, 0.0, 0.0), true)
		_check(enemy.windup_left > 0.0, "expected a wind-up to dodge")
		# Dash clear of the lunge before the telegraph finishes.
		player.global_position = enemy.global_position + Vector3(enemy.attack_range * 3.0, 0.0, 0.0)
		var before := player.health + player.shield
		enemy.windup_left = 0.0
		enemy._resolve_melee_windup()
		_check(player.health + player.shield == before, "leaving the lunge must dodge the strike")
	await _teardown()

func _test_ranged_fire_leads_target() -> void:
	await _make_world("elite")
	var enemy := await _spawn("spitter")
	if is_instance_valid(enemy):
		var player := world.player
		player.global_position = enemy.global_position + Vector3(10.0, 0.0, 0.0)
		# A player sprinting sideways at 8 m/s should be led, not trailed.
		enemy.target_velocity = Vector3(0.0, 0.0, 8.0)
		var aim := enemy._predicted_aim_point(16.0)
		var lead := aim.z - player.global_position.z
		_check(lead > 2.0, "elite fire must lead a moving target, got %.2f m" % lead)
		# With leading disabled the aim point must sit on the player.
		enemy.aim_lead = 0.0
		enemy.aim_spread = 0.0
		var static_aim := enemy._predicted_aim_point(16.0)
		_check(absf(static_aim.z - player.global_position.z) < 0.01, "no lead means aim at the player")
	await _teardown()

func _test_flanking_leaves_the_direct_line() -> void:
	await _make_world("elite")
	var enemy := await _spawn("crawler")
	if is_instance_valid(enemy):
		var player := world.player
		player.global_position = enemy.global_position + Vector3(12.0, 0.0, 0.0)
		# Force a hard 90-degree lane so the assertion is deterministic.
		enemy.flank_angle = PI * 0.5
		enemy.separation_vector = Vector3.ZERO
		enemy.strafe_strength = 0.0
		var slot := enemy._flank_position(4.0)
		var straight := (player.global_position - enemy.global_position).normalized()
		var to_slot := (slot - enemy.global_position).normalized()
		_check(to_slot.dot(straight) < 0.95, "flank slot must leave the direct approach line")
		var desired := enemy._approach_velocity(Vector3(12.0, 0.0, 0.0), true, 4.0)
		_check(desired.length() > 0.01, "a flanking enemy must keep moving")
		_check(desired.normalized().dot(straight) < 0.95, "approach must not beeline at the player")
	await _teardown()

func _test_token_released_on_death() -> void:
	await _make_world("veteran")
	var enemy := await _spawn("crawler")
	if is_instance_valid(enemy):
		_check(enemy._claim_attack_token(), "enemy should be able to claim a token")
		_check(world.attack_tokens.size() == 1, "token pool should hold one entry")
		enemy.take_damage(enemy.max_health * 2.0)
		_check(world.attack_tokens.is_empty(), "death must return the attack token")
	await _teardown()
