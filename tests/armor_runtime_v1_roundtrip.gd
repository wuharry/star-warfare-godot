extends "res://tests/armor_runtime_v1_test.gd"

func _run() -> void:
	_configure()
	var real_save:=GameState.save_path
	var before:=_hash(real_save)
	GameState.save_path="user://"+slug+"_roundtrip_profile.json"
	var fixture:=Fixture.new()
	add_child(fixture);fixture.setup()
	GameState.save_path="user://"+slug+"_roundtrip_profile.json"
	var player: WarfarePlayer=fixture.player
	GameState.equipped_armor=_equipped()
	player._apply_recovered_armor_visibility()
	var imported:=(load(asset_path+slug+".glb") as PackedScene).instantiate()
	add_child(imported)
	var head_atlas := _verify_head_atlas(imported)
	var sk:=imported.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var bind_aliases:=sk.get_bone_count()-28
	var original:=player.recovered_skeleton
	for i: int in original.get_bone_count():
		var name_key:=original.get_bone_name(i)
		var index:=sk.find_bone(name_key)
		_check(index>=0,"GLB lost original bone "+name_key)
		if index>=0:_check(sk.get_bone_global_rest(index).is_equal_approx(original.get_bone_global_rest(i)),"GLB changed rest "+name_key)
	var parts:=_visible(player)
	player.recovered_animation_tree.active=false
	for clip: String in ["idle_rifle","run_rifle"]:
		player._play_recovered_animation(clip,0,true)
		for time: float in [0.0,.25,.5]:
			player.recovered_animation_player.seek(time,true)
			original.force_update_all_bone_transforms()
			_compare(parts,original,imported,sk,clip,time)
	fixture.begin("gun00",0)
	for fraction: float in [.25,.50,.75]:
		fixture.advance_to(fixture.duration*fraction)
		_compare(parts,original,imported,sk,"reload",fraction)
	imported.free();fixture.cleanup();fixture.queue_free()
	await get_tree().process_frame
	_check(_hash(real_save)==before,"Roundtrip changed real save")
	GameState.save_path=real_save
	var report:=FileAccess.open(work_path+"review/roundtrip_test.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"poses":records,"head_atlas_pixels":head_atlas,"runtime_scene_sha256":_hash(scene_path),"glb_sha256":_hash(asset_path+slug+".glb"),"target_sha256":_hash(target_path),"original_bones":28,"bind_aliases":bind_aliases,"save_unchanged":_hash(real_save)==before},"\t"))
	print("ARMOR_ROUNDTRIP_%s failures=%d poses=%d"%["PASS" if failures.is_empty() else "FAIL",failures.size(),records.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_head_atlas(imported: Node) -> Dictionary:
	var head := imported.find_child(head_name, true, false) as MeshInstance3D
	_check(head != null, "GLB missing head material for current-atlas verification")
	if head == null: return {"status":"FAIL"}
	var material := head.get_active_material(0) as BaseMaterial3D
	_check(material != null and material.albedo_texture != null, "GLB head diffuse missing")
	if material == null or material.albedo_texture == null: return {"status":"FAIL"}
	var actual := material.albedo_texture.get_image()
	var expected := Image.load_from_file(ProjectSettings.globalize_path(asset_path+"head_diffuse.png"))
	_check(actual != null and expected != null, "Cannot decode imported/canonical head atlas")
	if actual == null or expected == null: return {"status":"FAIL"}
	if actual.is_compressed(): _check(actual.decompress() == OK, "Cannot decompress GLB head")
	var logical := Vector2i(material.albedo_texture.get_size())
	_check(logical == expected.get_size(), "GLB head logical size differs from canonical")
	_check(actual.get_width() >= logical.x and actual.get_width()-logical.x < 4 and actual.get_height() >= logical.y and actual.get_height()-logical.y < 4, "Unexpected imported head block dimensions")
	if logical != expected.get_size(): return {"status":"FAIL"}
	var samples: Array[Dictionary] = []
	var maximum := 0.0
	var source_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(work_path+"build/source.json"))
	var row: Dictionary=source_data.parts[head_name].surfaces[0]
	# Thirty deterministic actual triangle centers span original UV charts.
	var points: Array[Vector2]=[]
	var triangle_count: int=row.indices.size()/3
	for sample_index: int in 30:
		var offset: int=int(float(sample_index)*float(triangle_count-1)/29.0)*3
		var uv:=Vector2.ZERO
		for corner: int in 3:
			var value: Array=row.uv[int(row.indices[offset+corner])]
			uv+=Vector2(value[0],value[1])/3.0
		points.append(uv)
	for uv: Vector2 in points:
		var pixel := Vector2i(roundi(uv.x*(logical.x-1)),roundi(uv.y*(logical.y-1)))
		var a := actual.get_pixelv(pixel)
		var b := expected.get_pixelv(pixel)
		var error := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
		maximum = maxf(maximum,error)
		_check(error <= .05,"GLB imported head differs at %s RGBerror %.5f" % [pixel,error])
		samples.append({"uv":[uv.x,uv.y],"pixel":[pixel.x,pixel.y],"canonical_rgb":[b.r,b.g,b.b],"glb_rgb":[a.r,a.g,a.b],"max_rgb_error":error})
	return {"status":"PASS" if maximum <= .05 else "FAIL","canonical_sha256":_hash(asset_path+"head_diffuse.png"),"logical_size":[logical.x,logical.y],"block_decoded_size":[actual.get_width(),actual.get_height()],"codec_rgb_error_limit":.05,"max_rgb_error":maximum,"samples":samples,"scope":"Thirty actual imported head-material samples versus current canonical; standalone full-five-image RGB equality separately requires zero error."}

func _compare(parts: Array[MeshInstance3D], source_sk: Skeleton3D, imported: Node, sk: Skeleton3D, clip: String, time: float) -> void:
	sk.clear_bones_global_pose_override()
	for i: int in source_sk.get_bone_count():
		var index:=sk.find_bone(source_sk.get_bone_name(i))
		# Reload uses runtime IK overrides. Local animation poses alone omit those
		# solved arm transforms, so compare the actual final global bone poses.
		if index>=0:sk.set_bone_global_pose_override(index,source_sk.get_bone_global_pose(i),1.0,true)
	sk.force_update_all_bone_transforms()
	var maximum:=0.0
	for part: MeshInstance3D in parts:
		var other:=imported.find_child(str(part.name),true,false) as MeshInstance3D
		_check(other!=null,"GLB lost part "+str(part.name))
		if other==null:continue
		var a:=_posed_bounds(part,source_sk)
		var b:=_posed_bounds(other,sk)
		var delta:=maxf(a.position.distance_to(b.position),a.end.distance_to(b.end))
		maximum=maxf(maximum,delta)
		_check(delta<.001,"GLB deformation differs at %s / %s: %.6f"%[part.name,clip,delta])
	records.append({"clip":clip,"time":time,"max_bounds_difference":maximum})
