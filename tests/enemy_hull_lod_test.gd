extends Node

# Distance tiers share one damage body. The far tier must cover the animated
# torso without enabling the walking capsule, and returning near must restore
# the current limb pose. Sample rendered geometry independently below.

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("HULL LOD TEST: " + message)

func _shootable(world: WarfareGameWorld, enemy: WarfareEnemy, aim: Vector3) -> bool:
	# Mask 2 is the weapon layer: whatever answers here is what a bullet hits.
	var origin: Vector3 = aim + Vector3(6.0, 0.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, aim + (aim - origin).normalized() * 0.3, 2)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and EnemyHitGeometry.resolve(hit.collider) == enemy

func _settle(frames: int = 2) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	world.completed = true
	world.player.set_physics_process(false)
	await _settle()

	var enemy := world._spawn_enemy("crawler", false)
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health
	enemy.speed = 0.0
	enemy.spawn_left = 0.0
	enemy.model.position.y = 0.0
	await _settle()

	var anchor: Vector3 = world.player.global_position

	# --- near tier: hulls drive collision, capsule is parked on layer 0 -------
	enemy.global_position = anchor + Vector3(0.0, 0.0, 6.0)
	await _settle(3)
	_check(enemy.hulls_active, "enemy 6 m away is not in the per-bone tier")
	_check(enemy.collision_layer == 0, "near enemy capsule should stay off layer 2")
	_check(enemy.animated_hitbox.collision_layer == 2, "near enemy hulls are not on layer 2")
	var near_aim: Vector3 = enemy.global_position + Vector3.UP * 1.0
	_check(_shootable(world, enemy, near_aim), "near enemy is not shootable through its hulls")

	# --- far tier: one animated damage box, walking capsule stays separate ---
	enemy.global_position = anchor + Vector3(0.0, 0.0, 45.0)
	await _settle(3)
	_check(not enemy.hulls_active, "enemy 45 m away is still paying for per-bone hulls")
	_check(enemy.collision_layer == 0, "far tier exposed the walking capsule to weapons")
	_check(enemy.animated_hitbox.collision_layer == 2, "far damage body lost its weapon layer")
	_check(not enemy.animated_hitbox.coarse_collision.disabled, "far damage box is disabled")
	for part in enemy.animated_hitbox.parts:
		_check(part.collision.disabled, "far tier left a detailed physics shape enabled")
	var far_aim: Vector3 = enemy.global_position + Vector3.UP * 1.0
	_check(_shootable(world, enemy, far_aim), "FAR ENEMY IS UNSHOOTABLE -- bullets pass straight through")

	# --- hysteresis: the far threshold must not flip it back -----------------
	enemy.global_position = anchor + Vector3(0.0, 0.0, 30.0)
	await _settle(3)
	_check(not enemy.hulls_active, "enemy between the two thresholds flipped tier; hysteresis is broken")

	# --- return: hulls reconnect AND re-sync to the live pose -----------------
	enemy.global_position = anchor + Vector3(0.0, 0.0, 8.0)
	await _settle(3)
	_check(enemy.hulls_active, "enemy back at 8 m did not return to the per-bone tier")
	_check(enemy.collision_layer == 0, "returned enemy left its capsule on layer 2")
	_check(enemy.animated_hitbox.collision_layer == 2, "returned enemy hulls are not back on layer 2")
	_check(enemy.animated_hitbox.coarse_collision.disabled, "near tier left the broad damage box enabled")
	for part in enemy.animated_hitbox.parts:
		_check(not part.collision.disabled, "near tier did not restore a detailed shape")
	var back_aim: Vector3 = enemy.global_position + Vector3.UP * 1.0
	_check(_shootable(world, enemy, back_aim), "returned enemy is not shootable; hulls froze in a stale pose")

	# --- a corpse stops syncing but must not resurrect its hulls -------------
	enemy.global_position = anchor + Vector3(0.0, 0.0, 8.0)
	await _settle()
	enemy._die()
	await _settle()
	_check(enemy.animated_hitbox.collision_layer == 0, "corpse hulls are still shootable")
	var skeleton := enemy.animated_hitbox.parts[0].skeleton as Skeleton3D
	_check(not skeleton.skeleton_updated.is_connected(enemy.animated_hitbox.sync_pose),
		"corpse is still syncing per-bone hulls for the whole death animation")

	enemy.queue_free()
	await get_tree().process_frame
	await _test_visible_torso(world)

	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("ENEMY_HULL_LOD_TEST_PASS checks=%d" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

# Sample rendered triangle centers using all skin weights, independently of
# the per-bone collision hulls. A bind-pose AABB cannot validate a live skin.
func _torso_surface(enemy: WarfareEnemy) -> Vector3:
	var points: Array[Vector3] = []
	var bounds := AABB()
	var first := true
	for child in enemy.model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton == null or mesh.skin == null:
			continue
		skeleton.force_update_all_bone_transforms()
		var matrices: Array[Transform3D] = []
		for bind in range(mesh.skin.get_bind_count()):
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			matrices.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vertices.size()
			var posed := PackedVector3Array()
			for i in range(vertices.size()):
				var point := Vector3.ZERO
				for j in range(stride):
					point += (matrices[bones[i * stride + j]] * vertices[i]) * weights[i * stride + j]
				posed.append(point)
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
			for i in range(0, indices.size(), 3):
				points.append((posed[indices[i]] + posed[indices[i + 1]] + posed[indices[i + 2]]) / 3.0)
	var desired := bounds.get_center()
	desired.y = lerpf(bounds.position.y, bounds.end.y, 0.7)
	var best := Vector3.INF
	var distance := INF
	for point in points:
		if point.y < lerpf(bounds.position.y, bounds.end.y, 0.55):
			continue
		var score := point.distance_squared_to(desired)
		if score < distance:
			distance = score
			best = point
	return best

func _test_visible_torso(world: WarfareGameWorld) -> void:
	# Sample the rendered skin independently of the collision implementation.
	# Freeze above the map, then send the SAME 45 m ray through both LOD tiers.
	for kind in ["crawler", "spitter", "brute", "boss"]:
		var enemy := world._spawn_enemy(kind, false)
		enemy.set_physics_process(false)
		enemy.spawn_left = 0.0
		enemy.model.position.y = 0.0
		enemy.global_position = Vector3(0.0, 100.0, 0.0)
		# Hold the far tier across animation changes as well as testing switches.
		for distance in [8.0, 45.0, 8.0]:
			enemy._update_hull_detail(distance)
			for clip in ["idle", "run", "attack"]:
				var animator := enemy.recovered_animation_player
				animator.play(clip, 0.0)
				animator.advance(0.0)
				animator.seek(animator.get_animation(clip).length * 0.4, true)
				animator.pause()
				var aim := _torso_surface(enemy)
				_check(aim != Vector3.INF, "%s %s has no visible torso" % [kind, clip])
				await _settle()
				for direction in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK]:
					var origin: Vector3 = aim + direction * 45.0 + Vector3.UP * 0.4
					var query := PhysicsRayQueryParameters3D.create(origin, aim + (aim - origin).normalized() * 0.2, 2)
					var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
					_check(not hit.is_empty() and EnemyHitGeometry.resolve(hit.collider) == enemy,
						"%s %s view=%s tier_distance=%.0f misses visible torso" % [kind, clip, direction, distance])
		enemy._update_hull_detail(45.0)
		enemy._die()
		await _settle()
		var death_query := PhysicsRayQueryParameters3D.create(enemy.global_position + Vector3(0, 1, -20), enemy.global_position + Vector3(0, 1, 20), 2)
		_check(world.get_world_3d().direct_space_state.intersect_ray(death_query).is_empty(), "%s far corpse still blocks shots" % kind)
		enemy.queue_free()
		await get_tree().process_frame
