extends Node

const REFERENCE_VIEWPORT := Vector2(1280.0, 720.0)
const POSITION_TOLERANCE := 2.0

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MOBILE UI TEST: " + message)

func _named_control(root: Node, control_name: String) -> Control:
	return root.find_child(control_name, true, false) as Control

func _check_center(control: Control, expected: Vector2, label: String) -> void:
	if not is_instance_valid(control):
		_check(false, "%s is missing" % label)
		return
	var actual := control.get_global_rect().get_center()
	_check(
		actual.distance_to(expected) <= POSITION_TOLERANCE,
		"%s center does not match the recovered 960x640 layout (%s vs %s)" % [label, actual, expected]
	)

func _has_visible_texture(root: Control) -> bool:
	if root is TextureRect and (root as TextureRect).texture != null:
		return true
	if root is TextureButton and (root as TextureButton).texture_normal != null:
		return true
	if root is Button and (root as Button).icon != null:
		return true
	if root is TextureProgressBar:
		var progress := root as TextureProgressBar
		if progress.texture_under != null and progress.texture_progress != null:
			return true
	for child in root.get_children():
		if child is Control and _has_visible_texture(child):
			return true
	return false

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

	var viewport_rect := world.get_viewport().get_visible_rect()
	_check(viewport_rect.size.is_equal_approx(REFERENCE_VIEWPORT), "HUD regression coordinates require a 1280x720 viewport, got %s" % viewport_rect.size)
	_check(is_instance_valid(world.hud.touch_root), "touch control root was not created")
	if not is_instance_valid(world.hud.touch_root):
		await _cleanup(world, original_touch_setting)
		return
	_check(world.hud.touch_root.visible, "touch controls ignore the mobile preference")

	# The original mobile HUD had exactly two thumb controls. Weapon, skill,
	# pause and status widgets belong to the shared HUD and must not be copied
	# into touch_root.
	var joysticks: Array[WarfareVirtualJoystick] = []
	for child in world.hud.touch_root.get_children():
		_check(child is WarfareVirtualJoystick, "touch_root contains added control %s instead of only the two original joysticks" % child.name)
		if child is WarfareVirtualJoystick:
			joysticks.append(child)
	_check(joysticks.size() == 2, "the original dual-joystick mobile layout was not restored")
	_check(world.hud.touch_root.find_children("*", "TouchActionButton", true, false).is_empty(), "touch_root still contains the added text DASH button")
	_check(world.hud.touch_root.find_children("*", "BaseButton", true, false).is_empty(), "touch_root still contains a mobile-only weapon or skill button")

	joysticks.sort_custom(func(a: WarfareVirtualJoystick, b: WarfareVirtualJoystick) -> bool:
		return a.get_global_rect().get_center().x < b.get_global_rect().get_center().x
	)
	if joysticks.size() == 2:
		var move_joystick := joysticks[0]
		var shoot_joystick := joysticks[1]
		_check_center(move_joystick, Vector2(280.0, 551.25), "move joystick")
		_check_center(shoot_joystick, Vector2(1000.0, 551.25), "shoot joystick")
		for joystick in joysticks:
			_check(viewport_rect.encloses(joystick.get_global_rect()), "%s is outside the viewport" % joystick.name)
			_check(joystick.recovered_background != null and joystick.recovered_knob != null, "%s is not using the original HUD atlas" % joystick.name)
		move_joystick.vector_changed.emit(Vector2(0.35, -0.6))
		_check(world.player.touch_move.is_equal_approx(Vector2(0.35, -0.6)), "move joystick is not connected to player movement")
		shoot_joystick.engaged.emit()
		_check(world.player.touch_fire, "shoot joystick engagement is not connected to fire")
		shoot_joystick.released.emit()
		_check(not world.player.touch_fire, "shoot joystick release leaves the weapon firing")

	var pause_button := _named_control(world.hud, "PauseButton") as BaseButton
	var weapon_selector := _named_control(world.hud, "WeaponSelector") as BaseButton
	var skill_button := _named_control(world.hud, "SkillButton") as BaseButton
	var player_hp := _named_control(world.hud, "PlayerHP")
	var ammo_bar := _named_control(world.hud, "AmmoBar")
	var boss_state := _named_control(world.hud, "BossState")
	_check(is_instance_valid(pause_button), "shared PauseButton is missing on mobile")
	_check(is_instance_valid(weapon_selector), "shared WeaponSelector is missing on mobile")
	_check(is_instance_valid(skill_button), "shared SkillButton is missing on mobile")
	_check(is_instance_valid(player_hp), "the clean HUD is missing its single PlayerHP bar")
	_check(is_instance_valid(ammo_bar), "the clean HUD is missing its single AmmoBar")
	_check(is_instance_valid(boss_state), "the clean HUD is missing its centered boss bar")
	_check(_named_control(world.hud, "EnemyProgress") == null, "the removed top-center level progress bar is back")
	_check_center(pause_button, Vector2(56.25, 45.0), "PauseButton")
	_check_center(player_hp, Vector2(230.625, 61.875), "PlayerHP")
	_check_center(ammo_bar, Vector2(1055.0, 61.875), "AmmoBar")
	_check_center(weapon_selector, Vector2(1201.25, 180.0), "WeaponSelector")
	if is_instance_valid(boss_state):
		_check(absf(boss_state.get_global_rect().get_center().x - viewport_rect.get_center().x) <= POSITION_TOLERANCE, "boss bar is not centered across the screen")

	var textured_controls: Array[Control] = [pause_button, weapon_selector, skill_button, player_hp, ammo_bar, boss_state]
	for item in textured_controls:
		if is_instance_valid(item):
			_check(_has_visible_texture(item), "%s is not backed by recovered atlas artwork" % item.name)

	if is_instance_valid(weapon_selector):
		var weapon_before := world.player.current_weapon_id
		weapon_selector.pressed.emit()
		# Container layout is applied on the next UI frame after the AimID
		# texture changes size. Check the position that can actually be drawn.
		await get_tree().process_frame
		_check(world.player.current_weapon_id != weapon_before, "shared WeaponSelector does not switch equipped weapons")

	var viewport_center := viewport_rect.get_center()
	var reticle_center := world.hud.crosshair.get_global_rect().get_center()
	_check(reticle_center.distance_to(viewport_center) < 1.0, "reticle is not at the exact original screen center (%s vs %s)" % [reticle_center, viewport_center])
	_check(world.hud.crosshair.texture != null, "reticle is missing its original AimID atlas sprite")

	world.hud._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(get_tree().paused and world.hud.pause_overlay.visible, "Android Back does not pause gameplay")
	world.hud._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not get_tree().paused and not world.hud.pause_overlay.visible, "Android Back cannot resume a paused game")

	await _cleanup(world, original_touch_setting)

func _cleanup(world: WarfareGameWorld, original_touch_setting: bool) -> void:
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
		print("MOBILE_UI_SMOKE_TEST_PASS clean_shared_hud=true dual_joystick=true")
		get_tree().quit(0)
	else:
		print("MOBILE_UI_SMOKE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
