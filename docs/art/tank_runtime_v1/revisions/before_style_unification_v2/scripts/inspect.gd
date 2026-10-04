extends SceneTree

const WORK := "res://docs/art/tank_runtime_v1/build/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK))
	var source := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(source)
	var sk := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var data := {"bones": [], "parts": {}, "original_scene":"res://assets/models/player/animated/player.gltf", "original_scene_sha256":FileAccess.get_sha256("res://assets/models/player/animated/player.gltf")}
	for b: int in sk.get_bone_count():
		var t := sk.get_bone_global_rest(b)
		data.bones.append({"name": sk.get_bone_name(b), "parent": sk.get_bone_parent(b), "matrix": [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]})
	for name_key: String in ["ArmorHead_02", "ArmorBody_02", "ArmorHand_02", "ArmorFoot_02"]:
		var part := source.find_child(name_key, true, false) as MeshInstance3D
		var surfaces := []
		for sid: int in part.mesh.get_surface_count():
			var a := part.mesh.surface_get_arrays(sid)
			var row := {"positions": [], "uv": [], "indices": [], "weights": [], "bone_names": [], "raw_positions": [], "normals":[], "bone_indices":[]}
			var mat := part.get_active_material(sid) as BaseMaterial3D
			row.texture = mat.albedo_texture.resource_path
			row.tint = [mat.albedo_color.r,mat.albedo_color.g,mat.albedo_color.b,mat.albedo_color.a]
			for index: int in a[Mesh.ARRAY_VERTEX].size():
				var point := Vector3.ZERO
				var names := []
				var ws := []
				for j: int in 4:
					var bind: int = a[Mesh.ARRAY_BONES][index*4+j]
					var weight: float = a[Mesh.ARRAY_WEIGHTS][index*4+j]
					var bone := sk.find_bone(part.skin.get_bind_name(bind))
					point += (sk.get_bone_global_rest(bone)*part.skin.get_bind_pose(bind)*a[Mesh.ARRAY_VERTEX][index])*weight
					names.append(sk.get_bone_name(bone)); ws.append(weight)
				row.positions.append([point.x,point.y,point.z])
				var raw: Vector3 = a[Mesh.ARRAY_VERTEX][index]
				row.raw_positions.append([raw.x,raw.y,raw.z])
				var normal: Vector3=a[Mesh.ARRAY_NORMAL][index]
				row.normals.append([normal.x,normal.y,normal.z])
				row.bone_indices.append([a[Mesh.ARRAY_BONES][index*4],a[Mesh.ARRAY_BONES][index*4+1],a[Mesh.ARRAY_BONES][index*4+2],a[Mesh.ARRAY_BONES][index*4+3]])
				var uv: Vector2 = a[Mesh.ARRAY_TEX_UV][index]
				row.uv.append([uv.x,uv.y])
				row.bone_names.append(names); row.weights.append(ws)
			if a[Mesh.ARRAY_INDEX] != null:
				for i: int in a[Mesh.ARRAY_INDEX]: row.indices.append(i)
			else:
				for i: int in a[Mesh.ARRAY_VERTEX].size(): row.indices.append(i)
			surfaces.append(row)
		var bind_records:=[]
		for bind: int in part.skin.get_bind_count():
			var t:=part.skin.get_bind_pose(bind)
			bind_records.append({"name":part.skin.get_bind_name(bind),"bone":part.skin.get_bind_bone(bind),"matrix":[[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]})
		data.parts[name_key] = {"surfaces": surfaces, "skin_binds": part.skin.get_bind_count(), "bind_records":bind_records}
	var file := FileAccess.open(WORK+"source.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))
	print("TANK_SOURCE_PASS bones=%d parts=%d" % [data.bones.size(),data.parts.size()])
	source.free()
	quit()
