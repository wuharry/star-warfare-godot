extends SceneTree

func _initialize() -> void:
	var config := ConfigFile.new()
	var path := "res://assets/models/enemies/concept/warrior/warrior.gltf.import"
	var error := config.load(path)
	if error == OK:
		config.set_value("params", "import_script/path", "res://tools/enemy_concept/import_warrior.gd")
		error = config.save(path)
	if error != OK:
		push_error("Warrior import configuration failed: " + error_string(error))
		quit(1)
		return
	# A custom shader does not reliably trigger Godot's automatic 3D texture
	# detection. Explicit mipmaps keep painted ridges stable at game distance.
	var texture_config := ConfigFile.new()
	var texture_path := "res://assets/models/enemies/concept/warrior/warrior_anatomy_v4.png.import"
	error = texture_config.load(texture_path)
	if error == OK:
		texture_config.set_value("params", "mipmaps/generate", true)
		texture_config.set_value("params", "compress/mode", 2)
		texture_config.set_value("params", "detect_3d/compress_to", 0)
		error = texture_config.save(texture_path)
	if error != OK:
		push_error("Warrior texture configuration failed: " + error_string(error))
		quit(1)
		return
	print("WARRIOR_IMPORT_CONFIGURED; reimport warrior.gltf in the editor next")
	quit()
