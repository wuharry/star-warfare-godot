extends Node3D

const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const HeadContract = preload("res://tools/armor_runtime_v1/refined_head_contract.gd")
const PREFIXES := ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]
const LOCAL_GEOMETRY_CHANGE_LIMIT := .20 # Latest authorized original-total head limit; unchanged body/limbs independently exact.
const UV_CHANGED_COORDINATE_LIMIT := .20 # Per-surface original total; this iteration also requires exact v2 UV.
var slug := ""
var id := 0
var config: Dictionary
var work_path := ""
var asset_path := ""
var scene_path := ""
var target_path := ""
var head_name := ""
var non_head_names: Array[String] = []

func _configure() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--armor="):slug=argument.trim_prefix("--armor=")
	assert(slug in ["hydra","strike","titan"])
	config=JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/"+slug+"_runtime_v1/runtime_config.json"))
	id=int(config.runtime_id)
	work_path="res://"+str(config.work)+"/";asset_path="res://"+str(config.asset)+"/"
	scene_path=asset_path+slug+".scn";target_path=work_path+"build/target.json"
	head_name="ArmorHead_%02d"%id
	for name_key: String in config.parts:
		if name_key!=head_name:non_head_names.append(name_key)

func _equipped() -> Dictionary:
	return {"head":"armor_head_%02d"%id,"body":"armor_body_%02d"%id,"arms":"armor_arms_%02d"%id,"legs":"armor_legs_%02d"%id,"bag":"armor_bag_00"}

var failures: Array[String] = []
var records: Array[Dictionary] = []
var legacy_out_of_range_uv: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("ARMOR_RUNTIME_V1: " + message)

func _run() -> void:
	_configure()
	var real_save := GameState.save_path
	var before := _hash(real_save)
	GameState.save_path="user://"+slug+"_v1_test_profile.json"
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	GameState.save_path="user://"+slug+"_v1_test_profile.json"
	var player: WarfarePlayer=fixture.player
	var skeleton := player.recovered_skeleton
	var rests: Array[Transform3D]=[]
	for i: int in skeleton.get_bone_count():rests.append(skeleton.get_bone_rest(i))
	_check(Visuals.reworked_scene_path(id)==scene_path,"Default Tank should load the adopted current asset")
	for retained_id: int in [10,12,13,20,21,28]:
		_check(Visuals.reworked_scene_path(retained_id)=="res://assets/equipment_refined/armors/armor_%02d.scn"%retained_id,"Retained set changed")
	_check(Visuals.reworked_scene_path(6)=="res://assets/armors/thunder/thunder.scn","Adopted Thunder changed")
	var source := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	var authored: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(target_path))
	var geometry: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(work_path+"build/geometry.json"))
	GameState.equipped_armor=_equipped()
	player._apply_recovered_armor_visibility()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var parts := _visible(player)
	_check(parts.size()==4,"Expected four modular parts")
	var triangles := 0
	var uv_records: Dictionary = {}
	var rest_geometry_records: Dictionary = {}
	for part: MeshInstance3D in parts:
		var baseline:=source.find_child(str(part.name),true,false) as MeshInstance3D
		_check(part.get_meta("armor_rework","")==slug+"_runtime_v1","Wrong asset revision")
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
		var old_rest := _posed_bounds(baseline,skeleton)
		var dimension_deltas: Array[float] = []
		for axis: int in 3:
			var relative := absf(actual.size[axis]/old_rest.size[axis]-1.0)
			dimension_deltas.append(relative)
			_check(relative<=LOCAL_GEOMETRY_CHANGE_LIMIT,"Runtime rest dimensions exceed original20% head budget")
		var original_points := _posed_vertices(baseline,skeleton)
		var actual_points := _posed_vertices(part,skeleton)
		var is_refined_head := part.name==head_name and config.has("head_refinement")
		_check(actual_points.size()==(int(config.head_refinement.vertices) if is_refined_head else original_points.size()),"Runtime rest vertex count differs from explicit budget")
		var max_rest_displacement := 0.0
		for vertex_index: int in mini(actual_points.size(),original_points.size()):
			max_rest_displacement=maxf(max_rest_displacement,actual_points[vertex_index].distance_to(original_points[vertex_index]))
		var displacement_fraction := max_rest_displacement/minf(old_rest.size.x,minf(old_rest.size.y,old_rest.size.z))
		_check(displacement_fraction<=LOCAL_GEOMETRY_CHANGE_LIMIT,"Runtime rest vertex displacement exceeds original20% head budget")
		rest_geometry_records[str(part.name)]={"dimension_delta_fraction":dimension_deltas,"max_rest_displacement":max_rest_displacement,"max_displacement_fraction_of_smallest_dimension":displacement_fraction}
		if part.name==head_name:
			_check(actual.position.distance_to(Vector3(expected.min[0],expected.min[1],expected.min[2]))<.001,"Authored head shifted")
			_check(actual.end.distance_to(Vector3(expected.max[0],expected.max[1],expected.max[2]))<.001,"Authored head scaled")
		elif part.name in non_head_names:
			_check(actual.position.distance_to(old_rest.position)<.001 and actual.end.distance_to(old_rest.end)<.001,"Original limb rest geometry changed")
		for sid: int in part.mesh.get_surface_count():
			var arrays:=part.mesh.surface_get_arrays(sid)
			var raw:=baseline.mesh.surface_get_arrays(sid)
			if is_refined_head:
				for error: String in HeadContract.verify(arrays, raw, authored.parts[str(part.name)].surfaces[sid], config.head_refinement):
					_check(false,error)
			else:
				_check(arrays[Mesh.ARRAY_TEX_UV].size()==raw[Mesh.ARRAY_TEX_UV].size(),"Changed UV coordinate count")
			var moved:=0
			var maximum_uv_displacement:=0.0
			for index: int in raw[Mesh.ARRAY_TEX_UV].size():
				var old_uv: Vector2=raw[Mesh.ARRAY_TEX_UV][index]
				var new_uv: Vector2=arrays[Mesh.ARRAY_TEX_UV][index]
				var expected_uv: Array=authored.parts[str(part.name)].surfaces[sid].uv[index]
				_check(new_uv.distance_to(Vector2(expected_uv[0],expected_uv[1]))<.000001,"Runtime UV differs from authored master")
				var distance:=old_uv.distance_to(new_uv)
				maximum_uv_displacement=maxf(maximum_uv_displacement,distance)
				if distance>.000001:
					moved+=1
					_check(is_refined_head,"First integration must retain every original UV coordinate")
			var fraction: float=float(moved)/raw[Mesh.ARRAY_TEX_UV].size()
			_check(fraction<=UV_CHANGED_COORDINATE_LIMIT,"UV changes exceed20% of material surface")
			var original_charts:=_uv_charts(raw)
			var authored_charts:=_uv_charts(arrays)
			_check(original_charts==authored_charts,"Original UV chart count changed")
			uv_records["%s_surface_%d"%[part.name,sid]]={"coordinates":raw[Mesh.ARRAY_TEX_UV].size(),"changed":moved,"changed_fraction":fraction,"maximum_uv_displacement":maximum_uv_displacement,"original_charts":original_charts,"authored_charts":authored_charts}
			if not is_refined_head:
				_check(arrays[Mesh.ARRAY_INDEX]==raw[Mesh.ARRAY_INDEX],"Reordered original triangles")
				_check(arrays[Mesh.ARRAY_BONES]==raw[Mesh.ARRAY_BONES] and arrays[Mesh.ARRAY_WEIGHTS]==raw[Mesh.ARRAY_WEIGHTS],"Changed original rig weights")
			if part.name!=head_name:_check(arrays[Mesh.ARRAY_VERTEX]==raw[Mesh.ARRAY_VERTEX],"Untouched body/limb geometry changed")
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
			var material:=part.get_active_material(sid) as StandardMaterial3D
			_check(material!=null and material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,"Wrong painted rendering context")
			_check(material!=null and material.albedo_texture!=null,"Missing generated diffuse")
			if material!=null and material.albedo_texture!=null:_check(material.albedo_texture.get_width()>=512 and material.albedo_texture.get_width()==material.albedo_texture.get_height(),"Diffuse must be a square texture at least 512 pixels")
			for index: int in arrays[Mesh.ARRAY_TEX_UV].size():
				var uv: Vector2=arrays[Mesh.ARRAY_TEX_UV][index]
				var source_uv: Vector2=raw[Mesh.ARRAY_TEX_UV][index] if index<raw[Mesh.ARRAY_TEX_UV].size() else Vector2(INF,INF)
				var in_range:=uv.x>=0 and uv.x<=1 and uv.y>=0 and uv.y<=1
				_check(uv.is_finite() and (in_range or uv==source_uv),"New UV outside atlas; only exact inherited original outliers permitted")
				if not in_range:legacy_out_of_range_uv.append({"part":str(part.name),"surface":sid,"index":index,"source_uv":[source_uv.x,source_uv.y],"current_uv":[uv.x,uv.y],"source_exact":uv==source_uv})
			for i: int in arrays[Mesh.ARRAY_VERTEX].size():
				_check(arrays[Mesh.ARRAY_VERTEX][i].is_finite() and absf(arrays[Mesh.ARRAY_NORMAL][i].length()-1)<.01,"Invalid geometry attributes")
				var total:=0.0
				for j: int in 4:
					_check(arrays[Mesh.ARRAY_BONES][i*4+j]>=0 and arrays[Mesh.ARRAY_BONES][i*4+j]<part.skin.get_bind_count(),"Invalid skin index")
					total+=arrays[Mesh.ARRAY_WEIGHTS][i*4+j]
				_check(absf(total-1)<.001,"Weights not normalized")
	var expected_triangles := int(config.original_triangles)
	if config.has("head_refinement"):
		expected_triangles += int(config.head_refinement.triangles)-int(config.texture_slots.head.triangles)
	_check(triangles==expected_triangles,"Triangle topology differs from explicit head refinement budget")
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
	GameState.equipped_armor={"head":"armor_head_%02d"%id,"body":"armor_body_10","arms":"armor_arms_09","legs":"armor_legs_12","bag":"armor_bag_00"}
	player._apply_recovered_armor_visibility()
	var names: Array[String]=[]
	for part: MeshInstance3D in _visible(player):names.append(str(part.name))
	_check(names.size()==4,"Mixed equipment duplicated parts")
	for name_key: String in [head_name,"ArmorBody_10","ArmorHand_09","ArmorFoot_12"]:_check(name_key in names,"Mixed equipment lost "+name_key)
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
			shell._select_item("armor_%s_%02d"%[["head","body","arms","legs"][index],id],false)
			var shown:=shell.preview_root.find_child(PREFIXES[index]+("%02d"%id),true,false) as MeshInstance3D
			_check(shown!=null and shown.visible and shown.get_meta("armor_rework","")==slug+"_runtime_v1","Store/customize uses stale asset")
	shell.queue_free()
	source.free()
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_hash(real_save)==before,"Real save modified")
	GameState.save_path=real_save
	var report:=FileAccess.open(work_path+"review/runtime_test.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"triangles":triangles,"poses":records,"uv_edits":uv_records,"legacy_out_of_range_uv":legacy_out_of_range_uv,"rest_geometry":rest_geometry_records,"limits":{"uv_changed_coordinate_fraction":UV_CHANGED_COORDINATE_LIMIT,"uv_count_scope":"per_material_surface","local_geometry_change_fraction":LOCAL_GEOMETRY_CHANGE_LIMIT},"target_sha256":_hash(target_path),"runtime_scene_sha256":_hash(Visuals.reworked_scene_path(id)),"save_unchanged":_hash(real_save)==before,"user_args":OS.get_cmdline_user_args(),"armor_scene":Visuals.reworked_scene_path(id)},"\t"))
	print("ARMOR_RUNTIME_V1_TEST_%s failures=%d samples=%d triangles=%d save_unchanged=%s"%["PASS" if failures.is_empty() else "FAIL",failures.size(),records.size(),triangles,str(_hash(real_save)==before)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_pose(parts: Array[MeshInstance3D], skeleton: Skeleton3D, source: Node, clip: String, time: float) -> void:
	var pose_record:={"clip":clip,"time":time,"bounds":{}}
	for part: MeshInstance3D in parts:
		var bounds:=_posed_bounds(part,skeleton)
		_check(bounds.size.length()<3.2,"Mesh exploded during "+clip)
		if part.name in non_head_names:
			var original:=source.find_child(str(part.name),true,false) as MeshInstance3D
			var previous:=_posed_bounds(original,skeleton)
			_check(bounds.position.distance_to(previous.position)<.003 and bounds.end.distance_to(previous.end)<.003,"Original limb deformation changed in "+clip)
		if part.name==head_name:
			var original:=source.find_child(str(part.name),true,false) as MeshInstance3D
			var previous:=_posed_bounds(original,skeleton)
			var relative:=maxf(bounds.position.distance_to(previous.position),bounds.end.distance_to(previous.end))/minf(previous.size.x,minf(previous.size.y,previous.size.z))
			_check(relative<=LOCAL_GEOMETRY_CHANGE_LIMIT,"Head deformation exceeds original-total20% head budget")
			pose_record.head_bounds_delta_fraction=relative
		pose_record.bounds[str(part.name)]={"min":str(bounds.position),"max":str(bounds.end)}
	records.append(pose_record)

func _posed_bounds(part: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var first:=true
	var box:=AABB()
	for point: Vector3 in _posed_vertices(part,skeleton):
		box=AABB(point,Vector3.ZERO) if first else box.expand(point)
		first=false
	return box

func _posed_vertices(part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var transforms: Array[Transform3D]=[]
	for bind: int in part.skin.get_bind_count():
		var bone:=skeleton.find_bone(part.skin.get_bind_name(bind))
		transforms.append(skeleton.get_bone_global_pose(bone)*part.skin.get_bind_pose(bind))
	var points := PackedVector3Array()
	for sid: int in part.mesh.get_surface_count():
		var arrays:=part.mesh.surface_get_arrays(sid)
		for i: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point:=Vector3.ZERO
			for j: int in 4:
				point+=(transforms[arrays[Mesh.ARRAY_BONES][i*4+j]]*arrays[Mesh.ARRAY_VERTEX][i])*arrays[Mesh.ARRAY_WEIGHTS][i*4+j]
			_check(point.is_finite(),"Non-finite posed vertex")
			points.append(point)
	return points

func _visible(player: WarfarePlayer) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D]=[]
	for part: MeshInstance3D in player.recovered_avatar.find_children("Armor*","MeshInstance3D",true,false):
		if part.visible:result.append(part)
	return result

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"

func _uv_charts(arrays: Array) -> int:
	var keys: Array[String]=[]
	for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:keys.append("%.6f,%.6f"%[uv.x,uv.y])
	var adjacency: Dictionary={}
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for start: int in range(0,indices.size(),3):
		for index: int in 3:
			var key:=keys[indices[start+index]]
			if not adjacency.has(key):adjacency[key]={}
			for other: int in 3:adjacency[key][keys[indices[start+other]]]=true
	var remaining:=adjacency.duplicate()
	var count:=0
	while not remaining.is_empty():
		count+=1
		var first: String=remaining.keys()[0]
		var pending: Array[String]=[first]
		remaining.erase(first)
		while not pending.is_empty():
			var current: String=pending.pop_back()
			for neighbor: String in adjacency[current]:
				if remaining.has(neighbor):
					remaining.erase(neighbor)
					pending.append(neighbor)
	return count
