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
var screen_title: Label
var category_layer: Control
var item_dots_layer: Control
var comparison_rows: Array[Dictionary] = []
var item_swipe_distance := 0.0
var item_mouse_dragging := false
var category_swipe_distance := 0.0
var category_mouse_dragging := false

const SWIPE_THRESHOLD := 34.0


func setup(start_mode: String) -> void:
	requested_mode = "customize" if start_mode == "customize" else "store"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_background()
	_build_preview()
	_build_item_carousel()
	_build_comparison_stats()
	_build_details()
	_build_category_strip()
	_build_left_rail()
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
	background.texture = _component("armory_background")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	_set_rect(background, Rect2(Vector2.ZERO, DESIGN_SIZE))
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)


func _build_category_strip() -> void:
	category_layer = Control.new()
	category_layer.name = "CategoryTabs"
	_set_rect(category_layer, Rect2(0, 0, 960, 640))
	category_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(category_layer)
	var swipe_area := Control.new()
	swipe_area.name = "CategorySwipeArea"
	swipe_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_rect(swipe_area, Rect2(177, 494, 450, 99))
	swipe_area.gui_input.connect(_on_category_carousel_input)
	category_layer.add_child(swipe_area)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for category_index in range(CATEGORIES.size()):
		var category: Dictionary = CATEGORIES[category_index]
		var key := str(category.key)
		var button := Button.new()
		button.name = "%sTab" % key.capitalize()
		button.text = ""
		button.tooltip_text = tr("Browse %s equipment") % tr(str(category.label))
		button.toggle_mode = true
		button.button_group = group
		button.icon = _component("armory_category_%02d" % category_index)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_stylebox_override("normal", _empty_style())
		button.add_theme_stylebox_override("hover", _texture_style("armory_category_frame", Color(0.75, 1.0, 1.0)))
		button.add_theme_stylebox_override("pressed", _texture_style("armory_category_frame", Color.WHITE))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.gui_input.connect(_on_category_carousel_input)
		button.pressed.connect(_select_category.bind(key, true))
		category_buttons[key] = button
		category_layer.add_child(button)
	_layout_category_buttons()

	for category_index in range(CATEGORIES.size()):
		var dot := TextureRect.new()
		dot.name = "CategoryDot%02d" % category_index
		dot.texture = _component("armory_nav_dot")
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.stretch_mode = TextureRect.STRETCH_SCALE
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(dot, Rect2(324 + category_index * 30, 604, 10, 10))
		category_layer.add_child(dot)


func _build_left_rail() -> void:
	var rail := Control.new()
	rail.name = "UtilityRail"
	_set_rect(rail, Rect2(0, 0, 160, 640))
	add_child(rail)

	var utility_rows := [
		{"name": "ItemsButton", "label": "ITEMS", "y": 189.0},
		{"name": "AmmoButton", "label": "AMMO", "y": 289.0},
		{"name": "GoldButton", "label": "GOLD", "y": 389.0},
	]
	for row: Dictionary in utility_rows:
		var button := Button.new()
		button.name = str(row.name)
		button.text = tr(str(row.label))
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", CYAN)
		button.add_theme_stylebox_override("normal", _texture_style("armory_side_button", Color.WHITE))
		button.add_theme_stylebox_override("hover", _texture_style("armory_side_button", Color(0.72, 1.0, 1.0)))
		button.add_theme_stylebox_override("pressed", _texture_style("armory_side_button", Color(0.52, 0.92, 1.0)))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_set_rect(button, Rect2(20, float(row.y), 88, 75))
		match str(row.label):
			"ITEMS":
				button.pressed.connect(func(): _select_category("gun", true))
			"AMMO":
				button.pressed.connect(_show_ammo_notice)
			"GOLD":
				button.pressed.connect(_show_gold_notice)
		rail.add_child(button)

	var active_flag := TextureRect.new()
	active_flag.name = "ItemsActiveFlag"
	active_flag.texture = _component("armory_side_flag")
	active_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	active_flag.stretch_mode = TextureRect.STRETCH_SCALE
	active_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(active_flag, Rect2(53, 197, 21, 21))
	rail.add_child(active_flag)

	loadout_label = _label("", 11, Color(0.58, 0.82, 0.88))
	loadout_label.visible = false
	_set_rect(loadout_label, Rect2(0, 0, 1, 1))
	rail.add_child(loadout_label)


func _build_preview() -> void:
	var preview_panel := Control.new()
	preview_panel.name = "EquipmentPreview"
	_set_rect(preview_panel, Rect2(150, 90, 540, 430))
	add_child(preview_panel)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "PreviewViewportContainer"
	viewport_container.stretch = true
	_set_rect(viewport_container, Rect2(0, 0, 540, 430))
	preview_panel.add_child(viewport_container)

	preview_viewport = SubViewport.new()
	preview_viewport.name = "PreviewViewport"
	preview_viewport.size = Vector2i(540, 430)
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
	camera.position = Vector3(0, 0.18, 4.8)
	camera.current = true
	preview_viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.15, 0), Vector3.UP)

	preview_root = Node3D.new()
	preview_root.name = "Turntable"
	preview_viewport.add_child(preview_root)

	preview_caption = _label("", 16, Color.WHITE)
	preview_caption.visible = false
	preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	preview_caption.add_theme_constant_override("shadow_offset_x", 2)
	preview_caption.add_theme_constant_override("shadow_offset_y", 2)
	_set_rect(preview_caption, Rect2(30, 382, 480, 34))
	preview_panel.add_child(preview_caption)


func _build_item_carousel() -> void:
	var carousel_panel := Control.new()
	carousel_panel.name = "EquipmentCarousel"
	# UISliderAvatar uses a 600x135 clip with five 120px cells centred on x=400.
	_set_rect(carousel_panel, Rect2(100, 273, 600, 154))
	add_child(carousel_panel)

	item_scroll = ScrollContainer.new()
	item_scroll.name = "ItemScroll"
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	item_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	item_scroll.gui_input.connect(_on_item_carousel_input)
	_set_rect(item_scroll, Rect2(0, 0, 600, 135))
	carousel_panel.add_child(item_scroll)
	# Unity's UIScroller is gesture-only. Keep Godot's internal scrollbar fully
	# non-visual while retaining programmatic centring and touch drag support.
	var horizontal_bar := item_scroll.get_h_scroll_bar()
	horizontal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_bar.self_modulate = Color(1, 1, 1, 0)
	horizontal_bar.custom_minimum_size = Vector2.ZERO

	item_row = HBoxContainer.new()
	item_row.name = "ItemRow"
	item_row.add_theme_constant_override("separation", 10)
	item_scroll.add_child(item_row)

	preview_counter = _label("", 11, Color(0.48, 0.8, 0.86))
	preview_counter.visible = false
	preview_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(preview_counter, Rect2(0, 136, 600, 18))
	carousel_panel.add_child(preview_counter)

	item_dots_layer = Control.new()
	item_dots_layer.name = "ItemPositionDots"
	item_dots_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(item_dots_layer, Rect2(177, 86, 450, 18))
	add_child(item_dots_layer)


func _build_comparison_stats() -> void:
	# StoreUI.Create positions the authored HP/POW/SPD titles at y=106/146/186
	# and their rails at y=126/166/206 on the original 960x640 canvas.  These
	# are overall loadout comparisons; item-specific properties remain in the
	# description panel below, as they do in the Unity screen.
	var comparison := Control.new()
	comparison.name = "OverallComparison"
	comparison.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(comparison, Rect2(706, 104, 240, 130))
	add_child(comparison)
	for index in range(3):
		var key: String = str(["hp", "pow", "spd"][index])
		var row := Control.new()
		row.name = "%sComparison" % key.to_upper()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(row, Rect2(0, 2 + index * 40, 240, 34))
		comparison.add_child(row)

		var title := TextureRect.new()
		title.name = "AuthoredTitle"
		title.texture = _component("armory_stat_%s_title" % key)
		title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title.stretch_mode = TextureRect.STRETCH_SCALE
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(title, Rect2(0, 0, 240, 18))
		row.add_child(title)

		var value_label := _label("0", 12, DESCRIPTION)
		value_label.name = "Value"
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_set_rect(value_label, Rect2(64, -2, 106, 22))
		row.add_child(value_label)
		var delta_label := _label("", 11, DESCRIPTION)
		delta_label.name = "Delta"
		delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		delta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_set_rect(delta_label, Rect2(168, -2, 62, 22))
		row.add_child(delta_label)

		var meter := Control.new()
		meter.name = "AuthoredMeter"
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(meter, Rect2(6, 22, 214, 12))
		row.add_child(meter)
		var rail := TextureRect.new()
		rail.name = "Rail"
		rail.texture = _component("armory_stat_rail")
		rail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rail.stretch_mode = TextureRect.STRETCH_SCALE
		rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(rail, Rect2(0, 0, 214, 12))
		meter.add_child(rail)

		# Delta is drawn first and the current/selected value over it, matching
		# StoreUI.DrawComparsion's cyan/orange/green clipped layers.
		var gain_clip := _comparison_fill(meter, "Gain", "armory_stat_%s_gain" % key)
		var loss_clip := _comparison_fill(meter, "Loss", "armory_stat_%s_loss" % key)
		var value_clip := _comparison_fill(meter, "Selected", "armory_stat_%s_fill" % key)
		comparison_rows.append({
			"value": value_label,
			"delta": delta_label,
			"gain": gain_clip,
			"loss": loss_clip,
			"selected": value_clip,
		})


func _comparison_fill(parent: Control, node_name: String, component_name: String) -> Control:
	var clip := Control.new()
	clip.name = node_name
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(clip, Rect2(2, 1, 0, 10))
	parent.add_child(clip)
	var texture_rect := TextureRect.new()
	texture_rect.texture = _component(component_name)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(texture_rect, Rect2(0, 0, 210, 10))
	clip.add_child(texture_rect)
	return clip


func _build_details() -> void:
	var detail_panel := Control.new()
	detail_panel.name = "EquipmentDetails"
	_set_rect(detail_panel, Rect2(704, 240, 232, 374))
	add_child(detail_panel)
	var detail_art := TextureRect.new()
	detail_art.name = "RecoveredDetailFrame"
	detail_art.texture = _component("armory_detail_panel")
	detail_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_art.stretch_mode = TextureRect.STRETCH_SCALE
	detail_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(detail_art, Rect2(0, 0, 232, 374))
	detail_panel.add_child(detail_art)

	name_label = _label("", 18, TEAL)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_rect(name_label, Rect2(22, 8, 188, 26))
	detail_panel.add_child(name_label)
	state_label = _label("", 12, Color.WHITE)
	_set_rect(state_label, Rect2(12, 34, 208, 20))
	detail_panel.add_child(state_label)
	meta_label = _label("", 10, Color(0.58, 0.78, 0.84))
	meta_label.visible = false
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_rect(meta_label, Rect2(12, 54, 208, 18))
	detail_panel.add_child(meta_label)

	stats_text = RichTextLabel.new()
	stats_text.bbcode_enabled = true
	stats_text.fit_content = false
	stats_text.scroll_active = false
	stats_text.add_theme_font_size_override("normal_font_size", 12)
	_set_rect(stats_text, Rect2(62, 58, 160, 88))
	detail_panel.add_child(stats_text)

	description_text = RichTextLabel.new()
	description_text.bbcode_enabled = true
	description_text.fit_content = false
	description_text.scroll_active = true
	description_text.add_theme_font_size_override("normal_font_size", 11)
	description_text.add_theme_color_override("default_color", DESCRIPTION)
	_set_rect(description_text, Rect2(10, 146, 212, 136))
	detail_panel.add_child(description_text)

	price_label = _label("", 13, GOLD_COLOR)
	# Unity draws the numeric price directly inside the compact action plate.
	# Keep this compatibility label populated for callers, but do not render a
	# second price line above the original button.
	price_label.visible = false
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(price_label, Rect2(12, 254, 208, 23))
	detail_panel.add_child(price_label)

	slot_picker = OptionButton.new()
	slot_picker.name = "LoadoutSlotPicker"
	slot_picker.add_theme_font_size_override("font_size", 10)
	slot_picker.item_selected.connect(func(index: int):
		selected_slot = index
		_refresh_details()
	)
	_set_rect(slot_picker, Rect2(12, 250, 208, 30))
	detail_panel.add_child(slot_picker)

	action_button = Button.new()
	action_button.name = "PrimaryAction"
	action_button.add_theme_font_size_override("font_size", 14)
	action_button.add_theme_color_override("font_color", Color.WHITE)
	action_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	action_button.add_theme_stylebox_override("normal", _recovered_button_style("armory_action_normal", Color.WHITE))
	action_button.add_theme_stylebox_override("hover", _recovered_button_style("armory_action_normal", Color(0.82, 1.0, 1.0)))
	action_button.add_theme_stylebox_override("pressed", _recovered_button_style("armory_action_pressed", Color.WHITE))
	action_button.add_theme_stylebox_override("disabled", _recovered_button_style("armory_action_disabled", Color(0.72, 0.72, 0.72)))
	action_button.pressed.connect(_perform_primary_action)
	_set_rect(action_button, Rect2(43, 286, 150, 58))
	detail_panel.add_child(action_button)

	notice_label = _label("", 10, Color(1.0, 0.55, 0.2))
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_rect(notice_label, Rect2(8, 355, 216, 17))
	detail_panel.add_child(notice_label)


func _build_bottom_bar() -> void:
	var bar := Control.new()
	bar.name = "OriginalNavigationBar"
	_set_rect(bar, Rect2(0, 0, 960, 80))
	add_child(bar)
	var bar_art := TextureRect.new()
	bar_art.texture = _component("armory_nav_bar")
	bar_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar_art.stretch_mode = TextureRect.STRETCH_SCALE
	bar_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(bar_art, Rect2(0, 0, 960, 80))
	bar.add_child(bar_art)

	var back := TextureButton.new()
	back.name = "BackButton"
	back.texture_normal = _component("armory_back_normal")
	back.texture_hover = _component("armory_back_normal")
	back.texture_pressed = _component("armory_back_pressed")
	back.ignore_texture_size = true
	back.stretch_mode = TextureButton.STRETCH_SCALE
	back.pressed.connect(func():
		AudioDirector.play_ui("back")
		closed.emit()
	)
	_set_rect(back, Rect2(0, 1, 125, 78))
	bar.add_child(back)

	screen_title = _label("", 25, CYAN)
	screen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(screen_title, Rect2(138, 1, 559, 78))
	bar.add_child(screen_title)

	currency_label = _label("", 11, Color(0.72, 1.0, 1.0))
	currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(currency_label, Rect2(731, 5, 145, 69))
	bar.add_child(currency_label)

	var rank_badge := TextureRect.new()
	rank_badge.name = "RankBadge"
	rank_badge.texture = _component("main_nav_toggle")
	rank_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rank_badge.stretch_mode = TextureRect.STRETCH_SCALE
	rank_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# This is the collapsed NavigationMenuUI tab, which remains present over
	# StoreUI in the original game.  Preserve its actual off-screen origin.
	_set_rect(rank_badge, Rect2(840, -14, 120, 110))
	bar.add_child(rank_badge)
	var rank_icon := TextureRect.new()
	rank_icon.name = "RankIcon"
	rank_icon.texture = _component("main_rank_%02d" % clampi(GameState.get_rank_id(), 0, 11))
	rank_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rank_icon.stretch_mode = TextureRect.STRETCH_SCALE
	rank_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(rank_icon, Rect2(40, 15, 64, 64))
	rank_badge.add_child(rank_icon)


func set_mode(next_mode: String, play_sound := true) -> void:
	mode = "customize" if next_mode == "customize" else "store"
	if play_sound:
		AudioDirector.play_ui("accept")
	for key in mode_buttons:
		var button := mode_buttons[key] as Button
		var key_mode := "customize" if str(key).ends_with("customize") else "store"
		_style_mode_button(button, key_mode == mode)
	if is_instance_valid(screen_title):
		screen_title.text = tr("CUSTOMIZE" if mode == "customize" else "STORE")
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
	_layout_category_buttons()
	if play_sound:
		AudioDirector.play_ui("switch", -5.0)
	_rebuild_item_row()
	_select_preferred_item(false)


func _layout_category_buttons() -> void:
	if not is_instance_valid(category_layer) or not category_buttons.has(selected_category):
		return
	var selected_index := 0
	for index in range(CATEGORIES.size()):
		if str(CATEGORIES[index].key) == selected_category:
			selected_index = index
			break
	for index in range(CATEGORIES.size()):
		var key := str(CATEGORIES[index].key)
		var button := category_buttons.get(key) as Button
		if button == null:
			continue
		var relative := index - selected_index
		if relative > 3:
			relative -= CATEGORIES.size()
		elif relative < -2:
			relative += CATEGORIES.size()
		var active := index == selected_index
		# Exact UISliderTag spacing is 90px; each step from centre scales by 20%.
		var distance_scale := maxf(0.2, 1.0 - absf(float(relative)) * 0.2)
		var button_size := Vector2(120, 99) * distance_scale
		var center := Vector2(402.0 + relative * 90.0, 543.5)
		_set_rect(button, Rect2(center - button_size * 0.5, button_size))
		button.add_theme_constant_override("icon_max_width", roundi(64.0 * distance_scale))
		button.add_theme_stylebox_override("normal", _texture_style("armory_category_frame", Color.WHITE) if active else _empty_style())
		button.modulate = Color.WHITE if active else Color(0.64, 0.74, 0.76, 0.9)
		button.z_index = 2 if active else 1
	for index in range(CATEGORIES.size()):
		var dot := category_layer.get_node_or_null("CategoryDot%02d" % index) as TextureRect
		if dot == null:
			continue
		var active := index == selected_index
		var dot_size := 18.0 if active else 10.0
		dot.texture = _component("armory_nav_selected" if active else "armory_nav_dot")
		_set_rect(dot, Rect2(324 + index * 30 - (dot_size - 10.0) * 0.5, 604 - (dot_size - 10.0) * 0.5, dot_size, dot_size))


func _show_ammo_notice() -> void:
	AudioDirector.play_ui("switch", -5.0)
	if is_instance_valid(notice_label):
		notice_label.text = tr("AMMO REFILL SERVICE IS NOT REQUIRED IN OFFLINE PLAY")


func _show_gold_notice() -> void:
	AudioDirector.play_ui("switch", -5.0)
	if is_instance_valid(notice_label):
		notice_label.text = tr("ONLINE GOLD SERVICE UNAVAILABLE")


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
		button.custom_minimum_size = Vector2(110, 135)
		button.add_theme_font_size_override("font_size", 10)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var state := _get_item_state(item_key)
		if selected_category == "gun":
			var weapon: Dictionary = GameState.WEAPONS[item_key]
			button.icon = Atlas.weapon_icon(int(weapon.id))
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 78)
			button.text = ""
			button.tooltip_text = "%s • %s" % [str(weapon.name), tr(state.to_upper())]
		else:
			var item: Dictionary = GameState.ARMOR_ITEMS[item_key]
			button.text = _short_item_name(str(item.name))
			button.tooltip_text = "%s • %s" % [str(item.name), tr(state.to_upper())]
		_style_item_card(button, item_key == selected_item_key, state)
		button.gui_input.connect(_on_item_carousel_input)
		button.pressed.connect(_select_item.bind(item_key, true))
		item_row.add_child(button)
	preview_counter.text = tr("%d ITEMS") % ids.size()
	_rebuild_item_dots(ids.size())


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
	_rebuild_item_dots(ids.size())
	call_deferred("_ensure_item_visible", item_key)


func _ensure_item_visible(item_key: String) -> void:
	if not is_instance_valid(item_scroll) or not is_instance_valid(item_row):
		return
	for child in item_row.get_children():
		if child is Control and str(child.get_meta("item_key", "")) == item_key and item_scroll.is_ancestor_of(child):
			var card := child as Control
			var target := roundi(card.position.x + card.size.x * 0.5 - item_scroll.size.x * 0.5)
			item_scroll.scroll_horizontal = maxi(0, target)
			return


func _on_item_carousel_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			item_swipe_distance = 0.0
		else:
			_commit_item_swipe()
	elif event is InputEventScreenDrag:
		item_swipe_distance += event.relative.x
		item_scroll.scroll_horizontal -= roundi(event.relative.x)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		item_mouse_dragging = event.pressed
		if event.pressed:
			item_swipe_distance = 0.0
		else:
			_commit_item_swipe()
	elif event is InputEventMouseMotion and item_mouse_dragging:
		item_swipe_distance += event.relative.x
		item_scroll.scroll_horizontal -= roundi(event.relative.x)


func _commit_item_swipe() -> void:
	if absf(item_swipe_distance) < SWIPE_THRESHOLD:
		item_swipe_distance = 0.0
		return
	var ids := _get_category_ids()
	if ids.is_empty():
		return
	var index := ids.find(selected_item_key)
	if index < 0:
		index = 0
	var direction := 1 if item_swipe_distance < 0.0 else -1
	item_swipe_distance = 0.0
	_select_item(ids[posmod(index + direction, ids.size())], true)


func _on_category_carousel_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			category_swipe_distance = 0.0
		else:
			_commit_category_swipe()
	elif event is InputEventScreenDrag:
		category_swipe_distance += event.relative.x
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		category_mouse_dragging = event.pressed
		if event.pressed:
			category_swipe_distance = 0.0
		else:
			_commit_category_swipe()
	elif event is InputEventMouseMotion and category_mouse_dragging:
		category_swipe_distance += event.relative.x


func _commit_category_swipe() -> void:
	if absf(category_swipe_distance) < SWIPE_THRESHOLD:
		category_swipe_distance = 0.0
		return
	var selected_index := 0
	for index in range(CATEGORIES.size()):
		if str(CATEGORIES[index].key) == selected_category:
			selected_index = index
			break
	var direction := 1 if category_swipe_distance < 0.0 else -1
	category_swipe_distance = 0.0
	_select_category(str(CATEGORIES[posmod(selected_index + direction, CATEGORIES.size())].key), true)


func _rebuild_item_dots(item_count: int) -> void:
	if not is_instance_valid(item_dots_layer):
		return
	for child in item_dots_layer.get_children():
		child.free()
	if item_count <= 0:
		return
	var spacing := minf(30.0, 450.0 / float(item_count))
	var width := (item_count - 1) * spacing + 10.0
	var start_x := (450.0 - width) * 0.5
	var selected_index := _get_category_ids().find(selected_item_key)
	for index in range(item_count):
		var selected := index == selected_index
		var dot_size := 18.0 if selected else 10.0
		var dot := TextureRect.new()
		dot.texture = _component("armory_nav_selected" if selected else "armory_nav_dot")
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.stretch_mode = TextureRect.STRETCH_SCALE
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(dot, Rect2(start_x + index * spacing - (dot_size - 10.0) * 0.5, (18.0 - dot_size) * 0.5, dot_size, dot_size))
		item_dots_layer.add_child(dot)


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
	_refresh_comparison_stats()
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


func _refresh_comparison_stats() -> void:
	if comparison_rows.size() != 3:
		return
	var current_skills: Dictionary = GameState.get_armor_skills()
	var preview_skills := _preview_armor_skills(current_skills)
	var current_weapon := _comparison_weapon(false)
	var preview_weapon := _comparison_weapon(true)
	var current_values := [
		float(current_skills.get("hp", 0.0)),
		_comparison_power(current_weapon, current_skills),
		maxf(3.5, 7.0 + float(current_skills.get("speed_boost", 0.0))),
	]
	var preview_values := [
		float(preview_skills.get("hp", 0.0)),
		_comparison_power(preview_weapon, preview_skills),
		maxf(3.5, 7.0 + float(preview_skills.get("speed_boost", 0.0))),
	]
	for index in range(3):
		_set_comparison_row(index, float(current_values[index]), float(preview_values[index]))


func _comparison_weapon(use_preview: bool) -> Dictionary:
	var weapon_key := GameState.selected_weapon
	if selected_slot >= 0 and selected_slot < GameState.battle_weapons.size():
		weapon_key = GameState.battle_weapons[selected_slot]
	if use_preview and selected_category == "gun" and GameState.WEAPONS.has(selected_item_key):
		weapon_key = selected_item_key
	return GameState.WEAPONS.get(weapon_key, {})


func _preview_armor_skills(current_skills: Dictionary) -> Dictionary:
	var preview: Dictionary = current_skills.duplicate(true)
	if selected_category == "gun" or not GameState.ARMOR_ITEMS.has(selected_item_key):
		return preview
	var current_key := GameState.get_equipped_armor_key(selected_category)
	var current_item: Dictionary = GameState.ARMOR_ITEMS.get(current_key, {})
	var selected_item: Dictionary = GameState.ARMOR_ITEMS[selected_item_key]
	var current_set_id := GameState.get_equipped_set_id()
	if current_set_id >= 0 and GameState.ARMOR_SET_BONUSES.has(current_set_id):
		_merge_skill_delta(preview, GameState.ARMOR_SET_BONUSES[current_set_id].skills, -1.0)
	if not current_item.is_empty():
		_merge_skill_delta(preview, current_item.skills, -1.0)
	_merge_skill_delta(preview, selected_item.skills, 1.0)
	var preview_set_id := _preview_full_set_id()
	if preview_set_id >= 0 and GameState.ARMOR_SET_BONUSES.has(preview_set_id):
		_merge_skill_delta(preview, GameState.ARMOR_SET_BONUSES[preview_set_id].skills, 1.0)
	return preview


func _preview_full_set_id() -> int:
	var set_id := -1
	for part_key: String in ["head", "body", "arms", "legs"]:
		var armor_key := selected_item_key if selected_category == part_key else GameState.get_equipped_armor_key(part_key)
		if not GameState.ARMOR_ITEMS.has(armor_key):
			return -1
		var part_set_id := int(GameState.ARMOR_ITEMS[armor_key].set_id)
		if set_id < 0:
			set_id = part_set_id
		elif part_set_id != set_id:
			return -1
	return set_id


func _merge_skill_delta(target: Dictionary, source: Dictionary, multiplier: float) -> void:
	for skill_key in source:
		target[skill_key] = float(target.get(skill_key, 0.0)) + float(source[skill_key]) * multiplier


func _comparison_power(weapon: Dictionary, skills: Dictionary) -> float:
	if weapon.is_empty():
		return 0.0
	var multiplier := 1.0 + float(skills.get("attack_boost", 0.0)) + float(skills.get("team_attack_boost", 0.0))
	return float(weapon.get("damage", 0.0)) * maxf(0.0, multiplier)


func _set_comparison_row(index: int, current_value: float, preview_value: float) -> void:
	var row: Dictionary = comparison_rows[index]
	var value_label := row.value as Label
	var delta_label := row.delta as Label
	value_label.text = "%.1f" % preview_value if index == 2 else _format_price(roundi(preview_value))
	var delta := preview_value - current_value
	if absf(delta) < 0.01:
		delta_label.text = ""
	else:
		var delta_text := "%.1f" % absf(delta) if index == 2 else _format_price(absi(roundi(delta)))
		delta_label.text = "%s%s" % ["+" if delta > 0.0 else "-", delta_text]
		delta_label.add_theme_color_override("font_color", Color(0.25, 1.0, 0.45) if delta > 0.0 else Color(1.0, 0.3, 0.25))

	var current_width := _comparison_meter_width(index, current_value)
	var preview_width := _comparison_meter_width(index, preview_value)
	var gain_clip := row.gain as Control
	var loss_clip := row.loss as Control
	var selected_clip := row.selected as Control
	gain_clip.size.x = 0.0
	loss_clip.size.x = 0.0
	selected_clip.size.x = preview_width
	if preview_width > current_width:
		gain_clip.size.x = preview_width
		selected_clip.size.x = current_width
	elif preview_width < current_width:
		loss_clip.size.x = current_width


func _comparison_meter_width(index: int, value: float) -> float:
	if index == 2:
		return clampf(value * 200.0 / 15.0 + 10.0, 0.0, 210.0)
	var normalized := value / 10.0 if index == 0 else value
	if normalized <= 0.0:
		return 0.0
	return clampf(45.0 * pow(normalized, 0.2) - 63.0, 0.0, 210.0)


func _refresh_weapon_details() -> void:
	var weapon: Dictionary = GameState.WEAPONS.get(selected_item_key, {})
	if weapon.is_empty():
		return
	var state := _get_item_state(selected_item_key)
	name_label.text = str(weapon.name)
	name_label.add_theme_color_override("font_color", Color(weapon.color))
	state_label.text = tr("UNLOCK: RANK %d") % (_selected_unlock_rank() + 1) if state == "locked" else ""
	state_label.add_theme_color_override("font_color", _state_color(state))
	meta_label.text = ""
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
	state_label.text = tr("UNLOCK: RANK %d") % (_selected_unlock_rank() + 1) if state == "locked" else ""
	state_label.add_theme_color_override("font_color", _state_color(state))
	var set_name := _armor_set_name(int(item.set_id))
	meta_label.text = set_name if mode == "customize" and not set_name.is_empty() else ""
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
	if mode == "store":
		if state == "available":
			action_button.text = "%s\n%s" % [_selected_price_token(), tr("BUY")]
		elif state == "locked":
			action_button.text = "%s %d\n%s" % [tr("RANK"), _selected_unlock_rank() + 1, tr("REQUIRED")]


func _selected_price_token() -> String:
	var item: Dictionary = GameState.WEAPONS.get(selected_item_key, {}) if selected_category == "gun" else GameState.ARMOR_ITEMS.get(selected_item_key, {})
	if int(item.get("mithril", 0)) > 0:
		return "#%s" % _format_price(int(item.mithril))
	return "$%s" % _format_price(int(item.get("price", 0)))


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
		currency_label.text = "%s\n%s\n%s" % [
			_format_price(GameState.mithril),
			_format_price(GameState.credits),
			"0",
		]


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
	if not _build_equipped_avatar_for_weapon(weapon, mesh):
		if mesh == null:
			_build_fallback_weapon(Color(weapon.color))
		else:
			var preview := MeshInstance3D.new()
			preview.name = "SelectedWeapon"
			preview.mesh = mesh
			_normalize_preview_mesh(preview, 3.2, Color(weapon.color), 0.04, int(weapon.id))
			preview_root.add_child(preview)


func _build_equipped_avatar_for_weapon(weapon: Dictionary, weapon_mesh: Mesh) -> bool:
	if not ResourceLoader.exists(ARMOR_AVATAR_PATH):
		return false
	var avatar_scene := load(ARMOR_AVATAR_PATH) as PackedScene
	if avatar_scene == null:
		return false
	var avatar := avatar_scene.instantiate() as Node3D
	if avatar == null:
		return false
	var display := Node3D.new()
	display.name = "StoreAvatarDisplay"
	preview_root.add_child(display)
	avatar.name = "RecoveredStoreAvatar"
	avatar.rotation_degrees.y = -90.0
	display.add_child(avatar)
	_apply_preview_armor_visibility(avatar)
	if weapon_mesh != null:
		_attach_preview_weapon(avatar, weapon, weapon_mesh)
	_play_preview_idle(avatar, str(weapon.get("animation", "rifle")))
	if not _normalize_avatar_preview(display, avatar, 4.55):
		display.queue_free()
		return false
	return true


func _attach_preview_weapon(avatar: Node3D, weapon: Dictionary, weapon_mesh: Mesh) -> void:
	var skeleton: Skeleton3D = null
	for candidate in avatar.find_children("*", "Skeleton3D", true, false):
		skeleton = candidate as Skeleton3D
		break
	if skeleton == null:
		return
	var weapon_id := int(weapon.id)
	var bone_name := "l hand gun" if weapon_id in [22, 29, 44] else "r hand gun"
	if skeleton.find_bone(bone_name) < 0:
		bone_name = "Bip01 R Hand"
	if skeleton.find_bone(bone_name) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "StoreWeaponSocket"
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	var mount := Node3D.new()
	mount.rotation_degrees.x = -90.0
	attachment.add_child(mount)
	var preview := MeshInstance3D.new()
	preview.name = "SelectedWeapon"
	preview.mesh = weapon_mesh
	_prepare_preview_materials(preview, Color(weapon.color), 0.04, weapon_id)
	var kind := str(weapon.get("kind", "hitscan"))
	var target_length := 1.25
	if kind in ["shotgun", "shockwave"]:
		target_length = 1.3
	elif kind in ["rocket", "grenade", "fly_grenade"]:
		target_length = 1.42
	elif kind in ["sniper", "reflection"]:
		target_length = 1.62
	elif kind == "sword":
		target_length = 1.55
	var bounds := weapon_mesh.get_aabb()
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	preview.scale = Vector3.ONE * (target_length / longest if longest > 0.001 else 1.0)
	var authored_basis := Basis.from_euler(_preview_weapon_rotation(weapon_id) * (PI / 180.0))
	preview.basis = mount.basis.inverse() * authored_basis.scaled(preview.scale)
	mount.add_child(preview)


func _preview_weapon_rotation(weapon_id: int) -> Vector3:
	# WeaponResourceConfig.RotateGun cases used by the original player preview.
	if weapon_id in [22, 23, 24, 25, 28, 31, 32, 39, 41, 45, 46]:
		return Vector3.ZERO
	if weapon_id == 36:
		return Vector3(0.0, 90.0, -90.0)
	if weapon_id == 44:
		return Vector3(90.0, 0.0, 0.0)
	return Vector3(-90.0, 0.0, 0.0)


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


func _play_preview_idle(avatar: Node3D, weapon_pose := "rifle") -> void:
	var pose := weapon_pose
	if pose == "grenade_launcher":
		pose = "shotgun"
	elif pose == "laser":
		pose = "rifle"
	elif pose == "BLACKSTARS":
		pose = "bazinga"
	var requested := "idle_%s" % pose
	for candidate in avatar.find_children("*", "AnimationPlayer", true, false):
		var animation_player := candidate as AnimationPlayer
		var idle_name := requested if animation_player.has_animation(requested) else "idle_rifle"
		if animation_player.has_animation(idle_name):
			var idle_animation := animation_player.get_animation(idle_name)
			if idle_animation != null:
				idle_animation.loop_mode = Animation.LOOP_LINEAR
			animation_player.play(idle_name)
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
	# Unity hides the centre UISliderAvatar duplicate because the main avatar is
	# already wearing/holding that selection. Neighbours float without cards.
	button.add_theme_stylebox_override("normal", _empty_style())
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.04, 0.23, 0.26, 0.22), CYAN, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.08, 0.32, 0.35, 0.28), Color.WHITE, 1))
	button.add_theme_color_override("font_color", state_color)
	button.modulate = Color(1, 1, 1, 0) if selected else (Color.WHITE if state != "locked" else Color(0.48, 0.52, 0.54, 0.72))


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


func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _texture_style(component_name: String, tint := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _component(component_name)
	style.modulate_color = tint
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
