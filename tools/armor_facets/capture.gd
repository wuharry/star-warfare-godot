extends Node3D

const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const OUT := "res://test_output/armor_facets/"
const SIZE := Vector2i(900, 1100)
const VIEWS := {"front": Vector3(0, 0.12, -6), "three_quarter": Vector3(3.5, 0.3, -6), "side": Vector3(6, 0.12, 0), "rear": Vector3(0, 0.12, 6)}

var fixture: Node3D
var viewport: SubViewport
var baseline := false
var records: Array[Dictionary] = []
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array[int] = []
	for id: int in Catalog.SET_NAMES.size():
		ids.append(id)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--baseline":
			baseline = true
		if argument.begins_with("--ids="):
			ids.clear()
			for value: String in argument.trim_prefix("--ids=").split(","):
				if not value.is_valid_int() or int(value) < 0 or int(value) >= Catalog.SET_NAMES.size():
					_fail("Invalid armor id: " + value)
				else:
					ids.append(int(value))
	if not failures.is_empty():
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		_fail("Capture requires a real renderer; remove --headless")
		get_tree().quit(1)
		return
	var real_save := GameState.save_path
	var save_hash := _hash(real_save)
	GameState.save_path = "user://armor_facets_capture_profile.json"
	GameState.settings.quality = "high"
	GameState.settings.show_touch_controls = false
	get_window().size = Vector2i(420, 514)
	get_window().title = "Angular armor — runtime capture"
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	fixture = Fixture.new()
	viewport.add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://armor_facets_capture_profile.json"
	fixture.label.hide()
	fixture.player.set_process_unhandled_input(false)
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.fill.light_energy = 0.55
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child: Node in fixture.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 1.1
		elif child is WorldEnvironment:
			child.environment.background_color = Color(0.13, 0.15, 0.18)
			child.environment.ambient_light_energy = 0.65
	for id: int in ids:
		await _capture_set(id)
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--gameplay") and not baseline:
		await _capture_levels()
	if _hash(real_save) != save_hash:
		_fail("Real player save changed during capture")
	var version := "baseline" if baseline else "current"
	var record := {"version": version, "status": "CAPTURED_REQUIRES_VISUAL_REVIEW" if failures.is_empty() else "FAIL", "renderer": RenderingServer.get_current_rendering_method(), "viewport": [SIZE.x, SIZE.y], "ids": ids, "save_unchanged": _hash(real_save) == save_hash, "captures": records, "failures": failures}
	_write(OUT + version + "/capture.json", record)
	print("ANGULAR_CAPTURE_%s version=%s sets=%d frames=%d" % ["PASS" if failures.is_empty() else "FAIL", version, ids.size(), records.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture_set(id: int) -> void:
	fixture.player._cancel_reload()
	for debris: Node in get_tree().get_nodes_in_group("reload_debris"):
		debris.free()
	for index: int in 4:
		GameState.equipped_armor[Catalog.PART_KEYS[index]] = Catalog.item_key(index, id)
	fixture.player._apply_recovered_armor_visibility()
	var source_path := Visuals.reworked_scene_path(id)
	if baseline and id != 6:
		source_path = "res://assets/armors/viper/viper.scn" if id == 0 else "res://assets/equipment_refined/armors/armor_%02d.scn" % id
		var source := (load(source_path) as PackedScene).instantiate()
		for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
			var part_name := prefix + "%02d" % id
			var part := fixture.player.recovered_avatar.find_child(part_name, true, false) as MeshInstance3D
			var original := source.find_child(part_name, true, false) as MeshInstance3D
			part.material_override = null
			for surface: int in part.get_surface_override_material_count():
				part.set_surface_override_material(surface, null)
			part.mesh = original.mesh
			part.skin = original.skin
			part.transform = original.transform
		source.free()
	fixture.player._cancel_reload()
	fixture.player.recovered_animation_tree.active = false
	fixture.player._play_recovered_animation("idle_rifle", 0, true)
	fixture.player.recovered_animation_player.advance(0)
	fixture.player.recovered_skeleton.clear_bones_global_pose_override()
	fixture.player.recovered_skeleton.force_update_all_bone_transforms()
	fixture.player.backpack_socket.hide()
	fixture.player.gun_socket.hide()
	fixture.player.left_gun_socket.hide()
	var bounds := AABB(Vector3(-0.7, 0, -0.5), Vector3(1.4, 2.0, 1.0))
	var first := true
	var count := 0
	for part: MeshInstance3D in fixture.player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if not part.visible:
			continue
		count += 1
		if not str(part.name).ends_with("_%02d" % id):
			_fail("Wrong visible armor: " + str(part.name))
		var posed := _posed_bounds(part, fixture.player.recovered_skeleton)
		bounds = posed if first else bounds.merge(posed)
		first = false
	if count != 4:
		_fail("Expected four parts for armor %d, got %d" % [id, count])
	for view: String in VIEWS:
		_frame(bounds, view)
		await _save(id, view, source_path)
	if id in [0, 6, 9, 21, 28]:
		fixture.player.equip_weapon("gun00", false)
		fixture.player.gun_socket.show()
		fixture.player.backpack_socket.show()
		_frame(bounds, "three_quarter")
		await _save(id, "armed", source_path)
		fixture.begin("gun00", 0)
		fixture.advance_to(fixture.duration * 0.5)
		await _save(id, "reload", source_path)
	print("ANGULAR_CAPTURED id=%02d baseline=%s" % [id, str(baseline)])


func _frame(bounds: AABB, view: String) -> void:
	var center: Vector3 = fixture.player.global_transform * bounds.get_center()
	fixture.view_camera.size = maxf(bounds.size.y * 1.18, maxf(bounds.size.x, bounds.size.z) * float(SIZE.y) / float(SIZE.x) * 1.18)
	fixture.view_camera.position = center + VIEWS[view]
	fixture.view_camera.look_at(center)
	fixture.fill.position = center + Vector3(-2, 2, -3)


func _capture_levels() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	for sample: Array in [[0, 1], [9, 3], [21, 1], [28, 3]]:
		var id: int = sample[0]
		GameState.selected_level = int(sample[1])
		for part: int in 4:
			GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, id)
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		viewport.add_child(world)
		for frame: int in 15:
			await get_tree().process_frame
		world.player.set_process_unhandled_input(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await _save(id, "level_%d_game" % int(sample[1]), Visuals.reworked_scene_path(id))
		world.player.set_physics_process(false)
		var inspection := Camera3D.new()
		inspection.fov = 48
		world.add_child(inspection)
		var center: Vector3 = world.player.global_position + Vector3(0, 1.1, 0)
		inspection.global_position = center + world.player.model.global_basis * Vector3(2.2, .45, -3.4)
		inspection.look_at(center)
		inspection.current = true
		await _save(id, "level_%d_inspection" % int(sample[1]), Visuals.reworked_scene_path(id))
		world.queue_free()
		await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame


func _save(id: int, view: String, source_path: String) -> void:
	# macOS may stop ordinary window presentation while Codex is foreground.
	# Force the offscreen viewport instead of waiting for frame_post_draw.
	for frame: int in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false, 0.0)
	var image := viewport.get_texture().get_image()
	var version := "baseline" if baseline else "current"
	var path := OUT + "%s/armor_%02d_%s.png" % [version, id, view]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if image == null or image.is_empty() or image.save_png(ProjectSettings.globalize_path(path)) != OK:
		_fail("Could not save " + path)
		return
	records.append({"id": id, "view": view, "image": path, "size": [image.get_width(), image.get_height()], "scene": source_path, "scene_sha256": _hash(source_path)})


func _posed_bounds(part: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var transforms: Array[Transform3D] = []
	for bind: int in part.skin.get_bind_count():
		var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
		transforms.append(skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
	var result := AABB()
	var started := false
	for surface: int in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		for vertex: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for influence: int in 4:
				var index := vertex * 4 + influence
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][index]
				if weight > 0:
					point += (transforms[arrays[Mesh.ARRAY_BONES][index]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * weight
			result = result.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return result


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"


func _write(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
