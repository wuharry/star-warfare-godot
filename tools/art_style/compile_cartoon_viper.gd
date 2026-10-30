extends SceneTree

const ASSETS := "res://assets/armors/cartoon_viper/"
const INPUT := "res://test_output/cartoon_viper/meshes.json"

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	if not source is Array or source.size() != 5:
		push_error("Build the five Blender parts before compiling")
		quit(1)
		return
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(original)
	var skeleton := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skin := Skin.new()
	var bone_indices := {}
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		bone_indices[bone_name] = bone
		skin.add_named_bind(bone_name, skeleton.get_bone_global_rest(bone).affine_inverse())
	var container := Node3D.new()
	container.name = "CartoonViper"
	var triangle_count := 0
	for part: Dictionary in source:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for triangle in part.positions.size() / 9:
			triangle_count += 1
			for corner in [2, 1, 0]:
				var index: int = triangle * 3 + corner
				vertices.append(Vector3(part.positions[index * 3], part.positions[index * 3 + 1], part.positions[index * 3 + 2]))
				normals.append(Vector3(part.normals[index * 3], part.normals[index * 3 + 1], part.normals[index * 3 + 2]))
				uvs.append(Vector2(part.uv[index * 2], 1.0 - float(part.uv[index * 2 + 1])))
				for influence in 4:
					if influence < part.bones[index].size():
						var name: String = part.bones[index][influence]
						if not bone_indices.has(name):
							push_error("Missing skin bone: " + name)
							container.free()
							original.free()
							quit(1)
							return
						bones.append(bone_indices[name])
						weights.append(part.weights[index][influence])
					else:
						bones.append(0)
						weights.append(0.0)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		if part.name == "ArmorBag_00":
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := ShaderMaterial.new()
		material.shader = load(ASSETS + "paint.gdshader")
		material.set_shader_parameter("albedo_texture", load(ASSETS + str(part.texture)))
		var outline := ShaderMaterial.new()
		outline.shader = load("res://assets/shaders/ink_outline.gdshader")
		outline.set_shader_parameter("width_pixels", 1.5)
		material.next_pass = outline
		mesh.surface_set_material(0, material)
		if part.name == "ArmorBag_00":
			var bag_error := ResourceSaver.save(mesh, ASSETS + "backpack.res")
			if bag_error != OK:
				container.free()
				original.free()
				quit(1)
				return
			continue
		var instance := MeshInstance3D.new()
		instance.name = str(part.name)
		instance.mesh = mesh
		instance.skin = skin
		instance.skeleton = NodePath("..")
		instance.extra_cull_margin = 1.0
		instance.set_meta("armor_rework", "cartoon_viper_v1")
		container.add_child(instance)
		instance.owner = container
	var packed := PackedScene.new()
	var error := packed.pack(container)
	if error == OK:
		error = ResourceSaver.save(packed, ASSETS + "viper.scn")
	container.free()
	original.free()
	print("CARTOON_VIPER_COMPILE_%s triangles=%d" % ["PASS" if error == OK else "FAIL", triangle_count])
	quit(0 if error == OK else 1)
