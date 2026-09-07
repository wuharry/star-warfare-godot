extends Node

# The eight maps whose source materials used Unity's legacy direct texture
# dictionary (plus the three largest arenas that previously exceeded Godot's
# mesh-surface limit). Tiles are ordered left-to-right, top-to-bottom.
const LEVELS := [8, 13, 14, 17, 18, 19, 20, 21]
const OUTPUT_PATH := "res://tests/scene_restoration_preview.png"

var levels: Array = LEVELS.duplicate()
var output_dir := ""
var quality := "high"


func _ready() -> void:
	GameState.save_path = "user://scene_visual_capture_profile.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--quality="):
			quality = argument.trim_prefix("--quality=")
		elif argument.begins_with("--levels="):
			levels.clear()
			for value: String in argument.trim_prefix("--levels=").split(","):
				levels.append(int(value))
	if levels.is_empty() or quality not in ["low", "medium", "high"]:
		push_error("Capture requires levels and a supported quality setting")
		get_tree().quit(1)
		return
	if not output_dir.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		if directory_error != OK:
			push_error("Could not create capture directory: " + error_string(directory_error))
			get_tree().quit(1)
			return
	GameState.selected_weapon = "gun00"
	GameState.equipped_armor = {"head": "armor_head_00", "body": "armor_body_00", "arms": "armor_arms_00", "legs": "armor_legs_00", "bag": "armor_bag_00"}
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = quality

	var viewport_size := Vector2i(get_viewport().get_visible_rect().size)
	var tile_size := Vector2i(viewport_size.x / 2, viewport_size.y / 2)
	var sheet := Image.create_empty(tile_size.x * 4, tile_size.y * ceili(levels.size() / 4.0), false, Image.FORMAT_RGBA8)
	var captures: Array[Dictionary] = []
	for index in levels.size():
		seed(1633)
		GameState.selected_level = levels[index]
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		add_child(world)
		world.completed = true
		world.player.set_physics_process(false)
		for _frame in 12:
			await get_tree().process_frame
		world.hud.visible = false
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		if not output_dir.is_empty():
			var filename := "level_%02d.png" % int(levels[index])
			var capture_error := shot.save_png(output_dir.path_join(filename))
			if capture_error != OK:
				push_error("Could not save " + filename)
				get_tree().quit(1)
				return
			captures.append({"level": levels[index], "file": filename})
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

	var destination := OUTPUT_PATH if output_dir.is_empty() else output_dir.path_join("scene_restoration_preview.png")
	var error := sheet.save_png(destination)
	if not output_dir.is_empty():
		var manifest := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
		if manifest == null:
			push_error("Could not save scene capture manifest")
			get_tree().quit(1)
			return
		manifest.store_string(JSON.stringify({
			"viewport": [viewport_size.x, viewport_size.y],
			"renderer": RenderingServer.get_current_rendering_method(),
			"quality": quality,
			"render_scale": get_viewport().scaling_3d_scale,
			"msaa_3d": get_viewport().msaa_3d,
			"captures": captures,
		}, "\t"))
	if error == OK:
		print("SCENE_VISUAL_CAPTURE_PASS %s levels=%s quality=%s" % [destination, levels, quality])
		get_tree().quit(0)
	else:
		push_error("Could not save the scene restoration sheet: %s" % error_string(error))
		get_tree().quit(1)
