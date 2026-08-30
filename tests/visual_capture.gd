extends Node

func _ready() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(world)
	for _frame in range(12):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/restoration_preview.png")
	if error == OK:
		print("VISUAL_CAPTURE_PASS")
		get_tree().quit(0)
	else:
		push_error("Could not save rendered preview: %s" % error_string(error))
		get_tree().quit(1)
