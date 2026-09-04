extends SceneTree

# Runtime textures which were added after the original 2x restoration pass.
# Explicit targets make this tool idempotent and preserve UV coordinates.
const TARGET_SIZES := {
	"res://assets/models/weapons/c02.png": Vector2i(512, 512),
	"res://assets/models/weapons/gong_1.png": Vector2i(512, 512),
	"res://assets/models/weapons/guiji-0657.png": Vector2i(512, 512),
	"res://assets/models/weapons/joke_L.png": Vector2i(512, 512),
	"res://assets/models/weapons/lg_001.png": Vector2i(512, 512),
	"res://assets/models/weapons/lg_002.png": Vector2i(512, 512),
	"res://assets/models/weapons/leiquan.png": Vector2i(512, 512),
	"res://assets/models/weapons/shandian_003.png": Vector2i(256, 512),
	"res://assets/models/projectiles/gun0910.png": Vector2i(512, 512),
	"res://assets/models/projectiles/gun0910_hd.png": Vector2i(1024, 1024),
	"res://assets/models/projectiles/plasma_bolt1_red.png": Vector2i(512, 512),
	"res://assets/vfx/legacy_hd/laser_02_hd.png": Vector2i(1024, 1024),
}

func _initialize() -> void:
	var failures: Array[String] = []
	var changed := 0
	for path: String in TARGET_SIZES:
		var image := Image.new()
		var error := image.load(ProjectSettings.globalize_path(path))
		if error != OK:
			failures.append("could not load %s: %s" % [path, error_string(error)])
			continue
		var target: Vector2i = TARGET_SIZES[path]
		if image.get_size() == target and image.get_format() == Image.FORMAT_RGBA8:
			continue
		if image.get_size() != target:
			image.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGBA8)
		error = image.save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			failures.append("could not save %s: %s" % [path, error_string(error)])
		else:
			changed += 1
	if failures.is_empty():
		print("RUNTIME_ASSET_UPSCALE_PASS changed=%d targets=%d" % [changed, TARGET_SIZES.size()])
		quit(0)
	else:
		push_error("RUNTIME_ASSET_UPSCALE_FAIL: %s" % ", ".join(failures))
		quit(1)
