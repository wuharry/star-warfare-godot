extends Node

func _ready() -> void:
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for _frame in range(8):
		await get_tree().process_frame
	var error := get_viewport().get_texture().get_image().save_png("res://tests/menu_restoration_preview.png")
	menu._show_armory()
	for _frame in range(4):
		await get_tree().process_frame
	var armory_error := get_viewport().get_texture().get_image().save_png("res://tests/armory_restoration_preview.png")
	var weapon_count_ok: bool = menu.store_weapon_row.get_child_count() == GameState.get_weapon_ids().size()
	var tabs_ok: bool = menu.store_category_buttons.size() == 6
	var slots_ok: bool = menu.store_slot_picker.item_count >= 1
	menu.equipment_shell._select_item("gun22", false)
	for _frame in range(4):
		await get_tree().process_frame
	var special_error := get_viewport().get_texture().get_image().save_png("res://tests/special_store_preview.png")
	menu.equipment_shell._select_item("gun23", false)
	for _frame in range(4):
		await get_tree().process_frame
	var additive_error := get_viewport().get_texture().get_image().save_png("res://tests/additive_store_preview.png")
	menu.equipment_shell.set_mode("customize", false)
	menu.equipment_shell._select_category("head", false)
	for _frame in range(4):
		await get_tree().process_frame
	var armor_error := get_viewport().get_texture().get_image().save_png("res://tests/armor_restoration_preview.png")
	var armor_count_ok: bool = menu.store_weapon_row.get_child_count() == GameState.get_armor_ids("head").size()
	menu.equipment_shell._select_category("bag", false)
	menu.equipment_shell._select_item(GameState.get_armor_ids("bag")[0], false)
	for _frame in range(4):
		await get_tree().process_frame
	var bag_error := get_viewport().get_texture().get_image().save_png("res://tests/bag_restoration_preview.png")
	var bag_count_ok: bool = menu.store_weapon_row.get_child_count() == GameState.get_armor_ids("bag").size()
	var design_ok: bool = menu.design_root.size.is_equal_approx(Vector2(960, 640))
	var passed: bool = error == OK and armory_error == OK and special_error == OK and additive_error == OK and armor_error == OK and bag_error == OK and weapon_count_ok and armor_count_ok and bag_count_ok and tabs_ok and slots_ok and design_ok
	print("MENU_VISUAL_CAPTURE_PASS" if passed else "MENU_VISUAL_CAPTURE_FAIL")
	get_tree().quit(0 if passed else 1)
