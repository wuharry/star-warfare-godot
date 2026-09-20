extends "res://tests/mobile_store_sw1_test.gd"


func _run() -> void:
	var original_save := GameState.save_path
	GameState.save_path = "user://mobile_customize_sw1_%d.json" % Time.get_ticks_usec()
	GameState.weapon_levels.clear()
	GameState.armor_set_levels.clear()
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.owned_weapons.assign(["gun00", "gun01", "gun02", "gun03"])
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_weapon = "gun01" # CUSTOMIZE must start from primary, not this.
	GameState.package_slots.clear()
	GameState.package_storage.clear()
	GameState.owned_props = {"prop00": 3, "prop07": 1}
	GameState.credits = 999999999999
	GameState.mithril = 99999999
	GameState.owned_armor.append("armor_head_01")
	GameState.owned_armor.append("armor_body_01")
	var large_bag := ""
	for key: String in GameState.get_armor_ids("bag"):
		if int(GameState.ARMOR_ITEMS[key].bag_slots) >= 4:
			large_bag = key
			break
	GameState.owned_armor.append(large_bag)
	_check(not large_bag.is_empty(), "fixture needs a four-slot source backpack")
	capture = "--capture" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(2)
	menu._show_armory("customize")
	await _frames(5)
	shell = menu.equipment_shell
	_check(shell is MobileShell and shell.mode == "customize", "mobile CUSTOMIZE factory")
	_check(shell._ids == ["gun00", "gun01", "gun02", "gun03"], "CUSTOMIZE lists only owned guns in source order")
	_check(shell.selected_item_key == "gun00" and shell.equip_button.disabled, "CreateClone must use equipped primary")
	_check(shell._items_button.text == "PACK." and not shell.slot_picker.visible, "source PACK. entry, no desktop slot picker")
	_check(shell.equip_button.get_rect() == Rect2(735, 556, 170, 60), "source expanded EQUIP touch area")
	_check(shell.action_button.position + shell.detail_panel.position == Vector2(745, 491), "source UPGRADE rectangle")
	_check(shell.action_button.text == tr("UPGRADE") and not shell.action_button.disabled, "owned weapon must expose Upgrade separately from Equip")
	await _capture("customize_weapons")
	await _swipe(shell.gear_scroller, Vector2(340, 68), Vector2(220, 68), false)
	_check(shell.selected_item_key == "gun01" and GameState.battle_weapons[0] == "gun00", "swipe must preview without equipping")
	shell._select_category("head", false)
	_check(shell._ids.size() == 2, "owned armor filter")
	shell._select_item("armor_head_01", false)
	shell._select_category("body", false)
	shell._select_item("armor_body_01", false)
	shell._select_category("bag", false)
	shell._select_item(large_bag, false)
	_check(GameState.get_equipped_armor_key("head") == "armor_head_00", "outfit browsing wrote to save")
	shell._select_category("head", false)
	await _capture("customize_preview")
	var invalid: Dictionary = shell.preview_selection.duplicate()
	invalid.head = "armor_head_28"
	var original_outfit := GameState.equipped_armor.duplicate()
	_check(not GameState.apply_equipment_preview(invalid) and GameState.equipped_armor == original_outfit and GameState.battle_weapons[0] == "gun00", "unowned preview must reject atomically")
	await _tap_native_button(shell.equip_button)
	_check(GameState.battle_weapons[0] == "gun01" and GameState.get_equipped_armor_key("head") == "armor_head_01" and GameState.get_equipped_armor_key("body") == "armor_body_01" and GameState.get_equipped_armor_key("bag") == large_bag, "EQUIP must commit all six preview selections")
	_check(shell.equip_button.disabled and not shell.action_button.visible, "equipped armor button states")
	await _capture("customize_equipped")
	shell._select_category("arms", false)
	_check(shell._ids.size() == 1, "single owned part fixture")
	var locations: Array[Vector2] = []
	for card: Control in shell.gear_cards:
		if card.visible:
			_check(not locations.has(card.position), "single owned item copies overlap")
			locations.append(card.position)
	_check(locations.size() >= 4, "original small-list carousel repeats missing")
	# PACK opens from a real button, works on equipped state, discards preview on return.
	shell._select_category("head", false)
	shell._select_item("armor_head_00", false)
	await _tap_native_button(shell._items_button)
	var page: Control = shell.package_page
	_check(is_instance_valid(page) and shell.screen_title.text == "PACKAGE" and not shell.gear_scroller.enabled, "PACKAGE navigation")
	_check(page.scroller.get_rect() == Rect2(0, 83, 710, 385) and page.bag_cells.size() == GameState.get_bag_capacity(), "source storage/bag layout")
	await _capture("package_inventory")
	var gun_index: int = page.storage.find("gun02")
	await _move_item(page, Vector2i(1, gun_index), Vector2i(0, 1))
	_check(GameState.battle_weapons == ["gun01", "gun02"], "vertical storage drag must equip gun in empty slot")
	await _move_item(page, Vector2i(0, 1), Vector2i(0, 0))
	_check(GameState.battle_weapons == ["gun02", "gun01"], "bag drag must swap primary without duplicates")
	var prop_index: int = page.storage.find("prop00")
	await _move_item(page, Vector2i(1, prop_index), Vector2i(0, 2))
	_check(GameState.get_package_slots()[2] == "prop00" and GameState.get_prop_count("prop00") == 3, "prop reservation must not consume owned items")
	_check(page.storage.has("prop00"), "remaining prop stack disappeared")
	await _capture("package_props")
	await _move_item(page, Vector2i(0, 2), Vector2i(1, page.storage.find("prop00")))
	_check(GameState.get_package_slots()[2].is_empty() and GameState.get_prop_count("prop00") == 3, "returning prop must merge into its stack without consuming it")
	await _move_item(page, Vector2i(1, page.storage.find("prop00")), Vector2i(0, 2))
	var slots_before := GameState.get_package_slots()
	_touch(page, page.cell_rect(Vector2i(0, 0)).get_center(), true)
	_drag(page, Vector2(900, 630))
	_touch(page, Vector2(900, 630), false)
	_check(GameState.get_package_slots() == slots_before, "outside drop mutated package")
	# Navigation interruption cancels an in-flight drag; secondary fingers cannot steal it.
	_touch(page, page.cell_rect(Vector2i(0, 0)).get_center(), true, 1)
	_drag(page, Vector2(300, 470), 1)
	_touch(page, Vector2(300, 470), true, 2)
	_drag(page, page.cell_rect(Vector2i(0, 1)).get_center(), 2)
	_touch(page, page.cell_rect(Vector2i(0, 1)).get_center(), false, 2)
	_check(page.finger == 1, "second finger stole package drag")
	menu._toggle_drawer(true, false)
	_check(page.finger == -1 and not page.cursor.visible and not page.enabled, "drawer failed to cancel item drag")
	menu._handle_back()
	_check(page.enabled and not shell.gear_scroller.enabled, "drawer close enabled hidden carousel")
	_touch(page, Vector2(300, 470), false, 1)
	_check(GameState.get_package_slots() == slots_before, "interrupted drag applied after drawer close")
	# Horizontal gestures anywhere on inventory tiles swipe pages, not items.
	var p := Vector2(420, 275)
	_touch(page, p, true)
	for index in range(1, 9):
		_drag(page, p - Vector2(index * 31.25, 0))
		await _frames(1)
	_drag(page, p - Vector2(250, 0))
	_touch(page, p - Vector2(250, 0), false)
	await get_tree().create_timer(0.3).timeout
	_check(is_equal_approx(page.scroller.offset, 250) and GameState.get_package_slots() == slots_before, "inventory horizontal swipe should change page only")
	page.scroller.select(0)
	# Last-weapon rejection exercises the real transaction used by drag/drop.
	var only_gun: Array[String] = ["gun00"]
	GameState.set_package(only_gun, [])
	page._refresh_inventory()
	var empty_storage: int = page.storage.find("")
	await _move_item(page, Vector2i(0, 0), Vector2i(1, empty_storage))
	_check(GameState.battle_weapons == ["gun00"] and not page.notice.text.is_empty(), "last weapon must remain carried with feedback")
	# Save round-trip retains stack reservations and sparse carry slots.
	var sparse: Array[String] = ["prop00", "", "gun02", "gun01"]
	_check(GameState.set_package(sparse, page.storage), "valid sparse package rejected")
	GameState.package_slots.clear()
	GameState._load_save()
	_check(GameState.get_package_slots() == sparse and GameState.battle_weapons == ["gun02", "gun01"], "package persistence round-trip")
	GameState.set_loadout_weapon(1, "gun03")
	_check(GameState.get_package_slots()[1] == "gun03" and GameState.get_prop_count("prop00") == 3, "desktop loadout change must override stale mobile arrangement without consuming props")
	GameState.set_package(sparse, page.storage)
	menu._handle_back()
	await _frames(3)
	_check(shell.package_page == null and shell.screen_title.text == tr("CUSTOMIZE"), "PACKAGE Back must restore the localized CUSTOMIZE title")
	_check(shell.preview_selection.head == GameState.get_equipped_armor_key("head"), "PACKAGE Back must return to actual outfit")
	# Shrinking the bag retains the selected primary and ownership of overflow.
	var outfit: Dictionary = shell.preview_selection.duplicate()
	outfit.bag = "armor_bag_00"
	outfit.gun = "gun01"
	var owned_before := GameState.owned_weapons.duplicate()
	_check(GameState.apply_equipment_preview(outfit), "bag shrink failed")
	_check(GameState.battle_weapons[0] == "gun01" and GameState.owned_weapons == owned_before and GameState.get_package_slots().size() == GameState.get_bag_capacity(), "bag shrink lost primary or ownership")
	await _frames(3)
	shell.set_mode("customize", false)
	get_window().content_scale_size = Vector2i(1600, 720)
	await _frames(4)
	await _capture("customize_wide")
	var head_before := GameState.get_equipped_armor_key("head")
	shell._select_category("head", false)
	shell._select_item("armor_head_00", false)
	menu._handle_back()
	await _frames(3)
	_check(menu.equipment_shell == null and GameState.get_equipped_armor_key("head") == head_before, "Back must discard unapplied outfit")
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	menu._show_armory("customize")
	await _frames(3)
	_check(not menu.equipment_shell is MobileShell, "desktop CUSTOMIZE switched to mobile shell")
	await _capture("desktop_customize")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await _frames(3)
	await get_tree().create_timer(0.25).timeout
	for suffix: String in ["", ".bak", ".tmp"]:
		var isolated := ProjectSettings.globalize_path(GameState.save_path + suffix)
		if FileAccess.file_exists(isolated):
			DirAccess.remove_absolute(isolated)
	GameState.save_path = original_save
	print("MOBILE_CUSTOMIZE_SW1_PASS" if failures.is_empty() else "MOBILE_CUSTOMIZE_SW1_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _move_item(page: Control, source: Vector2i, target: Vector2i) -> void:
	var start: Vector2 = page.cell_rect(source).get_center()
	var finish: Vector2 = page.cell_rect(target).get_center()
	_touch(page, start, true)
	_drag(page, start + Vector2(0, 18)) # UISliderStorage's vertical drag threshold.
	await _frames(1)
	_drag(page, finish)
	await _frames(1)
	_touch(page, finish, false)
	await _frames(3)


func _tap_native_button(control: Control) -> void:
	# Enter at Input so Godot runs native touch-to-mouse emulation for Buttons.
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = get_viewport().get_final_transform() * point
		event.index = 0
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _capture(filename: String) -> void:
	if not capture:
		return
	await _frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/mobile_customize_sw1/%s.png" % filename)
