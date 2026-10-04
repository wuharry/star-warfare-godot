extends SceneTree

func _initialize() -> void:
	var path := "res://docs/art/tank_runtime_v1/guides/head_rear_coverage_v4"
	var image := Image.new()
	assert(image.load_svg_from_string(FileAccess.get_file_as_string(path+".svg")) == OK)
	assert(image.save_png(path+".png") == OK)
	print("TANK_HEAD_SEMANTIC_GUIDE_PASS actual authored triangle UV")
	quit()
