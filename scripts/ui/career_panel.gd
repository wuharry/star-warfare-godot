class_name CareerPanel
extends Control
## Reusable profile overlay. add_child(panel), then show_progress(career).
## All progress is local; this view never owns persistence or submits a score.

signal dismissed

const CareerData = preload("res://scripts/core/career_progress.gd")
const Art = preload("res://scripts/ui/recovered_armory_skin.gd")
const STAT_ROWS := [
	["enemy_kills", "ALIENS DEFEATED"], ["team_kills", "MULTIPLAYER ALIEN KILLS"],
	["max_combo", "BEST KILL CHAIN"], ["high_score", "HIGHEST RUN SCORE"],
	["high_kills", "MOST KILLS IN A RUN"], ["wins", "RUNS WON"],
	["losses", "RUNS LOST"], ["flawless_wins", "FLAWLESS PVE WINS"],
	["credits_spent", "CREDITS SPENT"], ["full_upgrades", "FULLY UPGRADED WEAPONS"],
	["suits_collected", "COMPLETE SW1 SUITS"], ["revivals", "REVIVALS USED"],
	["multiplayer_sessions", "MULTIPLAYER SESSIONS"],
]

var progress: CareerData
var panel: PanelContainer
var tabs: TabContainer
var filter: OptionButton
var close_button: Button
var completion_label: Label
var score_label: Label
var _stat_values: Dictionary = {}
var _achievement_rows: Dictionary = {}
var _previous_focus: Control
var _refresh_pending := false
var _layout_pending := false
var _translated_labels: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 210
	theme = Art.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.012, 0.025, 0.90)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.name = "CareerContent"
	panel.add_theme_stylebox_override("panel", Art.panel())
	add_child(panel)
	panel.minimum_size_changed.connect(_queue_layout)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := _label(header, "CAREER", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	completion_label = _label(header, "0 / 23", 18)
	completion_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	completion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	close_button = Button.new()
	close_button.text = tr("BACK")
	close_button.custom_minimum_size = Vector2(96, 44)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		close_button.add_theme_stylebox_override(state, Art.plate(state))
	close_button.add_theme_stylebox_override("focus", Art.focus())
	header.add_child(close_button)
	close_button.pressed.connect(close)
	var subtitle := _label(column, "LOCAL PROGRESS  /  OFFLINE ACHIEVEMENTS", 13)
	subtitle.modulate = Color(0.52, 0.85, 0.90)
	tabs = TabContainer.new()
	tabs.name = "CareerTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	_build_statistics()
	_build_achievements()
	_refresh_language()
	resized.connect(_layout)
	hide()
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_language()


func _refresh_language() -> void:
	# Retain English message IDs so an already-open panel can switch both ways.
	# Node names and achievement data stay unchanged for callers and saved data.
	for label: Label in _translated_labels:
		label.text = tr(str(_translated_labels[label]))
	close_button.text = tr("BACK")
	tabs.set_tab_title(0, tr("STATISTICS"))
	tabs.set_tab_title(1, tr("ACHIEVEMENTS"))
	var captions := ["ALL ACHIEVEMENTS", "IN PROGRESS", "COMPLETED"]
	for index in range(captions.size()):
		filter.set_item_text(index, tr(captions[index]))
	_refresh()
	_queue_layout()


func show_progress(value: CareerData) -> void:
	bind_progress(value)
	if not visible:
		_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	_refresh()
	_layout()
	_queue_layout()
	close_button.grab_focus()


func bind_progress(value: CareerData) -> void:
	if progress != null and progress.changed.is_connected(_queue_refresh):
		progress.changed.disconnect(_queue_refresh)
	progress = value
	if progress != null:
		progress.changed.connect(_queue_refresh)
	_queue_refresh()


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
		# Keep keyboard focus in the overlay, including when achievements are hidden.
		var controls: Array[Control] = [close_button, tabs.get_tab_bar()]
		if tabs.current_tab == 1:
			controls.append(filter)
		var index := controls.find(get_viewport().gui_get_focus_owner())
		var direction := -1 if event.is_action_pressed("ui_focus_prev") else 1
		controls[posmod(index + direction, controls.size())].grab_focus()
		get_viewport().set_input_as_handled()


func _build_statistics() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "STATISTICS"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	for row: Array in STAT_ROWS:
		_add_stat_row(column, str(row[0]), str(row[1]))
	_add_stat_row(column, "boss_0", "BOSSES: MANTIS")
	_add_stat_row(column, "boss_1", "BOSSES: SPIDER / EARTHWORM / SATAN")
	_add_stat_row(column, "boss_2", "BOSSES: DRAGON")
	column.add_child(HSeparator.new())
	_label(column, "BEST SCORES BY RUN", 17)
	score_label = _label(column, "No completed runs recorded.", 15)
	var note := _label(column, "Kill chains reset after more than 3 seconds without a kill.\nBoss milestones count each boss category separately.", 13)
	note.modulate = Color(0.60, 0.75, 0.81)


func _add_stat_row(parent: Control, key: String, caption: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size.y = 28
	parent.add_child(row)
	var label := _label(row, caption, 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, "0", 17)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.modulate = Art.CYAN
	_stat_values[key] = value


func _build_achievements() -> void:
	var column := VBoxContainer.new()
	column.name = "ACHIEVEMENTS"
	column.add_theme_constant_override("separation", 10)
	tabs.add_child(column)
	filter = OptionButton.new()
	filter.name = "AchievementFilter"
	filter.custom_minimum_size.y = 40
	for caption: String in ["ALL ACHIEVEMENTS", "IN PROGRESS", "COMPLETED"]:
		filter.add_item(tr(caption))
	column.add_child(filter)
	filter.item_selected.connect(func(_index: int) -> void: _refresh())
	var scroll := ScrollContainer.new()
	scroll.name = "AchievementScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for definition: Dictionary in CareerData.ACHIEVEMENTS:
		var card := PanelContainer.new()
		card.name = definition.id
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.07, 0.105, 0.94)
		style.border_color = Color(0.12, 0.28, 0.35)
		style.set_border_width_all(1)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_content_margin(side, 12)
		card.add_theme_stylebox_override("panel", style)
		list.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		card.add_child(body)
		var heading := HBoxContainer.new()
		body.add_child(heading)
		var title := _label(heading, str(definition.title), 17)
		title.uppercase = true
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var count := _label(heading, "0 / %d" % int(definition.target), 14)
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var detail := _label(body, definition.description, 14)
		detail.modulate = Color(0.68, 0.82, 0.88)
		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 8
		bar.show_percentage = false
		body.add_child(bar)
		_achievement_rows[definition.id] = {"card": card, "count": count, "bar": bar}


func _queue_refresh() -> void:
	if not is_node_ready() or not visible or _refresh_pending:
		return
	_refresh_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_pending = false
	if not is_node_ready() or not visible:
		return
	var model := progress if progress != null else CareerData.new()
	var stats := model.get_statistics()
	completion_label.text = "%d / %d" % [stats.achievements_completed, stats.achievements_total]
	for row: Array in STAT_ROWS:
		_stat_values[row[0]].text = str(stats[row[0]])
	for index in range(3):
		_stat_values["boss_%d" % index].text = str(stats.boss_kills[index])
	var score_lines: Array[String] = []
	var score_keys: Array = stats.best_scores.keys()
	score_keys.sort()
	for key: String in score_keys:
		score_lines.append("%s:  %d" % [tr(key), stats.best_scores[key]])
	score_label.text = tr("No completed runs recorded.") if score_lines.is_empty() else "\n".join(score_lines)
	for achievement: Dictionary in model.get_achievements():
		var row: Dictionary = _achievement_rows[achievement.id]
		row.card.visible = filter.selected == 0 or (filter.selected == 2) == bool(achievement.complete)
		row.count.text = tr("COMPLETE") if achievement.complete else "%d / %d" % [achievement.current, achievement.target]
		row.count.modulate = Color(0.45, 1.0, 0.70) if achievement.complete else Color(0.95, 0.77, 0.37)
		row.bar.value = float(achievement.progress) * 100.0


func _layout() -> void:
	_layout_pending = false
	if panel == null:
		return
	var inset := 16.0 if size.x >= 600.0 else 8.0
	panel.size = Vector2(minf(1040, size.x - inset * 2.0), minf(660, size.y - inset * 2.0))
	panel.position = (size - panel.size) * 0.5


func _queue_layout() -> void:
	# Wrapped labels first report a tall minimum before containers assign width.
	# Reflow after those measurements settle so the header stays inside the view.
	if not _layout_pending:
		_layout_pending = true
		_layout.call_deferred()


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	_translated_labels[label] = text
	label.text = tr(text)
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
