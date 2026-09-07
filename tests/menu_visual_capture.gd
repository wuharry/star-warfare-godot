extends Node

var output_dir := "res://tests"
var captures: Array[Dictionary] = []
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Capture-only changes and any incidental saves stay away from the real profile.
	GameState.save_path = "user://menu_visual_capture_profile.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--viewport="):
			var dimensions := argument.trim_prefix("--viewport=").split("x")
			if dimensions.size() == 2:
				var requested_size := Vector2i(int(dimensions[0]), int(dimensions[1]))
				get_window().content_scale_size = requested_size
				get_window().size = requested_size
		elif argument.begins_with("--locale="):
			Localization.apply_locale(argument.trim_prefix("--locale="))
		elif argument == "--fixture":
			GameState.unlocked_level = 1
			GameState.best_scores = {}
			GameState.credits = 90000
			GameState.mithril = 12
			GameState.owned_weapons.assign(["gun00"])
			GameState.battle_weapons.assign(["gun00"])
			GameState.owned_props = {}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	_check(directory_error == OK, "capture output directory could not be created")
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(0.45).timeout
	await _capture("menu_restoration_preview", "main menu")
	menu._toggle_drawer(true, false)
	await _capture("menu_navigation_preview", "navigation drawer")
	menu._toggle_drawer(false, false)
	menu._show_armory("store")
	var shell: UnityEquipmentShell = menu.equipment_shell
	shell._select_item("gun00", false)
	await _capture("armory_restoration_preview", "store / FR28a")
	_check(menu.store_weapon_row.get_child_count() == GameState.get_weapon_ids().size(), "weapon catalog count differs from GameState")
	_check(menu.store_category_buttons.size() == 6, "equipment categories are missing")
	_check(menu.store_slot_picker.item_count >= 1, "loadout slot picker is empty")
	shell._select_item("gun01", false)
	await _capture("purchase_store_preview", "store / purchasable weapon")
	var locked_key := "gun36"
	for weapon_key: String in GameState.get_weapon_ids():
		if not GameState.is_weapon_rank_unlocked(weapon_key) and not GameState.owned_weapons.has(weapon_key):
			locked_key = weapon_key
			break
	shell._select_item(locked_key, false)
	await _capture("locked_store_preview", "store / rank requirement")
	shell._select_item("gun22", false)
	await _capture("special_store_preview", "store / transparent material")
	shell._select_item("gun23", false)
	await _capture("additive_store_preview", "store / additive material")
	shell._select_category("head", false)
	await _capture("armor_store_preview", "store / armor")
	shell._select_category("bag", false)
	shell._select_item(GameState.get_armor_ids("bag")[0], false)
	await _capture("bag_store_preview", "store / bag")
	for supply_key: String in ["health", "aid", "assist"]:
		shell._select_supply_category(supply_key, false)
		await _capture("%s_store_preview" % supply_key, "store / %s supplies" % supply_key)
		_check(shell.item_row.get_child_count() == GameState.get_prop_ids(supply_key).size(), "%s supply count differs from GameState" % supply_key)
	shell._select_category("gun", false)
	shell._select_item("gun00", false)
	shell.set_mode("customize", false)
	await _capture("customize_store_preview", "customize / equipped weapon")
	shell._select_category("head", false)
	await _capture("armor_restoration_preview", "customize / armor")
	_check(menu.store_weapon_row.get_child_count() == GameState.get_armor_ids("head").size(), "armor catalog count differs from GameState")
	shell._select_category("bag", false)
	shell._select_item(GameState.get_armor_ids("bag")[0], false)
	await _capture("bag_restoration_preview", "customize / bag")
	_check(menu.store_weapon_row.get_child_count() == GameState.get_armor_ids("bag").size(), "bag catalog count differs from GameState")
	_check(menu.design_root.size.is_equal_approx(Vector2(960, 640)), "main-menu design canvas changed")
	var additive_probe := await _check_additive_preview_alpha()
	if output_dir != "res://tests":
		var manifest := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
		if manifest != null:
			manifest.store_string(JSON.stringify({
				"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
				"renderer": RenderingServer.get_current_rendering_method(),
				"locale": TranslationServer.get_locale(),
				"captures": captures,
				"additive_probe": additive_probe,
				"failures": failures,
			}, "\t"))
		else:
			_check(false, "capture manifest could not be saved")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	print("MENU_VISUAL_CAPTURE_PASS images=%d output=%s" % [captures.size(), output_dir] if failures.is_empty() else "MENU_VISUAL_CAPTURE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture(file_stem: String, description: String) -> void:
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture_image := get_viewport().get_texture().get_image()
	var capture_path := output_dir.path_join(file_stem + ".png")
	var error := capture_image.save_png(capture_path)
	_check(error == OK, "could not save " + capture_path)
	captures.append({"file": file_stem + ".png", "description": description, "width": capture_image.get_width(), "height": capture_image.get_height()})


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MENU VISUAL CAPTURE: " + message)


func _check_additive_preview_alpha() -> Dictionary:
	# Black pixels in legacy glow textures are opaque in the source PNG. They
	# must contribute neither color nor coverage to a transparent weapon preview.
	var viewport := SubViewport.new()
	viewport.name = "AdditiveAlphaProbe"
	viewport.size = Vector2i(64, 32)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var texture_image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	texture_image.fill(Color.BLACK)
	texture_image.fill_rect(Rect2i(32, 0, 32, 32), Color(0, 0.5, 1, 1))
	var texture := ImageTexture.create_from_image(texture_image)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 1)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = UnityEquipmentShell.AdditivePreviewShader
	material.set_shader_parameter("effect_texture", texture)
	material.set_shader_parameter("effect_tint", Color.WHITE)
	mesh.material_override = material
	viewport.add_child(mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	camera.position.z = 2.0
	viewport.add_child(camera)
	camera.make_current()
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	var black := rendered.get_pixel(16, 16)
	var blue := rendered.get_pixel(48, 16)
	_check(black.a < 0.02, "additive preview retains opaque black texture coverage")
	_check(blue.a > 0.5 and blue.b > 0.5 and blue.b > blue.r, "additive preview removed the visible blue glow")
	if output_dir != "res://tests":
		_check(rendered.save_png(output_dir.path_join("additive_alpha_probe.png")) == OK, "could not save additive alpha probe")
	viewport.queue_free()
	await get_tree().process_frame
	return {"black_alpha": black.a, "blue_alpha": blue.a, "blue_rgb": [blue.r, blue.g, blue.b]}
