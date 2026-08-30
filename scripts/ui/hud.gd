class_name WarfareHUD
extends CanvasLayer

const JoystickScript = preload("res://scripts/ui/virtual_joystick.gd")
const TouchButtonScript = preload("res://scripts/ui/touch_action_button.gd")
const Atlas = preload("res://scripts/ui/original_atlas.gd")

var world: WarfareGameWorld
var player: WarfarePlayer
var level_data: Dictionary

var health_bar: Range
var shield_bar: Range
var health_text: Label
var ammo_text: Label
var weapon_text: Label
var weapon_icon: TextureRect
var wave_text: Label
var score_text: Label
var credits_text: Label
var enemy_text: Label
var boss_panel: PanelContainer
var boss_bar: Range
var boss_text: Label
var dash_bar: Range
var energy_bar: Range
var ammo_panel: PanelContainer
var mobile_weapon_button: Button
var announcement: Label
var pause_overlay: Control
var result_overlay: Control
var touch_root: Control
var crosshair: TextureRect
var reticle_target_refresh := 0.0

func setup(game_world: WarfareGameWorld, controlled_player: WarfarePlayer, data: Dictionary) -> void:
	world = game_world
	player = controlled_player
	level_data = data

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_vignette()
	_build_status_hud()
	_build_crosshair()
	_build_touch_controls()
	_build_pause_overlay()
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
		# Keep the original cyan exactly, and switch to red only on a valid target.
		crosshair.modulate = Color(1.0, 0.0, 0.0, 0.95) if player.is_reticle_on_enemy() else Color(0.0, 1.0, 1.0, 0.8)
		crosshair.scale = Vector2.ONE * (1.2 if player.shoot_pose_left > 0.0 else 1.0)
	wave_text.text = "WAVE  %d / %d" % [world.current_wave, int(level_data.waves)]
	score_text.text = "SCORE  %07d" % world.score
	credits_text.text = "CREDITS  %05d" % world.battle_credits
	enemy_text.text = "HOSTILES  %02d" % world.alive_enemies

func _build_vignette() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment(){
	vec2 p = UV * 2.0 - 1.0;
	float edge = smoothstep(.54, 1.35, length(p * vec2(.78, 1.0)));
	COLOR = vec4(.0, .015, .025, edge * .37);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	overlay.material = material
	add_child(overlay)

func _build_status_hud() -> void:
	var top_left := PanelContainer.new()
	top_left.position = Vector2(10, 10)
	top_left.custom_minimum_size = Vector2(403, 108)
	top_left.add_theme_stylebox_override("panel", _atlas_panel_style("hud_41", 14))
	add_child(top_left)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 5)
	top_left.add_child(bars)
	var sector := _label("SECTOR %02d • %s" % [int(level_data.number), str(level_data.name)], 15, Color(0.48, 0.88, 1.0))
	bars.add_child(sector)
	health_bar = _atlas_progress("hud_71", "hud_70", 100.0)
	bars.add_child(health_bar)
	shield_bar = _atlas_progress("hud_68", "hud_64", 100.0)
	bars.add_child(shield_bar)
	health_text = _label("ARMOR 100  •  SHIELD 100", 13, Color(0.86, 0.94, 0.98))
	bars.add_child(health_text)

	var top_center := VBoxContainer.new()
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_center.position = Vector2(-150, 20)
	top_center.custom_minimum_size = Vector2(300, 86)
	top_center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top_center)
	wave_text = _label("WAVE  0 / %d" % int(level_data.waves), 19, Color(0.76, 0.94, 1.0))
	wave_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center.add_child(wave_text)
	enemy_text = _label("HOSTILES  00", 14, Color(1.0, 0.48, 0.23))
	enemy_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center.add_child(enemy_text)
	announcement = _label("", 22, Color(1.0, 0.78, 0.22))
	announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center.add_child(announcement)

	var top_right := PanelContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.position = Vector2(-413, 10)
	top_right.custom_minimum_size = Vector2(403, 108)
	top_right.add_theme_stylebox_override("panel", _atlas_panel_style("hud_42", 14))
	add_child(top_right)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	top_right.add_child(stats)
	score_text = _label("SCORE  0000000", 18, Color(0.75, 0.92, 0.98))
	credits_text = _label("CREDITS  00000", 15, Color(1.0, 0.77, 0.2))
	stats.add_child(score_text)
	stats.add_child(credits_text)
	var pause_button := Button.new()
	pause_button.text = "Ⅱ  PAUSE"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(toggle_pause)
	stats.add_child(pause_button)

	ammo_panel = PanelContainer.new()
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_panel.position = Vector2(-322, -154)
	ammo_panel.custom_minimum_size = Vector2(302, 134)
	ammo_panel.add_theme_stylebox_override("panel", _atlas_panel_style("hud_47", 16))
	add_child(ammo_panel)
	var ammo_column := VBoxContainer.new()
	ammo_column.add_theme_constant_override("separation", 3)
	ammo_panel.add_child(ammo_column)
	weapon_text = _label("AR-01 RIFLE", 14, Color(0.45, 0.88, 1.0))
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 9)
	weapon_icon = TextureRect.new()
	weapon_icon.custom_minimum_size = Vector2(92, 58)
	weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(weapon_icon)
	weapon_row.add_child(weapon_text)
	ammo_text = _label("ENERGY 5000 / 5000", 24, Color.WHITE)
	ammo_column.add_child(weapon_row)
	ammo_column.add_child(ammo_text)
	energy_bar = _atlas_progress("hud_69", "hud_70", 5000.0)
	ammo_column.add_child(energy_bar)
	dash_bar = _progress(Color(1.0, 0.67, 0.14), 1.0)
	dash_bar.custom_minimum_size.y = 6
	dash_bar.value = 1.0
	ammo_column.add_child(dash_bar)

	boss_panel = PanelContainer.new()
	boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_panel.position = Vector2(-330, 117)
	boss_panel.custom_minimum_size = Vector2(660, 74)
	boss_panel.visible = false
	boss_panel.add_theme_stylebox_override("panel", _atlas_panel_style("hud_44", 15))
	add_child(boss_panel)
	var boss_column := VBoxContainer.new()
	boss_panel.add_child(boss_column)
	boss_text = _label("BOSS", 16, Color(1.0, 0.55, 0.25))
	boss_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = _progress(Color(0.92, 0.08, 0.04), 100.0)
	boss_column.add_child(boss_text)
	boss_column.add_child(boss_bar)

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
	crosshair.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	var joystick := JoystickScript.new()
	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# HUD.prefab authored these centers at (-320, -170)/(320, -170)
	# in its 960x640 reference canvas. This is the equivalent 16:9 layout.
	joystick.position = Vector2(176, -294)
	joystick.size = Vector2(208, 208)
	joystick.vector_changed.connect(func(value):
		if is_instance_valid(player): player.set_touch_move(value)
	)
	touch_root.add_child(joystick)

	# The original HUD used a second joystick for camera rotation and firing,
	# rather than a large modern FIRE button.
	var shoot_joystick := JoystickScript.new()
	shoot_joystick.name = "ShootJoyStick"
	shoot_joystick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	shoot_joystick.position = Vector2(-384, -294)
	shoot_joystick.size = Vector2(208, 208)
	shoot_joystick.background_sprite = "hud_36"
	shoot_joystick.vector_changed.connect(func(value):
		if is_instance_valid(player): player.apply_touch_look(value * Vector2(5.5, 4.2))
	)
	shoot_joystick.engaged.connect(func(): if is_instance_valid(player): player.set_touch_fire(true))
	shoot_joystick.released.connect(func(): if is_instance_valid(player): player.set_touch_fire(false))
	touch_root.add_child(shoot_joystick)

	# State-Weapon in the Unity HUD was a compact right-edge draggable item,
	# rather than separate PREV/SWAP buttons over the ammunition panel.
	mobile_weapon_button = Button.new()
	mobile_weapon_button.name = "MobileWeaponSelector"
	mobile_weapon_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mobile_weapon_button.position = Vector2(-118, 130)
	mobile_weapon_button.size = Vector2(96, 88)
	mobile_weapon_button.expand_icon = true
	mobile_weapon_button.tooltip_text = "SWITCH WEAPON"
	mobile_weapon_button.add_theme_stylebox_override("normal", _atlas_panel_style("hud_47", 10))
	mobile_weapon_button.add_theme_stylebox_override("hover", _atlas_panel_style("hud_47", 10))
	mobile_weapon_button.pressed.connect(func(): if is_instance_valid(player): player.cycle_weapon(1))
	touch_root.add_child(mobile_weapon_button)

	var dash := _touch_button("DASH", Color(1.0, 0.7, 0.08), Vector2(400, -108), Vector2(72, 72))
	dash.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dash.pressed.connect(func(): if is_instance_valid(player): player.request_touch_dash())
	touch_root.add_child(dash)

	# Keep the useful restored energy readout, but place it between the original
	# joystick centers so it cannot obstruct either thumb zone.
	if is_instance_valid(ammo_panel):
		ammo_panel.anchor_left = 0.5
		ammo_panel.anchor_right = 0.5
		ammo_panel.anchor_top = 1.0
		ammo_panel.anchor_bottom = 1.0
		ammo_panel.position = Vector2(-151, -144)

func _build_pause_overlay() -> void:
	pause_overlay = _modal_base()
	pause_overlay.visible = false
	add_child(pause_overlay)
	var box := _modal_panel(pause_overlay, Vector2(460, 390))
	box.add_child(_center_label("TACTICAL PAUSE", 30, Color(0.72, 0.94, 1.0)))
	box.add_child(_center_label("The simulation is suspended.", 14, Color(0.62, 0.74, 0.8)))
	var resume := _modal_button("RESUME")
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)
	var restart := _modal_button("RESTART SECTOR")
	restart.pressed.connect(_restart)
	box.add_child(restart)
	var options := _modal_button("TOGGLE TOUCH CONTROLS")
	if is_instance_valid(touch_root):
		options.pressed.connect(func():
			GameState.set_setting("show_touch_controls", not bool(GameState.settings.show_touch_controls))
			touch_root.visible = bool(GameState.settings.show_touch_controls)
		)
		box.add_child(options)
	var menu := _modal_button("ABORT TO MENU")
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
	box.add_child(_center_label("SECTOR SECURED" if victory else "OPERATIVE LOST", 32, Color(0.35, 1.0, 0.63) if victory else Color(1.0, 0.24, 0.12)))
	box.add_child(_center_label("%s • SECTOR %02d" % [str(level_data.name), int(level_data.number)], 15, Color(0.6, 0.82, 0.9)))
	box.add_child(_center_label("SCORE        %07d" % int(stats.score), 21, Color.WHITE))
	box.add_child(_center_label("HOSTILES     %d" % int(stats.kills), 18, Color.WHITE))
	box.add_child(_center_label("CREDITS      +%d" % int(stats.credits), 18, Color(1.0, 0.78, 0.2)))
	box.add_child(_center_label("TIME         %02d:%02d" % [int(int(stats.time) / 60), int(stats.time) % 60], 18, Color.WHITE))
	if victory:
		var next := _modal_button("NEXT SECTOR")
		next.pressed.connect(_next_level)
		box.add_child(next)
	var retry := _modal_button("RETRY")
	retry.pressed.connect(_restart)
	box.add_child(retry)
	var menu := _modal_button("RETURN TO MENU")
	menu.pressed.connect(GameState.return_to_menu)
	box.add_child(menu)

func announce(message: String, duration := 2.0) -> void:
	announcement.text = message
	announcement.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(announcement, "modulate:a", 0.0, 0.5)

func report_boss(current: float, maximum: float, title := "ALIEN OVERLORD") -> void:
	boss_panel.visible = true
	boss_bar.max_value = maximum
	boss_bar.value = current
	boss_text.text = title

func _on_health_changed(health: float, shield: float) -> void:
	health_bar.value = health
	shield_bar.value = shield
	health_text.text = "ARMOR %03d  •  SHIELD %03d" % [int(health), int(shield)]

func _on_ammo_changed(current: int, maximum: int, reloading: bool) -> void:
	ammo_text.text = "ENERGY %04d / %04d" % [current, maximum]
	ammo_text.add_theme_color_override("font_color", Color(1.0, 0.26, 0.12) if current < maximum / 10 else Color.WHITE)
	if is_instance_valid(energy_bar):
		energy_bar.max_value = maximum
		energy_bar.value = current

func _on_weapon_changed(_weapon_id: String, data: Dictionary) -> void:
	weapon_text.text = str(data.name)
	weapon_text.add_theme_color_override("font_color", data.color)
	if is_instance_valid(weapon_icon):
		weapon_icon.texture = Atlas.weapon_icon(int(data.id))
	if is_instance_valid(mobile_weapon_button):
		mobile_weapon_button.icon = Atlas.weapon_icon(int(data.id))
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
		var original_size := texture.get_size()
		crosshair.custom_minimum_size = original_size
		crosshair.size = original_size
		crosshair.pivot_offset = original_size * 0.5

func _should_build_mobile_ui() -> bool:
	return OS.has_feature("mobile") or bool(ProjectSettings.get_setting("debug/restoration/force_mobile_ui", false))

func _on_dash_changed(ratio: float) -> void:
	dash_bar.value = ratio

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

func _touch_button(caption: String, color: Color, offset: Vector2, button_size: Vector2) -> TouchActionButton:
	var button := TouchButtonScript.new()
	button.caption = caption
	button.accent = color
	button.position = offset
	button.size = button_size
	return button

func _progress(color: Color, maximum: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(250, 14)
	bar.max_value = maximum
	bar.value = maximum
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.005, 0.02, 0.03, 0.85)
	background.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _atlas_progress(fill_sprite: String, background_sprite: String, maximum: float) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(250, 17)
	bar.max_value = maximum
	bar.value = maximum
	bar.texture_under = Atlas.hud(background_sprite)
	bar.texture_progress = Atlas.hud(fill_sprite)
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 8
	bar.stretch_margin_right = 8
	return bar

func _atlas_panel_style(sprite_name: String, margin: float) -> StyleBox:
	var texture := Atlas.hud(sprite_name)
	if texture == null:
		return _panel_style(Color(0.015, 0.06, 0.085, 0.86), Color(0.08, 0.52, 0.68, 0.78), 7)
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.set_texture_margin_all(margin)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.75
	style.content_margin_bottom = margin * 0.75
	return style

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
