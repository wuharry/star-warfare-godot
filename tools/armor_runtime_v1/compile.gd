extends SceneTree

const NeckContract = preload("res://tools/armor_runtime_v1/neck_contract.gd")

var OUT := ""
var WORK := ""
var config: Dictionary
var slug := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--armor="):slug=argument.trim_prefix("--armor=")
	assert(slug in ["hydra","strike","titan","atom","pegasus"])
	config=JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/"+slug+"_runtime_v1/runtime_config.json"))
	if config.has("head_refinement"):
		push_error("Titan visor subdivision uses update_titan_helmet.gd; the first-integration compiler cannot replace its expanded head.")
		quit(1)
		return
	OUT="res://"+str(config.asset)+"/";WORK="res://"+str(config.work)+"/build/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK+"target.json"))
	assert(data.revision == slug+"_runtime_v1" and data.id == config.runtime_id)
	assert(data.parts.size() == config.parts.size(), "Target must contain exactly the configured armor parts before delivery")
	for part_name: String in config.parts:
		assert(data.parts.has(part_name), "Target is missing configured armor part " + part_name)
	var bounded := str(config.get("geometry_mode", "texture_only")) == "original_source_bounded_refinement"
	var movable: Array = config.get("geometry_parts", []) if bounded else []
	if bounded:
		assert(slug in ["atom", "pegasus"] and config.get("preserve_all_geometry") == false and not movable.is_empty())
		assert(data.geometry_mode == config.geometry_mode and data.geometry_parts == movable)
		for part_name: String in movable:assert(config.parts.has(part_name))
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(original)
	var sk := original.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var container := Node3D.new()
	container.name = str(config.name)+"RuntimeV1"
	var triangles := 0
	for name_key: String in data.parts:
		var old := original.find_child(name_key,true,false) as MeshInstance3D
		var mesh := ArrayMesh.new()
		var preserved_surfaces: Array=[]
		for sid: int in old.mesh.get_surface_count():
			var a := old.mesh.surface_get_arrays(sid).duplicate(true)
			var geometry_changed := false
			var source_normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL].duplicate()
			var row: Dictionary = data.parts[name_key].surfaces[sid]
			assert(row.positions.size() == a[Mesh.ARRAY_VERTEX].size())
			for i: int in a[Mesh.ARRAY_VERTEX].size():
				var rest := Vector3.ZERO
				var basis := Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
				for j: int in 4:
					var bind: int = a[Mesh.ARRAY_BONES][i*4+j]
					var w: float = a[Mesh.ARRAY_WEIGHTS][i*4+j]
					var bone := sk.find_bone(old.skin.get_bind_name(bind))
					var t := sk.get_bone_global_rest(bone)*old.skin.get_bind_pose(bind)
					rest += (t*a[Mesh.ARRAY_VERTEX][i])*w
					basis.x += t.basis.x*w; basis.y += t.basis.y*w; basis.z += t.basis.z*w
				var target := Vector3(row.positions[i][0],row.positions[i][1],row.positions[i][2])
				var delta := target-rest
				# Preserve exact legacy bind-space coordinates on untouched parts.
				if delta.length() > .000001:
					geometry_changed = true
					a[Mesh.ARRAY_VERTEX][i] += basis.inverse()*delta
			if bounded:
				assert(geometry_changed == bool(row.geometry_changed))
				assert(not geometry_changed or name_key in movable)
				if geometry_changed:
					assert(row.raw_positions.size() == a[Mesh.ARRAY_VERTEX].size() and row.normals.size() == row.raw_positions.size() and row.tangents.size() == row.raw_positions.size())
					for i: int in row.raw_positions.size():
						var expected_raw := Vector3(row.raw_positions[i][0],row.raw_positions[i][1],row.raw_positions[i][2])
						assert(a[Mesh.ARRAY_VERTEX][i].distance_to(expected_raw) <= .000002)
						var n := Vector3(row.normals[i][0],row.normals[i][1],row.normals[i][2])
						var t := Vector3(row.tangents[i][0],row.tangents[i][1],row.tangents[i][2])
						assert(n.is_finite() and t.is_finite() and absf(n.length()-1) < .000001 and absf(t.length()-1) < .000001 and absf(n.dot(t)) < .000001)
						assert(absf(float(row.tangents[i][3])) == 1)
						a[Mesh.ARRAY_NORMAL][i] = n
						for component: int in 4:a[Mesh.ARRAY_TANGENT][i*4+component] = row.tangents[i][component]
			elif config.get("preserve_all_geometry", false):
				assert(not geometry_changed)
			assert(row.uv.size() == a[Mesh.ARRAY_TEX_UV].size())
			for uv_index: int in row.uv.size():
				if slug in ["atom", "pegasus"]:
					assert(a[Mesh.ARRAY_TEX_UV][uv_index] == Vector2(row.uv[uv_index][0],row.uv[uv_index][1]))
				a[Mesh.ARRAY_TEX_UV][uv_index] = Vector2(row.uv[uv_index][0],row.uv[uv_index][1])
			# Texture-only Atom/Pegasus keep original normal/tangent buffers too.
			var regenerate_head := not bounded and name_key == "ArmorHead_%02d" % int(config.runtime_id) and (geometry_changed or slug not in ["atom", "pegasus"])
			if regenerate_head:
				var sums := PackedVector3Array()
				sums.resize(a[Mesh.ARRAY_VERTEX].size())
				var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for tri: int in indices.size()/3:
					var i: int = indices[tri*3]; var j: int = indices[tri*3+1]; var k: int = indices[tri*3+2]
					var n: Vector3 = (a[Mesh.ARRAY_VERTEX][j]-a[Mesh.ARRAY_VERTEX][i]).cross(a[Mesh.ARRAY_VERTEX][k]-a[Mesh.ARRAY_VERTEX][i])
					if n.dot(source_normals[i]+source_normals[j]+source_normals[k]) < 0:n = -n
					for index: int in [i,j,k]:sums[index] += n
				for i: int in sums.size():
					if sums[i].length_squared()>.000000001:a[Mesh.ARRAY_NORMAL][i] = sums[i].normalized()
			var channel_errors: Array[String] = NeckContract.validate_channels(a, old.skin, "shared-before-upload " + name_key)
			if not channel_errors.is_empty():
				for message: String in channel_errors: push_error(message)
				container.free()
				original.free()
				quit(1)
				return
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
			triangles += a[Mesh.ARRAY_INDEX].size()/3
			var path := OUT+str(row.label)+"_diffuse.png"
			var source_material := old.get_active_material(sid) as BaseMaterial3D
			var mat := StandardMaterial3D.new()
			mat.resource_name = str(config.name)+"_"+str(row.label)+"_painted"
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_texture = source_material.albedo_texture if "--geometry-preview" in OS.get_cmdline_user_args() else load(path) as Texture2D
			assert(mat.albedo_texture != null)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			mesh.surface_set_material(sid,mat)
			# Re-adding decoded arrays can requantize legacy normals/tangents.
			# Preserve the engine's actual serialized buffers, editing only the
			# allowed head position bytes and four-byte encoded normal entries.
			var raw_surface: Dictionary=(old.mesh.get("_surfaces") as Array)[sid].duplicate(true)
			if regenerate_head or (bounded and geometry_changed):
				var generated:=RenderingServer.mesh_get_surface(mesh.get_rid(),sid)
				assert(raw_surface.format==generated.format)
				var source_bytes: PackedByteArray=raw_surface.vertex_data.duplicate()
				var edited_bytes: PackedByteArray=generated.vertex_data
				var count: int=raw_surface.vertex_count
				var vertex_stride:=RenderingServer.mesh_surface_get_format_vertex_stride(raw_surface.format,count)
				var normal_offset:=RenderingServer.mesh_surface_get_format_offset(raw_surface.format,count,Mesh.ARRAY_NORMAL)
				var tangent_offset:=RenderingServer.mesh_surface_get_format_offset(raw_surface.format,count,Mesh.ARRAY_TANGENT)
				assert(vertex_stride==12 and tangent_offset-normal_offset==4)
				for byte: int in count*vertex_stride:source_bytes[byte]=edited_bytes[byte]
				for i: int in count:
					for byte: int in (8 if bounded else 4):source_bytes[normal_offset+i*8+byte]=edited_bytes[normal_offset+i*8+byte]
				raw_surface.vertex_data=source_bytes
				raw_surface.aabb=generated.aabb;raw_surface.bone_aabbs=generated.bone_aabbs
			raw_surface.material=mat
			preserved_surfaces.append(raw_surface)
		var delivered_mesh:=ArrayMesh.new()
		delivered_mesh.set("_surfaces",preserved_surfaces)
		assert(delivered_mesh.get_surface_count()==old.mesh.get_surface_count())
		var part := MeshInstance3D.new()
		part.name = name_key; part.mesh = delivered_mesh; part.skin = old.skin.duplicate()
		part.transform = old.transform; part.skeleton = NodePath("..")
		part.extra_cull_margin = 1.0; part.set_meta("armor_rework",slug+"_runtime_v1")
		container.add_child(part); part.owner = container
	assert(triangles==config.original_triangles, "Triangle budget must pass before any SCN/GLB write")
	# Every shared-pipeline output retains the actual original neck interface.
	# Color limits belong to the individual design; opaque cloth is mandatory.
	var gate: Dictionary = save_checked_candidate(original, container,
		"ArmorHead_%02d" % int(config.runtime_id), OUT + slug + ".scn",
		bool(config.get("neck_charcoal_required", false)))
	gate.candidate_target_sha256 = FileAccess.get_sha256(WORK + "target.json")
	gate.stage = "before_shared_PackedScene_pack_ResourceSaver_save_and_GLB_export"
	var gate_file := FileAccess.open("res://" + str(config.work) + "/review/neck_interface_gate.json", FileAccess.WRITE)
	if gate_file != null: gate_file.store_string(JSON.stringify(gate, "\t") + "\n")
	if not gate.errors.is_empty():
		for message: String in gate.errors: push_error(message)
		container.free()
		original.free()
		print("ARMOR_NECK_INTERFACE_FAIL production SCN and GLB not written")
		quit(1)
		return
	if "--geometry-preview" not in OS.get_cmdline_user_args():
		for part: MeshInstance3D in container.get_children():
			var old := original.find_child(str(part.name),true,false) as MeshInstance3D
			old.mesh = part.mesh; old.skin = part.skin; old.visible = true
		for part: MeshInstance3D in original.find_children("*","MeshInstance3D",true,false):
			if not data.parts.has(str(part.name)):part.free()
		for ap: AnimationPlayer in original.find_children("*","AnimationPlayer",true,false):ap.free()
		sk.reset_bone_poses(); sk.force_update_all_bone_transforms()
		var document := GLTFDocument.new(); var state := GLTFState.new()
		assert(document.append_from_scene(original,state) == OK)
		assert(document.write_to_filesystem(state,OUT+slug+".glb") == OK)
	container.free(); original.free()
	print("%s_COMPILE_PASS triangles=%d parts=4 surfaces=%d bones=28" % [slug.to_upper(),triangles,int(config.original_surface_count)])
	quit()


static func save_checked_candidate(original: Node3D, candidate: Node3D,
		head_name: String, scene_path: String, check_charcoal: bool = false) -> Dictionary:
	## The test exercises this exact production writer with corrupt interfaces.
	## No pack/save can run when geometry, sampling, Skin or opacity is invalid.
	var source := original.find_child(head_name, true, false) as MeshInstance3D
	var head := candidate.find_child(head_name, true, false) as MeshInstance3D
	var report: Dictionary = NeckContract.verify_interface(source, head, check_charcoal)
	report.output_scene = scene_path
	report.wrote_scene = false
	report.output_sha256_before = FileAccess.get_sha256(scene_path) if FileAccess.file_exists(scene_path) else "missing"
	if not report.errors.is_empty():
		report.output_sha256_after = FileAccess.get_sha256(scene_path) if FileAccess.file_exists(scene_path) else "missing"
		return report
	var packed := PackedScene.new()
	var result: Error = packed.pack(candidate)
	if result != OK:
		report.errors.append("NECK_DELIVERY: candidate packing failed: " + error_string(result))
	else:
		result = ResourceSaver.save(packed, scene_path)
		if result != OK: report.errors.append("NECK_DELIVERY: candidate saving failed: " + error_string(result))
		else: report.wrote_scene = true
	report.status = "PASS" if report.errors.is_empty() else "FAIL"
	report.output_sha256_after = FileAccess.get_sha256(scene_path) if FileAccess.file_exists(scene_path) else "missing"
	return report
