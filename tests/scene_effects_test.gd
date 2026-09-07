extends Node3D

const Effects = preload("res://scripts/game/unity_scene_effects.gd")
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SCENE EFFECTS TEST: " + message)


func _run() -> void:
	var high: Dictionary = GameState.QUALITY_PROFILES.high
	var low: Dictionary = GameState.QUALITY_PROFILES.low
	for level_number in [1, 2, 4, 5, 6, 7, 14, 15, 16, 17, 18, 19, 20]:
		_check(Effects.build(self, level_number, high) == null, "Level %d invented ambient particles" % level_number)
	for level_number in [8, 13, 21]:
		var root := Effects.build(self, level_number, high)
		_check(root != null and root.get_child_count() == 1, "Level %d is missing its source snow emitter" % level_number)
		if root == null or root.get_child_count() != 1:
			continue
		var snow := root.get_child(0) as CPUParticles3D
		_check(snow != null, "Snow does not support the Compatibility renderer")
		if snow != null:
			_check(snow.position.distance_to(Vector3(0, 24.253786, 0)) < 0.0001, "Snow lost the original world position")
			_check((snow.basis * snow.direction).normalized().distance_to(Vector3.DOWN) < 0.0001, "Snow travels upward after Unity coordinate conversion")
			_check(snow.emission_box_extents.is_equal_approx(Vector3(50, 50, 25)), "Snow emission volume differs from Unity")
			_check(snow.amount == 75 and is_equal_approx(snow.lifetime, 1.0), "Snow emission rate/lifetime differs from 75 per second / 1 second")
			_check(is_equal_approx(snow.initial_velocity_min, 10.0) and is_equal_approx(snow.initial_velocity_max, 10.0), "Snow source speed differs")
			_check(is_equal_approx(snow.scale_amount_min, 0.5) and is_equal_approx(snow.scale_amount_max, 1.0), "Snow sizes differ from source")
			_check(snow.emitting and not snow.one_shot and snow.preprocess == 0.0, "Snow source playOnAwake / loop / prewarm differs")
			_check(snow.gravity == Vector3.ZERO, "Added gravity changes the authored snow speed")
			_check(snow.visibility_aabb.has_point(Vector3(50, 50, 35)), "Snow disappears when its emitter origin leaves the view")
			var material := snow.mesh.surface_get_material(0) as ShaderMaterial
			_check(material != null and material.get_shader_parameter("source_texture") is Texture2D, "Original snow texture did not load")
			_check(material != null and material.get_shader_parameter("use_particle_color") == false, "Unused tint changes original additive snow color")
		var low_root := Effects.build(self, level_number, low)
		var low_snow := low_root.get_child(0) as CPUParticles3D
		_check(low_snow.amount < snow.amount and low_snow.amount > 0, "Low quality does not limit snow density")
		_check(low_snow.transform.is_equal_approx(snow.transform) and low_snow.scale_amount_min == snow.scale_amount_min, "Low quality changes particle position or size")
		low_root.free()
		root.free()
	var stars := Effects.build(self, 3, high)
	_check(stars != null and stars.get_child_count() == 5, "Level 3 lost its five original distant glow emitters")
	if stars != null:
		var below_arena := stars.get_node_or_null("sc_03_fire1_222") as CPUParticles3D
		_check(below_arena != null and below_arena.position.distance_to(Vector3(-32.0761104, -109.655518, 26.809214)) < 0.0001, "A distant glow was moved to the arena floor")
		for child in stars.get_children():
			var glow := child as CPUParticles3D
			_check(glow != null and glow.emitting and glow.emission_sphere_radius == 10.0, "Legacy glow lost its enabled spherical emitter")
			_check(is_equal_approx(glow.lifetime_randomness, 0.2), "Legacy glow lifetime range no longer covers 0.8–1.0 seconds")
			_check(glow.initial_velocity_max == 0.0 and glow.gravity == Vector3.ZERO, "Stationary distant glow was turned into a rising fire")
			_check(glow.color_ramp.get_point_count() == 5, "Legacy particle color animation is missing")
			_check(glow.color_ramp.get_color(0).is_equal_approx(Color(1, 1, 1, 10.0 / 255.0)), "Packed Unity RGBA colors were decoded in the wrong order")
			_check(glow.scale_amount_curve.sample(1.0) == 3.0, "Legacy sizeGrow is missing")
		stars.free()
	await get_tree().process_frame
	if failures.is_empty():
		print("SCENE_EFFECTS_TEST_PASS source_emitters=8 source_textures=2")
		get_tree().quit(0)
	else:
		print("SCENE_EFFECTS_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
