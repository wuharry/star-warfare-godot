extends VBoxContainer
const Rules = preload("res://scripts/core/match_rules.gd")
var mode_picker: OptionButton
var map_picker: OptionButton
var boss_picker: OptionButton
var capacity: SpinBox
var duration: SpinBox
var score_limit: SpinBox
var port: SpinBox
var address: LineEdit
var nickname: LineEdit
var team: OptionButton
var ready_button: CheckButton
var roster_label: Label
var status_label: Label
var description_label: Label
var start_button: Button
var host_button: Button
var join_button: Button
var apply_button: Button
var refreshing := false
var lan_browser: Node
var lan_box: VBoxContainer
var room_list: ItemList
var quick_button: Button
var room_name: LineEdit
var lan_rooms: Array[Dictionary] = []

func _ready() -> void:
	name = "DirectConnectLobby"
	add_theme_constant_override("separation", 8)
	_text("DIRECT CONNECT • IP / LAN", 24)
	_text("Direct connection. Original matchmaking and servers are not restored. Internet play requires UDP port forwarding.", 14)
	_build_lan_browser()
	nickname = _edit("PLAYER NAME", str(GameState.settings.get("nickname", "PLAYER")))
	room_name = _edit("ROOM NAME", str(NetworkSession.room.room_name))
	address = _edit("HOST IP", "127.0.0.1")
	port = _number("UDP PORT", 1024, 65535, NetworkSession.DEFAULT_PORT)
	var choices := HBoxContainer.new()
	add_child(choices)
	mode_picker = OptionButton.new()
	mode_picker.name = "ModePicker"
	for mode: String in Rules.MODES:
		mode_picker.add_item(tr(mode))
	choices.add_child(mode_picker)
	map_picker = OptionButton.new()
	map_picker.name = "MapPicker"
	choices.add_child(map_picker)
	boss_picker = OptionButton.new()
	for boss_name: String in Rules.BOSS_TYPES:
		boss_picker.add_item(tr(boss_name))
	choices.add_child(boss_picker)
	mode_picker.item_selected.connect(func(_index):
		_populate_maps()
		_refresh_rooms()
	)
	capacity = _number("MAX PLAYERS", 2, 8, 4)
	duration = _number("PVP TIME LIMIT (SECONDS; CO-OP IS UNTIMED)", 60, 3600, 600)
	score_limit = _number("PVP SCORE LIMIT (LAN SETTING)", 100, 10000, 1000)
	description_label = _text("", 14)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size.y = 44
	_text("Uses each player's equipped weapons, upgrades, armor and battle items. Modern reloads are available.", 13)
	var actions := HBoxContainer.new()
	add_child(actions)
	host_button = _button(actions, "HOST ROOM", _host)
	join_button = _button(actions, "JOIN IP", _join)
	apply_button = _button(actions, "APPLY ROOM SETTINGS", func(): NetworkSession.configure_room(_config()))
	_button(actions, "LEAVE ROOM", func(): NetworkSession.leave())
	var readiness := HBoxContainer.new()
	add_child(readiness)
	team = OptionButton.new()
	team.add_item(tr("BLUE"), 0)
	team.add_item(tr("RED"), 1)
	readiness.add_child(team)
	ready_button = CheckButton.new()
	ready_button.text = tr("READY")
	readiness.add_child(ready_button)
	team.item_selected.connect(func(index):
		if not refreshing:
			NetworkSession.set_ready(false, index)
	)
	ready_button.toggled.connect(func(value):
		if not refreshing:
			NetworkSession.set_ready(value, team.selected)
	)
	start_button = _button(readiness, "START MATCH", func(): NetworkSession.start_match())
	roster_label = _text("", 16)
	status_label = _text("", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NetworkSession.lobby_changed.connect(_refresh)
	_populate_maps()
	_refresh()

func _build_lan_browser() -> void:
	lan_browser = preload("res://scripts/network/lan_discovery.gd").new()
	add_child(lan_browser)
	lan_box = VBoxContainer.new()
	add_child(lan_box)
	var title := Label.new()
	title.text = tr("LAN ROOMS • SAME NETWORK ONLY")
	lan_box.add_child(title)
	room_list = ItemList.new()
	room_list.name = "LANRoomList"
	room_list.custom_minimum_size.y = 110
	room_list.item_activated.connect(_join_discovered)
	lan_box.add_child(room_list)
	var actions := HBoxContainer.new()
	lan_box.add_child(actions)
	_button(actions, "REFRESH LAN", func(): lan_browser.refresh())
	_button(actions, "JOIN SELECTED", func():
		var selection := room_list.get_selected_items()
		if not selection.is_empty(): _join_discovered(selection[0])
	)
	quick_button = _button(actions, "QUICK JOIN (SELECTED MODE)", _quick_join)
	lan_browser.rooms_changed.connect(_refresh_rooms)
	lan_browser.browse()

func _refresh_rooms() -> void:
	if room_list == null: return
	var selected_key := ""
	var selection := room_list.get_selected_items()
	if not selection.is_empty() and selection[0] < lan_rooms.size():
		selected_key = str(lan_rooms[selection[0]].key)
	lan_rooms = lan_browser.get_rooms()
	room_list.clear()
	for entry: Dictionary in lan_rooms:
		var label := "%s • %s • %d/%d • %s:%d" % [entry.name, tr(str(entry.mode)), entry.players, entry.max_players, entry.address, entry.port]
		var index := room_list.add_item(label)
		room_list.set_item_disabled(index, int(entry.players) >= int(entry.max_players))
		if str(entry.key) == selected_key: room_list.select(index)
	if lan_rooms.is_empty():
		room_list.add_item(tr("No LAN rooms found. Refresh or enter the host IP."))
		room_list.set_item_disabled(0, true)
	quick_button.disabled = NetworkSession.phase != "offline" or _quick_room_index() < 0

func _quick_room_index() -> int:
	if mode_picker == null: return -1
	for index in lan_rooms.size():
		var entry: Dictionary = lan_rooms[index]
		if entry.mode == Rules.MODES[mode_picker.selected] and int(entry.players) < int(entry.max_players): return index
	return -1

func _quick_join() -> void:
	var index := _quick_room_index()
	if index >= 0: _join_discovered(index)

func _join_discovered(index: int) -> void:
	if NetworkSession.phase != "offline" or index < 0 or index >= lan_rooms.size(): return
	var entry: Dictionary = lan_rooms[index]
	address.text = entry.address
	port.value = entry.port
	_join()

func _exit_tree() -> void:
	if NetworkSession.phase in ["lobby", "connecting"]:
		NetworkSession.leave()

func _text(caption: String, size_value: int) -> Label:
	var label := Label.new()
	label.text = tr(caption)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size_value)
	add_child(label)
	return label

func _edit(caption: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = tr(caption)
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.max_length = 64
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field

func _number(caption: String, minimum: int, maximum: int, value: int) -> SpinBox:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = tr(caption)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = 1
	field.value = value
	row.add_child(field)
	return field

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = tr(caption)
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _populate_maps() -> void:
	map_picker.clear()
	var mode := str(Rules.MODES[mode_picker.selected])
	for level in range(1, 9) if Rules.is_coop(mode) else range(13, 22):
		map_picker.add_item("%02d %s" % [level, tr(str(GameState.get_level_data(level).name))], level)
	if mode == "CMI":
		map_picker.select(map_picker.get_item_index(21))
	capacity.min_value = 1 if Rules.is_coop(mode) else 2
	capacity.max_value = 3 if Rules.is_coop(mode) else 8
	boss_picker.visible = mode == "Boss"
	description_label.text = Rules.description(mode) if description_label != null else ""
	if mode == "Boss":
		description_label.text += tr(" Source bosses and arenas. Every cleared boss encounter awards each participant 1 Mithril.")

func _config() -> Dictionary:
	return {"mode": Rules.MODES[mode_picker.selected], "level": map_picker.get_selected_id(),
		"room_name": room_name.text,
		"boss_index": boss_picker.selected,
		"max_players": int(capacity.value), "time_limit": int(duration.value), "score_limit": int(score_limit.value)}

func _profile() -> Dictionary:
	var profile := NetworkSession.profile_from_local()
	profile.name = nickname.text
	return profile

func _host() -> void:
	NetworkSession.host_room(_config(), int(port.value), _profile())

func _join() -> void:
	NetworkSession.join_room(address.text.strip_edges(), int(port.value), _profile())

func _refresh() -> void:
	refreshing = true
	var in_room := NetworkSession.phase == "lobby"
	var editing := NetworkSession.phase == "offline" or NetworkSession.is_host()
	lan_box.visible = NetworkSession.phase == "offline"
	room_name.editable = editing
	if in_room:
		mode_picker.select(Rules.MODES.find(NetworkSession.room.mode))
		_populate_maps()
		map_picker.select(map_picker.get_item_index(int(NetworkSession.room.level)))
		boss_picker.select(int(NetworkSession.room.boss_index))
		capacity.value = NetworkSession.room.max_players
		duration.value = NetworkSession.room.time_limit
		score_limit.value = NetworkSession.room.score_limit
	mode_picker.disabled = not editing
	map_picker.disabled = not editing
	boss_picker.disabled = not editing
	capacity.editable = editing
	duration.editable = editing
	score_limit.editable = editing
	nickname.editable = not in_room
	host_button.disabled = NetworkSession.phase != "offline"
	join_button.disabled = NetworkSession.phase != "offline"
	apply_button.disabled = not NetworkSession.is_host() or not in_room
	ready_button.disabled = not in_room
	team.disabled = not in_room
	var id := NetworkSession.local_id()
	if NetworkSession.roster.has(id):
		ready_button.set_pressed_no_signal(NetworkSession.roster[id].ready)
		team.select(int(NetworkSession.roster[id].team))
	else:
		ready_button.set_pressed_no_signal(false)
	start_button.disabled = not NetworkSession.start_problem().is_empty()
	start_button.tooltip_text = tr(NetworkSession.start_problem())
	var lines: Array[String] = []
	for peer_id: int in NetworkSession.roster:
		var row: Dictionary = NetworkSession.roster[peer_id]
		lines.append("%s  •  %s  •  %s%s" % [row.name, tr("BLUE") if int(row.team) == 0 else tr("RED"), tr("READY") if row.ready else tr("WAITING"), " (HOST)" if peer_id == 1 else ""])
	roster_label.text = "\n".join(lines)
	status_label.text = tr(NetworkSession.status) + ("\n" + NetworkSession.discovery_status if not NetworkSession.discovery_status.is_empty() else "")
	_refresh_rooms()
	refreshing = false
