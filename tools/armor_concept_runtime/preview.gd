extends Node

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const ORIGINAL := "res://assets/models/player/animated/player.gltf"
const OUT := "res://test_output/armor_concept_runtime/"
const SIZE := Vector2i(600, 760)
const ROLLOUT := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11]
var fixtures: Array[Node3D] = []
var views: Array[SubViewport] = []
var original: Node3D
var selected_id := 11
var selected_view := "quarter"
var pose := "idle"
var title: Label
var elapsed := 0.0
var capturing := false
var real_save := ""
var real_hash := ""
var old_settings: Dictionary


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	real_save = GameState.save_path
	real_hash = _hash(real_save)
	old_settings = GameState.settings.duplicate(true)
	GameState.save_path = "user://concept_armor_preview.json"
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	get_window().size = Vector2i(1240, 870)
	get_window().title = "裝甲實機比對 — 貼合試稿 / 原版（相同骨架）"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	original = (load(ORIGINAL) as PackedScene).instantiate() as Node3D
	_build_ui()
	_equip(11)
	capturing = "--capture" in OS.get_cmdline_user_args()
	if capturing:
		await _capture_all()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("151c27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 20
	layout.offset_right = -20
	layout.offset_top = 14
	layout.offset_bottom = -14
	add_child(layout)
	var row := HBoxContainer.new()
	layout.add_child(row)
	var sets := OptionButton.new()
	for id: int in Catalog.SET_NAMES.size():
		sets.add_item("%02d · %s%s" % [id, Catalog.SET_NAMES[id], "（保留原版）" if id not in ROLLOUT else ""], id)
	sets.select(11)
	sets.item_selected.connect(func(index: int): _equip(sets.get_item_id(index)))
	row.add_child(sets)
	for view: String in ["quarter", "front", "side", "rear"]:
		var button := Button.new()
		button.text = {"quarter": "斜前", "front": "正面", "side": "側面", "rear": "背面"}[view]
		button.pressed.connect(func(): selected_view = view; _set_view())
		row.add_child(button)
	for action: String in ["idle", "run", "reload"]:
		var button := Button.new()
		button.text = {"idle": "持槍待機", "run": "跑步", "reload": "換彈"}[action]
		button.pressed.connect(func(): _set_pose(action))
		row.add_child(button)
	var turn := Button.new()
	turn.text = "切換武器顯示"
	turn.pressed.connect(func():
		for fixture: Node3D in fixtures:
			fixture.player.gun_socket.visible = not fixture.player.gun_socket.visible)
	row.add_child(turn)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 18)
	layout.add_child(title)
	var stages := HBoxContainer.new()
	stages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(stages)
	for side: int in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stages.add_child(column)
		var label := Label.new()
		label.text = "左 · Cygni 貼合試稿／其他現用模型" if side == 0 else "右 · 原版模型"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		var container := SubViewportContainer.new()
		container.stretch = true
		if "--capture-small" in OS.get_cmdline_user_args():
			container.stretch_shrink = 4
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = SIZE
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		views.append(viewport)
		var fixture := Fixture.new()
		viewport.add_child(fixture)
		fixture.setup()
		GameState.save_path = "user://concept_armor_preview.json"
		fixture.label.hide()
		fixture.player.backpack_socket.hide()
		fixture.player.gun_socket.hide()
		fixture.player.set_process_unhandled_input(false)
		fixture.player.recovered_animation_tree.active = false
		fixture.player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		fixture.view_camera.size = 2.35
		fixture.fill.light_energy = 0.55
		for child: Node in fixture.get_children():
			if child is WorldEnvironment:
				child.environment.ambient_light_energy = 0.6
			elif child is DirectionalLight3D:
				child.light_energy = 1.0
				child.shadow_enabled = true
		fixtures.append(fixture)


func _equip(id: int) -> void:
	selected_id = id
	for part: int in 4:
		GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, id)
	for fixture: Node3D in fixtures:
		fixture.player._apply_recovered_armor_visibility()
	# Always restore the right stage from raw source meshes, never from the
	# concept loader or the refined fallback. CoM uses its original adapter.
	var source := original
	if id >= Catalog.CALLOFMINI_FIRST_ID:
		source = (load(Catalog.gameplay_scene_path(id)) as PackedScene).instantiate() as Node3D
	for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
		var name_key := prefix + "%02d" % id
		var baseline := source.find_child(name_key, true, false) as MeshInstance3D
		var target := fixtures[1].player.recovered_avatar.find_child(name_key, true, false) as MeshInstance3D
		if baseline == null or target == null:
			push_error("Preview missing original part " + name_key)
			get_tree().quit(1)
			return
		target.mesh = baseline.mesh
		target.skin = baseline.skin
		target.transform = baseline.transform
		target.material_override = null
		for surface: int in target.get_surface_override_material_count():
			target.set_surface_override_material(surface, null)
		# Original SW armor is unlit, as documented by armor_visuals.gd.
		if id < Catalog.CALLOFMINI_FIRST_ID:
			for surface: int in target.mesh.get_surface_count():
				var material := baseline.get_active_material(surface).duplicate() as BaseMaterial3D
				if material != null:
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					target.set_surface_override_material(surface, material)
	if source != original:
		source.free()
	var trial := id == 11 and "--cygni-painted-trial" in OS.get_cmdline_user_args()
	var repaired := id == 11 and "--cygni-helmet-repair" in OS.get_cmdline_user_args()
	var description := "連續外殼灰模：先驗頭盔結構；身體保留原版" if repaired else ("手繪貼圖＋原模型貼合試稿" if trial else "此套使用現有遊戲素材")
	title.text = "%s · 相同原版骨架、鏡頭與姿勢 · %s" % [Catalog.SET_NAMES[id], description]
	_set_view()
	_set_pose("idle")


func _set_view() -> void:
	var positions := {"front": Vector3(0, 1.08, -6), "quarter": Vector3(3.3, 2.0, -5), "side": Vector3(6, 1.08, 0), "rear": Vector3(0, 1.08, 6)}
	for fixture: Node3D in fixtures:
		fixture.view_camera.position = positions[selected_view]
		fixture.view_camera.look_at(Vector3(0, 1.02, 0))
		fixture.fill.position = fixture.view_camera.position


func _set_pose(action: String) -> void:
	pose = action
	elapsed = 0.0
	for fixture: Node3D in fixtures:
		fixture.player._cancel_reload()
		fixture.player.recovered_animation_tree.active = false
		if action == "reload":
			fixture.begin("gun00", 0)
		else:
			fixture.player._play_recovered_animation("run_rifle" if action == "run" else "idle_rifle", 0, true)
			fixture.player.recovered_animation_player.advance(0)


func _process(delta: float) -> void:
	if fixtures.is_empty() or capturing:
		return
	elapsed += delta
	for fixture: Node3D in fixtures:
		if pose == "reload":
			if fixture.player.reload_left <= 0:
				fixture.begin("gun00", 0)
			fixture.step(delta)
		else:
			fixture.player.recovered_animation_player.advance(delta)
			fixture.player.recovered_skeleton.force_update_all_bone_transforms()


func _capture_all() -> void:
	var ids: Array[int] = []
	ids.assign(ROLLOUT)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ids="):
			ids.clear()
			for value: String in argument.trim_prefix("--ids=").split(","):
				if not value.is_valid_int() or int(value) < 0 or int(value) >= Catalog.SET_NAMES.size():
					push_error("Invalid capture id")
					get_tree().quit(1)
					return
				ids.append(int(value))
	var files: Array[Dictionary] = []
	for id: int in ids:
		_equip(id)
		for view: String in ["quarter", "front", "side", "rear"]:
			selected_view = view
			_set_view()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			for side: int in 2:
				var prefix := "repair_" if "--cygni-helmet-repair" in OS.get_cmdline_user_args() else ""
				var path := OUT + prefix + "armor_%02d_%s_%s%s.png" % [id, "concept" if side == 0 else "original", view, "_small" if "--capture-small" in OS.get_cmdline_user_args() else ""]
				if views[side].get_texture().get_image().save_png(path) != OK:
					push_error("Capture failed: " + path)
					get_tree().quit(1)
					return
				files.append({"id": id, "side": side, "view": view, "path": path})
		for action: String in ["run", "reload"]:
			_set_pose(action)
			for fixture: Node3D in fixtures:
				if action == "reload":
					fixture.advance_to(fixture.duration * 0.50)
				else:
					fixture.player.recovered_animation_player.seek(0.18, true)
					fixture.player.recovered_skeleton.force_update_all_bone_transforms()
			selected_view = "quarter"
			_set_view()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			for side: int in 2:
				var prefix := "repair_" if "--cygni-helmet-repair" in OS.get_cmdline_user_args() else ""
				var path := OUT + prefix + "armor_%02d_%s_%s%s.png" % [id, "concept" if side == 0 else "original", action, "_small" if "--capture-small" in OS.get_cmdline_user_args() else ""]
				if views[side].get_texture().get_image().save_png(path) != OK:
					push_error("Pose capture failed: " + path)
					get_tree().quit(1)
					return
				files.append({"id": id, "side": side, "view": action, "path": path})
		print("CONCEPT_ARMOR_CAPTURE id=%02d" % id)
	var save_unchanged := _hash(real_save) == real_hash
	var file := FileAccess.open(OUT + "capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "captured_requires_visual_review", "ids": ids, "files": files, "real_save_unchanged": save_unchanged, "renderer": RenderingServer.get_current_rendering_method(), "painted_trial": "--cygni-painted-trial" in OS.get_cmdline_user_args(), "repaired_head": "--cygni-helmet-repair" in OS.get_cmdline_user_args(), "small": "--capture-small" in OS.get_cmdline_user_args()}, "\t"))
	GameState.save_path = real_save
	GameState.settings = old_settings
	for fixture: Node3D in fixtures:
		fixture.cleanup()
		fixture.queue_free()
	fixtures.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	original.free()
	original = null
	print("CONCEPT_ARMOR_CAPTURE_%s sets=%d save_unchanged=%s" % ["PASS" if save_unchanged else "FAIL", ids.size(), str(save_unchanged)])
	get_tree().quit(0 if save_unchanged else 1)


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"


func _exit_tree() -> void:
	if is_instance_valid(original):
		original.free()
	AudioDirector.stop_all_sfx()
