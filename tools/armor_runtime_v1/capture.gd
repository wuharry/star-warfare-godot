extends Node3D

const Fixture=preload("res://tests/reload_catalog_fixture.gd")
var OUT:=""
var LABELS: Dictionary={}
var NAMES: Array[String]=[]
var config: Dictionary={}
var slug:=""
var id:=0
var work_path:=""
var asset_path:=""
var scene_path:=""
var target_path:=""
var preview_textures: Dictionary={}
var baseline: Node3D
var candidate: Node3D
var files: Array[String]=[]
var dimensions: Dictionary={}
var capture_viewport: SubViewport
var review_points: Array[Vector3]=[]
var framing: Dictionary={}
var texture_sha256: Dictionary = {}
var scene_sha256_at_start := ""
var target_sha256_at_start := ""
var capture_sha256: Dictionary = {}
var monitored_save_path := ""
var monitored_save_sha256 := ""
var save_change_first_capture := ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--armor="):slug=argument.trim_prefix("--armor=")
	assert(slug in ["hydra","strike","titan","atom","pegasus"])
	config=JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/"+slug+"_runtime_v1/runtime_config.json"))
	id=int(config.runtime_id);LABELS=config.parts;NAMES.assign(config.parts.keys())
	work_path="res://"+str(config.work)+"/";asset_path="res://"+str(config.asset)+"/"
	scene_path=asset_path+slug+".scn";target_path=work_path+"build/target.json"
	# A review candidate stays separate from the configured gameplay asset.
	# Its resource hashes are captured via the same fields as the live scene.
	var candidate_scene_supplied := false
	var candidate_target_supplied := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate-scene="):
			candidate_scene_supplied=true
			scene_path=argument.trim_prefix("--candidate-scene=")
			assert(scene_path.begins_with("res://") and scene_path.ends_with(".scn") and FileAccess.file_exists(scene_path))
		if argument.begins_with("--candidate-target="):
			candidate_target_supplied=true
			target_path=argument.trim_prefix("--candidate-target=")
			assert(target_path.begins_with("res://") and target_path.ends_with(".json") and FileAccess.file_exists(target_path))
	assert(candidate_scene_supplied==candidate_target_supplied, "A review candidate requires both its scene and authored target")
	OUT=work_path+"review/engine/"
	if "--material-preview" in OS.get_cmdline_user_args():OUT=work_path+"review/placement_v4_preview/"
	if "--head-preview" in OS.get_cmdline_user_args():OUT=work_path+"review/head_v2_preview/"
	if "--visor-coverage" in OS.get_cmdline_user_args():
		assert(slug == "titan")
		OUT = work_path + "review/helmet_v%d_coverage/" % int(str(config.active_helmet_revision).trim_prefix("helmet_refinement_v"))
	if "--baseline-only" in OS.get_cmdline_user_args():OUT=work_path+"review/baseline/"
	if "--geometry-review" in OS.get_cmdline_user_args():OUT=work_path+"review/pretexture/"
	if "--face-review" in OS.get_cmdline_user_args():OUT=work_path+"review/face_geometry/"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-revision="):
			var revision := argument.trim_prefix("--preview-revision=")
			assert(revision.is_valid_filename())
			OUT=work_path+"review/" + revision + "/"
	for label: String in ["head","body","shoulder","hand","foot"]:
		texture_sha256[label] = _hash(_texture_path(label))
	scene_sha256_at_start = _hash(scene_path)
	target_sha256_at_start = _hash(target_path)
	get_tree().root.size=Vector2i(640,720)
	capture_viewport=SubViewport.new()
	capture_viewport.size=Vector2i(640,720)
	capture_viewport.own_world_3d=true
	capture_viewport.msaa_3d=Viewport.MSAA_4X
	capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(capture_viewport)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if "--direct-textures" in OS.get_cmdline_user_args():
		for label: String in ["head","body","shoulder","hand","foot"]:
			var pixels:=Image.load_from_file(ProjectSettings.globalize_path(_texture_path(label)))
			assert(pixels!=null)
			pixels.generate_mipmaps()
			preview_textures[label]=ImageTexture.create_from_image(pixels)
	var real_save:=GameState.save_path
	var before:=_hash(real_save)
	monitored_save_path=real_save;monitored_save_sha256=before
	GameState.save_path="user://"+slug+"_v1_capture_profile.json"
	baseline=(load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	candidate=baseline.duplicate() if "--baseline-only" in OS.get_cmdline_user_args() else (load(scene_path) as PackedScene).instantiate()
	var fixture:=Fixture.new()
	capture_viewport.add_child(fixture)
	fixture.setup()
	GameState.save_path="user://"+slug+"_v1_capture_profile.json"
	GameState.equipped_armor={"head":"armor_head_%02d"%id,"body":"armor_body_%02d"%id,"arms":"armor_arms_%02d"%id,"legs":"armor_legs_%02d"%id,"bag":"armor_bag_00"}
	fixture.player._apply_recovered_armor_visibility()
	fixture.label.hide()
	var player: WarfarePlayer=fixture.player
	player.recovered_animation_tree.active=false
	player.recovered_animation_player.stop()
	player.recovered_skeleton.reset_bone_poses()
	player.recovered_skeleton.force_update_all_bone_transforms()
	var hidden: Array[MeshInstance3D]=[]
	for mesh: MeshInstance3D in player.recovered_avatar.find_children("*","MeshInstance3D",true,false):
		if (not str(mesh.name).begins_with("Armor") or str(mesh.name).begins_with("ArmorBag")) and mesh.visible:
			hidden.append(mesh);mesh.hide()
	# Fit both cages together, using the actual fixture skeleton in world space.
	# Import bounds alone omit the parent transform and the current skin pose.
	for source: Node3D in [baseline,candidate]:
		for name_key: String in NAMES:
			review_points.append_array(_posed_points(source.find_child(name_key,true,false) as MeshInstance3D,player.recovered_skeleton))
	if "--check-framing" in OS.get_cmdline_user_args():
		for view: String in ["front","side","rear","quarter"]:
			_set_ortho(fixture.view_camera,view)
		print("TANK_FRAMING_PASS "+JSON.stringify(framing))
		baseline.free();candidate.free();fixture.cleanup();GameState.save_path=real_save
		get_tree().quit();return
	if "--material-preview" in OS.get_cmdline_user_args():
		for view: String in ["front","side","rear","quarter"]:
			_set_ortho(fixture.view_camera,view)
			for version: String in ["original","new"]:
				_apply(player.recovered_avatar,version,false,true)
				await _capture("%s_diffuse_%s"%[version,view])
		baseline.free();candidate.free();fixture.cleanup();GameState.save_path=real_save
		AudioDirector.stop_all_sfx()
		print("TANK_MATERIAL_PREVIEW_PASS direct PNG / authored UV / files=%d save_unchanged=%s"%[files.size(),str(_hash(real_save)==before)])
		get_tree().quit(0 if _hash(real_save)==before else 1)
		return
	if "--visor-coverage" in OS.get_cmdline_user_args():
		_set_ortho(fixture.view_camera,"front")
		var center:=Vector3(0,1.58,-.07)
		var direction:=fixture.view_camera.global_basis.z
		fixture.view_camera.size=.83
		fixture.view_camera.global_position=center+direction*7
		fixture.view_camera.look_at(center)
		_apply(player.recovered_avatar,"new",false,true)
		for mesh: MeshInstance3D in player.recovered_avatar.find_children("*","MeshInstance3D",true,false):
			mesh.visible=str(mesh.name)=="ArmorHead_%02d"%id
		await _capture("visor_front_color")
		var head:=player.recovered_avatar.find_child("ArmorHead_%02d"%id,true,false) as MeshInstance3D
		var mask_material:=StandardMaterial3D.new()
		mask_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mask_material.albedo_color=Color.WHITE
		head.material_override=mask_material
		await _capture("visor_front_mask")
		var report:=FileAccess.open(OUT+"capture.json",FileAccess.WRITE)
		report.store_string(JSON.stringify({"runtime_scene_sha256":_hash(scene_path),"target_sha256":_hash(target_path),"canonical_diffuse_sha256_at_start":texture_sha256,"capture_sha256":capture_sha256,"files":files,"image_dimensions":dimensions,"renderer":RenderingServer.get_current_rendering_method(),"resource_mode":"normal_imported_resources","view":"orthographic front; whole ArmorHead mesh only, identical camera for painted and white silhouette passes","engine_arguments":OS.get_cmdline_args(),"save_unchanged":_hash(real_save)==before,"real_save_sha256_at_start":before,"real_save_sha256_at_end":_hash(real_save),"isolated_save_path_at_end":GameState.save_path,"save_change_first_capture":save_change_first_capture},"\t"))
		baseline.free();candidate.free();fixture.cleanup();GameState.save_path=real_save
		AudioDirector.stop_all_sfx()
		print("ARMOR_VISOR_COVERAGE_CAPTURE_PASS helmet-only white mask and actual canonical atlas")
		get_tree().quit(0 if _hash(real_save)==before else 1)
		return
	if "--head-preview" in OS.get_cmdline_user_args():
		for view: String in ["front","side","rear","quarter"]:
			_set_ortho(fixture.view_camera,view)
			var center:=Vector3(0,1.58,-.07)
			var direction:=fixture.view_camera.global_basis.z
			fixture.view_camera.size=.83
			fixture.view_camera.global_position=center+direction*7
			fixture.view_camera.look_at(center)
			for version: String in ["original","new"]:
				_apply(player.recovered_avatar,version,"--head-clay" in OS.get_cmdline_user_args(),true)
				await _capture("%s_head_%s"%[version,view])
		var report:=FileAccess.open(OUT+"capture.json",FileAccess.WRITE)
		report.store_string(JSON.stringify({"candidate_scene_path":scene_path,"candidate_target_path":target_path,"preview_not_applied_to_gameplay":scene_path!=asset_path+slug+".scn","runtime_scene_sha256":_hash(scene_path),"target_sha256":_hash(target_path),"canonical_diffuse_sha256_at_start":texture_sha256,"capture_sha256":capture_sha256,"files":files,"image_dimensions":dimensions,"renderer":RenderingServer.get_current_rendering_method(),"resource_mode":"normal_imported_resources" if preview_textures.is_empty() else "raw_png_preview","view":"same original skeleton and fixed orthographic front/side/rear/quarter cameras","engine_arguments":OS.get_cmdline_args(),"save_unchanged":_hash(real_save)==before},"\t"))
		baseline.free();candidate.free();fixture.cleanup();GameState.save_path=real_save
		AudioDirector.stop_all_sfx()
		print("ARMOR_HEAD_PREVIEW_PASS %s / authored UV / files=%d save_unchanged=%s"%["normal imported resources" if preview_textures.is_empty() else "direct PNG",files.size(),str(_hash(real_save)==before)])
		get_tree().quit(0 if _hash(real_save)==before else 1)
		return
	for view: String in ["front","side","rear","quarter"]:
		_set_ortho(fixture.view_camera,view)
		for style: String in ["clay","painted","diffuse"]:
			for version: String in ["original","new"]:
				_apply(player.recovered_avatar,version,style=="clay",style=="diffuse")
				await _capture("%s_%s_%s"%[version,style,view])
	if "--geometry-review" in OS.get_cmdline_user_args() or "--face-review" in OS.get_cmdline_user_args():
		print("TANK_GEOMETRY_CAPTURE_PASS")
		baseline.free();candidate.free();fixture.cleanup();GameState.save_path=real_save
		get_tree().quit();return
	for view: String in ["front","side","rear","quarter"]:
		_set_ortho(fixture.view_camera,view)
		var center:=Vector3(0,1.58,-.07)
		var direction:=fixture.view_camera.global_basis.z
		fixture.view_camera.size=.83
		fixture.view_camera.global_position=center+direction*7
		fixture.view_camera.look_at(center)
		for version: String in ["original","new"]:
			_apply(player.recovered_avatar,version,false,true)
			await _capture("%s_head_%s"%[version,view])
	# Compare with the untouched neighbouring suits as well as old Tank.
	_set_ortho(fixture.view_camera,"front")
	for id: int in [1,6]:
		for part: MeshInstance3D in player.recovered_avatar.find_children("Armor*","MeshInstance3D",true,false):
			part.visible=str(part.name) in ["ArmorHead_%02d"%id,"ArmorBody_%02d"%id,"ArmorHand_%02d"%id,"ArmorFoot_%02d"%id]
			if not part.visible:continue
			var raw:=baseline.find_child(str(part.name),true,false) as MeshInstance3D
			part.mesh=raw.mesh;part.skin=raw.skin;part.transform=raw.transform
			part.material_override=null
			for sid: int in part.mesh.get_surface_count():
				var mat:=raw.get_active_material(sid).duplicate() as BaseMaterial3D
				mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color=Color.WHITE
				part.set_surface_override_material(sid,mat)
		await _capture("family_original_%02d_front"%id)
	player._apply_recovered_armor_visibility()
	for mesh in hidden:mesh.show()
	fixture.view_camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	fixture.set_view("front")
	for clip: String in ["idle_rifle","run_rifle"]:
		player._play_recovered_animation(clip,0,true)
		player.recovered_animation_player.seek(.30,true)
		player.recovered_skeleton.force_update_all_bone_transforms()
		for version: String in ["original","new"]:
			_apply(player.recovered_avatar,version,false)
			await _capture(version+"_"+clip)
	fixture.begin("gun00",0)
	for i: int in 9:
		fixture.advance_to(fixture.duration*float(i)/8.0)
		for version: String in ["original","new"]:
			_apply(player.recovered_avatar,version,false)
			await _capture("%s_reload_%02d"%[version,i])
	fixture.cleanup()
	fixture.free()
	await get_tree().process_frame
	capture_viewport.size=Vector2i(1280,720)
	GameState.selected_weapon="gun00"
	GameState.battle_weapons.assign(["gun00"])
	GameState.equipped_armor={"head":"armor_head_%02d"%id,"body":"armor_body_%02d"%id,"arms":"armor_arms_%02d"%id,"legs":"armor_legs_%02d"%id,"bag":"armor_bag_00"}
	GameState.settings.show_touch_controls=false
	GameState.settings.quality="high"
	for level: int in [1,8]:
		seed(1633)
		GameState.selected_level=level
		var world: WarfareGameWorld=(load("res://scenes/game.tscn") as PackedScene).instantiate()
		capture_viewport.add_child(world)
		world.completed=true
		world.player.set_physics_process(false)
		for frame: int in 12:await get_tree().process_frame
		for version: String in ["original","new"]:
			_apply(world.player.recovered_avatar,version,false)
			await _capture("%s_level_%02d_gameplay"%[version,level])
		world.hud.hide()
		var camera:=Camera3D.new()
		world.add_child(camera)
		camera.fov=40
		camera.global_position=world.player.global_position+Vector3(3.1,1.8,-3.4)
		camera.look_at(world.player.global_position+Vector3(0,1.05,0))
		camera.make_current()
		for version: String in ["original","new"]:
			_apply(world.player.recovered_avatar,version,false)
			await _capture("%s_level_%02d_front"%[version,level])
		world.free()
		AudioDirector.stop_all_sfx()
		await get_tree().process_frame
	baseline.free()
	candidate.free()
	var after_save_hash:=_hash(real_save)
	var isolated_save_path_at_end:=GameState.save_path
	var unchanged:=after_save_hash==before
	GameState.save_path=real_save
	var report:=FileAccess.open(OUT+"capture.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"runtime_scene_sha256":_hash(scene_path),"target_sha256":_hash(target_path),"scene_sha256_at_start":scene_sha256_at_start,"target_sha256_at_start":target_sha256_at_start,"canonical_diffuse_sha256_at_start":texture_sha256,"capture_sha256":capture_sha256,"engine_arguments":OS.get_cmdline_args(),"resource_mode":"normal_imported_resources" if preview_textures.is_empty() else "raw_png_preview","viewports":{"review":[640,720],"gameplay":[1280,720]},"image_dimensions":dimensions,"renderer":RenderingServer.get_current_rendering_method(),"files":files,"save_unchanged":unchanged,"real_save_path":real_save,"real_save_sha256_at_start":before,"real_save_sha256_at_end":after_save_hash,"isolated_save_path_at_end":isolated_save_path_at_end,"save_change_first_capture":save_change_first_capture,"full_body_framing":framing,"note":"One current configured armor model for all views; each full-body camera fits the original and candidate posed vertices together with KEEP_HEIGHT and a shared margin. Original raw mesh/skin preserved for comparison. Poses use actual player and reload fixture; two real levels also captured.","diffuse_views":"White material tint for both versions, so original painted greys can be compared without the original material tint. Painted views retain original imported tint. This affects captures only, not source assets or gameplay defaults."},"\t"))
	print("ARMOR_CAPTURE_%s files=%d save_unchanged=%s"%["PASS" if unchanged else "FAIL",files.size(),str(unchanged)])
	get_tree().quit(0 if unchanged else 1)

func _apply(avatar: Node3D, version: String, clay: bool, neutral: bool=false) -> void:
	var source:=baseline if version=="original" else candidate
	for name_key: String in NAMES:
		var target:=avatar.find_child(name_key,true,false) as MeshInstance3D
		var part:=source.find_child(name_key,true,false) as MeshInstance3D
		target.mesh=part.mesh;target.skin=part.skin;target.transform=part.transform
		target.material_override=null
		for sid: int in target.get_surface_override_material_count():target.set_surface_override_material(sid,null)
		if clay:
			var material:=StandardMaterial3D.new()
			material.albedo_color=Color(.35,.35,.35)
			material.roughness=1
			material.cull_mode=BaseMaterial3D.CULL_DISABLED
			target.material_override=material
		elif version=="new" and "--direct-textures" in OS.get_cmdline_user_args():
			for sid: int in target.mesh.get_surface_count():
				var mat:=part.get_active_material(sid).duplicate() as BaseMaterial3D
				var label: String=LABELS[name_key][sid]
				mat.albedo_texture=preview_textures[label]
				target.set_surface_override_material(sid,mat)
		elif version=="original":
			for sid: int in target.mesh.get_surface_count():
				var material:=part.get_active_material(sid).duplicate() as BaseMaterial3D
				material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				if neutral:material.albedo_color=Color.WHITE
				target.set_surface_override_material(sid,material)

func _texture_path(label: String) -> String:
	return asset_path + str(config.get("texture_files", {}).get(label, label + "_diffuse.png"))

func _set_ortho(camera: Camera3D, view: String) -> void:
	var directions:={"front":Vector3(0,0,-1),"side":Vector3(1,0,0),"rear":Vector3(0,0,1),"quarter":Vector3(.55,.15,-1)}
	var center:=Vector3(0,1.04,0)
	if not review_points.is_empty():
		var world_bounds:=AABB(review_points[0],Vector3.ZERO)
		for point: Vector3 in review_points:world_bounds=world_bounds.expand(point)
		center=world_bounds.get_center()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.size=2.35
	camera.global_position=center+directions[view].normalized()*7
	camera.look_at(center)
	if review_points.is_empty():return
	var to_camera:=camera.global_transform.affine_inverse()
	var first_point:=to_camera*review_points[0]
	var projected:=Rect2(Vector2(first_point.x,first_point.y),Vector2.ZERO)
	for point: Vector3 in review_points:
		var local:=to_camera*point
		projected=projected.expand(Vector2(local.x,local.y))
	# Center the screen-space bounds, then retain at least 6% on every side.
	var offset:=projected.get_center()
	center+=camera.global_basis.x*offset.x+camera.global_basis.y*offset.y
	camera.global_position=center+directions[view].normalized()*7
	camera.look_at(center)
	var aspect:=float(capture_viewport.size.x)/float(capture_viewport.size.y)
	camera.size=maxf(2.35,maxf(projected.size.y,projected.size.x/aspect)/.88)
	var screen_bounds:=Rect2(camera.unproject_position(review_points[0]),Vector2.ZERO)
	for point: Vector3 in review_points:screen_bounds=screen_bounds.expand(camera.unproject_position(point))
	assert(screen_bounds.position.x>=12 and screen_bounds.position.y>=12 and screen_bounds.end.x<=capture_viewport.size.x-12 and screen_bounds.end.y<=capture_viewport.size.y-12,"Full-body capture clips an armor vertex")
	framing[view]={"orthographic_size":camera.size,"keep_aspect":"KEEP_HEIGHT","center":[center.x,center.y,center.z],"projected_bounds_px":{"min":[screen_bounds.position.x,screen_bounds.position.y],"max":[screen_bounds.end.x,screen_bounds.end.y]},"same_camera_for_original_and_new":true}

func _posed_points(part: MeshInstance3D, skeleton: Skeleton3D) -> Array[Vector3]:
	var transforms: Array[Transform3D]=[]
	for bind: int in part.skin.get_bind_count():
		var bone:=skeleton.find_bone(part.skin.get_bind_name(bind))
		transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*part.skin.get_bind_pose(bind))
	var result: Array[Vector3]=[]
	for sid: int in part.mesh.get_surface_count():
		var arrays:=part.mesh.surface_get_arrays(sid)
		for index: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point:=Vector3.ZERO
			for influence: int in 4:
				var offset:=index*4+influence
				point+=(transforms[arrays[Mesh.ARRAY_BONES][offset]]*arrays[Mesh.ARRAY_VERTEX][index])*arrays[Mesh.ARRAY_WEIGHTS][offset]
			result.append(point)
	return result

func _capture(name_key: String) -> void:
	if save_change_first_capture.is_empty() and _hash(monitored_save_path)!=monitored_save_sha256:
		save_change_first_capture=name_key
		print("ARMOR_CAPTURE_SAVE_CHANGED boundary=%s isolated=%s"%[name_key,GameState.save_path])
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var path:=OUT+name_key+".png"
	var image:=capture_viewport.get_texture().get_image()
	assert(image.save_png(path)==OK)
	capture_sha256[path] = _hash(path)
	dimensions[path]=[image.get_width(),image.get_height()]
	files.append(path)

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
