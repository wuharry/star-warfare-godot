extends Node

const MobileShell = preload("res://scripts/ui/mobile_sw1_equipment_shell.gd")
var failures: Array[String] = []
var menu: Control
var shell: Control
var capture := false


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MOBILE STORE: " + message)


func _run() -> void:
	var original_save := GameState.save_path
	GameState.save_path = "user://mobile_store_sw1_%d.json" % Time.get_ticks_usec()
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.owned_weapons.assign(["gun00"])
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_weapon = "gun00"
	GameState.owned_props.clear()
	GameState.credits = 999999999999
	GameState.mithril = 99999999
	capture = "--capture" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._show_armory("store")
	await _frames(5)
	shell = menu.equipment_shell
	_check(shell is MobileShell, "mobile factory did not instantiate the SW1 shell")
	_check(shell.size == Vector2(960, 640) and not shell.desktop_layout, "source design size")
	_check(shell.tag_scroller.get_rect() == Rect2(177, 494, 450, 99), "source category rectangle")
	_check(shell.detail_panel.get_rect() == Rect2(704, 240, 232, 374), "source detail rectangle")
	_check(shell.name_label.position + shell.detail_panel.position == Vector2(726, 248), "source title position")
	_check(shell.action_button.position + shell.detail_panel.position == Vector2(747, 526), "source purchase position")
	_check(shell.preview_root.get_node_or_null("StoreAvatarDisplay/RecoveredStoreAvatar") != null, "store does not preview the armed avatar")
	_check(menu.drawer.visible and menu.drawer.z_index > menu.modal_layer.z_index, "source rank drawer hidden behind store")
	_check(menu.mobile_armory_matte.visible and menu.mobile_armory_matte.color == Color.BLACK, "source black widescreen margins missing")
	await _capture("mobile_weapons")
	var owned_before: Array = GameState.owned_weapons.duplicate()
	var equipment_before: Dictionary = GameState.equipped_armor.duplicate()
	var cash_before := GameState.credits
	var selected_before: String = shell.selected_item_key
	await _swipe(shell.gear_scroller, Vector2(410, 68), Vector2(170, 68))
	_check(shell.selected_item_key != selected_before, "touch swipe did not select another weapon")
	_check(GameState.owned_weapons == owned_before and GameState.equipped_armor == equipment_before and GameState.credits == cash_before, "browsing mutated ownership, equipment or wallet")
	var ids: Array = shell._get_category_ids()
	shell._select_item(ids.back(), false)
	await _frames(2)
	await _swipe(shell.gear_scroller, Vector2(340, 68), Vector2(220, 68), false)
	_check(shell.selected_item_key == ids[0], "last-to-first cyclic swipe")
	shell._select_item(ids[0], false)
	await _swipe(shell.gear_scroller, Vector2(220, 68), Vector2(340, 68), false)
	_check(shell.selected_item_key == ids.back(), "first-to-last cyclic swipe")
	# A second finger cannot steal the first pointer or invoke a purchase.
	var initial_offset: float = shell.gear_scroller.offset
	_touch(shell.gear_scroller, Vector2(300, 68), true, 1)
	_touch(shell.gear_scroller, Vector2(300, 68), true, 2)
	_drag(shell.gear_scroller, Vector2(100, 68), 2)
	_touch(shell.gear_scroller, Vector2(100, 68), false, 2)
	_check(shell.gear_scroller.finger == 1 and shell.gear_scroller.offset == initial_offset, "second finger hijacked drag")
	_touch(shell.gear_scroller, Vector2(300, 68), false, 1, true)
	_check(shell.gear_scroller.finger == -1 and not shell.gear_scroller.moving, "canceled touch stuck")
	await _swipe(shell.tag_scroller, Vector2(260, 50), Vector2(170, 50), false)
	await get_tree().create_timer(0.4).timeout
	_check(shell.selected_category == "head", "category wrap from gun to head")
	await _capture("mobile_armor")
	var retained: String = shell.selected_item_key
	shell._select_category("gun", false)
	shell._select_category("head", false)
	_check(shell.selected_item_key == retained, "preview selection was lost on category round-trip")
	menu._toggle_drawer(true, false)
	_check(not shell.gear_scroller.enabled, "open navigation drawer did not block gestures behind it")
	await _capture("mobile_navigation")
	menu._handle_back()
	_check(not menu.drawer_open and is_instance_valid(menu.equipment_shell), "Back should close drawer first")
	shell._select_supply_category("health", false)
	await _frames(3)
	_check(shell.props_scroller.get_rect() == Rect2(275, 107, 685, 450), "source props clipping rectangle")
	_check(shell.prop_cards.size() == 6 and not shell.preview_panel.visible, "props page layout")
	await _capture("mobile_items")
	var props_before: int = GameState.get_prop_count("prop00")
	# Drag begins on BUY, but must never buy on release.
	await _swipe(shell.props_scroller, Vector2(510, 270), Vector2(510, 120))
	_check(GameState.get_prop_count("prop00") == props_before, "drag starting on Buy purchased a prop")
	shell.props_scroller.select(0)
	_touch(shell.props_scroller, Vector2(510, 270), true)
	_drag(shell.props_scroller, Vector2(510, 255))
	_touch(shell.props_scroller, Vector2(510, 255), false)
	_touch(shell.props_scroller, Vector2(510, 270), true)
	_touch(shell.props_scroller, Vector2(510, 270), false)
	await get_tree().create_timer(0.2).timeout
	_check(GameState.get_prop_count("prop00") == props_before, "tap to stop inertia purchased a prop")
	shell.props_scroller.select(0)
	shell.selected_item_key = "prop00"
	GameState.credits = 100000
	var count_before: int = GameState.get_prop_count("prop00")
	_touch(shell.props_scroller, Vector2(510, 270), true)
	_touch(shell.props_scroller, Vector2(510, 270), false)
	await _frames(2)
	_check(GameState.get_prop_count("prop00") == count_before + 1, "tap on supply Buy did not add exactly one item")
	_check(GameState.credits == 100000 - int(GameState.PROPS.prop00.price), "supply purchase charged wrong amount")
	menu._handle_back()
	_check(is_instance_valid(menu.equipment_shell) and shell.selected_section == "equipment", "Back from ITEMS should return to gear")
	# Real controls route through the existing transaction functions.
	shell._select_category("gun", false)
	shell._select_item("gun01", false)
	await _frames(2)
	GameState.credits = 0
	await _click(shell.action_button)
	_check(not GameState.is_weapon_owned("gun01") and GameState.credits == 0, "insufficient-cash purchase mutated state")
	_check(not shell.notice_label.text.is_empty(), "failed purchase has no feedback")
	GameState.credits = 100000
	await _click(shell.action_button)
	_check(GameState.is_weapon_owned("gun01") and GameState.credits == 75000, "weapon Buy charged wrong amount or failed")
	await _click(shell.action_button)
	_check(GameState.credits == 75000, "owned weapon charged twice")
	shell.set_mode("customize", false)
	shell._select_item("gun01", false)
	await _frames(2)
	await _click(shell.action_button)
	_check(GameState.battle_weapons[0] == "gun01", "mobile Equip did not update loadout")
	await _capture("mobile_customize")
	shell.set_mode("store", false)
	shell._select_category("head", false)
	shell._select_item("armor_head_01", false)
	GameState.credits = 99999999
	GameState.mithril = 99999999
	await _frames(2)
	await _click(shell.action_button)
	_check(GameState.is_armor_owned("armor_head_01"), "armor Buy did not grant ownership")
	# Paid CoM suits must still grant all four parts in the mobile adapter.
	GameState.experience = 99999999
	shell._select_item("armor_head_21", false)
	await _frames(2)
	await _click(shell.action_button)
	for part: String in ["head", "body", "arms", "legs"]:
		_check(GameState.is_armor_owned("armor_%s_21" % part), "whole-suit purchase omitted " + part)
	for key: String in ["body", "arms", "legs", "bag"]:
		shell._select_category(key, false)
		await _frames(2)
		_check(shell.gear_scroller.count == GameState.get_armor_ids(key).size(), "category lost catalog entries: " + key)
	await _capture("mobile_backpack")
	var ammo_cash := GameState.credits
	shell._show_ammo()
	await _frames(2)
	_check(shell._ammo_dialog.visible and not shell.gear_scroller.enabled, "AMMO dialog did not block background gestures")
	menu._handle_back()
	_check(not shell._ammo_dialog.visible and shell.gear_scroller.enabled and GameState.credits == ammo_cash, "AMMO notice changed wallet or failed to return")
	# SW1's 960 x 640 canvas must remain centered on wider landscape phones.
	get_window().content_scale_size = Vector2i(1600, 720)
	await _frames(3)
	_check(menu.design_root.position.x > 0 and menu.design_root.scale.x == menu.design_root.scale.y, "wide mobile canvas stretched or lost centering")
	shell._select_category("gun", false)
	shell._select_item("gun00", false)
	await _frames(2)
	await _swipe(shell.gear_scroller, Vector2(340, 68), Vector2(220, 68), false)
	_check(shell.selected_item_key == "gun01", "wide-phone touch coordinates do not match the visual carousel")
	await _capture("mobile_wide")
	get_window().content_scale_size = Vector2i(960, 640)
	await _frames(3)
	_check(menu.equipment_shell is MobileShell and shell.size == Vector2(960, 640), "source aspect-ratio phone lost mobile shell")
	await _capture("mobile_source_aspect")
	menu._handle_back()
	await _frames(2)
	_check(menu.equipment_shell == null and menu.drawer.z_index == 6, "Back failed to restore menu drawer layering")
	_check(not menu.mobile_armory_matte.visible, "mobile matte leaked into main menu")
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	menu._show_armory("store")
	await _frames(3)
	_check(not menu.equipment_shell is MobileShell and menu.equipment_shell.item_row.columns == 3, "narrow desktop changed to mobile UI")
	get_window().content_scale_size = Vector2i(1280, 720)
	await _frames(3)
	_check(not menu.equipment_shell is MobileShell and menu.equipment_shell.item_row.columns == 3, "desktop grid was replaced")
	await _capture("desktop_unchanged")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await _frames(3)
	await get_tree().create_timer(0.25).timeout
	var isolated := ProjectSettings.globalize_path(GameState.save_path)
	if FileAccess.file_exists(isolated):
		DirAccess.remove_absolute(isolated)
	GameState.save_path = original_save
	print("MOBILE_STORE_SW1_PASS" if failures.is_empty() else "MOBILE_STORE_SW1_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame


func _touch(control: Control, point: Vector2, pressed: bool, index := 0, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = control.get_global_transform_with_canvas() * point
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	get_viewport().push_input(event, true)


func _drag(control: Control, point: Vector2, index := 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = control.get_global_transform_with_canvas() * point
	event.index = index
	get_viewport().push_input(event, true)


func _click(control: Control) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_transform_with_canvas() * (control.size * 0.5)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await _frames(2)


func _swipe(control: Control, start: Vector2, end: Vector2, inertia := true) -> void:
	_touch(control, start, true)
	for index in range(1, 9):
		_drag(control, start.lerp(end, index / 8.0))
		await get_tree().process_frame
	if not inertia:
		_drag(control, end) # Stationary release, no last-frame fling.
	_touch(control, end, false)
	for index in 160:
		if not control.moving:
			break
		await get_tree().create_timer(0.01).timeout
	_check(not control.moving, "carousel failed to settle")


func _capture(filename: String) -> void:
	if not capture:
		return
	await _frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/mobile_store_sw1/%s.png" % filename)
