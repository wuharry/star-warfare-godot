extends Control

const Atlas = preload("res://scripts/ui/original_atlas.gd")
const EquipmentShell = preload("res://scripts/ui/unity_equipment_shell.gd")
const COMPONENT_DIR := "res://assets/ui/components/"
const DESIGN_SIZE := Vector2(960.0, 640.0)

# Level select thumbnails, recovered from the shipped UI resource rather than
# guessed. The campaign set comes from StageChoiseUI, which builds icon i from
# vUI[3] frame 8 module i where stage i loads Level i+1; the PvP set comes from
# CreateRoomUI, which builds the versus maps from vUI[5] frame 6 and whose index
# n loads Level 13+n. Neither is in level order, and the two live on different
# UI units, which is why no single grid could ever have produced them.
# Regenerate with:
#   python tools/ui_extractor/extract_stage_icons.py --assets-root <Assets> --mode solo
#   python tools/ui_extractor/extract_stage_icons.py --assets-root <Assets> --mode vs
# Values are 1x atlas coordinates; OriginalAtlas.region converts to the 2x pages.
const CAMPAIGN_STAGE_ICONS := {
	1: [15, Rect2(337, 182, 336, 181)],
	2: [15, Rect2(0, 364, 336, 181)],
	3: [15, Rect2(674, 0, 336, 181)],
	4: [15, Rect2(0, 182, 336, 181)],
	5: [15, Rect2(337, 364, 336, 181)],
	6: [15, Rect2(674, 182, 336, 181)],
	7: [15, Rect2(0, 0, 336, 181)],
	8: [20, Rect2(676, 0, 336, 180)],
	13: [14, Rect2(674, 182, 336, 181)],
	14: [14, Rect2(337, 364, 336, 181)],
	15: [14, Rect2(337, 182, 336, 181)],
	16: [14, Rect2(0, 364, 336, 181)],
	17: [14, Rect2(674, 364, 336, 181)],
	18: [15, Rect2(674, 364, 336, 181)],
	19: [20, Rect2(0, 0, 336, 181)],
	20: [20, Rect2(338, 0, 336, 180)],
	21: [20, Rect2(2, 388, 336, 180)],
}
const CYAN := Color(0.4, 1.0, 1.0)

var design_root: Control
var main_page: Control
var modal_layer: Control
var drawer: Control
var drawer_shadow: Button
var drawer_toggle: TextureButton
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
	# Fill wide-screen margins with the recovered Unity artwork instead of a
	# generated solid colour. The 960x640 interaction canvas remains unchanged.
	var backdrop := TextureRect.new()
	backdrop.name = "RecoveredMainBackdrop"
	backdrop.texture = _component("menu_hero")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)


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

	var strip := Control.new()
	strip.name = "DeploymentStrip"
	_set_rect(strip, Rect2(0, 490, 960, 150))
	main_page.add_child(strip)

	var strip_art := _texture_rect("main_bottom_panel")
	strip_art.name = "RecoveredBottomPanel"
	_set_rect(strip_art, Rect2(0, 0, 960, 150))
	strip.add_child(strip_art)

	var solo := _deployment_button("main_single_normal", "main_single_pressed")
	solo.name = "SoloButton"
	solo.tooltip_text = tr("SINGLE PLAYER • CAMPAIGN SECTORS 01-08")
	_set_rect(solo, Rect2(90, 35, 348, 87))
	solo.pressed.connect(func():
		AudioDirector.play_ui("accept")
		_show_level_select("singleplayer")
	)
	strip.add_child(solo)

	var coop := _deployment_button("main_online_normal", "main_online_pressed")
	coop.name = "MultiplayerButton"
	coop.tooltip_text = tr("ONLINE • ORIGINAL PVP ARENAS 13-21")
	_set_rect(coop, Rect2(521, 35, 348, 87))
	coop.pressed.connect(func():
		AudioDirector.play_ui("accept")
		_show_level_select("multiplayer")
	)
	strip.add_child(coop)

	var logo_texture := _component("main_title")
	if logo_texture:
		var logo := TextureRect.new()
		logo.name = "RecoveredTitle"
		logo.texture = logo_texture
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_SCALE
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(logo, Rect2(482, 18, 417, 177))
		main_page.add_child(logo)
	else:
		var fallback_title := _label("STAR WARFARE", 56, Color(0.93, 0.99, 1.0))
		fallback_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_rect(fallback_title, Rect2(460, 45, 450, 80))
		main_page.add_child(fallback_title)

	var version := _label("VER 2.97", 11, Color.WHITE)
	_set_rect(version, Rect2(10, 615, 100, 18))
	main_page.add_child(version)

	call_deferred("_focus_control", solo)


func _build_navigation_drawer() -> void:
	drawer_shadow = Button.new()
	drawer_shadow.name = "DrawerShadow"
	drawer_shadow.text = ""
	drawer_shadow.focus_mode = Control.FOCUS_NONE
	var shadow_style := _recovered_button_style("main_nav_shadow", Color.WHITE)
	drawer_shadow.add_theme_stylebox_override("normal", shadow_style)
	drawer_shadow.add_theme_stylebox_override("hover", shadow_style)
	drawer_shadow.add_theme_stylebox_override("pressed", shadow_style)
	_set_rect(drawer_shadow, Rect2(Vector2.ZERO, DESIGN_SIZE))
	drawer_shadow.z_index = 5
	drawer_shadow.visible = false
	drawer_shadow.pressed.connect(func(): _toggle_drawer(false))
	design_root.add_child(drawer_shadow)

	drawer = Control.new()
	drawer.name = "NavigationDrawer"
	_set_rect(drawer, Rect2(0, -257, 960, 350))
	drawer.z_index = 6
	design_root.add_child(drawer)

	var panel_art := _texture_rect("main_nav_panel")
	panel_art.name = "RecoveredNavigationPanel"
	_set_rect(panel_art, Rect2(0, 0, 960, 272))
	drawer.add_child(panel_art)

	drawer_status = _label("", 19, CYAN)
	drawer_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(drawer_status, Rect2(31, 132, 440, 34))
	drawer.add_child(drawer_status)
	_refresh_drawer_status()

	drawer_toggle = TextureButton.new()
	drawer_toggle.name = "DrawerToggle"
	drawer_toggle.texture_normal = _component("main_nav_toggle")
	drawer_toggle.texture_hover = _component("main_nav_toggle")
	drawer_toggle.texture_pressed = _component("main_nav_toggle")
	drawer_toggle.ignore_texture_size = true
	drawer_toggle.stretch_mode = TextureButton.STRETCH_SCALE
	drawer_toggle.tooltip_text = tr("OPEN / CLOSE MENU")
	_set_rect(drawer_toggle, Rect2(840, 240, 120, 110))
	drawer_toggle.pressed.connect(func(): _toggle_drawer(not drawer_open))
	drawer.add_child(drawer_toggle)

	var rank_icon := _texture_rect("main_rank_%02d" % clampi(GameState.get_rank_id(), 0, 11))
	rank_icon.name = "RankIcon"
	# NavigationMenuUI places the 64px rank module at (880,575) and the
	# 120x110 pull tab at (840,544) in Unity's bottom-left coordinates.  After
	# converting to Godot's top-left origin the authored local offset is
	# (40,15), not the geometric centre of the asymmetric tab artwork.
	_set_rect(rank_icon, Rect2(40, 15, 64, 64))
	drawer_toggle.add_child(rank_icon)

	var bank := TextureButton.new()
	bank.name = "BankButton"
	bank.texture_normal = _component("main_nav_bank")
	bank.texture_hover = _component("main_nav_bank")
	bank.texture_pressed = _component("main_nav_bank")
	bank.ignore_texture_size = true
	bank.stretch_mode = TextureButton.STRETCH_SCALE
	bank.tooltip_text = tr("BANK")
	_set_rect(bank, Rect2(520, 17, 410, 100))
	bank.pressed.connect(_show_bank_notice)
	drawer.add_child(bank)

	var customize := _drawer_button(tr("CUSTOMIZE"), "main_nav_customize_icon", "main_nav_customize_icon_pressed")
	customize.name = "CustomizeButton"
	_set_rect(customize, Rect2(520, 127, 190, 100))
	customize.pressed.connect(func(): _show_armory("customize"))
	drawer.add_child(customize)
	var store := _drawer_button(tr("STORE"), "main_nav_store_icon", "main_nav_store_icon_pressed")
	store.name = "StoreButton"
	_set_rect(store, Rect2(740, 127, 190, 100))
	store.pressed.connect(func(): _show_armory("store"))
	drawer.add_child(store)

	var options := _drawer_button(tr("OPTIONS"), "main_nav_options_icon", "main_nav_options_icon_pressed")
	options.name = "OptionsButton"
	_set_rect(options, Rect2(29, 17, 190, 100))
	options.pressed.connect(_show_options)
	drawer.add_child(options)

	var edit_name := TextureButton.new()
	edit_name.name = "EditNameButton"
	edit_name.texture_normal = _component("main_nav_edit_normal")
	edit_name.texture_hover = _component("main_nav_edit_pressed")
	edit_name.texture_pressed = _component("main_nav_edit_pressed")
	edit_name.ignore_texture_size = true
	edit_name.stretch_mode = TextureButton.STRETCH_SCALE
	_set_rect(edit_name, Rect2(47, 174, 151, 57))
	edit_name.pressed.connect(_show_name_editor)
	drawer.add_child(edit_name)
	var edit_label := _label(tr("EDIT NAME"), 18, Color(0.78, 1.0, 1.0))
	edit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(edit_label, Rect2(0, 0, 151, 57))
	edit_name.add_child(edit_label)


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
		strip.position.y = 640.0
		var strip_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		strip_tween.tween_property(strip, "position:y", 490.0, 0.32)
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
	var target_y := 0.0 if open else -257.0
	if not animate:
		drawer.position.y = target_y
		return
	drawer_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	drawer_tween.tween_property(drawer, "position:y", target_y, 0.24 if open else 0.2)


func _refresh_drawer_status() -> void:
	if is_instance_valid(drawer_status):
		drawer_status.text = tr("NICKNAME: %s") % str(GameState.settings.get("nickname", "PLAYER"))


func _show_name_editor() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.add_child(_label(tr("EDIT NAME"), 25, Color(0.72, 0.94, 1.0)))
	var rule := _label(tr("LETTERS AND NUMBERS ONLY, 1-15 CHARACTERS"), 14, Color(0.62, 0.78, 0.78))
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(rule)
	var input := LineEdit.new()
	input.name = "NicknameInput"
	input.text = str(GameState.settings.get("nickname", "PLAYER"))
	input.max_length = 15
	input.placeholder_text = tr("PLAYER NAME")
	input.custom_minimum_size = Vector2(480, 52)
	body.add_child(input)
	var validation := _label("", 13, Color(1.0, 0.45, 0.35))
	validation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	validation.custom_minimum_size.y = 24
	body.add_child(validation)
	var confirm := Button.new()
	confirm.text = tr("CONFIRM")
	confirm.custom_minimum_size.y = 46
	body.add_child(confirm)
	var submit := func() -> void:
		var candidate := input.text.strip_edges()
		var matcher := RegEx.new()
		matcher.compile("^[A-Za-z0-9]{1,15}$")
		if matcher.search(candidate) == null:
			validation.text = tr("USE 1-15 LETTERS OR NUMBERS")
			return
		GameState.set_setting("nickname", candidate)
		AudioDirector.play_ui("accept")
		_close_modal()
	confirm.pressed.connect(submit)
	input.text_submitted.connect(func(_value: String): submit.call())
	_show_modal(body, Vector2(620, 350))
	call_deferred("_focus_control", input)


func _show_bank_notice() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.add_child(_label(tr("BANK"), 25, Color(1.0, 0.88, 0.42)))
	body.add_child(_wrapped_label(tr("The original in-app purchase service is no longer online. Credits and Mithril earned in the restored offline game remain available in the Store."), 14, Color.WHITE))
	_show_modal(body, Vector2(650, 310))


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
	var heading := tr("SELECT SOLO SECTOR") if game_mode == "singleplayer" else tr("SELECT PVP ARENA")
	body.add_child(_label(heading, 25, Color(0.72, 0.94, 1.0)))
	if game_mode == "multiplayer":
		var note := _label(tr("Levels 13-21 are the original PvP arenas. Offline arena preview only; no PvE waves are used."), 12, Color(0.55, 0.76, 0.84))
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
		var is_locked: bool = not GameState.is_level_unlocked(level_number, game_mode)
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
	body.add_child(_wrapped_label(tr("1–4 direct weapon select  •  Mouse wheel switch weapon  •  Esc pause"), 14, Color.WHITE))
	body.add_child(_manual_heading(tr("CONTROLLER")))
	body.add_child(_wrapped_label(tr("Left stick move  •  Right stick aim  •  RB fire  •  LB focus  •  X previous weapon"), 14, Color.WHITE))
	body.add_child(_manual_heading(tr("MOBILE")))
	body.add_child(_wrapped_label(tr("Left thumbstick move  •  Drag right half to aim  •  FIRE / PREV / DASH buttons"), 14, Color.WHITE))
	body.add_child(_wrapped_label(tr("Solo campaign and the original PvP arenas now have separate offline entry points."), 12, Color(0.55, 0.72, 0.8)))
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


func _deployment_button(normal_component: String, pressed_component: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = _component(normal_component)
	button.texture_hover = _component(normal_component)
	button.texture_pressed = _component(pressed_component)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.focus_mode = Control.FOCUS_ALL
	return button


func _drawer_button(title_text: String, icon_component: String, pressed_icon_component: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = _component("main_nav_button_normal")
	button.texture_hover = _component("main_nav_button_normal")
	button.texture_pressed = _component("main_nav_button_pressed")
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	var icon := _texture_rect(icon_component)
	icon.name = "Icon"
	var icon_size := icon.texture.get_size() * 0.5 if icon.texture else Vector2(52, 60)
	_set_rect(icon, Rect2(Vector2((190.0 - icon_size.x) * 0.5, maxf(3.0, (68.0 - icon_size.y) * 0.5)), icon_size))
	# Keep the original pressed icon available to input/controller users too.
	button.button_down.connect(func(): icon.texture = _component(pressed_icon_component))
	button.button_up.connect(func(): icon.texture = _component(icon_component))
	button.mouse_exited.connect(func():
		if not button.button_pressed:
			icon.texture = _component(icon_component)
	)
	button.add_child(icon)
	var label := _label(title_text, 18, CYAN)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(label, Rect2(0, 69, 190, 27))
	button.add_child(label)
	return button


func _texture_rect(component_name: String) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.texture = _component(component_name)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


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
	# The tables are not in level order and span three atlas pages: Level 7 is
	# the top-left cell of page 15, Level 1 is in the middle row, Level 8 is on
	# page 20, and the PvP maps are mostly on page 14. Slicing a page into a
	# grid and handing the cells out in order is what put the wrong picture on
	# almost every card.
	if not CAMPAIGN_STAGE_ICONS.has(level_number):
		return null
	var record: Array = CAMPAIGN_STAGE_ICONS[level_number]
	return Atlas.region("res://assets/original/ui/pages/%d.png" % int(record[0]), record[1])


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
