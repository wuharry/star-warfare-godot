extends SceneTree

const OUTPUT := "res://assets/armors/viper/viper.scn"
const INPUT := "res://test_output/armor_rework/viper_meshes.json"
const ORIGINAL := "res://assets/models/player/animated/player.gltf"


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var original := (load(ORIGINAL) as PackedScene).instantiate()
	root.add_child(original)
	var skeleton := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skin := Skin.new()
	var bone_indices := {}
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		bone_indices[bone_name] = bone
		skin.add_named_bind(bone_name, skeleton.get_bone_global_rest(bone).affine_inverse())
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	var materials := _materials()
	var container := Node3D.new()
	container.name = "ViperRework"
	var triangle_count := 0
	for part: Dictionary in source:
		var mesh := ArrayMesh.new()
		for material_id in materials.size():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var uvs := PackedVector2Array()
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			for triangle in part.materials.size():
				if int(part.materials[triangle]) != material_id:
					continue
				triangle_count += 1
				for corner in [2, 1, 0]:
					var index: int = triangle * 3 + corner
					vertices.append(Vector3(part.positions[index * 3], part.positions[index * 3 + 1], part.positions[index * 3 + 2]))
					normals.append(Vector3(part.normals[index * 3], part.normals[index * 3 + 1], part.normals[index * 3 + 2]))
					uvs.append(Vector2(part.uv[index * 2], 1.0 - float(part.uv[index * 2 + 1])))
					for influence in range(4):
						if influence < part.bones[index].size():
							var bone_name: String = part.bones[index][influence]
							if not bone_indices.has(bone_name):
								push_error("Missing armor bone: " + bone_name)
								quit(1)
								return
							bones.append(bone_indices[bone_name])
							weights.append(part.weights[index][influence])
						else:
							bones.append(0)
							weights.append(0.0)
			if vertices.is_empty():
				continue
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[material_id])
		var instance := MeshInstance3D.new()
		instance.name = str(part.name).get_slice(".", 0)
		instance.mesh = mesh
		instance.skin = skin
		instance.skeleton = NodePath("..")
		instance.extra_cull_margin = 1.0
		instance.set_meta("armor_rework", "viper_original_refined")
		container.add_child(instance)
		instance.owner = container
	var packed := PackedScene.new()
	var error := packed.pack(container)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	print("VIPER_COMPILE_%s parts=%d triangles=%d bones=%d" % ["PASS" if error == OK else "FAIL", container.get_child_count(), triangle_count, skin.get_bind_count()])
	container.free()
	original.free()
	quit(0 if error == OK else 1)


func _materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for key in ["head", "body", "shoulder", "arms", "legs"]:
		var material := ShaderMaterial.new()
		material.resource_name = "ViperRefined_" + key
		material.shader = load("res://assets/armors/viper/painted_armor.gdshader")
		material.set_shader_parameter("albedo_texture", load("res://assets/armors/viper/textures/%s.png" % key))
		result.append(material)
	return result
