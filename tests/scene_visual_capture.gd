extends Node

# The eight maps whose source materials used Unity's legacy direct texture
# dictionary (plus the three largest arenas that previously exceeded Godot's
# mesh-surface limit). Tiles are ordered left-to-right, top-to-bottom.
const LEVELS := [8, 13, 14, 17, 18, 19, 20, 21]
const OUTPUT_PATH := "res://tests/scene_restoration_preview.png"


func _ready() -> void:
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	GameState.settings.day_length = "frozen"
	GameState.settings.frozen_hour = 12.5

	var viewport_size := Vector2i(get_viewport().get_visible_rect().size)
	var tile_size := Vector2i(viewport_size.x / 2, viewport_size.y / 2)
	var sheet := Image.create_empty(tile_size.x * 4, tile_size.y * 2, false, Image.FORMAT_RGBA8)
	for index in LEVELS.size():
		GameState.selected_level = LEVELS[index]
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		add_child(world)
		for _frame in 12:
			await get_tree().process_frame
		world.hud.visible = false
		await get_tree().process_frame
		var shot := get_viewport().get_texture().get_image()
		shot.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_LANCZOS)
		if shot.get_format() != sheet.get_format():
			shot.convert(sheet.get_format())
		sheet.blit_rect(
			shot,
			Rect2i(Vector2i.ZERO, tile_size),
			Vector2i((index % 4) * tile_size.x, (index / 4) * tile_size.y)
		)
		world.completed = true
		for audio in world.find_children("*", "AudioStreamPlayer", true, false):
			audio.stop()
		for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
		world.free()
		await get_tree().process_frame

	var error := sheet.save_png(OUTPUT_PATH)
	if error == OK:
		print("SCENE_VISUAL_CAPTURE_PASS %s levels=%s" % [OUTPUT_PATH, LEVELS])
		get_tree().quit(0)
	else:
		push_error("Could not save the scene restoration sheet: %s" % error_string(error))
		get_tree().quit(1)
