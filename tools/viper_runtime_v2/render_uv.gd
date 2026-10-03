extends SceneTree

func _initialize() -> void:
	var labels: Array=["head_uv_v6","head_regions_v7"] if "--head-v6" in OS.get_cmdline_user_args() else ["head","body","shoulder","hand","foot","head_regions"]
	for label: String in labels:
		var path := "res://docs/art/viper_runtime_v2/guides/"+label+("" if label in ["head_regions","head_uv_v6","head_regions_v6","head_regions_v7"] else "_uv")
		var image := Image.new()
		assert(image.load_svg_from_string(FileAccess.get_file_as_string(path+".svg")) == OK)
		assert(image.save_png(path+".png") == OK)
	print("VIPER_UV_GUIDES_PASS source layout / local visor layout")
	quit()
