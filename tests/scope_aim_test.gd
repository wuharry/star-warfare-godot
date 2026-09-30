extends Node

const Optics = preload("res://scripts/core/weapon_optics.gd")
var failures: Array[String] = []
var checks := 0
var world: WarfareGameWorld
var player: WarfarePlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SCOPE AIM TEST: " + message)

func _settle() -> void:
	for frame in 120:
		player._update_camera_controller(1.0 / 60.0)
	world.hud._update_aim_hud()
	world.hud._update_fire_reticle_visibility()

func _tap(button: Control, index: int = 7) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_level = 1
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = true
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", true)
	world = (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	world.completed = true
	world.set_physics_process(false)
	player = world.player
	player.set_physics_process(false)
	_check(InputMap.has_action("scope_zoom"), "magnification input was not registered")
	_check_scoped_readouts()
	# Audit-backed opt-in: an iron-sighted sniper or laser gets its old zoom,
	# while a scoped rifle must not lose its lens just because it is not a sniper.
	for id: String in ["gun01", "gun17", "gun19", "gun43"]:
		player.equip_weapon(id, false)
		Input.action_press("aim")
		_settle()
		_check(not player.is_scope_active() and not world.hud.scope_overlay.visible, id + " gained an unmodelled scope")
		var expected := 13.2 if id == "gun43" else 22.0
		_check(absf(player.camera.fov - expected) < 0.01, id + " lost its original unscoped zoom")
		_check(world.hud.crosshair.visible and player.model.visible, id + " lost its third-person view/reticle")
	Input.action_release("aim")
	for id: String in Optics.PROFILES:
		player.equip_weapon(id, false)
		var hip_texture := world.hud.crosshair.texture
		Input.action_press("aim")
		for step in player.get_scope_magnifications().size():
			_settle()
			var zoom := player.get_scope_magnification()
			var center := get_viewport().get_visible_rect().get_center()
			var sample := player.camera.global_transform * Vector3(1, 0, -20)
			var magnified_offset := player.camera.unproject_position(sample).distance_to(center)
			var scoped_fov := player.camera.fov
			player.camera.fov = player.get_hip_fov()
			var hip_offset := player.camera.unproject_position(sample).distance_to(center)
			player.camera.fov = scoped_fov
			_check(absf(magnified_offset / hip_offset - zoom) < 0.01, id + " label does not match actual perspective enlargement")
			_check(world.hud.scope_overlay.visible and not player.model.visible, id + " did not enter its live lens view")
			_check(world.hud.scope_overlay.optic.id == Optics.PROFILES[id].id, id + " used another optic's reticle/frame")
			_check(not world.hud.crosshair.visible and not world.hud.fire_crosshair.visible, id + " superimposed a hip-fire reticle on its scope")
			_check(world.hud.scope_zoom_button.visible == (player.get_scope_magnifications().size() > 1), "fixed and variable optics show the same zoom controls")
			var aim := player.get_aim_solution(40.0)
			var projected := player.camera.unproject_position(Vector3(aim.origin) + Vector3(aim.direction) * 20.0)
			_check(projected.distance_to(center) < 0.01, "scoped reticle and shot ray diverged")
			var zoom_event := InputEventAction.new()
			zoom_event.action = "scope_zoom"
			zoom_event.pressed = true
			player._unhandled_input(zoom_event)
		_check(player.scope_magnification_index == 0, id + " did not cycle back to its first magnification")
		Input.action_release("aim")
		_settle()
		_check(not world.hud.scope_overlay.visible and player.model.visible, id + " scope/hidden avatar leaked after release")
		_check(world.hud.crosshair.visible and world.hud.crosshair.texture == hip_texture, id + " did not restore its original hip reticle")
		_check(absf(player.camera.fov - player.get_hip_fov()) < 0.01, "hip FOV was not restored")
	# Real touch event routing, including a button disappearing before release.
	player.equip_weapon("gun40", false)
	await get_tree().process_frame
	_tap(world.hud.aim_button)
	_settle()
	_check(player.is_scope_active(), "mobile AIM tap did not enter the scope")
	_tap(world.hud.scope_zoom_button)
	_settle()
	_check(is_equal_approx(player.get_scope_magnification(), 4.0), "mobile magnification tap did not change FOV/profile")
	var touch := InputEventScreenTouch.new()
	touch.index = 8
	touch.pressed = true
	touch.position = world.hud.scope_zoom_button.get_global_rect().get_center()
	get_viewport().push_input(touch, true)
	player._set_magazine_rounds(1)
	player._start_reload()
	_settle()
	_check(not player.is_focus_aiming() and not world.hud.scope_overlay.visible and player.model.visible, "reload did not exit the scope")
	touch = touch.duplicate()
	touch.pressed = false
	get_viewport().push_input(touch, true)
	_check(world.hud.scope_zoom_button.active_touch == -1, "hidden zoom button retained its old finger")
	_tap(world.hud.aim_button)
	_check(not player.touch_aim, "mobile aim enabled while reloading")
	player._cancel_reload(false)
	world.hud.touch_root.hide()
	_tap(world.hud.aim_button)
	_check(not player.touch_aim, "hidden touch controls still accepted aim")
	world.hud.touch_root.show()
	_tap(world.hud.aim_button)
	_settle()
	world.hud.toggle_pause()
	_check(not world.hud.scope_overlay.visible and player.model.visible and is_equal_approx(player.camera.fov, 60.0), "pause retained scope zoom/hidden avatar")
	_tap(world.hud.aim_button)
	_check(not player.touch_aim, "pause menu accepted an aim tap")
	world.hud.toggle_pause()
	_tap(world.hud.aim_button)
	_settle()
	player.equip_weapon("gun01", false)
	_settle()
	_check(not player.touch_aim and player.scope_magnification_index == 0 and player.model.visible, "weapon swap retained the previous optic state")
	player.equip_weapon("gun00", false)
	_tap(world.hud.aim_button)
	_settle()
	player._die()
	world.hud._update_aim_hud()
	_check(not world.hud.scope_overlay.visible and player.model.visible and is_equal_approx(player.camera.fov, 60.0), "death retained the scope")
	get_tree().paused = false
	Input.action_release("aim")
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("SCOPE_AIM_TEST_%s optics=5 checks=%d projection=true two_reticles=true touch=true lifecycle=true readouts=true" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_scoped_readouts() -> void:
	# Each optic reports one live value. The overlay must receive real player
	# state, and it must not redraw when nothing displayed actually moved.
	var overlay := world.hud.scope_overlay
	for id: String in ["gun00", "gun14", "gun34", "gun35", "gun40"]:
		player.equip_weapon(id, false)
		var readout: Dictionary = player.get_reticle_readout()
		for key: String in overlay.READOUT_KEYS:
			_check(readout.has(key), id + " readout is missing " + key)
		_check(float(readout.target_distance) <= float(readout.weapon_range) + 0.01, id + " target distance exceeded its range")
		_check(float(readout.cooldown_ratio) >= 0.0 and float(readout.cooldown_ratio) <= 1.0, id + " cooldown ratio left 0..1")
		var arcing := str(player.current_weapon.get("kind", "")) == "grenade"
		var offset: Variant = readout.impact_offset
		_check(offset is Vector2 and Vector2(offset).is_finite() == arcing,
			id + " impact marker does not match whether the shot arcs")
		overlay.readout = {}
		overlay.set_readout(readout)
		_check(not overlay.readout.is_empty(), id + " readout never reached the overlay")
		# Re-sending identical values must not queue another surround redraw.
		var before: Dictionary = overlay.readout
		overlay.set_readout(readout.duplicate())
		_check(overlay.readout == before, id + " redrew on an unchanged readout")
	player.equip_weapon("gun00", false)
