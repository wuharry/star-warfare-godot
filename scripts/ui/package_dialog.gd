extends Control

const Atlas = preload("res://scripts/ui/original_atlas.gd")
const ItemBar = preload("res://scripts/ui/battle_items_bar.gd")
var slots: Array[String] = []
var selected_slot := 0
var slot_row: HBoxContainer
var inventory_grid: GridContainer
var notice: Label
var action_row: HBoxContainer
var previous_focus: Control


func _ready() -> void:
	name = "PackageDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	previous_focus = get_viewport().gui_get_focus_owner()
	slots = GameState.get_package_slots()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.01, 0.02, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 30)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = tr("PACKAGE")
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	notice = Label.new()
	notice.text = tr("Select a bag slot, then choose a weapon or supply. Keep at least one weapon.")
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(notice)
	slot_row = HBoxContainer.new()
	box.add_child(slot_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = 6
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inventory_grid)
	action_row = HBoxContainer.new()
	box.add_child(action_row)
	for label: String in ["CLEAR SLOT", "CANCEL", "APPLY"]:
		var button := Button.new()
		button.text = tr(label)
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_row.add_child(button)
		match label:
			"CLEAR SLOT": button.pressed.connect(_place.bind(""))
			"CANCEL": button.pressed.connect(close)
			"APPLY": button.pressed.connect(_apply)
	_rebuild()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		var controls := _focusable_controls()
		if not controls.is_empty():
			var direction := -1 if event.is_action_pressed("ui_focus_prev") else 1
			var current := controls.find(get_viewport().gui_get_focus_owner())
			controls[posmod(current + direction, controls.size())].grab_focus()
		get_viewport().set_input_as_handled()

func close() -> void:
	hide()
	if is_instance_valid(previous_focus):
		previous_focus.grab_focus()
	queue_free()

func _focusable_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for container: Container in [slot_row, inventory_grid, action_row]:
		for button: Button in container.get_children():
			if not button.disabled:
				controls.append(button)
	return controls


func _rebuild() -> void:
	for container: Container in [slot_row, inventory_grid]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	for index in slots.size():
		var button := _item_button(slots[index])
		button.text = str(index + 1)
		button.custom_minimum_size = Vector2(78, 68)
		button.modulate = Color(0.3, 1.0, 1.0) if index == selected_slot else Color.WHITE
		button.pressed.connect(func():
			selected_slot = index
			_rebuild()
		)
		slot_row.add_child(button)
	var available := GameState.owned_weapons.duplicate()
	for key: String in GameState.PROPS:
		if GameState.get_prop_count(key) > 0:
			available.append(key)
	for key: String in available:
		var button := _item_button(key)
		if GameState.PROPS.has(key):
			var remaining := GameState.get_prop_count(key) - slots.count(key)
			button.text = "×%d" % remaining
			button.disabled = remaining <= 0
		else:
			button.disabled = slots.has(key)
		button.pressed.connect(_place.bind(key))
		inventory_grid.add_child(button)
	var controls := _focusable_controls()
	for index in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index - 1, controls.size())])
		control.focus_neighbor_left = control.focus_previous
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_right = control.focus_next
		control.focus_neighbor_bottom = control.focus_next
	slot_row.get_child(selected_slot).grab_focus()


func _item_button(key: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(116, 76)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 64)
	if GameState.WEAPONS.has(key):
		button.icon = Atlas.weapon_icon(int(GameState.WEAPONS[key].id))
		button.tooltip_text = str(GameState.WEAPONS[key].name)
	elif GameState.PROPS.has(key):
		button.icon = ItemBar.item_icon(GameState.PROPS[key])
		button.tooltip_text = "%s\n%s" % [tr(str(GameState.PROPS[key].name)), tr(str(GameState.PROPS[key].description))]
	return button


func _place(key: String) -> void:
	if GameState.PROPS.has(key) and slots.count(key) >= GameState.get_prop_count(key):
		return
	if GameState.WEAPONS.has(key) and slots.has(key):
		return
	slots[selected_slot] = key
	_rebuild()


func _apply() -> void:
	if GameState.set_package(slots, GameState.get_package_storage()):
		AudioDirector.play_ui("accept")
		close()
	else:
		notice.text = tr("Keep at least one weapon and use only owned supplies. Changes could not be saved.")
