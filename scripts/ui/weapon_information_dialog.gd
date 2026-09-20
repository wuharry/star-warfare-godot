extends Control
## Read-only weapon and manufacturer stories, shared by desktop and mobile.
signal dismissed
const Catalog = preload("res://scripts/core/manufacturer_catalog.gd")
const Art = preload("res://scripts/ui/recovered_armory_skin.gd")

var panel: PanelContainer
var heading: Label
var manufacturer_label: Label
var english_name: Label
var scroll: ScrollContainer
var body: RichTextLabel
var close_button: Button
var weapon_id := ""
var _previous_focus: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	theme = Art.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Art.panel())
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	heading = _label(column, 26, Color.WHITE)
	manufacturer_label = _label(column, 20, Color(0.45, 0.88, 0.96))
	english_name = _label(column, 14, Color(0.66, 0.76, 0.79))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_ALL
	column.add_child(scroll)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 17)
	body.add_theme_color_override("default_color", Color(0.83, 0.90, 0.92))
	body.add_theme_constant_override("line_separation", 5)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(body)
	close_button = Button.new()
	close_button.text = tr("BACK")
	close_button.custom_minimum_size.y = 44
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		close_button.add_theme_stylebox_override(state, Art.plate(state))
	close_button.add_theme_stylebox_override("focus", Art.focus())
	close_button.pressed.connect(close)
	column.add_child(close_button)
	close_button.focus_next = scroll.get_path()
	close_button.focus_previous = scroll.get_path()
	scroll.focus_next = close_button.get_path()
	scroll.focus_previous = close_button.get_path()
	resized.connect(_layout)
	hide()

func show_weapon(id: String, display_name: String) -> void:
	var manufacturer := Catalog.get_manufacturer_for_weapon(id)
	if manufacturer.is_empty():
		return
	weapon_id = id
	close_button.text = tr("BACK")
	_previous_focus = get_viewport().gui_get_focus_owner()
	heading.text = display_name
	manufacturer_label.text = "%s · %s" % [manufacturer.code, Catalog.localized(manufacturer, "name")]
	english_name.text = str(manufacturer.name_en)
	english_name.visible = TranslationServer.get_locale().begins_with("zh")
	body.text = "[color=#73d5e7]%s[/color]\n%s\n\n[color=#73d5e7]%s[/color]\n%s" % [
		tr("WEAPON BACKGROUND"), Catalog.weapon_description(id),
		tr("MANUFACTURER BACKGROUND"), Catalog.localized(manufacturer, "story")]
	scroll.scroll_vertical = 0
	show()
	_layout()
	call_deferred("_layout")
	close_button.grab_focus()

func close() -> void:
	if not visible:
		return
	hide()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	dismissed.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		if get_viewport().gui_get_focus_owner() == close_button:
			scroll.grab_focus()
		else:
			close_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		scroll.scroll_vertical += -40 if event.is_action_pressed("ui_up") else 40
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		# Directional focus must not jump to the shop controls behind this modal.
		get_viewport().set_input_as_handled()

func _layout() -> void:
	if panel == null:
		return
	panel.size = Vector2(minf(650, size.x - 40), minf(500, size.y - 48))
	panel.position = (size - panel.size) * 0.5

func _label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
