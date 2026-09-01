class_name UnityEquipmentShell
extends Control

signal closed

const Atlas = preload("res://scripts/ui/original_atlas.gd")
const COMPONENT_DIR := "res://assets/ui/components/"
const DESIGN_SIZE := Vector2(960.0, 640.0)
const CYAN := Color(0.4, 1.0, 1.0)
const TEAL := Color(0.12156863, 0.6784314, 0.7372549)
const DESCRIPTION := Color(0.11372549, 0.7294118, 0.65882355)
const LOCKED := Color(0.4, 0.4, 0.4)
const HP_COLOR := Color(0.0, 0.6235294, 1.0)
const POWER_COLOR := Color(1.0, 0.64705884, 0.0)
const SPEED_COLOR := Color(0.039215688, 0.5019608, 0.0)
const GOLD_COLOR := Color(1.0, 1.0, 0.047058824)
const ARMOR_AVATAR_PATH := "res://assets/models/player/animated/player.gltf"
const ARMOR_BAG_DIR := "res://assets/models/player/animated/bags/"

const ARMOR_MESH_PARTS := {
	"head": "armorhead_",
	"body": "armorbody_",
	"arms": "armorhand_",
	"legs": "armorfoot_",
}

const WEAPON_ALPHA_MATERIALS := [
	"gong_1", "gun1112", "passer-standard_1", "sniper_effect", "orig_standard_7",
]
const WEAPON_ADDITIVE_MATERIALS := [
	"fist_eff_001", "fist_eff_001_2", "rpg_mat_031", "rpg_mat_031_2",
	"gunchristmas_02", "hotwing_qiangkou",
]

const CATEGORIES := [
	{"key": "head", "label": "HELMET"},
	{"key": "body", "label": "BODY"},
	{"key": "arms", "label": "ARMS"},
	{"key": "legs", "label": "LEGS"},
	{"key": "bag", "label": "PACK"},
	{"key": "gun", "label": "GUN"},
]

var requested_mode := "store"
var mode := "store"
var selected_category := "gun"
var selected_item_key := ""
var selected_slot := 0
var weapon_filter := ""

var item_scroll: ScrollContainer
var item_row: HBoxContainer
var category_buttons: Dictionary = {}
var mode_buttons: Dictionary = {}
var name_label: Label
var state_label: Label
var meta_label: Label
var stats_text: RichTextLabel
var description_text: RichTextLabel
var price_label: Label
var notice_label: Label
var action_button: Button
var slot_picker: OptionButton
var currency_label: Label
var loadout_label: Label
var preview_caption: Label
var preview_counter: Label
var preview_viewport: SubViewport
var preview_root: Node3D
var preview_tween: Tween


func setup(start_mode: String) -> void:
	requested_mode = "customize" if start_mode == "customize" else "store"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_background()
	_build_category_strip()
	_build_left_rail()
	_build_preview()
	_build_item_carousel()
	_build_details()
	_build_bottom_bar()
	if not GameState.store_changed.is_connected(_on_store_changed):
		GameState.store_changed.connect(_on_store_changed)
	if not GameState.loadout_changed.is_connected(_on_store_changed):
		GameState.loadout_changed.connect(_on_store_changed)
	if not GameState.armor_changed.is_connected(_on_armor_changed):
		GameState.armor_changed.connect(_on_armor_changed)
	set_mode(requested_mode, false)
	_select_category("gun", false)


func _exit_tree() -> void:
	if preview_tween and preview_tween.is_valid():
		preview_tween.kill()
	preview_tween = null


func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "UnityStoreBackdrop"
	background.texture = _component("store_backdrop")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	_set_rect(background, Rect2(Vector2.ZERO, DESIGN_SIZE))
	background.modulate = Color(0.66, 0.74, 0.77)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var wash := ColorRect.new()
	wash.color = Color(0.0, 0.025, 0.04, 0.58)
	_set_rect(wash, Rect2(Vector2.ZERO, DESIGN_SIZE))
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	# Unity authored the screen as two 480px plates. These subtle divisions keep
	# that recovered silhouette without stretching a single modern card across it.
	var center_rule := ColorRect.new()
	center_rule.color = Color(0.18, 0.82, 0.9, 0.18)
	_set_rect(center_rule, Rect2(700, 16, 2, 532))
	center_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_rule)


func _build_category_strip() -> void:
	var title := _label(tr("EQUIPMENT CLASS"), 12, Color(0.48, 0.78, 0.84))
	_set_rect(title, Rect2(112, 10, 584, 18))
	add_child(title)

	var strip := HBoxContainer.new()
	strip.name = "CategoryTabs"
	strip.add_theme_constant_override("separation", 5)
	_set_rect(strip, Rect2(112, 30, 584, 54))
	add_child(strip)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for category: Dictionary in CATEGORIES:
		var key := str(category.key)
		var button := Button.new()
		button.name = "%sTab" % key.capitalize()
		button.text = tr(str(category.label))
		button.tooltip_text = tr("Browse %s equipment") % tr(str(category.label))
		button.custom_minimum_size = Vector2(93, 50)
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_font_size_override("font_size", 13)
		_style_tab(button, false)
		button.pressed.connect(_select_category.bind(key, true))
		category_buttons[key] = button
		strip.add_child(button)


func _build_left_rail() -> void:
	var rail := Panel.new()
	rail.name = "UtilityRail"
	rail.add_theme_stylebox_override("panel", _panel_style(Color(0.005, 0.04, 0.055, 0.9), Color(0.08, 0.52, 0.6, 0.72), 2))
	_set_rect(rail, Rect2(12, 96, 90, 452))
	add_child(rail)

	var y := 12.0
	for mode_key in ["store", "customize"]:
		var button := Button.new()
		button.text = tr("STORE" if mode_key == "store" else "CUSTOMIZE")
		button.add_theme_font_size_override("font_size", 12)
		_set_rect(button, Rect2(8, y, 74, 62))
		button.pressed.connect(set_mode.bind(mode_key, true))
		mode_buttons[mode_key] = button
		rail.add_child(button)
		y += 70.0

	var armor_quick := Button.new()
	armor_quick.text = tr("ARMOR")
	armor_quick.tooltip_text = tr("Jump to equipped armor")
	armor_quick.add_theme_font_size_override("font_size", 12)
	_set_rect(armor_quick, Rect2(8, y + 6, 74, 54))
	armor_quick.pressed.connect(func():
		set_mode("customize", true)
		_select_category("head", true)
	)
	rail.add_child(armor_quick)

	var loadout_quick := Button.new()
	loadout_quick.text = tr("LOADOUT")
	loadout_quick.tooltip_text = tr("Jump to weapon loadout")
	loadout_quick.add_theme_font_size_override("font_size", 11)
	_set_rect(loadout_quick, Rect2(8, y + 68, 74, 54))
	loadout_quick.pressed.connect(func():
		set_mode("customize", true)
		_select_category("gun", true)
	)
	rail.add_child(loadout_quick)

	loadout_label = _label("", 11, Color(0.58, 0.82, 0.88))
	loadout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loadout_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	loadout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_rect(loadout_label, Rect2(6, 338, 78, 102))
	rail.add_child(loadout_label)


func _build_preview() -> void:
	var preview_panel := Panel.new()
	preview_panel.name = "EquipmentPreview"
	preview_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.0, 0.018, 0.027, 0.92), Color(0.04, 0.72, 0.82, 0.78), 3))
	_set_rect(preview_panel, Rect2(112, 94, 584, 312))
	add_child(preview_panel)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "PreviewViewportContainer"
	viewport_container.stretch = true
	_set_rect(viewport_container, Rect2(8, 8, 568, 252))
	preview_panel.add_child(viewport_container)

	preview_viewport = SubViewport.new()
	preview_viewport.name = "PreviewViewport"
	preview_viewport.size = Vector2i(568, 252)
	preview_viewport.transparent_bg = true
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(preview_viewport)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.2, 0.48, 0.57)
	environment.ambient_light_energy = 1.65
	environment_node.environment = environment
	preview_viewport.add_child(environment_node)

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(0.65, 0.95, 1.0)
	key_light.light_energy = 2.25
	key_light.rotation_degrees = Vector3(-38, -28, 0)
	preview_viewport.add_child(key_light)
	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color(1.0, 0.38, 0.1)
	rim_light.light_energy = 1.05
	rim_light.rotation_degrees = Vector3(24, 150, 0)
	preview_viewport.add_child(rim_light)
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-1.4, 1.8, 3.3)
	fill_light.light_color = Color(0.72, 0.94, 1.0)
	fill_light.light_energy = 4.5
	fill_light.omni_range = 12.0
	preview_viewport.add_child(fill_light)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.25, 4.4)
	camera.current = true
	preview_viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.15, 0), Vector3.UP)

	preview_root = Node3D.new()
	preview_root.name = "Turntable"
	preview_viewport.add_child(preview_root)

	preview_caption = _label("", 20, Color.WHITE)
	preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	preview_caption.add_theme_constant_override("shadow_offset_x", 2)
	preview_caption.add_theme_constant_override("shadow_offset_y", 2)
	_set_rect(preview_caption, Rect2(14, 264, 556, 38))
	preview_panel.add_child(preview_caption)


func _build_item_carousel() -> void:
	var carousel_panel := Panel.new()
	carousel_panel.name = "EquipmentCarousel"
	carousel_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.0, 0.025, 0.035, 0.96), Color(0.06, 0.58, 0.66, 0.82), 2))
	_set_rect(carousel_panel, Rect2(112, 416, 584, 132))
	add_child(carousel_panel)

	item_scroll = ScrollContainer.new()
	item_scroll.name = "ItemScroll"
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_set_rect(item_scroll, Rect2(8, 7, 568, 106))
	carousel_panel.add_child(item_scroll)

	item_row = HBoxContainer.new()
	item_row.name = "ItemRow"
	item_row.add_theme_constant_override("separation", 8)
	item_scroll.add_child(item_row)

	preview_counter = _label("", 11, Color(0.48, 0.8, 0.86))
	preview_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(preview_counter, Rect2(8, 113, 568, 17))
	carousel_panel.add_child(preview_counter)


func _build_details() -> void:
	var detail_panel := Panel.new()
	detail_panel.name = "EquipmentDetails"
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.035, 0.046, 0.97), Color(0.08, 0.72, 0.68, 0.9), 3))
	_set_rect(detail_panel, Rect2(704, 16, 244, 532))
	add_child(detail_panel)

	name_label = _label("", 22, TEAL)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_rect(name_label, Rect2(12, 10, 220, 31))
	detail_panel.add_child(name_label)
	state_label = _label("", 13, Color.WHITE)
	_set_rect(state_label, Rect2(12, 42, 220, 23))
	detail_panel.add_child(state_label)
	meta_label = _label("", 11, Color(0.58, 0.78, 0.84))
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_rect(meta_label, Rect2(12, 66, 220, 20))
	detail_panel.add_child(meta_label)

	var rule := ColorRect.new()
	rule.color = Color(0.18, 0.82, 0.9, 0.28)
	_set_rect(rule, Rect2(12, 90, 220, 1))
	detail_panel.add_child(rule)

	stats_text = RichTextLabel.new()
	stats_text.bbcode_enabled = true
	stats_text.fit_content = false
	stats_text.scroll_active = false
	stats_text.add_theme_font_size_override("normal_font_size", 13)
	_set_rect(stats_text, Rect2(12, 100, 220, 166))
	detail_panel.add_child(stats_text)

	description_text = RichTextLabel.new()
	description_text.bbcode_enabled = true
	description_text.fit_content = false
	description_text.scroll_active = true
	description_text.add_theme_font_size_override("normal_font_size", 12)
	description_text.add_theme_color_override("default_color", DESCRIPTION)
	_set_rect(description_text, Rect2(12, 272, 220, 112))
	detail_panel.add_child(description_text)

	price_label = _label("", 15, GOLD_COLOR)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(price_label, Rect2(12, 389, 220, 26))
	detail_panel.add_child(price_label)

	slot_picker = OptionButton.new()
	slot_picker.name = "LoadoutSlotPicker"
	slot_picker.add_theme_font_size_override("font_size", 12)
	slot_picker.item_selected.connect(func(index: int):
		selected_slot = index
		_refresh_details()
	)
	_set_rect(slot_picker, Rect2(12, 419, 220, 34))
	detail_panel.add_child(slot_picker)

	action_button = Button.new()
	action_button.name = "PrimaryAction"
	action_button.add_theme_font_size_override("font_size", 18)
	action_button.add_theme_stylebox_override("normal", _recovered_button_style("button_equip", Color(0.72, 1.0, 0.94)))
	action_button.add_theme_stylebox_override("hover", _recovered_button_style("button_hover", Color.WHITE))
	action_button.add_theme_stylebox_override("pressed", _recovered_button_style("button_pressed", Color(0.78, 1.0, 1.0)))
	action_button.pressed.connect(_perform_primary_action)
	_set_rect(action_button, Rect2(12, 459, 220, 46))
	detail_panel.add_child(action_button)

	notice_label = _label("", 10, Color(1.0, 0.55, 0.2))
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_rect(notice_label, Rect2(12, 508, 220, 18))
	detail_panel.add_child(notice_label)


func _build_bottom_bar() -> void:
	var bar := Panel.new()
	bar.name = "BottomStatusBar"
	bar.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.045, 0.06, 0.985), Color(0.1, 0.66, 0.76, 0.9), 1))
	_set_rect(bar, Rect2(0, 560, 960, 80))
	add_child(bar)

	var back := Button.new()
	back.name = "BackButton"
	back.text = tr("◀  BACK")
	back.add_theme_font_size_override("font_size", 17)
	back.add_theme_stylebox_override("normal", _recovered_button_style("button_normal", Color(0.75, 0.96, 1.0)))
	back.add_theme_stylebox_override("hover", _recovered_button_style("button_hover", Color.WHITE))
	back.pressed.connect(func():
		AudioDirector.play_ui("back")
		closed.emit()
	)
	_set_rect(back, Rect2(0, 1, 126, 78))
	bar.add_child(back)

	for mode_key in ["store", "customize"]:
		var button := Button.new()
		button.text = tr("STORE" if mode_key == "store" else "CUSTOMIZE")
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(set_mode.bind(mode_key, true))
		_set_rect(button, Rect2(140 if mode_key == "store" else 282, 14, 132, 52))
		bar.add_child(button)
		# Bottom and side switches intentionally share state styling.
		button.set_meta("mode_mirror", true)
		mode_buttons["bottom_" + mode_key] = button

	var title := _label(tr("ARMORY"), 23, CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(title, Rect2(422, 8, 250, 64))
	bar.add_child(title)

	currency_label = _label("", 13, Color(0.95, 0.8, 0.3))
	currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(currency_label, Rect2(682, 7, 264, 66))
	bar.add_child(currency_label)


func set_mode(next_mode: String, play_sound := true) -> void:
	mode = "customize" if next_mode == "customize" else "store"
	if play_sound:
		AudioDirector.play_ui("accept")
	for key in mode_buttons:
		var button := mode_buttons[key] as Button
		var key_mode := "customize" if str(key).ends_with("customize") else "store"
		_style_mode_button(button, key_mode == mode)
	_refresh_loadout_summary()
	_rebuild_item_row()
	_select_preferred_item(false)


func _select_category(category_key: String, play_sound := true) -> void:
	if not category_buttons.has(category_key):
		return
	selected_category = category_key
	for key in category_buttons:
		var active := str(key) == selected_category
		var button := category_buttons[key] as Button
		button.button_pressed = active
		_style_tab(button, active)
	if play_sound:
		AudioDirector.play_ui("switch", -5.0)
	_rebuild_item_row()
	_select_preferred_item(false)


func _select_preferred_item(play_sound := false) -> void:
	var ids := _get_category_ids()
	if ids.is_empty():
		selected_item_key = ""
		_refresh_details()
		return
	var preferred := ""
	if selected_category == "gun":
		preferred = GameState.selected_weapon
	else:
		preferred = GameState.get_equipped_armor_key(selected_category)
	if not ids.has(preferred):
		preferred = ids[0]
	_select_item(preferred, play_sound)


func _get_category_ids() -> Array[String]:
	if selected_category != "gun":
		return GameState.get_armor_ids(selected_category)
	var ids := GameState.get_weapon_ids()
	if weapon_filter.is_empty() or weapon_filter == "ALL":
		return ids
	var filtered: Array[String] = []
	for weapon_key: String in ids:
		var type_id := int(GameState.WEAPONS[weapon_key].type)
		var include := false
		match weapon_filter:
			"RIFLE":
				include = type_id in [1, 5, 23]
			"SHOTGUN":
				include = type_id in [2, 15]
			"HEAVY":
				include = type_id in [3, 4, 8, 11, 14, 21, 24, 43]
			"SPECIAL":
				include = type_id in [7, 9, 10, 13, 17, 18, 19, 20, 40, 41, 42]
			"MELEE":
				include = type_id in [12, 16]
		if include:
			filtered.append(weapon_key)
	return filtered


# Compatibility hook for the restoration regression suite. The visible tabs
# remain Unity's six equipment parts; this only lets older tests ask the Gun
# carousel for its former weapon-type subsets.
func set_weapon_filter(filter_key: String) -> void:
	weapon_filter = filter_key
	if selected_category != "gun":
		_select_category("gun", false)
	else:
		_rebuild_item_row()
		_select_preferred_item(false)


func _rebuild_item_row() -> void:
	if not is_instance_valid(item_row):
		return
	for child in item_row.get_children():
		child.free()
	var ids := _get_category_ids()
	for item_key: String in ids:
		var button := Button.new()
		button.name = "Card_%s" % item_key
		button.set_meta("item_key", item_key)
		button.custom_minimum_size = Vector2(108, 102)
		button.add_theme_font_size_override("font_size", 10)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var state := _get_item_state(item_key)
		if selected_category == "gun":
			var weapon: Dictionary = GameState.WEAPONS[item_key]
			button.icon = Atlas.weapon_icon(int(weapon.id))
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 70)
			button.text = tr(state.to_upper())
			button.tooltip_text = "%s • %s" % [str(weapon.name), tr(state.to_upper())]
		else:
			var item: Dictionary = GameState.ARMOR_ITEMS[item_key]
			button.text = "%s\n%s" % [_short_item_name(str(item.name)), tr(state.to_upper())]
			button.tooltip_text = "%s • %s" % [str(item.name), tr(state.to_upper())]
		_style_item_card(button, item_key == selected_item_key, state)
		button.pressed.connect(_select_item.bind(item_key, true))
		item_row.add_child(button)
	preview_counter.text = tr("%d ITEMS") % ids.size()


func _select_item(item_key: String, play_sound := true) -> void:
	if not _get_category_ids().has(item_key):
		return
	selected_item_key = item_key
	if play_sound:
		AudioDirector.play_ui("switch", -5.0)
	_refresh_card_styles()
	_refresh_details()
	_rebuild_preview()
	var ids := _get_category_ids()
	preview_counter.text = "%02d / %02d" % [ids.find(item_key) + 1, ids.size()]
	call_deferred("_ensure_item_visible", item_key)


func _ensure_item_visible(item_key: String) -> void:
	if not is_instance_valid(item_scroll) or not is_instance_valid(item_row):
		return
	for child in item_row.get_children():
		if child is Control and str(child.get_meta("item_key", "")) == item_key and item_scroll.is_ancestor_of(child):
			item_scroll.ensure_control_visible(child)
			return


func _refresh_card_styles() -> void:
	if not is_instance_valid(item_row):
		return
	for child in item_row.get_children():
		if child is Button:
			var key := str(child.get_meta("item_key", ""))
			_style_item_card(child, key == selected_item_key, _get_item_state(key))


func _get_item_state(item_key: String) -> String:
	if selected_category == "gun" or item_key.begins_with("gun"):
		if _active_battle_weapon_ids().has(item_key):
			return "equipped"
		if GameState.is_weapon_owned(item_key):
			return "owned"
		return "available" if GameState.is_weapon_rank_unlocked(item_key) else "locked"
	if GameState.get_equipped_armor_key(selected_category) == item_key:
		return "equipped"
	if GameState.is_armor_owned(item_key):
		return "owned"
	return "available" if GameState.is_armor_rank_unlocked(item_key) else "locked"


func _active_battle_weapon_ids() -> Array[String]:
	# Keep the full stored loadout intact when a smaller bag is equipped, but
	# mirror Player's live combat list so overflow weapons are shown as owned.
	var active_ids: Array[String] = []
	var capacity := maxi(1, GameState.get_bag_capacity())
	for weapon_id_value in GameState.battle_weapons:
		var weapon_id := str(weapon_id_value)
		if active_ids.size() >= capacity:
			break
		if GameState.WEAPONS.has(weapon_id) and not active_ids.has(weapon_id):
			active_ids.append(weapon_id)
	if active_ids.is_empty():
		active_ids.append("gun00")
	return active_ids


func _refresh_details() -> void:
	_refresh_currency()
	_refresh_loadout_summary()
	_rebuild_slot_picker()
	if selected_item_key.is_empty():
		name_label.text = tr("NO EQUIPMENT")
		state_label.text = ""
		meta_label.text = ""
		stats_text.text = ""
		description_text.text = ""
		price_label.text = ""
		action_button.disabled = true
		return
	if selected_category == "gun":
		_refresh_weapon_details()
	else:
		_refresh_armor_details()


func _refresh_weapon_details() -> void:
	var weapon: Dictionary = GameState.WEAPONS.get(selected_item_key, {})
	if weapon.is_empty():
		return
	var state := _get_item_state(selected_item_key)
	name_label.text = str(weapon.name)
	name_label.add_theme_color_override("font_color", Color(weapon.color))
	state_label.text = tr(state.to_upper())
	state_label.add_theme_color_override("font_color", _state_color(state))
	meta_label.text = tr("GUN • TYPE %02d • AIM %02d") % [int(weapon.type), int(weapon.aim_id)]
	var current_key := GameState.selected_weapon
	if selected_slot >= 0 and selected_slot < GameState.battle_weapons.size():
		current_key = GameState.battle_weapons[selected_slot]
	var current: Dictionary = GameState.WEAPONS.get(current_key, weapon)
	stats_text.text = "\n".join([
		_stat_line("POW", float(weapon.damage), float(current.damage), POWER_COLOR, false),
		_stat_line("FIRE", float(weapon.fire_rate), float(current.fire_rate), CYAN, true),
		_stat_line("ENG", float(weapon.energy), float(current.energy), GOLD_COLOR, false, true),
		_stat_line("RANGE", float(weapon.range), float(current.range), SPEED_COLOR, false),
	])
	description_text.text = tr("Recovered Unity weapon. Compare it with the selected bag slot before equipping.")
	_set_price(weapon)
	slot_picker.visible = mode == "customize"
	_configure_action(state)
	preview_caption.text = "%s  /  %s" % [str(weapon.name), tr(state.to_upper())]


func _refresh_armor_details() -> void:
	var item: Dictionary = GameState.ARMOR_ITEMS.get(selected_item_key, {})
	if item.is_empty():
		return
	var state := _get_item_state(selected_item_key)
	name_label.text = str(item.name)
	name_label.add_theme_color_override("font_color", TEAL if state != "locked" else LOCKED)
	state_label.text = tr(state.to_upper())
	state_label.add_theme_color_override("font_color", _state_color(state))
	var set_name := _armor_set_name(int(item.set_id))
	meta_label.text = "%s • %s" % [tr(_category_label(selected_category)), set_name if not set_name.is_empty() else tr("UTILITY GEAR")]
	var current_key := GameState.get_equipped_armor_key(selected_category)
	var current_item: Dictionary = GameState.ARMOR_ITEMS.get(current_key, item)
	var skills: Dictionary = item.skills
	var current_skills: Dictionary = current_item.skills
	var lines := [
		_stat_line("HP", float(skills.get("hp", 0.0)), float(current_skills.get("hp", 0.0)), HP_COLOR, false),
		_stat_line("POW", float(skills.get("attack_boost", 0.0)) * 100.0, float(current_skills.get("attack_boost", 0.0)) * 100.0, POWER_COLOR, false, false, "%"),
		_stat_line("SPD", float(skills.get("speed_boost", 0.0)) * 100.0, float(current_skills.get("speed_boost", 0.0)) * 100.0, SPEED_COLOR, false, false, "%"),
		_stat_line("GOLD", float(skills.get("money_boost", 0.0)) * 100.0, float(current_skills.get("money_boost", 0.0)) * 100.0, GOLD_COLOR, false, false, "%"),
	]
	if selected_category == "bag":
		lines.append(_stat_line("SLOTS", float(item.bag_slots), float(current_item.bag_slots), CYAN, false))
	stats_text.text = "\n".join(lines)
	description_text.text = _armor_description(item)
	_set_price(item)
	slot_picker.visible = false
	_configure_action(state)
	preview_caption.text = "%s  /  %s" % [str(item.name), tr(state.to_upper())]


func _armor_description(item: Dictionary) -> String:
	var fragments: Array[String] = []
	var set_id := int(item.set_id)
	var set_exp_boost := 0.0
	if selected_category != "bag":
		var pieces := _preview_set_piece_count(set_id)
		fragments.append(tr("%s SET • %d/4 MATCHED") % [_armor_set_name(set_id).to_upper(), pieces])
		if pieces == 4 and GameState.ARMOR_SET_BONUSES.has(set_id):
			fragments.append("[color=#%s]%s[/color]" % [CYAN.to_html(false), tr("FULL SET BONUS ACTIVE")])
			var set_skills: Dictionary = GameState.ARMOR_SET_BONUSES[set_id].get("skills", {})
			set_exp_boost = float(set_skills.get("exp_boost", 0.0))
	else:
		fragments.append(tr("BAG CAPACITY • %d WEAPON SLOTS") % int(item.bag_slots))
	var exp_boost := float(item.skills.get("exp_boost", 0.0))
	if not is_zero_approx(exp_boost):
		fragments.append(tr("EXP BOOST %s • XP SYSTEM NOT RESTORED") % _compact_value(exp_boost))
	if not is_zero_approx(set_exp_boost):
		fragments.append(tr("SET EXP BOOST %s • XP SYSTEM NOT RESTORED") % _compact_value(set_exp_boost))
	var advanced: Array[String] = []
	for skill_key in item.skills:
		var value := float(item.skills[skill_key])
		if absf(value) <= 0.0001 or skill_key in ["hp", "attack_boost", "speed_boost", "money_boost", "exp_boost"]:
			continue
		advanced.append("%s %s" % [str(skill_key).replace("_", " ").to_upper(), _compact_value(value)])
		if advanced.size() >= 3:
			break
	if not advanced.is_empty():
		fragments.append("\n".join(advanced))
	else:
		fragments.append(tr("Original Unity armor data restored for this equipment part."))
	return "\n".join(fragments)


func _preview_set_piece_count(set_id: int) -> int:
	var count := 0
	for part_key in ["head", "body", "arms", "legs"]:
		var equipped_key := selected_item_key if part_key == selected_category else GameState.get_equipped_armor_key(part_key)
		if GameState.ARMOR_ITEMS.has(equipped_key) and int(GameState.ARMOR_ITEMS[equipped_key].set_id) == set_id:
			count += 1
	return count


func _configure_action(state: String) -> void:
	action_button.disabled = false
	if mode == "store":
		match state:
			"locked":
				action_button.text = tr("RANK %d REQUIRED") % (_selected_unlock_rank() + 1)
				action_button.disabled = true
			"available":
				action_button.text = tr("BUY")
			_:
				action_button.text = tr("OWNED")
				action_button.disabled = true
	else:
		match state:
			"equipped":
				action_button.text = tr("EQUIPPED")
				action_button.disabled = true
			"owned":
				action_button.text = tr("EQUIP")
			"available":
				action_button.text = tr("BUY IN STORE")
			"locked":
				action_button.text = tr("RANK %d REQUIRED") % (_selected_unlock_rank() + 1)
				action_button.disabled = true


func _perform_primary_action() -> void:
	notice_label.text = ""
	var state := _get_item_state(selected_item_key)
	if mode == "store":
		if state != "available":
			return
		var result := GameState.purchase_weapon(selected_item_key) if selected_category == "gun" else GameState.purchase_armor(selected_item_key)
		match result:
			"purchased":
				notice_label.text = tr("PURCHASE COMPLETE")
				AudioDirector.play_ui("money")
			"rank_locked":
				notice_label.text = tr("Reach the required rank before purchasing this equipment.")
			"not_enough_credits":
				notice_label.text = tr("Not enough credits.")
			"not_enough_mithril":
				notice_label.text = tr("Not enough mithril.")
			_:
				notice_label.text = tr("Purchase could not be completed.")
	else:
		if state == "available":
			set_mode("store", true)
			return
		if state != "owned":
			return
		var equipped := false
		if selected_category == "gun":
			equipped = GameState.set_loadout_weapon(selected_slot, selected_item_key)
			if equipped:
				AudioDirector.play_ui("mount_weapon")
		else:
			equipped = GameState.equip_armor(selected_item_key)
			if equipped:
				AudioDirector.play_ui("mount_gear")
		if not equipped:
			notice_label.text = tr("Unable to equip this item in the selected slot.")
	_on_store_changed()


func _selected_unlock_rank() -> int:
	if selected_category == "gun":
		return int(GameState.WEAPONS.get(selected_item_key, {}).get("unlock", 0))
	return int(GameState.ARMOR_ITEMS.get(selected_item_key, {}).get("unlock", 0))


func _set_price(item: Dictionary) -> void:
	if mode == "customize" and _get_item_state(selected_item_key) in ["owned", "equipped"]:
		price_label.text = tr("OWNED • READY FOR LOADOUT")
		return
	if int(item.get("mithril", 0)) > 0:
		price_label.text = tr("PRICE  #%s MITHRIL") % _format_price(int(item.mithril))
	else:
		price_label.text = tr("PRICE  $%s CREDITS") % _format_price(int(item.get("price", 0)))


func _rebuild_slot_picker() -> void:
	if not is_instance_valid(slot_picker):
		return
	slot_picker.clear()
	var capacity := GameState.get_bag_capacity()
	var visible_slots := mini(capacity, GameState.battle_weapons.size() + 1)
	for slot in range(visible_slots):
		if slot < GameState.battle_weapons.size():
			var weapon_key := GameState.battle_weapons[slot]
			var weapon_name := str(GameState.WEAPONS.get(weapon_key, {}).get("name", tr("EMPTY")))
			slot_picker.add_item(tr("SLOT %d / %s") % [slot + 1, weapon_name])
		else:
			slot_picker.add_item(tr("SLOT %d / EMPTY") % (slot + 1))
	selected_slot = clampi(selected_slot, 0, maxi(0, slot_picker.item_count - 1))
	if slot_picker.item_count > 0:
		slot_picker.select(selected_slot)


func _refresh_currency() -> void:
	if is_instance_valid(currency_label):
		currency_label.text = tr("CREDITS  %s\nMITHRIL  %s") % [_format_price(GameState.credits), _format_price(GameState.mithril)]


func _refresh_loadout_summary() -> void:
	if not is_instance_valid(loadout_label):
		return
	var summary: Dictionary = GameState.get_armor_summary()
	var set_name := str(summary.get("full_set_name", ""))
	var capacity := maxi(1, int(summary.get("bag_slots", 1)))
	loadout_label.text = tr("RANK %d\nBAG %d/%d\n%s") % [
		GameState.get_rank_id() + 1,
		_active_battle_weapon_ids().size(),
		capacity,
		set_name if not set_name.is_empty() else tr("MIXED ARMOR"),
	]


func _on_store_changed() -> void:
	if not is_inside_tree():
		return
	_rebuild_item_row()
	_refresh_card_styles()
	_refresh_details()


func _on_armor_changed(_part_key: String, _armor_key: String) -> void:
	_on_store_changed()


func _rebuild_preview() -> void:
	if not is_instance_valid(preview_root):
		return
	if preview_tween and preview_tween.is_valid():
		preview_tween.kill()
	for child in preview_root.get_children():
		child.free()
	if selected_category == "gun":
		_build_weapon_preview()
	else:
		_build_armor_preview()
	preview_root.rotation_degrees = Vector3(-5, -24, 2)
	preview_tween = preview_root.create_tween().set_loops()
	preview_tween.tween_property(preview_root, "rotation_degrees:y", 336.0, 12.0).from(-24.0)


func _build_weapon_preview() -> void:
	var weapon: Dictionary = GameState.WEAPONS.get(selected_item_key, {})
	if weapon.is_empty():
		return
	var mesh_path := "res://assets/models/weapons/%s.obj" % str(weapon.model)
	var mesh := load(mesh_path) as Mesh if ResourceLoader.exists(mesh_path) else null
	if mesh == null:
		_build_fallback_weapon(Color(weapon.color))
		return
	var preview := MeshInstance3D.new()
	preview.mesh = mesh
	_normalize_preview_mesh(preview, 4.8, Color(weapon.color), 0.04, int(weapon.id))
	preview_root.add_child(preview)


func _build_armor_preview() -> void:
	if selected_category == "bag":
		_build_bag_preview()
		return
	if not ResourceLoader.exists(ARMOR_AVATAR_PATH):
		_build_fallback_armor()
		return
	var avatar_scene := load(ARMOR_AVATAR_PATH) as PackedScene
	if avatar_scene == null:
		_build_fallback_armor()
		return
	var avatar := avatar_scene.instantiate() as Node3D
	if avatar == null:
		_build_fallback_armor()
		return
	var display := Node3D.new()
	display.name = "ArmorAvatarDisplay"
	preview_root.add_child(display)
	avatar.name = "RecoveredArmorAvatar"
	avatar.rotation_degrees.y = -90.0
	display.add_child(avatar)
	_apply_preview_armor_visibility(avatar)
	_play_preview_idle(avatar)
	if not _normalize_avatar_preview(display, avatar, 3.8):
		display.queue_free()
		_build_fallback_armor()


func _build_bag_preview() -> void:
	var item: Dictionary = GameState.ARMOR_ITEMS.get(selected_item_key, {})
	var visual_id := int(item.get("visual_id", 0))
	var bag_name := "ArmorBag_%02d" % visual_id
	var mesh_path := "%s%s/%s.obj" % [ARMOR_BAG_DIR, bag_name, bag_name]
	var mesh := load(mesh_path) as Mesh if ResourceLoader.exists(mesh_path) else null
	if mesh == null:
		_build_fallback_armor()
		return
	var display := Node3D.new()
	display.name = "BagPreviewDisplay"
	preview_root.add_child(display)
	var preview := MeshInstance3D.new()
	preview.name = bag_name
	preview.mesh = mesh
	_prepare_preview_materials(preview, Color.WHITE, 0.0)
	display.add_child(preview)
	if not _normalize_preview_node(display, 3.55):
		display.queue_free()
		_build_fallback_armor()


func _apply_preview_armor_visibility(avatar: Node3D) -> void:
	var visible_ids := {}
	for part_key: String in ARMOR_MESH_PARTS:
		var armor_key := selected_item_key if selected_category == part_key else GameState.get_equipped_armor_key(part_key)
		visible_ids[part_key] = int(GameState.get_armor_item(armor_key).get("visual_id", 0))
	for candidate in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		var lower_name := mesh_instance.name.to_lower()
		for part_key: String in ARMOR_MESH_PARTS:
			var prefix := str(ARMOR_MESH_PARTS[part_key])
			if not lower_name.begins_with(prefix):
				continue
			var id_text := lower_name.trim_prefix(prefix)
			mesh_instance.visible = id_text.is_valid_int() and int(id_text) == int(visible_ids[part_key])
			break


func _play_preview_idle(avatar: Node3D) -> void:
	for candidate in avatar.find_children("*", "AnimationPlayer", true, false):
		var animation_player := candidate as AnimationPlayer
		if animation_player.has_animation("idle_rifle"):
			var idle_animation := animation_player.get_animation("idle_rifle")
			if idle_animation != null:
				idle_animation.loop_mode = Animation.LOOP_LINEAR
			animation_player.play("idle_rifle")
			animation_player.seek(0.0, true)
			return


func _normalize_avatar_preview(display: Node3D, avatar: Node3D, target_height: float) -> bool:
	# Skinned MeshInstance AABBs stay in their bind-space axes, while the imported
	# Unity skeleton stands upright after skinning. Use bone positions so the
	# animated avatar remains centered instead of drifting above the viewport.
	var skeleton := avatar.find_child("*", true, false) as Skeleton3D
	if skeleton == null:
		for candidate in avatar.find_children("*", "Skeleton3D", true, false):
			skeleton = candidate as Skeleton3D
			break
	if skeleton == null or skeleton.get_bone_count() == 0:
		return _normalize_preview_node(display, target_height)
	var skeleton_transform := _transform_relative_to_ancestor(skeleton, display)
	var bounds := AABB()
	var has_bounds := false
	for bone_index in range(skeleton.get_bone_count()):
		var bone_point := (skeleton_transform * skeleton.get_bone_global_pose(bone_index)).origin
		var point_bounds := AABB(bone_point, Vector3(0.001, 0.001, 0.001))
		bounds = bounds.merge(point_bounds) if has_bounds else point_bounds
		has_bounds = true
	if not has_bounds or bounds.size.y <= 0.05:
		return _normalize_preview_node(display, target_height)
	# Armor extends beyond the head, toes, shoulders and hands represented by the
	# skeleton. Add a small authored margin before deriving the preview transform.
	bounds = bounds.grow(0.16)
	var factor := target_height / bounds.size.y
	display.scale = Vector3.ONE * factor
	display.position = -(bounds.position + bounds.size * 0.5) * factor
	return true


func _normalize_preview_node(display: Node3D, target_size: float) -> bool:
	var bounds := AABB()
	var has_bounds := false
	for candidate in display.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if not mesh_instance.visible or mesh_instance.mesh == null:
			continue
		var relative_transform := _transform_relative_to_ancestor(mesh_instance, display)
		var candidate_bounds: AABB = relative_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(candidate_bounds) if has_bounds else candidate_bounds
		has_bounds = true
	if not has_bounds:
		return false
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var factor := target_size / longest if longest > 0.001 else 1.0
	display.scale = Vector3.ONE * factor
	display.position = -(bounds.position + bounds.size * 0.5) * factor
	return true


func _transform_relative_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var relative := node.transform
	var parent := node.get_parent()
	while parent != null and parent != ancestor:
		if parent is Node3D:
			relative = (parent as Node3D).transform * relative
		parent = parent.get_parent()
	return relative


func _normalize_preview_mesh(preview: MeshInstance3D, target_size: float, tint: Color, tint_weight: float, weapon_id := -1) -> void:
	_prepare_preview_materials(preview, tint, tint_weight, weapon_id)
	var bounds := preview.mesh.get_aabb()
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var factor := target_size / longest if longest > 0.001 else 1.0
	preview.scale = Vector3.ONE * factor
	preview.position = -(preview.basis * (bounds.position + bounds.size * 0.5))


func _prepare_preview_materials(preview: MeshInstance3D, tint: Color, tint_weight: float, weapon_id := -1) -> void:
	for surface_index in preview.mesh.get_surface_count():
		var source_material := preview.mesh.surface_get_material(surface_index)
		if source_material is StandardMaterial3D:
			var material := source_material.duplicate(true) as StandardMaterial3D
			material.albedo_color = Color.WHITE.lerp(tint, tint_weight)
			if material.albedo_texture != null:
				material.albedo_color.a = 1.0
			if weapon_id >= 0:
				_repair_preview_weapon_material(material, source_material, weapon_id, surface_index)
			preview.set_surface_override_material(surface_index, material)


func _repair_preview_weapon_material(material: StandardMaterial3D, source: StandardMaterial3D, weapon_id: int, surface_index: int) -> void:
	# OBJ/MTL cannot preserve Unity's SolidTexture versus additive shader roles.
	# Match the combat renderer's authored shader-name classification. PNG alpha
	# alone is not sufficient because multiple solid atlases contain unused alpha.
	var material_name := source.resource_name.to_lower()
	var alpha_effect := material_name in WEAPON_ALPHA_MATERIALS
	var additive_effect := material_name in WEAPON_ADDITIVE_MATERIALS
	if material_name.is_empty():
		alpha_effect = weapon_id == 22 and surface_index in [1, 2]
		additive_effect = (
			(weapon_id == 23 and surface_index in [0, 1])
			or (weapon_id == 37 and surface_index in [1, 2])
		)
	var forced_solid := (
		(weapon_id == 22 and surface_index == 0)
		or (weapon_id == 23 and surface_index == 2)
		or (weapon_id == 37 and surface_index == 0)
	)
	var almost_black_tint := source.albedo_color.r + source.albedo_color.g + source.albedo_color.b < 0.15
	if forced_solid or almost_black_tint or alpha_effect or additive_effect:
		material.albedo_color = Color(1.0, 1.0, 1.0, source.albedo_color.a)
	if forced_solid:
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	elif alpha_effect or additive_effect:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive_effect else BaseMaterial3D.BLEND_MODE_MIX
		if material_name == "gong_1":
			material.albedo_color.a = 0.58


func _build_fallback_weapon(color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.35)
	material.metallic = 0.72
	material.roughness = 0.28
	material.emission_enabled = true
	material.emission = color * 0.25
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(2.5, 0.58, 0.62)
	body_mesh.material = material
	body.mesh = body_mesh
	preview_root.add_child(body)
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.16
	barrel_mesh.bottom_radius = 0.2
	barrel_mesh.height = 2.2
	barrel_mesh.material = material
	barrel.mesh = barrel_mesh
	barrel.rotation_degrees.z = 90.0
	barrel.position.x = 1.65
	preview_root.add_child(barrel)


func _build_fallback_armor() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.45, 0.52)
	material.metallic = 0.65
	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.height = 2.2
	torso_mesh.radius = 0.7
	torso_mesh.material = material
	torso.mesh = torso_mesh
	preview_root.add_child(torso)


func _stat_line(label_text: String, value: float, current: float, color: Color, decimal := false, inverse := false, suffix := "") -> String:
	var delta := value - current
	var value_text := ("%.2f" % value) if decimal else str(roundi(value))
	var delta_text := ""
	if absf(delta) > 0.004:
		var beneficial := delta < 0.0 if inverse else delta > 0.0
		var delta_color := Color(0.25, 1.0, 0.45) if beneficial else Color(1.0, 0.3, 0.25)
		var formatted_delta := ("%.2f" % absf(delta)) if decimal else str(absi(roundi(delta)))
		delta_text = "  [color=#%s]%s%s%s[/color]" % [
			delta_color.to_html(false),
			"+" if delta > 0.0 else "-",
			formatted_delta,
			suffix,
		]
	return "[color=#%s]%s[/color]  %s%s%s" % [color.to_html(false), tr(label_text), value_text, suffix, delta_text]


func _compact_value(value: float) -> String:
	if absf(value) < 1.0:
		return "%+.0f%%" % (value * 100.0)
	return "%+.0f" % value


func _armor_set_name(set_id: int) -> String:
	return str(GameState.ARMOR_SET_BONUSES.get(set_id, {}).get("name", ""))


func _category_label(category_key: String) -> String:
	for category: Dictionary in CATEGORIES:
		if str(category.key) == category_key:
			return str(category.label)
	return category_key.to_upper()


func _short_item_name(value: String) -> String:
	return value if value.length() <= 15 else value.left(14) + "…"


func _state_color(state: String) -> Color:
	match state:
		"equipped":
			return Color(0.3, 1.0, 0.55)
		"owned":
			return CYAN
		"available":
			return Color(1.0, 0.78, 0.22)
	return LOCKED


func _style_tab(button: Button, active: bool) -> void:
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.03, 0.2, 0.23, 0.95) if active else Color(0.01, 0.045, 0.06, 0.94), CYAN if active else Color(0.16, 0.4, 0.46, 0.8), 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.05, 0.32, 0.36, 0.98), CYAN, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.08, 0.42, 0.45, 1.0), Color.WHITE, 2))
	button.add_theme_color_override("font_color", Color.WHITE if active else Color(0.55, 0.82, 0.87))


func _style_mode_button(button: Button, active: bool) -> void:
	_style_tab(button, active)
	button.disabled = false
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if active else Control.CURSOR_POINTING_HAND


func _style_item_card(button: Button, selected: bool, state: String) -> void:
	var state_color := _state_color(state)
	var fill := Color(0.025, 0.15, 0.17, 0.98) if selected else Color(0.006, 0.035, 0.045, 0.96)
	button.add_theme_stylebox_override("normal", _panel_style(fill, state_color if selected else Color(state_color, 0.48), 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.04, 0.23, 0.26, 0.98), state_color, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.08, 0.32, 0.35, 1.0), Color.WHITE, 2))
	button.add_theme_color_override("font_color", state_color)
	button.modulate = Color.WHITE if state != "locked" else Color(0.58, 0.62, 0.64)


func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _component(component_name: String) -> Texture2D:
	var path := COMPONENT_DIR + component_name + ".png"
	return load(path) if ResourceLoader.exists(path) else null


func _recovered_button_style(component_name: String, tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _component(component_name)
	style.modulate_color = tint
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _format_price(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
