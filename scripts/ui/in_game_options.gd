class_name WarfareInGameOptions
extends Control

signal closed

const ArmorySkin = preload("res://scripts/ui/recovered_armory_skin.gd")
const PAGE_KEYS := ["Graphics", "Audio", "Controls", "Language"]

var quality_picker: OptionButton
var language_picker: OptionButton
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _first_controls: Dictionary = {}
var _translated_controls: Dictionary = {}
var _sliders: Dictionary = {}
var _readouts: Dictionary = {}
var _toggles: Dictionary = {}
var _active_page := "Graphics"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ArmorySkin.make_theme(true)
	_build_ui()
	_translate_ui()
	sync_settings()
	_select_page("Graphics", false)
	GameState.settings_changed.connect(sync_settings)


func _exit_tree() -> void:
	if GameState.settings_changed.is_connected(sync_settings):
		GameState.settings_changed.disconnect(sync_settings)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_translate_ui()


func focus_default() -> void:
	var control := _first_controls.get(_active_page) as Control
	if is_instance_valid(control) and control.is_visible_in_tree():
		control.grab_focus()


func sync_settings() -> void:
	if not is_instance_valid(quality_picker):
		return
	quality_picker.select(maxi(0, GameState.QUALITY_ORDER.find(str(GameState.settings.quality))))
	var locale := Localization.resolve_locale(str(GameState.settings.language))
	language_picker.select(maxi(0, Localization.SUPPORTED_LOCALES.find(locale)))
	for key: String in _sliders:
		var slider := _sliders[key] as HSlider
		slider.set_value_no_signal(float(GameState.settings[key]))
		_update_readout(key, slider.value)
	for key: String in _toggles:
		(_toggles[key] as CheckButton).set_pressed_no_signal(bool(GameState.settings[key]))


## Return true when Escape only needs to close an open dropdown.
func close_popups() -> bool:
	for picker: OptionButton in [quality_picker, language_picker]:
		if is_instance_valid(picker) and picker.get_popup().visible:
			picker.get_popup().hide()
			picker.grab_focus()
			return true
	return false


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.025, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "InGameOptionsPanel"
	panel.custom_minimum_size = Vector2(650, 470)
	panel.add_theme_stylebox_override("panel", ArmorySkin.panel())
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	var title := _label("Options", 30, Color(0.72, 0.94, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var hint := _label("Changes apply immediately.", 14, Color(0.62, 0.74, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)
	var tab_row := HBoxContainer.new()
	tab_row.name = "OptionsTabs"
	tab_row.add_theme_constant_override("separation", 8)
	body.add_child(tab_row)
	var tab_group := ButtonGroup.new()
	for key: String in PAGE_KEYS:
		var button := _button(key)
		button.name = key + "TabButton"
		button.toggle_mode = true
		button.button_group = tab_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_color_override("font_pressed_color", ArmorySkin.CYAN)
		button.add_theme_color_override("font_hover_pressed_color", ArmorySkin.CYAN)
		button.pressed.connect(_select_page.bind(key))
		tab_row.add_child(button)
		_tabs[key] = button
	var pages := VBoxContainer.new()
	pages.name = "OptionsPages"
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.custom_minimum_size.y = 205
	body.add_child(pages)
	for key: String in PAGE_KEYS:
		var page := VBoxContainer.new()
		page.name = key + "OptionsPage"
		page.add_theme_constant_override("separation", 14)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		_pages[key] = page
	_build_graphics_page(_pages.Graphics)
	_build_audio_page(_pages.Audio)
	_build_controls_page(_pages.Controls)
	_build_language_page(_pages.Language)
	var back := _button("BACK")
	back.name = "ReturnToPauseButton"
	back.pressed.connect(func():
		close_popups()
		closed.emit()
	)
	body.add_child(back)


func _build_graphics_page(page: VBoxContainer) -> void:
	quality_picker = OptionButton.new()
	quality_picker.name = "GraphicsQualityPicker"
	for key: String in GameState.QUALITY_ORDER:
		quality_picker.add_item(tr(key.to_upper()))
	quality_picker.item_selected.connect(func(index: int):
		GameState.set_setting("quality", GameState.QUALITY_ORDER[index])
	)
	page.add_child(_picker_row("GRAPHICS QUALITY", quality_picker))
	page.add_child(_description("Adjust image quality without leaving the room."))
	_first_controls.Graphics = quality_picker


func _build_audio_page(page: VBoxContainer) -> void:
	var music := _slider_row("MUSIC VOLUME", "music", "MusicVolumeSlider", 0.0, 1.0)
	page.add_child(music)
	page.add_child(_slider_row("SOUND VOLUME", "sfx", "SoundVolumeSlider", 0.0, 1.0))
	page.add_child(_description("Music and sound effect volume are saved immediately."))
	_first_controls.Audio = _sliders.music


func _build_controls_page(page: VBoxContainer) -> void:
	page.add_child(_slider_row("LOOK SENSITIVITY", "look_sensitivity", "LookSensitivitySlider", 0.08, 0.65))
	page.add_child(_toggle("INVERT VERTICAL LOOK", "invert_y", "InvertLookButton"))
	if OS.has_feature("mobile") or bool(ProjectSettings.get_setting("debug/restoration/force_mobile_ui", false)):
		page.add_child(_toggle("SHOW MOBILE TOUCH CONTROLS", "show_touch_controls", "ShowTouchControlsButton"))
	page.add_child(_description("Adjust aiming and touch controls."))
	_first_controls.Controls = _sliders.look_sensitivity


func _build_language_page(page: VBoxContainer) -> void:
	language_picker = OptionButton.new()
	language_picker.name = "LanguagePicker"
	for locale: String in Localization.SUPPORTED_LOCALES:
		language_picker.add_item(Localization.locale_display_name(locale))
	language_picker.item_selected.connect(func(index: int):
		GameState.set_setting("language", Localization.SUPPORTED_LOCALES[index])
	)
	page.add_child(_picker_row("LANGUAGE", language_picker))
	page.add_child(_description("Change the display language without leaving the room."))
	_first_controls.Language = language_picker


func _select_page(key: String, focus_control := true) -> void:
	close_popups()
	_active_page = key
	for page_key: String in _pages:
		(_pages[page_key] as Control).visible = page_key == key
		(_tabs[page_key] as Button).set_pressed_no_signal(page_key == key)
	if focus_control:
		focus_default()


func _picker_row(source_key: String, picker: OptionButton) -> HBoxContainer:
	var row := _setting_row(source_key)
	picker.custom_minimum_size = Vector2(240, 45)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ArmorySkin.style_picker(picker, theme)
	row.add_child(picker)
	return row


func _slider_row(source_key: String, key: String, node_name: String, minimum: float, maximum: float) -> HBoxContainer:
	var row := _setting_row(source_key)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(180, 45)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.value_changed.connect(func(value: float):
		_update_readout(key, value)
		GameState.set_setting(key, value)
	)
	row.add_child(slider)
	_sliders[key] = slider
	var value_label := Label.new()
	value_label.name = node_name + "Value"
	value_label.custom_minimum_size.x = 64
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", ArmorySkin.CYAN)
	row.add_child(value_label)
	_readouts[key] = value_label
	return row


func _toggle(source_key: String, key: String, node_name: String) -> CheckButton:
	var button := CheckButton.new()
	button.name = node_name
	button.custom_minimum_size.y = 45
	button.add_theme_font_size_override("font_size", 14)
	ArmorySkin.style_button(button)
	_track_translation(button, source_key)
	button.toggled.connect(func(value: bool): GameState.set_setting(key, value))
	_toggles[key] = button
	return button


func _setting_row(source_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _label(source_key, 14, Color.WHITE)
	label.custom_minimum_size.x = 196
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


func _description(source_key: String) -> Label:
	var label := _label(source_key, 14, Color(0.62, 0.74, 0.8))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _label(source_key: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_track_translation(label, source_key)
	return label


func _button(source_key: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 45
	button.add_theme_font_size_override("font_size", 16)
	ArmorySkin.style_button(button)
	_track_translation(button, source_key)
	return button


func _track_translation(control: Control, source_key: String) -> void:
	control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	control.set_meta("translation_key", source_key)
	_translated_controls[control] = source_key
	control.set("text", tr(source_key))


func _translate_ui() -> void:
	for control: Control in _translated_controls:
		control.set("text", tr(str(_translated_controls[control])))
	for index in GameState.QUALITY_ORDER.size():
		quality_picker.set_item_text(index, tr(str(GameState.QUALITY_ORDER[index]).to_upper()))
	for index in Localization.SUPPORTED_LOCALES.size():
		language_picker.set_item_text(index, Localization.locale_display_name(Localization.SUPPORTED_LOCALES[index]))


func _update_readout(key: String, value: float) -> void:
	var label := _readouts.get(key) as Label
	if is_instance_valid(label):
		label.text = "%.2f" % value if key == "look_sensitivity" else "%d%%" % roundi(value * 100.0)
