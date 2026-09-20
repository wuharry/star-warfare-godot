extends "res://tests/desktop_armory_ui_test.gd"

func _run() -> void:
	var original_save := GameState.save_path
	GameState.save_path = "user://equipment_upgrade_ui_%d.json" % Time.get_ticks_usec()
	GameState.owned_weapons.assign(["gun00"])
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_weapon = "gun00"
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.weapon_levels.clear()
	GameState.armor_set_levels.clear()
	for part in range(4):
		GameState.owned_armor.append(GameState.ArmorCatalogData.item_key(part, 21))
	GameState.credits = 100000
	GameState.mithril = 100
	GameState.experience = 0
	capture = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/equipment_upgrades"))
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(3)
	menu._show_armory("store")
	await _frames(4)
	shell = menu.equipment_shell
	_check(shell.upgrade_button.visible and shell.meta_label.text == "LV 1 / 8", "owned desktop weapon upgrade entry")
	await _click(shell.upgrade_button)
	_check(shell.upgrade_dialog.visible and shell.upgrade_dialog.quote.credits == 4500, "desktop quote missing/wrong price")
	await _capture("desktop_weapon_quote")
	await _click(shell.upgrade_dialog.cancel_button)
	_check(GameState.get_equipment_level("gun00") == 1 and GameState.credits == 100000, "cancel spent money")
	await _click(shell.upgrade_button)
	await _key(KEY_ESCAPE)
	_check(not shell.upgrade_dialog.visible and menu.equipment_shell == shell, "Escape closed the shop instead of the quote")
	await _click(shell.upgrade_button)
	await _key(KEY_TAB)
	_check(get_viewport().gui_get_focus_owner() == shell.upgrade_dialog.cancel_button, "Tab escaped the upgrade dialog")
	await _key(KEY_TAB)
	_check(get_viewport().gui_get_focus_owner() == shell.upgrade_dialog.confirm_button, "Tab did not cycle within the quote")
	# Selection changes cannot redirect an already opened quote.
	shell._select_item("gun01", false)
	await _key(KEY_ENTER)
	_check(GameState.get_equipment_level("gun00") == 2 and not GameState.is_weapon_owned("gun01"), "confirm targeted a different item")
	_check(GameState.credits == 95500, "confirmation used wrong price or charged twice")
	shell.upgrade_dialog._confirm()
	_check(GameState.credits == 95500, "hidden quote accepted a repeated confirm")
	shell._select_item("gun00", false)
	_check(shell.stats_text.text.contains("23") and shell.meta_label.text == "LV 2 / 8", "desktop details did not show upgraded weapon")
	await _capture("desktop_weapon_lv2")
	GameState.credits = 0
	shell._refresh_details()
	await _click(shell.upgrade_button)
	_check(shell.upgrade_dialog.confirm_button.disabled, "insufficient wallet can confirm")
	await _capture("desktop_insufficient")
	menu._handle_back()
	_check(not shell.upgrade_dialog.visible and GameState.credits == 0, "Back did not cancel quote")
	GameState.credits = 100000
	GameState.armor_set_levels["21"] = 4
	GameState.equip_armor_set(21)
	shell._select_category("head", false)
	shell._select_item("armor_head_21", false)
	await _click(shell.upgrade_button)
	_check(shell.upgrade_dialog.quote.credits == 0 and shell.upgrade_dialog.quote.mithril == 25, "premium stage displays wrong currency")
	await _capture("desktop_suit_quote")
	await _click(shell.upgrade_dialog.confirm_button)
	_check(GameState.get_equipment_level("armor_legs_21") == 5 and GameState.mithril == 75, "whole suit not upgraded together")
	_check(shell.description_text.text.contains("234"), "full suit description stayed at base HP")
	# Mobile's original UPGRADE rectangle now invokes the same transaction.
	menu._close_modal()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	menu._show_armory("customize")
	await _frames(5)
	shell = menu.equipment_shell
	_check(shell.action_button.visible and not shell.action_button.disabled and shell.price_label.text == "$7,500", "mobile Upgrade entry/price")
	_check(shell.state_label.text == "LV 2 / 8" and shell.stats_text.text.contains("23 (+4)"), "mobile current and next weapon damage")
	await _capture("mobile_weapon")
	await _click(shell.action_button)
	_check(not shell.gear_scroller.enabled and not shell.tag_scroller.enabled, "modal allows background carousel input")
	var selected: String = shell.selected_item_key
	await _swipe(shell.gear_scroller, Vector2(340, 68), Vector2(220, 68), false)
	_check(shell.selected_item_key == selected, "background swipe retargeted upgrade")
	menu._handle_back()
	_check(shell.gear_scroller.enabled and shell.tag_scroller.enabled, "cancel left mobile locked")
	await _click(shell.action_button)
	await _click(shell.upgrade_dialog.confirm_button)
	await _frames(4)
	_check(GameState.get_equipment_level("gun00") == 3 and shell.state_label.text == "LV 3 / 8", "mobile confirm did not refresh level")
	shell._show_package()
	await _frames(3)
	var package: Control = shell.package_page
	var bag_index: int = package.slots.find("gun00")
	package._select(Vector2i(0, bag_index) if bag_index >= 0 else Vector2i(1, package.storage.find("gun00")))
	_check(package.stats.text.contains("POW 27"), "PACKAGE shows base damage after upgrading")
	menu._handle_back()
	await _frames(2)
	shell._select_category("head", false)
	shell._select_item("armor_head_21", false)
	await _click(shell.action_button)
	_check(shell.upgrade_dialog.visible and shell.upgrade_dialog.quote.mithril == 49, "mobile CoM suit upgrade")
	await _capture("mobile_suit_quote")
	await _click(shell.upgrade_dialog.confirm_button)
	await _frames(4)
	_check(GameState.get_equipment_level("armor_body_21") == 6 and GameState.mithril == 26, "mobile premium charge/shared level")
	_check(shell.description_text.get_global_rect().end.y <= shell.action_button.get_global_rect().position.y, "mobile suit description overlaps upgrade button")
	await _capture("mobile_suit_lv6")
	GameState.weapon_levels.gun00 = 8
	shell._select_category("gun", false)
	shell._select_item("gun00", false)
	_check(shell.action_button.disabled and shell.action_button.text == tr("MAX LEVEL"), "max-level upgrade still enabled")
	await _capture("mobile_max")
	shell._select_category("head", false)
	shell._select_item("armor_head_00", false)
	_check(not shell.action_button.visible, "unsupported SW1 armor got an Upgrade button")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await _frames(4)
	await get_tree().create_timer(0.25).timeout
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(GameState.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameState.save_path = original_save
	print("EQUIPMENT_UPGRADE_UI_PASS" if failures.is_empty() else "EQUIPMENT_UPGRADE_UI_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)

func _capture(filename: String) -> void:
	if not capture:
		return
	await _frames(10)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/equipment_upgrades/%s.png" % filename)
