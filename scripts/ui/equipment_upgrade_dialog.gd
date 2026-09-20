extends Control
## A fixed quote is confirmed once. Changing the catalog behind it cannot retarget it.

signal confirmed(item_key: String, expected_level: int)
signal dismissed
const Art = preload("res://scripts/ui/recovered_armory_skin.gd")

var panel: PanelContainer
var heading: Label
var details: Label
var cost_label: Label
var status_label: Label
var confirm_button: Button
var cancel_button: Button
var quote: Dictionary = {}
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
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	heading = _label(column, 23, Color.WHITE)
	details = _label(column, 18, Color(0.70, 0.92, 0.96))
	cost_label = _label(column, 20, Color(1.0, 0.78, 0.3))
	status_label = _label(column, 15, Color(0.95, 0.71, 0.35))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	column.add_child(actions)
	cancel_button = _button(actions, tr("CANCEL"))
	confirm_button = _button(actions, tr("CONFIRM UPGRADE"))
	cancel_button.pressed.connect(close)
	confirm_button.pressed.connect(_confirm)
	resized.connect(_layout)
	hide()


func show_quote(value: Dictionary, item_name: String, whole_suit: bool) -> void:
	quote = value.duplicate(true)
	_previous_focus = get_viewport().gui_get_focus_owner()
	heading.text = "%s · %s" % [tr("UPGRADE"), item_name]
	var lines: Array[String] = ["LV %d → %d" % [int(quote.level), int(quote.next_level)]]
	for key: String in quote.current:
		lines.append("%s  %s → %s  (+%s)" % [key, _value(quote.current[key]), _value(quote.next[key]), _value(float(quote.next[key]) - float(quote.current[key]))])
	if whole_suit:
		lines.append(tr("Full suit values. All four pieces share this upgrade."))
	details.text = "\n".join(lines)
	cost_label.text = tr("COST: %s") % price_text(quote)
	status_label.text = result_text(str(quote.status))
	confirm_button.disabled = str(quote.status) != "ready"
	# Keep keyboard navigation inside the confirmation, including unaffordable quotes.
	cancel_button.focus_next = cancel_button.get_path() if confirm_button.disabled else confirm_button.get_path()
	cancel_button.focus_previous = cancel_button.focus_next
	confirm_button.focus_next = cancel_button.get_path()
	confirm_button.focus_previous = cancel_button.get_path()
	show()
	_layout()
	call_deferred("_layout")
	(cancel_button if confirm_button.disabled else confirm_button).grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	dismissed.emit()


func _confirm() -> void:
	if not visible or confirm_button.disabled:
		return
	confirm_button.disabled = true
	close()
	confirmed.emit(str(quote.item_key), int(quote.level))


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	if panel == null:
		return
	panel.size = Vector2(minf(540, size.x - 40), maxf(360, panel.get_combined_minimum_size().y))
	panel.position = (size - panel.size) * 0.5


static func price_text(value: Dictionary) -> String:
	var parts: Array[String] = []
	if int(value.credits) > 0:
		parts.append("$%s" % _group_digits(int(value.credits)))
	if int(value.mithril) > 0:
		parts.append("#%s" % _group_digits(int(value.mithril)))
	return " + ".join(parts) if not parts.is_empty() else "$0"


func result_text(result: String) -> String:
	match result:
		"ready": return ""
		"upgraded": return tr("UPGRADE COMPLETE")
		"max_level": return tr("MAX LEVEL")
		"not_enough_credits": return tr("Not enough credits.")
		"not_enough_mithril": return tr("Not enough mithril.")
		"save_failed": return tr("Could not save. Upgrade and payment were canceled.")
		"stale": return tr("Equipment level changed. Please open the upgrade again.")
		_: return tr("This equipment cannot be upgraded.")


static func _group_digits(value: int) -> String:
	var text := str(value)
	var index := text.length() - 3
	while index > 0:
		text = text.insert(index, ",")
		index -= 3
	return text


static func _value(value: float) -> String:
	return String.num(value, 2)


func _label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, Art.plate(state))
	button.add_theme_stylebox_override("focus", Art.focus())
	parent.add_child(button)
	return button
