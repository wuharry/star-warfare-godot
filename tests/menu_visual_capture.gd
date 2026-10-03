extends Node

var output_dir := "res://test_output/ui_unified/after/desktop"
var captures: Array[Dictionary] = []
var failures: Array[String] = []
var mobile := false
var ui_only := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Capture-only changes and any incidental saves stay away from the real profile.
	var previous_save_path := GameState.save_path
	GameState.save_path = "user://menu_visual_capture_%d.json" % Time.get_ticks_usec()
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
		elif argument == "--mobile":
			mobile = true
		elif argument == "--ui-only":
			ui_only = true
		elif argument == "--fixture":
			GameState.unlocked_level = 1
			GameState.best_scores = {}
			GameState.credits = 90000
			GameState.mithril = 12
			GameState.owned_weapons.assign(["gun00"])
			GameState.battle_weapons.assign(["gun00"])
			GameState.owned_props = {}
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", mobile)
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	_check(directory_error == OK, "capture output directory could not be created")
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(0.65).timeout
	var solo := menu.main_page.get_node("DeploymentStrip/SoloButton") as TextureButton
	if solo != null:
		solo.release_focus()
	_mouse_motion(Vector2(6, 200))
	await _capture("menu_restoration_preview", "main menu")
	await _capture_main_button_states(menu, solo)
	menu._toggle_drawer(true, false)
	await _capture("menu_navigation_preview", "navigation drawer")
	menu._toggle_drawer(false, false)
	await _capture_menu_pages(menu)
	if not ui_only:
		await _capture_armory(menu)
	_check(menu.design_root.size.is_equal_approx(Vector2(960, 640)), "main-menu design canvas changed")
	var additive_probe := await _check_additive_preview_alpha()
	if output_dir != "res://tests":
		var manifest := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
		if manifest != null:
			manifest.store_string(JSON.stringify({
				"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
				"renderer": RenderingServer.get_current_rendering_method(),
				"locale": TranslationServer.get_locale(),
				"mobile": mobile,
				"captures": captures,
				"additive_probe": additive_probe,
				"failures": failures,
			}, "\t"))
		else:
			_check(false, "capture manifest could not be saved")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(GameState.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameState.save_path = previous_save_path
	print("MENU_VISUAL_CAPTURE_PASS images=%d output=%s" % [captures.size(), output_dir] if failures.is_empty() else "MENU_VISUAL_CAPTURE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture_main_button_states(menu: Control, button: TextureButton) -> void:
	_check(button != null, "outer main-menu deployment control is not its original TextureButton")
	if button == null:
		return
	var original_rect := button.get_global_rect()
	_check(button.texture_normal == load("res://assets/ui/components/main_single_normal.png"), "outer main menu replaced its original normal artwork")
	_check(button.texture_pressed == load("res://assets/ui/components/main_single_pressed.png"), "outer main menu replaced its original pressed artwork")
	_check(button.get_draw_mode() == BaseButton.DRAW_NORMAL, "main button did not start in its normal state")
	_mouse_motion(_window_position(button))
	await _capture("menu_hover", "main menu / actual mouse hover")
	_check(button.get_draw_mode() == BaseButton.DRAW_HOVER, "actual mouse movement did not hover the main button")
	_mouse_button(_window_position(button), true)
	await _capture("menu_pressed", "main menu / held mouse button")
	_check(button.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED], "actual held click did not show the pressed state")
	# Release away from the target so the state capture does not launch a level.
	_mouse_motion(Vector2(6, 200))
	_mouse_button(Vector2(6, 200), false)
	await _frames(2)
	_check(menu.modal_layer.get_child_count() == 0, "releasing outside the main button activated it")
	button.release_focus()
	button.disabled = true
	await _click(button)
	await _capture("menu_disabled", "main menu / disabled button rejects input")
	_check(button.get_draw_mode() == BaseButton.DRAW_DISABLED and menu.modal_layer.get_child_count() == 0, "disabled main button still accepts clicks")
	button.disabled = false
	_mouse_motion(Vector2(6, 200))
	button.grab_focus()
	await _capture("menu_focus", "original outer menu / keyboard focus")
	_check(button.has_focus(), "original main button cannot receive keyboard focus")
	_check(button.get_global_rect().is_equal_approx(original_rect), "interaction states changed the main button hit target")
	button.release_focus()


func _capture_menu_pages(menu: Control) -> void:
	menu._toggle_drawer(true, false)
	await _click(menu.drawer.get_node("OptionsButton") as Control)
	await _capture("menu_options", "options / shared metal controls")
	var pickers: Array[Node] = menu.modal_layer.find_children("*", "OptionButton", true, false)
	_check(pickers.size() == 3, "options page did not open from the navigation button")
	if not pickers.is_empty():
		var picker := pickers[0] as OptionButton
		await _click(picker)
		_check(picker.get_popup().visible, "options dropdown did not open from a real click")
		await _key(KEY_DOWN, picker.get_popup().get_window_id())
		await _capture("menu_options_dropdown", "options / recovered popup and highlighted row")
		var popup := picker.get_popup()
		for pressed: bool in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ESCAPE
			key.physical_keycode = KEY_ESCAPE
			key.pressed = pressed
			key.window_id = popup.get_window_id()
			Input.parse_input_event(key)
			await _frames(2)
		_check(not popup.visible, "Escape did not close the options dropdown")
	var invert := menu.modal_layer.find_child("InvertLookButton", true, false) as CheckButton
	_check(invert != null, "options switch is missing")
	if invert != null:
		var previous_invert := bool(GameState.settings.invert_y)
		await _click(invert)
		_check(bool(GameState.settings.invert_y) != previous_invert and invert.button_pressed == bool(GameState.settings.invert_y), "actual options-switch click did not update the setting")
	var sliders: Array[Node] = menu.modal_layer.find_children("*", "HSlider", true, false)
	if not sliders.is_empty():
		var sound := sliders[0] as HSlider
		var previous_volume := sound.value
		sound.grab_focus()
		await _key(KEY_LEFT if is_equal_approx(sound.value, sound.max_value) else KEY_RIGHT, get_window().get_window_id())
		_check(not is_equal_approx(sound.value, previous_volume) and is_equal_approx(float(GameState.settings.sfx), sound.value), "focused options slider ignored the arrow key")
	await _capture("menu_options_changed", "options / checked switch and keyboard-adjusted slider")
	menu._handle_back()
	await _frames(2)
	menu._toggle_drawer(true, false)
	await _click(menu.drawer.get_node("EditNameButton") as Control)
	await _capture("menu_name", "name editor / recovered field and actions")
	var name_input := menu.modal_layer.find_child("NicknameInput", true, false) as LineEdit
	_check(name_input != null and name_input.has_focus(), "name editor did not focus its input")
	menu._handle_back()
	await _frames(2)
	await _click(menu.main_page.get_node("DeploymentStrip/SoloButton") as Control)
	await _capture("menu_solo_sectors", "solo selection / enabled and locked metal cards")
	_check(not menu.modal_layer.find_children("*", "GridContainer", true, false).is_empty(), "Solo click did not open campaign selection")
	menu._handle_back()
	await _frames(2)
	await _click(menu.main_page.get_node("DeploymentStrip/MultiplayerButton") as Control)
	await _capture("menu_pvp_arenas", "arena selection / same card format")
	_check(not menu.modal_layer.find_children("*", "GridContainer", true, false).is_empty(), "Online click did not open arena selection")
	menu._handle_back()
	await _frames(2)
	menu._toggle_drawer(true, false)
	await _click(menu.drawer.get_node("BankButton") as Control)
	await _capture("menu_bank", "bank notice / shared modal and back action")
	menu._handle_back()
	await _frames(2)


func _capture_armory(menu: Control) -> void:
	menu._show_armory("store")
	var shell: UnityEquipmentShell = menu.equipment_shell
	shell._select_item("gun00", false)
	await _capture("armory_restoration_preview", "store / FR28a")
	if not mobile:
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
		if not mobile:
			_check(shell.item_row.get_child_count() == GameState.get_prop_ids(supply_key).size(), "%s supply count differs from GameState" % supply_key)
	shell._select_category("gun", false)
	shell._select_item("gun00", false)
	shell.set_mode("customize", false)
	await _capture("customize_store_preview", "customize / equipped weapon")
	shell._select_category("head", false)
	await _capture("armor_restoration_preview", "customize / armor")
	if not mobile:
		_check(menu.store_weapon_row.get_child_count() == GameState.get_armor_ids("head").size(), "armor catalog count differs from GameState")
	shell._select_category("bag", false)
	shell._select_item(GameState.get_armor_ids("bag")[0], false)
	await _capture("bag_restoration_preview", "customize / bag")
	if not mobile:
		_check(menu.store_weapon_row.get_child_count() == GameState.get_armor_ids("bag").size(), "bag catalog count differs from GameState")


func _window_position(control: Control) -> Vector2:
	return get_viewport().get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.window_id = get_window().get_window_id()
	Input.parse_input_event(event)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.window_id = get_window().get_window_id()
	Input.parse_input_event(event)


func _click(control: Control) -> void:
	_mouse_motion(_window_position(control))
	for pressed: bool in [true, false]:
		_mouse_button(_window_position(control), pressed)
		await _frames(2)


func _key(code: Key, window_id: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.window_id = window_id
		Input.parse_input_event(event)
		await _frames(2)


func _frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


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
