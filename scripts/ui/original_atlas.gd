class_name OriginalAtlas
extends RefCounted

const SOURCE_PIXEL_SCALE := 2.0

static var _frame_cache: Dictionary = {}
static var _flipped_cache: Dictionary = {}

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
	# Atlas metadata and recovered UI layouts stay in the original 1x logical
	# coordinate space. The replacement PNGs contain exactly twice as many
	# source pixels on each axis, so convert only at this texture boundary.
	texture.region = Rect2(
		rectangle.position * SOURCE_PIXEL_SCALE,
		rectangle.size * SOURCE_PIXEL_SCALE
	)
	texture.filter_clip = true
	return texture

static func logical_size(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return texture.get_size() / SOURCE_PIXEL_SCALE

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

static func hud_flipped_h(sprite_name: String) -> Texture2D:
	return flipped_h("res://assets/ui/HUD.png", "res://assets/ui/HUD.json", sprite_name)

static func flipped_h(atlas_path: String, json_path: String, sprite_name: String) -> Texture2D:
	var cache_key := "%s:%s:%s" % [atlas_path, json_path, sprite_name]
	if _flipped_cache.has(cache_key):
		return _flipped_cache[cache_key]
	var base_texture := sprite(atlas_path, json_path, sprite_name)
	if base_texture == null:
		return null
	var atlas := base_texture.atlas as Texture2D
	if atlas == null:
		return base_texture
	var img := atlas.get_image()
	if img == null:
		return base_texture
	var sub := img.get_region(Rect2i(base_texture.region))
	sub.flip_x()
	var flipped := ImageTexture.create_from_image(sub)
	_flipped_cache[cache_key] = flipped
	return flipped

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
