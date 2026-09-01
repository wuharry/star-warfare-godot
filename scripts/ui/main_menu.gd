extends Control

const Atlas = preload("res://scripts/ui/original_atlas.gd")
const EquipmentShell = preload("res://scripts/ui/unity_equipment_shell.gd")
const COMPONENT_DIR := "res://assets/ui/components/"
const DESIGN_SIZE := Vector2(960.0, 640.0)
const CYAN := Color(0.4, 1.0, 1.0)

var design_root: Control
var main_page: Control
var modal_layer: Control
var drawer: Control
var drawer_shadow: Button
var drawer_toggle: Button
var drawer_status: Label
var drawer_open := false
var drawer_tween: Tween
var music_player: AudioStreamPlayer
var equipment_shell: UnityEquipmentShell

# Compatibility fields kept for the restoration tests and older menu callers.
var store_weapon_row: HBoxContainer
var store_slot_picker: OptionButton
var store_category_buttons: Dictionary = {}


func _ready() -> void:
	var recovered_font := "res://assets/original/fonts/ZEROTWOS.ttf"
	if ResourceLoader.exists(recovered_font):
		var recovered_theme := Theme.new()
		recovered_theme.default_font = load(recovered_font)
		recovered_theme.default_font_size = 16
		theme = recovered_theme
	_build_letterbox()
	_build_design_root()
	_build_main_page()
	_build_navigation_drawer()
	_build_modal_layer()
	_rescale_design()
	resized.connect(_rescale_design)
	_start_intro_animation()
	_start_music()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not is_node_ready():
		return
	_handle_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_back()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if drawer_tween and drawer_tween.is_valid():
		drawer_tween.kill()
	if is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null


func _handle_back() -> void:
	if is_instance_valid(modal_layer) and modal_layer.get_child_count() > 0:
		AudioDirector.play_ui("back")
		_close_modal()
	elif drawer_open:
		_toggle_drawer(false)
	else:
		_toggle_drawer(true)


func _build_letterbox() -> void:
	var black := ColorRect.new()
	black.name = "Letterbox"
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)


func _build_design_root() -> void:
	design_root = Control.new()
	design_root.name = "Unity960x640"
	design_root.size = DESIGN_SIZE
	design_root.clip_contents = true
	design_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(design_root)


func _build_main_page() -> void:
	main_page = Control.new()
	main_page.name = "MainMenuPage"
	_set_rect(main_page, Rect2(Vector2.ZERO, DESIGN_SIZE))
	design_root.add_child(main_page)

	var hero := TextureRect.new()
	hero.name = "RecoveredMainBackdrop"
	hero.texture = _component("menu_hero")
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_set_rect(hero, Rect2(Vector2.ZERO, DESIGN_SIZE))
	hero.modulate = Color(0.74, 0.82, 0.86, 0.78)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_page.add_child(hero)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.012, 0.022, 0.52)
	_set_rect(shade, Rect2(Vector2.ZERO, DESIGN_SIZE))
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_page.add_child(shade)

	for i in range(28):
		var spark := ColorRect.new()
		var spark_size := 1.0 + float((i * 13) % 3)
		spark.color = Color(0.25, 0.85, 1.0, 0.16 + float(i % 3) * 0.08)
		_set_rect(spark, Rect2(float((i * 193) % 920) + 20.0, float((i * 83) % 520) + 10.0, spark_size, spark_size))
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main_page.add_child(spark)

	var strip := Panel.new()
	strip.name = "DeploymentStrip"
	strip.add_theme_stylebox_override("panel", _panel_style(Color(0.005, 0.035, 0.05, 0.96), Color(0.1, 0.64, 0.74, 0.82), 1, 3))
	_set_rect(strip, Rect2(0, 0, 960, 150))
	main_page.add_child(strip)

	var solo := _deployment_button(tr("SINGLE PLAYER"), tr("CAMPAIGN / SECTORS 01-08"))
	solo.name = "SoloButton"
	_set_rect(solo, Rect2(90, 28, 348, 87))
	solo.pressed.connect(func():
		AudioDirector.play_ui("accept")
		_show_level_select("singleplayer")
	)
	strip.add_child(solo)

	var coop := _deployment_button(tr("MULTIPLAYER"), tr("LOCAL SKIRMISH / SECTORS 13-21"))
	coop.name = "MultiplayerButton"
	_set_rect(coop, Rect2(521, 28, 348, 87))
	coop.pressed.connect(func():
		AudioDirector.play_ui("accept")
		_show_level_select("multiplayer")
	)
	strip.add_child(coop)

	var divider := ColorRect.new()
	divider.color = Color(0.38, 0.95, 1.0, 0.42)
	_set_rect(divider, Rect2(479, 21, 2, 108))
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(divider)

	var logo_texture := _component("menu_logo")
	if logo_texture:
		var logo := TextureRect.new()
		logo.name = "RecoveredTitle"
		logo.texture = logo_texture
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(logo, Rect2(250, 242, 460, 108))
		main_page.add_child(logo)
		var subtitle_texture := _component("menu_subtitle")
		if subtitle_texture:
			var subtitle := TextureRect.new()
			subtitle.texture = subtitle_texture
			subtitle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			subtitle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_rect(subtitle, Rect2(275, 353, 410, 28))
			main_page.add_child(subtitle)
	else:
		var fallback_title := _label("STAR WARFARE", 56, Color(0.93, 0.99, 1.0))
		fallback_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_rect(fallback_title, Rect2(180, 255, 600, 80))
		main_page.add_child(fallback_title)

	var edition := _label(tr("LOCAL OFFLINE RESTORATION"), 14, Color(0.38, 0.84, 0.94))
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(edition, Rect2(250, 390, 460, 24))
	main_page.add_child(edition)

	var expanse := _deployment_button(tr("THE EXPANSE"), tr("OPEN CONTINENT / FREE DEPLOYMENT"))
	expanse.name = "ExpanseButton"
	_set_rect(expanse, Rect2(280, 458, 400, 74))
	expanse.pressed.connect(func():
		AudioDirector.play_ui("accept")
		GameState.start_expanse()
	)
	main_page.add_child(expanse)

	var instruction := _label(tr("CHOOSE SOLO OR MULTIPLAYER • OPEN THE ARMORY FROM THE LOWER MENU"), 12, Color(0.55, 0.72, 0.78))
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(instruction, Rect2(170, 432, 620, 24))
	main_page.add_child(instruction)

	var version := _label("VER 2.97  /  GODOT 4.7", 11, Color(0.7, 0.78, 0.8))
	_set_rect(version, Rect2(10, 615, 230, 18))
	main_page.add_child(version)

	call_deferred("_focus_control", solo)


func _build_navigation_drawer() -> void:
	drawer_shadow = Button.new()
	drawer_shadow.name = "DrawerShadow"
	drawer_shadow.text = ""
	drawer_shadow.focus_mode = Control.FOCUS_NONE
	drawer_shadow.add_theme_stylebox_override("normal", _flat_style(Color(0.0, 0.008, 0.015, 0.68)))
	drawer_shadow.add_theme_stylebox_override("hover", _flat_style(Color(0.0, 0.008, 0.015, 0.68)))
	drawer_shadow.add_theme_stylebox_override("pressed", _flat_style(Color(0.0, 0.008, 0.015, 0.72)))
	_set_rect(drawer_shadow, Rect2(Vector2.ZERO, DESIGN_SIZE))
	drawer_shadow.z_index = 5
	drawer_shadow.visible = false
	drawer_shadow.pressed.connect(func(): _toggle_drawer(false))
	design_root.add_child(drawer_shadow)

	drawer = Control.new()
	drawer.name = "NavigationDrawer"
	_set_rect(drawer, Rect2(0, 544, 960, 350))
	drawer.z_index = 6
	design_root.add_child(drawer)

	var drawer_body := Panel.new()
	drawer_body.add_theme_stylebox_override("panel", _panel_style(Color(0.01, 0.045, 0.058, 0.99), Color(0.09, 0.62, 0.7, 0.9), 2, 2))
	_set_rect(drawer_body, Rect2(0, 78, 960, 272))
	drawer.add_child(drawer_body)

	var collapsed_bar := Panel.new()
	collapsed_bar.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.035, 0.048, 0.995), Color(0.12, 0.72, 0.82, 0.94), 1, 2))
	_set_rect(collapsed_bar, Rect2(0, 0, 960, 96))
	drawer.add_child(collapsed_bar)

	var nav_title := _label(tr("STAR WARFARE COMMAND"), 19, CYAN)
	_set_rect(nav_title, Rect2(24, 13, 340, 29))
	collapsed_bar.add_child(nav_title)
	var nav_hint := _label(tr("STORE • CUSTOMIZE • OPTIONS"), 11, Color(0.52, 0.76, 0.82))
	_set_rect(nav_hint, Rect2(24, 47, 340, 20))
	collapsed_bar.add_child(nav_hint)

	drawer_status = _label("", 12, Color(0.95, 0.79, 0.32))
	drawer_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	drawer_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(drawer_status, Rect2(390, 7, 425, 70))
	collapsed_bar.add_child(drawer_status)
	_refresh_drawer_status()

	drawer_toggle = Button.new()
	drawer_toggle.name = "DrawerToggle"
	drawer_toggle.text = tr("MENU") + "\n▲"
	drawer_toggle.add_theme_font_size_override("font_size", 17)
	drawer_toggle.add_theme_stylebox_override("normal", _recovered_button_style("button_normal", Color(0.72, 1.0, 1.0)))
	drawer_toggle.add_theme_stylebox_override("hover", _recovered_button_style("button_hover", Color.WHITE))
	drawer_toggle.add_theme_stylebox_override("pressed", _recovered_button_style("button_pressed", Color(0.72, 1.0, 1.0)))
	_set_rect(drawer_toggle, Rect2(840, 0, 120, 96))
	drawer_toggle.pressed.connect(func(): _toggle_drawer(not drawer_open))
	drawer.add_child(drawer_toggle)

	var customize := _drawer_button(tr("CUSTOMIZE"), tr("EQUIP OWNED GEAR"))
	_set_rect(customize, Rect2(520, 123, 190, 100))
	customize.pressed.connect(func(): _show_armory("customize"))
	drawer.add_child(customize)
	var store := _drawer_button(tr("STORE"), tr("ARMOR & WEAPONS"))
	_set_rect(store, Rect2(740, 123, 190, 100))
	store.pressed.connect(func(): _show_armory("store"))
	drawer.add_child(store)

	var options := _drawer_button(tr("OPTIONS"), tr("AUDIO • VIDEO • CONTROL"), 14)
	_set_rect(options, Rect2(29, 233, 190, 100))
	options.pressed.connect(_show_options)
	drawer.add_child(options)
	var manual := _drawer_button(tr("FIELD MANUAL"), tr("CONTROLS & STATUS"), 13)
	_set_rect(manual, Rect2(249, 233, 190, 100))
	manual.pressed.connect(_show_help)
	drawer.add_child(manual)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := _drawer_button(tr("QUIT"), tr("RETURN TO DESKTOP"), 14)
		_set_rect(quit, Rect2(469, 233, 190, 100))
		quit.pressed.connect(get_tree().quit)
		drawer.add_child(quit)


func _build_modal_layer() -> void:
	modal_layer = Control.new()
	modal_layer.name = "ModalLayer"
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.z_index = 20
	design_root.add_child(modal_layer)


func _rescale_design() -> void:
	if not is_instance_valid(design_root):
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		available = get_viewport_rect().size
	var scale_factor := minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	design_root.scale = Vector2.ONE * maxf(scale_factor, 0.01)
	design_root.position = (available - DESIGN_SIZE * scale_factor) * 0.5
	design_root.size = DESIGN_SIZE


func _start_intro_animation() -> void:
	var strip := main_page.get_node_or_null("DeploymentStrip") as Control
	var title := main_page.get_node_or_null("RecoveredTitle") as Control
	if is_instance_valid(strip):
		strip.position.y = -150.0
		var strip_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		strip_tween.tween_property(strip, "position:y", 0.0, 0.32)
	if is_instance_valid(title):
		title.modulate.a = 0.0
		title.scale = Vector2(0.86, 0.86)
		title.pivot_offset = title.size * 0.5
		var title_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		title_tween.tween_property(title, "modulate:a", 1.0, 0.55)
		title_tween.tween_property(title, "scale", Vector2.ONE, 0.55)


func _toggle_drawer(open: bool, animate := true) -> void:
	if not is_instance_valid(drawer) or not drawer.visible:
		return
	drawer_open = open
	if drawer_tween and drawer_tween.is_valid():
		drawer_tween.kill()
	drawer_shadow.visible = open
	drawer_shadow.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	drawer_toggle.text = tr("MENU") + ("\n▼" if open else "\n▲")
	var target_y := 290.0 if open else 544.0
	if not animate:
		drawer.position.y = target_y
		return
	drawer_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	drawer_tween.tween_property(drawer, "position:y", target_y, 0.24 if open else 0.2)


func _refresh_drawer_status() -> void:
	if is_instance_valid(drawer_status):
		drawer_status.text = tr("RANK %d   /   CREDITS %s   /   MITHRIL %s") % [
			GameState.get_rank_id() + 1,
			_format_price(GameState.credits),
			_format_price(GameState.mithril),
		]


func _show_armory(start_mode: String = "store") -> void:
	_close_modal()
	_toggle_drawer(false, false)
	main_page.visible = false
	drawer.visible = false
	drawer_shadow.visible = false
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	equipment_shell = EquipmentShell.new()
	equipment_shell.name = "RecoveredUnityStore"
	equipment_shell.setup(start_mode)
	equipment_shell.closed.connect(_close_modal)
	modal_layer.add_child(equipment_shell)
	store_weapon_row = equipment_shell.item_row
	store_slot_picker = equipment_shell.slot_picker
	store_category_buttons = equipment_shell.category_buttons


# Retained for the original regression suite. The actual visible UI now uses
# Helmet/Body/Arms/Legs/Pack/Gun; these names only filter the Gun carousel when
# an older caller explicitly requests one of the pre-overhaul subsets.
func _select_store_category(category: String) -> void:
	if is_instance_valid(equipment_shell):
		equipment_shell.set_weapon_filter(category)


func _show_level_select(game_mode: String = "singleplayer") -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var heading := tr("SELECT SOLO SECTOR") if game_mode == "singleplayer" else tr("SELECT MULTIPLAYER MAP")
	body.add_child(_label(heading, 25, Color(0.72, 0.94, 1.0)))
	if game_mode == "multiplayer":
		var note := _label(tr("Official servers are retired; multiplayer maps run as local offline skirmishes."), 12, Color(0.55, 0.76, 0.84))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.y = 34
		body.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for level_number in GameState.get_levels_for_mode(game_mode):
		var data: Dictionary = GameState.get_level_data(level_number)
		var button := Button.new()
		var is_locked: bool = game_mode == "singleplayer" and level_number > GameState.unlocked_level
		button.text = (tr("LOCKED • ") if is_locked else "") + "%02d\n%s" % [level_number, tr(str(data.name))]
		button.custom_minimum_size = Vector2(198, 96)
		button.icon = _level_preview(level_number)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 88)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.025, 0.12, 0.17, 0.96), Color(0.12, 0.52, 0.66, 0.8), 4, 6))
		button.add_theme_stylebox_override("hover", _panel_style(Color(0.05, 0.32, 0.4, 0.98), Color(0.35, 0.9, 1.0), 4, 6))
		button.disabled = is_locked
		button.pressed.connect(func():
			AudioDirector.play_ui("accept")
			GameState.start_level(level_number, game_mode)
		)
		grid.add_child(button)
	_show_modal(body, Vector2(880, 570))


func _show_options() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.add_child(_label(tr("OPTIONS"), 25, Color(0.72, 0.94, 1.0)))
	body.add_child(_slider_row(tr("SOUND VOLUME"), "sfx", 0.0, 1.0, 0.05))
	body.add_child(_slider_row(tr("MUSIC VOLUME"), "music", 0.0, 1.0, 0.05))
	body.add_child(_slider_row(tr("LOOK SENSITIVITY"), "look_sensitivity", 0.08, 0.65, 0.01))
	body.add_child(_difficulty_row())
	body.add_child(_quality_row())
	body.add_child(_day_night_row())
	if GameState.is_day_cycle_frozen():
		body.add_child(_fixed_hour_row())
	body.add_child(_language_row())
	var invert := CheckButton.new()
	invert.text = tr("INVERT VERTICAL LOOK")
	invert.button_pressed = bool(GameState.settings.invert_y)
	invert.toggled.connect(func(value): GameState.set_setting("invert_y", value))
	body.add_child(invert)
	if OS.has_feature("mobile"):
		var touch := CheckButton.new()
		touch.text = tr("SHOW MOBILE TOUCH CONTROLS")
		touch.button_pressed = bool(GameState.settings.show_touch_controls)
		touch.toggled.connect(func(value): GameState.set_setting("show_touch_controls", value))
		body.add_child(touch)
	_show_modal(body, Vector2(650, 570))


func _difficulty_row() -> Control:
	var labels := {"recruit": tr("RECRUIT"), "veteran": tr("VETERAN"), "elite": tr("ELITE")}
	var options: Array[String] = []
	for key: String in GameState.DIFFICULTY_ORDER:
		options.append(str(labels.get(key, key)))
	var current := GameState.DIFFICULTY_ORDER.find(str(GameState.settings.difficulty))
	return _option_row(tr("COMBAT DIFFICULTY"), options, maxi(0, current), func(index: int):
		GameState.set_setting("difficulty", GameState.DIFFICULTY_ORDER[index])
	)


func _quality_row() -> Control:
	var labels := {"low": tr("LOW"), "medium": tr("MEDIUM"), "high": tr("HIGH")}
	var options: Array[String] = []
	for key: String in GameState.QUALITY_ORDER:
		options.append(str(labels.get(key, key)))
	var current := GameState.QUALITY_ORDER.find(str(GameState.settings.quality))
	return _option_row(tr("GRAPHICS QUALITY"), options, maxi(0, current), func(index: int):
		GameState.set_setting("quality", GameState.QUALITY_ORDER[index])
	)


func _day_night_row() -> Control:
	var labels := {
		"brisk": tr("30 MIN / DAY"),
		"standard": tr("36 MIN / DAY"),
		"slow": tr("45 MIN / DAY"),
		"frozen": tr("FROZEN TIME"),
	}
	var options: Array[String] = []
	for key: String in GameState.DAY_LENGTH_ORDER:
		options.append(str(labels.get(key, key)))
	var current := GameState.DAY_LENGTH_ORDER.find(str(GameState.settings.day_length))
	return _option_row(tr("DAY-NIGHT CYCLE"), options, maxi(0, current), func(index: int):
		GameState.set_setting("day_length", GameState.DAY_LENGTH_ORDER[index])
		_show_options()
	)


func _fixed_hour_row() -> Control:
	var options: Array[String] = []
	for preset in GameState.FROZEN_HOUR_PRESETS:
		var hour := float(preset)
		options.append("%s  %s" % [WarfareDayNightCycle.format_clock(hour), tr(WarfareDayNightCycle.phase_key(hour))])
	var stored := float(GameState.settings.frozen_hour)
	var current := 0
	for index in range(GameState.FROZEN_HOUR_PRESETS.size()):
		if absf(float(GameState.FROZEN_HOUR_PRESETS[index]) - stored) < 0.05:
			current = index
	return _option_row(tr("FIXED TIME"), options, current, func(index: int):
		GameState.set_setting("frozen_hour", float(GameState.FROZEN_HOUR_PRESETS[index]))
	)


func _language_row() -> Control:
	var codes := Localization.SUPPORTED_LOCALES
	var options: Array[String] = []
	var current := 0
	var active := Localization.resolve_locale(str(GameState.settings.language))
	for i in range(codes.size()):
		options.append(Localization.locale_display_name(codes[i]))
		if codes[i] == active:
			current = i
	return _option_row(tr("LANGUAGE"), options, current, func(index: int):
		GameState.set_setting("language", codes[index])
		AudioDirector.play_ui("accept")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)


func _option_row(label_text: String, options: Array[String], selected_index: int, on_select: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _label(label_text, 14, Color.WHITE)
	label.custom_minimum_size.x = 220
	row.add_child(label)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(300, 36)
	for option_text in options:
		picker.add_item(option_text)
	if not options.is_empty():
		picker.select(clampi(selected_index, 0, options.size() - 1))
	picker.item_selected.connect(func(index: int): on_select.call(index))
	row.add_child(picker)
	return row


func _slider_row(label_text: String, key: String, min_value: float, max_value: float, step: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _label(label_text, 14, Color.WHITE)
	label.custom_minimum_size.x = 220
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(300, 34)
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = float(GameState.settings[key])
	slider.value_changed.connect(func(value): GameState.set_setting(key, value))
	row.add_child(slider)
	return row


func _show_help() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(_label(tr("FIELD MANUAL"), 25, Color(0.72, 0.94, 1.0)))
	body.add_child(_manual_heading(tr("DESKTOP")))
	body.add_child(_wrapped_label(tr("WASD move  •  Mouse aim  •  LMB fire  •  RMB focus  •  R previous weapon  •  Shift dash"), 14, Color.WHITE))
	body.add_child(_wrapped_label(tr("1–4 switch weapon  •  Mouse wheel camera distance  •  Esc pause"), 14, Color.WHITE))
	body.add_child(_manual_heading(tr("CONTROLLER")))
	body.add_child(_wrapped_label(tr("Left stick move  •  Right stick aim  •  RB fire  •  LB focus  •  X previous weapon"), 14, Color.WHITE))
	body.add_child(_manual_heading(tr("MOBILE")))
	body.add_child(_wrapped_label(tr("Left thumbstick move  •  Drag right half to aim  •  FIRE / PREV / DASH buttons"), 14, Color.WHITE))
	body.add_child(_wrapped_label(tr("Solo campaign and retired multiplayer maps now have separate offline entry points."), 12, Color(0.55, 0.72, 0.8)))
	_show_modal(body, Vector2(800, 500))


func _manual_heading(value: String) -> Label:
	return _label(value, 18, Color(1.0, 0.78, 0.24))


func _wrapped_label(value: String, font_size: int, color: Color) -> Label:
	var label := _label(value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 36
	return label


func _show_modal(body: Control, requested_size: Vector2) -> void:
	_close_modal()
	_toggle_drawer(false, false)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.01, 0.025, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(requested_size.x, 920.0), minf(requested_size.y, 600.0))
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.014, 0.06, 0.085, 0.995), Color(0.17, 0.78, 0.94, 0.92), 3, 12))
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var close := Button.new()
	close.text = tr("BACK")
	close.custom_minimum_size.y = 42
	close.pressed.connect(func():
		AudioDirector.play_ui("back")
		_close_modal()
	)
	outer.add_child(close)
	call_deferred("_focus_control", close)


func _close_modal() -> void:
	if not is_instance_valid(modal_layer):
		return
	if is_instance_valid(equipment_shell):
		equipment_shell.queue_free()
	equipment_shell = null
	store_weapon_row = null
	store_slot_picker = null
	store_category_buttons.clear()
	for child in modal_layer.get_children():
		child.queue_free()
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(main_page):
		main_page.visible = true
	if is_instance_valid(drawer):
		drawer.visible = true
		_toggle_drawer(false, false)
	_refresh_drawer_status()


func _deployment_button(title_text: String, subtitle: String) -> Button:
	var button := Button.new()
	button.text = title_text + "\n" + subtitle
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.75, 0.94, 0.98))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _recovered_button_style("button_normal", Color(0.72, 0.96, 1.0)))
	button.add_theme_stylebox_override("hover", _recovered_button_style("button_hover", Color.WHITE))
	button.add_theme_stylebox_override("pressed", _recovered_button_style("button_pressed", Color(0.7, 1.0, 1.0)))
	return button


func _drawer_button(title_text: String, subtitle: String, font_size := 15) -> Button:
	var button := Button.new()
	button.text = title_text + "\n" + subtitle
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(0.74, 0.94, 0.97))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.015, 0.08, 0.1, 0.98), Color(0.12, 0.54, 0.62, 0.85), 3, 8))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.03, 0.24, 0.28, 1.0), CYAN, 3, 8))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.06, 0.34, 0.37, 1.0), Color.WHITE, 3, 8))
	return button


func _component(component_name: String) -> Texture2D:
	var path := COMPONENT_DIR + component_name + ".png"
	return load(path) if ResourceLoader.exists(path) else null


func _recovered_button_style(component_name: String, tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _component(component_name)
	style.modulate_color = tint
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _level_preview(level_number: int) -> AtlasTexture:
	var index := GameState.CAMPAIGN_LEVELS.find(level_number)
	if index < 8:
		var rects := [
			Rect2(0, 0, 332, 180), Rect2(338, 0, 332, 180), Rect2(675, 0, 333, 180),
			Rect2(0, 184, 332, 180), Rect2(338, 184, 332, 180), Rect2(675, 184, 333, 180),
			Rect2(0, 369, 332, 178), Rect2(338, 369, 332, 178),
		]
		return Atlas.region("res://assets/original/ui/pages/15.png", rects[index])
	var late_rects := [
		Rect2(0, 0, 332, 180), Rect2(338, 0, 332, 180), Rect2(675, 0, 333, 180),
		Rect2(0, 184, 332, 180), Rect2(338, 184, 332, 180), Rect2(675, 184, 333, 180),
		Rect2(0, 369, 332, 180), Rect2(338, 369, 332, 180), Rect2(675, 369, 333, 180),
	]
	return Atlas.region("res://assets/original/ui/pages/20.png", late_rects[(index - 8) % late_rects.size()])


func _panel_style(fill: Color, border: Color, radius: int, margins := 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margins
	style.content_margin_right = margins
	style.content_margin_top = margins
	style.content_margin_bottom = margins
	return style


func _flat_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	return style


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _focus_control(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree():
		control.grab_focus()


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _format_price(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result


func _start_music() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = &"Music"
	var path := "res://assets/original/audio/menu/menumusic.wav"
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream is AudioStreamWAV:
			stream = stream.duplicate()
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		music_player.stream = stream
	add_child(music_player)
	if music_player.stream:
		music_player.play()
