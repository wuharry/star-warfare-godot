extends Node

# Renders one sector at four pinned hours and composes them into a single
# 2x2 sheet, so the timecycle can be reviewed as art rather than as numbers.
# Run it with a real display (no --headless), same as the other captures.

const CAPTURES := [
	{"hour": 6.0, "name": "sunrise"},
	{"hour": 12.5, "name": "noon"},
	{"hour": 19.0, "name": "sunset"},
	{"hour": 22.0, "name": "night"},
]
const OUTPUT_PATH := "res://tests/day_night_preview.png"

func _ready() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	# Pinning the clock keeps every tile of the sheet reproducible.
	GameState.settings.day_length = "frozen"

	var viewport_size := get_viewport().get_visible_rect().size
	var tile_size := Vector2i(int(viewport_size.x) / 2, int(viewport_size.y) / 2)
	var sheet := Image.create_empty(tile_size.x * 2, tile_size.y * 2, false, Image.FORMAT_RGBA8)

	for index in range(CAPTURES.size()):
		var capture: Dictionary = CAPTURES[index]
		GameState.settings.frozen_hour = float(capture.hour)
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate()
		add_child(world)
		for _frame in range(14):
			await get_tree().process_frame
		var shot := get_viewport().get_texture().get_image()
		shot.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_LANCZOS)
		if shot.get_format() != sheet.get_format():
			shot.convert(sheet.get_format())
		sheet.blit_rect(
			shot,
			Rect2i(Vector2i.ZERO, tile_size),
			Vector2i((index % 2) * tile_size.x, (index / 2) * tile_size.y)
		)
		world.queue_free()
		await get_tree().process_frame

	var error := sheet.save_png(OUTPUT_PATH)
	if error == OK:
		print("DAY_NIGHT_CAPTURE_PASS %s" % OUTPUT_PATH)
		get_tree().quit(0)
	else:
		push_error("Could not save the day/night sheet: %s" % error_string(error))
		get_tree().quit(1)
