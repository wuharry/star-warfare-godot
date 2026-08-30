@tool
extends EditorPlugin

func _enter_tree() -> void:
	var android_sdk := OS.get_environment("STAR_WARFARE_ANDROID_SDK")
	var java_sdk := OS.get_environment("STAR_WARFARE_JAVA_SDK")
	if android_sdk.is_empty() or java_sdk.is_empty():
		return
	var settings := get_editor_interface().get_editor_settings()
	settings.set_setting("export/android/android_sdk_path", android_sdk)
	settings.set_setting("export/android/java_sdk_path", java_sdk)
	print("ANDROID_EDITOR_SETTINGS_OK")
	if OS.get_environment("STAR_WARFARE_CONFIGURE_ONLY") == "1":
		get_tree().call_deferred("quit", 0)
