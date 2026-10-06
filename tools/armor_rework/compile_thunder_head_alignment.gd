extends SceneTree

const WORK := "res://docs/art/thunder_head_alignment_v1/"
const BASE := WORK + "before/resources/assets/armors/thunder/thunder.scn"
const BASE_SHA := "9f939667c6516ee3e2335cb973abeb7805d6865fd4df6b97821303bcd2661df5"
const INPUT := "res://test_output/armor_rework/thunder_aligned_head.json"
const OLD_INPUT := WORK + "before/resources/test_output/armor_rework/thunder_sw2_meshes.json"
const ALBEDO := "res://assets/armors/thunder/textures/helmet_aligned_albedo.png"
const TEXTURE := "res://assets/armors/thunder/textures/helmet_aligned_albedo.res"
const SHADER := "res://assets/armors/thunder/helmet_aligned.gdshader"
const IDS := {"Thunder_NavyShell": 6, "Thunder_DarkJoint": 10,
	"Thunder_PairedHelmet": 11, "Thunder_RespiratorSteel": 12,
	"Thunder_RespiratorEdge": 13, "Thunder_EngravedVisor": 14}

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	assert(FileAccess.get_sha256(BASE) == BASE_SHA, "Frozen head scene changed")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_INPUT))[0]
	for key in ["uv", "bones", "weights", "materials"]:
		assert(data[key] == old[key], "UV/topology/skin export changed: " + key)
	var image := Image.new()
	assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(ALBEDO)) == OK)
	var native := ImageTexture.create_from_image(image)
	assert(ResourceSaver.save(native, TEXTURE, ResourceSaver.FLAG_COMPRESS) == OK)
	var atlas := load(TEXTURE) as Texture2D
	var scene := (load(BASE) as PackedScene).instantiate()
	var head := scene.get_node("ArmorHead_06") as MeshInstance3D
	var mesh := ArrayMesh.new()
	var count := 0
	for surface in head.mesh.get_surface_count():
		var old_material := head.mesh.surface_get_material(surface) as ShaderMaterial
		var material := old_material.duplicate() as ShaderMaterial
		var id: int = IDS[material.resource_name]
		var arrays := head.mesh.surface_get_arrays(surface)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var tangents := PackedFloat32Array()
		var cursor := 0
		for triangle in data.materials.size():
			if int(data.materials[triangle]) != id:
				continue
			count += 1
			for corner in [2, 1, 0]:
				var index: int = triangle * 3 + corner
				var source := Vector3(old.positions[index * 3], old.positions[index * 3 + 1], old.positions[index * 3 + 2])
				assert(source.distance_to(arrays[Mesh.ARRAY_VERTEX][cursor]) < 0.000001, "Head corner order changed")
				assert(Vector2(data.uv[index * 2], 1.0 - float(data.uv[index * 2 + 1])).distance_to(arrays[Mesh.ARRAY_TEX_UV][cursor]) < 0.000001, "Head UV order changed")
				vertices.append(Vector3(data.positions[index * 3], data.positions[index * 3 + 1], data.positions[index * 3 + 2]))
				normals.append(Vector3(data.normals[index * 3], data.normals[index * 3 + 1], data.normals[index * 3 + 2]))
				for axis in 4:
					tangents.append(data.tangents[index * 4 + axis])
				cursor += 1
		assert(cursor == arrays[Mesh.ARRAY_VERTEX].size())
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		# UV, bones, weights and every other channel come from the actual SCN.
		mesh.add_surface_from_arrays(head.mesh.surface_get_primitive_type(surface), arrays)
		if id in [11, 14]:
			material.shader = load(SHADER)
			material.set_shader_parameter("albedo_texture", atlas)
			material.set_shader_parameter("shell_palette_strength", 1.0 if id == 11 else 0.0)
		elif id == 12:
			material.set_shader_parameter("paint_color", Color("355f88"))
		elif id == 13:
			material.set_shader_parameter("paint_color", Color("657b8e"))
		mesh.surface_set_material(surface, material)
	head.mesh = mesh
	head.set_meta("head_revision", "thunder_head_alignment_v1")
	head.set_meta("head_reference_sha256", "c5e647dfc186e63bf529be00fd6796489c3819a74c76a469c6d1ec1907e7b4e1")
	assert(count == 6284)
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	for path in ["res://assets/armors/thunder/thunder.scn", "res://assets/armors/thunder/thunder_sw2.scn"]:
		assert(ResourceSaver.save(packed, path) == OK)
	print("THUNDER_HEAD_ALIGNMENT_COMPILE_PASS head_triangles=%d body_from_frozen_scn=true" % count)
	scene.free()
	quit(0)
