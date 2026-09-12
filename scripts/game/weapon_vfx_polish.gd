class_name WeaponVfxPolish
extends Node3D

# Pure presentation: no collision shapes, weapon state, or damage callbacks.
const RIBBON_SHADER = preload("res://assets/shaders/weapon_energy_ribbon.gdshader")
const FLARE_SHADER = preload("res://assets/shaders/weapon_soft_flare.gdshader")
const GROUP := "weapon_vfx_polish"
const MAX_POINTS := 48
var mode := "beam"
var elapsed := 0.0
var lifetime := 0.18
var tail_lifetime := 0.26
var width := 0.26
var source: WeakRef
var points: Array[Vector3] = []
var times: Array[float] = []
var ribbon: ImmediateMesh
var ribbon_material: ShaderMaterial
var flares: Array[MeshInstance3D] = []
var ring_mesh: MeshInstance3D
var detail := "high"

static func _create(parent: Node, kind: String) -> WeaponVfxPolish:
	var quality := str(GameState.settings.get("quality", "high"))
	var limit := 64 if quality == "high" else (36 if quality == "medium" else 18)
	if parent.get_tree().get_nodes_in_group(GROUP).size() >= limit:
		return null
	var effect := WeaponVfxPolish.new()
	effect.name = "Polished" + kind.to_pascal_case()
	effect.mode = kind
	effect.detail = quality
	parent.add_child(effect)
	effect.set_as_top_level(true)
	effect.global_transform = Transform3D.IDENTITY
	effect.add_to_group(GROUP)
	return effect

static func beam(parent: Node, from: Vector3, to: Vector3, color: Color) -> WeaponVfxPolish:
	if from.distance_squared_to(to) < 0.0025:
		return null
	var effect := _create(parent, "beam")
	if effect == null:
		return null
	effect.points.assign([from, to])
	effect._build_ribbon(color)
	effect.ribbon_material.set_shader_parameter("flow_scale", from.distance_to(to) * 1.2)
	effect._flare(from, color, 0.7)
	effect._flare(to, color, 0.9)
	effect._draw_ribbon()
	return effect

static func trail(projectile: Node3D, color: Color, kind: String) -> WeaponVfxPolish:
	var parent := projectile.get_parent()
	var container := parent.get_node_or_null("Effects")
	var effect := _create(container if container != null else parent, "trail")
	if effect == null:
		return null
	effect.source = weakref(projectile)
	effect.tail_lifetime = 0.32 if kind in ["plasma", "tracking", "spring", "ricochet"] else 0.22
	effect.width = 0.17 if kind in ["rocket", "grenade"] else 0.29
	effect._build_ribbon(color)
	effect.ribbon_material.set_shader_parameter("core_strength", 0.3)
	effect._flare(projectile.global_position, color, 0.5 if kind == "rocket" else 0.72)
	# Sample on the first process frame, after the caller places the new projectile.
	return effect

static func burst(parent: Node, at: Vector3, normal: Vector3, color: Color, radius := 1.0) -> WeaponVfxPolish:
	var effect := _create(parent, "burst")
	if effect == null:
		return null
	effect.lifetime = 0.48
	effect.width = clampf(radius, 0.6, 2.5)
	effect._flare(at, color, effect.width * 1.8)
	effect.ring_mesh = effect._flare(at, color, effect.width)
	effect.ring_mesh.material_override.set_shader_parameter("ring", true)
	var axis := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	effect.ring_mesh.look_at(at + axis, Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.98 else Vector3.UP)
	if effect.detail != "low":
		effect._sparks(at, axis, color)
	return effect

func _build_ribbon(color: Color) -> void:
	ribbon = ImmediateMesh.new()
	ribbon_material = ShaderMaterial.new()
	ribbon_material.shader = RIBBON_SHADER
	ribbon_material.set_shader_parameter("energy_color", color)
	var instance := MeshInstance3D.new()
	instance.name = "SoftEnergyRibbon"
	instance.mesh = ribbon
	instance.material_override = ribbon_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _flare(at: Vector3, color: Color, size: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	mesh.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = FLARE_SHADER
	material.set_shader_parameter("energy_color", color)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = at
	flares.append(mesh)
	return mesh

func _sparks(at: Vector3, normal: Vector3, color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "EnergyMotes"
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 14 if detail == "high" else 7
	particles.lifetime = 0.38
	particles.local_coords = false
	particles.direction = normal
	particles.spread = 60.0
	particles.gravity = Vector3.DOWN * 1.5
	particles.initial_velocity_min = 1.4
	particles.initial_velocity_max = 4.5
	# Unit quad: these are final world sizes, not two tiny scales multiplied.
	particles.scale_amount_min = 0.055
	particles.scale_amount_max = 0.13
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = FLARE_SHADER
	material.set_shader_parameter("energy_color", color)
	material.set_shader_parameter("particle_billboard", true)
	quad.material = material
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.global_position = at
	particles.emitting = true

func _sample_position(at: Vector3) -> void:
	# Do not draw a streak across a teleport, respawn or initial spawn placement.
	if not points.is_empty() and points[-1].distance_to(at) > 8.0:
		points.clear()
		times.clear()
	if points.is_empty() or points[-1].distance_squared_to(at) > 0.0016:
		points.append(at)
		times.append(elapsed)
	while points.size() > (MAX_POINTS if detail == "high" else 24):
		points.pop_front()
		times.pop_front()

func _process(delta: float) -> void:
	elapsed += delta
	var fade := clampf(1.0 - elapsed / lifetime, 0.0, 1.0)
	if mode == "trail":
		var target: Node3D = source.get_ref() as Node3D
		if is_instance_valid(target) and not target.is_queued_for_deletion():
			_sample_position(target.global_position)
			flares[0].global_position = target.global_position
		else:
			flares[0].visible = false
		while not times.is_empty() and elapsed - times[0] > tail_lifetime:
			times.pop_front()
			points.pop_front()
		if not is_instance_valid(target) and points.is_empty():
			queue_free()
			return
		fade = 1.0
	if ribbon != null:
		ribbon_material.set_shader_parameter("age", elapsed)
		ribbon_material.set_shader_parameter("opacity", fade)
		_draw_ribbon()
	var camera := get_viewport().get_camera_3d()
	for flare: MeshInstance3D in flares:
		flare.material_override.set_shader_parameter("opacity", fade)
		if flare == ring_mesh:
			flare.scale = Vector3.ONE * (0.3 + elapsed * 4.0)
		elif camera != null:
			flare.global_basis = camera.global_basis.orthonormalized()
	if mode != "trail" and elapsed >= lifetime:
		queue_free()

func _draw_ribbon() -> void:
	ribbon.clear_surfaces()
	if points.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ribbon_material)
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var tangent := (end - start).normalized()
		var side := tangent.cross(camera.global_position - (start + end) * 0.5).normalized()
		if side.length_squared() < 0.01:
			side = tangent.cross(camera.global_basis.y).normalized()
		var a := float(index) / float(points.size() - 1)
		var b := float(index + 1) / float(points.size() - 1)
		var alpha_a := 1.0 if mode == "beam" else clampf(1.0 - (elapsed - times[index]) / tail_lifetime, 0.0, 1.0)
		var alpha_b := 1.0 if mode == "beam" else clampf(1.0 - (elapsed - times[index + 1]) / tail_lifetime, 0.0, 1.0)
		var width_a := width * (0.18 + alpha_a * 0.82)
		var width_b := width * (0.18 + alpha_b * 0.82)
		_vertex(start - side * width_a, Vector2(a, 0), alpha_a)
		_vertex(start + side * width_a, Vector2(a, 1), alpha_a)
		_vertex(end + side * width_b, Vector2(b, 1), alpha_b)
		_vertex(start - side * width_a, Vector2(a, 0), alpha_a)
		_vertex(end + side * width_b, Vector2(b, 1), alpha_b)
		_vertex(end - side * width_b, Vector2(b, 0), alpha_b)
	ribbon.surface_end()

func _vertex(at: Vector3, uv: Vector2, alpha: float) -> void:
	ribbon.surface_set_uv(uv)
	ribbon.surface_set_color(Color(1, 1, 1, alpha))
	ribbon.surface_add_vertex(at)
