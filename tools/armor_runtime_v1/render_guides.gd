extends SceneTree
func _initialize() -> void:
	var selected: Array[String] = ["hydra","strike","titan"]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--armor="):
			var slug := argument.trim_prefix("--armor=")
			assert(slug in ["hydra","strike","titan","atom","pegasus"])
			selected.assign([slug])
		if argument.begins_with("--guide="):
			var guide:=argument.trim_prefix("--guide=")
			var rendered:=Image.new()
			assert(rendered.load_svg_from_string(FileAccess.get_file_as_string(guide+".svg"))==OK)
			assert(rendered.save_png(guide+".png")==OK)
			print("ARMOR_TECHNICAL_GUIDE_PASS "+guide)
			quit();return
	for slug: String in selected:
		for label: String in ["head","body","shoulder","hand","foot"]:
			var path := "res://docs/art/"+slug+"_runtime_v1/guides/"+label+"_uv"
			var image := Image.new()
			assert(image.load_svg_from_string(FileAccess.get_file_as_string(path+".svg")) == OK)
			assert(image.save_png(path+".png") == OK)
		var path := "res://docs/art/"+slug+"_runtime_v1/guides/head_semantics"
		var image := Image.new()
		assert(image.load_svg_from_string(FileAccess.get_file_as_string(path+".svg")) == OK)
		assert(image.save_png(path+".png") == OK)
	print("THREE_ARMOR_UV_GUIDES_PASS exact original layouts")
	quit()
