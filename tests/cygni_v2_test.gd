extends Node3D

const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const PREFIXES := ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]
var failures: Array[String] = []
var records: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("CYGNI_V2: " + message)

func _run() -> void:
	var real_save := GameState.save_path
	var before := _hash(real_save)
	GameState.save_path="user://cygni_v2_test_profile.json"
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	GameState.save_path="user://cygni_v2_test_profile.json"
	var player: WarfarePlayer=fixture.player
	var skeleton := player.recovered_skeleton
	var rests: Array[Transform3D]=[]
	for i: int in skeleton.get_bone_count():rests.append(skeleton.get_bone_rest(i))
	_check(Visuals.reworked_scene_path(11)=="res://assets/armors/cygni_v2/cygni.scn","Run this test with --cygni-v2")
	for id: int in [10,12,13,20,21,28]:
		_check(Visuals.reworked_scene_path(id)=="res://assets/equipment_refined/armors/armor_%02d.scn"%id,"Retained set changed")
	_check(Visuals.reworked_scene_path(6)=="res://assets/armors/thunder/thunder.scn","Adopted Thunder changed")
	var source := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	var geometry: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/cygni_runtime_v2/build/geometry.json"))
	GameState.equipped_armor={"head":"armor_head_11","body":"armor_body_11","arms":"armor_arms_11","legs":"armor_legs_11","bag":"armor_bag_00"}
	player._apply_recovered_armor_visibility()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var parts := _visible(player)
	_check(parts.size()==4,"Expected four modular parts")
	var triangles := 0
	for part: MeshInstance3D in parts:
		var baseline:=source.find_child(str(part.name),true,false) as MeshInstance3D
		_check(part.get_meta("armor_rework","")=="cygni_runtime_v2","Wrong asset revision")
		_check(part.skin!=null and part.get_node_or_null(part.skeleton)==skeleton,"Part lost its skeleton")
		_check(part.transform.is_equal_approx(Transform3D.IDENTITY),"Unexpected attachment transform")
		for i: int in part.skin.get_bind_count():
			var bone := skeleton.find_bone(part.skin.get_bind_name(i))
			_check(bone>=0,"Unknown bind name")
			if bone>=0:
				var expected_bind:=skeleton.get_bone_global_rest(bone).affine_inverse()
				if i<baseline.skin.get_bind_count():
					expected_bind=baseline.skin.get_bind_pose(i)
					_check(part.skin.get_bind_name(i)==baseline.skin.get_bind_name(i),"Reordered legacy bind")
				_check(part.skin.get_bind_pose(i).is_equal_approx(expected_bind),"Changed source bind")
		var expected: Dictionary=geometry.parts[str(part.name)].bounds_game
		var actual := _posed_bounds(part,skeleton)
		if part.name=="ArmorHead_11":
			_check(actual.position.distance_to(Vector3(expected.min[0],expected.min[1],expected.min[2]))<.001,"Authored head shifted")
			_check(actual.end.distance_to(Vector3(expected.max[0],expected.max[1],expected.max[2]))<.001,"Authored head scaled")
		elif part.name in ["ArmorHand_11","ArmorFoot_11"]:
			var old_rest:=_posed_bounds(baseline,skeleton)
			_check(actual.position.distance_to(old_rest.position)<.001 and actual.end.distance_to(old_rest.end)<.001,"Original limb rest geometry changed")
		for sid: int in part.mesh.get_surface_count():
			var arrays:=part.mesh.surface_get_arrays(sid)
			triangles+=arrays[Mesh.ARRAY_VERTEX].size()/3
			var material:=part.get_active_material(sid) as StandardMaterial3D
			_check(material!=null and material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,"Wrong painted rendering context")
			_check(material!=null and material.albedo_texture!=null,"Missing generated diffuse")
			if material!=null and material.albedo_texture!=null:_check(material.albedo_texture.get_size()==Vector2(512,512),"Wrong delivered texture size")
			for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:_check(uv.is_finite() and uv.x>=0 and uv.x<=1 and uv.y>=0 and uv.y<=1,"UV outside atlas")
			for i: int in arrays[Mesh.ARRAY_VERTEX].size():
				_check(arrays[Mesh.ARRAY_VERTEX][i].is_finite() and absf(arrays[Mesh.ARRAY_NORMAL][i].length()-1)<.01,"Invalid geometry attributes")
				var total:=0.0
				for j: int in 4:
					_check(arrays[Mesh.ARRAY_BONES][i*4+j]>=0 and arrays[Mesh.ARRAY_BONES][i*4+j]<part.skin.get_bind_count(),"Invalid skin index")
					total+=arrays[Mesh.ARRAY_WEIGHTS][i*4+j]
				_check(absf(total-1)<.001,"Weights not normalized")
	_check(triangles<=3000,"Exceeded prototype budget")
	player.recovered_animation_tree.active=false
	for clip: String in ["idle_rifle","run_rifle"]:
		player._play_recovered_animation(clip,0,true)
		for time: float in [0.0,.15,.30,.50,.75]:
			player.recovered_animation_player.seek(time,true)
			skeleton.force_update_all_bone_transforms()
			_check_pose(parts,skeleton,source,clip,time)
	fixture.begin("gun00",0)
	for fraction: float in [.15,.35,.55,.75,.95]:
		fixture.advance_to(fixture.duration*fraction)
		_check_pose(parts,skeleton,source,"reload",fraction)
	for i: int in skeleton.get_bone_count():_check(skeleton.get_bone_rest(i).is_equal_approx(rests[i]),"Skeleton rest or mount changed")
	GameState.equipped_armor={"head":"armor_head_11","body":"armor_body_10","arms":"armor_arms_09","legs":"armor_legs_12","bag":"armor_bag_00"}
	player._apply_recovered_armor_visibility()
	var names: Array[String]=[]
	for part: MeshInstance3D in _visible(player):names.append(str(part.name))
	_check(names.size()==4,"Mixed equipment duplicated parts")
	for name_key: String in ["ArmorHead_11","ArmorBody_10","ArmorHand_09","ArmorFoot_12"]:_check(name_key in names,"Mixed equipment lost "+name_key)
	var count:=skeleton.get_child_count()
	for i: int in 5:player._apply_recovered_armor_visibility()
	_check(count==skeleton.get_child_count(),"Repeated equip adds nodes")
	var shell := UnityEquipmentShell.new()
	shell.setup("store",true)
	add_child(shell)
	for mode: String in ["store","customize"]:
		shell.set_mode(mode,false)
		for index: int in 4:
			shell._select_category(["head","body","arms","legs"][index],false)
			shell._select_item("armor_%s_11"%["head","body","arms","legs"][index],false)
			var shown:=shell.preview_root.find_child(PREFIXES[index]+"11",true,false) as MeshInstance3D
			_check(shown!=null and shown.visible and shown.get_meta("armor_rework","")=="cygni_runtime_v2","Store/customize uses stale asset")
	shell.queue_free()
	source.free()
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_hash(real_save)==before,"Real save modified")
	GameState.save_path=real_save
	var report:=FileAccess.open("res://docs/art/cygni_runtime_v2/review/runtime_test.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"triangles":triangles,"poses":records,"save_unchanged":_hash(real_save)==before},"\t"))
	print("CYGNI_V2_TEST_%s failures=%d samples=%d triangles=%d save_unchanged=%s"%["PASS" if failures.is_empty() else "FAIL",failures.size(),records.size(),triangles,str(_hash(real_save)==before)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_pose(parts: Array[MeshInstance3D], skeleton: Skeleton3D, source: Node, clip: String, time: float) -> void:
	var pose_record:={"clip":clip,"time":time,"bounds":{}}
	for part: MeshInstance3D in parts:
		var bounds:=_posed_bounds(part,skeleton)
		_check(bounds.size.length()<3.2,"Mesh exploded during "+clip)
		if part.name in ["ArmorHand_11","ArmorFoot_11"]:
			var original:=source.find_child(str(part.name),true,false) as MeshInstance3D
			var previous:=_posed_bounds(original,skeleton)
			_check(bounds.position.distance_to(previous.position)<.003 and bounds.end.distance_to(previous.end)<.003,"Original limb deformation changed in "+clip)
		pose_record.bounds[str(part.name)]={"min":str(bounds.position),"max":str(bounds.end)}
	records.append(pose_record)

func _posed_bounds(part: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var transforms: Array[Transform3D]=[]
	for bind: int in part.skin.get_bind_count():
		var bone:=skeleton.find_bone(part.skin.get_bind_name(bind))
		transforms.append(skeleton.get_bone_global_pose(bone)*part.skin.get_bind_pose(bind))
	var first:=true
	var box:=AABB()
	for sid: int in part.mesh.get_surface_count():
		var arrays:=part.mesh.surface_get_arrays(sid)
		for i: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point:=Vector3.ZERO
			for j: int in 4:
				point+=(transforms[arrays[Mesh.ARRAY_BONES][i*4+j]]*arrays[Mesh.ARRAY_VERTEX][i])*arrays[Mesh.ARRAY_WEIGHTS][i*4+j]
			_check(point.is_finite(),"Non-finite posed vertex")
			box=AABB(point,Vector3.ZERO) if first else box.expand(point)
			first=false
	return box

func _visible(player: WarfarePlayer) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D]=[]
	for part: MeshInstance3D in player.recovered_avatar.find_children("Armor*","MeshInstance3D",true,false):
		if part.visible:result.append(part)
	return result

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
