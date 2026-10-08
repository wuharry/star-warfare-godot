extends SceneTree

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
			assert(row.uv.size() == a[Mesh.ARRAY_TEX_UV].size())
			for uv_index: int in row.uv.size():
				a[Mesh.ARRAY_TEX_UV][uv_index] = Vector2(row.uv[uv_index][0],row.uv[uv_index][1])
			# Texture-only Atom/Pegasus keep original normal/tangent buffers too.
			var regenerate_head := name_key == "ArmorHead_%02d" % int(config.runtime_id) and (geometry_changed or slug not in ["atom", "pegasus"])
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
			if regenerate_head:
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
					for byte: int in 4:source_bytes[normal_offset+i*8+byte]=edited_bytes[normal_offset+i*8+byte]
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
	var packed := PackedScene.new()
	assert(packed.pack(container) == OK)
	assert(ResourceSaver.save(packed,OUT+slug+".scn") == OK)
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
	assert(triangles==config.original_triangles)
	print("%s_COMPILE_PASS triangles=%d parts=4 surfaces=%d bones=28" % [slug.to_upper(),triangles,int(config.original_surface_count)])
	quit()
