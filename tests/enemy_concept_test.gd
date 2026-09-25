extends Node3D

const Catalog = preload("res://scripts/core/monster_catalog.gd")
const CONCEPT_PATH := "res://assets/models/enemies/concept/warrior/warrior.gltf"
const ORIGINAL_PATH := "res://assets/models/enemies/animated/bug01/bug01.gltf"
const TEXTURE_PATH := "res://assets/models/enemies/concept/warrior/warrior_albedo.png"
const REQUIRED_CLIPS := ["idle", "run", "run01", "run02", "attack", "attacked", "dead", "dead01"]

var failures: Array[String] = []
var checks := 0
var rays := 0


func _ready() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("ENEMY CONCEPT TEST: " + message)


func _enemy(kind: String, concept: bool, location: Vector3) -> WarfareEnemy:
	var enemy := WarfareEnemy.new()
	enemy.use_concept_visuals = concept
	enemy.configure_recovered(null, kind)
	enemy.position = location
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.spawn_left = 0.0
	enemy.model.position = Vector3.ZERO
	return enemy


func _skeleton(enemy: WarfareEnemy) -> Skeleton3D:
	for node in enemy.model.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


func _pose(enemy: WarfareEnemy, clip: String, fraction: float) -> void:
	var animator := enemy.recovered_animation_player
	animator.play(clip, 0.0)
	animator.advance(0.0)
	animator.seek(animator.get_animation(clip).length * fraction, true)
	animator.pause()
	var skeleton := _skeleton(enemy)
	if skeleton:
		skeleton.force_update_all_bone_transforms()
	if enemy.animated_hitbox:
		enemy.animated_hitbox.sync_pose()


# Derive visible triangle centres from the rendered skin independently of the
# hull builder. Also count vertices actually weighted to each added bone.
func _skin_sample(enemy: WarfareEnemy, added_names: Array[String]) -> Dictionary:
	var bounds := AABB()
	var first := true
	var triangles: Array[Vector3] = []
	var weighted: Dictionary = {}
	var extra_points: Dictionary = {}
	for node in enemy.model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if mesh.mesh == null or mesh.skin == null or skeleton == null:
			continue
		var matrices: Array[Transform3D] = []
		var names: Array[String] = []
		for bind in range(mesh.skin.get_bind_count()):
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			if bone < 0 or bone >= skeleton.get_bone_count():
				_check(false, "skin references a missing skeleton bone")
				return {"bounds": AABB(), "aim": Vector3.INF, "weighted": {}, "extra_points": {}}
			matrices.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
			names.append(str(skeleton.get_bone_name(bone)))
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			if bones.size() % vertices.size() != 0 or weights.size() != bones.size() or indices.size() % 3 != 0:
				_check(false, "malformed skin arrays or triangle indices")
				continue
			var valid_indices := true
			for vertex_index in indices:
				if vertex_index < 0 or vertex_index >= vertices.size():
					valid_indices = false
					break
			if not valid_indices:
				_check(false, "triangle references a missing skin vertex")
				continue
			var stride := int(bones.size() / vertices.size())
			var posed := PackedVector3Array()
			for i in range(vertices.size()):
				var point := Vector3.ZERO
				var influenced: Dictionary = {}
				for j in range(stride):
					var bind := bones[i * stride + j]
					var weight := weights[i * stride + j]
					if bind < 0 or bind >= matrices.size():
						_check(false, "skin vertex references an invalid bind")
						continue
					point += (matrices[bind] * vertices[i]) * weight
					if weight >= 0.1 and names[bind] in added_names:
						weighted[names[bind]] = int(weighted.get(names[bind], 0)) + 1
						influenced[names[bind]] = true
				for bone_name: String in influenced:
					var points: PackedVector3Array = extra_points.get(bone_name, PackedVector3Array())
					if points.size() < 64:
						points.append(point)
						extra_points[bone_name] = points
				posed.append(point)
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
			for i in range(0, indices.size(), 3):
				triangles.append((posed[indices[i]] + posed[indices[i + 1]] + posed[indices[i + 2]]) / 3.0)
	var desired := bounds.get_center()
	desired.y = lerpf(bounds.position.y, bounds.end.y, 0.68)
	var aim := Vector3.INF
	var score := INF
	for point in triangles:
		if point.y < lerpf(bounds.position.y, bounds.end.y, 0.5):
			continue
		var distance := point.distance_squared_to(desired)
		if distance < score:
			score = distance
			aim = point
	return {"bounds": bounds, "aim": aim, "weighted": weighted, "extra_points": extra_points}


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _run() -> void:
	_check(ResourceLoader.exists(CONCEPT_PATH), "concept scene has not been imported")
	_check(Catalog.visual_scene_path("crawler", true) == CONCEPT_PATH, "live crawler silently fell back to recovered art")
	_check(Catalog.visual_scene_path("crawler", false) == ORIGINAL_PATH, "baseline selector does not select original")
	if not ResourceLoader.exists(CONCEPT_PATH):
		get_tree().quit(1)
		return
	var baseline := _enemy("crawler", false, Vector3(15, 100, 0))
	var enemy := _enemy("crawler", true, Vector3(0, 100, 0))
	_check(enemy.recovered_enemy != null and enemy.recovered_enemy.scene_file_path == CONCEPT_PATH, "actual instantiated crawler is not concept scene")
	_check(baseline.recovered_enemy != null and baseline.recovered_enemy.scene_file_path == ORIGINAL_PATH, "baseline instance was replaced")
	if enemy.recovered_enemy == null or baseline.recovered_enemy == null:
		get_tree().quit(1)
		return
	var original_skeleton := _skeleton(baseline)
	var skeleton := _skeleton(enemy)
	_check(skeleton != null and original_skeleton != null, "missing imported skeleton")
	_check(enemy.recovered_animation_player != null, "missing concept animation player")
	if skeleton == null or original_skeleton == null or enemy.recovered_animation_player == null:
		get_tree().quit(1)
		return
	_check(original_skeleton.get_bone_count() == 22, "baseline no longer has the original 22 bones")
	var original_names: Array[String] = []
	for bone in range(original_skeleton.get_bone_count()):
		var bone_name := str(original_skeleton.get_bone_name(bone))
		original_names.append(bone_name)
		_check(skeleton.find_bone(bone_name) >= 0, "concept lost original bone: " + bone_name)
	var added_names: Array[String] = []
	for bone in range(skeleton.get_bone_count()):
		var bone_name := str(skeleton.get_bone_name(bone))
		if bone_name not in original_names:
			added_names.append(bone_name)
	_check(added_names.size() >= 8, "new scythe/mandible rig has fewer than eight extra bones")
	var all_clips := true
	for clip: String in REQUIRED_CLIPS:
		var present := enemy.recovered_animation_player.has_animation(clip)
		_check(present, "missing original clip: " + clip)
		all_clips = all_clips and present
	if not all_clips:
		get_tree().quit(1)
		return
	var uses_texture := false
	for node in enemy.model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			_check(false, "concept contains a MeshInstance3D with no mesh")
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material and material.albedo_texture and material.albedo_texture.resource_path == TEXTURE_PATH:
				uses_texture = true
	_check(uses_texture, "no live mesh material uses warrior_albedo.png")
	_pose(enemy, "idle", 0.0)
	var sample := _skin_sample(enemy, added_names)
	var bounds: AABB = sample.bounds
	_check(absf(bounds.size.y - WarfareEnemy.TARGET_HEIGHTS.crawler) < 0.04, "idle posed skin is not the 2 m target height")
	_check(absf(bounds.position.y - enemy.global_position.y) < 0.04, "idle visible feet are not grounded")
	for bone_name in added_names:
		_check(int(sample.weighted.get(bone_name, 0)) >= 4, "added bone has no real skinned geometry: " + bone_name)
	var moved: Dictionary = {}
	var geometry_moved: Dictionary = {}
	for clip: String in ["run", "attack", "dead"]:
		_pose(enemy, clip, 0.1)
		var first_points: Dictionary = _skin_sample(enemy, added_names).extra_points
		var first_poses: Dictionary = {}
		for bone_name in added_names:
			first_poses[bone_name] = skeleton.get_bone_pose(skeleton.find_bone(bone_name))
		_pose(enemy, clip, 0.65)
		var later_points: Dictionary = _skin_sample(enemy, added_names).extra_points
		for bone_name in added_names:
			var before: Transform3D = first_poses[bone_name]
			var after := skeleton.get_bone_pose(skeleton.find_bone(bone_name))
			if not before.is_equal_approx(after):
				moved[bone_name] = true
			var initial: PackedVector3Array = first_points.get(bone_name, PackedVector3Array())
			var later: PackedVector3Array = later_points.get(bone_name, PackedVector3Array())
			for i in range(mini(initial.size(), later.size())):
				if initial[i].distance_to(later[i]) > 0.002:
					geometry_moved[bone_name] = true
					break
	for bone_name in added_names:
		_check(moved.has(bone_name), "extra bone never articulates in run/attack/dead: " + bone_name)
		_check(geometry_moved.has(bone_name), "weighted geometry never moves with extra bone: " + bone_name)
	_check(enemy.animated_hitbox != null and not enemy.animated_hitbox.parts.is_empty(), "concept skin built no animated damage hulls")
	if enemy.animated_hitbox == null or enemy.animated_hitbox.parts.is_empty():
		get_tree().quit(1)
		return
	_check(enemy.collision_layer == 0, "walking capsule incorrectly receives weapon hits")
	if enemy.animated_hitbox:
		for bone_name in added_names:
			var found := false
			for part in enemy.animated_hitbox.parts:
				if str((part.skeleton as Skeleton3D).get_bone_name(int(part.bone))) == bone_name:
					found = true
			_check(found, "added skinned limb has no damage hull: " + bone_name)
		for distance in [8.0, 45.0, 8.0]:
			enemy._update_hull_detail(distance)
			for clip: String in ["idle", "run", "attack"]:
				_pose(enemy, clip, 0.4)
				var aim: Vector3 = _skin_sample(enemy, added_names).aim
				_check(aim != Vector3.INF, "no rendered surface to aim at")
				if aim == Vector3.INF:
					continue
				await _settle()
				for direction in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK]:
					var origin: Vector3 = aim + direction * 6.0 + Vector3.UP * 0.25
					var query := PhysicsRayQueryParameters3D.create(origin, aim + (aim - origin).normalized() * 0.3, 2)
					var hit := get_world_3d().direct_space_state.intersect_ray(query)
					_check(not hit.is_empty() and EnemyHitGeometry.resolve(hit.collider) == enemy, "visible %s surface missed at LOD distance %.0f" % [clip, distance])
					rays += 1
	for property: String in ["source_monster_id", "source_monster_name", "max_health", "speed", "attack_damage", "attack_range", "reward", "experience_value"]:
		_check(enemy.get(property) == baseline.get(property), "visual replacement changed gameplay field: " + property)
	for kind: String in ["spitter", "brute", "boss"]:
		_check(Catalog.visual_scene_path(kind, true) == Catalog.visual_scene_path(kind, false), "unrelated species changed: " + kind)
	var health_before := enemy.health
	enemy.take_damage(1.0, bounds.get_center())
	_check(enemy.health == health_before - 1.0 and enemy.recovered_animation_name == "attacked", "hit reaction/damage contract changed")
	enemy.take_damage(enemy.health + 1.0, bounds.get_center())
	_check(enemy.dead and enemy.recovered_animation_name == "dead", "lethal damage did not play death clip")
	_check(enemy.collision_layer == 0 and enemy.animated_hitbox.collision_layer == 0, "dead concept still receives weapon rays")
	await _settle()
	# Audio playback is released by the audio mixer after stop, not synchronously
	# with free(). Allow queued frees and the mixer to finish before engine exit.
	for specimen in [baseline, enemy]:
		for audio in specimen.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
			audio.stream = null
		(specimen as WarfareEnemy).queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	if failures.is_empty():
		print("ENEMY_CONCEPT_TEST_PASS checks=%d rays=%d extra_bones=%d original_bones=22 texture=true baseline=true" % [checks, rays, added_names.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
