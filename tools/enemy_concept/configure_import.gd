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
	print("WARRIOR_IMPORT_CONFIGURED; reimport warrior.gltf in the editor next")
	quit()
