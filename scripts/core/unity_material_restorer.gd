class_name UnityMaterialRestorer

const LIGHTMAP_SHADER = preload("res://assets/shaders/unity_lightmap.gdshader")
const SOLID_OVERLAY_SHADER = preload("res://assets/shaders/unity_solid_overlay.gdshader")
static var _lightmap_shaders: Dictionary = {}
static var _weapon_overlays: Dictionary = {}


static func restore_weapon_overlays(instance: MeshInstance3D, weapon_id: int) -> void:
	if weapon_id not in [36, 45, 46] or instance.mesh == null:
		return
	# Recover the original Unity two-texture materials omitted by old OBJ caches.
	var definitions := {
		36: ["_Material_26_", "gun_17.png", "gun_17_l.png", 2.0],
		45: ["_HotWing-Material_25_", "HotWing_D.png", "HotWing_L.png", 1.0],
		46: ["_33_EartherBreaker-Material_19_", "33_EartherBreaker_D.png", "33_EartherBreaker_L.png", 1.0],
	}
	var definition: Array = definitions[weapon_id]
	for surface in instance.mesh.get_surface_count():
		var source := instance.mesh.surface_get_material(surface) as StandardMaterial3D
		if source == null or not source.resource_name.begins_with(str(definition[0])):
			continue
		# Share these immutable materials across rapid weapon swaps and reload props.
		if _weapon_overlays.has(weapon_id):
			instance.set_surface_override_material(surface, _weapon_overlays[weapon_id])
			continue
		var material := _overlay_material(source, {
			"overlay_texture": "res://assets/models/weapons/" + str(definition[2]),
			"overlay_color": [1.0, 1.0, 1.0, 1.0],
			"overlay_multiplier": definition[3],
			# WHITE DRILL's source mesh has no second UV channel; use its authored UV0.
			"base_uses_uv2": false,
		})
		material.set_shader_parameter("base_texture", load(preload("res://scripts/core/equipment_refinement.gd").texture_path("res://assets/models/weapons/" + str(definition[1]))))
		_weapon_overlays[weapon_id] = material
		instance.set_surface_override_material(surface, material)


static func load_stage_mesh(level_root: String, metadata: Dictionary) -> Mesh:
	var visual := str(metadata.get("visual_with_uv2", "stage.obj"))
	var resource: Resource = load(level_root.path_join(visual))
	if resource is Mesh:
		return resource as Mesh
	if resource is PackedScene:
		var scene := (resource as PackedScene).instantiate()
		var instances := scene.find_children("*", "MeshInstance3D", true, false)
		var mesh: Mesh = null
		if scene is MeshInstance3D:
			mesh = (scene as MeshInstance3D).mesh
		elif not instances.is_empty():
			mesh = (instances[0] as MeshInstance3D).mesh
		scene.free()
		return mesh
	return null

# Wavefront MTL can carry a diffuse map and opacity, but it cannot represent
# the blend, culling, depth-write, or unlit state of the recovered Unity
# shaders. The exporter stores those bits in level.json; this helper restores
# them as per-instance material overrides without mutating imported meshes.


static func apply_to_mesh(instance: MeshInstance3D, states: Variant) -> int:
	if instance == null or instance.mesh == null or not states is Dictionary:
		return 0
	var repaired := 0
	for surface_index in instance.mesh.get_surface_count():
		var source := instance.mesh.surface_get_material(surface_index) as StandardMaterial3D
		if source == null:
			continue
		var state_value: Variant = states.get(source.resource_name, {})
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		if state.has("overlay_texture"):
			instance.set_surface_override_material(surface_index, _overlay_material(source, state))
			repaired += 1
			continue
		if state.has("lightmap_texture"):
			instance.set_surface_override_material(surface_index, _lightmap_material(source, state))
			repaired += 1
			continue
		var material := source.duplicate(true) as StandardMaterial3D
		if material == null:
			continue
		var blend := str(state.get("blend", "opaque"))
		match blend:
			"alpha":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			"additive":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			"cutout":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = clampf(float(state.get("alpha_scissor_threshold", 0.5)), 0.0, 1.0)
			_:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		material.cull_mode = (
			BaseMaterial3D.CULL_DISABLED
			if bool(state.get("cull_disabled", false))
			else BaseMaterial3D.CULL_BACK
		)
		if not bool(state.get("depth_write", true)):
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		elif blend == "opaque" or blend == "cutout":
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		else:
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if bool(state.get("unshaded", false))
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)
		instance.set_surface_override_material(surface_index, material)
		repaired += 1
	return repaired


static func _lightmap_material(source: StandardMaterial3D, state: Dictionary) -> ShaderMaterial:
	var blend := str(state.get("blend", "opaque"))
	var cull_disabled := bool(state.get("cull_disabled", false))
	var lightmap_repeat := bool(state.get("lightmap_repeat", false))
	var key := "%s_%s_%s" % [blend, cull_disabled, lightmap_repeat]
	if not _lightmap_shaders.has(key):
		var code: String = LIGHTMAP_SHADER.code
		if lightmap_repeat:
			code = code.replace("filter_linear_mipmap, repeat_disable", "filter_linear_mipmap, repeat_enable")
		var modes := "ambient_light_disabled, specular_disabled"
		if cull_disabled:
			modes += ", cull_disabled"
		if blend == "alpha" or blend == "additive":
			modes += ", depth_draw_never"
			if blend == "additive":
				modes += ", blend_add"
			code = "#define USE_ALPHA\n" + code
		code = code.replace("render_mode ambient_light_disabled, specular_disabled;", "render_mode %s;" % modes)
		var shader := Shader.new()
		shader.code = code
		_lightmap_shaders[key] = shader
	var material := ShaderMaterial.new()
	material.resource_name = source.resource_name
	material.shader = _lightmap_shaders[key]
	material.set_shader_parameter("base_texture", source.albedo_texture)
	material.set_shader_parameter("base_color", source.albedo_color)
	material.set_shader_parameter("lightmap_texture", load(str(state.lightmap_texture)))
	material.set_shader_parameter("lightmap_scale", Vector2(float(state.lightmap_scale[0]), float(state.lightmap_scale[1])))
	material.set_shader_parameter("lightmap_offset", Vector2(float(state.lightmap_offset[0]), float(state.lightmap_offset[1])))
	material.set_shader_parameter("lightmap_multiplier", float(state.get("lightmap_multiplier", 1.0)))
	var quality := str(GameState.settings.get("quality", "high"))
	material.set_shader_parameter("dynamic_light_strength", 0.14 if quality == "high" else (0.06 if quality == "medium" else 0.0))
	return material


static func _overlay_material(source: StandardMaterial3D, state: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = source.resource_name
	material.shader = SOLID_OVERLAY_SHADER
	material.set_shader_parameter("base_texture", source.albedo_texture)
	material.set_shader_parameter("overlay_texture", load(str(state.overlay_texture)))
	var tint: Array = state.overlay_color
	material.set_shader_parameter("overlay_color", Color(float(tint[0]), float(tint[1]), float(tint[2]), float(tint[3])))
	material.set_shader_parameter("overlay_multiplier", float(state.overlay_multiplier))
	material.set_shader_parameter("base_uses_uv2", bool(state.base_uses_uv2))
	return material
