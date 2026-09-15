extends Node

# Micro-benchmark for the two per-frame hot spots that scale with enemy count:
# EnemyHitGeometry.sync_pose (one transform write per bone) and
# WarfareEnemy._refresh_separation (a scan over every other enemy).
#
# It times the functions directly rather than sampling frame duration. Godot's
# headless physics tick is pinned at 60 Hz, so wall-clock per frame reads ~16.6 ms
# whether there are 8 enemies or 80 -- that number is the tick interval, not the
# work, and an earlier version of this file was fooled by exactly that.
#
# Each hot spot is also run against the pre-optimisation implementation, kept
# here verbatim, so the speedup is measured rather than asserted and the two
# implementations can be checked for identical output.

const REPEATS := 200

var results: Array[String] = []
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

# --- pre-optimisation implementations, preserved for comparison -------------

func _sync_pose_legacy(hitbox: EnemyHitGeometry) -> void:
	if not hitbox.is_inside_tree():
		return
	for part in hitbox.parts:
		var skeleton: Skeleton3D = part.skeleton
		var collision: CollisionShape3D = part.collision
		collision.transform = hitbox.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(int(part.bone))

func _separation_legacy(enemy: WarfareEnemy) -> Vector3:
	var separation := Vector3.ZERO
	if enemy.separation_radius <= 0.0:
		return separation
	for other_node in get_tree().get_nodes_in_group("enemies"):
		var other := other_node as Node3D
		if other == enemy or not is_instance_valid(other):
			continue
		var offset := Vector3(enemy.global_position.x - other.global_position.x, 0.0,
			enemy.global_position.z - other.global_position.z)
		var gap := offset.length()
		if gap > 0.001 and gap < enemy.separation_radius:
			separation += offset / gap * (1.0 - gap / enemy.separation_radius)
	return separation

# ---------------------------------------------------------------------------

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("BENCHMARK: " + message)

func _spawn_ring(world: WarfareGameWorld, count: int, spread: float) -> Array[WarfareEnemy]:
	var enemies: Array[WarfareEnemy] = []
	var anchor: Vector3 = world.player.global_position
	for i in range(count):
		var enemy := world._spawn_enemy("crawler", false)
		if enemy == null:
			continue
		# Pack them at a realistic crowd density rather than one thin ring, so
		# the separation scan sees the neighbour counts a real wave produces.
		var angle := TAU * float(i) / 12.0
		var radius: float = spread + float(i / 12) * 2.2
		enemy.global_position = anchor + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		enemy.speed = 0.0
		enemy.spawn_left = 0.0
		enemy.model.position.y = 0.0
		enemy.max_health = 1000000.0
		enemy.health = enemy.max_health
		enemies.append(enemy)
	return enemies

func _clear(enemies: Array[WarfareEnemy]) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

func _bench_sync(enemies: Array[WarfareEnemy]) -> void:
	var live: Array[EnemyHitGeometry] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and is_instance_valid(enemy.animated_hitbox) and not enemy.animated_hitbox.parts.is_empty():
			live.append(enemy.animated_hitbox)
	if live.is_empty():
		return
	var bones := 0
	for hitbox in live:
		bones += hitbox.parts.size()

	var start := Time.get_ticks_usec()
	for r in range(REPEATS):
		for hitbox in live:
			hitbox.sync_pose()
	var now_us := float(Time.get_ticks_usec() - start) / float(REPEATS)

	start = Time.get_ticks_usec()
	for r in range(REPEATS):
		for hitbox in live:
			_sync_pose_legacy(hitbox)
	var was_us := float(Time.get_ticks_usec() - start) / float(REPEATS)

	results.append("sync_pose   n=%3d (%4d hulls)  before %7.1f us  after %7.1f us  = %.2fx  [%.2f%% of a 16.6 ms frame]" % [
		live.size(), bones, was_us, now_us, was_us / maxf(now_us, 0.001), now_us / 16600.0 * 100.0])

func _bench_separation(enemies: Array[WarfareEnemy]) -> void:
	var live: Array[WarfareEnemy] = []
	for enemy in enemies:
		if is_instance_valid(enemy):
			live.append(enemy)
	if live.is_empty():
		return

	# Equivalence first: the rewrite rejects on the squared gap before taking a
	# square root, which must not change a single resulting vector.
	var worst := 0.0
	for enemy in live:
		var expected := _separation_legacy(enemy)
		enemy.separation_refresh = -1.0
		enemy._refresh_separation(0.0)
		worst = maxf(worst, enemy.separation_vector.distance_to(expected))
	_check(worst < 0.00001, "separation rewrite changed the result by %.9f" % worst)

	var start := Time.get_ticks_usec()
	for r in range(REPEATS):
		for enemy in live:
			enemy.separation_refresh = -1.0
			enemy._refresh_separation(0.0)
	var now_us := float(Time.get_ticks_usec() - start) / float(REPEATS)

	start = Time.get_ticks_usec()
	for r in range(REPEATS):
		for enemy in live:
			_separation_legacy(enemy)
	var was_us := float(Time.get_ticks_usec() - start) / float(REPEATS)

	results.append("separation  n=%3d              before %7.1f us  after %7.1f us  = %.2fx  (max delta %.8f)" % [
		live.size(), was_us, now_us, was_us / maxf(now_us, 0.001), worst])

func _measure(world: WarfareGameWorld, count: int) -> void:
	var enemies := _spawn_ring(world, count, 6.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_bench_sync(enemies)
	_bench_separation(enemies)
	results.append("")
	await _clear(enemies)

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.set_setting("difficulty", "veteran")
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	world.completed = true
	world.player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Is the hull cache shared? It keys on the Skin object's instance id, so if
	# instantiate() hands out a fresh Skin per enemy, every spawn rebuilds every
	# convex hull from raw triangles instead of reusing one set.
	EnemyHitGeometry.mesh_parts.clear()
	var probe := _spawn_ring(world, 12, 6.0)
	await get_tree().physics_frame
	var cache_entries := EnemyHitGeometry.mesh_parts.size()
	await _clear(probe)

	# A warm pass so one-off hull building never lands inside a timed run.
	var warm := _spawn_ring(world, 8, 6.0)
	await get_tree().physics_frame
	_bench_sync(warm)
	results.clear()
	results.append("hull cache: %d entry/entries for 12 crawlers (1 = shared, 12 = rebuilt per enemy)" % cache_entries)
	results.append("")
	await _clear(warm)

	for count in [8, 40, 80]:
		await _measure(world, count)

	print("=== ENEMY CROWD BENCHMARK (headless: GDScript + physics only, no GPU) ===")
	for line in results:
		print(line)
	if failures.is_empty():
		print("ENEMY_SCALE_BENCHMARK_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
