class_name UnitySceneEffects
extends RefCounted

const SOURCE_PATH := "res://assets/scene_effects/effects.json"
const TEXTURE_ROOT := "res://assets/scene_effects/"

# These are the active ambient particles in the Unity scenes. The Level 3
# objects are named sc_03_fire1 but live under Stars, including far below the
# arena: their authored placement is intentional and must not be ground-snapped.
static func build(parent: Node3D, level_number: int, quality: Dictionary) -> Node3D:
	var source_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if not source_value is Dictionary:
		push_warning("Invalid original Unity scene effects metadata")
		return null
	var records: Array = source_value.get("levels", {}).get(str(level_number), [])
	if records.is_empty():
		return null
	var root := Node3D.new()
	root.name = "OriginalUnitySceneEffects"
	parent.add_child(root)
	for value: Variant in records:
		if value is Dictionary:
			var particles := _build_emitter(value, quality)
			root.add_child(particles)
	return root


static func _build_emitter(record: Dictionary, quality: Dictionary) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "%s_%d" % [str(record.name), int(record.game_object)]
	particles.set_meta("unity_game_object", int(record.game_object))
	particles.set_meta("unity_effect_kind", str(record.kind))
	particles.set_meta("unity_source_scene", str(record.source_scene))
	particles.set_meta("unity_emission_rate", record.emission_rate)
	particles.transform = _transform(record.transform)
	particles.local_coords = false
	particles.gravity = Vector3.ZERO
	particles.spread = 0.0
	particles.one_shot = bool(record.one_shot)
	particles.emitting = bool(record.emitting)
	particles.lifetime = float(record.lifetime[1])
	particles.lifetime_randomness = 1.0 - float(record.lifetime[0]) / particles.lifetime
	# Unity's legacy emitter varies its rate from 3 to 8 / second. Godot's
	# persistent particle pool represents this with the rounded mean rate; the
	# original range remains in source metadata. Snow's 75 / second is exact.
	var density := 0.5 if float(quality.get("render_scale", 1.0)) <= 0.7 else 1.0
	particles.amount = maxi(1, int(round(float(record.particle_capacity) * density)))
	particles.scale_amount_min = float(record.size[0])
	particles.scale_amount_max = float(record.size[1])
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material(record)
	particles.mesh = quad
	if str(record.kind) == "snow":
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = _vector(record.box_size) * 0.5
		# Unity local +Z becomes Godot -Z. A negative authored speed therefore
		# points toward local +Z, which the recovered emitter basis turns downward.
		var speed := float(record.start_speed[1])
		particles.direction = Vector3.FORWARD if speed >= 0.0 else Vector3.BACK
		particles.initial_velocity_min = absf(float(record.start_speed[0]))
		particles.initial_velocity_max = absf(speed)
		particles.speed_scale = float(record.get("speed_scale", 1.0))
		particles.preprocess = particles.lifetime if bool(record.get("prewarm", false)) else 0.0
		var bounds := AABB(-particles.emission_box_extents, particles.emission_box_extents * 2.0)
		var travel := particles.direction * particles.initial_velocity_max * particles.lifetime
		particles.visibility_aabb = bounds.merge(AABB(bounds.position + travel, bounds.size)).grow(particles.scale_amount_max)
	else:
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = float(record.ellipsoid[0])
		particles.initial_velocity_min = 0.0
		particles.initial_velocity_max = 0.0
		if bool(record.random_rotation):
			particles.angle_min = 0.0
			particles.angle_max = 360.0
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array()
		gradient.colors = PackedColorArray()
		var colors: Array = record.color_over_life
		for index in colors.size():
			var rgba: Array = colors[index]
			gradient.add_point(float(index) / float(colors.size() - 1), Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3])))
		particles.color_ramp = gradient
		var growth := Curve.new()
		growth.max_value = 1.0 + float(record.size_grow) * particles.lifetime
		growth.add_point(Vector2(0.0, 1.0))
		growth.add_point(Vector2(1.0, growth.max_value))
		growth.set_point_right_mode(0, Curve.TANGENT_LINEAR)
		growth.set_point_left_mode(1, Curve.TANGENT_LINEAR)
		particles.scale_amount_curve = growth
		var radius := particles.emission_sphere_radius + growth.max_value * particles.scale_amount_max
		particles.visibility_aabb = AABB(-Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	return particles


static func _material(record: Dictionary) -> ShaderMaterial:
	var additive := str(record.shader) == "iPhone/Additive"
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, %s;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_particle_color = false;
void vertex() {
	// Camera-facing particles retain their size and random rotation.
	vec3 particle_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	float angle = INSTANCE_CUSTOM.x;
	VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * particle_scale.x, INV_VIEW_MATRIX[1] * particle_scale.y, INV_VIEW_MATRIX[2] * particle_scale.z, MODEL_MATRIX[3]);
}
void fragment() {
	vec4 texel = texture(source_texture, UV);
	// AlphaBlend_VertexColor uses texture * primary double. Additive uses
	// texture alone, so its unused Unity _TintColor must not darken the snow.
	vec4 result = texel * (use_particle_color ? COLOR * 2.0 : vec4(1.0));
	ALBEDO = clamp(result.rgb, vec3(0.0), vec3(1.0));
	ALPHA = clamp(result.a, 0.0, 1.0);
}
""" % ("blend_add" if additive else "blend_mix")
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("source_texture", load(TEXTURE_ROOT.path_join(str(record.texture))))
	material.set_shader_parameter("use_particle_color", not additive)
	return material


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func _transform(values: Array) -> Transform3D:
	return Transform3D(
		Basis(Vector3(float(values[0]), float(values[4]), float(values[8])), Vector3(float(values[1]), float(values[5]), float(values[9])), Vector3(float(values[2]), float(values[6]), float(values[10]))),
		Vector3(float(values[3]), float(values[7]), float(values[11]))
	)
