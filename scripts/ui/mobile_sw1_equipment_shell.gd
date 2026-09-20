extends "res://scripts/ui/unity_equipment_shell.gd"
## Mobile-only SW1 StoreUI / UISliderTag / UISliderAvatar / PropsStoreUI port.
## Transactions and current HD equipment stay shared with the desktop shell.

const Layout = preload("res://scripts/ui/sw1_store_layout.gd")
const Scroller = preload("res://scripts/ui/sw1_store_scroller.gd")
const ArmorVisuals = preload("res://scripts/game/armor_visuals.gd")
const Refinement = preload("res://scripts/core/equipment_refinement.gd")
const PackagePage = preload("res://scripts/ui/mobile_sw1_package.gd")
const DESCRIPTION_SKILLS := {
	"HP_BOOTH": ["hp", false, true], "ATTACK_BOOTH": ["attack_boost", true, true],
	"SPEED_BOOTH": ["speed_boost", false, true], "MONEY_BOOTH": ["money_boost", true, true],
	"EXP_BOOTH": ["exp_boost", true, true], "SAVE_ENEGY": ["save_energy", true, true],
	"RECOVERY_BOOTH": ["recovery_boost", true, false], "DAMAGE_REDUCE": ["damage_reduce", true, true],
	"HP_RECOVERY_WHEN_MAKE_KILL": ["hp_on_kill", false, true], "BLOCK_AT_A_RATE": ["block_rate", true, false],
	"LASER_BOOTH": ["laser_boost", true, true], "RPG_BOOTH": ["rpg_boost", true, false],
	"SWORD_DEFENCE": ["sword_defence", true, false], "SHOTGUN_BOOTH": ["shotgun_boost", true, true],
	"ASSAULT_BOOTH": ["assault_boost", true, false], "HP_AUTO_RECOVERY": ["hp_auto_recovery", false, true],
	"TEAM_HP_RECOVERY": ["team_hp_recovery", false, true], "TEAM_ATTACK_BOOTH": ["team_attack_boost", true, true],
	"TEAM_DAMAGE_REDUCE": ["team_damage_reduce", true, false], "SWORD_BOOTH": ["sword_boost", true, false],
}

var gear_scroller: Control
var tag_scroller: Control
var props_scroller: Control
var equipment_controls: Control
var props_controls: Control
var preview_panel: Control
var gear_cards: Array[Control] = []
var prop_cards: Array[Control] = []
var item_dots: Control
var tag_dots: Control
var prop_dots: Control
var preview_selection: Dictionary = {}
var _ids: Array[String] = []
var _currency_values: Array[Label] = []
var _part_meshes: Dictionary = {}
var _ammo_dialog: AcceptDialog
var _prop_category_marker: TextureRect
var _category_tween: Tween
var _gear_spread := 1.0
var _refresh_pending := false
var equip_button: Button
var customize_controls: Control
var package_page: Control
var _items_button: Button
var _items_flag: TextureRect
var _equip_art: Array[TextureRect] = []
var _suit_icons: Array[TextureRect] = []
var _level_icons: Array[TextureRect] = []
var _interaction_enabled := true


func _build_background() -> void:
	var background := _art(self, "armory_background", Rect2(0, 0, 960, 640))
	background.name = "UnityStoreBackdrop"
	equipment_controls = Control.new()
	equipment_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(equipment_controls)
	props_controls = Control.new()
	props_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	props_controls.hide()
	add_child(props_controls)
	for category: Dictionary in CATEGORIES:
		var key := str(category.key)
		preview_selection[key] = GameState.selected_weapon if key == "gun" else GameState.get_equipped_armor_key(key)


func _build_catalog() -> void:
	tag_scroller = Scroller.new()
	tag_scroller.name = "SW1CategoryScroller"
	tag_scroller.spacing = 90.0
	tag_scroller.max_velocity = 10.0
	_set_rect(tag_scroller, Layout.rect(11, 2))
	equipment_controls.add_child(tag_scroller)
	category_layer = tag_scroller
	for index in CATEGORIES.size():
		var button := Button.new()
		button.name = str(CATEGORIES[index].key).capitalize() + "Tab"
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _texture_style("armory_category_frame"))
		button.add_theme_stylebox_override("hover", _texture_style("armory_category_frame"))
		button.add_theme_stylebox_override("pressed", _texture_style("armory_category_frame"))
		button.size = Vector2(120, 99)
		_art(button, "armory_category_%02d" % index, Rect2(31, 16, 64, 64))
		tag_scroller.add_child(button)
		category_buttons[str(CATEGORIES[index].key)] = button
	tag_scroller.moved.connect(_position_tags)
	tag_scroller.settled.connect(_animate_category_switch)
	tag_scroller.configure(6, 5)
	tag_dots = Control.new()
	tag_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipment_controls.add_child(tag_dots)
	for index in 6:
		_art(tag_dots, "armory_nav_dot", Layout.rect(11, 24 + index))
	gear_scroller = Scroller.new()
	gear_scroller.name = "SW1EquipmentScroller"
	# StoreUI.SetAvatar: five cells, 120 pixels each; selected cell is on the avatar.
	_set_rect(gear_scroller, Rect2(102, 217.5, 600, 135))
	equipment_controls.add_child(gear_scroller)
	for index in 7:
		var card := Control.new()
		card.name = "GearCell%d" % index
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size = Vector2(120, 135)
		gear_scroller.add_child(card)
		gear_cards.append(card)
	gear_scroller.moved.connect(_position_gear)
	gear_scroller.settled.connect(func(index: int):
		if index < _ids.size():
			_select_item(_ids[index], true)
	)
	item_dots = Control.new()
	item_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipment_controls.add_child(item_dots)
	preview_counter = _label("", 12, CYAN)
	preview_counter.hide()
	add_child(preview_counter)
	var items := _side_button(equipment_controls, "ITEMS", Layout.rect(11, 48))
	items.name = "ItemsButton"
	items.pressed.connect(_select_supply_category.bind("health", true))
	_items_button = items
	_items_flag = _module_art(equipment_controls, 11, 75)
	var ammo := _side_button(equipment_controls, "AMMO", Layout.rect(11, 49))
	ammo.name = "AmmoButton"
	ammo.pressed.connect(_show_ammo)
	_module_art(equipment_controls, 11, 76)
	_build_props()
	_build_customize()


func _build_customize() -> void:
	customize_controls = Control.new()
	customize_controls.z_index = 5
	customize_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(customize_controls)
	for index in [75, 76, 77, 78, 79, 80, 81]:
		var art := _module_art(customize_controls, 10, index)
		art.set_meta("module", index)
		_equip_art.append(art)
	equip_button = Button.new()
	equip_button.name = "EquipPreviewButton"
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		equip_button.add_theme_stylebox_override(state, _empty_style())
	equip_button.focus_mode = Control.FOCUS_NONE
	_set_rect(equip_button, Layout.rect(10, 79).grow_individual(40, 16, 40, 16))
	customize_controls.add_child(equip_button)
	equip_button.pressed.connect(_equip_preview)
	equip_button.button_down.connect(_refresh_equip_button.bind(true))
	equip_button.button_up.connect(_refresh_equip_button.bind(false))
	for index in 4:
		_suit_icons.append(_module_art(customize_controls, 10, 59 + index))
	for index in 7:
		var icon := _module_art(customize_controls, 10, 67)
		icon.position.x += index * 18
		_level_icons.append(icon)
	customize_controls.hide()


func set_mode(next_mode: String, play_sound := true) -> void:
	if is_instance_valid(package_page):
		package_page.queue_free()
		package_page = null
	if next_mode == "customize":
		# CreateClone in CustomizeUI starts from the equipped outfit and first gun.
		for category: Dictionary in CATEGORIES:
			var key := str(category.key)
			preview_selection[key] = GameState.battle_weapons[0] if key == "gun" else GameState.get_equipped_armor_key(key)
		selected_item_key = str(preview_selection[selected_category])
		selected_section = "equipment"
	super.set_mode(next_mode, play_sound)
	apply_layout(false)
	_refresh_details()


func _get_category_ids() -> Array[String]:
	var ids: Array[String] = super._get_category_ids()
	if mode != "customize" or selected_section != "equipment":
		return ids
	var owned: Array[String] = []
	for key: String in ids:
		if GameState.is_weapon_owned(key) if selected_category == "gun" else GameState.is_armor_owned(key):
			owned.append(key)
	return owned


func _equip_preview() -> void:
	if mode != "customize" or not _interaction_enabled or equip_button.disabled:
		return
	if GameState.apply_equipment_preview(preview_selection):
		AudioDirector.play_ui("mount_gear")
		_refresh_details()


func _refresh_equip_button(pressed := false) -> void:
	var changed := str(preview_selection.get("gun", "")) != GameState.battle_weapons[0]
	for key: String in ["head", "body", "arms", "legs", "bag"]:
		changed = changed or str(preview_selection.get(key, "")) != GameState.get_equipped_armor_key(key)
	equip_button.disabled = not changed or not _interaction_enabled
	for art: TextureRect in _equip_art:
		var index := int(art.get_meta("module"))
		art.visible = index in ([75, 77 if pressed else 79, 80] if changed else [76, 78, 81])


func _select_supply_category(category_key: String, play_sound := true) -> void:
	if mode == "customize":
		_show_package()
	else:
		super._select_supply_category(category_key, play_sound)


func _show_package() -> void:
	if not _interaction_enabled or is_instance_valid(package_page):
		return
	set_interaction_enabled(false)
	package_page = PackagePage.new()
	package_page.shell = self
	add_child(package_page)
	move_child(package_page, get_node("OriginalNavigationBar").get_index())
	screen_title.text = "PACKAGE"
	AudioDirector.play_ui("accept")


func _close_package() -> void:
	package_page.queue_free()
	package_page = null
	set_mode("customize", false)
	set_interaction_enabled(true)


func _build_props() -> void:
	for index in SUPPLY_CATEGORIES.size():
		var category: Dictionary = SUPPLY_CATEGORIES[index]
		var button := _side_button(props_controls, str(category.label), Layout.rect(13, 3 + index))
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_select_supply_category.bind(str(category.key), true))
		supply_buttons[str(category.key)] = button
	_prop_category_marker = _module_art(props_controls, 13, 6)
	props_scroller = Scroller.new()
	props_scroller.name = "SW1PropsScroller"
	props_scroller.vertical = true
	props_scroller.looping = false
	props_scroller.spacing = 150.0
	_set_rect(props_scroller, Layout.rect(13, 2))
	props_controls.add_child(props_scroller)
	props_scroller.moved.connect(_position_props)
	props_scroller.settled.connect(func(index: int):
		if index < _ids.size():
			selected_item_key = _ids[index]
			_refresh_currency()
			_draw_dots(prop_dots, _ids.size(), index, Vector2(268, 327), 24.0, true)
	)
	props_scroller.tapped.connect(_tap_prop)
	prop_dots = Control.new()
	prop_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	props_controls.add_child(prop_dots)


func _build_details() -> void:
	super._build_details()
	(detail_panel as Panel).add_theme_stylebox_override("panel", _empty_style())
	var frame := _art(detail_panel, "armory_detail_panel", Rect2(0, 0, 232, 374))
	detail_panel.move_child(frame, 0)
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.add_theme_font_size_override("font_size", 15)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_text.add_theme_font_size_override("normal_font_size", 15)
	stats_text.add_theme_constant_override("line_separation", 3)
	description_text.add_theme_font_size_override("normal_font_size", 15)
	description_text.add_theme_color_override("default_color", DESCRIPTION)
	price_label.add_theme_font_size_override("font_size", 20)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button.add_theme_font_size_override("font_size", 20)
	action_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Price is in the top half of the original 150 x 58 button; BUY is below it.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := action_button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_top = 24.0
		style.content_margin_bottom = 0.0
		action_button.add_theme_stylebox_override(state, style)
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_label.z_index = 2
	detail_panel.get_node("PurchaseDivider").hide()
	notice_label.reparent(self)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(notice_label, Rect2(170, 615, 760, 24))
	notice_label.add_theme_font_size_override("font_size", 14)


func _build_preview() -> void:
	super._build_preview()
	preview_panel = detail_panel.get_node("EquipmentPreview")
	preview_panel.reparent(self)
	move_child(preview_panel, 1)
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var container := preview_panel.get_node("PreviewViewportContainer") as SubViewportContainer
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(preview_panel, Rect2(152, 90, 500, 414))
	_set_rect(container, Rect2(0, 0, 500, 414))
	preview_caption.hide()


func _build_comparison_stats() -> void:
	super._build_comparison_stats()
	comparison_panel.reparent(self)
	_set_rect(comparison_panel, Rect2(706, 106, 240, 114))
	for index in 3:
		var row := comparison_panel.get_child(index) as Control
		row.position = Vector2(0, index * 40)
		row.get_node("AuthoredMeter").position.y = 20
		row.get_node("AuthoredMeter/TrackGlow").hide()
	comparison_title.hide()


func _build_bottom_bar() -> void:
	var bar := Control.new()
	bar.z_index = 20
	bar.name = "OriginalNavigationBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(bar, Rect2(0, 0, 960, 80))
	add_child(bar)
	_art(bar, "armory_nav_bar", Rect2(0, 0, 960, 80))
	var back := TextureButton.new()
	back.name = "BackButton"
	back.texture_normal = _component("armory_back_normal")
	back.texture_pressed = _component("armory_back_pressed")
	back.ignore_texture_size = true
	back.stretch_mode = TextureButton.STRETCH_SCALE
	_set_rect(back, Rect2(0, 1, 125, 78))
	back.pressed.connect(handle_back)
	bar.add_child(back)
	screen_title = _label("STORE", 38, CYAN)
	screen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_rect(screen_title, Rect2(138, 1, 559, 78))
	bar.add_child(screen_title)
	for index in 3:
		var art := _module_art(bar, 19, 11 + index)
		var value := _label("", 16, CYAN)
		_set_rect(value, Rect2(art.position.x + art.size.x + 3, art.position.y - 2, 109, 21))
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bar.add_child(value)
		_currency_values.append(value)
	_refresh_currency()


func apply_layout(_use_desktop_layout: bool) -> void:
	desktop_layout = false
	_set_rect(self, Rect2(0, 0, 960, 640))
	if not is_instance_valid(detail_panel):
		return
	_set_rect(detail_panel, Rect2(704, 240, 232, 374))
	_set_rect(name_label, _detail_rect(52))
	_set_rect(state_label, _detail_rect(53))
	_set_rect(stats_text, Rect2(62, 58, 180, 88) if mode == "customize" else Rect2(14, 58, 216, 88))
	_set_rect(description_text, _detail_rect(50))
	_set_rect(action_button, _detail_rect(19))
	_set_rect(price_label, _detail_rect(58))
	_set_rect(meta_label, Rect2(10, 142, 212, 20))
	_set_rect(slot_picker, Rect2(-190, 307, 180, 36))
	_fit_preview_camera()


func _detail_rect(index: int) -> Rect2:
	var rect := Layout.rect(10 if mode == "customize" else 11, index)
	rect.position -= Vector2(704, 240)
	return rect


func _refresh_filter_buttons() -> void:
	_refresh_desktop_navigation()


func _refresh_desktop_navigation() -> void:
	var equipment := selected_section == "equipment"
	if is_instance_valid(customize_controls):
		customize_controls.visible = mode == "customize" and equipment
		_items_button.text = "PACK." if mode == "customize" else "ITEMS"
		_items_flag.texture = _module_texture(10, 82) if mode == "customize" else _module_texture(11, 75)
	equipment_controls.visible = equipment
	props_controls.visible = not equipment
	if is_instance_valid(detail_panel):
		detail_panel.visible = equipment
	if is_instance_valid(preview_panel):
		preview_panel.visible = equipment
	if is_instance_valid(comparison_panel):
		comparison_panel.visible = equipment
	if is_instance_valid(comparison_title):
		comparison_title.hide()
	for key: String in supply_buttons:
		var button := supply_buttons[key] as Button
		button.add_theme_stylebox_override("normal", _texture_style("armory_side_button"))
		button.modulate = Color.WHITE if selected_supply_category == key else Color(0.7, 0.7, 0.7)
		if key == selected_supply_category:
			_prop_category_marker.position = button.position
	if tag_dots != null:
		for index in 6:
			var dot := tag_dots.get_child(index) as TextureRect
			var active := str(CATEGORIES[index].key) == selected_category
			dot.texture = _component("armory_nav_selected" if active else "armory_nav_dot")
			var rect := Layout.rect(11, 24 + index)
			if active:
				rect = rect.grow(4)
			_set_rect(dot, rect)


func _select_category(category_key: String, play_sound := true) -> void:
	if not category_buttons.has(category_key):
		return
	super._select_category(category_key, play_sound)
	tag_scroller.select(category_buttons.keys().find(category_key))


func _animate_category_switch(index: int) -> void:
	if _category_tween and _category_tween.is_valid():
		_category_tween.kill()
	gear_scroller.cancel()
	gear_scroller.enabled = false
	_category_tween = create_tween()
	# UISliderAvatar retracts/expands at 30 design pixels per 60 Hz frame.
	_category_tween.tween_method(_set_gear_spread, _gear_spread, 0.0, 0.17)
	_category_tween.tween_callback(_select_category.bind(str(CATEGORIES[index].key), true))
	_category_tween.tween_method(_set_gear_spread, 0.0, 1.0, 0.17)
	_category_tween.tween_callback(func(): gear_scroller.enabled = true)


func _set_gear_spread(value: float) -> void:
	_gear_spread = value
	_position_gear()


func _select_preferred_item(play_sound := false) -> void:
	var ids := _get_category_ids()
	if ids.is_empty():
		return
	var key := str(preview_selection.get(selected_category, ids[0]))
	if selected_section == "supplies":
		key = selected_item_key
	_select_item(key if ids.has(key) else ids[0], play_sound)


func _rebuild_item_row() -> void:
	_ids = _get_category_ids()
	if selected_section == "supplies":
		_build_prop_cards()
		return
	gear_scroller.configure(_ids.size(), maxi(0, _ids.find(selected_item_key)))
	_draw_dots(item_dots, _ids.size(), maxi(0, _ids.find(selected_item_key)), Vector2(408, 94), minf(30.0, 450.0 / maxf(1, _ids.size())))


func _refresh_card_styles() -> void:
	_position_gear()


func _ensure_item_visible(item_key: String) -> void:
	if not is_inside_tree() or selected_section != "equipment":
		return
	var index := _ids.find(item_key)
	if index >= 0 and gear_scroller.finger == -1:
		gear_scroller.select(index)


func _select_item(item_key: String, play_sound := true) -> void:
	if not _get_category_ids().has(item_key):
		return
	if selected_section == "equipment":
		preview_selection[selected_category] = item_key
	super._select_item(item_key, false)
	if play_sound:
		AudioDirector.play_ui("mount_weapon" if selected_category == "gun" else "mount_gear")
	if selected_section == "equipment":
		gear_scroller.select(_ids.find(item_key))
		_draw_dots(item_dots, _ids.size(), _ids.find(item_key), Vector2(408, 94), minf(30.0, 450.0 / maxf(1, _ids.size())))


func _refresh_details() -> void:
	super._refresh_details()
	comparison_title.hide()
	meta_label.hide()
	if selected_section == "equipment" and selected_category == "gun" and not selected_item_key.is_empty():
		var weapon := GameState.get_weapon_data(selected_item_key)
		# SW1 displays seconds per shot, not shots per second, beside FIRERATE.
		stats_text.text = "[color=#ffa500]POW %s\nFIRERATE %.2f\nENG %d%s[/color]" % [
			_source_value(float(weapon.damage)), float(weapon.cooldown), int(weapon.energy),
			"\nSPD %s" % _source_value(float(weapon.speed_drag)) if not is_zero_approx(float(weapon.speed_drag)) else ""]
		description_text.text = str(Layout.WEAPON_DESCRIPTIONS[int(weapon.id)]).replace("[n]", "\n").replace("[EMPTY]", "")
	elif selected_section == "equipment" and GameState.ARMOR_ITEMS.has(selected_item_key):
		var item: Dictionary = GameState.ARMOR_ITEMS[selected_item_key]
		if str(item.get("source_game", "sw1")) == "sw1":
			var lines: Array[String] = []
			for index in 4:
				var key := str(["hp", "attack_boost", "speed_boost", "money_boost"][index])
				var value := float(item.skills.get(key, 0.0))
				if is_zero_approx(value):
					continue
				var percentage := index in [1, 3]
				var text := ("+" if value > 0.0 else "") + _source_value(value * (100.0 if percentage else 1.0)) + ("%" if percentage else "")
				var color: Color = [HP_COLOR, POWER_COLOR, SPEED_COLOR, GOLD_COLOR][index]
				lines.append("[color=#%s]%s %s[/color]" % [color.to_html(false), text, ["HP", "POW", "SPD", "GOLD"][index]])
			stats_text.text = "\n".join(lines)
	if mode == "store" and not selected_item_key.is_empty() and _get_item_state(selected_item_key) in ["owned", "equipped"]:
		price_label.text = ""
	# Keep longer restored CoM/full-suit labels inside the original button.
	action_button.add_theme_font_size_override("font_size", 12 if action_button.text.length() > 14 else 20)
	if mode == "customize":
		slot_picker.hide()
		price_label.hide()
		action_button.hide()
		state_label.text = ""
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		stats_text.position.x = 62
		stats_text.size.x = 156
		var rect := _detail_rect(50)
		if selected_category != "gun" and not _selected_is_com():
			rect.size.y += 58
		_set_rect(description_text, rect)
		for index in _level_icons.size():
			var icon := _level_icons[index]
			icon.visible = selected_category == "gun"
			icon.texture = _module_texture(10, 68 if index < GameState.get_equipment_level(selected_item_key) - 1 else 67)
		for index in _suit_icons.size():
			var icon := _suit_icons[index]
			icon.visible = selected_category in ARMOR_MESH_PARTS
			if icon.visible:
				var set_id := int(GameState.ARMOR_ITEMS[selected_item_key].set_id)
				var part := str(["head", "body", "arms", "legs"][index])
				var equipped_set := int(GameState.ARMOR_ITEMS[str(preview_selection[part])].set_id)
				icon.texture = _module_texture(10, 59 + index + (4 if set_id == equipped_set else 0))
		_refresh_equip_button()
	else:
		price_label.show()
		action_button.show()
		action_button.tooltip_text = ""
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_text.position.x = 14
		stats_text.size.x = 216
	if selected_section == "equipment":
		var quote := GameState.get_upgrade_quote(selected_item_key)
		if str(quote.status) not in ["unsupported", "not_owned"]:
			state_label.text = "LV %d / %d" % [int(quote.level), int(quote.max_level)]
			action_button.show()
			action_button.disabled = str(quote.status) == "max_level"
			action_button.text = tr("MAX LEVEL") if action_button.disabled else tr("UPGRADE")
			action_button.tooltip_text = tr("Preview the next level and confirm its cost.")
			price_label.visible = not action_button.disabled
			price_label.text = UpgradeDialog.price_text(quote)
			if selected_category == "gun" and not action_button.disabled:
				var extra := _source_value(float(quote.next.POW) - float(quote.current.POW))
				stats_text.text = stats_text.text.replace("POW %s" % _source_value(float(quote.current.POW)), "POW %s (+%s)" % [_source_value(float(quote.current.POW)), extra])
	action_button.add_theme_font_size_override("font_size", 12 if action_button.text.length() > 14 else (14 if action_button.text.length() > 8 else 20))


func _perform_primary_action() -> void:
	if selected_section == "equipment" and str(GameState.get_upgrade_quote(selected_item_key).status) not in ["unsupported", "not_owned"]:
		_request_upgrade()
	else:
		super._perform_primary_action()


func _armor_description(item: Dictionary) -> String:
	if str(item.get("source_game", "sw1")) != "sw1":
		return super._armor_description(item)
	var index := int(item.id)
	var descriptions: Array = Layout.BAG_DESCRIPTIONS if selected_category == "bag" else Layout.ARMOR_DESCRIPTIONS
	if index >= descriptions.size():
		return super._armor_description(item)
	var text := str(descriptions[index]).replace("[n]", "\n").replace("[EMPTY]", "")
	text = text.replace("[BAG_SLOT]", str(item.bag_slots))
	var skills: Dictionary = item.skills if selected_category == "bag" else GameState.ARMOR_SET_BONUSES.get(int(item.set_id), {}).get("skills", {})
	for token: String in DESCRIPTION_SKILLS:
		var rule: Array = DESCRIPTION_SKILLS[token]
		var value := float(skills.get(str(rule[0]), 0.0))
		var formatted := ("+" if bool(rule[2]) and value > 0.0 else "") + _source_value(value * (100.0 if bool(rule[1]) else 1.0)) + ("%" if bool(rule[1]) else "")
		text = text.replace("[%s]" % token, formatted)
	return text


func _set_price(item: Dictionary) -> void:
	price_label.text = ("#%s" % _format_price(int(item.mithril))) if int(item.get("mithril", 0)) > 0 else ("$%s" % _format_price(int(item.get("price", 0))))


func _refresh_currency() -> void:
	if _currency_values.size() != 3:
		return
	_currency_values[0].text = _format_price(GameState.mithril)
	_currency_values[1].text = _format_price(GameState.credits)
	# No persistent paid energy reservoir exists in the restoration.
	_currency_values[2].text = "—"
	for value: Label in _currency_values:
		value.add_theme_font_size_override("font_size", 11 if value.text.length() > 10 else 16)


func _rebuild_preview() -> void:
	if not is_instance_valid(preview_root):
		return
	for child in preview_root.get_children():
		_release_preview(child)
	if selected_section == "supplies":
		return
	var key := str(preview_selection.get("gun", GameState.selected_weapon))
	var weapon: Dictionary = GameState.WEAPONS[key]
	_build_equipped_avatar_for_weapon(weapon, Refinement.weapon_mesh(str(weapon.model)))
	preview_root.rotation_degrees = Vector3(0, -24, 0)
	if selected_category == "bag":
		preview_root.rotation_degrees.y = 150
	_fit_preview_camera()
	_position_carousel_at_part()


func _apply_preview_armor_visibility(avatar: Node3D) -> void:
	var visual_ids := {}
	for key: String in ARMOR_MESH_PARTS:
		visual_ids[key] = int(GameState.get_armor_item(str(preview_selection.get(key, GameState.get_equipped_armor_key(key)))).get("visual_id", 0))
	ArmorVisuals.ensure_parts(avatar, visual_ids)
	for mesh: MeshInstance3D in avatar.find_children("*", "MeshInstance3D", true, false):
		for key: String in ARMOR_MESH_PARTS:
			var prefix := str(ARMOR_MESH_PARTS[key])
			if mesh.name.to_lower().begins_with(prefix):
				mesh.visible = str(mesh.name).to_lower() == "%s%02d" % [prefix, int(visual_ids[key])]
	# Bags are separate source meshes. Attach to the same animated spine as gameplay.
	var bag: Dictionary = GameState.get_armor_item(str(preview_selection.get("bag", GameState.get_equipped_armor_key("bag"))))
	var skeletons := avatar.find_children("*", "Skeleton3D", true, false)
	if not bag.is_empty() and not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		var path := "%sArmorBag_%02d/ArmorBag_%02d.obj" % [ARMOR_BAG_DIR, int(bag.visual_id), int(bag.visual_id)]
		if ResourceLoader.exists(path):
			var attachment := BoneAttachment3D.new()
			attachment.bone_name = "fly_bag"
			skeleton.add_child(attachment)
			var mesh := MeshInstance3D.new()
			mesh.mesh = load(path)
			var bone := skeleton.find_bone("fly_bag")
			var body_id := int(visual_ids.body)
			var bag_id := int(bag.visual_id)
			var authored_scale := float({14: 1.2, 15: 1.2, 16: 1.2, 17: 1.2, 18: 1.1, 19: 1.2, 20: 1.2}.get(bag_id, 1.0))
			if body_id != 5:
				authored_scale *= 0.8
			if bone >= 0:
				mesh.basis = skeleton.get_bone_global_rest(bone).basis.inverse() * Basis.from_scale(Vector3.ONE * authored_scale)
			attachment.add_child(mesh)
			ArmorVisuals.restore_starter_backpack(mesh, int(bag.visual_id))


func _fit_preview_camera() -> void:
	if not is_instance_valid(preview_viewport):
		return
	var camera := preview_viewport.get_camera_3d()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 5.9
	camera.position = Vector3(0, 0.25, 6)
	camera.look_at(Vector3(0, 0.25, 0), Vector3.UP)


func _position_carousel_at_part() -> void:
	var y := 285.0
	if selected_category in ARMOR_MESH_PARTS:
		# Skinned mesh bounds are in bind space. Project the posed bone instead.
		var skeletons := preview_root.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var skeleton := skeletons[0] as Skeleton3D
			var bone := skeleton.find_bone(str({"head": "Bip01 Head", "body": "Bip01 Spine1", "arms": "Bip01 L Forearm", "legs": "Bip01 L Calf"}[selected_category]))
			if bone >= 0:
				var center := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
				y = preview_panel.position.y + preview_viewport.get_camera_3d().unproject_position(center).y
	gear_scroller.position.y = clampf(y - 67.5, 113.0, 354.0)


func _position_tags() -> void:
	if not is_instance_valid(tag_scroller):
		return
	for index in category_buttons.size():
		var button := category_buttons.values()[index] as Button
		var distance: float = tag_scroller.distance(index)
		var ratio := maxf(0.2, 1.0 - absf(distance) / 450.0)
		button.scale = Vector2.ONE * ratio
		button.position = Vector2(225 + distance - 60 * ratio, (99 - 99 * ratio) * 0.5)


func _position_gear() -> void:
	if not is_instance_valid(gear_scroller) or _ids.is_empty() or selected_section != "equipment":
		return
	var center := roundi(gear_scroller.offset / 120.0)
	for slot in gear_cards.size():
		var index := posmod(center + slot - 3, _ids.size())
		var card := gear_cards[slot]
		# CustomizeUI.GetDispCount repeats small owned lists around the avatar.
		# Use each visible copy's unwrapped position, not the same wrapped index.
		var distance: float = ((center + slot - 3) * 120.0 - gear_scroller.offset) * _gear_spread
		card.visible = absf(distance) > 25.0 and absf(distance) < 360.0
		if not card.visible:
			continue
		if str(card.get_meta("key", "")) != _ids[index]:
			_fill_gear_cell(card, _ids[index])
		var ratio := maxf(0.2, 1.0 - absf(distance) / 600.0)
		card.scale = Vector2.ONE * ratio
		card.position = Vector2(300 + distance - 60 * ratio, (135 - 135 * ratio) * 0.5)
		var brightness := minf(1.0, 100.0 * (absf(distance) + 1.0) / (distance * distance + 100.0))
		if _get_item_state(_ids[index]) == "locked":
			brightness *= 0.08
		card.modulate = Color(brightness, brightness, brightness)


func _fill_gear_cell(card: Control, item_key: String) -> void:
	for child in card.get_children():
		_release_preview(child)
	card.set_meta("key", item_key)
	var mesh: Mesh
	var weapon_id := -1
	if selected_category == "gun":
		weapon_id = int(GameState.WEAPONS[item_key].id)
		mesh = Refinement.weapon_mesh(str(GameState.WEAPONS[item_key].model))
	else:
		mesh = _armor_part_mesh(item_key)
	if mesh == null:
		return
	var container := SubViewportContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.stretch = true
	_set_rect(container, Rect2(0, 0, 120, 135))
	card.add_child(container)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.size = Vector2i(120, 135)
	# Redraw while visible: a newly reused cell can still be resizing and
	# compiling its material on its first frame (especially after a tag switch).
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	camera.position.z = 6
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 2.0
	viewport.add_child(light)
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(-5, -55 if weapon_id >= 0 else -110, 0)
	viewport.add_child(pivot)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	_normalize_preview_mesh(instance, 2.9, Color.WHITE, 0.0, weapon_id)
	pivot.add_child(instance)
	var state := _get_item_state(item_key)
	if state == "locked":
		var lock_art := TextureRect.new()
		lock_art.texture = load("res://assets/original/ui/pages/lock.png")
		lock_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(lock_art, Rect2(43, 83, 34, 34))
		card.add_child(lock_art)


func _armor_part_mesh(item_key: String) -> Mesh:
	if _part_meshes.has(item_key):
		return _part_meshes[item_key]
	var item: Dictionary = GameState.get_armor_item(item_key)
	var visual_id := int(item.get("visual_id", 0))
	if selected_category == "bag":
		var path := "%sArmorBag_%02d/ArmorBag_%02d.obj" % [ARMOR_BAG_DIR, visual_id, visual_id]
		return load(path) as Mesh if ResourceLoader.exists(path) else null
	var path := ArmorVisuals.reworked_scene_path(visual_id)
	if not ResourceLoader.exists(path):
		path = preload("res://scripts/core/armor_catalog.gd").gameplay_scene_path(visual_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		path = ARMOR_AVATAR_PATH
	var source := (load(path) as PackedScene).instantiate()
	var prefix := str(ARMOR_MESH_PARTS[selected_category])
	var wanted := "%s%02d" % [prefix, visual_id]
	var result: Mesh
	for instance: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if instance.name.to_lower() == wanted:
			result = instance.mesh
			break
	source.free()
	_part_meshes[item_key] = result
	return result


func _build_prop_cards() -> void:
	for card in prop_cards:
		card.free()
	prop_cards.clear()
	for item_key in _ids:
		var item: Dictionary = GameState.PROPS[item_key]
		var card := Control.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size = Vector2(676, 270)
		card.set_meta("key", item_key)
		props_scroller.add_child(card)
		prop_cards.append(card)
		var frame := _module_art(card, 13, 7)
		frame.position = Vector2.ZERO
		_art(card, "props_item_%02d" % int(item.index), Rect2(70, 73, 128, 128))
		var title := _module_art(card, 13, int(item.index), 1)
		title.position = Vector2(207, 55)
		var description := _label(tr(str(item.description)), 15, DESCRIPTION)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_set_rect(description, Rect2(207, 95, 321, 53))
		card.add_child(description)
		var count_label := _label("x%d" % GameState.get_prop_count(item_key), 20, CYAN)
		_set_rect(count_label, Rect2(110, 205, 100, 30))
		card.add_child(count_label)
		var buy := _side_button(card, _item_price_token(item), Rect2(441, 152, 150, 58), "armory_action_disabled")
		buy.name = "Buy"
		buy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = GameState.get_prop_count(item_key) >= 99
	props_scroller.configure(_ids.size(), maxi(0, _ids.find(selected_item_key)))
	_draw_dots(prop_dots, _ids.size(), maxi(0, _ids.find(selected_item_key)), Vector2(268, 327), 24.0, true)


func _position_props() -> void:
	if not is_instance_valid(props_scroller):
		return
	for index in prop_cards.size():
		var card := prop_cards[index]
		var distance: float = props_scroller.distance(index)
		var ratio := maxf(0.2, 1.0 - absf(distance) / 450.0)
		card.scale = Vector2.ONE * ratio
		card.position = Vector2(1 + (676 - 676 * ratio) * 0.5, 225 + distance - 135 * ratio)
		card.visible = absf(distance) < 360
		card.modulate = Color.WHITE * maxf(0.15, ratio)
		card.modulate.a = 1.0
		card.z_index = 2 if absf(distance) < 75 else 0


func _tap_prop(point: Vector2) -> void:
	if props_scroller.moving:
		return
	var index := clampi(roundi(props_scroller.offset / 150.0), 0, prop_cards.size() - 1)
	var card := prop_cards[index]
	var buy := card.get_node("Buy") as Button
	var local := (point - card.position) / card.scale
	if Rect2(buy.position, buy.size).has_point(local) and not buy.disabled:
		selected_item_key = str(card.get_meta("key"))
		_perform_primary_action()


func _draw_dots(parent: Control, count: int, selected: int, center: Vector2, spacing: float, vertical := false) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		child.free()
	for index in count:
		var dot_size := 18.0 if index == selected else 10.0
		var distance := (index - (count - 1) * 0.5) * spacing
		var location := center + (Vector2(0, distance) if vertical else Vector2(distance, 0)) - Vector2.ONE * dot_size * 0.5
		_art(parent, "armory_nav_selected" if index == selected else "armory_nav_dot", Rect2(location, Vector2.ONE * dot_size))


func set_interaction_enabled(value: bool) -> void:
	_interaction_enabled = value
	if is_instance_valid(package_page):
		package_page.set_interaction_enabled(value)
	if is_instance_valid(equip_button):
		_refresh_equip_button()
	if _category_tween and _category_tween.is_valid():
		_category_tween.kill()
		tag_scroller.select(category_buttons.keys().find(selected_category))
	_set_gear_spread(1.0)
	for scroller: Control in [gear_scroller, tag_scroller, props_scroller]:
		scroller.enabled = value and not is_instance_valid(package_page)
		if not scroller.enabled:
			scroller.cancel()


func handle_back() -> void:
	AudioDirector.play_ui("back")
	if close_upgrade_dialog():
		return
	if is_instance_valid(package_page):
		_close_package()
	elif is_instance_valid(_ammo_dialog) and _ammo_dialog.visible:
		_ammo_dialog.hide()
	elif selected_section == "supplies":
		_select_category(selected_category, false)
	else:
		closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if _interaction_enabled and not is_instance_valid(package_page):
		super._unhandled_key_input(event)


func _show_ammo() -> void:
	if not is_instance_valid(_ammo_dialog):
		_ammo_dialog = AcceptDialog.new()
		_ammo_dialog.title = "AMMO"
		_ammo_dialog.dialog_text = "每場任務開始時會補充能量，無須購買彈藥。\n這裡不會扣除點數或秘銀。"
		add_child(_ammo_dialog)
		_ammo_dialog.visibility_changed.connect(func(): set_interaction_enabled(not _ammo_dialog.visible))
	_ammo_dialog.popup_centered(Vector2i(460, 150))


func _art(parent: Node, component: String, rect: Rect2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = _component(component)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(art, rect)
	parent.add_child(art)
	return art


func _module_art(parent: Node, unit: int, index: int, frame := 0) -> TextureRect:
	var module := Layout.module(unit, index, frame)
	var region: Array = module.rect
	var art := TextureRect.new()
	art.texture = Atlas.region("res://assets/original/ui/pages/%d.png" % int(module.page), Rect2(region[0], region[1], region[2], region[3]))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.flip_h = int(module.rotate) == 1
	_set_rect(art, Layout.rect(unit, index, frame))
	parent.add_child(art)
	return art


func _module_texture(unit: int, index: int, frame := 0) -> Texture2D:
	var module := Layout.module(unit, index, frame)
	var region: Array = module.rect
	return Atlas.region("res://assets/original/ui/pages/%d.png" % int(module.page), Rect2(region[0], region[1], region[2], region[3]))


func _side_button(parent: Node, caption: String, rect: Rect2, component := "armory_side_button") -> Button:
	var button := Button.new()
	button.text = caption
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", CYAN)
	button.add_theme_color_override("font_hover_color", CYAN)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := _texture_style(component)
		if component == "armory_side_button":
			style.content_margin_top = 19.0
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", _empty_style())
	_set_rect(button, rect)
	parent.add_child(button)
	return button


func _release_preview(node: Node) -> void:
	# Hold overrides until instances leave the renderer. Otherwise destruction of
	# shader overrides can invalidate RIDs while MeshInstance3D tears down surfaces.
	var materials: Array[Material] = []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null:
			materials.append(mesh.material_override)
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface)
			if material != null:
				materials.append(material)
		mesh.mesh = null
	node.free()


func _comparison_weapon(use_preview: bool) -> Dictionary:
	if use_preview:
		return GameState.get_weapon_data(str(preview_selection.get("gun", GameState.selected_weapon)))
	return super._comparison_weapon(false)


func _preview_armor_skills(_current: Dictionary) -> Dictionary:
	var outfit: Dictionary = GameState.equipped_armor.duplicate()
	for key: String in ["head", "body", "arms", "legs", "bag"]:
		outfit[key] = str(preview_selection.get(key, GameState.get_equipped_armor_key(key)))
	return GameState.get_armor_skills_for(outfit)


func _preview_full_set_id() -> int:
	var selected_set := -1
	for key: String in ["head", "body", "arms", "legs"]:
		var item := GameState.get_armor_item(str(preview_selection.get(key, GameState.get_equipped_armor_key(key))))
		var set_id := int(item.get("set_id", -1))
		if selected_set < 0:
			selected_set = set_id
		elif set_id != selected_set:
			return -1
	return selected_set


func _preview_set_piece_count(set_id: int) -> int:
	var count := 0
	for key: String in ["head", "body", "arms", "legs"]:
		var item := GameState.get_armor_item(str(preview_selection.get(key, GameState.get_equipped_armor_key(key))))
		if int(item.get("set_id", -1)) == set_id:
			count += 1
	return count


func _on_store_changed() -> void:
	# One armor purchase emits armor_changed and store_changed synchronously.
	# Rebuild the mobile 3D preview only once after that transaction finishes.
	if is_inside_tree() and not _refresh_pending:
		_refresh_pending = true
		call_deferred("_refresh_mobile_state")


func _refresh_mobile_state() -> void:
	_refresh_pending = false
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if is_instance_valid(package_page):
		_refresh_currency()
		return
	super._on_store_changed()


func _source_value(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else ("%.2f" % value).trim_suffix("0")


func _exit_tree() -> void:
	if _category_tween and _category_tween.is_valid():
		_category_tween.kill()
	if is_instance_valid(preview_root):
		for child in preview_root.get_children():
			_release_preview(child)
	for card in gear_cards:
		for child in card.get_children():
			_release_preview(child)
	super._exit_tree()
