extends Node

const CATEGORY_MIN_LONG_EDGE := {
	"res://assets/models/weapons": 512,
	"res://assets/models/enemies": 512,
	"res://assets/vfx/legacy_hd": 512,
}
const REQUIRED_RUNTIME_ASSETS := {
	"res://assets/models/projectiles/gun0910_hd.png": Vector2i(1024, 1024),
	"res://assets/models/projectiles/plasma_bolt1_red.png": Vector2i(512, 512),
	"res://assets/ui/components/store_backdrop.png": Vector2i(960, 1280),
	"res://assets/ui/components/menu_hero.png": Vector2i(1920, 1280),
	"res://assets/ui/components/main_bottom_panel.png": Vector2i(1920, 300),
	"res://assets/ui/components/main_nav_panel.png": Vector2i(1920, 544),
	"res://assets/ui/components/main_title.png": Vector2i(1190, 506),
	"res://assets/ui/components/armory_detail_panel.png": Vector2i(464, 748),
	"res://assets/ui/components/armory_selector_plate_v2.png": Vector2i(1024, 389),
	"res://assets/ui/components/armory_selector_plate_active_v2.png": Vector2i(1024, 389),
	"res://assets/ui/components/armory_nav_bar.png": Vector2i(1920, 160),
	"res://assets/ui/HUD.png": Vector2i(2048, 2048),
	"res://assets/ui/weapons1.png": Vector2i(2048, 2048),
}

var failures: Array[String] = []
var checked := 0

func _ready() -> void:
	for directory: String in CATEGORY_MIN_LONG_EDGE:
		var paths: Array[String] = []
		_collect_pngs(directory, paths)
		_check(not paths.is_empty(), "no textures found in " + directory)
		for path: String in paths:
			var image := _load_image(path)
			if image == null:
				continue
			var minimum := int(CATEGORY_MIN_LONG_EDGE[directory])
			_check(maxi(image.get_width(), image.get_height()) >= minimum, "%s is below the %dpx HD baseline" % [path, minimum])
	for path: String in REQUIRED_RUNTIME_ASSETS:
		var image := _load_image(path)
		if image == null:
			continue
		var expected: Vector2i = REQUIRED_RUNTIME_ASSETS[path]
		_check(image.get_width() >= expected.x and image.get_height() >= expected.y, "%s is %s, expected at least %s" % [path, image.get_size(), expected])
	if failures.is_empty():
		print("HD_ASSET_COVERAGE_TEST_PASS checked=%d categories=%d required=%d" % [checked, CATEGORY_MIN_LONG_EDGE.size(), REQUIRED_RUNTIME_ASSETS.size()])
		get_tree().quit(0)
	else:
		print("HD_ASSET_COVERAGE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _load_image(path: String) -> Image:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	_check(error == OK, "could not decode " + path)
	if error != OK:
		return null
	checked += 1
	_check(FileAccess.file_exists(path + ".import"), "missing import sidecar for " + path)
	return image

func _collect_pngs(directory_path: String, texture_paths: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	_check(directory != null, "could not scan " + directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var path := directory_path.path_join(entry)
			if directory.current_is_dir():
				_collect_pngs(path, texture_paths)
			elif entry.get_extension().to_lower() == "png":
				texture_paths.append(path)
		entry = directory.get_next()
	directory.list_dir_end()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("HD ASSET COVERAGE TEST: " + message)
