extends SceneTree

const Contract = preload("res://tools/armor_runtime_v1/refined_head_contract.gd")
const WORK := "res://docs/art/titan_runtime_v1/"
const REVIEW := WORK+"review/draft_alignment_20261006/"
const HEAD := "ArmorHead_05"
var errors: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:errors.append(message)

func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK+"runtime_config.json"))
	var target: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REVIEW+"candidate_target.json"))
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	var active := (load("res://assets/armors/titan_v1/titan.scn") as PackedScene).instantiate()
	var candidate := (load(REVIEW+"candidate.scn") as PackedScene).instantiate()
	var skeleton := original.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var maximum_rest_error := 0.0
	for name_key: String in config.parts:
		var current := active.find_child(name_key,true,false) as MeshInstance3D
		var trial := candidate.find_child(name_key,true,false) as MeshInstance3D
		_check(trial.transform==current.transform,"Changed part transform: "+name_key)
		_check(trial.skin.get_bind_count()==current.skin.get_bind_count(),"Changed bind count")
		for bind: int in current.skin.get_bind_count():
			_check(trial.skin.get_bind_name(bind)==current.skin.get_bind_name(bind) and trial.skin.get_bind_pose(bind)==current.skin.get_bind_pose(bind),"Changed skin bind")
		for sid: int in current.mesh.get_surface_count():
			var a := current.mesh.surface_get_arrays(sid)
			var b := trial.mesh.surface_get_arrays(sid)
			for channel: int in Mesh.ARRAY_MAX:
				if name_key==HEAD and channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL]:continue
				_check(a[channel]==b[channel],"Changed existing array: %s/%d/%d"%[name_key,sid,channel])
			_check(trial.get_active_material(sid).albedo_texture.resource_path==current.get_active_material(sid).albedo_texture.resource_path,"Changed canonical texture")
			if name_key!=HEAD:continue
			var source := original.find_child(HEAD,true,false) as MeshInstance3D
			var row: Dictionary = target.parts[HEAD].surfaces[sid]
			errors.append_array(Contract.verify(b,source.mesh.surface_get_arrays(sid),row,config.head_refinement))
			for vertex: int in b[Mesh.ARRAY_VERTEX].size():
				var rest := Vector3.ZERO
				for slot: int in 4:
					var bind: int=b[Mesh.ARRAY_BONES][vertex*4+slot]
					var bone:=skeleton.find_bone(trial.skin.get_bind_name(bind))
					var transform:=skeleton.get_bone_global_rest(bone)*trial.skin.get_bind_pose(bind)
					rest+=(transform*b[Mesh.ARRAY_VERTEX][vertex])*b[Mesh.ARRAY_WEIGHTS][vertex*4+slot]
				var expected:=Vector3(row.positions[vertex][0],row.positions[vertex][1],row.positions[vertex][2])
				maximum_rest_error=maxf(maximum_rest_error,rest.distance_to(expected))
	_check(maximum_rest_error<.000001,"Candidate rest positions differ from target")
	var report := {"status":"PASS" if errors.is_empty() else "FAIL","errors":errors,"scope":"Separate geometry-only candidate; active UV/topology/weights/materials and all non-head arrays exact, inherited source skin binds and authored rest positions checked.","maximum_rest_error":maximum_rest_error,"candidate_scene_sha256":FileAccess.get_sha256(REVIEW+"candidate.scn"),"candidate_target_sha256":FileAccess.get_sha256(REVIEW+"candidate_target.json"),"active_scene_sha256":FileAccess.get_sha256("res://assets/armors/titan_v1/titan.scn")}
	FileAccess.open(REVIEW+"candidate_scene_test.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	original.free();active.free();candidate.free()
	print("TITAN_ALIGNMENT_SCENE_%s errors=%d"%[report.status,errors.size()])
	quit(0 if errors.is_empty() else 1)
