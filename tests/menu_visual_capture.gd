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
	var passed := error == OK and armory_error == OK
	print("MENU_VISUAL_CAPTURE_PASS" if passed else "MENU_VISUAL_CAPTURE_FAIL")
	get_tree().quit(0 if passed else 1)
