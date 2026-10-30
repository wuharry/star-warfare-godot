class_name WarfareBattleItemsBar
extends VBoxContainer

const SLOT_KEYS := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_COMMA]
var controller: WarfareBattleItems
var grid: GridContainer
var buffs: HBoxContainer
var buttons: Dictionary = {}
var selected_slot := -1
var buff_signature := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid = GridContainer.new()
	grid.columns = 4
	add_child(grid)
	buffs = HBoxContainer.new()
	add_child(buffs)
	controller.changed.connect(rebuild)
	rebuild()


static func item_icon(item: Dictionary) -> Texture2D:
	return load("res://assets/ui/components/props_item_%02d.png" % int(item.index))


func rebuild() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	buttons.clear()
	for entry: Dictionary in controller.get_slots():
		var slot := int(entry.slot)
		var button := Button.new()
		button.name = "ItemSlot%d" % slot
		button.custom_minimum_size = Vector2(52, 54)
		button.icon = item_icon(entry.item)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
		button.text = OS.get_keycode_string(SLOT_KEYS[slot])
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = "%s\n%s" % [tr(str(entry.item.name)), tr(str(entry.item.description))]
		button.pressed.connect(use_slot.bind(slot))
		grid.add_child(button)
		buttons[slot] = button
	if not buttons.has(selected_slot):
		selected_slot = int(buttons.keys()[0]) if not buttons.is_empty() else -1
	buff_signature = ""


func use_slot(slot: int) -> void:
	if controller.use_slot(slot):
		AudioDirector.play_ui("accept")


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or not controller.enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := SLOT_KEYS.find(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
		if slot >= 0 and buttons.has(slot):
			use_slot(slot)
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and not buttons.is_empty():
		var slots := buttons.keys()
		if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
			selected_slot = int(slots[posmod(slots.find(selected_slot) + (1 if event.button_index == JOY_BUTTON_DPAD_DOWN else -1), slots.size())])
			get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_A:
			use_slot(selected_slot)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	for slot: int in buttons:
		var button: Button = buttons[slot]
		button.disabled = not controller.can_use(slot) or get_tree().paused
		button.modulate = Color(0.5, 1.0, 1.0) if slot == selected_slot else Color.WHITE
	var signature := str(controller.active_effects.keys())
	if signature != buff_signature:
		buff_signature = signature
		for child in buffs.get_children():
			buffs.remove_child(child)
			child.queue_free()
		for key: String in controller.active_effects:
			var indicator := Button.new()
			indicator.name = key
			indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			indicator.focus_mode = Control.FOCUS_NONE
			indicator.icon = item_icon(controller.inventory.PROPS[key])
			indicator.expand_icon = true
			indicator.add_theme_constant_override("icon_max_width", 24)
			indicator.custom_minimum_size = Vector2(62, 32)
			buffs.add_child(indicator)
	for indicator: Button in buffs.get_children():
		indicator.text = "%ds" % ceili(float(controller.active_effects[str(indicator.name)].remaining))
