extends Node3D

const Fixture=preload("res://tests/reload_catalog_fixture.gd")
var OUT:="res://docs/art/viper_runtime_v2/review/engine/"
const NAMES:=["ArmorHead_00","ArmorBody_00","ArmorHand_00","ArmorFoot_00"]
var baseline: Node3D
var candidate: Node3D
var files: Array[String]=[]
var dimensions: Dictionary={}
var capture_viewport: SubViewport
var review_points: Array[Vector3]=[]
var framing: Dictionary={}
var texture_sha256: Dictionary={}
var model_sha256 := ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--baseline-only" in OS.get_cmdline_user_args():OUT="res://docs/art/viper_runtime_v2/review/baseline/"
	if "--geometry-review" in OS.get_cmdline_user_args():OUT="res://docs/art/viper_runtime_v2/review/pretexture/"
	if "--face-review" in OS.get_cmdline_user_args():OUT="res://docs/art/viper_runtime_v2/review/face_geometry/"
	for label: String in ["head", "body", "shoulder", "hand", "foot"]:
		texture_sha256[label] = FileAccess.get_sha256("res://assets/armors/viper_v2/" + label + "_diffuse.png")
	model_sha256 = FileAccess.get_sha256("res://assets/armors/viper_v2/viper.scn")
	get_tree().root.size=Vector2i(640,720)
	capture_viewport=SubViewport.new()
	capture_viewport.size=Vector2i(640,720)
	capture_viewport.own_world_3d=true
	capture_viewport.msaa_3d=Viewport.MSAA_4X
	capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(capture_viewport)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var real_save:=GameState.save_path
	var before:=_hash(real_save)
	GameState.save_path="user://viper_v2_capture_profile.json"
	baseline=(load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	candidate=baseline.duplicate() if "--baseline-only" in OS.get_cmdline_user_args() else (load("res://assets/armors/viper_v2/viper.scn") as PackedScene).instantiate()
	var fixture:=Fixture.new()
	capture_viewport.add_child(fixture)
	fixture.setup()
	GameState.save_path="user://viper_v2_capture_profile.json"
	GameState.equipped_armor={"head":"armor_head_00","body":"armor_body_00","arms":"armor_arms_00","legs":"armor_legs_00","bag":"armor_bag_00"}
	fixture.player._apply_recovered_armor_visibility()
	fixture.label.hide()
	var player: WarfarePlayer=fixture.player
	player.recovered_animation_tree.active=false
	player.recovered_animation_player.stop()
	player.recovered_skeleton.reset_bone_poses()
	player.recovered_skeleton.force_update_all_bone_transforms()
	var hidden: Array[MeshInstance3D]=[]
	for mesh: MeshInstance3D in player.recovered_avatar.find_children("*","MeshInstance3D",true,false):
		if not str(mesh.name).begins_with("Armor") and mesh.visible:
			hidden.append(mesh);mesh.hide()
	# Fit both cages together, using the actual fixture skeleton in world space.
	# Import bounds alone omit the parent transform and the current skin pose.
	for source: Node3D in [baseline,candidate]:
		for name_key: String in NAMES:
			review_points.append_array(_posed_points(source.find_child(name_key,true,false) as MeshInstance3D,player.recovered_skeleton))
	if "--check-framing" in OS.get_cmdline_user_args():
		for view: String in ["front","side","rear","quarter"]:
			_set_ortho(fixture.view_camera,view)
		print("VIPER_FRAMING_PASS "+JSON.stringify(framing))
		baseline.free();candidate.free();fixture.cleanup();GameState.save_path=real_save
		get_tree().quit();return
	for view: String in ["front","side","rear","quarter"]:
		_set_ortho(fixture.view_camera,view)
		for style: String in ["clay","painted","diffuse"]:
			for version: String in ["original","new"]:
				_apply(player.recovered_avatar,version,style=="clay",style=="diffuse")
				await _capture("%s_%s_%s"%[version,style,view])
	if "--geometry-review" in OS.get_cmdline_user_args() or "--face-review" in OS.get_cmdline_user_args():
		print("VIPER_GEOMETRY_CAPTURE_PASS")
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
	# Compare with the untouched neighbouring suits as well as old Viper.
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
	GameState.equipped_armor={"head":"armor_head_00","body":"armor_body_00","arms":"armor_arms_00","legs":"armor_legs_00","bag":"armor_bag_00"}
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
	var unchanged:=_hash(real_save)==before
	GameState.save_path=real_save
	var report:=FileAccess.open(OUT+"capture.json",FileAccess.WRITE)
	var file_sha256: Dictionary={}
	for filename: String in files:file_sha256[filename] = FileAccess.get_sha256(filename)
	report.store_string(JSON.stringify({"viewports":{"review":[640,720],"gameplay":[1280,720]},"image_dimensions":dimensions,"renderer":RenderingServer.get_current_rendering_method(),"configured_windows_driver":ProjectSettings.get_setting("rendering/gl_compatibility/driver.windows"),"runtime_scene_sha256":model_sha256,"texture_sha256":texture_sha256,"file_sha256":file_sha256,"files":files,"save_unchanged":unchanged,"full_body_framing":framing,"note":"One new model for all views; each full-body camera fits the original and candidate posed vertices together with KEEP_HEIGHT and a shared margin. Original raw mesh/skin preserved for comparison. Poses use actual player and reload fixture; two real levels also captured. Actual rendering driver/device is recorded in the capture execution stdout, configured_windows_driver is configuration only.","diffuse_views":"White material tint for both versions, so original painted greys can be compared without the glTF pink head tint. Painted views retain original imported tint. This affects captures only, not source assets or gameplay defaults."},"\t"))
	print("VIPER_CAPTURE_%s files=%d save_unchanged=%s"%["PASS" if unchanged else "FAIL",files.size(),str(unchanged)])
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
		elif version=="original":
			for sid: int in target.mesh.get_surface_count():
				var material:=part.get_active_material(sid).duplicate() as BaseMaterial3D
				material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				if neutral:material.albedo_color=Color.WHITE
				target.set_surface_override_material(sid,material)

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
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var path:=OUT+name_key+".png"
	var image:=capture_viewport.get_texture().get_image()
	assert(image.save_png(path)==OK)
	dimensions[path]=[image.get_width(),image.get_height()]
	files.append(path)

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
