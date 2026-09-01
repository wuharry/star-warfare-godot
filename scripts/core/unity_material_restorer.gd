class_name UnityMaterialRestorer

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
