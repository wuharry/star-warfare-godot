extends SceneTree

# Bridge the generated skinned mesh to Blender without re-importing its rig.
# Run --export, refine_assault.py in Blender, then run --import.
const SCENE_PATH := "res://assets/callOfMini/gameplay/AssaultArmor.scn"
const WORK_DIR := "res://test_output/assault_refinement"
const REFERENCE_PATH := "res://assets/models/player/animated/player.gltf"
const ASSAULT_TINT := Color(1.0, 0.62, 0.82, 1.0)

const HAND_TEX_PATH := "res://assets/callOfMini/enhanced/Assault Armor/hand_assault.png"
const FOOT_TEX_PATH := "res://assets/callOfMini/enhanced/Assault Armor/foot_assault.png"
const BODY_TEX_PATH := "res://assets/callOfMini/enhanced/Assault Armor/body_assault.png"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	var source_path := SCENE_PATH
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			source_path = argument.trim_prefix("--source=")
	var scene := (load(source_path) as PackedScene).instantiate()
	var baseline_stats := _mesh_stats(scene)
	if OS.get_cmdline_user_args().has("--export"):
		var allow_reexport := OS.get_cmdline_user_args().has("--force")
		assert(allow_reexport or not scene.has_meta("assault_refinement"), "Regenerate the baseline with retarget_armors.gd before refining again")
		var surfaces: Array = []
		for instance: MeshInstance3D in scene.get_children():
			for surface in instance.mesh.get_surface_count():
				var arrays := instance.mesh.surface_get_arrays(surface)
				var vertices: Array = []
				var uvs: Array = []
				for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					vertices.append([point.x, point.y, point.z])
				for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
					uvs.append([uv.x, uv.y])
				surfaces.append({"part": instance.name, "surface": surface, "vertices": vertices, "uvs": uvs,
					"indices": Array(arrays[Mesh.ARRAY_INDEX]), "bones": Array(arrays[Mesh.ARRAY_BONES]),
					"weights": Array(arrays[Mesh.ARRAY_WEIGHTS])})
		var file := FileAccess.open(WORK_DIR + "/mesh_input.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"source_sha256": FileAccess.get_sha256(source_path), "surfaces": surfaces}))
		print("ASSAULT_EXPORT_PASS surfaces=", surfaces.size())
	else:
		assert(OS.get_cmdline_user_args().has("--import"))
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK_DIR + "/mesh_output.json"))
		assert(data.source_sha256 == FileAccess.get_sha256(source_path), "Source changed since export")
		var reference := (load(REFERENCE_PATH) as PackedScene).instantiate()
		for instance: MeshInstance3D in scene.get_children():
			# Keep the signature skull helmet byte-for-byte unchanged.
			if String(instance.name).begins_with("ArmorHead"):
				continue
			if String(instance.name).begins_with("ArmorHand"):
				instance.mesh = _build_refined_limb_mesh(data, String(instance.name), HAND_TEX_PATH)
				continue
			if String(instance.name).begins_with("ArmorFoot"):
				instance.mesh = _build_refined_limb_mesh(data, String(instance.name), FOOT_TEX_PATH)
				continue
			# ArmorBody: combine refined Viper torso/thigh with remodeled Assault shoulder plates
			var mesh := _reference_mesh(reference, instance)
			if mesh.get_surface_count() > 0:
				var body_mat := mesh.surface_get_material(0).duplicate() as BaseMaterial3D
				body_mat.albedo_texture = load(BODY_TEX_PATH)
				body_mat.albedo_color = Color.WHITE
				body_mat.vertex_color_use_as_albedo = true
				mesh.surface_set_material(0, body_mat)
			if mesh.get_surface_count() > 1:
				var jian_mat := mesh.surface_get_material(1).duplicate() as BaseMaterial3D
				jian_mat.albedo_texture = load(BODY_TEX_PATH)
				jian_mat.albedo_color = Color.WHITE
				jian_mat.vertex_color_use_as_albedo = true
				mesh.surface_set_material(1, jian_mat)
			for entry: Dictionary in data.surfaces:
				if entry.part != String(instance.name):
					continue
				var arrays: Array = []
				arrays.resize(Mesh.ARRAY_MAX)
				var vertices := PackedVector3Array()
				var normals := PackedVector3Array()
				var uvs := PackedVector2Array()
				var colors := PackedColorArray()
				for point: Array in entry.vertices:
					vertices.append(Vector3(point[0], point[1], point[2]))
				for normal: Array in entry.normals:
					normals.append(Vector3(normal[0], normal[1], normal[2]))
				for uv: Array in entry.uvs:
					uvs.append(Vector2(uv[0], uv[1]))
				for color: Array in entry.colors:
					colors.append(Color(color[0], color[1], color[2], 1.0))
				arrays[Mesh.ARRAY_VERTEX] = vertices
				arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TEX_UV] = uvs
				arrays[Mesh.ARRAY_COLOR] = colors
				arrays[Mesh.ARRAY_BONES] = PackedInt32Array(entry.bones)
				arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(entry.weights)
				var shoulder_indices := PackedInt32Array()
				for triangle in range(0, entry.indices.size(), 3):
					var center := Vector3.ZERO
					for corner in 3:
						center += vertices[int(entry.indices[triangle + corner])] / 3.0
					if absf(center.x) > 0.33 and center.y > 1.10:
						for corner in 3:
							shoulder_indices.append(int(entry.indices[triangle + corner]))
				if shoulder_indices.is_empty():
					continue
				arrays[Mesh.ARRAY_INDEX] = shoulder_indices
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays))
				var material := instance.mesh.surface_get_material(int(entry.surface)).duplicate() as BaseMaterial3D
				material.vertex_color_use_as_albedo = true
				mesh.surface_set_material(mesh.get_surface_count() - 1, material)
			instance.mesh = mesh
		reference.free()
		scene.set_meta("assault_refinement", "Rounded limbs and shoulder plates with cohesive dark metal palette v3")
		var packed := PackedScene.new()
		assert(packed.pack(scene) == OK)
		assert(ResourceSaver.save(packed, SCENE_PATH, ResourceSaver.FLAG_COMPRESS) == OK)
		var report := FileAccess.open("res://assets/callOfMini/gameplay/assault_refinement_report.json", FileAccess.WRITE)
		report.store_string(JSON.stringify({"prototype": "Assault Armor only", "version": 3,
			"reference": REFERENCE_PATH, "source_sha256": data.source_sha256,
			"head": "Original Assault helmet preserved", "body": "Cohesive dark metal torso with remodeled Assault shoulder plates",
			"arms_legs": "Beveled rounded limbs with dedicated Assault dark metal & orange accent textures",
			"baseline": baseline_stats, "refined": _mesh_stats(scene)}, "\t") + "\n")
		print("ASSAULT_IMPORT_PASS")
	scene.free()
	quit()

func _mesh_stats(scene: Node) -> Array:
	var result: Array = []
	for instance: MeshInstance3D in scene.get_children():
		var triangles := 0
		for surface in instance.mesh.get_surface_count():
			triangles += instance.mesh.surface_get_array_index_len(surface) / 3
		result.append({"part": instance.name, "triangles": triangles})
	return result

func _reference_mesh(reference: Node3D, destination: MeshInstance3D) -> ArrayMesh:
	var source := reference.find_child(String(destination.name).replace("_21", "_00"), true, false) as MeshInstance3D
	var skeleton := reference.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mesh := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			for influence in 4:
				var slot := vertex * 4 + influence
				var bind := bones[slot]
				var bone := skeleton.find_bone(source.skin.get_bind_name(bind))
				var transform := skeleton.get_bone_global_rest(bone) * source.skin.get_bind_pose(bind)
				point += (transform * vertices[vertex]) * weights[slot]
				normal += (transform.basis.inverse().transposed() * normals[vertex]) * weights[slot]
				bones[slot] = bone
				assert(destination.skin.get_bind_name(bone) == skeleton.get_bone_name(bone))
			vertices[vertex] = point
			normals[vertex] = normal.normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_TANGENT] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := source.get_active_material(surface).duplicate() as BaseMaterial3D
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = ASSAULT_TINT
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

func _compact(arrays: Array) -> Array:
	# Unreferenced source legs must not affect culling, bounds or thumbnails.
	var ids: Array[int] = []
	var remap := {}
	var indices := PackedInt32Array()
	for source_index: int in arrays[Mesh.ARRAY_INDEX]:
		if not remap.has(source_index):
			remap[source_index] = ids.size()
			ids.append(source_index)
		indices.append(remap[source_index])
	var output: Array = []
	output.resize(Mesh.ARRAY_MAX)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		output[slot] = arrays[slot].slice(0, 0)
		var width := 4 if slot in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS] else 1
		for source_index in ids:
			for component in width:
				output[slot].append(arrays[slot][source_index * width + component])
	output[Mesh.ARRAY_INDEX] = indices
	return output

func _build_refined_limb_mesh(data: Dictionary, part_name: String, texture_path: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for entry: Dictionary in data.surfaces:
		if entry.part != part_name:
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		for point: Array in entry.vertices:
			vertices.append(Vector3(point[0], point[1], point[2]))
		for normal: Array in entry.normals:
			normals.append(Vector3(normal[0], normal[1], normal[2]))
		for uv: Array in entry.uvs:
			uvs.append(Vector2(uv[0], uv[1]))
		for color: Array in entry.colors:
			colors.append(Color(color[0], color[1], color[2], 1.0))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array(entry.bones)
		arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(entry.weights)
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(entry.indices)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays))
		var material := StandardMaterial3D.new()
		material.resource_name = part_name + "_refined"
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = load(texture_path)
		material.albedo_color = Color.WHITE
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

