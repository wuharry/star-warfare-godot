extends Node3D

# EnemyShotScript.cs distinguishes direct damage, Explosion (area only), and
# Sputtering (direct + area). WarfareProjectile's falloff explosion cannot
# express these rules. These deliberately procedural visuals are declared in
# MonsterCatalog.presentation_gaps; they do not borrow another monster's art.
var source: Node
var target: Node3D
var travel_velocity := Vector3.ZERO
var gravity_strength := 0.0
var direct_damage := 0.0
var area_damage := 0.0
var area_radius := 0.0
var ignore_blast_walls := false
var lifetime := 8.0
var resolved := false
var tint := Color(0.5, 0.85, 0.15)
var homing_delay := -1.0
var homing_turn_rate := 0.0
var homing_speed := 0.0
var lock_target_once := false
var locked_target := Vector3.INF
var elapsed := 0.0
var ground_fuse := -1.0
var landed := false
var hazard: Dictionary = {}
var loot: Dictionary = {}
var collision_radius := 0.0
var collision_sphere: SphereShape3D


static func ballistic_velocity(origin: Vector3, aim: Vector3, flight_time: float, gravity_value := 9.81) -> Vector3:
	var duration := maxf(flight_time, 0.01)
	return (aim - origin) / duration + Vector3.UP * gravity_value * duration * 0.5


func _ready() -> void:
	add_to_group("enemy_source_projectiles")
	set_meta("visual_provenance", "procedural; original enemy effect prefab is not exported")
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 10
	mesh.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	mesh.material = material
	visual.mesh = mesh
	add_child(visual)


func _physics_process(delta: float) -> void:
	if resolved:
		return
	lifetime -= delta
	elapsed += delta
	if lifetime <= 0.0:
		queue_free()
		return
	if landed:
		ground_fuse -= delta
		if ground_fuse <= 0.0: detonate()
		return
	if homing_delay >= 0.0 and elapsed >= homing_delay and is_instance_valid(target):
		if not lock_target_once or locked_target == Vector3.INF:
			locked_target = target.global_position + Vector3.UP * (0.6 if lock_target_once else maxf(0.0, (7.0 - elapsed) / 7.0))
		var desired := (locked_target - global_position).normalized()
		var heading := travel_velocity.normalized()
		var angle := heading.angle_to(desired)
		var weight := minf(1.0, homing_turn_rate * delta / maxf(angle, 0.001))
		travel_velocity = heading.slerp(desired, weight).normalized() * homing_speed
	var acceleration := Vector3.DOWN * gravity_strength
	var destination := global_position + travel_velocity * delta + acceleration * delta * delta * 0.5
	travel_velocity += acceleration * delta
	var hit := _sweep(destination)
	if hit.is_empty():
		global_position = destination
	else:
		global_position = hit.position
		var collider := hit.get("collider") as Node
		if ground_fuse >= 0.0 and not collider.has_method("take_damage"):
			landed = true
			global_position += Vector3(hit.normal) * 0.05
		else: detonate(collider)


func _sweep(destination: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	if is_instance_valid(source) and source is CollisionObject3D: excluded.append(source.get_rid())
	if collision_radius <= 0.0:
		var ray := PhysicsRayQueryParameters3D.create(global_position, destination, 5, excluded)
		return space.intersect_ray(ray)
	if not collision_sphere: collision_sphere = SphereShape3D.new()
	collision_sphere.radius = collision_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 5
	query.exclude = excluded
	var hit := space.get_rest_info(query)
	if hit.is_empty():
		query.motion = destination - global_position
		var motion := space.cast_motion(query)
		if motion.size() != 2 or motion[0] >= 1.0: return {}
		query.transform.origin += query.motion * minf(1.0, motion[1] + 0.0001)
		query.motion = Vector3.ZERO
		hit = space.get_rest_info(query)
	if hit.is_empty(): return {}
	return {"position": query.transform.origin, "normal": hit.normal,
		"collider": instance_from_id(int(hit.collider_id))}


func detonate(direct_target: Node = null) -> void:
	if resolved:
		return
	resolved = true
	var attacker: Node = source if is_instance_valid(source) else null
	if is_instance_valid(direct_target) and direct_target.has_method("take_damage") and direct_damage > 0.0:
		direct_target.take_damage(direct_damage, global_position, attacker)
	var candidates: Array = source.source_damage_receivers() if is_instance_valid(source) and source.has_method("source_damage_receivers") else [target]
	for candidate in candidates:
		if area_damage > 0.0 and is_instance_valid(candidate) and candidate.has_method("take_damage"):
			if global_position.distance_squared_to(candidate.global_position) < area_radius * area_radius and _has_blast_sight(candidate):
				candidate.take_damage(area_damage, global_position, attacker)
	if not hazard.is_empty() and is_instance_valid(source): source.source_spawn_hazard(global_position, hazard)
	if not loot.is_empty() and is_instance_valid(source): source.source_drop_gift(global_position, loot)
	queue_free()


func _has_blast_sight(candidate: Node3D = null) -> bool:
	if not is_instance_valid(candidate): candidate = target
	if not is_instance_valid(candidate): return false
	if ignore_blast_walls:
		return true
	# Slightly raise floor impacts so the floor itself doesn't block the ray.
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.05,
		candidate.global_position + Vector3.UP * 0.5, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
