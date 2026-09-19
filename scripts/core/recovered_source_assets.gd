class_name RecoveredSourceAssets
extends RefCounted

const CATALOG_PATH := "res://assets/recovered_sources/catalog.json"
static var _catalog: Dictionary = {}
static var _atlases: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary:
			_catalog = parsed
	return _catalog

static func audio_path(game: String, clip_name: String) -> String:
	return str(catalog().get("audio", {}).get(game + ":" + clip_name, ""))

static func sprite(game: String, atlas_name: String, sprite_name: String) -> AtlasTexture:
	var entry: Dictionary = catalog().get("ui", {}).get(game + ":" + atlas_name, {})
	var json_path := str(entry.get("atlas", ""))
	if json_path.is_empty():
		return null
	if not _atlases.has(json_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if not parsed is Dictionary:
			return null
		_atlases[json_path] = parsed.get("frames", {})
	var frames: Dictionary = _atlases[json_path]
	var key := sprite_name if frames.has(sprite_name) else sprite_name + ".png"
	if not frames.has(key):
		return null
	var frame: Dictionary = frames[key].frame
	var scale := float(entry.get("source_pixel_scale", 1.0))
	var result := AtlasTexture.new()
	result.atlas = load(str(entry.texture)) as Texture2D
	result.region = Rect2(float(frame.x) * scale, float(frame.y) * scale, float(frame.w) * scale, float(frame.h) * scale)
	result.filter_clip = true
	return result
