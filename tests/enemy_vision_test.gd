extends Node3D

# Exercise real enemy physics, target bodies and world occluders. Navigation
# records its destination so a hidden live position cannot masquerade as memory.
class VisionArena extends Node3D:
	var destinations: Array[Vector3] = []
	func get_enemy_navigation_target(_from: Vector3, destination: Vector3) -> Vector3:
		destinations.append(destination)
		return destination

var failures: Array[String] = []
var checks := 0
var arena: VisionArena
var player: WarfarePlayer
var enemy: WarfareEnemy
var wall: StaticBody3D

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("ENEMY VISION: " + message)

func _reset() -> void:
	enemy.position = Vector3.ZERO
	enemy.rotation = Vector3.ZERO
	enemy.velocity = Vector3.ZERO
	enemy.awareness = WarfareEnemy.Awareness.UNAWARE
	enemy.detection_progress = 0.0
	enemy.last_seen_position = Vector3.INF
	enemy.last_target_position = Vector3.INF
	enemy.target_velocity = Vector3.ZERO
	enemy.navigation_target = Vector3.INF
	enemy.windup_left = 0.0
	enemy.attack_cooldown = 0.0
	enemy._release_attack_token()
	enemy.model.position = Vector3.ZERO
	player.position = Vector3(0, 0, -10)
	arena.destinations.clear()

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	arena = VisionArena.new()
	add_child(arena)
	player = WarfarePlayer.new()
	arena.add_child(player)
	player.set_physics_process(false)
	enemy = WarfareEnemy.new()
	enemy.configure(player, "crawler", 1000.0)
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.spawn_left = 0.0
	enemy.gravity = 0.0
	wall = StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(100, 2, -5)
	arena.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_reset()
	_check(enemy._can_see_target(), "front target in range must be visible")
	player.position = Vector3(0, 0, 10)
	_check(not enemy._can_see_target(), "rear target must remain unseen")
	for i in range(60):
		enemy._physics_process(1.0 / 60.0)
	_check(enemy.awareness == WarfareEnemy.Awareness.UNAWARE, "idle AI acquired rear target")
	_check(enemy.position.is_equal_approx(Vector3.ZERO), "unaware AI chased hidden target")
	_check(arena.destinations.is_empty(), "unaware AI asked for the player's route")
	player.position = Vector3(10, 0, 0)
	_check(not enemy._can_see_target(), "side target outside cone must remain unseen")
	player.position = Vector3(0, 0, -enemy.sight_distance - 1.0)
	_check(not enemy._can_see_target(), "target beyond sight range must remain unseen")
	player.position = Vector3(0, 0, -10).rotated(Vector3.UP, deg_to_rad(50))
	_check(enemy._can_see_target(), "target inside cone edge was lost")
	player.position = Vector3(0, 0, -10).rotated(Vector3.UP, deg_to_rad(60))
	_check(not enemy._can_see_target(), "target outside cone edge was seen")

	_reset()
	enemy._physics_process(0.1)
	_check(enemy.awareness == WarfareEnemy.Awareness.SUSPICIOUS, "brief sighting must start suspicion")
	_check(enemy.velocity.is_zero_approx(), "suspicion must not begin a chase")
	player.position = Vector3(0, 0, 10)
	enemy._physics_process(0.1)
	_check(enemy.awareness == WarfareEnemy.Awareness.UNAWARE, "brief sighting must decay when hidden")
	player.position = Vector3(0, 0, -10)
	enemy._physics_process(enemy.detection_time + 0.01)
	_check(enemy.awareness == WarfareEnemy.Awareness.ENGAGED, "sustained sighting must engage")
	enemy._physics_process(0.1)
	_check(enemy.velocity.length() > 0.0, "engaged enemy must use the combat brain")

	_reset()
	wall.position = Vector3(0, 2, -5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not enemy._can_see_target(), "solid cover must block acquisition")
	enemy._physics_process(1.0)
	_check(enemy.awareness == WarfareEnemy.Awareness.UNAWARE, "wall must prevent pursuit")
	# Low cover hides the chest but exposes the head: one clear ray suffices.
	wall.position.y = -0.75
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(enemy._can_see_target(), "head visible over low cover must be detectable")
	wall.position.x = 100
	await get_tree().physics_frame
	await get_tree().physics_frame

	_reset()
	enemy._physics_process(enemy.detection_time + 0.01)
	var remembered := enemy.last_seen_position
	enemy._claim_attack_token()
	enemy._begin_melee_windup()
	wall.position = Vector3(0, 2, -5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.position = Vector3(2, 0, -12)
	enemy._physics_process(0.1)
	_check(enemy.awareness == WarfareEnemy.Awareness.SEARCHING, "losing sight must start search")
	_check(enemy.last_seen_position == remembered, "hidden movement leaked into last sighting")
	_check(arena.destinations.back() == remembered, "search path followed hidden current position")
	_check(not enemy.holds_attack_token and enemy.windup_left == 0.0, "lost sight must cancel queued melee and token")
	_check(enemy.target_velocity == Vector3.ZERO, "search retained hidden velocity prediction")
	_check(not enemy.attack_motion.is_running(), "lost sight left the lunge tween running")
	# Reacquisition must reset aim history rather than lead across hidden time.
	wall.position.x = 100
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy.rotation = Vector3.ZERO
	enemy._physics_process(0.01)
	_check(enemy.awareness == WarfareEnemy.Awareness.ENGAGED, "search must reacquire visible player")
	_check(enemy.target_velocity == Vector3.ZERO, "reacquisition manufactured a velocity spike")
	player.position = Vector3(0, 0, 100)
	enemy._physics_process(0.1)
	enemy._physics_process(enemy.search_duration + 0.1)
	_check(enemy.awareness == WarfareEnemy.Awareness.UNAWARE, "search must eventually end")
	_check(enemy.last_seen_position == Vector3.INF, "search expiry retained target location")

	_reset()
	player.position = Vector3(0, 0, 10)
	enemy.take_damage(1, enemy.position, player)
	_check(enemy.awareness == WarfareEnemy.Awareness.SEARCHING, "rear damage must alert the victim")
	_check(enemy.last_seen_position == player.position, "damage must record impact-time attacker position")
	var impact_position := enemy.last_seen_position
	player.position = Vector3(50, 0, 10)
	enemy._physics_process(0.1)
	_check(enemy.last_seen_position == impact_position, "damage granted ongoing sight of hidden attacker")

	_reset()
	player.position = Vector3(0, 0, -2)
	wall.position = Vector3(0, 2, -1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before := player.health + player.shield
	enemy._resolve_melee_windup()
	_check(player.health + player.shield == before, "melee resolved through cover")
	var child_count := arena.get_child_count()
	enemy._tactical_boss(2.0, Vector3.FORWARD, false)
	_check(player.health + player.shield == before and arena.get_child_count() == child_count, "boss attacked without sight")
	player.dead = true
	_check(not enemy._can_see_target(), "dead player must not be perceived")
	enemy._claim_attack_token()
	enemy._physics_process(0.1)
	_check(not enemy.holds_attack_token, "dead player must release attack token")

	player.dead = false
	for kind in ["spitter", "brute", "boss"]:
		var other := WarfareEnemy.new()
		other.configure(player, kind, 100.0)
		other.position = Vector3(20, 0, 0)
		arena.add_child(other)
		other.set_physics_process(false)
		other.spawn_left = 0.0
		other.rotation = Vector3.ZERO
		player.position = other.position + Vector3(0, 0, -10)
		_check(other._can_see_target(), kind + " must see a front target")
		other._update_perception(other.detection_time + 0.01)
		_check(other.awareness == WarfareEnemy.Awareness.ENGAGED, kind + " must acquire through perception")
		player.position = other.position + Vector3(0, 0, 10)
		other._update_perception(0.1)
		_check(other.awareness == WarfareEnemy.Awareness.SEARCHING, kind + " must lose rear target")
		other.free()

	arena.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	print("ENEMY_VISION_TEST_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)
