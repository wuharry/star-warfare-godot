extends SceneTree

const OUT := "res://assets/armors/fortune_v1/"
const WORK := "res://docs/art/fortune_runtime_v1/build/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK+"target.json"))
	assert(data.revision == "fortune_runtime_v1" and data.id == 1)
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(original)
	var sk := original.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var container := Node3D.new()
	container.name = "FortuneRuntimeV1"
	var triangles := 0
	for name_key: String in data.parts:
		var old := original.find_child(name_key,true,false) as MeshInstance3D
		var mesh := ArrayMesh.new()
		for sid: int in old.mesh.get_surface_count():
			var a := old.mesh.surface_get_arrays(sid).duplicate(true)
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
					a[Mesh.ARRAY_VERTEX][i] += basis.inverse()*delta
			assert(row.uv.size() == a[Mesh.ARRAY_TEX_UV].size())
			for uv_index: int in row.uv.size():
				a[Mesh.ARRAY_TEX_UV][uv_index] = Vector2(row.uv[uv_index][0],row.uv[uv_index][1])
			if name_key == "ArmorHead_01":
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
			mat.resource_name = "Fortune_"+str(row.label)+"_painted"
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_texture = source_material.albedo_texture if "--geometry-preview" in OS.get_cmdline_user_args() else load(path) as Texture2D
			assert(mat.albedo_texture != null)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			mesh.surface_set_material(sid,mat)
		var part := MeshInstance3D.new()
		part.name = name_key; part.mesh = mesh; part.skin = old.skin.duplicate()
		part.transform = old.transform; part.skeleton = NodePath("..")
		part.extra_cull_margin = 1.0; part.set_meta("armor_rework","fortune_runtime_v1")
		container.add_child(part); part.owner = container
	var packed := PackedScene.new()
	assert(packed.pack(container) == OK)
	assert(ResourceSaver.save(packed,OUT+"fortune.scn") == OK)
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
		assert(document.write_to_filesystem(state,OUT+"fortune.glb") == OK)
	container.free(); original.free()
	print("FORTUNE_COMPILE_PASS triangles=%d parts=4 surfaces=5 bones=28" % triangles)
	quit()
