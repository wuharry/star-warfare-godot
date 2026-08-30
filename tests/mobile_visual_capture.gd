extends Node

func _ready() -> void:
	GameState.selected_level = 1
	GameState.settings.show_touch_controls = true
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(world)
	for _frame in range(12):
		await get_tree().process_frame
	var error := get_viewport().get_texture().get_image().save_png("res://tests/mobile_restoration_preview.png")
	if error == OK:
		print("MOBILE_VISUAL_CAPTURE_PASS")
		get_tree().quit(0)
	else:
		push_error("Could not save mobile preview: %s" % error_string(error))
		get_tree().quit(1)
