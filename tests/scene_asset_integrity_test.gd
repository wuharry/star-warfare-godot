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


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SCENE ASSET INTEGRITY TEST: " + message)


func _run() -> void:
	for level_number in LEVEL_NUMBERS:
		_check_level(level_number)
	if failures.is_empty():
		print(
			"SCENE_ASSET_INTEGRITY_TEST_PASS levels=%d materials=%d textures=%d textured_surfaces=%d source_alpha_surfaces=%d transparent_surfaces=%d"
			% [LEVEL_NUMBERS.size(), checked_materials, checked_textures, textured_surfaces, source_alpha_surfaces, transparent_surfaces]
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

	var mesh := load(obj_path) as Mesh
	_check(mesh != null, "Level %d stage mesh did not import" % level_number)
	if mesh == null:
		return
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
		var material := runtime_instance.get_surface_override_material(surface_index) as BaseMaterial3D
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
