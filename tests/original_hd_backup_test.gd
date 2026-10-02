extends Node3D

const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("ORIGINAL_HD_BACKUP: " + message)

func _triangles(mesh: Mesh, sid: int) -> Array[String]:
	# HD refinement splits vertices at hard normals. Compare the actual
	# triangle corners, including UVs, rather than storage vertex count.
	var arrays := mesh.surface_get_arrays(sid)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		for i: int in points.size():
			indices.append(i)
	var result: Array[String] = []
	for offset: int in range(0, indices.size(), 3):
		var corners: Array[String] = []
		for j: int in 3:
			var i := indices[offset + j]
			corners.append("%.5f,%.5f,%.5f/%.5f,%.5f" % [points[i].x, points[i].y, points[i].z, uvs[i].x, uvs[i].y])
		corners.sort()
		result.append("|".join(corners))
	result.sort()
	return result

func _run() -> void:
	var real_save := GameState.save_path
	var before := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "absent"
	GameState.save_path = "user://original_hd_backup_test_profile.json"
	var capture := "--capture" in OS.get_cmdline_user_args()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var fixture := Fixture.new()
	viewport.add_child(fixture)
	fixture.setup()
	fixture.label.hide()
	fixture.player.backpack_socket.hide()
	fixture.player.gun_socket.hide()
	fixture.player.left_gun_socket.hide()
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.view_camera.size = 2.35
	fixture.view_camera.position = Vector3(0, 1.1, -6)
	fixture.view_camera.look_at(Vector3(0, 1.04, 0), Vector3.UP)
	fixture.player.recovered_animation_tree.active = false
	fixture.player.recovered_animation_player.stop()
	fixture.player.recovered_skeleton.reset_bone_poses()
	var source := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	for id: int in 21:
		for part: int in 4:
			GameState.equipped_armor[ArmorCatalog.PART_KEYS[part]] = ArmorCatalog.item_key(part, id)
		fixture.player._apply_recovered_armor_visibility()
		for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
			var key := prefix + "%02d" % id
			var shown := fixture.player.recovered_avatar.find_child(key, true, false) as MeshInstance3D
			var original := source.find_child(key, true, false) as MeshInstance3D
			_check(shown != null and shown.visible, "Missing original part " + key)
			if shown == null:
				continue
			_check(shown.mesh.get_surface_count() == original.mesh.get_surface_count(), "Surface count changed " + key)
			_check(shown.transform.is_equal_approx(original.transform), "Original transform changed " + key)
			for sid: int in original.mesh.get_surface_count():
				_check(_triangles(shown.mesh, sid) == _triangles(original.mesh, sid), "Original triangle geometry or UV changed " + key)
		if capture and id in [6, 8, 11]:
			for view: String in ["front", "side"]:
				fixture.view_camera.position = Vector3(0, 1.1, -6) if view == "front" else Vector3(6, 1.1, 0)
				fixture.view_camera.look_at(Vector3(0, 1.04, 0), Vector3.UP)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var dir := "res://docs/art/original_hd_backup/review/"
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
				var image := viewport.get_texture().get_image()
				_check(image.get_size() == Vector2i(640, 720), "Wrong capture size")
				_check(image.save_png(dir + "armor_%02d_%s.png" % [id, view]) == OK, "Cannot save capture")
	source.free()
	fixture.cleanup()
	viewport.queue_free()
	await get_tree().process_frame
	GameState.save_path = real_save
	var after := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "absent"
	_check(before == after, "Real save changed")
	var dir := "res://docs/art/original_hd_backup/review/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var report := FileAccess.open(dir + "validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"original_sets":21,"original_parts":84,"capture":capture,"renderer":RenderingServer.get_current_rendering_method(),"viewport":[640,720],"save_unchanged":before==after}, "\t"))
	print("ORIGINAL_HD_BACKUP_%s sets=21 parts=84 triangle_geometry_and_uv_checked=true capture=%s save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", str(capture), str(before == after)])
	get_tree().quit(0 if failures.is_empty() else 1)
