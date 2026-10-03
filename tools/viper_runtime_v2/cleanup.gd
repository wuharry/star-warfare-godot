extends SceneTree

func _initialize() -> void:
	# Engine API owns cleanup of the no-longer-imported authoring master metadata.
	for filename: String in ["viper_master.blend.import","viper_master.blend1"]:
		var path := "res://docs/art/viper_runtime_v2/build/"+filename
		if FileAccess.file_exists(path):assert(DirAccess.remove_absolute(path)==OK)
	quit()
