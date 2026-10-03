extends Node

# Drive the production room's Pause/Options UI through mouse events. The
# isolated profile protects the player's save even when a regression reloads
# the current scene; current_scene stays null so this verifier survives it.
var failures: Array[String] = []
var check_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
		push_error("IN GAME OPTIONS TEST: " + message)


func _run() -> void:
	get_tree().current_scene = null
	var original_save: String = GameState.save_path
	var original_exists := FileAccess.file_exists(original_save)
	var original_sha := FileAccess.get_sha256(original_save) if original_exists else ""
	var original_settings: Dictionary = GameState.settings.duplicate(true)
	var original_level: int = GameState.selected_level
	var original_mode: String = GameState.selected_game_mode
	var original_locale := TranslationServer.get_locale()
	var original_mouse_mode := Input.mouse_mode
	var had_forced_mobile := ProjectSettings.has_setting("debug/restoration/force_mobile_ui")
	var original_forced_mobile: Variant = ProjectSettings.get_setting("debug/restoration/force_mobile_ui", false)
	var viewport := get_viewport()
	var original_quality := [viewport.scaling_3d_mode, viewport.scaling_3d_scale, viewport.msaa_3d]
	var original_audio: Dictionary = {}
	for bus in AudioServer.bus_count:
		original_audio[bus] = AudioServer.get_bus_volume_db(bus)
	GameState.save_path = "user://in_game_options_%d.json" % Time.get_ticks_usec()
	_check(GameState._save(), "could not create an isolated profile")
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	GameState.set_setting("language", "en")
	GameState.set_setting("show_touch_controls", true)
	GameState.set_setting("invert_y", false)
	GameState.set_setting("music", 0.8)
	GameState.set_setting("sfx", 0.3)
	GameState.set_setting("look_sensitivity", 0.24)
	GameState.selected_level = 13
	GameState.selected_game_mode = "multiplayer"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	await _frames(8)
	world.score = 751
	world.elapsed_time = 42.125
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _click(world.hud.pause_button)
	_check(world.pvp_arena and get_tree().paused and world.hud.pause_overlay.visible, "mouse Pause did not suspend the real multiplayer room")
	var snapshot := {"world": world.get_instance_id(), "player": world.player.get_instance_id(), "hud": world.hud.get_instance_id(), "position": world.player.global_position, "time": world.elapsed_time, "score": world.score}
	await _click(world.hud.pause_options_button)
	_check(is_instance_valid(world.hud.pause_options_overlay) and world.hud.pause_options_overlay.visible, "mouse Options did not open the room settings")
	if is_instance_valid(world.hud.pause_options_overlay):
		await _test_settings(world, snapshot)
	# Remove only test-owned scenes before restoring autoload state.
	world.completed = true
	get_tree().paused = false
	world.queue_free()
	if is_instance_valid(get_tree().current_scene):
		get_tree().current_scene.queue_free()
		get_tree().current_scene = null
	AudioDirector.stop_all_sfx()
	await _frames(3)
	GameState.settings = original_settings
	GameState.selected_level = original_level
	GameState.selected_game_mode = original_mode
	GameState._apply_audio_settings()
	GameState.apply_viewport_quality()
	Localization.apply_locale(original_locale)
	viewport.scaling_3d_mode = original_quality[0]
	viewport.scaling_3d_scale = original_quality[1]
	viewport.msaa_3d = original_quality[2]
	for bus: int in original_audio:
		AudioServer.set_bus_volume_db(bus, float(original_audio[bus]))
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", original_forced_mobile if had_forced_mobile else null)
	Input.mouse_mode = original_mouse_mode
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(GameState.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameState.save_path = original_save
	_check(FileAccess.file_exists(original_save) == original_exists, "test changed whether the player's save exists")
	if original_exists:
		_check(FileAccess.get_sha256(original_save) == original_sha, "test changed the player's save SHA256")
	print("IN_GAME_OPTIONS_TEST_PASS checks=%d" % check_count if failures.is_empty() else "IN_GAME_OPTIONS_TEST_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_settings(world: WarfareGameWorld, snapshot: Dictionary) -> void:
	var overlay: Control = world.hud.pause_options_overlay
	var controls: Dictionary = {}
	for node_name: String in ["GraphicsTabButton", "AudioTabButton", "ControlsTabButton", "LanguageTabButton", "MusicVolumeSlider", "SoundVolumeSlider", "LookSensitivitySlider", "InvertLookButton", "ShowTouchControlsButton", "LanguagePicker", "ReturnToPauseButton"]:
		controls[node_name] = overlay.find_child(node_name, true, false)
		_check(controls[node_name] != null, "missing room settings control " + node_name)
		if controls[node_name] == null:
			return
	var music := controls.MusicVolumeSlider as HSlider
	var sfx := controls.SoundVolumeSlider as HSlider
	var sensitivity := controls.LookSensitivitySlider as HSlider
	var invert := controls.InvertLookButton as CheckButton
	var touch := controls.ShowTouchControlsButton as CheckButton
	var language := controls.LanguagePicker as OptionButton
	_check(not music.is_visible_in_tree() and world.hud.pause_quality_picker.is_visible_in_tree(), "opening Options did not show the Graphics page")
	await _click(controls.AudioTabButton)
	_check(music.is_visible_in_tree() and sfx.is_visible_in_tree() and not world.hud.pause_quality_picker.is_visible_in_tree(), "mouse Audio tab did not switch pages")
	await _click(music, Vector2(0.3, 0.5))
	await _click(sfx, Vector2(0.7, 0.5))
	_check(music.value < 0.5 and sfx.value > 0.5, "actual slider clicks did not change the music and effects volume")
	_check_setting("music", music.value)
	_check_setting("sfx", sfx.value)
	for pair: Array in [["Music", music.value], ["SFX", sfx.value]]:
		var bus := AudioServer.get_bus_index(str(pair[0]))
		_check(bus >= 0, "missing live audio bus " + str(pair[0]))
		if bus >= 0:
			_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bus)), float(pair[1])), str(pair[0]) + " volume did not apply to the live audio bus")
	var saved_music := music.value
	var saved_sfx := sfx.value
	await _click(controls.ControlsTabButton)
	_check(sensitivity.is_visible_in_tree() and invert.is_visible_in_tree() and touch.is_visible_in_tree(), "mouse Controls tab did not expose aiming and mobile controls")
	await _click(sensitivity, Vector2(0.01, 0.5))
	var low_sensitivity := sensitivity.value
	_check_setting("look_sensitivity", low_sensitivity)
	var low_delta := _look_response(world.player)
	_check(low_delta.x < 0 and low_delta.y < 0, "non-inverted touch aiming moved the camera in the wrong direction")
	await _click(sensitivity, Vector2(0.99, 0.5))
	var high_sensitivity := sensitivity.value
	_check_setting("look_sensitivity", high_sensitivity)
	var high_delta := _look_response(world.player)
	_check(high_sensitivity > low_sensitivity and absf(high_delta.x) > absf(low_delta.x) * 3.0 and absf(high_delta.y) > absf(low_delta.y) * 3.0, "raising sensitivity did not increase actual camera movement: %.2f %s -> %.2f %s" % [low_sensitivity, low_delta, high_sensitivity, high_delta])
	await _click(invert)
	_check(invert.button_pressed, "mouse invert click did not enable vertical inversion")
	_check_setting("invert_y", true)
	var inverted_delta := _look_response(world.player)
	_check(inverted_delta.y > 0 and is_equal_approx(inverted_delta.x, high_delta.x) and is_equal_approx(inverted_delta.y, -high_delta.y), "vertical inversion did not reverse pitch while retaining yaw")
	_check(is_instance_valid(world.hud.touch_root) and world.hud.touch_root.visible, "forced mobile room did not have visible touch controls")
	await _click(touch)
	_check(not touch.button_pressed and not world.hud.touch_root.visible, "disabling mobile controls did not hide the existing touch HUD immediately")
	_check_setting("show_touch_controls", false)
	await _click(touch)
	_check(touch.button_pressed and world.hud.touch_root.visible, "enabling mobile controls did not reveal the existing touch HUD immediately")
	_check_setting("show_touch_controls", true)
	await _click(controls.LanguageTabButton)
	_check(language.is_visible_in_tree(), "mouse Language tab did not show the language selector")
	var overlay_id := overlay.get_instance_id()
	for locale: String in ["zh_TW", "en"]:
		await _choose_language(language, Localization.SUPPORTED_LOCALES.find(locale))
		_check_setting("language", locale)
		_check(TranslationServer.get_locale() == locale, "room language selection did not apply immediately")
		_check(world.hud.pause_options_overlay.get_instance_id() == overlay_id and overlay.visible, "changing language replaced or closed the existing Options overlay")
		_check((controls.AudioTabButton as Button).text == ("音效" if locale == "zh_TW" else "Audio") and (controls.ControlsTabButton as Button).text == ("操作" if locale == "zh_TW" else "Controls"), "language selection did not refresh existing Options labels")
		_check(world.hud.pause_options_button.text == ("選項" if locale == "zh_TW" else "Options") and world.hud.pause_resume_button.text == ("繼續" if locale == "zh_TW" else "RESUME"), "language selection did not refresh the hidden Pause buttons")
		var pause_title := world.hud.pause_overlay.find_child("PauseTitle", true, false) as Label
		_check(pause_title.text == ("戰術暫停" if locale == "zh_TW" else "TACTICAL PAUSE"), "language selection did not refresh the existing Pause title")
		_check_frozen(world, snapshot)
	await _click(controls.ReturnToPauseButton)
	_check(world.hud.pause_overlay.visible and not overlay.visible and get_tree().paused, "Back did not return to the still-paused room")
	await _click(world.hud.pause_options_button)
	_check(world.hud.pause_options_overlay == overlay and overlay.visible, "reopening Options replaced the settings UI")
	await _click(controls.AudioTabButton)
	_check(is_equal_approx(music.value, saved_music) and is_equal_approx(sfx.value, saved_sfx), "reopening Options lost the saved audio values")
	await _click(controls.ControlsTabButton)
	_check(is_equal_approx(sensitivity.value, high_sensitivity) and invert.button_pressed and touch.button_pressed, "reopening Options lost aiming or touch preferences")
	await _click(controls.LanguageTabButton)
	_check(language.selected == Localization.SUPPORTED_LOCALES.find("en"), "reopening Options lost the saved language")
	_check_frozen(world, snapshot)
	await _click(controls.ReturnToPauseButton)
	await _click(world.hud.pause_resume_button)
	_check(not get_tree().paused and not world.hud.pause_overlay.visible and not overlay.visible, "mouse Resume did not resume the room")
	await _frames(3)
	_check(world.elapsed_time > float(snapshot.time) and world.score == int(snapshot.score) and world.get_instance_id() == int(snapshot.world) and world.player.get_instance_id() == int(snapshot.player), "resuming replaced or reset the original room")


func _check_setting(key: String, expected: Variant) -> void:
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path))
	var live_value: Variant = GameState.settings[key]
	var live_matches: bool = is_equal_approx(float(live_value), float(expected)) if expected is float else live_value == expected
	_check(live_matches, key + " did not update live settings")
	var saved_matches := false
	if stored is Dictionary and stored.get("settings") is Dictionary and stored.settings.has(key):
		var saved: Variant = stored.settings[key]
		saved_matches = is_equal_approx(float(saved), float(expected)) if expected is float else saved == expected
	_check(saved_matches, key + " did not persist in the isolated profile")


func _look_response(player: WarfarePlayer) -> Vector2:
	var previous := Vector2(player.camera_yaw, player.camera_pitch)
	player.apply_touch_look(Vector2(20, 10))
	var response := Vector2(player.camera_yaw, player.camera_pitch) - previous
	# Cancel the same small delta to keep the paused session's camera intact.
	player.apply_touch_look(Vector2(-20, -10))
	return response


func _check_frozen(world: WarfareGameWorld, snapshot: Dictionary) -> void:
	_check(world.is_inside_tree() and world.get_instance_id() == int(snapshot.world) and world.player.get_instance_id() == int(snapshot.player) and world.hud.get_instance_id() == int(snapshot.hud), "settings replaced the existing world, player or HUD")
	_check(world.score == int(snapshot.score) and is_equal_approx(world.elapsed_time, float(snapshot.time)) and world.player.global_position.is_equal_approx(snapshot.position), "settings advanced or reset the paused room progress")
	_check(get_tree().paused and get_tree().current_scene == null and GameState.selected_level == 13 and GameState.selected_game_mode == "multiplayer", "settings resumed the room or changed its scene/map")


func _choose_language(picker: OptionButton, index: int) -> void:
	await _click(picker)
	var popup := picker.get_popup()
	_check(popup.visible, "mouse click did not open the language dropdown")
	if not popup.visible:
		return
	var point := Vector2(popup.size.x * 0.5, popup.size.y * (float(index) + 0.5) / float(popup.item_count))
	var window_id := popup.get_window_id()
	if popup.is_embedded():
		point = get_viewport().get_final_transform() * (Vector2(popup.position) + point)
		window_id = get_window().get_window_id()
	await _mouse_click(point, window_id)
	_check(picker.selected == index and not popup.visible, "mouse dropdown row did not select the requested language")
	if popup.visible:
		popup.hide()


func _click(control: Control, fraction := Vector2(0.5, 0.5)) -> void:
	var point := get_viewport().get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * fraction))
	await _mouse_click(point, get_window().get_window_id())


func _mouse_click(point: Vector2, window_id: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.window_id = window_id
		Input.parse_input_event(event)
		await _frames(2)


func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame
