extends Control
## MakePackageUI / UISliderStorage: horizontal page swipe, vertical item drag.
## Counts are reservations in the owned inventory, never purchases or deletions.

const Layout = preload("res://scripts/ui/sw1_store_layout.gd")
const Scroller = preload("res://scripts/ui/sw1_store_scroller.gd")

var shell: Control
var scroller: Control
var slots: Array[String] = []
var storage: Array[String] = []
var pages: Array[Control] = []
var bag_cells: Array[Control] = []
var dots: Control
var title: Label
var stats: RichTextLabel
var description: RichTextLabel
var notice: Label
var cursor: TextureRect
var selection: TextureRect
var enabled := true
var finger := -1
var _origin := Vector2.ZERO
var _source := Vector2i(-1, -1) # x = bag (0) / storage (1); y = cell.
var _gesture := 0 # undecided / horizontal page swipe / item drag
var _selected := Vector2i(-1, -1)


func _ready() -> void:
	name = "SW1Package"
	z_index = 10
	size = Vector2(960, 640)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell._art(self, "armory_background", Rect2(0, 0, 960, 640))
	var background: TextureRect = shell._module_art(self, 12, 21)
	shell._set_rect(background, Layout.rect(12, 3))
	for index in range(22, 34):
		shell._module_art(self, 12, index)
	title = shell._label("", 19, shell.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell._set_rect(title, Layout.rect(12, 38))
	add_child(title)
	stats = RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.scroll_active = false
	stats.add_theme_font_size_override("normal_font_size", 15)
	shell._set_rect(stats, Rect2(732, 161, 198, 88))
	add_child(stats)
	description = RichTextLabel.new()
	description.scroll_active = true
	description.add_theme_font_size_override("normal_font_size", 15)
	description.add_theme_color_override("default_color", shell.DESCRIPTION)
	shell._set_rect(description, Layout.rect(12, 37))
	add_child(description)
	notice = shell._label("", 15, shell.CYAN)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell._set_rect(notice, Rect2(12, 609, 920, 27))
	add_child(notice)
	scroller = Scroller.new()
	shell._set_rect(scroller, Layout.rect(12, 2))
	scroller.spacing = 250.0
	add_child(scroller)
	scroller.set_process_input(false) # This page arbitrates swipe vs. item drag.
	scroller.moved.connect(_position_pages)
	scroller.settled.connect(func(_index: int): _position_pages())
	for index in 8:
		var panel := Control.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.size = Vector2(391, 334)
		scroller.add_child(panel)
		pages.append(panel)
		for cell_index in 9:
			var cell := Control.new()
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.position = Vector2(10 + (cell_index % 3) * 127, 10 + (cell_index / 3) * 108)
			cell.size = Vector2(117, 98)
			panel.add_child(cell)
			var shadow: TextureRect = shell._module_art(cell, 12, 4)
			shell._set_rect(shadow, Rect2(-36.5, -36, 190, 170))
			var frame: TextureRect = shell._module_art(cell, 12, 6)
			shell._set_rect(frame, Rect2(Vector2.ZERO, cell.size))
	for index in GameState.get_bag_capacity():
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shell._set_rect(cell, Layout.rect(12, 7 + index))
		add_child(cell)
		bag_cells.append(cell)
		var frame: TextureRect = shell._module_art(cell, 12, 7 + index)
		frame.position = Vector2.ZERO
	dots = Control.new()
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dots)
	selection = shell._module_art(self, 12, 15)
	selection.hide()
	cursor = TextureRect.new()
	cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.size = Vector2(88, 75)
	add_child(cursor)
	cursor.hide()
	_refresh_inventory()
	scroller.configure(8, 0)
	visibility_changed.connect(_cancel)


func _texture(key: String) -> Texture2D:
	if GameState.WEAPONS.has(key):
		return shell._module_texture(20, int(GameState.WEAPONS[key].id), 0)
	if GameState.PROPS.has(key):
		return shell._module_texture(20, int(GameState.PROPS[key].index), 1)
	return null


func _refresh_inventory() -> void:
	slots = GameState.get_package_slots()
	storage = GameState.get_package_storage()
	for index in bag_cells.size():
		_fill_cell(bag_cells[index], slots[index], 1)
	for index in storage.size():
		var key := storage[index]
		var count := GameState.get_prop_count(key) - slots.count(key) if GameState.PROPS.has(key) else 1
		_fill_cell(pages[index / 9].get_child(index % 9), key, count)
	_position_pages()


func _fill_cell(cell: Control, key: String, count: int) -> void:
	for child in cell.get_children():
		if child.has_meta("item"):
			child.free()
	if key.is_empty():
		return
	var icon := TextureRect.new()
	icon.texture = _texture(key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = cell.size * 0.08
	icon.size = cell.size * 0.84
	icon.set_meta("item", true)
	cell.add_child(icon)
	if count > 1:
		var amount: Label = shell._label(str(count), 18, shell.CYAN)
		amount.set_meta("item", true)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		shell._set_rect(amount, Rect2(4, cell.size.y - 25, cell.size.x - 12, 23))
		cell.add_child(amount)


func _position_pages() -> void:
	if not is_instance_valid(scroller):
		return
	for index in pages.size():
		var panel := pages[index]
		var distance: float = scroller.distance(index)
		var ratio := maxf(0.2, 1.0 - absf(distance) / 710.0)
		panel.scale = Vector2.ONE * ratio
		panel.position = Vector2(355 + distance, 192.5) - panel.size * ratio * 0.5
		panel.visible = absf(distance) < 710
		panel.z_index = 2 if absf(distance) < 125 else 0
	if is_instance_valid(dots):
		shell._draw_dots(dots, 8, posmod(roundi(scroller.offset / 250), 8), Vector2(359, 485), 32.0)
	if is_instance_valid(selection) and _selected.x >= 0:
		selection.visible = _selected.x == 0 or (not scroller.moving and _selected.y / 9 == posmod(roundi(scroller.offset / 250), 8))
		if selection.visible:
			shell._set_rect(selection, cell_rect(_selected))


func cell_rect(address: Vector2i) -> Rect2:
	if address.x == 0:
		return bag_cells[address.y].get_rect()
	var panel := pages[address.y / 9]
	var cell := panel.get_child(address.y % 9) as Control
	return Rect2(scroller.position + panel.position + cell.position * panel.scale, cell.size * panel.scale)


func _hit(point: Vector2) -> Vector2i:
	for index in bag_cells.size():
		if cell_rect(Vector2i(0, index)).has_point(point):
			return Vector2i(0, index)
	if scroller.get_rect().has_point(point) and not scroller.moving:
		var page := posmod(roundi(scroller.offset / 250.0), 8)
		for index in 9:
			if cell_rect(Vector2i(1, page * 9 + index)).has_point(point):
				return Vector2i(1, page * 9 + index)
	return Vector2i(-1, -1)


func _key(address: Vector2i) -> String:
	if address.x < 0:
		return ""
	return slots[address.y] if address.x == 0 else storage[address.y]


func _select(address: Vector2i) -> void:
	_selected = address
	var key := _key(address)
	title.text = ""
	stats.text = ""
	description.text = ""
	if GameState.WEAPONS.has(key):
		var item: Dictionary = GameState.WEAPONS[key]
		title.text = str(item.name)
		stats.text = "[color=#ffa500]POW %s\nFIRERATE %.2f\nENG %d\nSPD %s[/color]" % [shell._source_value(item.damage), float(item.cooldown), int(item.energy), shell._source_value(item.speed_drag)]
		description.text = str(Layout.WEAPON_DESCRIPTIONS[int(item.id)]).replace("[n]", "\n").replace("[EMPTY]", "")
	elif GameState.PROPS.has(key):
		var item: Dictionary = GameState.PROPS[key]
		title.text = str(item.name)
		description.text = str(item.description)
		stats.text = "[color=#00eaff]x %d[/color]" % GameState.get_prop_count(key)
	selection.texture = shell._module_texture(12, 15 if address.x == 0 else 5)
	selection.visible = address.x >= 0
	_position_pages()


func _drop(target: Vector2i) -> void:
	if target.x < 0 or target == _source or _key(_source).is_empty():
		return
	var next_slots := slots.duplicate()
	var next_storage := storage.duplicate()
	if _source.x == target.x:
		var list: Array[String] = next_slots if target.x == 0 else next_storage
		var temp := list[_source.y]
		list[_source.y] = list[target.y]
		list[target.y] = temp
	else:
		var bag_index := _source.y if _source.x == 0 else target.y
		var storage_index := _source.y if _source.x == 1 else target.y
		var old_bag := slots[bag_index]
		var incoming := storage[storage_index]
		var remaining := GameState.get_prop_count(incoming) - slots.count(incoming) if GameState.PROPS.has(incoming) else 1
		if old_bag == incoming:
			next_slots[bag_index] = "" # Return this reserved prop to its stack.
		else:
			next_slots[bag_index] = incoming
			if remaining <= 1:
				next_storage[storage_index] = ""
			if not old_bag.is_empty() and not next_storage.has(old_bag):
				var free_index := storage_index if next_storage[storage_index].is_empty() else next_storage.find("")
				if free_index < 0:
					return
				next_storage[free_index] = old_bag
	if not GameState.set_package(next_slots, next_storage):
		notice.text = "至少保留一把武器；物品數量不能超過已擁有的數量。"
		return
	notice.text = ""
	AudioDirector.play_ui("switch")
	_refresh_inventory()
	_select(target)


func set_interaction_enabled(value: bool) -> void:
	enabled = value
	if not value:
		_cancel()


func _cancel() -> void:
	finger = -1
	_gesture = 0
	_source = Vector2i(-1, -1)
	if is_instance_valid(cursor):
		cursor.hide()
	if is_instance_valid(scroller):
		scroller.cancel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel()


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	var point := Vector2.ZERO
	var pointer := -1
	var press := false
	var release := false
	var drag := false
	var canceled := false
	if event is InputEventScreenTouch:
		point = event.position
		pointer = event.index
		press = event.pressed
		release = not press
		canceled = event.canceled
	elif event is InputEventScreenDrag:
		point = event.position
		pointer = event.index
		drag = true
	elif event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		point = event.position
		pointer = 10000
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			press = event.pressed
			release = not press
		elif event is InputEventMouseMotion:
			drag = true
	else:
		return
	point = get_global_transform_with_canvas().affine_inverse() * point
	if press and finger == -1:
		if not Rect2(0, 83, 960, 516).has_point(point) or Layout.rect(12, 37).has_point(point):
			return
		finger = pointer
		_origin = point
		_source = _hit(point)
		_gesture = 1 if scroller.moving else 0
		scroller._input(event)
		if _source.x >= 0:
			_select(_source)
	elif finger != pointer:
		return
	elif canceled:
		_cancel()
	elif drag:
		var delta := point - _origin
		if _gesture == 0 and delta.length_squared() > 100:
			_gesture = 1 if _source.x != 0 and absf(delta.x) > absf(delta.y) else 2
			if _gesture == 2:
				scroller.cancel()
		if _gesture == 1:
			scroller._input(event)
		elif _gesture == 2 and not _key(_source).is_empty():
			cursor.texture = _texture(_key(_source))
			cursor.position = point - cursor.size * 0.5
			cursor.show()
	elif release:
		if _gesture == 2:
			_drop(_hit(point))
		else:
			scroller._input(event)
		cursor.hide()
		finger = -1
		_gesture = 0
		_source = Vector2i(-1, -1)
	else:
		return
	get_viewport().set_input_as_handled()
