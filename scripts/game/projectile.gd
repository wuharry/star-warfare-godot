class_name WarfareProjectile
extends Node3D

const LEGACY_HD_ROOT := "res://assets/vfx/legacy_hd/"
const ORIGINAL_ROCKET_MESH_PATH := "res://assets/models/projectiles/original_rocket.obj"
const ORIGINAL_ROCKET_HD_TEXTURE_PATH := "res://assets/models/projectiles/gun0910_hd.png"
const ORIGINAL_ROCKET_MATERIAL_STATES := {
	"fire_001": {"blend": "additive", "depth_write": false, "cull_disabled": true, "unshaded": true},
	"fire_001_2": {"blend": "additive", "depth_write": false, "cull_disabled": true, "unshaded": true},
	"fire_001_3": {"blend": "additive", "depth_write": false, "cull_disabled": true, "unshaded": true},
	"RPG_-13_-_Default": {"blend": "opaque", "depth_write": true, "cull_disabled": false, "unshaded": false},
}

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
			# gun30 has its own recovered fantasy projectile. Standard RPG weapons use
			# the exact Effect/Projectile mesh, crossed flame planes and texture atlas
			# from the Unity project instead of the former capsule approximation.
			if visual_variant != "gun30" and _add_original_rocket_visual():
				_add_original_rocket_smoke()
				return true
			_add_capsule("bug_RPG6_hd.png", 0.17, 0.7, Color.WHITE, 0.9)
			_add_billboard("gun_up_1_slf_sfx_hd.png", Vector2(0.58, 1.25), tint, 4.8, Vector3(0.0, 0.0, 0.52))
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

func _add_original_rocket_visual() -> bool:
	if not ResourceLoader.exists(ORIGINAL_ROCKET_MESH_PATH):
		return false
	var rocket_mesh := load(ORIGINAL_ROCKET_MESH_PATH) as Mesh
	if rocket_mesh == null:
		return false
	var body := MeshInstance3D.new()
	body.name = "OriginalUnityRocket"
	body.mesh = rocket_mesh
	# The YAML converter preserves the prefab's authored world transform. Center
	# the combined body/flame mesh so projectile movement still uses this node's
	# origin, while leaving the original proportions and UV coordinates intact.
	body.position = -rocket_mesh.get_aabb().get_center()
	body.set_meta("source_prefab", "Effect/Projectile")
	body.set_meta("hd_texture", "gun0910_hd.png")
	UnityMaterialRestorer.apply_to_mesh(body, ORIGINAL_ROCKET_MATERIAL_STATES)
	_apply_original_rocket_hd_texture(body)
	visual_root.add_child(body)
	return true

func _apply_original_rocket_hd_texture(body: MeshInstance3D) -> void:
	if not ResourceLoader.exists(ORIGINAL_ROCKET_HD_TEXTURE_PATH):
		return
	var hd_texture := load(ORIGINAL_ROCKET_HD_TEXTURE_PATH) as Texture2D
	if hd_texture == null:
		return
	for surface_index in body.mesh.get_surface_count():
		var material := body.get_surface_override_material(surface_index) as StandardMaterial3D
		if material == null:
			var source := body.mesh.surface_get_material(surface_index) as StandardMaterial3D
			if source != null:
				material = source.duplicate(true) as StandardMaterial3D
		if material == null or not material.resource_name.begins_with("RPG_"):
			continue
		material.albedo_texture = hd_texture
		body.set_surface_override_material(surface_index, material)

func _add_original_rocket_smoke() -> void:
	# Reconstruct the two legacy ParticleEmitter layers from Effect/Projectile:
	# a long soft smoke plume and a tighter animated combustion puff.
	_add_original_rocket_smoke_layer(
		"OriginalRocketSmokeLong",
		"fire_smook_001_hd.png",
		15,
		0.95,
		Vector2(0.62, 0.62),
		Vector2(0.9, 1.5),
		Vector2(3.8, 5.2),
		Color(0.58, 0.61, 0.64, 0.34),
		0.25
	)
	_add_original_rocket_smoke_layer(
		"OriginalRocketSmokeHot",
		"fire_00302_hd.png",
		12,
		0.68,
		Vector2(0.42, 0.42),
		Vector2(0.4, 0.8),
		Vector2(1.6, 2.4),
		Color(1.0, 0.58, 0.22, 0.68),
		0.12
	)

func _add_original_rocket_smoke_layer(
	name_value: String,
	texture_name: String,
	particle_amount: int,
	lifetime_value: float,
	quad_size: Vector2,
	scale_range: Vector2,
	velocity_range: Vector2,
	color_value: Color,
	position_z: float
) -> void:
	var particles := GPUParticles3D.new()
	particles.name = name_value
	particles.amount = particle_amount
	particles.lifetime = lifetime_value
	particles.randomness = 0.25
	particles.local_coords = true
	particles.position.z = position_z
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.0, 1.0)
	process_material.spread = 12.0
	process_material.gravity = Vector3.ZERO
	process_material.initial_velocity_min = velocity_range.x
	process_material.initial_velocity_max = velocity_range.y
	process_material.scale_min = scale_range.x
	process_material.scale_max = scale_range.y
	process_material.color = color_value
	particles.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.orientation = PlaneMesh.FACE_Z
	quad.material = _legacy_hd_material(texture_name, Color.WHITE, 0.55, true)
	particles.draw_pass_1 = quad
	particles.set_meta("source_emitter", "Effect/Projectile/%s" % name_value)
	visual_root.add_child(particles)

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
