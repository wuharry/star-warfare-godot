extends SceneTree

const OUTPUT := "res://assets/armors/thunder/thunder.scn"
const ORIGINAL := "res://assets/models/player/animated/player.gltf"
const PART_NAMES := ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"]
const MATERIAL_COUNT := 15
var variant := "sw2"
var input_path := ""
var output_path := ""
const TEXTURES := [
	"f8d96c60d30f", "dce7a1446714", "d6da6925f6b4", "df2d0a0b46da", "14ceb45bf36d",
]


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--helmet="):
			variant = argument.trim_prefix("--helmet=")
	if variant not in ["sw2", "prototype"]:
		_fail("Unknown helmet variant: " + variant)
		return
	input_path = "res://test_output/armor_rework/thunder_%s_meshes.json" % variant
	output_path = "res://assets/armors/thunder/thunder_%s.scn" % variant
	if "--self-test" in OS.get_cmdline_user_args():
		_test_validation.call_deferred()
	else:
		_build.call_deferred()


func _build() -> void:
	var json := JSON.new()
	if not FileAccess.file_exists(input_path):
		_fail("Missing Blender export: " + input_path)
		return
	var parse_error := json.parse(FileAccess.get_file_as_string(input_path))
	if parse_error != OK or not json.data is Array:
		_fail("Invalid Blender JSON: " + json.get_error_message())
		return
	var packed_original := load(ORIGINAL) as PackedScene
	if packed_original == null:
		_fail("Cannot load original player skeleton")
		return
	var original := packed_original.instantiate()
	root.add_child(original)
	var skeletons := original.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		original.free()
		_fail("Original player has no Skeleton3D")
		return
	var skeleton := skeletons[0] as Skeleton3D
	var skin := Skin.new()
	var bone_indices := {}
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		bone_indices[bone_name] = bone
		skin.add_named_bind(bone_name, skeleton.get_bone_global_rest(bone).affine_inverse())
	var source: Array = json.data
	var validation_error := _validate_source(source, bone_indices)
	if not validation_error.is_empty():
		original.free()
		_fail(validation_error)
		return
	var materials := _materials()
	if materials.size() != MATERIAL_COUNT:
		original.free()
		_fail("Could not load Thunder shaders or source textures")
		return
	var container := Node3D.new()
	container.name = "ThunderRework"
	var triangle_count := 0
	for part: Dictionary in source:
		var mesh := ArrayMesh.new()
		for material_id in MATERIAL_COUNT:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var tangents := PackedFloat32Array()
			var uvs := PackedVector2Array()
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			for triangle in part.materials.size():
				if int(part.materials[triangle]) != material_id:
					continue
				triangle_count += 1
				# Blender's exported face winding and V axis match the Viper pipeline.
				for corner in [2, 1, 0]:
					var index: int = triangle * 3 + corner
					vertices.append(Vector3(part.positions[index * 3], part.positions[index * 3 + 1], part.positions[index * 3 + 2]))
					normals.append(Vector3(part.normals[index * 3], part.normals[index * 3 + 1], part.normals[index * 3 + 2]))
					# Keep Blender's original tangent frame paired with its normal
					# map, even though texture addressing below flips V.
					for axis in 4:
						tangents.append(part.tangents[index * 4 + axis])
					uvs.append(Vector2(part.uv[index * 2], 1.0 - float(part.uv[index * 2 + 1])))
					for influence in range(4):
						if influence < part.bones[index].size():
							bones.append(bone_indices[part.bones[index][influence]])
							weights.append(part.weights[index][influence])
						else:
							bones.append(0)
							weights.append(0.0)
			if vertices.is_empty():
				continue
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = tangents
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[material_id])
		var instance := MeshInstance3D.new()
		instance.name = str(part.name)
		instance.mesh = mesh
		instance.skin = skin
		instance.skeleton = NodePath("..")
		instance.extra_cull_margin = 1.0
		instance.set_meta("armor_rework", "thunder_helmet_v5_" + variant)
		container.add_child(instance)
		instance.owner = container
	var packed := PackedScene.new()
	var error := packed.pack(container)
	if error == OK:
		error = ResourceSaver.save(packed, output_path)
	if error == OK and variant == "sw2":
		error = ResourceSaver.save(packed, OUTPUT)
	print("THUNDER_COMPILE_%s parts=%d triangles=%d bones=%d" % ["PASS" if error == OK else "FAIL", container.get_child_count(), triangle_count, skin.get_bind_count()])
	container.free()
	original.free()
	quit(0 if error == OK else 1)


func _validate_source(source: Array, bone_indices: Dictionary) -> String:
	if source.size() != PART_NAMES.size():
		return "Expected exactly four Thunder parts"
	var seen := {}
	for value: Variant in source:
		if not value is Dictionary:
			return "Each part must be an object"
		var part: Dictionary = value
		var part_name := str(part.get("name", ""))
		if not part_name in PART_NAMES or seen.has(part_name):
			return "Unexpected or duplicated part: " + part_name
		seen[part_name] = true
		for key in ["positions", "normals", "tangents", "uv", "bones", "weights", "materials"]:
			if not part.get(key) is Array:
				return part_name + " missing array: " + key
		var triangles: int = part.materials.size()
		var corners := triangles * 3
		if triangles == 0 or part.positions.size() != corners * 3 or part.normals.size() != corners * 3 or part.tangents.size() != corners * 4 or part.uv.size() != corners * 2 or part.bones.size() != corners or part.weights.size() != corners:
			return part_name + " has inconsistent triangle arrays"
		for material_id: Variant in part.materials:
			if not _is_number(material_id) or float(material_id) != int(material_id) or int(material_id) < 0 or int(material_id) >= MATERIAL_COUNT:
				return part_name + " has invalid material ID"
		for key in ["positions", "normals", "tangents", "uv"]:
			for component: Variant in part[key]:
				if not _is_number(component):
					return part_name + " has non-finite geometry: " + key
		for index in corners:
			var normal := Vector3(part.normals[index * 3], part.normals[index * 3 + 1], part.normals[index * 3 + 2])
			if normal.length_squared() < 0.01:
				return part_name + " has zero-length vertex normal"
			if int(part.materials[index / 3]) in [11, 14]:
				var tangent := Vector3(part.tangents[index * 4], part.tangents[index * 4 + 1], part.tangents[index * 4 + 2])
				if absf(tangent.length_squared() - 1.0) > 0.02 or absf(tangent.dot(normal.normalized())) > 0.02 or absf(absf(part.tangents[index * 4 + 3]) - 1.0) > 0.002:
					return part_name + " has invalid normal-map tangent frame"
			if not part.bones[index] is Array or not part.weights[index] is Array:
				return part_name + " has invalid skin arrays"
			var names: Array = part.bones[index]
			var vertex_weights: Array = part.weights[index]
			if names.is_empty() or names.size() > 4 or names.size() != vertex_weights.size():
				return part_name + " needs one to four matching skin influences"
			var weight_sum := 0.0
			for influence in names.size():
				if not names[influence] is String or not bone_indices.has(names[influence]):
					return part_name + " has unknown bone: " + str(names[influence])
				var weight: Variant = vertex_weights[influence]
				if not _is_number(weight) or float(weight) < 0.0:
					return part_name + " has invalid skin weight"
				weight_sum += float(weight)
			if absf(weight_sum - 1.0) > 0.002:
				return part_name + " skin weights are not normalized"
	return ""


func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	var painted_shader := load("res://assets/armors/thunder/painted_armor.gdshader") as Shader
	var shell_shader := load("res://assets/armors/thunder/hard_surface.gdshader") as Shader
	if painted_shader == null or shell_shader == null:
		return result
	for index in TEXTURES.size():
		var directory := "res://assets/equipment_refined/textures" if index == 0 else "res://assets/armors/thunder/textures"
		var texture := load("%s/%s.png" % [directory, TEXTURES[index]]) as Texture2D
		if texture == null:
			return []
		var material := ShaderMaterial.new()
		material.resource_name = "ThunderPainted_" + ["head", "body", "shoulder", "arms", "legs"][index]
		material.shader = painted_shader
		material.set_shader_parameter("albedo_texture", texture)
		material.set_shader_parameter("amber_visor", 1.0 if index == 0 else 0.0)
		result.append(material)
	# IDs 5..10 are shared with build_thunder.py. Colors are sRGB.
	var finishes := [
		["SteelBlueShell", Color("355f88"), 0.12, 0.62, 0.38, 0.0],
		["NavyShell", Color("203750"), 0.12, 0.64, 0.30, 0.0],
		["MetalEdge", Color("496984"), 0.16, 0.55, 0.30, 0.0],
		["WarmGold", Color("efb93d"), 0.12, 0.55, 0.34, 0.0],
		["AmberVisor", Color("eea321"), 0.04, 0.42, 0.55, 0.22],
		["DarkJoint", Color("181b20"), 0.0, 0.84, 0.20, 0.0],
	]
	var shell_detail := load("res://assets/armors/thunder/textures/blue_shell_paint.png") as Texture2D
	var visor_paint := load("res://assets/armors/thunder/textures/amber_visor_paint.png") as Texture2D
	if shell_detail == null or visor_paint == null:
		return []
	for finish: Array in finishes:
		var material := ShaderMaterial.new()
		material.resource_name = "Thunder_" + str(finish[0])
		material.shader = shell_shader
		material.set_shader_parameter("paint_color", finish[1])
		material.set_shader_parameter("metalness", finish[2])
		material.set_shader_parameter("surface_roughness", finish[3])
		material.set_shader_parameter("readability_fill", finish[4])
		material.set_shader_parameter("glow_strength", finish[5])
		material.set_shader_parameter("shell_detail_texture", shell_detail)
		material.set_shader_parameter("visor_paint_texture", visor_paint)
		material.set_shader_parameter("paint_detail", 1.0 if finish[0] in ["SteelBlueShell", "NavyShell", "MetalEdge"] else 0.0)
		if finish[0] == "AmberVisor":
			material.set_shader_parameter("visor_finish", 1.0)
		result.append(material)
	var helmet := ShaderMaterial.new()
	helmet.resource_name = "Thunder_PairedHelmet"
	helmet.shader = load("res://assets/armors/thunder/helmet_detail.gdshader") as Shader
	if helmet.shader == null:
		return []
	var helmet_textures := {"albedo_texture": "helmet_detail_albedo", "source_albedo_texture": "helmet_source_albedo", "normal_texture": "helmet_detail_normal", "emission_texture": "helmet_detail_emission"}
	for binding in helmet_textures:
		var stem: String = helmet_textures[binding]
		var image := _raw_helmet_texture(stem)
		if image == null:
			return []
		helmet.set_shader_parameter(binding, image)
	result.append(helmet)
	for finish in [["RespiratorSteel", Color("343d49")], ["RespiratorEdge", Color("596570")]]:
		var material := ShaderMaterial.new()
		material.resource_name = "Thunder_" + str(finish[0])
		material.shader = shell_shader
		material.set_shader_parameter("paint_color", finish[1])
		material.set_shader_parameter("metalness", 0.12)
		material.set_shader_parameter("surface_roughness", 0.65)
		material.set_shader_parameter("readability_fill", 0.15)
		material.set_shader_parameter("paint_detail", 1.0)
		material.set_shader_parameter("shell_detail_texture", shell_detail)
		result.append(material)
	var visor := helmet.duplicate() as ShaderMaterial
	visor.resource_name = "Thunder_EngravedVisor"
	result.append(visor)
	return result


func _raw_helmet_texture(stem: String) -> Texture2D:
	# Unity's alpha channel carries material masks, including fully transparent
	# pixels whose RGB still contains essential paint and tangent normals.
	# Godot's default fix_alpha_border rewrites those RGB values. Load the raw
	# PNG with Image (no import processing), then save a portable lossless
	# ImageTexture resource through Godot itself. No .import/cache edits.
	var source := "res://assets/armors/thunder/textures/%s.png" % stem
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(source))
	if decode_error != OK or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	var output := "res://assets/armors/thunder/textures/%s.res" % stem
	var error := ResourceSaver.save(texture, output, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Cannot save raw Thunder texture: " + source)
		return null
	return load(output) as Texture2D


func _fail(message: String) -> void:
	push_error("THUNDER_COMPILE_FAIL: " + message)
	quit(1)


func _test_validation() -> void:
	# This path never loads or writes the game scene. Exercise malformed export
	# rejection before Blender output is allowed to replace the runtime asset.
	var valid := []
	for part_name in PART_NAMES:
		valid.append({
			"name": part_name,
			"positions": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
			"normals": [0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0],
			"tangents": [1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0],
			"uv": [0.0, 0.0, 1.0, 0.0, 0.0, 1.0],
			"bones": [["Head"], ["Head"], ["Head"]],
			"weights": [[1.0], [1.0], [1.0]],
			"materials": [5],
		})
	var bone_indices := {"Head": 0}
	var rejected := []
	var missing_part: Array = valid.duplicate(true)
	missing_part.pop_back()
	rejected.append(missing_part)
	var duplicated_part: Array = valid.duplicate(true)
	duplicated_part[1].name = PART_NAMES[0]
	rejected.append(duplicated_part)
	var wrong_length: Array = valid.duplicate(true)
	wrong_length[0].positions.pop_back()
	rejected.append(wrong_length)
	var bad_material: Array = valid.duplicate(true)
	bad_material[0].materials[0] = MATERIAL_COUNT
	rejected.append(bad_material)
	var bad_bone: Array = valid.duplicate(true)
	bad_bone[0].bones[0][0] = "MissingBone"
	rejected.append(bad_bone)
	var bad_weights: Array = valid.duplicate(true)
	bad_weights[0].weights[0][0] = 0.5
	rejected.append(bad_weights)
	var bad_float: Array = valid.duplicate(true)
	bad_float[0].positions[0] = NAN
	rejected.append(bad_float)
	var bad_normal: Array = valid.duplicate(true)
	bad_normal[0].normals = [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]
	rejected.append(bad_normal)
	var missing_tangent: Array = valid.duplicate(true)
	missing_tangent[0].tangents.pop_back()
	rejected.append(missing_tangent)
	var bad_tangent: Array = valid.duplicate(true)
	bad_tangent[0].materials[0] = 11
	bad_tangent[0].tangents[0] = 0.0
	rejected.append(bad_tangent)
	var bad_handedness: Array = valid.duplicate(true)
	bad_handedness[0].materials[0] = 11
	bad_handedness[0].tangents[3] = 0.0
	rejected.append(bad_handedness)
	var passed := _validate_source(valid, bone_indices).is_empty()
	for malformed: Array in rejected:
		passed = not _validate_source(malformed, bone_indices).is_empty() and passed
	print("THUNDER_COMPILER_VALIDATION_%s cases=%d" % ["PASS" if passed else "FAIL", rejected.size() + 1])
	quit(0 if passed else 1)
