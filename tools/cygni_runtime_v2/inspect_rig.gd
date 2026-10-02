extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for method: Dictionary in GLTFDocument.new().get_method_list():
		if str(method.name).contains("write"):print("GLTF_METHOD ",method.name)
	var avatar := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	root.add_child(avatar)
	var sk := avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("SKELETON_WORLD ", sk.global_transform)
	var head := avatar.find_child("ArmorHead_11", true, false) as MeshInstance3D
	print("MESH_LOCAL ", head.transform, " WORLD ", head.global_transform)
	for name_key: String in ["ArmorHand_11","ArmorFoot_11"]:
		var part := avatar.find_child(name_key,true,false) as MeshInstance3D
		print("SOURCE_PART ",name_key," bounds=",part.mesh.get_aabb()," skin_binds=",part.skin.get_bind_count()," TRANSFORM ",part.transform)
		for bind: int in part.skin.get_bind_count():
			var name_bone:=part.skin.get_bind_name(bind)
			var delta:=sk.get_bone_global_rest(sk.find_bone(name_bone))*part.skin.get_bind_pose(bind)
			if not delta.is_equal_approx(Transform3D.IDENTITY):
				print("NONIDENTITY_BIND ",name_bone," ",delta)
	var records: Array[Dictionary] = []
	for i: int in sk.get_bone_count():
		var t := sk.get_bone_global_rest(i)
		records.append({"name": sk.get_bone_name(i), "parent": sk.get_bone_parent(i),
			"matrix": [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],
			[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],
			[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]})
	var file := FileAccess.open("res://docs/art/cygni_runtime_v2/build/runtime_rig.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t"))
	for name_key: String in ["Bip01 Head", "Bip01 Spine1", "r hand gun", "fly_bag"]:
		var index := sk.find_bone(name_key)
		var rest := sk.get_bone_global_rest(index)
		print("BONE ", name_key, " LOCAL ", rest, " WORLD ", sk.global_transform * rest)
	avatar.free()
	quit()
