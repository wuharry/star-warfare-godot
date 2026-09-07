extends Node

var failures: Array[String] = []
var shots := 0
var occluded := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("MAP HIT TEST: " + message)

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

func _run() -> void:
	var levels: Array = GameState.SINGLEPLAYER_LEVELS.duplicate()
	levels.append(22)
	for level in levels:
		GameState.selected_level = level
		GameState.selected_weapon = "gun00"
		var scene := "res://scenes/expanse.tscn" if level == 22 else "res://scenes/game.tscn"
		var world := (load(scene) as PackedScene).instantiate() as WarfareGameWorld
		add_child(world)
		world.completed = true
		if world is WarfareExpanseWorld:
			world.banked = true
			world.pending_spawn_position = world.player.global_position + Vector3(8.0, 0.0, 8.0)
		world.player.set_physics_process(false)
		world.player.current_weapon.spread = 0.0
		world.player.current_weapon.pellets = 1
		world.player.camera.set_as_top_level(true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var level_shots := shots
		for kind in ["crawler", "spitter", "brute", "boss"]:
			var enemy := world._spawn_enemy(kind, false)
			enemy.max_health = 100000.0
			enemy.health = enemy.max_health
			enemy.set_physics_process(false)
			enemy.spawn_left = 0.0
			enemy.model.position.y = 0.0
			for clip in ["idle", "run", "attack"]:
				var animator := enemy.recovered_animation_player
				animator.play(clip, 0.0)
				animator.advance(0.0)
				animator.seek(animator.get_animation(clip).length * 0.4, true)
				animator.pause()
				var target := _torso_surface(enemy)
				_check(target != Vector3.INF, "%d %s %s has no visible torso" % [level, kind, clip])
				await get_tree().physics_frame
				await get_tree().physics_frame
				for direction in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK]:
					# The previous shot starts a hit-reaction clip; restore the tested
					# pose before aiming from the next side.
					animator.play(clip, 0.0)
					animator.advance(0.0)
					animator.seek(animator.get_animation(clip).length * 0.4, true)
					animator.pause()
					target = _torso_surface(enemy)
					await get_tree().physics_frame
					await get_tree().physics_frame
					var origin: Vector3 = target + direction * 6.0 + Vector3.UP * 0.4
					var query := PhysicsRayQueryParameters3D.create(origin, target + (target - origin).normalized() * 0.2, 2)
					var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
					_check(not hit.is_empty() and EnemyHitGeometry.resolve(hit.collider) == enemy,
						"level=%d %s %s direction=%s misses visible torso at %s" % [level, kind, clip, direction, target])
					query.collision_mask = 1
					var wall := world.get_world_3d().direct_space_state.intersect_ray(query)
					if not wall.is_empty() and (hit.is_empty() or origin.distance_to(wall.position) < origin.distance_to(hit.position)):
						occluded += 1
						continue
					world.player.camera.global_position = origin
					world.player.camera.look_at(target)
					_check(world.player.is_reticle_on_enemy(), "level=%d %s %s reticle does not recognize skin" % [level, kind, clip])
					var before := enemy.health
					world.player._fire_hitscan()
					_check(enemy.health < before, "level=%d %s %s visible rifle shot dealt no damage" % [level, kind, clip])
					shots += 1
				enemy.health = enemy.max_health
			enemy.queue_free()
			await get_tree().process_frame
			await get_tree().physics_frame
		_check(shots > level_shots, "no clear weapon shots exercised on level %d" % level)
		print("MAP_HIT_LEVEL %d rifle_shots=%d" % [level, shots - level_shots])
		world.free()
		AudioDirector.stop_all_sfx()
		await get_tree().process_frame
	if failures.is_empty():
		print("ENEMY_MAP_HIT_TEST_PASS maps=9 species=4 poses=3 rifle_shots=%d blocked_by_map=%d" % [shots, occluded])
	get_tree().quit(0 if failures.is_empty() else 1)
