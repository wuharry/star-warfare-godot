extends Node

const EXPECTED_TEXTURE_COUNT := 321
# These are UI regions extracted losslessly from the recovered Unity atlases.
# Their source rectangles intentionally keep the original odd dimensions and
# are not part of the 2x texture-upscale corpus verified by this test. Armor
# variants and bags have their own stricter import/manifest coverage in
# avatar_import_test.gd, so they are kept out of this fixed legacy corpus.
const EXCLUDED_TEXTURE_PREFIXES := [
	"res://assets/ui/components/",
	"res://assets/ui/armor_thumbnails/",
	"res://assets/models/player/animated/armor_textures/",
	"res://assets/models/player/animated/bags/",
	# Projectile/VFX resolution and active large UI assets are validated by
	# hd_asset_coverage_test.gd; keep this fixed corpus focused on the original
	# 2x restoration set.
	"res://assets/models/projectiles/",
	"res://assets/vfx/legacy_hd/",
	# This optional imported character pack has its own coverage test and keeps
	# unimported source PNGs beside the generated runtime assets.
	"res://assets/callOfMini/enhanced/",
]
# Pages 11, 13 and 14 moved from 512x512 to 2048x2048 when they were
# re-extracted: Resources/ui/{11,13,14}.mat point at Texture2D/0/*.png, but the
# 256x256 same-named files from Texture2D/ had been picked up instead. The PvP
# level thumbnails live on page 14, and at the wrong size their rectangles fell
# off the end of the image.
const EXPECTED_DIMENSIONS := {
	"64x64": 3,
	"128x64": 2,
	"128x128": 5,
	"256x128": 4,
	"256x256": 14,
	"256x512": 1,
	"512x256": 2,
	"512x512": 87,
	"1024x256": 1,
	"1024x512": 4,
	"1024x1024": 130,
	"2048x128": 1,
	"2048x1024": 3,
	"2048x2048": 63,
	"4096x2048": 1,
}
const IMPORT_CHECKS := {
	"res://assets/icon.png": Vector2i(1024, 1024),
	"res://assets/models/player/animated/body.png": Vector2i(512, 512),
	"res://assets/models/levels/level_14/booox_003.png": Vector2i(2048, 2048),
	"res://assets/ui/HUD.png": Vector2i(2048, 2048),
	"res://assets/original/ui/pages/4.png": Vector2i(4096, 2048),
	"res://assets/original/ui/ngui/font/4/hud_4_0.png": Vector2i(64, 64),
}

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("TEXTURE UPSCALE TEST: " + message)

func _run() -> void:
	var texture_paths: Array[String] = []
	_collect_pngs("res://assets", texture_paths)
	texture_paths.sort()
	_check(
		texture_paths.size() == EXPECTED_TEXTURE_COUNT,
		"expected %d PNG textures, found %d" % [EXPECTED_TEXTURE_COUNT, texture_paths.size()]
	)

	var observed_dimensions: Dictionary = {}
	var largest_dimension := 0
	for texture_path: String in texture_paths:
		var image := Image.new()
		var image_error := image.load(ProjectSettings.globalize_path(texture_path))
		_check(image_error == OK, "source PNG could not be decoded: " + texture_path)
		if image_error != OK:
			continue
		var width := image.get_width()
		var height := image.get_height()
		var dimension_key := "%dx%d" % [width, height]
		observed_dimensions[dimension_key] = int(observed_dimensions.get(dimension_key, 0)) + 1
		largest_dimension = maxi(largest_dimension, maxi(width, height))
		_check(image.get_format() == Image.FORMAT_RGBA8, "%s is no longer RGBA8" % texture_path)
		_check(maxi(width, height) <= 4096, "%s exceeds the mobile-safe 4096-pixel limit" % texture_path)
		_check(FileAccess.file_exists(texture_path + ".import"), "missing import sidecar: " + texture_path)
		_check_import_settings(texture_path, width, height)

	for dimension_key: String in EXPECTED_DIMENSIONS:
		_check(
			int(observed_dimensions.get(dimension_key, 0)) == int(EXPECTED_DIMENSIONS[dimension_key]),
			"dimension %s expected %d textures, found %d" % [
				dimension_key,
				int(EXPECTED_DIMENSIONS[dimension_key]),
				int(observed_dimensions.get(dimension_key, 0)),
			]
		)
	for dimension_key: String in observed_dimensions:
		_check(EXPECTED_DIMENSIONS.has(dimension_key), "unexpected texture dimension: " + dimension_key)

	for texture_path: String in IMPORT_CHECKS:
		var texture := ResourceLoader.load(texture_path) as Texture2D
		_check(texture != null, "Godot could not import representative texture: " + texture_path)
		if texture != null:
			var imported_size := Vector2i(texture.get_width(), texture.get_height())
			_check(
				imported_size == IMPORT_CHECKS[texture_path],
				"Godot imported %s at %s instead of %s" % [texture_path, imported_size, IMPORT_CHECKS[texture_path]]
			)

	_check(
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "gl_compatibility",
		"desktop renderer is no longer GL Compatibility"
	)
	_check(
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "")) == "gl_compatibility",
		"mobile renderer is no longer GL Compatibility"
	)

	if failures.is_empty():
		print("TEXTURE_UPSCALE_TEST_PASS textures=%d max_dimension=%d" % [texture_paths.size(), largest_dimension])
		get_tree().quit(0)
	else:
		print("TEXTURE_UPSCALE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _collect_pngs(directory_path: String, texture_paths: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	_check(directory != null, "could not scan directory: " + directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var entry_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				_collect_pngs(entry_path, texture_paths)
			elif entry.get_extension().to_lower() == "png":
				var excluded := false
				for prefix: String in EXCLUDED_TEXTURE_PREFIXES:
					if entry_path.begins_with(prefix):
						excluded = true
						break
				if not excluded:
					texture_paths.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()

func _check_import_settings(texture_path: String, width: int, height: int) -> void:
	var import_config := ConfigFile.new()
	var error := import_config.load(texture_path + ".import")
	_check(error == OK, "invalid import sidecar for %s: %s" % [texture_path, error_string(error)])
	if error != OK:
		return
	_check(str(import_config.get_value("remap", "importer", "")) == "texture", "wrong importer for " + texture_path)
	var size_limit := int(import_config.get_value("params", "process/size_limit", 0))
	_check(
		size_limit <= 0 or maxi(width, height) <= size_limit,
		"%s is silently downscaled by process/size_limit=%d" % [texture_path, size_limit]
	)
	_check(
		bool(import_config.get_value("params", "process/fix_alpha_border", true)),
		"alpha-border repair is disabled for " + texture_path
	)
