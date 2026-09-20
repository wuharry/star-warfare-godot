extends "res://tests/desktop_armory_ui_test.gd"
const Manufacturers = preload("res://scripts/core/manufacturer_catalog.gd")

func _run() -> void:
	var original_save := GameState.save_path
	var original_hash := FileAccess.get_sha256(original_save)
	var original_locale := TranslationServer.get_locale()
	GameState.save_path = "user://weapon_manufacturer_%d.json" % Time.get_ticks_usec()
	GameState.owned_weapons.assign(["gun00"])
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_weapon = "gun00"
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.weapon_levels.clear()
	GameState.armor_set_levels.clear()
	GameState.credits = 5000
	GameState.mithril = 0
	GameState.experience = 0
	TranslationServer.set_locale("zh_TW")
	var members := {}
	var expected_names := ["鐵衡聯邦防務", "邊垣野戰軍械", "赫曜光電動力", "矢界超導防務", "坩堝重裝兵械", "裂相前沿實驗室", "棘環搜救工造"]
	_check(Manufacturers.MANUFACTURERS.size() == 7, "manufacturer count")
	for id: String in Manufacturers.MANUFACTURERS:
		var company: Dictionary = Manufacturers.MANUFACTURERS[id]
		_check(str(company.name_zh) in expected_names and not str(company.story_en).is_empty(), "renamed company or English background missing")
		for key: String in company.weapons:
			_check(GameState.WEAPONS.has(key) and not members.has(key), "unknown or duplicate membership: " + key)
			members[key] = id
	_check(members.size() == 47 and Manufacturers.WEAPON_STORIES.size() == 47, "incomplete weapon assignment")
	for key: String in GameState.get_weapon_ids():
		_check(members.has(key) and Manufacturers.WEAPON_STORIES.has(key), "missing weapon: " + key)
		_check(not Manufacturers.weapon_description(key).is_empty(), "missing Chinese weapon story")
		TranslationServer.set_locale("en")
		_check(not Manufacturers.weapon_description(key).is_empty(), "missing English weapon story")
		TranslationServer.set_locale("zh_TW")
	_check(Manufacturers.get_manufacturer_for_weapon("FR28a").is_empty() and Manufacturers.get_manufacturer_for_weapon("invalid").is_empty(), "display name or invalid key accepted")
	var copy := Manufacturers.get_manufacturer_for_weapon("gun00")
	copy.weapons.clear()
	_check(Manufacturers.get_manufacturer_for_weapon("gun00").weapons.size() == 8, "caller mutated source membership")
	capture = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/weapon_manufacturers"))
	if capture:
		var names := {}
		for key: String in GameState.get_weapon_ids():
			names[key] = GameState.WEAPONS[key].name
		var file := FileAccess.open("res://test_output/weapon_manufacturers/catalog.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"manufacturers": Manufacturers.MANUFACTURERS, "weapons": Manufacturers.WEAPON_STORIES, "names": names}, "\t"))
		file.close()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(3)
	menu._show_armory("store")
	await _frames(4)
	shell = menu.equipment_shell
	_check(shell.weapon_info_button.visible and shell.weapon_info_button.text == "!", "square weapon information entry missing")
	_check(not shell.name_label.get_global_rect().intersects(shell.weapon_info_button.get_global_rect()), "information button overlaps weapon title")
	await _capture("desktop_entry")
	await _click(shell.weapon_info_button)
	_check(shell.weapon_info_dialog.visible and shell.weapon_info_dialog.manufacturer_label.text == "ILD · 鐵衡聯邦防務", "desktop button did not open renamed manufacturer")
	_check(shell.weapon_info_dialog.body.text.contains("FR 系列"), "weapon-specific description missing")
	_check(shell.get_global_rect().encloses(shell.weapon_info_dialog.panel.get_global_rect()), "dialog outside desktop canvas")
	await _capture("desktop_rifle")
	await _key(KEY_RIGHT)
	_check(shell.selected_item_key == "gun00" and shell.weapon_info_dialog.weapon_id == "gun00", "background navigation changed information target")
	await _key(KEY_TAB)
	_check(get_viewport().gui_get_focus_owner() == shell.weapon_info_dialog.scroll, "Tab escaped modal")
	await _key(KEY_ESCAPE)
	_check(not shell.weapon_info_dialog.visible and menu.equipment_shell == shell, "Escape closed store")
	# Membership remains stable when a display name changes.
	var old_name: String = GameState.WEAPONS.gun00.name
	GameState.WEAPONS.gun00.name = "FR28a renamed"
	shell._refresh_details()
	await _click(shell.weapon_info_button)
	_check(shell.weapon_info_dialog.heading.text == "FR28a renamed" and shell.weapon_info_dialog.manufacturer_label.text.begins_with("ILD"), "renaming a weapon broke manufacturer lookup")
	menu._handle_back()
	GameState.WEAPONS.gun00.name = old_name
	for key: String in ["gun01", "gun17", "gun22", "gun11", "gun30", "gun27"]:
		shell._select_item(key, false)
		await _click(shell.weapon_info_button)
		_check(shell.weapon_info_dialog.manufacturer_label.text.contains(str(Manufacturers.get_manufacturer_for_weapon(key).name_zh)), "wrong manufacturer dialog: " + key)
		if key == "gun11":
			await _capture("desktop_launcher")
		menu._handle_back()
	shell._select_item("gun45", false)
	await _click(shell.weapon_info_button)
	_check(shell.weapon_info_dialog.visible and not GameState.is_weapon_owned("gun45"), "locked/unowned weapon information unavailable")
	await _capture("desktop_locked")
	menu._handle_back()
	TranslationServer.set_locale("en")
	await _click(shell.weapon_info_button)
	_check(shell.weapon_info_dialog.manufacturer_label.text == "PAL · Parallax Advanced Labs" and shell.weapon_info_dialog.body.text.contains("WEAPON BACKGROUND"), "English information missing")
	_check(shell.weapon_info_dialog.close_button.text == "BACK", "information close button retained previous language")
	await _capture("desktop_english")
	menu._handle_back()
	TranslationServer.set_locale("zh_TW")
	shell._select_category("head", false)
	_check(not shell.weapon_info_button.visible, "weapon info leaked into armor")
	shell._select_supply_category("health", false)
	_check(not shell.weapon_info_button.visible, "weapon info leaked into supplies")
	menu._close_modal()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	menu._show_armory("customize")
	await _frames(5)
	shell = menu.equipment_shell
	_check(shell.weapon_info_button.is_visible_in_tree() and shell.get_global_rect().encloses(shell.weapon_info_button.get_global_rect()), "mobile information entry clipped")
	await _capture("mobile_entry")
	await _tap_screen(shell.weapon_info_button)
	_check(shell.weapon_info_dialog.visible and not shell.gear_scroller.enabled and not shell.tag_scroller.enabled, "mobile info permits background swipes")
	await _swipe(shell.gear_scroller, Vector2(340, 68), Vector2(220, 68), false)
	_check(shell.selected_item_key == "gun00", "mobile background changed selection")
	await _capture("mobile_details")
	menu._handle_back()
	_check(not shell.weapon_info_dialog.visible and shell.gear_scroller.enabled and shell.tag_scroller.enabled, "mobile Back failed to restore interaction")
	await _click(shell.weapon_info_button)
	await _click(shell.weapon_info_dialog.close_button)
	_check(shell.gear_scroller.enabled, "mobile close button left interaction locked")
	await _click(shell.action_button)
	_check(shell.upgrade_dialog.visible and not shell.weapon_info_dialog.visible, "upgrade flow broke after reading information")
	menu._handle_back()
	_check(GameState.credits == 5000 and GameState.mithril == 0 and GameState.owned_weapons == ["gun00"] and GameState.weapon_levels.is_empty(), "reading information changed wallet, ownership or upgrades")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await _frames(4)
	await get_tree().create_timer(0.25).timeout
	GameState.save_path = original_save
	TranslationServer.set_locale(original_locale)
	_check(FileAccess.get_sha256(original_save) == original_hash, "read-only test altered real save")
	print("WEAPON_MANUFACTURER_PASS" if failures.is_empty() else "WEAPON_MANUFACTURER_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)

func _tap_screen(control: Control) -> void:
	var point := get_viewport().get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 0
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)

func _capture(filename: String) -> void:
	if not capture:
		return
	await _frames(10)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/weapon_manufacturers/%s.png" % filename)
