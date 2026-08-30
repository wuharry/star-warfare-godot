extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MOBILE UI TEST: " + message)

func _run() -> void:
	_check(int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) == DisplayServer.SCREEN_SENSOR_LANDSCAPE, "project is not locked to sensor landscape orientation")
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) > int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)), "mobile viewport is not landscape")
	_check(not bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)), "Android Back would quit the game without opening pause")
	var original_touch_setting := bool(GameState.settings.show_touch_controls)
	GameState.settings.show_touch_controls = true
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	GameState.selected_level = 1

	var packed := load("res://scenes/game.tscn") as PackedScene
	_check(packed != null, "game scene could not be loaded")
	if packed == null:
		GameState.settings.show_touch_controls = original_touch_setting
		get_tree().quit(1)
		return

	var world := packed.instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	_check(is_instance_valid(world.hud.touch_root), "touch control root was not created")
	_check(world.hud.touch_root.visible, "touch controls ignore the mobile preference")

	var joystick: WarfareVirtualJoystick
	var action_buttons: Array[TouchActionButton] = []
	for child in world.hud.touch_root.get_children():
		if child is WarfareVirtualJoystick:
			if child.name != "ShootJoyStick":
				joystick = child
		elif child is TouchActionButton:
			action_buttons.append(child)

	_check(is_instance_valid(joystick), "virtual joystick was not created")
	_check(action_buttons.size() == 1, "expected the DASH auxiliary touch button")
	var joysticks: Array[WarfareVirtualJoystick] = []
	for child in world.hud.touch_root.get_children():
		if child is WarfareVirtualJoystick:
			joysticks.append(child)
	_check(joysticks.size() == 2, "the original dual-joystick mobile layout was not restored")

	var viewport_rect := world.get_viewport().get_visible_rect()
	if is_instance_valid(joystick):
		_check(viewport_rect.encloses(joystick.get_global_rect()), "virtual joystick is outside the viewport")
		_check(joystick.recovered_background != null and joystick.recovered_knob != null, "virtual joystick is not using the original HUD atlas")
		joystick.vector_changed.emit(Vector2(0.35, -0.6))
		_check(world.player.touch_move.is_equal_approx(Vector2(0.35, -0.6)), "joystick is not connected to player movement")

	var captions: Array[String] = []
	for button in action_buttons:
		captions.append(button.caption)
		_check(viewport_rect.encloses(button.get_global_rect()), "%s button is outside the viewport" % button.caption)
	_check(captions.has("DASH"), "DASH touch action is missing")

	var shoot_joystick := world.hud.touch_root.get_node_or_null("ShootJoyStick") as WarfareVirtualJoystick
	_check(is_instance_valid(shoot_joystick), "shoot joystick is missing")
	if is_instance_valid(shoot_joystick):
		shoot_joystick.engaged.emit()
		_check(world.player.touch_fire, "shoot joystick engagement is not connected to fire")
		shoot_joystick.released.emit()
		_check(not world.player.touch_fire, "shoot joystick release leaves the weapon firing")
	var weapon_selector := world.hud.touch_root.get_node_or_null("MobileWeaponSelector") as Button
	_check(is_instance_valid(weapon_selector), "original right-edge weapon selector is missing")
	if is_instance_valid(weapon_selector):
		_check(viewport_rect.encloses(weapon_selector.get_global_rect()), "weapon selector is outside the viewport")
		_check(weapon_selector.icon != null, "weapon selector is missing the original weapon atlas icon")
		var weapon_before := world.player.current_weapon_id
		weapon_selector.pressed.emit()
		_check(world.player.current_weapon_id != weapon_before, "weapon selector does not switch equipped weapons")

	world.hud._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(get_tree().paused and world.hud.pause_overlay.visible, "Android Back does not pause gameplay")
	world.hud._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not get_tree().paused and not world.hud.pause_overlay.visible, "Android Back cannot resume a paused game")

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	GameState.settings.show_touch_controls = original_touch_setting
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", false)
	await get_tree().create_timer(0.2).timeout

	if failures.is_empty():
		print("MOBILE_UI_SMOKE_TEST_PASS")
		get_tree().quit(0)
	else:
		print("MOBILE_UI_SMOKE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
