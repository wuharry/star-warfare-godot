extends Node3D

# Run with --path . --rendering-method gl_compatibility res://tools/armor_hd_refinement/capture.tscn.
# Optional --armor-ids=2,21 captures only selected sets while developing the tools.
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const OUT := "res://test_output/armor_hd_refinement/"
const SIZE := Vector2i(1000, 1200)
const VIEWS := {"front": Vector3(0, 0.2, -6), "side": Vector3(6, 0.2, 0), "rear": Vector3(0, 0.2, 6)}

var game_state: Node
var fixture: Node3D
var viewport: SubViewport
var real_save := ""
var real_save_hash := ""
var failures: Array[String] = []
var resources: Dictionary = {}
var jobs: Dictionary = {}
var baseline_textures: Dictionary = {}
var frames: Array[Dictionary] = []
var all_ids: Array[int] = []
var completed_ids: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	game_state = get_tree().root.get_node("GameState")
	real_save = game_state.save_path
	real_save_hash = _hash(real_save)
	game_state.save_path = "user://armor_hd_refinement_profile.json"
	game_state.settings.quality = "high"
	game_state.settings.show_touch_controls = false
	for id: int in Catalog.SET_NAMES.size():
		if id != 6:
			all_ids.append(id)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--armor-ids="):
			all_ids.clear()
			for value: String in argument.trim_prefix("--armor-ids=").split(","):
				if not value.is_valid_int() or int(value) < 0 or int(value) >= Catalog.SET_NAMES.size() or int(value) == 6:
					_fail("Invalid armor id: " + value)
				else:
					all_ids.append(int(value))
	if not failures.is_empty():
		get_tree().quit(1)
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/equipment_refined/manifest.json"))
	for job: Dictionary in source.textures:
		jobs[str(job.output)] = job
	get_window().size = Vector2i(420, 504)
	get_window().title = "Armor HD — actual runtime capture"
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var fixture_script := load("res://tests/reload_catalog_fixture.gd") as Script
	fixture = fixture_script.new()
	viewport.add_child(fixture)
	fixture.setup()
	# Fixture chooses its own isolated profile; keep this capture's profile distinct.
	game_state.save_path = "user://armor_hd_refinement_profile.json"
	fixture.label.hide()
	fixture.player.backpack_socket.hide()
	fixture.player.gun_socket.hide()
	fixture.player.left_gun_socket.hide()
	fixture.player.set_process_unhandled_input(false)
	fixture.player.recovered_animation_tree.active = false
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.fill.light_energy = 0.8
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child: Node in fixture.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 1.0
		elif child is WorldEnvironment:
			child.environment.background_color = Color(0.20, 0.22, 0.25)
	for id: int in all_ids:
		await _capture_set(id)
	if completed_ids != all_ids:
		_fail("Capture did not finish all selected sets: " + str(completed_ids))
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame
	var save_unchanged := _hash(real_save) == real_save_hash
	if not save_unchanged:
		_fail("Real save changed during capture")
	for path: String in resources:
		if _hash(path) != resources[path]:
			_fail("Resource changed during capture: " + path)
	_write(OUT + "run.json", {
		"status": "CAPTURED_REQUIRES_VISUAL_REVIEW" if failures.is_empty() else "FAIL",
		"ids": all_ids, "completed_ids": completed_ids, "save_unchanged": save_unchanged, "failures": failures,
		"captured_at": Time.get_datetime_string_from_system(), "resources": resources,
	})
	print("ARMOR_HD_CAPTURE_%s sets=%d save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", all_ids.size(), str(save_unchanged)])
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture_set(id: int) -> void:
	var key := "armor_%02d" % id
	var reference := id in [0, 1]
	frames.clear()
	var first_failure := failures.size()
	for part: int in 4:
		game_state.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, id)
	fixture.player._apply_recovered_armor_visibility()
	fixture.player.recovered_animation_tree.active = false
	fixture.player._play_recovered_animation("idle_rifle", 0, true)
	fixture.player.recovered_animation_player.advance(0)
	fixture.player.recovered_skeleton.clear_bones_global_pose_override()
	fixture.player.recovered_skeleton.force_update_all_bone_transforms()
	var visible: Array[MeshInstance3D] = []
	var used: Dictionary = {}
	var part_records: Array[Dictionary] = []
	var set_resources: Dictionary = {}
	_record_path(Visuals.reworked_scene_path(id), set_resources)
	for script_path: String in ["res://tools/armor_hd_refinement/capture.gd", "res://scripts/game/armor_visuals.gd", "res://scripts/game/player.gd", "res://tests/reload_catalog_fixture.gd"]:
		_record_path(script_path, set_resources)
	var full := AABB()
	var first := true
	for part: MeshInstance3D in fixture.player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if not part.visible:
			continue
		visible.append(part)
		if not str(part.name).ends_with("_%02d" % id):
			_fail("Wrong runtime part for %s: %s" % [key, part.name])
		var bound := _posed_bounds(part, fixture.player.recovered_skeleton)
		full = bound if first else full.merge(bound)
		first = false
		var surfaces: Array[Dictionary] = []
		for index: int in part.mesh.get_surface_count():
			var material := part.get_active_material(index)
			var texture := _albedo(material)
			if texture == null:
				_fail("Missing albedo: %s surface %d" % [part.name, index])
				continue
			var path := texture.resource_path
			if not reference and (not jobs.has(path) or key not in jobs[path].owners):
				_fail("Unexpected runtime texture: %s %s" % [key, path])
			_record_path(path, set_resources)
			if material is ShaderMaterial:
				_record_path(material.shader.resource_path, set_resources)
			used[path] = true
			surfaces.append({"index": index, "texture": path, "sha256": _hash(path), "size": [texture.get_width(), texture.get_height()]})
		part_records.append({"name": str(part.name), "revision": str(part.get_meta("armor_rework", "")), "surfaces": surfaces})
	if visible.size() != 4:
		_fail("Expected four visible parts for %s, got %d" % [key, visible.size()])
	var unused: Array[String] = []
	for path: String in jobs:
		if key in jobs[path].owners and not used.has(path):
			unused.append(path)
	var versions: Array[String] = ["current"]
	if not reference:
		versions.append("baseline")
	var baseline_hashes: Dictionary = {}
	for version: String in versions:
		if version == "baseline":
			for part: MeshInstance3D in visible:
				for index: int in part.mesh.get_surface_count():
					var original := part.get_active_material(index)
					var texture := _albedo(original)
					if texture == null:
						continue
					var path := OUT + "baseline/textures/" + texture.resource_path.get_file()
					if not FileAccess.file_exists(path):
						_fail("Missing baseline texture: " + path)
						continue
					baseline_hashes[path] = _hash(path)
					if not baseline_textures.has(path):
						var image := Image.load_from_file(ProjectSettings.globalize_path(path))
						baseline_textures[path] = ImageTexture.create_from_image(image)
					var material := original.duplicate() as Material
					if material is ShaderMaterial:
						material.set_shader_parameter("albedo_texture", baseline_textures[path])
					elif material is BaseMaterial3D:
						material.albedo_texture = baseline_textures[path]
					part.set_surface_override_material(index, material)
		for framing: String in ["full", "close"]:
			for view: String in VIEWS:
				_frame(full, framing == "close", view)
				await _save(key, version, framing, view)
	# Baseline affects private material copies only; restore runtime materials now.
	for part: MeshInstance3D in visible:
		for index: int in part.get_surface_override_material_count():
			part.set_surface_override_material(index, null)
	if frames.size() != versions.size() * 6:
		_fail("Incomplete frames for " + key)
	_write(OUT + "sets/" + key + "/manifest.json", {
		"id": id, "key": key, "name": Catalog.SET_NAMES[id], "reference": reference,
		"status": "CAPTURED_REQUIRES_VISUAL_REVIEW" if failures.size() == first_failure else "FAIL",
		"captured_at": Time.get_datetime_string_from_system(), "renderer": RenderingServer.get_current_rendering_method(),
		"runtime_loader": "WarfarePlayer._apply_recovered_armor_visibility", "pose": "idle_rifle (weapon and backpack hidden)",
		"save_unchanged": _hash(real_save) == real_save_hash, "resources": set_resources,
		"baseline_textures": baseline_hashes, "parts": part_records, "unused_inventory_textures": unused,
		"bounds": {"position": [full.position.x, full.position.y, full.position.z], "size": [full.size.x, full.size.y, full.size.z]},
		"frames": frames, "failures": failures.slice(first_failure),
		"comparison": "Current uses actual runtime materials; baseline substitutes pre-task PNGs on identical mesh/material copies. Camera, pose and lighting are identical. References retain their accepted textures.",
	})
	completed_ids.append(id)
	print("ARMOR_HD_SET_%s %s %s images=%d visible_textures=%d" % ["PASS" if failures.size() == first_failure else "FAIL", key, Catalog.SET_NAMES[id], frames.size(), used.size()])


func _albedo(material: Material) -> Texture2D:
	if material is ShaderMaterial:
		return material.get_shader_parameter("albedo_texture") as Texture2D
	if material is BaseMaterial3D:
		return material.albedo_texture
	return null


func _posed_bounds(instance: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var transforms: Array[Transform3D] = []
	if instance.skin != null:
		for bind: int in instance.skin.get_bind_count():
			var bone := skeleton.find_bone(instance.skin.get_bind_name(bind))
			if bone < 0:
				bone = instance.skin.get_bind_bone(bind)
			transforms.append(skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
	var bounds := AABB()
	var started := false
	for surface: int in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		for i: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
			if not transforms.is_empty():
				point = Vector3.ZERO
				for k: int in 4:
					var weight: float = arrays[Mesh.ARRAY_WEIGHTS][i * 4 + k]
					if weight > 0:
						point += (transforms[arrays[Mesh.ARRAY_BONES][i * 4 + k]] * arrays[Mesh.ARRAY_VERTEX][i]) * weight
				point = skeleton.global_transform * point
			else:
				point = instance.global_transform * point
			bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return bounds


func _frame(bounds: AABB, close: bool, view: String) -> void:
	var center := bounds.get_center()
	if close:
		center.y = bounds.position.y + bounds.size.y * 0.74
	fixture.view_camera.size = bounds.size.y * 0.61 if close else maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z) * 1.2) * 1.18
	fixture.view_camera.position = center + VIEWS[view]
	fixture.view_camera.look_at(center)
	fixture.fill.position = fixture.view_camera.position


func _save(key: String, version: String, framing: String, view: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var name := "%s_%s_%s.png" % [version, framing, view]
	var folder := OUT + "sets/" + key + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if image == null or image.is_empty() or image.get_size() != SIZE or image.save_png(folder + name) != OK:
		_fail("Invalid capture: " + key + "/" + name)
		return
	frames.append({"file": name, "version": version, "framing": framing, "view": view, "width": SIZE.x, "height": SIZE.y, "sha256": _hash(folder + name)})


func _record_path(path: String, set_resources: Dictionary) -> void:
	path = path.get_slice("::", 0)
	if path.begins_with("res://") and FileAccess.file_exists(path):
		set_resources[path] = _hash(path)
		resources[path] = set_resources[path]


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)
