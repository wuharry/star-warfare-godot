extends Node

# Pixel checks exercise the rendered shader, independently of exporter data:
# source Gamma multiplication, the x2 shader variant, and Unity atlas ST.
const LightmapShader = preload("res://assets/shaders/unity_lightmap.gdshader")
const OUTPUT_DIR := "res://test_output/armor_lighting/lightmap_probe"
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	camera.position.z = 2.0
	viewport.add_child(camera)
	camera.make_current()
	var base := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	base.fill(Color(0.5, 0.4, 0.25))
	var atlas := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.4, 0.2, 0.6))
	atlas.fill_rect(Rect2i(4, 4, 4, 4), Color(0.2, 0.8, 0.4))
	var material := ShaderMaterial.new()
	material.shader = LightmapShader
	material.set_shader_parameter("base_texture", ImageTexture.create_from_image(base))
	material.set_shader_parameter("lightmap_texture", ImageTexture.create_from_image(atlas))
	var reference_shader := Shader.new()
	reference_shader.code = """shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
uniform vec3 reference_rgb;
void fragment() { ALBEDO = vec3(0.0); EMISSION = reference_rgb; }
"""
	var reference_material := ShaderMaterial.new()
	reference_material.shader = reference_shader
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0.5, 0), Vector3(1, 0.5, 0), Vector3(1, -0.5, 0), Vector3(-1, -0.5, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0.25, 0.25), Vector2(0.25, 0.25), Vector2(0.25, 0.25), Vector2(0.25, 0.25)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	viewport.add_child(instance)
	var probes: Array[Dictionary] = []
	for fixture: Dictionary in [
		{"name": "iphone", "scale": Vector2.ONE, "offset": Vector2.ZERO, "multiplier": 1.0, "expected": Color(0.2, 0.08, 0.15)},
		{"name": "optimized", "scale": Vector2.ONE, "offset": Vector2.ZERO, "multiplier": 2.0, "expected": Color(0.4, 0.16, 0.3)},
		{"name": "atlas_st", "scale": Vector2(0.5, 0.5), "offset": Vector2(0.5, 0), "multiplier": 1.0, "expected": Color(0.1, 0.32, 0.1)},
	]:
		instance.material_override = material
		material.set_shader_parameter("lightmap_scale", fixture.scale)
		material.set_shader_parameter("lightmap_offset", fixture.offset)
		material.set_shader_parameter("lightmap_multiplier", fixture.multiplier)
		for _frame in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var rendered := viewport.get_texture().get_image()
		var observed := rendered.get_pixel(128, 64)
		var expected: Color = fixture.expected
		_check(rendered.save_png(OUTPUT_DIR.path_join(str(fixture.name) + ".png")) == OK, "Could not save " + str(fixture.name))
		# Compare the same pipeline with a constant independently calculated
		# result. This separates shader arithmetic from display conversion.
		reference_material.set_shader_parameter("reference_rgb", Vector3(expected.r, expected.g, expected.b))
		instance.material_override = reference_material
		for _frame in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var displayed_reference := viewport.get_texture().get_image().get_pixel(128, 64)
		var largest_error := maxf(absf(observed.r - displayed_reference.r), maxf(absf(observed.g - displayed_reference.g), absf(observed.b - displayed_reference.b)))
		_check(largest_error < 0.008, "%s RGB %s differs from reference render %s" % [fixture.name, observed, displayed_reference])
		probes.append({"name": fixture.name, "observed": [observed.r, observed.g, observed.b], "expected_shader_rgb": [expected.r, expected.g, expected.b], "displayed_reference": [displayed_reference.r, displayed_reference.g, displayed_reference.b], "max_error": largest_error})
	var manifest := FileAccess.open(OUTPUT_DIR.path_join("manifest.json"), FileAccess.WRITE)
	_check(manifest != null, "Could not save lightmap probe manifest")
	if manifest != null:
		manifest.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "viewport": [256, 128], "probes": probes, "failures": failures}, "\t"))
	viewport.queue_free()
	await get_tree().process_frame
	print("LIGHTMAP_VISUAL_CAPTURE_PASS probes=3" if failures.is_empty() else "LIGHTMAP_VISUAL_CAPTURE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("LIGHTMAP VISUAL CAPTURE: " + message)
