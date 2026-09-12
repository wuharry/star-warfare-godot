extends SceneTree

func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/equipment_refined/manifest.json"))
	var changed := 0
	for job: Dictionary in manifest.textures:
		if job.status != "approved": continue
		var path: String = job.output + ".import"
		var config := ConfigFile.new()
		if config.load(path) != OK: continue
		if config.get_value("params", "mipmaps/generate", false) and config.get_value("params", "compress/mode", 0) == 2: continue
		config.set_value("params", "mipmaps/generate", true)
		config.set_value("params", "compress/mode", 2)
		assert(config.save(path) == OK)
		changed += 1
	print("EQUIPMENT_IMPORT_SETTINGS textures=", changed, " (run editor import next)")
	quit()
