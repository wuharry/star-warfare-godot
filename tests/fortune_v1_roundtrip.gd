extends "res://tests/fortune_v1_test.gd"

func _run() -> void:
	var real_save:=GameState.save_path
	var before:=_hash(real_save)
	GameState.save_path="user://fortune_v1_roundtrip_profile.json"
	var fixture:=Fixture.new()
	add_child(fixture);fixture.setup()
	GameState.save_path="user://fortune_v1_roundtrip_profile.json"
	var player: WarfarePlayer=fixture.player
	GameState.equipped_armor={"head":"armor_head_01","body":"armor_body_01","arms":"armor_arms_01","legs":"armor_legs_01","bag":"armor_bag_00"}
	player._apply_recovered_armor_visibility()
	var imported:=(load("res://assets/armors/fortune_v1/fortune.glb") as PackedScene).instantiate()
	add_child(imported)
	var head_atlas := _verify_head_atlas(imported)
	var sk:=imported.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
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
	var bind_aliases := sk.get_bone_count() - 28
	imported.free();fixture.cleanup();fixture.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_hash(real_save)==before,"Roundtrip changed real save")
	GameState.save_path=real_save
	var report:=FileAccess.open("res://docs/art/fortune_runtime_v1/review/roundtrip_test.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"poses":records,"original_bones":28,"bind_aliases":bind_aliases,"head_atlas_pixels":head_atlas,"runtime_scene_sha256":_hash("res://assets/armors/fortune_v1/fortune.scn"),"glb_sha256":_hash("res://assets/armors/fortune_v1/fortune.glb"),"save_unchanged":_hash(real_save)==before},"\t"))
	print("FORTUNE_ROUNDTRIP_%s failures=%d poses=%d"%["PASS" if failures.is_empty() else "FAIL",failures.size(),records.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_head_atlas(imported: Node) -> Dictionary:
	var head := imported.find_child("ArmorHead_01", true, false) as MeshInstance3D
	_check(head != null, "GLB has no head for texture comparison")
	if head == null:return {"status":"FAIL"}
	var material := head.get_active_material(0) as BaseMaterial3D
	_check(material != null and material.albedo_texture != null, "GLB head has no diffuse")
	if material == null or material.albedo_texture == null:return {"status":"FAIL"}
	var actual := material.albedo_texture.get_image()
	var expected := Image.load_from_file(ProjectSettings.globalize_path("res://assets/armors/fortune_v1/head_diffuse.png"))
	_check(actual != null and expected != null, "Cannot decode GLB/canonical head images")
	if actual == null or expected == null:return {"status":"FAIL"}
	if actual.is_compressed():_check(actual.decompress() == OK, "Cannot decompress GLB head image")
	var logical_size := Vector2i(material.albedo_texture.get_size())
	_check(logical_size == expected.get_size(), "GLB head logical texture size differs from canonical")
	_check(actual.get_width() >= logical_size.x and actual.get_width()-logical_size.x < 4 and actual.get_height() >= logical_size.y and actual.get_height()-logical_size.y < 4, "Unexpected GLB block-decoded image size")
	if logical_size != expected.get_size():return {"status":"FAIL"}
	var points: Array[Dictionary] = []
	for u: float in [.555, .58, .62]:
		for v: float in [.735, .79, .87, .93, .967]:points.append({"region":"visor_centre","uv":Vector2(u,v)})
	for u: float in [.69, .80, .93]:
		for v: float in [.75, .84]:points.append({"region":"visor_side","uv":Vector2(u,v)})
	for u: float in [.09, .20, .32, .40]:
		for v: float in [.865, .90, .94]:points.append({"region":"neck","uv":Vector2(u,v)})
	points.append({"region":"front_crown","uv":Vector2(.6225,.0816)})
	var maximum := 0.0
	var samples: Array[Dictionary] = []
	for sample: Dictionary in points:
		var uv: Vector2 = sample.uv
		var pixel := Vector2i(roundi(uv.x * (expected.get_width()-1)), roundi(uv.y * (expected.get_height()-1)))
		var a := actual.get_pixelv(pixel)
		var b := expected.get_pixelv(pixel)
		var error := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
		maximum = maxf(maximum,error)
		_check(error <= .05, "GLB has stale/different %s pixels at %s (RGB difference %.5f)"%[sample.region,pixel,error])
		samples.append({"region":sample.region,"pixel":[pixel.x,pixel.y],"canonical_rgb":[b.r,b.g,b.b],"glb_rgb":[a.r,a.g,a.b],"max_rgb_error":error})
	return {"status":"PASS" if maximum<=.05 else "FAIL","canonical_sha256":_hash("res://assets/armors/fortune_v1/head_diffuse.png"),"glb_texture":material.albedo_texture.resource_path,"logical_size":[logical_size.x,logical_size.y],"block_decoded_size":[actual.get_width(),actual.get_height()],"codec_rgb_error_limit":.05,"codec_note":"Imported VRAM texture blocks pad1254 to1256. Normalized UV samples use logical1254 dimensions, not the padded decode. Direct standalone GLB embedded PNGs are separately required to have exactly equal RGB pixels.","samples":samples,"max_rgb_error":maximum}

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
