extends SceneTree
const HeadContract = preload("res://tools/armor_runtime_v1/refined_head_contract.gd")

var errors: Array[String]=[]
func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok:errors.append(message)

func _run() -> void:
	var slug := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--armor="):slug=argument.trim_prefix("--armor=")
	assert(slug in ["hydra","strike","titan","atom","pegasus"])
	var work := "res://docs/art/"+slug+"_runtime_v1/"
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(work+"runtime_config.json"))
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(work+"build/source.json"))
	var target: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(work+"build/target.json"))
	var bounded := str(config.get("geometry_mode", "texture_only")) == "original_source_bounded_refinement"
	var movable: Array = config.get("geometry_parts", []) if bounded else []
	if bounded:
		_check(slug in ["atom", "pegasus"] and config.get("preserve_all_geometry") == false and not movable.is_empty(),"Invalid bounded geometry contract")
		_check(target.get("geometry_mode") == config.geometry_mode and target.get("geometry_parts") == movable,"Authored geometry scope changed")
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	var current_path := "res://"+str(config.asset)+"/"+slug+".scn"
	var current := (load(current_path) as PackedScene).instantiate()
	var sk := original.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var records: Array[Dictionary]=[]
	_check(current.get_child_count()==4,"Current scene must retain four modular parts")
	_check(sk.get_bone_count()==28,"Original skeleton must have 28 bones")
	for name_key: String in config.parts:
		var raw:=original.find_child(name_key,true,false) as MeshInstance3D
		var part:=current.find_child(name_key,true,false) as MeshInstance3D
		var previous:=errors.size()
		_check(raw!=null and part!=null,"Missing original part "+name_key)
		if raw==null or part==null:continue
		_check(raw.transform==part.transform,"Changed original part transform "+name_key)
		_check(part.skeleton==NodePath(".."),"Modular attachment must address parent skeleton")
		_check(raw.skin.get_bind_count()==part.skin.get_bind_count(),"Changed skin bind count")
		for i: int in raw.skin.get_bind_count():
			_check(raw.skin.get_bind_name(i)==part.skin.get_bind_name(i) and raw.skin.get_bind_bone(i)==part.skin.get_bind_bone(i) and raw.skin.get_bind_pose(i)==part.skin.get_bind_pose(i),"Changed original skin bind "+name_key)
		_check(raw.mesh.get_surface_count()==part.mesh.get_surface_count(),"Changed original surface count")
		var maximum_rest_error:=0.0
		var maximum_raw_error:=0.0
		var maximum_frame_error:=0.0
		var modified_part:=false
		for sid: int in raw.mesh.get_surface_count():
			var a:=raw.mesh.surface_get_arrays(sid)
			var b:=part.mesh.surface_get_arrays(sid)
			var is_head:=name_key=="ArmorHead_%02d"%int(config.runtime_id)
			var authored: Dictionary=target.parts[name_key].surfaces[sid]
			var changed := bounded and bool(authored.get("geometry_changed", false))
			modified_part = modified_part or changed
			_check(not changed or name_key in movable,"Changed part outside authorized geometry scope")
			var refined := is_head and config.has("head_refinement") and authored.has("added_vertices")
			if refined:
				errors.append_array(HeadContract.verify(b, a, authored, config.head_refinement))
			for channel: int in Mesh.ARRAY_MAX:
				if refined:continue # Full head subdivision/bind/UV contract above; other parts stay exact.
				if changed and channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:continue
				if not bounded and is_head and not config.get("preserve_all_geometry", false) and channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL]:continue
				_check(a[channel]==b[channel],"Changed original array %s/%d/channel%d"%[name_key,sid,channel])
			if not refined:
				_check(b[Mesh.ARRAY_VERTEX].size()==a[Mesh.ARRAY_VERTEX].size(),"Changed vertex count")
				_check(authored.uv==source.parts[name_key].surfaces[sid].uv,"First integration UV differs from frozen original")
			for i: int in b[Mesh.ARRAY_VERTEX].size():
				if changed:
					var raw_position := Vector3(authored.raw_positions[i][0],authored.raw_positions[i][1],authored.raw_positions[i][2])
					var normal := Vector3(authored.normals[i][0],authored.normals[i][1],authored.normals[i][2])
					var tangent := Vector3(authored.tangents[i][0],authored.tangents[i][1],authored.tangents[i][2])
					var actual_tangent := Vector3(b[Mesh.ARRAY_TANGENT][i*4],b[Mesh.ARRAY_TANGENT][i*4+1],b[Mesh.ARRAY_TANGENT][i*4+2])
					maximum_raw_error=maxf(maximum_raw_error,b[Mesh.ARRAY_VERTEX][i].distance_to(raw_position))
					maximum_frame_error=maxf(maximum_frame_error,maxf(b[Mesh.ARRAY_NORMAL][i].distance_to(normal),actual_tangent.distance_to(tangent)))
					_check(absf(b[Mesh.ARRAY_TANGENT][i*4+3]-float(authored.tangents[i][3]))<.000001,"Authored tangent handedness changed")
					_check(b[Mesh.ARRAY_NORMAL][i].is_finite() and actual_tangent.is_finite() and absf(b[Mesh.ARRAY_NORMAL][i].length()-1)<.001 and absf(actual_tangent.length()-1)<.001 and absf(b[Mesh.ARRAY_NORMAL][i].dot(actual_tangent))<.001,"Invalid delivered normal/tangent frame")
				var rest:=Vector3.ZERO
				for j: int in 4:
					var bind: int=b[Mesh.ARRAY_BONES][i*4+j]
					var bone:=sk.find_bone(part.skin.get_bind_name(bind))
					rest+=(sk.get_bone_global_rest(bone)*part.skin.get_bind_pose(bind)*b[Mesh.ARRAY_VERTEX][i])*b[Mesh.ARRAY_WEIGHTS][i*4+j]
				var p: Array=authored.positions[i]
				maximum_rest_error=maxf(maximum_rest_error,rest.distance_to(Vector3(p[0],p[1],p[2])))
				var uv: Vector2=b[Mesh.ARRAY_TEX_UV][i]
				var t: Array=authored.uv[i]
				_check(uv.distance_to(Vector2(t[0],t[1]))<=.000001,"Actual scene UV differs from authored target")
			_check(maximum_rest_error<=.000001,"Actual scene rest position differs from target")
			_check(maximum_raw_error<=.000002,"Actual scene raw bind position differs from target")
			_check(maximum_frame_error<=.001,"Actual scene normal/tangent differs from target beyond octahedral quantization")
			var material:=part.get_active_material(sid) as BaseMaterial3D
			_check(material!=null and material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,"Generated diffuse rendering context changed")
			if material!=null:
				var label := str(config.parts[name_key][sid])
				var filename := str(config.get("texture_files", {}).get(label, label+"_diffuse.png"))
				_check(material.albedo_texture.resource_path=="res://"+str(config.asset)+"/"+filename,"Wrong canonical texture slot")
		var ok:=errors.size()==previous
		var refined_head := name_key.begins_with("ArmorHead_") and config.has("head_refinement")
		var exact_original: Variant = null if refined_head else ok
		# Retain the first-integration report key for Hydra/Strike consumers.
		records.append({"part":name_key,"surfaces":raw.mesh.get_surface_count(),"indices_skin_weights_bones_topology_exact":exact_original,"original_indices_skin_weights_topology_exact":exact_original,"refinement_contract_verified":ok if refined_head else null,"rest_position_uv_verified_against_target":ok,"max_rest_error_m":maximum_rest_error,"body_limbs_all_arrays_exact":ok if not name_key.begins_with("ArmorHead_") and not modified_part else null,"geometry_changed":modified_part,"immutable_arrays_exact":ok if bounded else null,"normal_frames_verified_against_target":ok if modified_part else null,"max_raw_position_error_m":maximum_raw_error,"max_normal_tangent_error":maximum_frame_error})
	var frozen_path := work+"revisions/original_source_v1/source.json"
	_check(FileAccess.get_file_as_bytes(work+"build/source.json")==FileAccess.get_file_as_bytes(frozen_path),"Immutable true original source changed")
	var report := {"status":"PASS" if errors.is_empty() else "FAIL","errors":errors,"scope":"Actual SCN versus current original player.gltf. Body/limb arrays and all skin binds exact; explicit head subdivision budget, parent weights, UVs and authored rest positions checked.","current_scene_sha256":FileAccess.get_sha256(current_path),"source_sha256":FileAccess.get_sha256(work+"build/source.json"),"target_sha256":FileAccess.get_sha256(work+"build/target.json"),"geometry_sha256":FileAccess.get_sha256(work+"build/geometry.json"),"original_source_snapshot_sha256":FileAccess.get_sha256("res://"+str(config.original_source_snapshot)),"original_bones":28,"original_node_ids":config.original_node_ids,"records":records}
	if bounded:
		report.scope="Actual SCN versus true original: configured part positions/normal/tangent frames match authored target; all UV0, topology, skin, weights, transforms and every unchanged surface array exact. Normal/tangent octahedral quantization tolerance .001."
		report.geometry_mode=config.geometry_mode;report.geometry_parts=movable
	var file:=FileAccess.open(work+"review/original_scene_invariants.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	original.free();current.free()
	print(slug.to_upper()+"_ORIGINAL_SCENE_%s errors=%d"%[report.status,errors.size()])
	quit(0 if errors.is_empty() else 1)
