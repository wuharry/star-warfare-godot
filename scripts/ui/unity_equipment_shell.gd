class_name UnityEquipmentShell
extends Control

signal closed

const Atlas = preload("res://scripts/ui/original_atlas.gd")
const PropsCatalogData = preload("res://scripts/core/props_catalog.gd")
const AdditivePreviewShader = preload("res://scripts/ui/store_additive_preview.gdshader")
const COMPONENT_DIR := "res://assets/ui/components/"
const ARMOR_THUMBNAIL_DIR := "res://assets/ui/armor_thumbnails/"
const DESIGN_SIZE := Vector2(960.0, 640.0)
const DESKTOP_DESIGN_SIZE := Vector2(1138.0, 640.0)
const DESKTOP_X_OFFSET := -89.0
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
const SUPPLY_CATEGORIES := [
	{"key": "health", "label": "HEALTH"},
	{"key": "aid", "label": "AID-KIT"},
	{"key": "assist", "label": "ASSIST"},
]

var requested_mode := "store"
var mode := "store"
var desktop_layout := false
var selected_category := "gun"
var selected_section := "equipment"
var selected_supply_category := "health"
var selected_item_key := ""
var selected_slot := 0
var weapon_filter := ""

var item_scroll: ScrollContainer
var item_row: GridContainer
var category_buttons: Dictionary = {}
var section_buttons: Dictionary = {}
var desktop_equipment_buttons: Dictionary = {}
var supply_buttons: Dictionary = {}
var weapon_filter_picker: OptionButton
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
var supply_preview_art: TextureRect
var preview_tween: Tween
var screen_title: Label
var category_layer: Control
var catalog_panel: Control
var detail_panel: Control
var comparison_title: Label
var comparison_rows: Array[Dictionary] = []
var comparison_panel: Control


func setup(start_mode: String, use_desktop_layout := false) -> void:
	requested_mode = "customize" if start_mode == "customize" else "store"
	desktop_layout = use_desktop_layout


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_background()
	_build_catalog()
	_build_details()
	_build_preview()
	_build_comparison_stats()
	_build_bottom_bar()
	apply_layout(desktop_layout)
	if not GameState.store_changed.is_connected(_on_store_changed):
		GameState.store_changed.connect(_on_store_changed)
	if not GameState.loadout_changed.is_connected(_on_store_changed):
		GameState.loadout_changed.connect(_on_store_changed)
	if not GameState.armor_changed.is_connected(_on_armor_changed):
		GameState.armor_changed.connect(_on_armor_changed)
	set_mode(requested_mode, false)


func _exit_tree() -> void:
	if preview_tween and preview_tween.is_valid():
		preview_tween.kill()
	preview_tween = null


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT, KEY_A:
			_step_item(-1)
		KEY_RIGHT, KEY_D:
			_step_item(1)
		KEY_Q:
			_step_category(-1)
		KEY_E:
			_step_category(1)
		_:
			return
	get_viewport().set_input_as_handled()


func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "UnityStoreBackdrop"
	background.texture = _component("armory_background")
	background.modulate = Color(0.34, 0.42, 0.45)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_catalog() -> void:
	catalog_panel = Panel.new()
	catalog_panel.name = "EquipmentCatalog"
	catalog_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.045, 0.052, 0.92), Color(0.16, 0.28, 0.3), 4))
	add_child(catalog_panel)
	for section_key in ["equipment", "supplies"]:
		var button := Button.new()
		button.name = "%sSection" % section_key.capitalize()
		button.text = tr("GEAR" if section_key == "equipment" else "SUPPLY")
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_select_desktop_section.bind(section_key))
		section_buttons[section_key] = button
		catalog_panel.add_child(button)
	category_layer = Control.new()
	category_layer.name = "CategoryTabs"
	category_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	catalog_panel.add_child(category_layer)
	for index in range(CATEGORIES.size()):
		var category: Dictionary = CATEGORIES[index]
		var key := str(category.key)
		var button := Button.new()
		button.name = "%sTab" % key.capitalize()
		button.tooltip_text = tr(str(category.label))
		button.pressed.connect(_select_category.bind(key, true))
		category_layer.add_child(button)
		var art := TextureRect.new()
		art.name = "CategoryArt"
		art.texture = _component("armory_category_%02d" % index)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(art)
		var caption := _label(tr(str(category.label)), 10, Color(0.75, 0.87, 0.89))
		caption.name = "CategoryName"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(caption)
		category_buttons[key] = button
		desktop_equipment_buttons[key] = button
	for category: Dictionary in SUPPLY_CATEGORIES:
		var key := str(category.key)
		var button := Button.new()
		button.name = "%sSupply" % key.capitalize()
		button.text = tr(str(category.label))
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_select_supply_category.bind(key, true))
		supply_buttons[key] = button
		catalog_panel.add_child(button)
	weapon_filter_picker = OptionButton.new()
	weapon_filter_picker.name = "WeaponTypeFilter"
	weapon_filter_picker.add_theme_font_size_override("font_size", 12)
	for filter_key in ["ALL", "RIFLE", "SHOTGUN", "HEAVY", "SPECIAL", "MELEE"]:
		weapon_filter_picker.add_item(tr(filter_key))
		weapon_filter_picker.set_item_metadata(weapon_filter_picker.item_count - 1, filter_key)
	weapon_filter_picker.item_selected.connect(func(index: int): set_weapon_filter(str(weapon_filter_picker.get_item_metadata(index))))
	_style_desktop_picker(weapon_filter_picker)
	catalog_panel.add_child(weapon_filter_picker)
	preview_counter = _label("", 11, Color(0.53, 0.71, 0.74))
	preview_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	catalog_panel.add_child(preview_counter)
	item_scroll = ScrollContainer.new()
	item_scroll.name = "ItemScroll"
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_scroll.follow_focus = true
	item_scroll.scroll_deadzone = 12
	catalog_panel.add_child(item_scroll)
	item_row = GridContainer.new()
	item_row.name = "ItemGrid"
	item_row.columns = 3
	item_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_row.add_theme_constant_override("h_separation", 8)
	item_row.add_theme_constant_override("v_separation", 8)
	item_scroll.add_child(item_row)
	for direction in [-1, 1]:
		var arrow := _desktop_carousel_arrow("PreviousItem" if direction < 0 else "NextItem", "‹" if direction < 0 else "›", direction)
		catalog_panel.add_child(arrow)
	var hint := _label(tr("A / D  SELECT"), 10, Color(0.53, 0.71, 0.74))
	hint.name = "SelectionHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	catalog_panel.add_child(hint)
	loadout_label = _label("", 11, Color.WHITE)
	loadout_label.visible = false
	catalog_panel.add_child(loadout_label)


func _refresh_filter_buttons() -> void:
	_refresh_desktop_navigation()


func _refresh_desktop_navigation() -> void:
	for key in section_buttons:
		_style_tab(section_buttons[key], str(key) == selected_section)
	for key in category_buttons:
		_style_tab(category_buttons[key], str(key) == selected_category)
	for key in supply_buttons:
		var button := supply_buttons[key] as Button
		button.visible = selected_section == "supplies"
		_style_tab(button, str(key) == selected_supply_category)
	category_layer.visible = selected_section == "equipment"
	weapon_filter_picker.visible = selected_section == "equipment" and selected_category == "gun"
	for index in range(weapon_filter_picker.item_count):
		if str(weapon_filter_picker.get_item_metadata(index)) == ("ALL" if weapon_filter.is_empty() else weapon_filter):
			weapon_filter_picker.select(index)
			break
	if is_instance_valid(comparison_panel):
		comparison_panel.visible = selected_section == "equipment"
		comparison_title.visible = comparison_panel.visible


func _build_preview() -> void:
	var preview_panel := Control.new()
	preview_panel.name = "EquipmentPreview"
	var preview_rect := Rect2(10, 88, 400, 236)
	_set_rect(preview_panel, preview_rect)
	detail_panel.add_child(preview_panel)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "PreviewViewportContainer"
	viewport_container.stretch = true
	_set_rect(viewport_container, Rect2(0, 0, preview_rect.size.x, preview_rect.size.y))
	preview_panel.add_child(viewport_container)

	preview_viewport = SubViewport.new()
	preview_viewport.name = "PreviewViewport"
	preview_viewport.size = Vector2i(preview_rect.size)
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

	supply_preview_art = TextureRect.new()
	supply_preview_art.name = "SupplyPreviewArt"
	supply_preview_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	supply_preview_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	supply_preview_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	supply_preview_art.visible = false
	supply_preview_art.modulate = Color(0.86, 1.0, 1.0)
	var supply_size := 230.0 if desktop_layout else 250.0
	_set_rect(supply_preview_art, Rect2((preview_rect.size.x - supply_size) * 0.5, 54 if desktop_layout else 70, supply_size, supply_size))
	preview_panel.add_child(supply_preview_art)

	preview_caption = _label("", 16, Color.WHITE)
	preview_caption.visible = false
	preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	preview_caption.add_theme_constant_override("shadow_offset_x", 2)
	preview_caption.add_theme_constant_override("shadow_offset_y", 2)
	_set_rect(preview_caption, Rect2(30, 302 if desktop_layout else 382, preview_rect.size.x - 60, 34))
	preview_panel.add_child(preview_caption)


func _build_comparison_stats() -> void:
	# These three recovered meters compare the whole loadout. Keep them together
	# below the selected product; its own attributes appear next to the preview.
	comparison_panel = Control.new()
	comparison_panel.name = "OverallComparison"
	comparison_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(comparison_panel, Rect2(20, 366, 628, 40))
	detail_panel.add_child(comparison_panel)
	for index in range(3):
		var key: String = str(["hp", "pow", "spd"][index])
		var row := Control.new()
		row.name = "%sComparison" % key.to_upper()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(row, Rect2(0, 2 + index * 40, 240, 34))
		comparison_panel.add_child(row)

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

		# Keep the authored black rail, but reveal the entire available slot with
		# a restrained colour bed. On modern bright displays the original near-black
		# empty section otherwise disappears into the store background.
		var track_glow := TextureRect.new()
		track_glow.name = "TrackGlow"
		track_glow.texture = _component("armory_stat_%s_fill" % key)
		track_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		track_glow.stretch_mode = TextureRect.STRETCH_SCALE
		track_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track_glow.modulate = Color(1.0, 1.0, 1.0, 0.24)
		_set_rect(track_glow, Rect2(2, 1, 210, 10))
		meter.add_child(track_glow)

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
	detail_panel = Panel.new()
	detail_panel.name = "EquipmentDetails"
	detail_panel.add_theme_stylebox_override("panel", _frame_style("armory_detail_panel", Color(0.72, 0.85, 0.88)))
	add_child(detail_panel)
	name_label = _label("", 27, Color.WHITE)
	name_label.name = "ItemName"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_panel.add_child(name_label)
	state_label = _label("", 12, CYAN)
	state_label.name = "ItemState"
	detail_panel.add_child(state_label)
	meta_label = _label("", 11, Color(0.6, 0.75, 0.78))
	meta_label.name = "ItemMeta"
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_panel.add_child(meta_label)
	stats_text = RichTextLabel.new()
	stats_text.name = "ItemStats"
	stats_text.bbcode_enabled = true
	stats_text.scroll_active = true
	stats_text.add_theme_font_size_override("normal_font_size", 15)
	stats_text.add_theme_constant_override("line_separation", 5)
	detail_panel.add_child(stats_text)
	description_text = RichTextLabel.new()
	description_text.name = "ItemDescription"
	description_text.bbcode_enabled = true
	description_text.scroll_active = true
	description_text.add_theme_font_size_override("normal_font_size", 12)
	description_text.add_theme_color_override("default_color", Color(0.62, 0.77, 0.78))
	detail_panel.add_child(description_text)
	comparison_title = _label(tr("EQUIPMENT COMPARISON"), 11, Color(0.57, 0.73, 0.76))
	comparison_title.name = "ComparisonTitle"
	detail_panel.add_child(comparison_title)
	var divider := ColorRect.new()
	divider.name = "PurchaseDivider"
	divider.color = Color(0.22, 0.4, 0.43, 0.5)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_child(divider)
	price_label = _label("", 16, Color(1.0, 0.78, 0.3))
	price_label.name = "ItemPrice"
	price_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_panel.add_child(price_label)
	slot_picker = OptionButton.new()
	slot_picker.name = "LoadoutSlotPicker"
	slot_picker.add_theme_font_size_override("font_size", 12)
	slot_picker.add_theme_stylebox_override("normal", _panel_style(Color(0.02, 0.10, 0.13), Color(0.24, 0.65, 0.7), 2))
	slot_picker.add_theme_stylebox_override("hover", _panel_style(Color(0.04, 0.2, 0.23), CYAN, 2))
	slot_picker.add_theme_stylebox_override("pressed", _panel_style(Color(0.06, 0.28, 0.3), Color.WHITE, 2))
	slot_picker.item_selected.connect(func(index: int):
		selected_slot = index
		_refresh_details()
	)
	detail_panel.add_child(slot_picker)
	action_button = Button.new()
	action_button.name = "PrimaryAction"
	action_button.add_theme_font_size_override("font_size", 16)
	action_button.add_theme_color_override("font_color", Color.WHITE)
	action_button.add_theme_color_override("font_disabled_color", Color(0.55, 0.63, 0.65))
	action_button.add_theme_stylebox_override("normal", _recovered_button_style("armory_action_normal", Color.WHITE))
	action_button.add_theme_stylebox_override("hover", _recovered_button_style("armory_action_normal", Color(0.82, 1.0, 1.0)))
	action_button.add_theme_stylebox_override("pressed", _recovered_button_style("armory_action_pressed", Color.WHITE))
	action_button.add_theme_stylebox_override("disabled", _recovered_button_style("armory_action_disabled", Color(0.72, 0.72, 0.72)))
	action_button.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), CYAN, 3))
	action_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action_button.pressed.connect(_perform_primary_action)
	detail_panel.add_child(action_button)
	notice_label = _label("", 12, Color(1.0, 0.68, 0.35))
	notice_label.name = "ActionNotice"
	notice_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_panel.add_child(notice_label)


func _build_bottom_bar() -> void:
	var bar := Panel.new()
	bar.name = "OriginalNavigationBar"
	bar.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.04, 0.05, 0.98), Color(0.15, 0.27, 0.29), 0))
	add_child(bar)
	var back := TextureButton.new()
	back.name = "BackButton"
	back.texture_normal = _component("armory_back_normal")
	back.texture_pressed = _component("armory_back_pressed")
	back.ignore_texture_size = true
	back.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	back.tooltip_text = tr("BACK")
	back.pressed.connect(func():
		AudioDirector.play_ui("back")
		closed.emit()
	)
	bar.add_child(back)
	screen_title = _label("", 23, CYAN)
	screen_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(screen_title)
	for key in ["store", "customize"]:
		var button := Button.new()
		button.name = "%sMode" % key.capitalize()
		button.text = tr("STORE" if key == "store" else "CUSTOMIZE")
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(set_mode.bind(key, true))
		mode_buttons[key] = button
		bar.add_child(button)
	currency_label = _label("", 13, Color(0.83, 0.9, 0.9))
	currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(currency_label)
	var rank_badge := Control.new()
	rank_badge.name = "RankBadge"
	rank_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(rank_badge)
	var rank_icon := TextureRect.new()
	rank_icon.name = "RankIcon"
	rank_icon.texture = _component("main_rank_%02d" % clampi(GameState.get_rank_id(), 0, 11))
	rank_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rank_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rank_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(rank_icon, Rect2(0, 0, 40, 40))
	rank_badge.add_child(rank_icon)


func apply_layout(use_desktop_layout: bool) -> void:
	desktop_layout = use_desktop_layout
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_set_rect(self, Rect2(Vector2(DESKTOP_X_OFFSET if desktop_layout else 0.0, 0), _active_design_size()))
	if not is_instance_valid(catalog_panel):
		return
	var width := _active_design_size().x
	var catalog_width := 414.0 if desktop_layout else 336.0
	var detail_x := catalog_width + 36.0
	var detail_width := width - detail_x - 20.0
	_set_rect(catalog_panel, Rect2(20, 88, catalog_width, 532))
	_set_rect(detail_panel, Rect2(detail_x, 88, detail_width, 532))
	var inner := catalog_width - 24.0
	_set_rect(section_buttons.equipment, Rect2(12, 12, (inner - 8) / 2, 34))
	_set_rect(section_buttons.supplies, Rect2(16 + inner / 2, 12, (inner - 8) / 2, 34))
	_set_rect(category_layer, Rect2(12, 58, inner, 50))
	var category_width := (inner - 20.0) / 6.0
	for index in range(CATEGORIES.size()):
		var button := category_buttons[str(CATEGORIES[index].key)] as Button
		_set_rect(button, Rect2(index * (category_width + 4), 0, category_width, 50))
		_set_rect(button.get_node("CategoryArt"), Rect2((category_width - 25) / 2, 4, 25, 26))
		_set_rect(button.get_node("CategoryName"), Rect2(0, 32, category_width, 15))
	for index in range(SUPPLY_CATEGORIES.size()):
		var button := supply_buttons[str(SUPPLY_CATEGORIES[index].key)] as Button
		_set_rect(button, Rect2(12 + index * (inner + 8) / 3, 58, (inner - 16) / 3, 50))
	_set_rect(weapon_filter_picker, Rect2(12, 120, inner * 0.6, 30))
	_set_rect(preview_counter, Rect2(inner * 0.6 + 20, 125, inner * 0.4 - 8, 20))
	_set_rect(item_scroll, Rect2(12, 160, inner, 324))
	_set_rect(catalog_panel.get_node("PreviousItem"), Rect2(12, 494, 40, 28))
	_set_rect(catalog_panel.get_node("NextItem"), Rect2(catalog_width - 52, 494, 40, 28))
	_set_rect(catalog_panel.get_node("SelectionHint"), Rect2(58, 500, catalog_width - 116, 18))
	catalog_panel.get_node("SelectionHint").visible = not OS.has_feature("mobile")
	for card in item_row.get_children():
		_layout_item_card(card)
	_set_rect(name_label, Rect2(20, 14, detail_width - 40, 35))
	_set_rect(state_label, Rect2(20, 53, detail_width - 40, 22))
	_set_rect(meta_label, Rect2(detail_width - 226, 78, 206, 18))
	var preview_panel := detail_panel.get_node("EquipmentPreview") as Control
	_set_rect(preview_panel, Rect2(10, 88, detail_width - 246, 236))
	_set_rect(preview_panel.get_node("PreviewViewportContainer"), Rect2(Vector2.ZERO, preview_panel.size))
	_set_rect(supply_preview_art, Rect2((preview_panel.size.x - 180) / 2, 28, 180, 180))
	_set_rect(stats_text, Rect2(detail_width - 226, 104, 206, 114))
	_set_rect(description_text, Rect2(detail_width - 226, 228, 206, 96))
	_set_rect(comparison_title, Rect2(20, 337, detail_width - 40, 18))
	_set_rect(comparison_panel, Rect2(20, 366, detail_width - 40, 40))
	var column_width := (comparison_panel.size.x - 16) / 3.0
	for index in range(3):
		var row := comparison_panel.get_child(index) as Control
		row.position = Vector2(index * (column_width + 8), 0)
		row.scale = Vector2(column_width / 240.0, 1)
	_set_rect(slot_picker, Rect2(20, 416, detail_width - 40, 28))
	_set_rect(detail_panel.get_node("PurchaseDivider"), Rect2(20, 450, detail_width - 40, 1))
	_set_rect(price_label, Rect2(20, 470, detail_width - 248, 26))
	_set_rect(action_button, Rect2(detail_width - 216, 462, 196, 44))
	_set_rect(notice_label, Rect2(20, 510, detail_width - 40, 18))
	var bar := get_node("OriginalNavigationBar") as Control
	_set_rect(bar, Rect2(0, 0, width, 72))
	_set_rect(bar.get_node("BackButton"), Rect2(12, 12, 68, 48))
	_set_rect(screen_title, Rect2(92, 12, 124, 48))
	_set_rect(mode_buttons.store, Rect2(226, 18, 86, 36))
	_set_rect(mode_buttons.customize, Rect2(320, 18, 100, 36))
	_set_rect(currency_label, Rect2(432, 14, width - 516, 44))
	_set_rect(bar.get_node("RankBadge"), Rect2(width - 64, 16, 40, 40))
	_fit_preview_camera()
	if not selected_item_key.is_empty():
		call_deferred("_ensure_item_visible", selected_item_key)


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
	_refresh_filter_buttons()
	_refresh_loadout_summary()
	_rebuild_item_row()
	if _get_category_ids().has(selected_item_key):
		_select_item(selected_item_key, false)
	else:
		_select_preferred_item(false)


func _select_desktop_section(section_key: String) -> void:
	if section_key == "supplies":
		_select_supply_category(selected_supply_category, true)
	else:
		_select_category(selected_category, true)


func _select_supply_category(category_key: String, play_sound := true) -> void:
	var valid := false
	for category: Dictionary in SUPPLY_CATEGORIES:
		if str(category.key) == category_key:
			valid = true
			break
	if not valid:
		return
	selected_section = "supplies"
	selected_supply_category = category_key
	_refresh_desktop_navigation()
	if play_sound:
		AudioDirector.play_ui("switch", -5.0)
	_rebuild_item_row()
	_select_preferred_item(false)


func _select_category(category_key: String, play_sound := true) -> void:
	if not category_buttons.has(category_key):
		return
	selected_section = "equipment"
	selected_category = category_key
	for key in category_buttons:
		var active := str(key) == selected_category
		var button := category_buttons[key] as Button
		button.button_pressed = active
	_refresh_filter_buttons()
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
	if selected_section == "supplies":
		preferred = selected_item_key if ids.has(selected_item_key) else ids[0]
	elif selected_category == "gun":
		preferred = GameState.selected_weapon
	else:
		preferred = GameState.get_equipped_armor_key(selected_category)
	if not ids.has(preferred):
		preferred = ids[0]
	_select_item(preferred, play_sound)


func _get_category_ids() -> Array[String]:
	if selected_section == "supplies":
		return GameState.get_prop_ids(selected_supply_category)
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


# Shared by the catalog filter picker and older main-menu callers.
func set_weapon_filter(filter_key: String) -> void:
	weapon_filter = filter_key
	_refresh_filter_buttons()
	if selected_section != "equipment" or selected_category != "gun":
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
		# Let the scroll container receive a drag that starts on a product card.
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.set_meta("item_key", item_key)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var item: Dictionary
		if selected_section == "supplies":
			item = GameState.PROPS[item_key]
			art.name = "SupplyArt"
			art.texture = _component("props_item_%02d" % int(item.index))
		elif selected_category == "gun":
			item = GameState.WEAPONS[item_key]
			art.name = "WeaponArt"
			art.texture = Atlas.weapon_icon(int(item.id))
		else:
			item = GameState.ARMOR_ITEMS[item_key]
			art.name = "ArmorArt"
			art.texture = _armor_thumbnail(item)
		button.add_child(art)
		var title := _label(tr(str(item.name)), 12, Color(0.85, 0.92, 0.93))
		title.name = "ItemName"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_child(title)
		var state_label_card := _label("", 10, Color.WHITE)
		state_label_card.name = "ItemState"
		state_label_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_label_card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_child(state_label_card)
		var state := _get_item_state(item_key)
		var rank_label := _label("", 9, Color(0.55, 0.67, 0.7))
		rank_label.name = "RankRequirement"
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.add_child(rank_label)
		if selected_section == "supplies":
			state_label_card.text = "x%d  ·  %s" % [GameState.get_prop_count(item_key), _item_price_token(item)]
		elif state in ["owned", "equipped"]:
			state_label_card.text = tr(state.to_upper())
		else:
			state_label_card.text = _item_price_token(item)
			if state == "locked":
				rank_label.text = tr("RANK %d") % (int(item.get("unlock", 0)) + 1)
		button.tooltip_text = "%s · %s" % [title.text, state_label_card.text]
		_style_item_card(button, item_key == selected_item_key, state)
		button.pressed.connect(_select_item.bind(item_key, true))
		item_row.add_child(button)
		_layout_item_card(button)
	preview_counter.text = tr("%d ITEMS") % ids.size()


func _layout_item_card(button: Button) -> void:
	var card_width := floorf((item_scroll.size.x - 30) / 3.0)
	button.custom_minimum_size = Vector2(card_width, 100)
	var art := button.get_child(0) as TextureRect
	_set_rect(art, Rect2(10, 16, card_width - 20, 44))
	_set_rect(button.get_node("RankRequirement"), Rect2(5, 3, card_width - 10, 12))
	_set_rect(button.get_node("ItemName"), Rect2(5, 62, card_width - 10, 18))
	_set_rect(button.get_node("ItemState"), Rect2(4, 82, card_width - 8, 15))


func _item_price_token(item: Dictionary) -> String:
	return "#%s" % _format_price(int(item.mithril)) if int(item.get("mithril", 0)) > 0 else "$%s" % _format_price(int(item.get("price", 0)))


func _select_item(item_key: String, play_sound := true) -> void:
	if not _get_category_ids().has(item_key):
		return
	selected_item_key = item_key
	if play_sound:
		AudioDirector.play_ui("switch", -5.0)
	_refresh_card_styles()
	_refresh_details()
	_rebuild_preview()
	preview_counter.text = tr("%d ITEMS") % _get_category_ids().size()
	notice_label.text = ""
	call_deferred("_ensure_item_visible", item_key)


func _ensure_item_visible(item_key: String) -> void:
	if not is_instance_valid(item_scroll):
		return
	var card := item_row.get_node_or_null("Card_%s" % item_key) as Control
	if card != null:
		item_scroll.ensure_control_visible(card)


func _step_item(direction: int) -> void:
	var ids := _get_category_ids()
	if ids.is_empty():
		return
	var index := ids.find(selected_item_key)
	if index < 0:
		index = 0
	_select_item(ids[posmod(index + direction, ids.size())], true)


func _step_category(direction: int) -> void:
	if selected_section == "supplies":
		var supply_index := 0
		for index in range(SUPPLY_CATEGORIES.size()):
			if str(SUPPLY_CATEGORIES[index].key) == selected_supply_category:
				supply_index = index
				break
		_select_supply_category(str(SUPPLY_CATEGORIES[posmod(supply_index + direction, SUPPLY_CATEGORIES.size())].key), true)
		return
	var selected_index := 0
	for index in range(CATEGORIES.size()):
		if str(CATEGORIES[index].key) == selected_category:
			selected_index = index
			break
	_select_category(str(CATEGORIES[posmod(selected_index + direction, CATEGORIES.size())].key), true)


func _desktop_carousel_arrow(node_name: String, glyph: String, direction: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = glyph
	button.tooltip_text = tr("PREVIOUS WEAPON" if direction < 0 else "NEXT WEAPON")
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.62, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _texture_style("armory_side_button"))
	button.add_theme_stylebox_override("hover", _texture_style("armory_side_button", Color(0.72, 1.0, 1.0)))
	button.add_theme_stylebox_override("pressed", _texture_style("armory_side_button", Color(0.52, 0.9, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_step_item.bind(direction))
	return button


func _refresh_card_styles() -> void:
	if not is_instance_valid(item_row):
		return
	for child in item_row.get_children():
		if child is Button:
			var key := str(child.get_meta("item_key", ""))
			_style_item_card(child, key == selected_item_key, _get_item_state(key))


func _get_item_state(item_key: String) -> String:
	if item_key.begins_with("prop"):
		return "full" if GameState.get_prop_count(item_key) >= 99 else "available"
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
	if selected_section == "supplies":
		_refresh_prop_details()
	elif selected_category == "gun":
		_refresh_weapon_details()
	else:
		_refresh_armor_details()


func _refresh_comparison_stats() -> void:
	if is_instance_valid(comparison_panel):
		comparison_panel.visible = selected_section == "equipment"
	if selected_section == "supplies":
		return
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
	name_label.add_theme_color_override("font_color", Color(0.9, 0.97, 0.98))
	state_label.text = tr("UNLOCK: RANK %d") % (_selected_unlock_rank() + 1) if state == "locked" else tr(state.to_upper())
	state_label.add_theme_color_override("font_color", _state_color(state))
	meta_label.text = ""
	meta_label.visible = false
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
	description_text.text = tr("Weapon performance compared with the selected loadout slot.")
	_set_price(weapon)
	slot_picker.visible = mode == "customize"
	_configure_action(state)
	preview_caption.text = "%s  /  %s" % [str(weapon.name), tr(state.to_upper())]


func _refresh_armor_details() -> void:
	var item: Dictionary = GameState.ARMOR_ITEMS.get(selected_item_key, {})
	if item.is_empty():
		return
	var state := _get_item_state(selected_item_key)
	name_label.text = tr(str(item.name))
	name_label.add_theme_color_override("font_color", Color(0.9, 0.97, 0.98))
	state_label.text = tr("UNLOCK: RANK %d") % (_selected_unlock_rank() + 1) if state == "locked" else tr(state.to_upper())
	state_label.add_theme_color_override("font_color", _state_color(state))
	var set_name := _armor_set_name(int(item.set_id))
	meta_label.text = set_name if mode == "customize" and not set_name.is_empty() else ""
	meta_label.visible = not meta_label.text.is_empty()
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
	preview_caption.text = "%s  /  %s" % [tr(str(item.name)), tr(state.to_upper())]


func _refresh_prop_details() -> void:
	var item: Dictionary = GameState.PROPS.get(selected_item_key, {})
	if item.is_empty():
		return
	var count := GameState.get_prop_count(selected_item_key)
	name_label.text = tr(str(item.name))
	name_label.add_theme_color_override("font_color", CYAN)
	state_label.text = tr("OWNED %d / 99") % count
	state_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72))
	meta_label.text = tr(str(PropsCatalogData.CATEGORY_LABELS.get(str(item.category), "SUPPLY")))
	meta_label.visible = true
	var effect_lines: Array[String] = []
	for effect_key in item.effects:
		var value := float(item.effects[effect_key])
		match str(effect_key):
			"heal":
				effect_lines.append("[color=#%s]HP[/color] %s" % [HP_COLOR.to_html(false), "FULL" if value >= 999999.0 else "+%s" % _format_price(roundi(value))])
			"revive_ratio":
				effect_lines.append("[color=#%s]REVIVE[/color] %d%% HP" % [DESCRIPTION.to_html(false), roundi(value * 100.0)])
			"speed_boost":
				effect_lines.append("[color=#%s]SPEED[/color] +%s" % [SPEED_COLOR.to_html(false), _compact_value(value)])
			"damage_reduction":
				effect_lines.append("[color=#%s]DEFENCE[/color] +%d%%" % [HP_COLOR.to_html(false), roundi(value * 100.0)])
			"attack_boost":
				effect_lines.append("[color=#%s]DAMAGE[/color] +%d%%" % [POWER_COLOR.to_html(false), roundi(value * 100.0)])
	if int(item.duration) > 0:
		effect_lines.append("[color=#%s]DURATION[/color] %d SEC" % [GOLD_COLOR.to_html(false), int(item.duration)])
	stats_text.text = "\n".join(effect_lines)
	description_text.text = tr(str(item.description))
	_set_price(item)
	slot_picker.visible = false
	action_button.disabled = count >= 99
	if mode == "store":
		action_button.text = tr("MAX 99") if count >= 99 else tr("BUY +1")
	else:
		action_button.text = tr("BUY IN STORE")
	preview_caption.text = "%s  /  x%d" % [tr(str(item.name)), count]


func _armor_description(item: Dictionary) -> String:
	var fragments: Array[String] = []
	var callofmini := str(item.get("appearance_source", "")) == "callofmini"
	if callofmini:
		fragments.append(tr("Call of Mini appearance • Viper stats and prices."))
	var set_id := int(item.set_id)
	var set_exp_boost := 0.0
	if selected_category != "bag":
		var pieces := _preview_set_piece_count(set_id)
		fragments.append(tr("%s SET • %d/4 MATCHED") % [_armor_set_name(set_id).to_upper(), pieces])
		if pieces == 4 and GameState.ARMOR_SET_BONUSES.has(set_id):
			fragments.append("[color=#%s]%s[/color]" % [CYAN.to_html(false), tr("MATCHING SET EQUIPPED" if callofmini else "FULL SET BONUS ACTIVE")])
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
		fragments.append(tr("Select matching armor pieces to complete a set."))
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
	if selected_section == "supplies":
		if mode != "store":
			set_mode("store", true)
			return
		var prop_result := GameState.purchase_prop(selected_item_key)
		match prop_result:
			"purchased":
				notice_label.text = tr("PURCHASE COMPLETE • OWNED %d") % GameState.get_prop_count(selected_item_key)
				AudioDirector.play_ui("money")
			"full":
				notice_label.text = tr("STORAGE LIMIT REACHED (99)")
			"not_enough_credits":
				notice_label.text = tr("Not enough credits.")
			"not_enough_mithril":
				notice_label.text = tr("Not enough mithril.")
			_:
				notice_label.text = tr("Purchase could not be completed.")
		return
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
	if selected_section == "supplies":
		return 0
	if selected_category == "gun":
		return int(GameState.WEAPONS.get(selected_item_key, {}).get("unlock", 0))
	return int(GameState.ARMOR_ITEMS.get(selected_item_key, {}).get("unlock", 0))


func _set_price(item: Dictionary) -> void:
	if selected_section != "supplies" and _get_item_state(selected_item_key) in ["owned", "equipped"]:
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
		currency_label.text = tr("CREDITS  %s   /   MITHRIL  %s") % [_format_price(GameState.credits), _format_price(GameState.mithril)]


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
	_rebuild_preview()
	call_deferred("_ensure_item_visible", selected_item_key)


func _on_armor_changed(_part_key: String, _armor_key: String) -> void:
	_on_store_changed()


func _rebuild_preview() -> void:
	if not is_instance_valid(preview_root):
		return
	if preview_tween and preview_tween.is_valid():
		preview_tween.kill()
	for child in preview_root.get_children():
		child.free()
	if is_instance_valid(supply_preview_art):
		supply_preview_art.visible = selected_section == "supplies"
	if selected_section == "supplies":
		var item: Dictionary = GameState.PROPS.get(selected_item_key, {})
		supply_preview_art.texture = _component("props_item_%02d" % int(item.get("index", 0)))
	elif selected_category == "gun":
		_build_weapon_preview()
	else:
		_build_armor_preview()
	# Keep the selected product still so its silhouette can be compared with the cards.
	preview_root.rotation_degrees = Vector3(-5, -24, 2)
	if mode == "store" and selected_section == "equipment" and selected_category == "gun":
		preview_root.rotation_degrees = Vector3(-8, -68, -6)
	_fit_preview_camera()
	preview_tween = null


func _fit_preview_camera() -> void:
	if not is_instance_valid(preview_viewport):
		return
	var camera := preview_viewport.get_camera_3d()
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 5.8 if mode == "customize" and selected_category == "gun" else 4.6
	var weapon := preview_root.get_node_or_null("SelectedWeapon") as MeshInstance3D
	if weapon != null and weapon.mesh != null:
		var visual_bounds: AABB = preview_root.transform * (weapon.transform * weapon.mesh.get_aabb())
		var viewport_size := (detail_panel.get_node("EquipmentPreview") as Control).size
		var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
		var required_size := maxf(visual_bounds.size.y, visual_bounds.size.x / aspect) * 1.12
		camera.size = maxf(3.9, required_size)
	camera.position = Vector3(0, 0, 6)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _build_weapon_preview() -> void:
	var weapon: Dictionary = GameState.WEAPONS.get(selected_item_key, {})
	if weapon.is_empty():
		return
	var mesh_path := "res://assets/models/weapons/%s.obj" % str(weapon.model)
	var mesh := load(mesh_path) as Mesh if ResourceLoader.exists(mesh_path) else null
	if mode == "store" or not _build_equipped_avatar_for_weapon(weapon, mesh):
		if mesh == null:
			_build_fallback_weapon(Color(weapon.color))
		else:
			var preview := MeshInstance3D.new()
			preview.name = "SelectedWeapon"
			preview.mesh = mesh
			_normalize_preview_mesh(preview, _store_weapon_target_size(weapon), Color(weapon.color), 0.04, int(weapon.id))
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
	preload("res://scripts/game/armor_visuals.gd").restore_starter_backpack(preview, visual_id)
	display.add_child(preview)
	if not _normalize_preview_node(display, 3.55):
		display.queue_free()
		_build_fallback_armor()


func _apply_preview_armor_visibility(avatar: Node3D) -> void:
	var visible_ids := {}
	for part_key: String in ARMOR_MESH_PARTS:
		var armor_key := selected_item_key if selected_category == part_key else GameState.get_equipped_armor_key(part_key)
		visible_ids[part_key] = int(GameState.get_armor_item(armor_key).get("visual_id", 0))
	preload("res://scripts/game/armor_visuals.gd").ensure_parts(avatar, visible_ids)
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
	var authored_rot := _store_weapon_rotation(weapon_id) if weapon_id >= 0 else Vector3.ZERO
	var authored_basis := Basis.from_euler(authored_rot * (PI / 180.0))
	var bounds: AABB = preview.mesh.get_aabb()
	var oriented_box: AABB = Transform3D(authored_basis, Vector3.ZERO) * bounds
	var longest := maxf(oriented_box.size.x, maxf(oriented_box.size.y, oriented_box.size.z))
	var factor := target_size / longest if longest > 0.001 else 1.0
	preview.basis = authored_basis.scaled(Vector3.ONE * factor)
	preview.position = -(preview.basis * (bounds.position + bounds.size * 0.5))


func _store_weapon_target_size(weapon: Dictionary) -> float:
	var weapon_id := int(weapon.get("id", -1))
	var kind := str(weapon.get("kind", ""))
	if weapon_id in [23, 42]:
		return 1.95 # Compact gloves / fists
	elif weapon_id == 36:
		return 2.3 # Arm drill
	elif weapon_id in [26, 31]:
		return 2.4 # Compact sidearms
	elif kind in ["sniper", "reflection"]:
		return 3.45 # Snipers & railguns
	elif kind in ["rocket", "machinegun", "fly_grenade"] or weapon_id in [11, 12, 13, 16, 24, 25, 30, 37, 39, 45]:
		return 3.3 # Heavy artillery & launcher weapons
	elif weapon_id in [27, 28, 33]:
		return 3.25 # Swords
	elif weapon_id in [22, 29, 44]:
		return 3.2 # Bows
	return 2.8 # Standard rifles & shotguns


func _store_weapon_rotation(weapon_id: int) -> Vector3:
	if weapon_id == 20: # Plasma Neo: barrel along +Y, align to canonical rifle orientation
		return Vector3(90.0, 180.0, 0.0)
	elif weapon_id in [27, 28, 33]: # Swords: tilt diagonally across showcase with blade flat to camera
		return Vector3(0.0, 110.0, -50.0)
	elif weapon_id in [22, 29, 44]: # Bows: face forward, tilt diagonally across showcase
		return Vector3(-15.0, 100.0, -35.0)
	elif weapon_id == 23: # Energy Glove: face front-right
		return Vector3(0.0, 180.0, 0.0)
	return Vector3.ZERO


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
			if material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				var effect := ShaderMaterial.new()
				effect.shader = AdditivePreviewShader
				effect.set_shader_parameter("effect_texture", material.albedo_texture)
				effect.set_shader_parameter("effect_tint", material.albedo_color)
				preview.set_surface_override_material(surface_index, effect)
			else:
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
	return tr(str(GameState.ARMOR_SET_BONUSES.get(set_id, {}).get("name", "")))


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
	button.add_theme_stylebox_override("normal", _texture_style("button_pressed" if active else "button_normal"))
	button.add_theme_stylebox_override("hover", _texture_style("button_hover"))
	button.add_theme_stylebox_override("pressed", _texture_style("button_pressed"))
	button.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), CYAN, 2))
	button.add_theme_color_override("font_color", Color.WHITE if active else Color(0.56, 0.72, 0.74))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _style_mode_button(button: Button, active: bool) -> void:
	_style_tab(button, active)
	button.disabled = false
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if active else Control.CURSOR_POINTING_HAND


func _style_item_card(button: Button, selected: bool, state: String) -> void:
	button.add_theme_stylebox_override("normal", _texture_style("button_pressed") if selected else _panel_style(Color(0.055, 0.075, 0.082), Color(0.16, 0.23, 0.25), 3))
	button.add_theme_stylebox_override("hover", _texture_style("button_hover"))
	button.add_theme_stylebox_override("pressed", _texture_style("button_pressed"))
	button.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), CYAN, 3))
	var label := button.get_node("ItemState") as Label
	label.add_theme_color_override("font_color", Color(0.64, 0.73, 0.75) if state == "locked" else (CYAN if state in ["owned", "equipped"] else Color(1.0, 0.77, 0.35)))


func _frame_style(component_name: String, tint := Color.WHITE) -> StyleBoxTexture:
	var style := _texture_style(component_name, tint)
	# Preserve the recovered cut corners instead of stretching them across a panel.
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 50.0)
		style.set_content_margin(side, 0.0)
	return style


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


func _selector_plate_style(component_name: String, tint := Color.WHITE) -> StyleBoxTexture:
	var style := _texture_style(component_name, tint)
	style.content_margin_left = 14
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _style_desktop_picker(picker: OptionButton) -> void:
	picker.add_theme_color_override("font_color", Color(0.62, 0.83, 0.86))
	picker.add_theme_color_override("font_hover_color", Color.WHITE)
	picker.add_theme_color_override("font_pressed_color", Color.WHITE)
	picker.add_theme_stylebox_override("normal", _selector_plate_style("button_normal"))
	picker.add_theme_stylebox_override("hover", _selector_plate_style("button_hover"))
	picker.add_theme_stylebox_override("pressed", _selector_plate_style("button_pressed"))
	picker.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _armor_thumbnail(item: Dictionary) -> Texture2D:
	var path := "%sarmor_%s_%02d.png" % [ARMOR_THUMBNAIL_DIR, str(item.part_key), int(item.visual_id)]
	return load(path) if ResourceLoader.exists(path) else null


func _component(component_name: String) -> Texture2D:
	var path := COMPONENT_DIR + component_name + ".png"
	return load(path) if ResourceLoader.exists(path) else null


func _active_design_size() -> Vector2:
	return DESKTOP_DESIGN_SIZE if desktop_layout else DESIGN_SIZE


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
