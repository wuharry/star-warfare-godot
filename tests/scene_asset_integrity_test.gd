extends Node

const UnityMaterialRestorerScript = preload("res://scripts/core/unity_material_restorer.gd")
const LEVEL_NUMBERS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21]
# Level 19 intentionally renders one source collision material as flat grey;
# it is the only visual material in the recovered Unity scenes without a map.
const INTENTIONAL_UNTEXTURED := {19: ["collision"]}

var failures: Array[String] = []
var checked_materials := 0
var checked_textures := 0
var textured_surfaces := 0
var source_alpha_surfaces := 0
var transparent_surfaces := 0
var checked_texture_paths := {}
var texture_alpha_modes := {}
var lightmapped_surfaces := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SCENE ASSET INTEGRITY TEST: " + message)


func _run() -> void:
	for level_number in LEVEL_NUMBERS:
		_check_level(level_number)
	_check(lightmapped_surfaces == 270, "the source's 270 lightmapped surfaces were not all restored")
	if failures.is_empty():
		print(
			"SCENE_ASSET_INTEGRITY_TEST_PASS levels=%d materials=%d textures=%d textured_surfaces=%d source_alpha_surfaces=%d transparent_surfaces=%d lightmapped_surfaces=%d"
			% [LEVEL_NUMBERS.size(), checked_materials, checked_textures, textured_surfaces, source_alpha_surfaces, transparent_surfaces, lightmapped_surfaces]
		)
		get_tree().quit(0)
	else:
		print("SCENE_ASSET_INTEGRITY_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)


func _check_level(level_number: int) -> void:
	var root := "res://assets/models/levels/level_%02d" % level_number
	var obj_path := root.path_join("stage.obj")
	var mtl_path := root.path_join("stage.mtl")
	var metadata_path := root.path_join("level.json")
	_check(FileAccess.file_exists(obj_path), "Level %d stage.obj is missing" % level_number)
	_check(FileAccess.file_exists(mtl_path), "Level %d stage.mtl is missing" % level_number)
	if not FileAccess.file_exists(obj_path) or not FileAccess.file_exists(mtl_path):
		return
	var metadata_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	_check(metadata_value is Dictionary, "Level %d metadata is invalid" % level_number)
	if not metadata_value is Dictionary:
		return
	var material_states: Dictionary = metadata_value.get("material_render_modes", {})

	var materials := _parse_materials(mtl_path)
	var used_materials := _parse_used_materials(obj_path)
	_check(not used_materials.is_empty(), "Level %d stage.obj has no materials" % level_number)
	_check(used_materials.size() <= 256, "Level %d exceeds Godot's 256 mesh-surface limit" % level_number)
	_check(material_states.size() == materials.size(), "Level %d material render metadata is incomplete" % level_number)
	for material_name: String in used_materials:
		_check(materials.has(material_name), "Level %d references undefined material %s" % [level_number, material_name])
		if not materials.has(material_name):
			continue
		checked_materials += 1
		var texture_name := str(materials[material_name])
		var intentional_untextured := _is_intentional_untextured(level_number, material_name)
		_check(not texture_name.is_empty() or intentional_untextured, "Level %d material %s has no diffuse texture" % [level_number, material_name])
		if texture_name.is_empty():
			continue
		var texture_path := root.path_join(texture_name)
		_check(FileAccess.file_exists(texture_path), "Level %d material %s is missing %s" % [level_number, material_name, texture_name])
		_check(FileAccess.file_exists(texture_path + ".import"), "Level %d texture %s has no import sidecar" % [level_number, texture_name])
		if not FileAccess.file_exists(texture_path):
			continue
		if checked_texture_paths.has(texture_path):
			continue
		checked_texture_paths[texture_path] = true
		var image := Image.new()
		var image_error := image.load(ProjectSettings.globalize_path(texture_path))
		_check(image_error == OK, "Level %d texture %s cannot be decoded" % [level_number, texture_name])
		if image_error == OK:
			_check(image.get_width() > 1 and image.get_height() > 1, "Level %d texture %s is empty" % [level_number, texture_name])
			texture_alpha_modes[texture_path] = image.detect_alpha()
		checked_textures += 1

	var mesh := UnityMaterialRestorerScript.load_stage_mesh(root, metadata_value)
	_check(mesh != null, "Level %d stage mesh did not import" % level_number)
	if mesh == null:
		return
	_check_mesh_parity(level_number, load(obj_path) as Mesh, mesh)
	var bounds := mesh.get_aabb()
	_check(bounds.size.length_squared() > 1.0, "Level %d stage mesh bounds are empty" % level_number)
	_check(_finite_vector(bounds.position) and _finite_vector(bounds.size), "Level %d stage mesh bounds are not finite" % level_number)
	_check(mesh.get_surface_count() == used_materials.size(), "Level %d imported %d surfaces for %d used materials" % [level_number, mesh.get_surface_count(), used_materials.size()])
	var runtime_instance := MeshInstance3D.new()
	runtime_instance.mesh = mesh
	var repaired_count := UnityMaterialRestorerScript.apply_to_mesh(runtime_instance, material_states)
	_check(repaired_count == mesh.get_surface_count(), "Level %d repaired %d of %d runtime materials" % [level_number, repaired_count, mesh.get_surface_count()])
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		_check(arrays.size() == Mesh.ARRAY_MAX, "Level %d surface %d has invalid arrays" % [level_number, surface_index])
		if arrays.size() != Mesh.ARRAY_MAX:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		_check(not vertices.is_empty(), "Level %d surface %d has no vertices" % [level_number, surface_index])
		_check(normals.size() == vertices.size(), "Level %d surface %d has incomplete normals" % [level_number, surface_index])
		_check(uvs.size() == vertices.size(), "Level %d surface %d has incomplete UVs" % [level_number, surface_index])
		var source_material := mesh.surface_get_material(surface_index) as BaseMaterial3D
		var override_material := runtime_instance.get_surface_override_material(surface_index)
		if override_material is ShaderMaterial and source_material != null:
			var state: Dictionary = material_states.get(source_material.resource_name, {})
			if state.has("overlay_texture"):
				_check_overlay_material(level_number, override_material as ShaderMaterial, state, source_material)
				continue
			_check_lightmap_material(level_number, surface_index, override_material as ShaderMaterial, state, arrays, source_material)
			continue
		var material := override_material as BaseMaterial3D
		_check(source_material != null, "Level %d surface %d has no imported material" % [level_number, surface_index])
		_check(material != null, "Level %d surface %d has no runtime material override" % [level_number, surface_index])
		if source_material != null and material != null:
			var intentional_untextured := _is_intentional_untextured(level_number, source_material.resource_name)
			_check(material.albedo_texture != null or intentional_untextured, "Level %d surface %d has no imported diffuse texture" % [level_number, surface_index])
			var state_value: Variant = material_states.get(source_material.resource_name, {})
			_check(state_value is Dictionary and not state_value.is_empty(), "Level %d material %s has no Unity render state" % [level_number, source_material.resource_name])
			var state: Dictionary = state_value if state_value is Dictionary else {}
			var blend := str(state.get("blend", "opaque"))
			if material.albedo_texture != null:
				textured_surfaces += 1
				var alpha_mode := int(texture_alpha_modes.get(material.albedo_texture.resource_path, Image.ALPHA_NONE))
				if alpha_mode != Image.ALPHA_NONE:
					source_alpha_surfaces += 1
			if blend == "alpha" or blend == "additive":
				transparent_surfaces += 1
				_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Level %d surface %d did not restore alpha blending" % [level_number, surface_index])
				var expected_blend := BaseMaterial3D.BLEND_MODE_ADD if blend == "additive" else BaseMaterial3D.BLEND_MODE_MIX
				_check(material.blend_mode == expected_blend, "Level %d surface %d has the wrong blend equation" % [level_number, surface_index])
			elif blend == "cutout":
				transparent_surfaces += 1
				_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Level %d surface %d did not restore alpha cutout" % [level_number, surface_index])
			else:
				_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Level %d surface %d makes an opaque Unity shader transparent" % [level_number, surface_index])
			var expected_cull := BaseMaterial3D.CULL_DISABLED if bool(state.get("cull_disabled", false)) else BaseMaterial3D.CULL_BACK
			_check(material.cull_mode == expected_cull, "Level %d surface %d has the wrong cull mode" % [level_number, surface_index])
			if not bool(state.get("depth_write", true)):
				_check(material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "Level %d surface %d still writes depth" % [level_number, surface_index])
	# Detach the mesh before freeing the temporary rendering instance. The dummy
	# renderer otherwise tears down each surface override after its material RID
	# is already gone and reports a misleading "material is null" error.
	runtime_instance.mesh = null
	runtime_instance.free()


func _check_mesh_parity(level_number: int, original: Mesh, runtime: Mesh) -> void:
	_check(original != null, "Level %d has no OBJ reference mesh" % level_number)
	if original == null:
		return
	var label := "Level %d glTF" % level_number
	var source_bounds := original.get_aabb()
	var bounds := runtime.get_aabb()
	_check(bounds.position.distance_to(source_bounds.position) < 0.01 and bounds.size.distance_to(source_bounds.size) < 0.01, label + " changed the original scene bounds")
	var source_triangles := 0
	var runtime_triangles := 0
	var source_coordinates: Dictionary = {}
	for surface_index in original.get_surface_count():
		var arrays := original.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		source_triangles += (vertices.size() if indices.is_empty() else indices.size()) / 3
		var material_name := original.surface_get_material(surface_index).resource_name
		for vertex_index in vertices.size():
			var point := vertices[vertex_index]
			var key := "%s:%.3f:%.3f:%.3f" % [material_name, point.x, point.y, point.z]
			if not source_coordinates.has(key):
				source_coordinates[key] = []
			(source_coordinates[key] as Array).append(uvs[vertex_index])
	var mismatched_uvs := 0
	for surface_index in runtime.get_surface_count():
		var arrays := runtime.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		runtime_triangles += (vertices.size() if indices.is_empty() else indices.size()) / 3
		var material_name := runtime.surface_get_material(surface_index).resource_name
		for vertex_index in vertices.size():
			var point := vertices[vertex_index]
			var key := "%s:%.3f:%.3f:%.3f" % [material_name, point.x, point.y, point.z]
			var matched := false
			for source_uv: Vector2 in source_coordinates.get(key, []):
				if source_uv.distance_to(uvs[vertex_index]) < 0.001:
					matched = true
					break
			if not matched:
				mismatched_uvs += 1
	_check(runtime_triangles == source_triangles, label + " changed the source triangle count")
	_check(mismatched_uvs == 0, "%s changed %d source vertex/UV0 pairs" % [label, mismatched_uvs])


func _check_lightmap_material(level_number: int, surface_index: int, material: ShaderMaterial, state: Dictionary, arrays: Array, source: BaseMaterial3D) -> void:
	var label := "Level %d surface %d" % [level_number, surface_index]
	_check(state.has("lightmap_texture"), label + " uses a lightmap shader without source lightmap metadata")
	if not state.has("lightmap_texture"):
		return
	lightmapped_surfaces += 1
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(uv2s.size() == vertices.size(), label + " lost the authored UV2 channel")
	var base: Texture2D = material.get_shader_parameter("base_texture")
	var lightmap: Texture2D = material.get_shader_parameter("lightmap_texture")
	_check(base != null and base == source.albedo_texture, label + " lost its base texture")
	_check(lightmap != null and lightmap.resource_path == str(state.lightmap_texture), label + " lost its original lightmap")
	if base != null:
		textured_surfaces += 1
		if int(texture_alpha_modes.get(base.resource_path, Image.ALPHA_NONE)) != Image.ALPHA_NONE:
			source_alpha_surfaces += 1
	_check(is_equal_approx(float(material.get_shader_parameter("lightmap_multiplier")), float(state.lightmap_multiplier)), label + " has the wrong source shader multiplier")
	var expected_scale := Vector2(float(state.lightmap_scale[0]), float(state.lightmap_scale[1]))
	var expected_offset := Vector2(float(state.lightmap_offset[0]), float(state.lightmap_offset[1]))
	_check((material.get_shader_parameter("lightmap_scale") as Vector2).is_equal_approx(expected_scale), label + " lost the lightmap atlas scale")
	_check((material.get_shader_parameter("lightmap_offset") as Vector2).is_equal_approx(expected_offset), label + " lost the lightmap atlas offset")
	var alpha := str(state.blend) in ["alpha", "additive"]
	_check(material.shader.code.contains("#define USE_ALPHA") == alpha, label + " changed the source transparency")
	_check(material.shader.code.contains(", cull_disabled") == bool(state.cull_disabled), label + " changed the source culling")
	_check(material.shader.code.contains("depth_draw_never") == (not bool(state.depth_write)), label + " changed the source depth write")
	_check(material.shader.code.contains("filter_linear_mipmap, repeat_enable") == bool(state.get("lightmap_repeat", false)), label + " changed the source lightmap wrap mode")
	if alpha:
		transparent_surfaces += 1


func _check_overlay_material(level_number: int, material: ShaderMaterial, state: Dictionary, source: BaseMaterial3D) -> void:
	var label := "Level %d luminous fixture" % level_number
	var base: Texture2D = material.get_shader_parameter("base_texture")
	var overlay: Texture2D = material.get_shader_parameter("overlay_texture")
	_check(base != null and base == source.albedo_texture, label + " lost its base texture")
	_check(overlay != null and overlay.resource_path == str(state.overlay_texture), label + " lost its luminous layer")
	_check(is_equal_approx(float(material.get_shader_parameter("overlay_multiplier")), 2.0 if level_number == 5 else 1.0), label + " changed the original shader multiplier")
	_check(bool(material.get_shader_parameter("base_uses_uv2")) == (level_number == 5), label + " changed its source texture coordinate binding")
	if base != null:
		textured_surfaces += 1


func _parse_materials(mtl_path: String) -> Dictionary:
	var result := {}
	var current_name := ""
	for raw_line in FileAccess.get_file_as_string(mtl_path).split("\n"):
		var line := str(raw_line).strip_edges()
		if line.begins_with("newmtl "):
			current_name = line.trim_prefix("newmtl ").strip_edges()
			result[current_name] = ""
		elif line.begins_with("map_Kd ") and not current_name.is_empty():
			result[current_name] = line.trim_prefix("map_Kd ").strip_edges().trim_prefix("\"").trim_suffix("\"")
	return result


func _parse_used_materials(obj_path: String) -> Array[String]:
	var result: Array[String] = []
	for raw_line in FileAccess.get_file_as_string(obj_path).split("\n"):
		var line := str(raw_line).strip_edges()
		if not line.begins_with("usemtl "):
			continue
		var material_name := line.trim_prefix("usemtl ").strip_edges()
		if not result.has(material_name):
			result.append(material_name)
	return result


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_intentional_untextured(level_number: int, material_name: String) -> bool:
	var names: Array = INTENTIONAL_UNTEXTURED.get(level_number, [])
	return names.has(material_name)
