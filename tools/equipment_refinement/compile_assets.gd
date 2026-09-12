extends SceneTree

const BASE := "res://assets/equipment_refined/"
const WORK := "res://test_output/equipment_refinement/"
const Catalog = preload("res://scripts/core/armor_catalog.gd")
var meshes: Dictionary
var texture_map: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	meshes = JSON.parse_string(FileAccess.get_file_as_string(WORK + "meshes.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "manifest.json"))
	for job: Dictionary in manifest.textures:
		if job.status == "approved" and ResourceLoader.exists(job.output):
			texture_map[job.source] = job.output
	for folder in ["armors", "weapons"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE + folder))
	var avatar := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(avatar)
	for id in range(1, Catalog.SET_NAMES.size()):
		var source: Node = avatar
		if id >= Catalog.CALLOFMINI_FIRST_ID:
			source = (load(Catalog.gameplay_scene_path(id)) as PackedScene).instantiate()
		var container := Node3D.new()
		container.name = "RefinedArmor%02d" % id
		for prefix in ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]:
			var original := source.find_child(prefix + "%02d" % id, true, false) as MeshInstance3D
			var replacement := MeshInstance3D.new()
			replacement.name = original.name
			replacement.transform = original.transform
			replacement.skin = original.skin
			replacement.skeleton = NodePath("..")
			replacement.extra_cull_margin = 1.0
			replacement.mesh = _compile(original.mesh, str(original.name), true, original)
			replacement.set_meta("armor_rework", "original_refined_%02d" % id)
			container.add_child(replacement)
			replacement.owner = container
		var packed := PackedScene.new()
		assert(packed.pack(container) == OK)
		assert(ResourceSaver.save(packed, BASE + "armors/armor_%02d.scn" % id) == OK)
		container.free()
		if source != avatar:
			source.free()
	var sources: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK + "sources.json"))
	for model: String in sources.weapon_meshes:
		var original := load("res://assets/models/weapons/%s.obj" % model) as Mesh
		assert(ResourceSaver.save(_compile(original, model, false), BASE + "weapons/%s.res" % model) == OK)
	avatar.free()
	print("EQUIPMENT_COMPILE_PASS armors=28 weapons=%d textures=%d" % [sources.weapon_meshes.size(), texture_map.size()])
	quit()

func _compile(original: Mesh, mesh_name: String, armor: bool, instance: MeshInstance3D = null) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.resource_name = original.resource_name
	# Keep original bounds for weapon scale, culling and reload alignment.
	result.custom_aabb = original.get_aabb()
	for surface in original.get_surface_count():
		var source: Dictionary = meshes[mesh_name][surface]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		for key: String in source:
			var index := int(key)
			if index in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
				var values := PackedVector3Array()
				for v: Array in source[key]: values.append(Vector3(v[0], v[1], v[2]))
				arrays[index] = values
			elif index in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				var values := PackedVector2Array()
				for v: Array in source[key]: values.append(Vector2(v[0], v[1]))
				arrays[index] = values
			elif index == Mesh.ARRAY_COLOR:
				var values := PackedColorArray()
				for v: Array in source[key]: values.append(Color(v[0], v[1], v[2], v[3]))
				arrays[index] = values
			elif index in [Mesh.ARRAY_INDEX, Mesh.ARRAY_BONES]:
				arrays[index] = PackedInt32Array(source[key])
			elif index == Mesh.ARRAY_WEIGHTS:
				arrays[index] = PackedFloat32Array(source[key])
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := instance.get_active_material(surface) if instance else original.surface_get_material(surface)
		result.surface_set_material(surface, _material(material, armor))
	return result

func _material(source: Material, armor: bool) -> Material:
	if source == null:
		return null
	if source is BaseMaterial3D:
		var texture: Texture2D = source.albedo_texture
		if texture != null and texture_map.has(texture.resource_path):
			texture = load(texture_map[texture.resource_path]) as Texture2D
		if armor and source.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			var painted := ShaderMaterial.new()
			painted.resource_name = source.resource_name
			painted.shader = load("res://assets/equipment_refined/painted_equipment.gdshader")
			painted.set_shader_parameter("albedo_texture", texture)
			painted.set_shader_parameter("albedo_tint", source.albedo_color)
			return painted
		var material := source.duplicate() as BaseMaterial3D
		material.albedo_texture = texture
		material.roughness = maxf(material.roughness, 0.72)
		material.metallic = minf(material.metallic, 0.12)
		material.metallic_specular = minf(material.metallic_specular, 0.2)
		return material
	var material := source.duplicate() as ShaderMaterial
	if material != null:
		for parameter: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(parameter.name)
			if value is Texture2D and texture_map.has(value.resource_path):
				material.set_shader_parameter(parameter.name, load(texture_map[value.resource_path]))
		return material
	return source
