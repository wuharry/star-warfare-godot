class_name OriginalAtlas
extends RefCounted

static var _frame_cache: Dictionary = {}

static func sprite(atlas_path: String, json_path: String, sprite_name: String) -> AtlasTexture:
	var frames := _frames(json_path)
	var key := sprite_name if sprite_name.ends_with(".png") else sprite_name + ".png"
	if not frames.has(key) or not ResourceLoader.exists(atlas_path):
		return null
	var frame: Dictionary = frames[key].frame
	return region(atlas_path, Rect2(float(frame.x), float(frame.y), float(frame.w), float(frame.h)))

static func region(texture_path: String, rectangle: Rect2) -> AtlasTexture:
	if not ResourceLoader.exists(texture_path):
		return null
	var texture := AtlasTexture.new()
	texture.atlas = load(texture_path)
	texture.region = rectangle
	return texture

static func weapon_icon(gun_id: int) -> AtlasTexture:
	var sprite_id := gun_id if gun_id < 39 else gun_id + 1
	return sprite(
		"res://assets/ui/weapons1.png",
		"res://assets/ui/weapons1.json",
		"weapons_%d" % sprite_id
	)

static func hud(sprite_name: String) -> AtlasTexture:
	return sprite(
		"res://assets/ui/HUD.png",
		"res://assets/ui/HUD.json",
		sprite_name
	)

static func _frames(json_path: String) -> Dictionary:
	if _frame_cache.has(json_path):
		return _frame_cache[json_path]
	if not FileAccess.file_exists(json_path):
		return {}
	var file := FileAccess.open(json_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var frames: Dictionary = parsed.get("frames", {}) if parsed is Dictionary else {}
	_frame_cache[json_path] = frames
	return frames

