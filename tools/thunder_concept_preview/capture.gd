extends Node3D

# Real WarfarePlayer equipment, animation, and game scenes. No preview replacement
# materials, model scaling, compositing, or reference-image billboard is used.
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const OUT := "res://test_output/thunder_concept_preview/"
const SIZE := Vector2i(1200, 1440)
const VIEWS := {
	"front": Vector3(0, 0.4, -6),
	"three_quarter": Vector3(2.7, 1.2, -5),
	"side": Vector3(6, 0.4, 0),
	"rear": Vector3(-2.7, 0.9, 5),
}
var viewport: SubViewport
var fixture: Node3D
var stage := "current"
var manifest: Array[Dictionary] = []
var parts: Array[Dictionary] = []
var failures: Array[String] = []
var real_save := ""
var real_save_hash := ""
var scene_hash := ""
var resource_hashes: Dictionary = {}
var full_bounds := AABB()
var head_bounds := AABB()


func _ready() -> void:
	# _ready is before this scene creates a player or mutates equipment.
	real_save = GameState.save_path
	real_save_hash = FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "MISSING"
	GameState.save_path = "user://thunder_concept_preview_profile.json"
	scene_hash = FileAccess.get_sha256("res://assets/armors/thunder/thunder.scn")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--stage="):
			stage = argument.trim_prefix("--stage=")
	if stage not in ["baseline", "current"]:
		push_error("Stage must be baseline or current")
		get_tree().quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + stage)) != OK:
		push_error("Cannot create Thunder preview directory")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(500, 600)
	get_window().title = "Thunder actual runtime comparison"
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	fixture = Fixture.new()
	viewport.add_child(fixture)
	fixture.setup() # Fixture also isolates its profile before creating its player.
	GameState.save_path = "user://thunder_concept_preview_profile.json"
	_equip_thunder()
	fixture.player._apply_recovered_armor_visibility()
	_check_parts(fixture.player, true)
	fixture.label.hide()
	fixture.player.backpack_socket.hide()
	fixture.player.gun_socket.hide()
	fixture.player.left_gun_socket.hide()
	fixture.player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.fill.light_energy = 0.6
	for child in fixture.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 1.0
			child.rotation_degrees = Vector3(-35, -35, 0)
			child.shadow_enabled = true
		elif child is WorldEnvironment:
			child.environment.background_color = Color(0.24, 0.245, 0.25)
			child.environment.ambient_light_energy = 0.8
	fixture.player.recovered_animation_tree.active = false
	fixture.player._play_recovered_animation("idle_rifle", 0, true)
	fixture.player.recovered_animation_player.advance(0)
	fixture.player.recovered_skeleton.force_update_all_bone_transforms()
	_measure()
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(200, 200)
	ground.position.y = full_bounds.position.y - 0.005
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.30, 0.31, 0.32)
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	fixture.add_child(ground)
	for view: String in VIEWS:
		_frame(view, false)
		await _save("full_" + view, "studio", view, "idle_rifle", 0.0, viewport)
	for view: String in VIEWS:
		_frame(view, true)
		await _save("helmet_" + view, "helmet", view, "idle_rifle", 0.0, viewport)
	fixture.player.gun_socket.show()
	fixture.player.left_gun_socket.show()
	_frame("three_quarter", false)
	await _save("armed_idle", "motion", "three_quarter", "idle_rifle", 0.0, viewport)
	for fraction: float in [0.2, 0.52, 0.85]:
		fixture.begin("gun00", 0, true)
		fixture.advance_to(fixture.duration * fraction)
		for view: String in ["three_quarter", "side", "rear"]:
			_frame(view, false)
			await _save("reload_%02d_%s" % [roundi(fraction * 100), view], "motion", view, "moving_gun00_reload_variant_0", fixture.elapsed, viewport)
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame
	await _capture_gameplay()
	var final_hash := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "MISSING"
	if final_hash != real_save_hash:
		_fail("Real save changed during capture")
	for path: String in resource_hashes:
		if FileAccess.get_sha256(path) != resource_hashes[path]:
			_fail("Runtime resource changed during capture: " + path)
	var output := FileAccess.open(OUT + stage + "/manifest.json", FileAccess.WRITE)
	if output == null:
		_fail("Cannot write capture manifest")
	else:
		output.store_string(JSON.stringify({
			"status": "CAPTURED_REQUIRES_VISUAL_REVIEW" if failures.is_empty() else "FAIL",
			"stage": stage,
			"captured_at": Time.get_datetime_string_from_system(),
			"runtime_loader": "WarfarePlayer._apply_recovered_armor_visibility",
			"renderer": RenderingServer.get_current_rendering_method(),
			"quality": {"render_scale": 1.0, "msaa": "4x", "source": "GameState high profile"},
			"runtime_scene_sha256": scene_hash,
			"runtime_resource_sha256": resource_hashes,
			"save_unchanged": final_hash == real_save_hash,
			"parts": parts,
			"full_bounds": {"position": _vec(full_bounds.position), "size": _vec(full_bounds.size)},
			"head_bounds": {"position": _vec(head_bounds.position), "size": _vec(head_bounds.size)},
			"frames": manifest,
			"failures": failures,
			"notes": "Actual runtime meshes/materials. Studio uses the existing rifle idle pose with weapon/backpack hidden; pose and lighting differ from the concept. Rear is a model design continuation, not a provided rear reference. Motion/game views use existing game animations and materials.",
		}, "\t"))
		output.close()
	AudioDirector.stop_all_sfx()
	print("THUNDER_CONCEPT_CAPTURE_%s stage=%s images=%d save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", stage, manifest.size(), str(final_hash == real_save_hash)])
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture_gameplay() -> void:
	var game_viewport := SubViewport.new()
	game_viewport.size = Vector2i(1600, 900)
	game_viewport.own_world_3d = true
	game_viewport.msaa_3d = Viewport.MSAA_4X
	game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(game_viewport)
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	_equip_thunder()
	for level: int in [1, 3]:
		GameState.selected_level = level
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		game_viewport.add_child(world)
		for tick in 15:
			await get_tree().process_frame
		_check_parts(world.player, false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await _save("game_level_%d" % level, "game", "game_camera", "live_game", 0.0, game_viewport)
		world.queue_free()
		await get_tree().process_frame
	game_viewport.queue_free()
	await get_tree().process_frame


func _equip_thunder() -> void:
	for part: int in 4:
		GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, 6)


func _check_parts(player: WarfarePlayer, record: bool) -> void:
	var count := 0
	for part: MeshInstance3D in player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if not part.visible:
			continue
		count += 1
		if not str(part.name).ends_with("_06") or not str(part.get_meta("armor_rework", "")).begins_with("thunder"):
			_fail("Unexpected runtime part: " + str(part.name))
		if stage == "current" and str(part.get_meta("armor_rework", "")) != "thunder_concept_v3":
			_fail("Current capture requires thunder_concept_v3: " + str(part.name))
		if record:
			parts.append({"name": str(part.name), "revision": str(part.get_meta("armor_rework", "")), "mesh": part.mesh.resource_path, "surfaces": part.mesh.get_surface_count()})
			_record_resource(part.mesh)
			for surface: int in part.mesh.get_surface_count():
				var material := part.get_active_material(surface) as ShaderMaterial
				if material == null or material.shader == null:
					continue
				_record_resource(material.shader)
				for uniform: Dictionary in material.shader.get_shader_uniform_list():
					var value: Variant = material.get_shader_parameter(str(uniform.name))
					if value is Texture2D:
						_record_resource(value)
	if count != 4:
		_fail("Expected exactly four visible Thunder parts, got %d" % count)


func _record_resource(resource: Resource) -> void:
	var path := resource.resource_path.get_slice("::", 0)
	if path.begins_with("res://") and not resource_hashes.has(path) and FileAccess.file_exists(path):
		resource_hashes[path] = FileAccess.get_sha256(path)


func _measure() -> void:
	var started := false
	for part: MeshInstance3D in fixture.player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if not part.visible:
			continue
		var bounds := _posed_bounds(part, fixture.player.recovered_skeleton)
		full_bounds = full_bounds.merge(bounds) if started else bounds
		started = true
		if str(part.name).begins_with("ArmorHead"):
			head_bounds = bounds


func _posed_bounds(instance: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var transforms: Array[Transform3D] = []
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
			var point := Vector3.ZERO
			for k: int in 4:
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][i * 4 + k]
				if weight > 0:
					point += (transforms[arrays[Mesh.ARRAY_BONES][i * 4 + k]] * arrays[Mesh.ARRAY_VERTEX][i]) * weight
			point = skeleton.global_transform * point
			bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return bounds


func _frame(view: String, close: bool) -> void:
	var bounds := head_bounds if close else full_bounds
	var center := bounds.get_center()
	fixture.view_camera.size = maxf(bounds.size.y, bounds.size.x * 1.2) * (1.27 if close else 1.22)
	fixture.view_camera.position = center + VIEWS[view]
	fixture.view_camera.look_at(center)
	fixture.fill.position = fixture.view_camera.position


func _save(stem: String, category: String, view: String, pose: String, elapsed: float, target: SubViewport) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var screenshot := target.get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_size() != target.size:
		_fail("Invalid capture: " + stem)
		return
	if screenshot.save_png(ProjectSettings.globalize_path(OUT + stage + "/" + stem + ".png")) != OK:
		_fail("Cannot save capture: " + stem)
		return
	manifest.append({"file": stem + ".png", "width": target.size.x, "height": target.size.y, "category": category, "view": view, "pose": pose, "time": elapsed})


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _vec(vector: Vector3) -> Array[float]:
	return [vector.x, vector.y, vector.z]
