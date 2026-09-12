class_name OriginalPickupVisual
extends Node3D

const ASSET_ROOT := "res://assets/pickups/"
static var _data: Dictionary = {}
static var _meshes: Dictionary = {}
static var _shaders: Dictionary = {}

var elapsed := 0.0
var tracks: Array[Dictionary] = []
var emitters: Array[Dictionary] = []
var lifetime := 0.0
var prefab_name := ""
var pulse_material: ShaderMaterial

static func create(source_name: String, spawned := false) -> OriginalPickupVisual:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(ASSET_ROOT + "pickups.json"))
	var visual := OriginalPickupVisual.new()
	visual.prefab_name = source_name
	visual.name = source_name
	visual.lifetime = 2.0 if source_name.begins_with("effect_pick_") else 0.0
	var nodes: Dictionary = {}
	var records: Array = _data.prefabs[source_name].nodes
	for record: Dictionary in records:
		var node := Node3D.new()
		node.name = record.name
		node.position = _vector(record.position, true)
		node.quaternion = _rotation(record.rotation)
		node.scale = _vector(record.scale)
		if str(record.parent) == "0" and spawned:
			# Unity Instantiate(position, Quaternion.identity) replaces root pose,
			# but retains prefab scale (0.4 for both drops).
			node.position = Vector3.ZERO
			node.quaternion = Quaternion.IDENTITY
		nodes[record.id] = node
	for record: Dictionary in records:
		var node: Node3D = nodes[record.id]
		var parent: Node3D = visual if str(record.parent) == "0" else nodes[record.parent]
		parent.add_child(node)
		var material: ShaderMaterial
		if record.has("material"):
			material = _material(record.material, record.has("particles"))
			if source_name == "Enegy":
				visual.pulse_material = material
		if record.has("mesh"):
			var instance := MeshInstance3D.new()
			instance.mesh = _mesh(record.mesh)
			instance.material_override = material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(instance)
		if record.has("animation"):
			for channel: Dictionary in _data.animations[record.animation].channels:
				visual.tracks.append({"node": node, "material": material, "channel": channel})
		if record.has("particles"):
			visual._add_particles(node, record.particles, material)
	visual.advance(0.0)
	return visual

static func _vector(value: Array, mirror_z := false) -> Vector3:
	return Vector3(value[0], value[1], -float(value[2]) if mirror_z else float(value[2]))

static func _rotation(value: Array) -> Quaternion:
	return Quaternion(-float(value[0]), -float(value[1]), value[2], value[3]).normalized()

static func _mesh(mesh_id: String) -> ArrayMesh:
	if _meshes.has(mesh_id):
		return _meshes[mesh_id]
	var record: Dictionary = _data.meshes[mesh_id]
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for value: Array in record.positions:
		vertices.append(_vector(value, true))
	for value: Array in record.uv:
		uv.append(Vector2(value[0], 1.0 - float(value[1])))
	if record.uv2 != null:
		for value: Array in record.uv2:
			uv2.append(Vector2(value[0], 1.0 - float(value[1])))
	else:
		# danjia has only UV0; both fixed-function texture stages use that set.
		uv2 = uv
	var mesh := ArrayMesh.new()
	for indices: Array in record.surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uv
		if not uv2.is_empty():
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[mesh_id] = mesh
	return mesh

static func _material(material_id: String, billboard: bool) -> ShaderMaterial:
	var record: Dictionary = _data.materials[material_id]
	var additive := str(record.shader).contains("Additive")
	var tinted := str(record.shader) == "iPhone/Additive_Color"
	var overlay := record.has("overlay")
	var key := "%s_%s" % [record.shader, billboard]
	if not _shaders.has(key):
		var shader := Shader.new()
		var code := "shader_type spatial;\nrender_mode unshaded, cull_disabled"
		code += ", depth_draw_never, blend_add;\n" if additive else ";\n"
		code += "uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_disable;\n"
		code += "uniform float alpha = 1.0;\nuniform vec3 tint = vec3(1.0);\n"
		if overlay:
			code += "uniform sampler2D overlay_texture : source_color;\nuniform float brightness = 0.0;\n"
		if billboard:
			code += "void vertex() {\n"
			code += "float a = INSTANCE_CUSTOM.x; VERTEX.xy = mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a))) * VERTEX.xy;\n"
			code += "vec3 s = vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));\n"
			code += "MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0]*s.x,INV_VIEW_MATRIX[1]*s.y,INV_VIEW_MATRIX[2]*s.z,MODEL_MATRIX[3]); }\n"
		code += "void fragment() { vec4 c = texture(source_texture, UV);\n"
		if tinted:
			code += "c *= vec4(tint, alpha) * 2.0;\n"
		if overlay:
			# Original shader binds its second texture stage (_texBase) to UV2.
			code += "c = texture(source_texture, UV2) + texture(overlay_texture, UV) * brightness * 2.0;\n"
		code += "ALBEDO = clamp(c.rgb, vec3(0.0), vec3(1.0));\n"
		if additive:
			code += "ALPHA = clamp(c.a, 0.0, 1.0);\n"
		code += "}\n"
		shader.code = code
		_shaders[key] = shader
	var material := ShaderMaterial.new()
	material.shader = _shaders[key]
	material.set_shader_parameter("source_texture", load(ASSET_ROOT + str(record.texture)))
	material.set_shader_parameter("tint", Vector3(record.color[0], record.color[1], record.color[2]))
	material.set_shader_parameter("alpha", float(record.color[3]))
	if overlay:
		material.set_shader_parameter("overlay_texture", load(ASSET_ROOT + str(record.overlay)))
	return material

func _add_particles(parent: Node3D, record: Dictionary, material: ShaderMaterial) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "PickupStars"
	particles.emitting = false
	particles.local_coords = true
	particles.one_shot = false # Stop emission at the original 0.5-second duration.
	particles.lifetime = float(record.lifetime[1])
	particles.lifetime_randomness = 1.0 - float(record.lifetime[0]) / particles.lifetime
	particles.amount = ceili(float(record.rate) * particles.lifetime)
	particles.gravity = Vector3.ZERO
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = float(record.radius)
	particles.direction = Vector3.FORWARD
	particles.spread = 180.0
	particles.initial_velocity_min = float(record.speed[0])
	particles.initial_velocity_max = float(record.speed[1])
	particles.scale_amount_min = float(record.size[0])
	particles.scale_amount_max = float(record.size[1])
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.scale_amount_curve = Curve.new()
	for point: Dictionary in record.size_curve:
		particles.scale_amount_curve.add_point(Vector2(point.time, point.value[0]), point["in"][0], point["out"][0])
	var quad := QuadMesh.new()
	quad.material = material
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)
	emitters.append({"node": particles, "start": float(record.delay), "end": float(record.delay) + float(record.duration)})

# Hermite interpolation preserves the original Unity tangents, including alpha.
static func sample(points: Array, time: float) -> Array:
	if time <= float(points[0].time):
		return points[0].value
	for index in range(1, points.size()):
		var right: Dictionary = points[index]
		if time > float(right.time):
			continue
		var left: Dictionary = points[index - 1]
		var duration := float(right.time) - float(left.time)
		var t := (time - float(left.time)) / duration
		var start_weight := 2.0 * t * t * t - 3.0 * t * t + 1.0
		var start_tangent := (t * t * t - 2.0 * t * t + t) * duration
		var end_weight := -2.0 * t * t * t + 3.0 * t * t
		var end_tangent := (t * t * t - t * t) * duration
		var result := []
		for axis in left.value.size():
			result.append(
				start_weight * float(left.value[axis]) + start_tangent * float(left["out"][axis])
				+ end_weight * float(right.value[axis]) + end_tangent * float(right["in"][axis])
			)
		return result
	return points[-1].value

func _process(delta: float) -> void:
	advance(delta)
	if lifetime > 0.0 and elapsed >= lifetime:
		queue_free()

func advance(delta: float) -> void:
	elapsed += delta
	for track: Dictionary in tracks:
		var value := sample(track.channel.keys, elapsed)
		var node: Node3D = track.node
		match str(track.channel.kind):
			"rotation": node.quaternion = _rotation(value)
			"position": node.position = _vector(value, true)
			"scale": node.scale = _vector(value).max(Vector3.ONE * 0.00001)
			"alpha": track.material.set_shader_parameter("alpha", float(value[0]))
	for emitter: Dictionary in emitters:
		var particles: CPUParticles3D = emitter.node
		particles.emitting = elapsed >= float(emitter.start) and elapsed < float(emitter.end)
	if pulse_material != null:
		pulse_material.set_shader_parameter("brightness", pingpong(elapsed * 3.0, 1.0))
