class_name WarfareHUD
extends CanvasLayer

const JoystickScript = preload("res://scripts/ui/virtual_joystick.gd")
const Atlas = preload("res://scripts/ui/original_atlas.gd")

var world: WarfareGameWorld
var player: WarfarePlayer
var level_data: Dictionary

var health_bar: Range
var health_text: Label
var ammo_text: Label
var weapon_icon: TextureRect
var boss_panel: Control
var boss_bar: Range
var energy_bar: Range
var weapon_button: Button
var announcement: Label
var pause_overlay: Control
var result_overlay: Control
var touch_root: Control
var crosshair: TextureRect
var reticle_target_refresh := 0.0
var hud_root: Control
var pause_button: Button
var skill_button: Button
var boss_icon: TextureRect
var move_joystick: WarfareVirtualJoystick
var shoot_joystick: WarfareVirtualJoystick

func setup(game_world: WarfareGameWorld, controlled_player: WarfarePlayer, data: Dictionary) -> void:
	world = game_world
	player = controlled_player
	level_data = data

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_status_hud()
	_build_crosshair()
	_build_touch_controls()
	_build_pause_overlay()
	get_viewport().size_changed.connect(_layout_original_hud)
	_layout_original_hud()
	if is_instance_valid(player):
		player.health_changed.connect(_on_health_changed)
		player.ammo_changed.connect(_on_ammo_changed)
		player.weapon_changed.connect(_on_weapon_changed)
		player.dash_changed.connect(_on_dash_changed)
		_on_health_changed(player.health, player.shield)
		_on_weapon_changed(player.current_weapon_id, player.current_weapon)
		player._emit_ammo()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready() and not is_instance_valid(result_overlay):
		toggle_pause()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not is_instance_valid(result_overlay):
		toggle_pause()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(world):
		return
	reticle_target_refresh -= delta
	if is_instance_valid(crosshair) and reticle_target_refresh <= 0.0:
		reticle_target_refresh = 0.09
		# StateAim.cs used the weapon's AimID sprite with UIConstant.COLOR_AIM.
		# The original reticle never pulsed while firing. It only changed to
		# opaque red when StateAim detected a valid hostile target.
		crosshair.modulate = Color.RED if player.is_reticle_on_enemy() else Color(0.0, 1.0, 1.0, 0.8)

func _build_status_hud() -> void:
	# The recovered prefab uses a 960x640 logical canvas. At wider/taller
	# aspect ratios the anchors stay on the screen edges while every sprite is
	# uniformly scaled. Keeping the original states separate is what gives the
	# battle view its sparse, readable appearance.
	hud_root = Control.new()
	hud_root.name = "BattleHUDRoot"
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)

	pause_button = _atlas_button("PauseButton", "skill_bk")
	_make_centered_icon(pause_button, Atlas.hud("hud_29"), Vector2(34, 35), Vector2(88, 74))
	pause_button.pressed.connect(toggle_pause)
	hud_root.add_child(pause_button)

	health_bar = _atlas_progress("hud_71", "hud_70", 200.0)
	health_bar.name = "PlayerHP"
	hud_root.add_child(health_bar)
	health_text = _label("200/200", 13, Color(0.0, 0.82, 1.0))
	health_text.name = "PlayerHPValue"
	health_text.add_theme_constant_override("outline_size", 2)
	health_text.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_root.add_child(health_text)

	energy_bar = _atlas_progress("hud_69", "hud_70", 5000.0)
	energy_bar.name = "AmmoBar"
	energy_bar.fill_mode = TextureProgressBar.FILL_RIGHT_TO_LEFT
	hud_root.add_child(energy_bar)
	ammo_text = _label("5000/5000", 13, Color(1.0, 0.78, 0.05))
	ammo_text.name = "AmmoValue"
	ammo_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_text.add_theme_constant_override("outline_size", 2)
	ammo_text.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_root.add_child(ammo_text)

	weapon_button = _atlas_button("WeaponSelector", "hud_59")
	weapon_button.tooltip_text = tr("SWITCH WEAPON")
	weapon_button.pressed.connect(func(): if is_instance_valid(player): player.cycle_weapon(1))
	hud_root.add_child(weapon_button)
	weapon_icon = _make_centered_icon(weapon_button, null, Vector2(100, 77), Vector2(116, 98))

	skill_button = _atlas_button("SkillButton", "hud_32")
	skill_button.tooltip_text = tr("DASH")
	_make_centered_icon(skill_button, Atlas.hud("skill_1"), Vector2(65, 66), Vector2(102, 98))
	skill_button.pressed.connect(func(): if is_instance_valid(player): player.request_touch_dash())
	hud_root.add_child(skill_button)

	boss_panel = Control.new()
	boss_panel.name = "BossState"
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_panel.visible = false
	hud_root.add_child(boss_panel)
	boss_bar = _atlas_progress("hud_72", "hud_73", 100.0)
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_panel.add_child(boss_bar)
	boss_icon = TextureRect.new()
	boss_icon.name = "BossIcon"
	boss_icon.texture = Atlas.hud("hud_35")
	boss_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	boss_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boss_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	boss_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_panel.add_child(boss_icon)

	announcement = _label("", 22, Color(1.0, 0.78, 0.22))
	announcement.name = "Announcement"
	announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcement.add_theme_constant_override("outline_size", 4)
	announcement.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_root.add_child(announcement)

func _build_crosshair() -> void:
	# A real full-screen Control parent is required here. CanvasLayer itself has
	# no layout rectangle, so anchoring the reticle directly to it placed the
	# recovered sprite at (0, 0) on some aspect ratios.
	var reticle_layer := CenterContainer.new()
	reticle_layer.name = "ReticleLayer"
	reticle_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reticle_layer)
	reticle_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair = TextureRect.new()
	crosshair.size = Vector2(76, 50)
	crosshair.pivot_offset = crosshair.size * 0.5
	crosshair.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crosshair.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# HUD.png used bilinear filtering in Unity. This matters when the original
	# 960x640 UI is uniformly scaled to modern phone and desktop resolutions.
	crosshair.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.modulate = Color(0.0, 1.0, 1.0, 0.8)
	reticle_layer.add_child(crosshair)
	_set_reticle_for_weapon({"aim_id": 0})

func _build_touch_controls() -> void:
	if not _should_build_mobile_ui():
		touch_root = null
		return
	touch_root = Control.new()
	touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_root.visible = bool(GameState.settings.show_touch_controls)
	add_child(touch_root)
	move_joystick = JoystickScript.new()
	move_joystick.name = "MoveJoyStick"
	move_joystick.background_sprite = "hud_37"
	move_joystick.vector_changed.connect(func(value):
		if is_instance_valid(player): player.set_touch_move(value)
	)
	touch_root.add_child(move_joystick)

	# The original HUD used a second joystick for camera rotation and firing,
	# rather than a large modern FIRE button.
	shoot_joystick = JoystickScript.new()
	shoot_joystick.name = "ShootJoyStick"
	shoot_joystick.background_sprite = "hud_36"
	shoot_joystick.vector_changed.connect(func(value):
		if is_instance_valid(player): player.apply_touch_look(value * Vector2(5.5, 4.2))
	)
	shoot_joystick.engaged.connect(func(): if is_instance_valid(player): player.set_touch_fire(true))
	shoot_joystick.released.connect(func(): if is_instance_valid(player): player.set_touch_fire(false))
	touch_root.add_child(shoot_joystick)

func _layout_original_hud() -> void:
	if not is_instance_valid(hud_root):
		return
	var ui_scale := _original_ui_scale()

	# HUD.prefab coordinates after converting Unity's positive-up Y to
	# Godot's positive-down canvas coordinates.
	_place_original(pause_button, Vector2(0.0, 0.0), Vector2(50, 40), Vector2(88, 74), ui_scale)
	_place_original(health_bar, Vector2(0.0, 0.0), Vector2(205, 55), Vector2(215, 17), ui_scale)
	_place_original(health_text, Vector2(0.0, 0.0), Vector2(205, 79), Vector2(215, 24), ui_scale)
	_place_original(energy_bar, Vector2(1.0, 0.0), Vector2(-200, 55), Vector2(215, 17), ui_scale)
	_place_original(ammo_text, Vector2(1.0, 0.0), Vector2(-200, 79), Vector2(215, 24), ui_scale)
	_place_original(weapon_button, Vector2(1.0, 0.5), Vector2(-70, -160), Vector2(116, 98), ui_scale)
	_place_original(skill_button, Vector2(1.0, 0.5), Vector2(-50, 50), Vector2(102, 98), ui_scale)
	_place_original(boss_panel, Vector2(0.5, 0.0), Vector2(0, 20), Vector2(510, 32), ui_scale)
	_place_original(announcement, Vector2(0.5, 0.0), Vector2(0, 72), Vector2(600, 40), ui_scale)

	health_text.add_theme_font_size_override("font_size", maxi(10, roundi(13.0 * ui_scale)))
	ammo_text.add_theme_font_size_override("font_size", maxi(10, roundi(13.0 * ui_scale)))
	announcement.add_theme_font_size_override("font_size", maxi(14, roundi(22.0 * ui_scale)))

	if is_instance_valid(boss_icon):
		var boss_icon_size := Vector2(53, 19) * ui_scale
		boss_icon.size = boss_icon_size
		boss_icon.position = boss_panel.size * 0.5 + Vector2(-260.0 * ui_scale, 0.0) - boss_icon_size * 0.5

	if is_instance_valid(move_joystick):
		_place_original(move_joystick, Vector2(0.5, 0.5), Vector2(-320, 170), Vector2(200, 201), ui_scale)
	if is_instance_valid(shoot_joystick):
		_place_original(shoot_joystick, Vector2(0.5, 0.5), Vector2(320, 170), Vector2(200, 197), ui_scale)

	_resize_crosshair()

func _place_original(control: Control, anchor: Vector2, center_offset: Vector2, logical_size: Vector2, ui_scale: float) -> void:
	if not is_instance_valid(control):
		return
	var half_size := logical_size * ui_scale * 0.5
	var center := center_offset * ui_scale
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = center.x - half_size.x
	control.offset_right = center.x + half_size.x
	control.offset_top = center.y - half_size.y
	control.offset_bottom = center.y + half_size.y

func _resize_crosshair() -> void:
	if not is_instance_valid(crosshair) or crosshair.texture == null:
		return
	var display_size := Atlas.logical_size(crosshair.texture) * _original_ui_scale()
	crosshair.custom_minimum_size = display_size
	crosshair.size = display_size
	crosshair.pivot_offset = display_size * 0.5

func _original_ui_scale() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	return maxf(0.1, minf(viewport_size.x / 960.0, viewport_size.y / 640.0))

func _build_pause_overlay() -> void:
	pause_overlay = _modal_base()
	pause_overlay.visible = false
	add_child(pause_overlay)
	var box := _modal_panel(pause_overlay, Vector2(460, 390))
	box.add_child(_center_label(tr("TACTICAL PAUSE"), 30, Color(0.72, 0.94, 1.0)))
	box.add_child(_center_label(tr("The simulation is suspended."), 14, Color(0.62, 0.74, 0.8)))
	var resume := _modal_button(tr("RESUME"))
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)
	var restart := _modal_button(tr("RESTART SECTOR"))
	restart.pressed.connect(_restart)
	box.add_child(restart)
	var options := _modal_button(tr("TOGGLE TOUCH CONTROLS"))
	if is_instance_valid(touch_root):
		options.pressed.connect(func():
			GameState.set_setting("show_touch_controls", not bool(GameState.settings.show_touch_controls))
			touch_root.visible = bool(GameState.settings.show_touch_controls)
		)
		box.add_child(options)
	var menu := _modal_button(tr("ABORT TO MENU"))
	menu.pressed.connect(GameState.return_to_menu)
	box.add_child(menu)

func toggle_pause() -> void:
	if is_instance_valid(result_overlay):
		return
	var pausing := not get_tree().paused
	AudioDirector.play_ui("pause" if pausing else "resume")
	get_tree().paused = pausing
	pause_overlay.visible = pausing
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pausing or OS.has_feature("mobile") else Input.MOUSE_MODE_CAPTURED

func show_result(victory: bool, stats: Dictionary) -> void:
	if is_instance_valid(result_overlay):
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	result_overlay = _modal_base()
	add_child(result_overlay)
	var box := _modal_panel(result_overlay, Vector2(520, 500))
	box.add_child(_center_label(tr("SECTOR SECURED") if victory else tr("OPERATIVE LOST"), 32, Color(0.35, 1.0, 0.63) if victory else Color(1.0, 0.24, 0.12)))
	box.add_child(_center_label(tr("%s • SECTOR %02d") % [tr(str(level_data.name)), int(level_data.number)], 15, Color(0.6, 0.82, 0.9)))
	box.add_child(_center_label(tr("SCORE        %07d") % int(stats.score), 21, Color.WHITE))
	box.add_child(_center_label(tr("HOSTILES     %d") % int(stats.kills), 18, Color.WHITE))
	box.add_child(_center_label(tr("CREDITS      +%d") % int(stats.credits), 18, Color(1.0, 0.78, 0.2)))
	box.add_child(_center_label(tr("TIME         %02d:%02d") % [int(int(stats.time) / 60), int(stats.time) % 60], 18, Color.WHITE))
	if victory:
		var next := _modal_button(tr("NEXT SECTOR"))
		next.pressed.connect(_next_level)
		box.add_child(next)
	var retry := _modal_button(tr("RETRY"))
	retry.pressed.connect(_restart)
	box.add_child(retry)
	var menu := _modal_button(tr("RETURN TO MENU"))
	menu.pressed.connect(GameState.return_to_menu)
	box.add_child(menu)

func announce(message: String, duration := 2.0) -> void:
	announcement.text = message
	announcement.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(announcement, "modulate:a", 0.0, 0.5)

func report_boss(current: float, maximum: float, _title := "ALIEN OVERLORD") -> void:
	boss_panel.visible = true
	boss_bar.max_value = maximum
	boss_bar.value = current

func _on_health_changed(health: float, shield: float) -> void:
	var maximum := 200.0
	if is_instance_valid(player):
		maximum = player.max_health + player.max_shield
	health_bar.max_value = maximum
	health_bar.value = health + shield
	health_text.text = "%d/%d" % [int(health + shield), int(maximum)]

func _on_ammo_changed(current: int, maximum: int, reloading: bool) -> void:
	ammo_text.text = "%d/%d" % [current, maximum]
	ammo_text.add_theme_color_override("font_color", Color(1.0, 0.26, 0.12) if current < maximum / 10 else Color(1.0, 0.78, 0.05))
	if is_instance_valid(energy_bar):
		energy_bar.max_value = maximum
		energy_bar.value = current

func _on_weapon_changed(_weapon_id: String, data: Dictionary) -> void:
	if is_instance_valid(weapon_icon):
		weapon_icon.texture = Atlas.weapon_icon(int(data.id))
	_set_reticle_for_weapon(data)

func _set_reticle_for_weapon(data: Dictionary) -> void:
	if not is_instance_valid(crosshair):
		return
	var aim_id := int(data.get("aim_id", 0))
	var texture := Atlas.hud("hud%d" % clampi(aim_id, 0, 13))
	if texture == null:
		texture = Atlas.hud("hud0")
	crosshair.texture = texture
	if texture:
		var original_size := Atlas.logical_size(texture)
		var display_size := original_size * _original_ui_scale()
		crosshair.custom_minimum_size = display_size
		crosshair.size = display_size
		crosshair.pivot_offset = display_size * 0.5

func _should_build_mobile_ui() -> bool:
	return OS.has_feature("mobile") or bool(ProjectSettings.get_setting("debug/restoration/force_mobile_ui", false))

func _on_dash_changed(ratio: float) -> void:
	if is_instance_valid(skill_button):
		skill_button.disabled = ratio < 0.999
		skill_button.modulate = Color(1.0, 1.0, 1.0, lerpf(0.42, 1.0, clampf(ratio, 0.0, 1.0)))

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _next_level() -> void:
	get_tree().paused = false
	var index := GameState.CAMPAIGN_LEVELS.find(int(level_data.number))
	if index >= 0 and index + 1 < GameState.CAMPAIGN_LEVELS.size():
		GameState.start_level(int(GameState.CAMPAIGN_LEVELS[index + 1]))
	else:
		GameState.return_to_menu()

func _atlas_progress(fill_sprite: String, background_sprite: String, maximum: float) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2.ZERO
	bar.max_value = maximum
	bar.value = maximum
	bar.texture_under = Atlas.hud(background_sprite)
	bar.texture_progress = Atlas.hud(fill_sprite)
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 8
	bar.stretch_margin_right = 8
	return bar

func _atlas_button(node_name: String, sprite_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _atlas_button_style(sprite_name))
	return button

func _atlas_button_style(sprite_name: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = Atlas.hud(sprite_name)
	return style

func _make_centered_icon(parent: Control, texture: Texture2D, logical_size: Vector2, parent_logical_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var relative_size := logical_size / parent_logical_size
	icon.anchor_left = (1.0 - relative_size.x) * 0.5
	icon.anchor_right = 1.0 - icon.anchor_left
	icon.anchor_top = (1.0 - relative_size.y) * 0.5
	icon.anchor_bottom = 1.0 - icon.anchor_top
	parent.add_child(icon)
	return icon

func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _label(value: String, size_value: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color)
	var recovered_font := "res://assets/original/fonts/ZEROTWOS.ttf"
	if ResourceLoader.exists(recovered_font):
		label.add_theme_font_override("font", load(recovered_font))
	return label

func _center_label(value: String, size_value: int, color: Color) -> Label:
	var label := _label(value, size_value, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _modal_base() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.025, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	return root

func _modal_panel(root: Control, minimum_size: Vector2) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.065, 0.09, 0.99), Color(0.16, 0.77, 0.94, 0.95), 12))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box

func _modal_button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 45
	button.add_theme_font_size_override("font_size", 16)
	return button
