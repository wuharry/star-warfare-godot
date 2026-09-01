class_name WarfareProjectile
extends Node3D

var owner_node: Node
var direction := Vector3.FORWARD
var speed := 25.0
var damage := 40.0
var splash_radius := 0.0
var tint := Color.ORANGE_RED
var hostile := false
var lifetime := 5.0
var previous_position := Vector3.ZERO
var projectile_kind := "rocket"
var explosion_sound := ""
var bounces_left := 3
var gravity_strength := 0.0
var homing_target: Node3D

func configure(source: Node, travel_direction: Vector3, travel_speed: float, damage_value: float, splash: float, color_value: Color, is_hostile: bool, kind := "rocket", recovered_explosion_sound := "") -> void:
	owner_node = source
	direction = travel_direction.normalized()
	speed = travel_speed
	damage = damage_value
	splash_radius = splash
	tint = color_value
	hostile = is_hostile
	projectile_kind = kind
	explosion_sound = recovered_explosion_sound
	gravity_strength = 14.0 if kind == "grenade" else 0.0
	lifetime = 8.0 if kind in ["tracking", "fly_grenade", "ricochet"] else 5.0

func _ready() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.11 if not hostile else 0.16
	mesh.height = 0.22 if not hostile else 0.32
	mesh.radial_segments = 10
	mesh.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 5.0
	mesh.material = material
	mesh_instance.mesh = mesh
	add_child(mesh_instance)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 2.2
	light.omni_range = 3.2
	add_child(light)
	previous_position = global_position
	if projectile_kind in ["tracking", "fly_grenade"] and not hostile:
		homing_target = _find_nearest_enemy()

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	previous_position = global_position
	if is_instance_valid(homing_target):
		var desired := (homing_target.global_position + Vector3.UP * 0.8 - global_position).normalized()
		direction = direction.slerp(desired, clampf(delta * 3.6, 0.0, 1.0)).normalized()
	if gravity_strength > 0.0:
		direction = (direction * speed + Vector3.DOWN * gravity_strength * delta).normalized()
	var next_position := global_position + direction * speed * delta
	var mask := 5 if hostile else 3
	var query := PhysicsRayQueryParameters3D.create(previous_position, next_position, mask)
	if is_instance_valid(owner_node) and owner_node is CollisionObject3D:
		query.exclude = [owner_node.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var collider := result.get("collider") as Node
		if projectile_kind == "ricochet" and bounces_left > 0 and (not is_instance_valid(collider) or not collider.is_in_group("enemies")):
			bounces_left -= 1
			direction = direction.bounce(result.normal).normalized()
			global_position = result.position + direction * 0.08
			AudioDirector.play_3d("diablo/black_disk_bounce0%d.wav" % (4 - bounces_left), global_position, -3.0)
			return
		_impact(result.position, collider)
		return
	global_position = next_position

func _impact(position_value: Vector3, direct_target: Node) -> void:
	global_position = position_value
	if splash_radius > 0.0:
		var shape := SphereShape3D.new()
		shape.radius = splash_radius
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis.IDENTITY, position_value)
		params.collision_mask = 4 if hostile else 2
		for hit in get_world_3d().direct_space_state.intersect_shape(params, 24):
			var target: Node3D = hit.collider as Node3D
			if is_instance_valid(target) and target.has_method("take_damage"):
				var distance: float = target.global_position.distance_to(position_value)
				target.take_damage(damage * clampf(1.0 - distance / maxf(splash_radius, 0.01), 0.25, 1.0), position_value, owner_node)
	elif is_instance_valid(direct_target) and direct_target.has_method("take_damage"):
		direct_target.take_damage(damage, position_value, owner_node)
	var world := get_parent()
	if is_instance_valid(world) and world.has_method("spawn_explosion"):
		world.spawn_explosion(position_value, tint, splash_radius, explosion_sound)
	queue_free()

func _find_nearest_enemy() -> Node3D:
	var nearest: Node3D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Node3D:
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest
