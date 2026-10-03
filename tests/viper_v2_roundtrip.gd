extends "res://tests/viper_v2_test.gd"

func _run() -> void:
	var real_save:=GameState.save_path
	var before:=_hash(real_save)
	GameState.save_path="user://viper_roundtrip_profile.json"
	var fixture:=Fixture.new()
	add_child(fixture);fixture.setup()
	var player: WarfarePlayer=fixture.player
	GameState.equipped_armor={"head":"armor_head_00","body":"armor_body_00","arms":"armor_arms_00","legs":"armor_legs_00","bag":"armor_bag_00"}
	player._apply_recovered_armor_visibility()
	var imported:=(load("res://assets/armors/viper_v2/viper.glb") as PackedScene).instantiate()
	add_child(imported)
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
	imported.free();fixture.cleanup();fixture.queue_free()
	await get_tree().process_frame
	_check(_hash(real_save)==before,"Roundtrip changed real save")
	GameState.save_path=real_save
	var report:=FileAccess.open("res://docs/art/viper_runtime_v2/review/roundtrip_test.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"poses":records,"original_bones":28,"bind_aliases":0,"save_unchanged":_hash(real_save)==before},"\t"))
	print("VIPER_ROUNDTRIP_%s failures=%d poses=%d"%["PASS" if failures.is_empty() else "FAIL",failures.size(),records.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

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
