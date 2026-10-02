extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source:=(load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(source)
	var sk:=source.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var candidate:=(load("res://assets/armors/cygni_v2/cygni.scn") as PackedScene).instantiate()
	var result:={"original":[],"new":[]}
	for version: String in result:
		for name_key: String in ["ArmorHead_11","ArmorBody_11","ArmorHand_11","ArmorFoot_11"]:
			var part:=(source if version=="original" else candidate).find_child(name_key,true,false) as MeshInstance3D
			var transforms: Array[Transform3D]=[]
			for bind: int in part.skin.get_bind_count():
				transforms.append(sk.get_bone_global_pose(sk.find_bone(part.skin.get_bind_name(bind)))*part.skin.get_bind_pose(bind))
			for sid: int in part.mesh.get_surface_count():
				var a:=part.mesh.surface_get_arrays(sid)
				var vertices:=PackedFloat32Array()
				var uvs:=PackedFloat32Array()
				var triangles: PackedInt32Array=a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				if triangles.is_empty():
					for i: int in a[Mesh.ARRAY_VERTEX].size():triangles.append(i)
				for i: int in triangles:
					var point:=Vector3.ZERO
					for j: int in 4:point+=(transforms[a[Mesh.ARRAY_BONES][i*4+j]]*a[Mesh.ARRAY_VERTEX][i])*a[Mesh.ARRAY_WEIGHTS][i*4+j]
					vertices.append_array([point.x,point.y,point.z])
					uvs.append_array([a[Mesh.ARRAY_TEX_UV][i].x,a[Mesh.ARRAY_TEX_UV][i].y])
				var material:=part.get_active_material(sid) as BaseMaterial3D
				var color:=material.albedo_color
				result[version].append({"positions":vertices,"uv":uvs,"texture":material.albedo_texture.resource_path.trim_prefix("res://"),"tint":[color.r,color.g,color.b,1],"part":name_key})
	var file:=FileAccess.open("res://docs/art/cygni_runtime_v2/build/viewer_meshes.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	source.free();candidate.free()
	print("CYGNI_VIEWER_DATA_PASS original_and_new_rest_skinned")
	quit()
