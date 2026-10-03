extends Node

var failures: Array[String] = []
var check_count := 0
var capture := false
var locale := "zh_TW"
var output_dir := "res://test_output/pause_options"
var captures: Array[Dictionary] = []
var input_mode := "mouse"
var requested_window_size := Vector2i.ZERO
var original_touch_emulation := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
		push_error("PAUSE OPTIONS TEST: " + message)


func _run() -> void:
	# A mistaken restart must not destroy the verifier before it can report it.
	get_tree().current_scene = null
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture":
			capture = true
		elif argument.begins_with("--locale="):
			locale = argument.trim_prefix("--locale=")
		elif argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=")
		elif argument == "--controller":
			input_mode = "controller"
		elif argument == "--touch":
			input_mode = "touch"
		elif argument.begins_with("--window-size="):
			var dimensions := argument.trim_prefix("--window-size=").split("x")
			if dimensions.size() == 2:
				requested_window_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	if requested_window_size.x > 0 and requested_window_size.y > 0:
		get_window().size = requested_window_size
		await _frames(4)
		_check(get_window().size == requested_window_size, "requested native window dimensions were not applied")
	original_touch_emulation = Input.emulate_mouse_from_touch
	var had_forced_mobile := ProjectSettings.has_setting("debug/restoration/force_mobile_ui")
	var original_forced_mobile: Variant = ProjectSettings.get_setting("debug/restoration/force_mobile_ui", false)
	if input_mode == "touch":
		Input.emulate_mouse_from_touch = true
		ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	var original_save: String = GameState.save_path
	var original_settings: Dictionary = GameState.settings.duplicate(true)
	var original_level: int = GameState.selected_level
	var original_mode: String = GameState.selected_game_mode
	var original_locale := TranslationServer.get_locale()
	var original_mouse_mode := Input.mouse_mode
	var original_exists := FileAccess.file_exists(original_save)
	var original_sha := FileAccess.get_sha256(original_save) if original_exists else ""
	GameState.save_path = "user://pause_options_%d.json" % Time.get_ticks_usec()
	_check(GameState._save(), "could not clone the current profile into an isolated save")
	if input_mode == "touch":
		GameState.set_setting("show_touch_controls", true)
	Localization.apply_locale(locale)
	_check(tr("Options") == ("選項" if locale == "zh_TW" else "Options"), "pause Options label has the wrong translation")
	if locale == "zh_TW":
		_check(tr("OPTIONS") == "設定", "pause label changed the existing main-menu SETTINGS translation")
	if capture:
		_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) == OK, "could not create capture directory")
	if input_mode == "mouse":
		await _test_mode(13, "multiplayer", "pvp")
		await _test_mode(1, "singleplayer", "solo")
	else:
		await _test_alternate_input(13, "multiplayer", "pvp")
		await _test_alternate_input(1, "singleplayer", "solo")
	get_tree().paused = false
	# A failed restart can leave a replacement scene; remove only that test scene.
	if is_instance_valid(get_tree().current_scene):
		get_tree().current_scene.queue_free()
		get_tree().current_scene = null
	await _frames(2)
	GameState.settings = original_settings
	GameState.selected_level = original_level
	GameState.selected_game_mode = original_mode
	GameState._apply_audio_settings()
	GameState.apply_viewport_quality()
	Localization.apply_locale(original_locale)
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(GameState.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameState.save_path = original_save
	_check(FileAccess.file_exists(original_save) == original_exists, "test changed whether the real save exists")
	if original_exists:
		_check(FileAccess.get_sha256(original_save) == original_sha, "pause options wrote into the real player profile")
	Input.mouse_mode = original_mouse_mode
	Input.emulate_mouse_from_touch = original_touch_emulation
	if input_mode == "touch":
		ProjectSettings.set_setting("debug/restoration/force_mobile_ui", original_forced_mobile if had_forced_mobile else null)
	AudioDirector.stop_all_sfx()
	await _frames(2)
	if capture:
		_check(captures.size() == 12, "capture did not save both modes and all four options pages")
		var manifest := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
		_check(manifest != null, "could not save capture manifest")
		if manifest != null:
			manifest.store_string(JSON.stringify({"locale": locale, "input_mode": input_mode, "touch_emulation_default": original_touch_emulation, "renderer": RenderingServer.get_current_rendering_method(), "window_size": [get_window().size.x, get_window().size.y], "viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y], "stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode"), "checks": check_count, "captures": captures, "failures": failures}, "\t"))
	print("PAUSE_OPTIONS_TEST_PASS checks=%d modes=pvp,solo input=%s capture=%d" % [check_count, input_mode, captures.size()] if failures.is_empty() else "PAUSE_OPTIONS_TEST_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_mode(level_number: int, game_mode: String, prefix: String) -> void:
	GameState.selected_level = level_number
	GameState.selected_game_mode = game_mode
	GameState.set_setting("quality", "high")
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	# The verifier keeps processing while paused; the game itself must stop.
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	await _frames(8)
	_check(world.pvp_arena == (game_mode == "multiplayer"), prefix + " did not enter the requested real game mode")
	_check(world.hud.pause_options_overlay == null, prefix + " options were constructed before the player opened them")
	world.score = 751
	world.elapsed_time = 42.125
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _click(world.hud.pause_button)
	_check(get_tree().paused and world.hud.pause_overlay.visible, prefix + " actual Pause click did not suspend the game")
	var snapshot := _snapshot(world)
	var options := world.hud.pause_overlay.find_child("PauseOptionsButton", true, false) as Button
	_check(options != null and options.text == tr("Options"), prefix + " pause menu still shows a restart instead of Options")
	if options == null:
		await _cleanup_world(world)
		return
	_check(world.hud.pause_overlay.find_child("ResumeButton", true, false) is Button and world.hud.pause_overlay.find_child("AbortMenuButton", true, false) is Button, prefix + " pause navigation controls are missing")
	for node: Node in world.hud.pause_overlay.find_children("*", "Button", true, false):
		var button := node as Button
		_check(not button.text in [tr("RESTART ARENA"), tr("RESTART SECTOR")], prefix + " pause menu retained a restart action")
	await _capture(prefix + "_pause", "actual paused %s session" % game_mode)
	await _click(options)
	_check(get_tree().paused and not world.hud.pause_overlay.visible and is_instance_valid(world.hud.pause_options_overlay) and world.hud.pause_options_overlay.visible, prefix + " Options click resumed or restarted the game")
	if not is_instance_valid(world.hud.pause_options_overlay):
		await _cleanup_world(world)
		return
	var overlay: Control = world.hud.pause_options_overlay
	var picker := overlay.find_child("GraphicsQualityPicker", true, false) as OptionButton
	var back := overlay.find_child("ReturnToPauseButton", true, false) as Button
	_check(overlay.name == "PauseOptionsOverlay" and picker != null and back != null, prefix + " options API controls are missing")
	if picker == null or back == null:
		await _cleanup_world(world)
		return
	_check(picker.item_count == 3 and picker.selected == 2, prefix + " options do not reflect the saved graphics preset")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_check(picker.get_theme_stylebox(state) is StyleBoxTexture and back.get_theme_stylebox(state) is StyleBoxTexture, prefix + " options have no shared metal " + state)
	_check(get_viewport().get_visible_rect().encloses(picker.get_global_rect()) and get_viewport().get_visible_rect().encloses(back.get_global_rect()), prefix + " options controls overflow the viewport")
	_check_frozen(world, snapshot, prefix + " initial options")
	await _capture(prefix + "_options", "in-session graphics controls / saved High preset")
	await _click(picker)
	var popup := picker.get_popup()
	_check(popup.visible, prefix + " actual dropdown click did not open graphics presets")
	await _key(KEY_DOWN, popup.get_window_id())
	await _capture(prefix + "_dropdown", "graphics dropdown / keyboard-highlighted preset")
	await _key(KEY_ESCAPE, popup.get_window_id())
	_check(not popup.visible and overlay.visible and get_tree().paused, prefix + " dropdown Escape closed the options or resumed the game")
	_check(str(GameState.settings.quality) == "high", prefix + " Escape applied an unconfirmed dropdown selection")
	await _capture_settings_pages(overlay, prefix)
	for index in GameState.QUALITY_ORDER.size():
		await _choose_preset(picker, index)
		var preset: String = GameState.QUALITY_ORDER[index]
		_check_live_quality(world, preset, prefix)
		_check_frozen(world, snapshot, prefix + " " + preset)
	await _click(back)
	_check(get_tree().paused and world.hud.pause_overlay.visible and not overlay.visible, prefix + " Return to pause resumed the simulation")
	_check(options.has_focus(), prefix + " returning from options lost the pause-button focus")
	await _click(options)
	_check(world.hud.pause_options_overlay == overlay, prefix + " reopening options replaced its existing UI")
	_check(picker.selected == 2, prefix + " reopening options lost the last saved High preset")
	await _click(picker)
	world.hud._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(not popup.visible and overlay.visible and get_tree().paused, prefix + " native Back skipped the open dropdown")
	world.hud._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(not overlay.visible and world.hud.pause_overlay.visible and get_tree().paused, prefix + " native Back skipped the pause menu")
	await _click(options)
	await _key(KEY_ESCAPE, get_window().get_window_id())
	_check(not overlay.visible and world.hud.pause_overlay.visible and get_tree().paused, prefix + " first options Escape resumed the game")
	_check_frozen(world, snapshot, prefix + " final pause")
	await _key(KEY_ESCAPE, get_window().get_window_id())
	_check(not get_tree().paused and not world.hud.pause_overlay.visible and not overlay.visible, prefix + " second Escape did not resume the game")
	await _frames(3)
	_check(world.elapsed_time > float(snapshot.time), prefix + " resumed session no longer advances its original clock")
	_check(world.get_instance_id() == int(snapshot.world) and world.player.get_instance_id() == int(snapshot.player) and world.score == int(snapshot.score), prefix + " resume replaced or reset the session")
	await _cleanup_world(world)


func _snapshot(world: WarfareGameWorld) -> Dictionary:
	return {"world": world.get_instance_id(), "player": world.player.get_instance_id(), "hud": world.hud.get_instance_id(), "score": world.score, "time": world.elapsed_time, "position": world.player.global_position, "mode": GameState.selected_game_mode, "level": GameState.selected_level}


func _test_alternate_input(level_number: int, game_mode: String, prefix: String) -> void:
	GameState.selected_level = level_number
	GameState.selected_game_mode = game_mode
	GameState.set_setting("quality", "high")
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	await _frames(8)
	_check(world.pvp_arena == (game_mode == "multiplayer"), prefix + " alternate input entered the wrong game mode")
	world.score = 751
	world.elapsed_time = 42.125
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if input_mode == "controller":
		await _joy(JOY_BUTTON_START)
	else:
		await _hold_touch_controls(world)
		await _tap(world.hud.pause_button)
	_check(get_tree().paused and world.hud.pause_overlay.visible, prefix + " " + input_mode + " could not open Pause")
	if not get_tree().paused:
		await _cleanup_world(world)
		return
	var snapshot := _snapshot(world)
	var resume := world.hud.pause_overlay.find_child("ResumeButton", true, false) as Button
	var options := world.hud.pause_overlay.find_child("PauseOptionsButton", true, false) as Button
	_check(resume != null and options != null, prefix + " pause buttons are missing")
	_check_panel_bounds(world.hud.pause_overlay, prefix + " pause")
	if input_mode == "controller":
		_check(resume.has_focus(), prefix + " Start did not focus Resume by default")
	else:
		await _check_paused_touch_controls(world, snapshot, prefix)
	await _capture(prefix + "_pause", input_mode + " opened Pause")
	if input_mode == "controller":
		await _joy(JOY_BUTTON_DPAD_DOWN)
		_check(options.has_focus(), prefix + " D-pad Down did not move from Resume to Options")
		await _joy(JOY_BUTTON_A)
	else:
		await _tap(options)
	_check(get_tree().paused and is_instance_valid(world.hud.pause_options_overlay) and world.hud.pause_options_overlay.visible, prefix + " " + input_mode + " could not open Options without resuming")
	if not is_instance_valid(world.hud.pause_options_overlay) or not world.hud.pause_options_overlay.visible:
		await _cleanup_world(world)
		return
	var overlay: Control = world.hud.pause_options_overlay
	var picker: OptionButton = world.hud.pause_quality_picker
	var back := overlay.find_child("ReturnToPauseButton", true, false) as Button
	var popup := picker.get_popup()
	_check_panel_bounds(overlay, prefix + " options")
	_check_frozen(world, snapshot, prefix + " alternate options")
	if input_mode == "controller":
		_check(picker.has_focus(), prefix + " controller Options did not focus the quality selector")
	await _capture(prefix + "_options", input_mode + " graphics options")
	for index in GameState.QUALITY_ORDER.size():
		if input_mode == "controller":
			await _joy(JOY_BUTTON_A)
		else:
			await _tap(picker)
		_check(popup.visible, prefix + " " + input_mode + " could not open the quality dropdown")
		if not popup.visible:
			break
		if index == 0:
			await _capture(prefix + "_dropdown", input_mode + " native quality dropdown")
		if input_mode == "controller":
			# Native OptionButton initially focuses the saved row. Move through
			# real D-pad events; do not preselect a row or emit item_selected.
			var focused := popup.get_focused_item()
			_check(focused >= 0, prefix + " controller dropdown has no focused preset")
			for step in absi(index - focused):
				await _joy(JOY_BUTTON_DPAD_UP if index < focused else JOY_BUTTON_DPAD_DOWN)
			await _joy(JOY_BUTTON_A)
		else:
			await _tap_popup_row(popup, index)
		_check(picker.selected == index and not popup.visible, prefix + " " + input_mode + " did not confirm quality row " + str(index))
		_check_live_quality(world, GameState.QUALITY_ORDER[index], prefix)
		_check_frozen(world, snapshot, prefix + " alternate quality")
	await _capture_settings_pages(overlay, prefix)
	if input_mode == "controller":
		await _joy(JOY_BUTTON_A)
		_check(popup.visible, prefix + " controller could not reopen the dropdown")
		await _joy(JOY_BUTTON_B)
		_check(not popup.visible and overlay.visible and get_tree().paused, prefix + " first B skipped dropdown or resumed")
		await _joy(JOY_BUTTON_B)
		_check(not overlay.visible and world.hud.pause_overlay.visible and get_tree().paused, prefix + " second B did not return Options to Pause")
		_check(options.has_focus(), prefix + " B lost focus on the Options button")
		# Pause-level B resumes, then Start must reopen at Resume.
		await _joy(JOY_BUTTON_B)
		_check(not get_tree().paused and not world.hud.pause_overlay.visible, prefix + " third B did not resume from Pause")
		await _joy(JOY_BUTTON_START)
		_check(get_tree().paused and resume.has_focus(), prefix + " reopening via Start did not restore Resume focus")
		if prefix == "pvp":
			await _joy(JOY_BUTTON_A)
		else:
			await _joy(JOY_BUTTON_START)
	else:
		await _tap(back)
		_check(get_tree().paused and world.hud.pause_overlay.visible and not overlay.visible, prefix + " touch Back resumed instead of returning to Pause")
		_check_frozen(world, snapshot, prefix + " touch final pause")
		await _tap(resume)
	_check(not get_tree().paused and not world.hud.pause_overlay.visible, prefix + " " + input_mode + " could not resume")
	await _frames(3)
	_check(world.elapsed_time > float(snapshot.time), prefix + " alternate-input resume did not restart the session clock")
	_check(world.get_instance_id() == int(snapshot.world) and world.player.get_instance_id() == int(snapshot.player) and world.score == int(snapshot.score), prefix + " alternate input reset the session")
	if input_mode == "touch":
		await _check_hidden_touch_controls(world, prefix)
	await _cleanup_world(world)


func _check_panel_bounds(overlay: Control, context: String) -> void:
	# Native dropdown Windows have their own internal panels; only the outer
	# centered modal determines whether the game menu fits the viewport.
	var panels: Array[PanelContainer] = []
	for candidate: PanelContainer in overlay.find_children("*", "PanelContainer", true, false):
		if candidate.get_parent() is CenterContainer:
			panels.append(candidate)
	_check(panels.size() == 1, context + " did not contain a single main modal panel")
	var viewport_rect := get_viewport().get_visible_rect()
	for panel: PanelContainer in panels:
		_check(viewport_rect.encloses(panel.get_global_rect()), context + " full modal panel overflows the production stretched viewport")
	for control: Node in overlay.find_children("*", "BaseButton", true, false):
		var button := control as BaseButton
		if button.is_visible_in_tree():
			_check(viewport_rect.encloses(button.get_global_rect()) and button.size.x > 0 and button.size.y > 0, context + " button " + str(button.name) + " is outside the visible/clickable viewport")


func _joy(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _tap(control: Control) -> void:
	var logical_point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	await _touch_point(get_viewport().get_final_transform() * logical_point, 0, true, get_window().get_window_id())
	await _touch_point(get_viewport().get_final_transform() * logical_point, 0, false, get_window().get_window_id())


func _touch_point(point: Vector2, index: int, pressed: bool, window_id: int) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = index
	event.pressed = pressed
	event.window_id = window_id
	Input.parse_input_event(event)
	await _frames(2)


func _tap_popup_row(popup: PopupMenu, index: int) -> void:
	var point := Vector2(popup.size.x * 0.5, popup.size.y * (float(index) + 0.5) / float(popup.item_count))
	var window_id := popup.get_window_id()
	if popup.is_embedded():
		point = get_viewport().get_final_transform() * (Vector2(popup.position) + point)
		window_id = get_window().get_window_id()
	await _touch_point(point, 0, true, window_id)
	await _touch_point(point, 0, false, window_id)


func _hold_touch_controls(world: WarfareGameWorld) -> void:
	_check(is_instance_valid(world.hud.touch_root) and world.hud.touch_root.is_visible_in_tree(), "touch test did not build visible mobile controls")
	for pair: Array in [[world.hud.move_joystick, 7], [world.hud.shoot_joystick, 8]]:
		var joystick := pair[0] as WarfareVirtualJoystick
		var point := joystick.global_position + joystick.size * 0.5 + Vector2(joystick.radius * 0.6, 0)
		await _touch_point(get_viewport().get_final_transform() * point, int(pair[1]), true, get_window().get_window_id())
	_check(world.player.touch_move.length() > 0 and world.player.touch_fire, "real held joysticks did not establish movement and firing before pause")


func _check_paused_touch_controls(world: WarfareGameWorld, snapshot: Dictionary, context: String) -> void:
	_check(world.player.touch_move == Vector2.ZERO and not world.player.touch_fire and not world.player.touch_fire_started, context + " Pause retained held movement, firing or queued fire")
	_check(world.hud.move_joystick.active_touch == -1 and world.hud.shoot_joystick.active_touch == -1, context + " Pause retained held joystick fingers")
	var yaw: float = world.player.camera_yaw
	var pitch: float = world.player.camera_pitch
	for pair: Array in [[world.hud.move_joystick, 7], [world.hud.shoot_joystick, 8]]:
		var joystick := pair[0] as WarfareVirtualJoystick
		var point := joystick.global_position + joystick.size * 0.5 + Vector2(joystick.radius * 0.8, 0)
		await _touch_point(get_viewport().get_final_transform() * point, int(pair[1]), true, get_window().get_window_id())
		var drag := InputEventScreenDrag.new()
		drag.position = get_viewport().get_final_transform() * (point + Vector2(0, joystick.radius * 0.2))
		drag.relative = get_viewport().get_final_transform().basis_xform(Vector2(0, joystick.radius * 0.2))
		drag.index = int(pair[1])
		drag.window_id = get_window().get_window_id()
		Input.parse_input_event(drag)
		await _frames(2)
		await _touch_point(drag.position, int(pair[1]), false, drag.window_id)
	_check(world.player.touch_move == Vector2.ZERO and not world.player.touch_fire, context + " paused touch/drag reactivated movement or firing")
	_check(is_equal_approx(world.player.camera_yaw, yaw) and is_equal_approx(world.player.camera_pitch, pitch), context + " paused joystick touch/drag changed the camera")
	_check_frozen(world, snapshot, context + " paused joystick input")


func _check_hidden_touch_controls(world: WarfareGameWorld, context: String) -> void:
	world.hud.touch_root.hide()
	await _frames(2)
	var yaw: float = world.player.camera_yaw
	var pitch: float = world.player.camera_pitch
	await _hold_hidden_joysticks(world)
	_check(world.player.touch_move == Vector2.ZERO and not world.player.touch_fire and world.hud.move_joystick.active_touch == -1 and world.hud.shoot_joystick.active_touch == -1, context + " hidden touch_root still accepted new joystick touches")
	_check(is_equal_approx(world.player.camera_yaw, yaw) and is_equal_approx(world.player.camera_pitch, pitch), context + " hidden joystick changed the camera")


func _hold_hidden_joysticks(world: WarfareGameWorld) -> void:
	for pair: Array in [[world.hud.move_joystick, 7], [world.hud.shoot_joystick, 8]]:
		var joystick := pair[0] as WarfareVirtualJoystick
		var point := joystick.global_position + joystick.size * 0.5 + Vector2(joystick.radius * 0.6, 0)
		await _touch_point(get_viewport().get_final_transform() * point, int(pair[1]), true, get_window().get_window_id())
		await _touch_point(get_viewport().get_final_transform() * point, int(pair[1]), false, get_window().get_window_id())


func _check_frozen(world: WarfareGameWorld, snapshot: Dictionary, context: String) -> void:
	_check(is_instance_valid(world) and world.get_instance_id() == int(snapshot.world) and world.is_inside_tree(), context + " replaced the world")
	_check(world.player.get_instance_id() == int(snapshot.player) and world.hud.get_instance_id() == int(snapshot.hud), context + " replaced the player or HUD")
	_check(world.score == int(snapshot.score) and is_equal_approx(world.elapsed_time, float(snapshot.time)), context + " reset or advanced score/session time while paused")
	_check(world.player.global_position.is_equal_approx(snapshot.position), context + " moved the player while paused")
	_check(GameState.selected_game_mode == str(snapshot.mode) and GameState.selected_level == int(snapshot.level) and get_tree().current_scene == null, context + " started a new scene or changed the active map")
	_check(get_tree().paused, context + " resumed the simulation")


func _check_live_quality(world: WarfareGameWorld, preset: String, context: String) -> void:
	var profile: Dictionary = GameState.QUALITY_PROFILES[preset]
	_check(str(GameState.settings.quality) == preset, context + " quality selection did not update settings")
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path))
	_check(stored is Dictionary and stored.settings.quality == preset, context + " quality selection was not saved to the isolated profile")
	_check(is_equal_approx(get_viewport().scaling_3d_scale, float(profile.render_scale)) and int(get_viewport().msaa_3d) == int(profile.msaa), context + " quality did not update the live viewport")
	var sun := world.get_node_or_null("KeyLight") as DirectionalLight3D
	_check(sun != null and sun.shadow_enabled == bool(profile.shadows), context + " quality did not update existing directional shadows")
	var environments := world.find_children("*", "WorldEnvironment", true, false)
	_check(not environments.is_empty(), context + " live environment is missing")
	if not environments.is_empty():
		var environment := (environments[0] as WorldEnvironment).environment
		var source_settings: Dictionary = world.stage_metadata.get("render_settings", {})
		_check(environment.glow_enabled == bool(profile.glow), context + " quality did not update live glow")
		_check(environment.fog_enabled == (bool(profile.fog) and bool(source_settings.get("fog_enabled", true))), context + " quality violated the authored fog setting")


func _choose_preset(picker: OptionButton, index: int) -> void:
	await _click(picker)
	var popup := picker.get_popup()
	_check(popup.visible, "graphics preset popup did not open")
	# Match the project's native popup tests: focus the desired row, then use
	# the real Enter event to execute OptionButton's selection signal.
	popup.set_focused_item(index)
	await _key(KEY_ENTER, popup.get_window_id())
	_check(picker.selected == index and not popup.visible, "keyboard selection did not apply the requested graphics preset")


func _click(control: Control) -> void:
	var position := get_viewport().get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.window_id = get_window().get_window_id()
	Input.parse_input_event(motion)
	await _frames(2)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.window_id = get_window().get_window_id()
		Input.parse_input_event(event)
		await _frames(2)


func _key(code: Key, window_id: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.window_id = window_id
		Input.parse_input_event(event)
		await _frames(2)


func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame


func _capture_settings_pages(overlay: Control, prefix: String) -> void:
	if not capture:
		return
	for page: String in ["Audio", "Controls", "Language"]:
		await _click(overlay.find_child(page + "TabButton", true, false) as Button)
		_check_panel_bounds(overlay, prefix + " " + page)
		await _capture(prefix + "_" + page.to_lower(), "in-session " + page.to_lower() + " settings")
	await _click(overlay.find_child("GraphicsTabButton", true, false) as Button)


func _capture(stem: String, description: String) -> void:
	if not capture:
		return
	await _frames(4)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.save_png(output_dir.path_join(stem + ".png")) == OK, "could not save " + stem)
	captures.append({"file": stem + ".png", "description": description, "width": image.get_width(), "height": image.get_height()})


func _cleanup_world(world: WarfareGameWorld) -> void:
	world.completed = true
	get_tree().paused = false
	for audio: Node in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	for audio: Node in world.find_children("*", "AudioStreamPlayer3D", true, false):
		(audio as AudioStreamPlayer3D).stop()
	world.queue_free()
	AudioDirector.stop_all_sfx()
	await _frames(3)
