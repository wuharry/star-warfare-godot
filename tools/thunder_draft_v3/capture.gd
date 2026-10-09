extends Node3D

const Contract = preload("res://tools/thunder_draft_v3/contract.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const CONFIG := "res://docs/art/thunder_draft_v3/runtime_config.json"
const NAMES := ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"]
const SIZE := Vector2i(800, 960)
const DIRECTIONS := {"front": Vector3(0, 0, -1), "side": Vector3(1, 0, 0), "rear": Vector3(0, 0, 1), "quarter": Vector3(0.55, 0.15, -1)}

var config: Dictionary = {}
var sources: Dictionary = {}
var versions: Array[String] = ["original", "before", "new"]
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var framing: Dictionary = {}
var resource_hashes: Dictionary = {}
var files: Array[String] = []
var capture_hashes: Dictionary = {}
var dimensions: Dictionary = {}
var output := ""
var real_save := ""
var real_save_hash := ""
var scene_hash := ""
var native_png_hash := ""
var target_hash := ""
var head_metrics: Dictionary = {}
var viewport: SubViewport
var fixture: Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	failures.append_array(Contract.check_pins(config))
	if not failures.is_empty():
		_finish()
		return
	output = str(config.work) + "review/engine/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	failures.append_array(Contract.check_pins(config, true))
	if not failures.is_empty():
		_finish()
		return
	var target: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(config.head_target)))
	target_hash = _hash(str(config.head_target))
	sources.original = (load(str(config.source_scene)) as PackedScene).instantiate() as Node3D
	sources.new = (load(str(config.output_scene)) as PackedScene).instantiate() as Node3D
	failures.append_array(Contract.compare_head(sources.original.find_child(str(config.head_node), true, false), sources.new.find_child(str(config.head_node), true, false), target))
	if not failures.is_empty():
		_finish()
		return
	if "before" in versions:
		sources.before = (load(str(config.before_scene)) as PackedScene).instantiate() as Node3D
		for part_name: String in config.inherited_body_nodes:
			failures.append_array(Contract.compare_part(sources.before.find_child(part_name, true, false), sources.new.find_child(part_name, true, false)))
	var original_head := sources.original.find_child(str(config.head_node), true, false) as MeshInstance3D
	head_metrics = Contract.geometry_report(original_head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], Contract.target_points(target), original_head.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX])
	if not failures.is_empty():
		_finish()
		return
	scene_hash = FileAccess.get_sha256(str(config.output_scene))
	native_png_hash = FileAccess.get_sha256(str(config.native_generated_png))
	for path: String in [str(config.output_scene), str(config.portable_texture), str(config.native_generated_png), str(config.source_scene), str(config.source_buffer), str(config.before_scene), str(config.head_target), str(config.head_source_json), str(config.before_snapshot)]:
		resource_hashes[path] = FileAccess.get_sha256(path)
	for path: String in config.inherited_body_resource_sha256:
		resource_hashes[path] = FileAccess.get_sha256(path)
	real_save = GameState.save_path
	real_save_hash = _hash(real_save)
	GameState.save_path = "user://thunder_draft_v3_capture_profile.json"
	GameState.settings.quality = "high"
	GameState.settings.show_touch_controls = false
	get_window().size = Vector2i(500, 600)
	get_window().title = "Thunder draft v3: original / frozen 3ed / new"
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	fixture = Fixture.new()
	viewport.add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://thunder_draft_v3_capture_profile.json"
	_equip()
	fixture.player._apply_recovered_armor_visibility()
	_check_live_default(fixture.player)
	fixture.label.hide()
	fixture.player.set_process_unhandled_input(false)
	fixture.player.backpack_socket.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child: Node in fixture.get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color(0.065, 0.075, 0.085)
			child.environment.ambient_light_energy = 0.8
		elif child is DirectionalLight3D:
			child.light_energy = 1.0
			child.shadow_enabled = true
	fixture.fill.light_energy = 0.6
	_pose("idle")
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(200, 200)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.31, 0.33, 0.35)
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	fixture.add_child(ground)
	var lowest := 1.0e10
	for version: String in versions:
		for point: Vector3 in _source_points(version, fixture.player, false):
			lowest = minf(lowest, point.y)
	ground.position.y = lowest - 0.005
	# Thirteen controlled pairs plus two live-level pairs. Each controlled pair
	# uses one camera fitted to the union of all versions' posed vertices.
	for view: String in ["front", "side", "rear", "quarter"]:
		await _studio_pair("full_" + view, view, false, false, "idle")
	for view: String in ["front", "side", "rear", "quarter"]:
		await _studio_pair("head_" + view, view, true, false, "idle")
	for view: String in ["front", "side"]:
		await _studio_pair("clay_" + view, view, false, true, "idle")
	await _studio_pair("idle", "quarter", false, false, "idle_armed")
	await _studio_pair("run", "quarter", false, false, "run")
	await _studio_pair("reload", "quarter", false, false, "reload")
	fixture.cleanup()
	fixture.queue_free()
	viewport.queue_free()
	await get_tree().process_frame
	await _game_pairs()
	_finish()


func _studio_pair(key: String, view: String, head_only: bool, clay: bool, pose: String) -> void:
	_pose(pose)
	_fit(fixture.view_camera, fixture.player, view, head_only, key)
	for version: String in versions:
		_apply(fixture.player, version, clay)
		await _save(version + "_" + key, version, key, pose, viewport)


func _pose(pose: String) -> void:
	var player: WarfarePlayer = fixture.player
	player._cancel_reload()
	player.recovered_animation_tree.active = false
	player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if pose == "reload":
		fixture.begin("gun00", 0, true)
		fixture.advance_to(fixture.duration * 0.52)
	else:
		player.recovered_animation_player.play("run_rifle" if pose == "run" else "idle_rifle")
		player.recovered_animation_player.seek(0.2 if pose == "run" else 0.0, true)
		player.recovered_skeleton.force_update_all_bone_transforms()
	var armed := pose in ["idle_armed", "run", "reload"]
	player.gun_socket.visible = armed
	player.left_gun_socket.visible = armed


func _apply(player: WarfarePlayer, version: String, clay: bool) -> void:
	var source: Node3D = sources[version]
	for name_key: String in NAMES:
		var part := source.find_child(name_key, true, false) as MeshInstance3D
		var target := player.recovered_avatar.find_child(name_key, true, false) as MeshInstance3D
		target.mesh = part.mesh
		target.skin = part.skin
		target.transform = part.transform
		target.material_override = null
		for sid: int in target.get_surface_override_material_count():
			target.set_surface_override_material(sid, null)
		if clay:
			var neutral := StandardMaterial3D.new()
			neutral.albedo_color = Color(0.43, 0.43, 0.43)
			neutral.roughness = 1.0
			neutral.cull_mode = BaseMaterial3D.CULL_DISABLED
			target.material_override = neutral
		elif version == "original":
			# Restore recovered Unity's unlit diffuse behavior on original glTF
			# materials only. Preserve its original tint and imported textures.
			for sid: int in target.mesh.get_surface_count():
				var painted := part.get_active_material(sid).duplicate() as BaseMaterial3D
				painted.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				target.set_surface_override_material(sid, painted)
		elif version == "new":
			for sid: int in target.mesh.get_surface_count():
				if target.get_active_material(sid) != part.get_active_material(sid):
					failures.append("New capture changed authored material " + name_key)


func _source_points(version: String, player: WarfarePlayer, head_only: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var source: Node3D = sources[version]
	var skeleton := player.recovered_skeleton
	for name_key: String in NAMES:
		if head_only and name_key != "ArmorHead_06":
			continue
		var part := source.find_child(name_key, true, false) as MeshInstance3D
		var transforms: Array[Transform3D] = []
		for bind: int in part.skin.get_bind_count():
			var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
			transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
		for sid: int in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(sid)
			for vertex: int in arrays[Mesh.ARRAY_VERTEX].size():
				var point := Vector3.ZERO
				for influence: int in 4:
					var offset := vertex * 4 + influence
					point += (transforms[arrays[Mesh.ARRAY_BONES][offset]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * arrays[Mesh.ARRAY_WEIGHTS][offset]
				result.append(point)
	return result


func _fit(camera: Camera3D, player: WarfarePlayer, view: String, head_only: bool, frame_key: String) -> void:
	var points: Array[Vector3] = []
	for version: String in versions:
		points.append_array(_source_points(version, player, head_only))
	var world_bounds := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		world_bounds = world_bounds.expand(point)
	var center := world_bounds.get_center()
	var direction: Vector3 = DIRECTIONS[view]
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.global_position = center + direction.normalized() * 7.0
	camera.look_at(center)
	var to_camera := camera.global_transform.affine_inverse()
	var local: Vector3 = to_camera * points[0]
	var projected := Rect2(Vector2(local.x, local.y), Vector2.ZERO)
	for point: Vector3 in points:
		local = to_camera * point
		projected = projected.expand(Vector2(local.x, local.y))
	var offset := projected.get_center()
	center += camera.global_basis.x * offset.x + camera.global_basis.y * offset.y
	camera.global_position = center + direction.normalized() * 7.0
	camera.look_at(center)
	var aspect := float(viewport.size.x) / float(viewport.size.y)
	camera.size = maxf(0.2, maxf(projected.size.y, projected.size.x / aspect) / 0.85)
	var screen := Rect2(camera.unproject_position(points[0]), Vector2.ZERO)
	for point: Vector3 in points:
		screen = screen.expand(camera.unproject_position(point))
	if screen.position.x < 12 or screen.position.y < 12 or screen.end.x > viewport.size.x - 12 or screen.end.y > viewport.size.y - 12:
		failures.append("Shared camera clips compared geometry: " + frame_key)
	framing[frame_key] = {"same_camera_for_original_and_new": true, "includes_before": "before" in versions, "includes_original_high_crest": true, "orthographic_size": camera.size, "center": [center.x, center.y, center.z], "projected_min_px": [screen.position.x, screen.position.y], "projected_max_px": [screen.end.x, screen.end.y], "head_only": head_only}
	fixture.fill.global_position = camera.global_position


func _game_pairs() -> void:
	var game_view := SubViewport.new()
	game_view.size = Vector2i(1280, 720)
	game_view.own_world_3d = true
	game_view.msaa_3d = Viewport.MSAA_4X
	game_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(game_view)
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	for level: int in [1, 3]:
		_equip()
		GameState.selected_level = level
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		game_view.add_child(world)
		for tick: int in 15:
			await get_tree().process_frame
		_check_live_default(world.player)
		world.player.set_physics_process(false)
		world.player.set_process_unhandled_input(false)
		world.player.recovered_animation_tree.active = false
		world.player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		world.player.recovered_skeleton.force_update_all_bone_transforms()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		for version: String in versions:
			_apply(world.player, version, false)
			await _save(version + "_game_level_%d" % level, version, "game_level_%d" % level, "live_game", game_view)
		world.queue_free()
		await get_tree().process_frame
	game_view.queue_free()
	await get_tree().process_frame


func _check_live_default(player: WarfarePlayer) -> void:
	var source: Node3D = sources.new
	for name_key: String in NAMES:
		var authored := source.find_child(name_key, true, false) as MeshInstance3D
		var actual := player.recovered_avatar.find_child(name_key, true, false) as MeshInstance3D
		if actual == null or not actual.visible or actual.mesh != authored.mesh or actual.skin != authored.skin:
			failures.append("Live default loader did not equip authored mesh/Skin: " + name_key)
			continue
		for sid: int in authored.mesh.get_surface_count():
			if actual.get_active_material(sid) != authored.get_active_material(sid):
				failures.append("Live default loader overrides authored material: " + name_key)


func _save(name_key: String, version: String, key: String, pose: String, source_view: SubViewport) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := source_view.get_texture().get_image()
	var path := output + name_key + ".png"
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append("Cannot save capture " + name_key)
		return
	if _hash(real_save) != real_save_hash:
		failures.append("Real save changed while capturing " + name_key)
	files.append(path)
	capture_hashes[path] = FileAccess.get_sha256(path)
	dimensions[path] = [image.get_width(), image.get_height()]
	frames.append({"file": name_key + ".png", "sha256": capture_hashes[path], "version": version, "view": key, "pose": pose, "width": image.get_width(), "height": image.get_height(), "controlled_pair": pose != "live_game"})


func _equip() -> void:
	GameState.equipped_armor = {"head": "armor_head_06", "body": "armor_body_06", "arms": "armor_arms_06", "legs": "armor_legs_06", "bag": "armor_bag_00"}


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"


func _finish() -> void:
	if not output.is_empty() and files.size() != versions.size() * 15:
		failures.append("Expected %d complete frames, captured %d" % [versions.size() * 15, files.size()])
	if not real_save.is_empty() and _hash(real_save) != real_save_hash:
		failures.append("Real user save changed during capture")
	for path: String in resource_hashes:
		if FileAccess.get_sha256(path) != str(resource_hashes[path]):
			failures.append("Source/runtime resource changed during capture: " + path)
	if not output.is_empty():
		var report := {
			"status": "CAPTURED_REQUIRES_VISUAL_REVIEW" if failures.is_empty() else "FAIL", "errors": failures,
			"revision": config.revision, "versions": versions, "paired_view_count": 15, "files": files,
			"runtime_scene_sha256": scene_hash, "default_scene_sha256": scene_hash,
			"native_png_sha256": native_png_hash, "portable_texture_sha256": _hash(str(config.portable_texture)),
			"before_scene_sha256": config.before_scene_sha256, "target_sha256": target_hash, "head_contract": head_metrics,
			"body_baseline_commit": config.body_baseline_commit,
			"original_scene_sha256": config.source_scene_sha256, "original_buffer_sha256": config.source_buffer_sha256,
			"runtime_loader": "WarfarePlayer._apply_recovered_armor_visibility",
			"resource_mode": "normal_imported_resources", "renderer": RenderingServer.get_current_rendering_method(),
			"engine_arguments": OS.get_cmdline_args(), "runtime_resource_sha256": resource_hashes,
			"capture_sha256": capture_hashes, "image_dimensions": dimensions, "frames": frames, "framing": framing,
			"viewports": {"studio": [SIZE.x, SIZE.y], "gameplay": [1280, 720]},
			"save_unchanged": _hash(real_save) == real_save_hash, "real_save_sha256_at_start": real_save_hash, "real_save_sha256_at_end": _hash(real_save),
			"original_scope": "True original SW1 player.gltf four parts; original diffuse receives the existing Unity unlit behavior and retains original imported tint/texture. No rewritten SW2 head is used as the original.",
			"new_scope": "Actual default draft-v3 head bounded to true original SW1 geometry; three body/limb parts exactly inherit frozen 3ed1c291. No whole-suit original percentage, capture-only repaint or direct-PNG material substitution.",
			"live_game_limits": "Two sequential views of each single live world. Player pose/camera are frozen for the pair; NPCs, particles and clocks may still change, so these are readability checks, not pixel-level whole-scene comparisons.",
			"clay_scope": "Neutral material override in the two named clay views only; geometry remains the actual model. All other new views use authored runtime materials."
		}
		var file := FileAccess.open(output + "capture.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	for version: String in sources:
		(sources[version] as Node3D).free()
	if not real_save.is_empty():
		GameState.save_path = real_save
	AudioDirector.stop_all_sfx()
	for error: String in failures:
		push_error(error)
	print("THUNDER_DRAFT_V3_CAPTURE_%s images=%d save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", files.size(), str(not real_save.is_empty() and _hash(real_save) == real_save_hash)])
	get_tree().quit(0 if failures.is_empty() else 1)
