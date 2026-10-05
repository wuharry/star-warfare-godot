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
	await _test_recruit_keeps_source_swarm()
	await _test_swarm_keeps_pace_with_the_player()
	await _test_tactical_waves_do_not_inflate_health()
	await _test_bomber_fuse_can_be_dodged()
	await _test_bomber_blast_hits_a_close_player()
	await _test_shot_bomber_takes_the_pack()
	await _test_pouncer_catches_a_backpedal()
	await _test_pouncer_leap_hits_or_misses()
	await _test_surround_spawns_come_from_every_side()
	await _test_director_breathes_after_a_peak()
	await _test_director_hold_pauses_the_spawner()
	if failures.is_empty():
		print("ENEMY_AI_TEST_PASS checks=19")
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

# --- Swarm pressure: speed, roster, bombers, pouncers, spawns, pacing -------

func _test_recruit_keeps_source_swarm() -> void:
	await _make_world("recruit")
	var crawler := await _spawn("crawler")
	if is_instance_valid(crawler):
		_check(crawler.speed == 4.0, "recruit crawler must keep the source 4 m/s, got %.2f" % crawler.speed)
	var bomber := await _spawn("brute")
	if is_instance_valid(bomber):
		bomber.take_damage(bomber.max_health * 2.0)
		_check(bomber.dead and not bomber.exploded, "recruit bombers must not gain a death burst")
	world.current_wave = 3
	for index in range(30):
		_check(world._choose_enemy_kind(index, false) != "pouncer", "recruit must keep the source roster")
	await _teardown()

func _test_swarm_keeps_pace_with_the_player() -> void:
	# The median full armor runs 8.2 m/s; the swarm sits on it, +-0.5 per bug.
	var bands := {"veteran": Vector2(7.7, 8.7), "elite": Vector2(8.1, 9.1)}
	for tier: String in bands:
		await _make_world(tier)
		var band: Vector2 = bands[tier]
		for kind in ["crawler", "crawler", "crawler", "brute", "pouncer"]:
			var bug := await _spawn(kind)
			if is_instance_valid(bug):
				_check(bug.speed >= band.x - 0.001 and bug.speed <= band.y + 0.001, "%s %s speed %.2f is outside %s" % [tier, kind, bug.speed, band])
		var spitter := await _spawn("spitter")
		if is_instance_valid(spitter):
			_check(spitter.speed == 3.0, "%s spitters must hold their source pace" % tier)
		world.current_wave = 2
		var pouncers := 0
		for index in range(16):
			if world._choose_enemy_kind(index, false) == "pouncer":
				pouncers += 1
		_check(pouncers > 0, "%s wave 2 must field pouncers" % tier)
		await _teardown()

func _test_tactical_waves_do_not_inflate_health() -> void:
	for tier in ["veteran", "recruit"]:
		await _make_world(tier)
		world.current_wave = 5
		var late := await _spawn("crawler")
		if is_instance_valid(late):
			var base := 45.0 * float(world.level_data.get("enemy_health_scale", 1.0))
			var expected := base if tier == "veteran" else base * 1.48
			_check(is_equal_approx(late.max_health, expected), "%s wave-5 crawler HP %.1f, expected %.1f" % [tier, late.max_health, expected])
		await _teardown()

func _test_bomber_fuse_can_be_dodged() -> void:
	await _make_world("veteran")
	var bomber := await _spawn("brute")
	if is_instance_valid(bomber):
		var player := world.player
		player.global_position = bomber.global_position + Vector3(1.0, 0.0, 0.0)
		var before := player.health + player.shield
		var desired := bomber._tactical_bomber(0.0, 1.0, Vector3(1.0, 0.0, 0.0), true)
		_check(desired == Vector3.ZERO and bomber.fuse_left > 0.0, "a bomber in reach must light its fuse")
		_check(player.health + player.shield == before, "the fuse is the warning, not the hit")
		# Run clear before the fuse burns down.
		var clear := bomber.blast_radius + 2.0
		player.global_position = bomber.global_position + Vector3(clear, 0.0, 0.0)
		bomber._tactical_bomber(bomber.fuse_left, clear, Vector3(clear, 0.0, 0.0), true)
		_check(bomber.dead and bomber.exploded, "a burnt-down fuse must detonate the bomber")
		_check(player.health + player.shield == before, "leaving the blast radius must dodge it")
	await _teardown()

func _test_bomber_blast_hits_a_close_player() -> void:
	await _make_world("veteran")
	var bomber := await _spawn("brute")
	if is_instance_valid(bomber):
		var player := world.player
		player.global_position = bomber.global_position + Vector3(1.0, 0.0, 0.0)
		var before := player.health + player.shield
		bomber._light_fuse()
		bomber._tactical_bomber(bomber.fuse_left, 1.0, Vector3(1.0, 0.0, 0.0), true)
		_check(player.health + player.shield < before, "a player inside the blast must be hurt")
	await _teardown()

func _test_shot_bomber_takes_the_pack() -> void:
	await _make_world("veteran")
	var bomber := await _spawn("brute")
	var first := await _spawn("crawler")
	var second := await _spawn("crawler")
	if is_instance_valid(bomber) and is_instance_valid(first) and is_instance_valid(second):
		first.global_position = bomber.global_position + Vector3(0.8, 0.0, 0.0)
		second.global_position = bomber.global_position + Vector3(0.0, 0.0, 1.0)
		var player := world.player
		player.global_position = bomber.global_position + Vector3(20.0, 0.0, 0.0)
		var before := player.health + player.shield
		bomber.take_damage(bomber.max_health * 2.0, Vector3.ZERO, player)
		_check(bomber.dead and bomber.exploded, "a bomber shot dead must still burst")
		_check(first.dead and second.dead, "the burst must take the crawlers beside it")
		_check(player.health + player.shield == before, "a distant shooter is outside the blast")
	await _teardown()

func _test_pouncer_catches_a_backpedal() -> void:
	await _make_world("veteran")
	var pouncer := await _spawn("pouncer")
	if is_instance_valid(pouncer):
		var player := world.player
		var backpedal := Vector3(8.2, 0.0, 0.0)
		var reach := pouncer.pounce_range
		player.global_position = pouncer.global_position + Vector3(reach, 0.0, 0.0)
		pouncer.target_velocity = backpedal
		pouncer._tactical_pouncer(0.0, reach, Vector3(reach, 0.0, 0.0), true)
		_check(pouncer.pounce_windup_left > 0.0, "a pouncer at the edge of its reach must wind up")
		_check(pouncer.holds_attack_token, "a pounce must go through the attack-token pool")
		# The player keeps backing away for the whole wind-up.
		player.global_position += backpedal * WarfareEnemy.POUNCE_WINDUP
		var gap := pouncer.global_position.distance_to(player.global_position)
		pouncer._tactical_pouncer(pouncer.pounce_windup_left, gap, Vector3(gap, 0.0, 0.0), true)
		_check(pouncer.pounce_flight_left > 0.0, "the wind-up must end in a leap")
		var flight := pouncer.pounce_flight_left
		_check(flight < WarfareEnemy.POUNCE_MAX_FLIGHT, "the leap must land before its flight cap, took %.2f s" % flight)
		var landing := pouncer.global_position + pouncer.pounce_velocity * flight
		var fled_to := player.global_position + backpedal * flight
		var miss := Vector2(landing.x - fled_to.x, landing.z - fled_to.z).length()
		_check(miss <= WarfareEnemy.POUNCE_HIT_RADIUS, "the leap must land on a player backing straight away, missed by %.2f m" % miss)
	await _teardown()

func _test_pouncer_leap_hits_or_misses() -> void:
	await _make_world("veteran")
	var pouncer := await _spawn("pouncer")
	if is_instance_valid(pouncer):
		var player := world.player
		pouncer._claim_attack_token()
		pouncer.pounce_velocity = Vector3(WarfareEnemy.POUNCE_LEAP_SPEED, 0.0, 0.0)
		pouncer.pounce_flight_left = 0.5
		player.global_position = pouncer.global_position + Vector3(1.0, 0.0, 0.0)
		var before := player.health + player.shield
		pouncer._tactical_pouncer(0.016, 1.0, Vector3(1.0, 0.0, 0.0), true)
		_check(player.health + player.shield < before, "a leap that reaches the player must hurt")
		_check(pouncer.pounce_recovery_left > 0.0 and not pouncer.holds_attack_token, "landing must leave it exposed and free its token")
		# A sideways dash leaves the leap line: no damage, and it still lands exposed.
		pouncer.pounce_recovery_left = 0.0
		pouncer.pounce_flight_left = 0.3
		player.global_position = pouncer.global_position + Vector3(2.0, 0.0, 3.5)
		before = player.health + player.shield
		pouncer._tactical_pouncer(0.3, 4.0, Vector3(2.0, 0.0, 3.5), true)
		_check(player.health + player.shield == before, "a sideways dash must dodge the leap")
		_check(pouncer.pounce_recovery_left > 0.0, "a missed leap must still end in a recovery")
	await _teardown()

func _test_surround_spawns_come_from_every_side() -> void:
	await _make_world("veteran")
	world.wave_spawn_bearings.clear()
	var origin := world.player.global_position
	var sides := {}
	var previous := Vector3.INF
	for group in range(6):
		# Go through the wave spawner's own entry point, not the helper.
		var spawn := world._choose_swarm_group_origin(previous)
		previous = spawn
		_check(spawn != Vector3.INF, "sector 1 must offer a surround spawn for group %d" % group)
		if spawn == Vector3.INF:
			break
		var offset := Vector2(spawn.x - origin.x, spawn.z - origin.z)
		_check(offset.length() >= WarfareGameWorld.SURROUND_MIN_DISTANCE - 0.01, "a surround spawn landed on top of the player")
		var bearing := atan2(offset.x, offset.y)
		sides[int(wrapf(bearing + PI * 0.25, 0.0, TAU) / (PI * 0.5))] = true
	_check(sides.size() >= 3, "six groups must arrive from at least three sides, got %d" % sides.size())
	await _teardown()

func _test_director_breathes_after_a_peak() -> void:
	await _make_world("veteran")
	world.spawning = true
	world.intensity = WarfareGameWorld.INTENSITY_PEAK + 5.0
	world._update_director(0.0)
	_check(world._director_holds_spawns(), "past the peak the rest of the wave must wait")
	for step in range(20):
		world._update_director(0.5)
	_check(not world._director_holds_spawns(), "the hold must end once the player has breathed")
	_check(world.peak_ready, "calming down must re-arm the next peak")
	# A capped hold must never stall the wave, even if the pressure stays up.
	world.intensity = 100.0
	world._update_director(0.0)
	world._update_director(WarfareGameWorld.RELAX_MAX_HOLD + 0.1)
	world.intensity = 90.0
	world._update_director(0.0)
	_check(not world._director_holds_spawns(), "one peak earns one capped hold, not an endless one")
	# Damage taken is pressure.
	world.intensity = 0.0
	world._update_director(0.0)
	var pool_max := world.player.max_health + world.player.max_shield
	world.player.health -= pool_max * 0.2
	world._update_director(0.0)
	_check(world.intensity >= WarfareGameWorld.INTENSITY_PER_HEALTH * 0.2 - 0.5, "losing a fifth of the pool must raise the pressure, got %.1f" % world.intensity)
	await _teardown()
	await _make_world("recruit")
	world.spawning = true
	world.intensity = 90.0
	world._update_director(0.016)
	_check(not world._director_holds_spawns(), "recruit has no pacing director")
	await _teardown()

func _test_director_hold_pauses_the_spawner() -> void:
	await _make_world("veteran")
	# Mid pressure with the peak already spent: the hold runs on its own timer.
	world.intensity = 60.0
	world.peak_ready = false
	world.relax_hold_left = 30.0
	world._start_next_wave()
	await get_tree().create_timer(0.6).timeout
	_check(world.total_spawned == 0, "a held wave must not spawn, got %d" % world.total_spawned)
	world.relax_hold_left = 0.0
	var waited := 0.0
	while world.total_spawned == 0 and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(world.total_spawned > 0, "releasing the hold must resume the wave")
	# Let the spawner coroutine see completion before the world is freed.
	world.completed = true
	while world.spawning and waited < 4.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await _teardown()
