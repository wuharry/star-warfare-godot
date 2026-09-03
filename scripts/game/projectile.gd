class_name WarfareProjectile
extends Node3D

const LEGACY_HD_ROOT := "res://assets/vfx/legacy_hd/"

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
var visual_root: Node3D
var visual_spin := 0.0
var visual_spin_speed := 0.0
var visual_variant := ""

func configure(source: Node, travel_direction: Vector3, travel_speed: float, damage_value: float, splash: float, color_value: Color, is_hostile: bool, kind := "rocket", recovered_explosion_sound := "", recovered_visual_variant := "") -> void:
	owner_node = source
	direction = travel_direction.normalized()
	speed = travel_speed
	damage = damage_value
	splash_radius = splash
	tint = color_value
	hostile = is_hostile
	projectile_kind = kind
	explosion_sound = recovered_explosion_sound
	visual_variant = recovered_visual_variant
	gravity_strength = 14.0 if kind == "grenade" else 0.0
	lifetime = 8.0 if kind in ["tracking", "fly_grenade", "ricochet"] else 5.0

func _ready() -> void:
	visual_root = Node3D.new()
	visual_root.name = "ProjectileVisual"
	add_child(visual_root)
	if not hostile and _build_legacy_hd_visual():
		pass
	else:
		_build_fallback_visual()
	previous_position = global_position
	_update_visual_orientation()
	if projectile_kind in ["tracking", "fly_grenade"] and not hostile:
		homing_target = _find_nearest_enemy()

func _build_fallback_visual() -> void:
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
	visual_root.add_child(mesh_instance)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 2.2
	light.omni_range = 3.2
	visual_root.add_child(light)

func _build_legacy_hd_visual() -> bool:
	match projectile_kind:
		"plasma":
			_add_billboard("l_001_hd.png", Vector2(0.95, 0.95), tint, 5.5)
			_add_billboard("shandian_005_hd.png", Vector2(1.25, 1.25), Color(0.55, 1.0, 0.76), 4.0)
			_add_projectile_light(tint, 3.2, 4.2)
			return true
		"rocket":
			var rocket_texture := "bug_RPG6_hd.png" if visual_variant == "gun30" else "gun0910_hd.png"
			_add_capsule(rocket_texture, 0.17, 0.7, Color.WHITE, 0.9)
			_add_billboard("gun_up_1_slf_sfx_hd.png" if visual_variant == "gun30" else "plasma_bolt1_red_hd.png", Vector2(0.58, 1.25), tint, 4.8, Vector3(0.0, 0.0, 0.52))
			_add_billboard("fire_00302_hd.png", Vector2(0.46, 0.8), Color(1.0, 0.55, 0.18), 3.8, Vector3(0.0, 0.0, 0.72))
			_add_billboard("fire_smook_001_hd.png", Vector2(0.72, 1.28), Color(0.62, 0.65, 0.68, 0.42), 0.35, Vector3(0.0, 0.0, 1.12))
			visual_spin_speed = 5.0
			return true
		"grenade":
			var grenade_texture := "joke_force_hd.png" if visual_variant == "gun41" else "gun0506_hd.png"
			_add_sphere(grenade_texture, 0.24, Color.WHITE, 1.4)
			if visual_variant == "gun41":
				_add_billboard("joke_warning01_hd.png", Vector2(0.36, 0.72), Color(0.75, 1.0, 0.2), 3.5)
				_add_billboard("xmas_light01_r_hd.png", Vector2(0.42, 0.42), Color.WHITE, 2.6)
			visual_spin_speed = 9.0
			return true
		"fly_grenade":
			_add_capsule("HotWing_D_hd.png", 0.2, 0.62, Color.WHITE, 1.8)
			_add_billboard("S2_Fireflys_hd.png", Vector2(0.72, 0.72), tint, 4.0, Vector3(0.0, 0.0, 0.42))
			_add_billboard("Skill_1_01_hd.png", Vector2(0.5, 0.5), Color(0.72, 1.0, 1.0), 3.2, Vector3(0.0, 0.0, 0.18))
			_add_billboard("VD5_Rush_01_hd.png", Vector2(0.34, 0.72), Color.WHITE, 2.8, Vector3(0.0, 0.0, 0.62))
			visual_spin_speed = 4.0
			return true
		"tracking":
			_add_capsule("dg_test_002_hd.png", 0.13, 0.48, Color.WHITE, 1.3)
			_add_billboard("bc_002_hd.png", Vector2(0.38, 1.45), tint, 5.0)
			_add_billboard("glow_002_hd.png", Vector2(0.68, 0.68), tint, 4.2)
			return true
		"spring":
			_add_capsule("dg_test_002_a_hd.png", 0.13, 0.48, Color.WHITE, 1.3)
			_add_billboard("bc_002_a_hd.png", Vector2(0.38, 1.45), tint, 5.0)
			_add_billboard("glow_002_a_hd.png", Vector2(0.68, 0.68), tint, 4.2)
			return true
		"ricochet":
			_add_disc("fd_01_hd.png", 0.5, 0.08, tint, 4.0)
			visual_spin_speed = 16.0
			return true
	return false

func _legacy_hd_material(texture_name: String, color: Color, emission_energy: float, billboard := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var texture_path := LEGACY_HD_ROOT + texture_name
	if ResourceLoader.exists(texture_path):
		var texture := load(texture_path) as Texture2D
		material.albedo_texture = texture
		material.emission_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material

func _add_billboard(texture_name: String, size: Vector2, color: Color, emission_energy: float, position_value := Vector3.ZERO) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	sprite.name = texture_name.get_basename().to_pascal_case()
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = _legacy_hd_material(texture_name, color, emission_energy, true)
	sprite.mesh = mesh
	sprite.position = position_value
	visual_root.add_child(sprite)
	return sprite

func _add_capsule(texture_name: String, radius: float, height: float, color: Color, emission_energy: float) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	body.name = "RecoveredProjectileBody"
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh.material = _legacy_hd_material(texture_name, color, emission_energy)
	body.mesh = mesh
	body.rotation.x = PI * 0.5
	visual_root.add_child(body)
	return body

func _add_sphere(texture_name: String, radius: float, color: Color, emission_energy: float) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	body.name = "RecoveredProjectileBody"
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	mesh.material = _legacy_hd_material(texture_name, color, emission_energy)
	body.mesh = mesh
	visual_root.add_child(body)
	return body

func _add_disc(texture_name: String, radius: float, height: float, color: Color, emission_energy: float) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	disc.name = "RecoveredRicochetDisc"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.material = _legacy_hd_material(texture_name, color, emission_energy)
	disc.mesh = mesh
	disc.rotation.x = PI * 0.5
	visual_root.add_child(disc)
	return disc

func _add_projectile_light(color: Color, energy: float, radius: float) -> void:
	if not bool(GameState.get_quality_profile().get("glow", true)):
		return
	var light := OmniLight3D.new()
	light.name = "RecoveredProjectileLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	visual_root.add_child(light)

func _update_visual_orientation() -> void:
	if not is_instance_valid(visual_root) or direction.length_squared() < 0.001:
		return
	var up_axis := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	visual_root.look_at(visual_root.global_position + direction, up_axis)
	if not is_zero_approx(visual_spin):
		visual_root.rotate_object_local(Vector3.FORWARD, visual_spin)

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
	visual_spin += visual_spin_speed * delta
	_update_visual_orientation()
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
