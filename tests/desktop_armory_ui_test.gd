extends "res://tests/mobile_store_sw1_test.gd"

func _run() -> void:
	var original_save := GameState.save_path
	GameState.save_path = "user://desktop_armory_ui_%d.json" % Time.get_ticks_usec()
	GameState.weapon_levels.clear()
	GameState.armor_set_levels.clear()
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.owned_weapons.assign(["gun00"])
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_weapon = "gun00"
	GameState.owned_props.clear()
	GameState.credits = 999999999999
	GameState.mithril = 99999999
	GameState.experience = 99999999
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/desktop_armory_ui"))
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(2)
	menu._show_armory("store")
	await _frames(4)
	shell = menu.equipment_shell
	_check(shell._recovered_desktop_skin and shell.theme != null, "desktop recovered skin not installed")
	_check(shell.catalog_panel.get_theme_stylebox("panel") is StyleBoxTexture, "catalog frame is still procedural")
	_check(shell.get_node("OriginalNavigationBar").get_theme_stylebox("panel") is StyleBoxTexture, "navigation bar is still procedural")
	_check(shell.detail_panel.get_node("PurchaseDivider") is TextureRect, "purchase divider does not use original atlas")
	for picker: OptionButton in [shell.weapon_filter_picker, shell.slot_picker]:
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			_check(picker.get_theme_stylebox(state) is StyleBoxTexture, "picker state is unstyled: " + state)
		_check(picker.get_node_or_null("RecoveredDropdownArrow") != null, "picker has default arrow")
		_check(picker.get_popup().get_theme_stylebox("panel") is StyleBoxTexture and picker.get_popup().get_theme_stylebox("hover") is StyleBoxTexture, "expanded popup retains default panel/hover")
		_check(picker.get_popup().get_theme_icon("radio_checked") is AtlasTexture, "popup radio uses engine default art")
	_check(shell.item_scroll.get_v_scroll_bar().get_theme_stylebox("grabber") is StyleBoxTexture, "catalog scrollbar is still default")
	_check(shell.description_text.get_v_scroll_bar().get_theme_stylebox("scroll") is StyleBoxTexture, "description scrollbar is still default")
	_check(shell.theme.get_stylebox("panel", "TooltipPanel") is StyleBoxTexture, "tooltip is still default")
	for card: Button in shell.item_row.get_children():
		_check(card.get_theme_stylebox("normal") is StyleBoxTexture and card.get_theme_stylebox("focus") is StyleBoxTexture, "product card still uses generic panel/focus")
	shell._select_item("gun01", false)
	await _capture("store")
	await _click(shell.weapon_filter_picker)
	var popup: PopupMenu = shell.weapon_filter_picker.get_popup()
	_check(popup.visible, "mouse did not open weapon filter")
	popup.set_focused_item(3)
	await _capture("filter_open")
	await _popup_key(popup, KEY_ENTER)
	_check(shell.weapon_filter == "HEAVY" and not popup.visible and shell.item_row.get_child_count() < 47, "filter keyboard selection did not apply")
	_check(shell.weapon_filter_picker.get_node("RecoveredDropdownArrow").rotation_degrees == -90, "picker arrow did not close")
	await _capture("filter_applied")
	# Escape and outside-click dismiss without changing the filter or purchase.
	await _click(shell.weapon_filter_picker)
	popup.set_focused_item(1)
	await _popup_key(popup, KEY_ESCAPE)
	_check(shell.weapon_filter == "HEAVY" and not popup.visible, "Escape applied a hovered option")
	await _click(shell.weapon_filter_picker)
	await _click(menu.design_root)
	_check(not popup.visible and shell.weapon_filter == "HEAVY", "outside click failed to dismiss filter")
	shell.set_weapon_filter("ALL")
	shell._select_item("gun01", false)
	var cash_before := GameState.credits
	await _click(shell.action_button)
	_check(GameState.is_weapon_owned("gun01") and GameState.credits == cash_before - 25000, "recovered button broke the existing purchase transaction")
	await _capture("purchased")
	# Popups above a near-bottom loadout picker must stay within the viewport.
	GameState.owned_weapons.assign(GameState.get_weapon_ids())
	var capacity := 1
	for key: String in GameState.get_armor_ids("bag"):
		if int(GameState.ARMOR_ITEMS[key].bag_slots) > capacity:
			GameState.owned_armor.append(key)
			GameState.equipped_armor.bag = key
			capacity = int(GameState.ARMOR_ITEMS[key].bag_slots)
	capacity = GameState.get_bag_capacity()
	GameState.battle_weapons.assign(["gun00", "gun11", "gun12", "gun24", "gun30", "gun34", "gun40", "gun41"].slice(0, capacity))
	shell.set_mode("customize", false)
	shell._select_item("gun02", false)
	await _frames(3)
	_check(shell.slot_picker.item_count == capacity and capacity > 1, "loadout picker lost available slots")
	await _click(shell.slot_picker)
	popup = shell.slot_picker.get_popup()
	_check(popup.visible, "loadout picker did not open")
	popup.set_focused_item(capacity - 1)
	_check(popup.position.y >= 0 and popup.position.y + popup.size.y <= get_viewport().get_visible_rect().size.y, "loadout popup escaped bottom edge")
	await _capture("slots_open")
	await _popup_key(popup, KEY_ENTER)
	_check(shell.selected_slot == capacity - 1, "popup selection did not update chosen weapon slot")
	await _click(shell.action_button)
	_check(GameState.battle_weapons[capacity - 1] == "gun02" and GameState.battle_weapons[0] == "gun00", "Equip changed wrong slot")
	await _capture("customize")
	shell.set_mode("store", false)
	shell._select_category("head", false)
	shell._select_item("armor_head_21", false)
	await _capture("armor")
	shell._select_supply_category("health", false)
	await _capture("supplies")
	# Wide and narrow desktop retain the same skin; active mobile stays separate.
	get_window().content_scale_size = Vector2i(960, 640)
	await _frames(4)
	shell._select_category("gun", false)
	await _frames(3)
	_check(shell.catalog_panel.get_global_rect().encloses(shell.item_scroll.get_global_rect()), "resizing pushed the product grid outside its panel")
	var visible_width: float = shell.item_scroll.size.x - shell.item_scroll.get_v_scroll_bar().size.x
	for card: Control in shell.item_row.get_children():
		_check(card.position.x >= 0 and card.position.x + card.size.x <= visible_width + 1, "narrow desktop cropped product card: " + card.name)
	await _click(shell.weapon_filter_picker)
	await _capture("narrow_filter")
	await _popup_key(shell.weapon_filter_picker.get_popup(), KEY_ESCAPE)
	menu._close_modal()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	menu._show_armory("store")
	await _frames(4)
	_check(menu.equipment_shell is MobileShell and not menu.equipment_shell._recovered_desktop_skin, "desktop theme leaked into mobile shell")
	await _capture("mobile_unchanged")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await _frames(4)
	await get_tree().create_timer(0.25).timeout
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(GameState.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameState.save_path = original_save
	print("DESKTOP_ARMORY_UI_PASS" if failures.is_empty() else "DESKTOP_ARMORY_UI_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _popup_key(popup: PopupMenu, code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.window_id = popup.get_window_id()
		Input.parse_input_event(event)
		await _frames(2)


func _click(control: Control) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = get_viewport().get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.window_id = get_window().get_window_id()
		Input.parse_input_event(event)
		await _frames(2)


func _capture(filename: String) -> void:
	if not capture:
		return
	await _frames(10)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/desktop_armory_ui/%s.png" % filename)
