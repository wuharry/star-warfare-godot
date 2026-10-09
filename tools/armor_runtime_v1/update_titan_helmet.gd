extends SceneTree
## Update only Titan's helmet; retain the actual current body/limb resources.

const ASSET := "res://assets/armors/titan_v1/"
const WORK := "res://docs/art/titan_runtime_v1/"
const HEAD := "ArmorHead_05"
const NeckContract = preload("res://tools/armor_runtime_v1/neck_contract.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var target_path := WORK + "build/target.json"
	var preview_output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-target="):
			target_path=argument.trim_prefix("--preview-target=")
		if argument.begins_with("--preview-output="):
			preview_output=argument.trim_prefix("--preview-output=")
	if not preview_output.is_empty():
		assert(preview_output.begins_with(WORK+"review/") and preview_output.ends_with(".scn"))
		assert(target_path.begins_with(WORK+"review/") and target_path.ends_with(".json") and FileAccess.file_exists(target_path))
	else:
		assert(target_path==WORK+"build/target.json", "An alternate target requires a separate review output")
	var target: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(target_path))
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(original)
	var current := (load(ASSET + "titan.scn") as PackedScene).instantiate()
	var skeleton := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var source := original.find_child(HEAD, true, false) as MeshInstance3D
	var head := current.find_child(HEAD, true, false) as MeshInstance3D
	var arrays := source.mesh.surface_get_arrays(0).duplicate(true)
	var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
	var row: Dictionary = target.parts[HEAD].surfaces[0]
	var original_count: int = arrays[Mesh.ARRAY_VERTEX].size()
	for added: Dictionary in row.get("added_vertices", []):
		var a: int = added.parents[0]
		var b: int = added.parents[1]
		assert(added.index == arrays[Mesh.ARRAY_VERTEX].size())
		arrays[Mesh.ARRAY_VERTEX].append((arrays[Mesh.ARRAY_VERTEX][a] + arrays[Mesh.ARRAY_VERTEX][b]) * .5)
		source_normals.append((source_normals[a] + source_normals[b]).normalized())
		arrays[Mesh.ARRAY_NORMAL].append(source_normals[-1])
		for j: int in 4:
			arrays[Mesh.ARRAY_BONES].append(int(row.bone_indices[added.index][j]))
			arrays[Mesh.ARRAY_WEIGHTS].append(float(row.weights[added.index][j]))
			arrays[Mesh.ARRAY_TANGENT].append(arrays[Mesh.ARRAY_TANGENT][a * 4 + j])
		arrays[Mesh.ARRAY_TEX_UV].append(Vector2.ZERO)
	if row.has("indices"):
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(row.indices)
	assert(row.positions.size() == arrays[Mesh.ARRAY_VERTEX].size())
	for i: int in arrays[Mesh.ARRAY_VERTEX].size():
		arrays[Mesh.ARRAY_TEX_UV][i] = Vector2(row.uv[i][0], row.uv[i][1])
		var rest := Vector3.ZERO
		var basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		for j: int in 4:
			var bind: int = arrays[Mesh.ARRAY_BONES][i * 4 + j]
			var weight: float = arrays[Mesh.ARRAY_WEIGHTS][i * 4 + j]
			var bone := skeleton.find_bone(source.skin.get_bind_name(bind))
			var transform := skeleton.get_bone_global_rest(bone) * source.skin.get_bind_pose(bind)
			rest += (transform * arrays[Mesh.ARRAY_VERTEX][i]) * weight
			basis.x += transform.basis.x * weight
			basis.y += transform.basis.y * weight
			basis.z += transform.basis.z * weight
		var position := Vector3(row.positions[i][0], row.positions[i][1], row.positions[i][2])
		arrays[Mesh.ARRAY_VERTEX][i] += basis.inverse() * (position - rest)
	var sums := PackedVector3Array()
	sums.resize(arrays[Mesh.ARRAY_VERTEX].size())
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for tri: int in indices.size() / 3:
		var i := indices[tri * 3]
		var j := indices[tri * 3 + 1]
		var k := indices[tri * 3 + 2]
		var normal: Vector3 = (arrays[Mesh.ARRAY_VERTEX][j] - arrays[Mesh.ARRAY_VERTEX][i]).cross(arrays[Mesh.ARRAY_VERTEX][k] - arrays[Mesh.ARRAY_VERTEX][i])
		if normal.dot(source_normals[i] + source_normals[j] + source_normals[k]) < 0:
			normal = -normal
		for index: int in [i, j, k]:
			sums[index] += normal
	for i: int in sums.size():
		assert(sums[i].length_squared() > 0.000000001)
		arrays[Mesh.ARRAY_NORMAL][i] = sums[i].normalized()
	var channel_errors: Array[String] = NeckContract.validate_channels(arrays, source.skin, "Titan-before-upload")
	if not channel_errors.is_empty():
		for message: String in channel_errors: push_error(message)
		current.free()
		original.free()
		quit(1)
		return
	var rebuilt := ArrayMesh.new()
	rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var generated := RenderingServer.mesh_get_surface(rebuilt.get_rid(), 0)
	var surface: Dictionary = (head.mesh.get("_surfaces") as Array)[0].duplicate(true)
	if original_count != arrays[Mesh.ARRAY_VERTEX].size():
		# Limited edge subdivision needs a new buffer; all old UV IDs and binds
		# remain independently checked against the original prefix and target.
		surface = generated.duplicate(true)
	assert(surface.format == generated.format)
	var bytes: PackedByteArray = surface.vertex_data.duplicate()
	var updated: PackedByteArray = generated.vertex_data
	var count: int = surface.vertex_count
	var stride := RenderingServer.mesh_surface_get_format_vertex_stride(surface.format, count)
	var normal_offset := RenderingServer.mesh_surface_get_format_offset(surface.format, count, Mesh.ARRAY_NORMAL)
	var tangent_offset := RenderingServer.mesh_surface_get_format_offset(surface.format, count, Mesh.ARRAY_TANGENT)
	assert(stride == 12 and tangent_offset - normal_offset == 4)
	for byte: int in count * stride:
		bytes[byte] = updated[byte]
	for i: int in count:
		for byte: int in 4:
			bytes[normal_offset + i * 8 + byte] = updated[normal_offset + i * 8 + byte]
	surface.vertex_data = bytes
	surface.aabb = generated.aabb
	surface.bone_aabbs = generated.bone_aabbs
	# Refresh the actual imported texture after generation without changing UVs.
	var material := head.get_active_material(0).duplicate() as BaseMaterial3D
	material.albedo_texture = load(ASSET + "titan_head_diffuse.png") as Texture2D
	assert(material.albedo_texture != null)
	surface.material = material
	var mesh := ArrayMesh.new()
	mesh.set("_surfaces", [surface])
	head.mesh = mesh
	# Check the REAL candidate and material before either production write.
	# Face roundness/count budgets cannot prove mixed-equipment neck safety.
	var neck_report: Dictionary = NeckContract.verify(source, head)
	neck_report.candidate_target = target_path
	neck_report.candidate_target_sha256 = FileAccess.get_sha256(target_path)
	neck_report.canonical_head_png_sha256 = FileAccess.get_sha256(ASSET + "titan_head_diffuse.png")
	neck_report.output_scene = ASSET + "titan.scn" if preview_output.is_empty() else preview_output
	neck_report.stage = "before_PackedScene_pack_ResourceSaver_save_and_GLB_export"
	var neck_file := FileAccess.open(WORK + "review/neck_contract_gate.json", FileAccess.WRITE)
	if neck_file != null: neck_file.store_string(JSON.stringify(neck_report, "\t") + "\n")
	if not neck_report.errors.is_empty():
		for message: String in neck_report.errors: push_error(message)
		current.free()
		original.free()
		print("TITAN_NECK_CONTRACT_FAIL production SCN and GLB not written")
		quit(1)
		return
	var packed := PackedScene.new()
	assert(packed.pack(current) == OK)
	assert(ResourceSaver.save(packed, ASSET + "titan.scn" if preview_output.is_empty() else preview_output) == OK)
	if not preview_output.is_empty():
		current.free()
		original.free()
		print("TITAN_HELMET_PREVIEW_PASS separate scene / active SCN and GLB untouched")
		quit()
		return
	# Export the same actual runtime meshes with the original skeleton.
	for part: MeshInstance3D in current.get_children():
		var original_part := original.find_child(str(part.name), true, false) as MeshInstance3D
		original_part.mesh = part.mesh
		original_part.skin = part.skin
		original_part.transform = part.transform
		original_part.visible = true
	for part: MeshInstance3D in original.find_children("*", "MeshInstance3D", true, false):
		if not target.parts.has(str(part.name)):
			part.free()
	for animation_player: AnimationPlayer in original.find_children("*", "AnimationPlayer", true, false):
		animation_player.free()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(original, state) == OK)
	assert(document.write_to_filesystem(state, ASSET + "titan.glb") == OK)
	current.free()
	original.free()
	print("TITAN_HELMET_UPDATE_PASS head=%d triangles; three UV charts / original binds / other parts retained" % (indices.size() / 3))
	quit()
