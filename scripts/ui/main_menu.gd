extends Control

const Atlas = preload("res://scripts/ui/original_atlas.gd")

# Menu art is loaded as individual component textures rather than sampled out of
# the recovered NGUI page atlases at runtime. The hand written rectangles this
# replaces were a standing source of bugs: the button plate sample was wide
# enough to pull in the cyan play arrow packed two pixels to its right and short
# enough to slice off the bottom border, and the title sample clipped its tail
# flourish while catching the yellow reward coin beside it.
# Regenerate with tools/ui_extractor/extract_ui_components.py.
const COMPONENT_DIR := "res://assets/ui/components/"

var content: VBoxContainer
var modal_layer: Control
var music_player: AudioStreamPlayer
var store_selected_weapon := ""
var store_name: Label
var store_type: Label
var store_stats: Label
var store_price: Label
var store_equipped: Label
var store_equip_button: Button
var store_preview_root: Node3D
var store_preview_viewport: SubViewport
var store_preview_tween: Tween
var store_weapon_row: HBoxContainer
var store_currency_label: Label
var store_notice: Label
var store_slot_picker: OptionButton
var store_selected_slot := 0
var store_category := "ALL"
var store_category_buttons: Dictionary = {}

func _ready() -> void:
	var recovered_font := "res://assets/original/fonts/ZEROTWOS.ttf"
	if ResourceLoader.exists(recovered_font):
		var recovered_theme := Theme.new()
		recovered_theme.default_font = load(recovered_font)
		recovered_theme.default_font_size = 16
		theme = recovered_theme
	_build_background()
	_build_header()
	_build_main_buttons()
	_build_footer()
	_start_music()

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not is_node_ready():
		return
	if is_instance_valid(modal_layer) and modal_layer.get_child_count() > 0:
		_close_modal()
	else:
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(modal_layer) and modal_layer.get_child_count() > 0:
		AudioDirector.play_ui("back")
		_close_modal()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	# Stop streamed audio explicitly so desktop quit and mobile app shutdown
	# release the playback resource before the audio server is torn down.
	if is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null

func _build_background() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	float glow = max(0.0, 1.0 - distance(uv, vec2(0.72, 0.38)) * 1.65);
	float grid_x = smoothstep(0.965, 1.0, sin((uv.x + uv.y * .32) * 92.0) * .5 + .5);
	float grid_y = smoothstep(0.975, 1.0, sin(uv.y * 74.0) * .5 + .5);
	vec3 base = mix(vec3(.008, .018, .045), vec3(.035, .11, .17), uv.y);
	base += vec3(.04, .31, .42) * glow * .55;
	base += vec3(.08, .35, .43) * (grid_x + grid_y) * .055 * (1.0 - uv.y);
	COLOR = vec4(base, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	background.material = material
	add_child(background)

	var hero_texture := _component("menu_hero")
	if hero_texture:
		var hero := TextureRect.new()
		hero.texture = hero_texture
		hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hero.modulate = Color(0.72, 0.8, 0.86, 0.72)
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hero)
		var shade := ColorRect.new()
		shade.color = Color(0.0, 0.015, 0.025, 0.42)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)

	for i in range(34):
		var spark := ColorRect.new()
		var size := 1.0 + float((i * 17) % 4)
		spark.color = Color(0.25, 0.85, 1.0, 0.18 + float(i % 3) * 0.09)
		spark.position = Vector2(float((i * 193) % 1240) + 20.0, float((i * 83) % 640) + 20.0)
		spark.size = Vector2(size, size)
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(spark)

func _build_header() -> void:
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 56)
	safe.add_theme_constant_override("margin_top", 42)
	safe.add_theme_constant_override("margin_right", 56)
	safe.add_theme_constant_override("margin_bottom", 36)
	add_child(safe)

	var root_row := HBoxContainer.new()
	root_row.add_theme_constant_override("separation", 46)
	safe.add_child(root_row)

	content = VBoxContainer.new()
	content.custom_minimum_size = Vector2(470, 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	root_row.add_child(content)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_row.add_child(spacer)

	var status_panel := PanelContainer.new()
	status_panel.custom_minimum_size = Vector2(300, 108)
	status_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	status_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.12, 0.18, 0.88), Color(0.16, 0.75, 0.9, 0.55), 12))
	root_row.add_child(status_panel)
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 5)
	status_panel.add_child(status)
	var profile := _label(tr("OFFLINE OPERATIVE"), 16, Color(0.43, 0.9, 1.0))
	status.add_child(profile)
	status.add_child(_label(tr("CREDITS  %07d") % GameState.credits, 25, Color(0.98, 0.77, 0.24)))
	status.add_child(_label(tr("MITHRIL  %04d") % GameState.mithril, 14, Color(0.34, 0.92, 1.0)))
	status.add_child(_label(tr("LOCAL SAVE / NO SERVER REQUIRED"), 12, Color(0.62, 0.72, 0.78)))

	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.z_index = 10
	add_child(modal_layer)

func _build_main_buttons() -> void:
	var logo_texture := _component("menu_logo")
	if logo_texture:
		var logo := TextureRect.new()
		logo.texture = logo_texture
		logo.custom_minimum_size = Vector2(460, 108)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The shader that used to erase a yellow reward coin from this sprite is
		# gone: the coin was a neighbouring atlas entry the old rectangle reached
		# into, and the extracted component excludes it.
		content.add_child(logo)
		var subtitle_logo := TextureRect.new()
		subtitle_logo.texture = _component("menu_subtitle")
		subtitle_logo.custom_minimum_size = Vector2(410, 28)
		subtitle_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		subtitle_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		subtitle_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(subtitle_logo)
	else:
		content.add_child(_label("STAR WARFARE", 62, Color(0.95, 0.99, 1.0)))
	content.add_child(_label(tr("LOCAL OFFLINE RESTORATION"), 14, Color(0.33, 0.82, 0.94)))

	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	content.add_child(gap)

	var solo := _menu_button(tr("SINGLE PLAYER"), tr("CAMPAIGN / SECTORS 01-08"))
	_bind_accept_sound(solo)
	solo.pressed.connect(_show_level_select.bind("singleplayer"))
	content.add_child(solo)
	var multiplayer := _menu_button(tr("MULTIPLAYER"), tr("LOCAL SKIRMISH / SECTORS 13-21"))
	_bind_accept_sound(multiplayer)
	multiplayer.pressed.connect(_show_level_select.bind("multiplayer"))
	content.add_child(multiplayer)
	var armory := _menu_button(tr("SHOP & CUSTOMIZE"), tr("47 RECOVERED WEAPONS"))
	_bind_accept_sound(armory)
	armory.pressed.connect(_show_armory)
	content.add_child(armory)
	var options := _menu_button(tr("OPTIONS"), tr("Audio, quality, language and controls"))
	_bind_accept_sound(options)
	options.pressed.connect(_show_options)
	content.add_child(options)
	var help := _menu_button(tr("FIELD MANUAL"), tr("Desktop, controller and mobile controls"))
	_bind_accept_sound(help)
	help.pressed.connect(_show_help)
	content.add_child(help)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := _menu_button(tr("QUIT"), tr("Return to desktop"))
		_bind_accept_sound(quit)
		quit.pressed.connect(get_tree().quit)
		content.add_child(quit)
	call_deferred("_focus_control", solo)

func _build_footer() -> void:
	var footer := Label.new()
	footer.text = tr("COMM-LINK OFFLINE   /   ORIGINAL ONLINE SERVICES RETIRED   /   GODOT 4 RESTORATION")
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.38, 0.58, 0.67))
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.position = Vector2(56, -35)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)

func _show_level_select(game_mode: String = "singleplayer") -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	var heading := tr("SELECT SOLO SECTOR") if game_mode == "singleplayer" else tr("SELECT MULTIPLAYER MAP")
	body.add_child(_label(heading, 28, Color(0.72, 0.94, 1.0)))
	if game_mode == "multiplayer":
		var note := _label(tr("Official servers are retired; multiplayer maps run as local offline skirmishes."), 13, Color(0.55, 0.76, 0.84))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1050, 430 if game_mode == "multiplayer" else 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 9)
	scroll.add_child(grid)
	for level_number in GameState.get_levels_for_mode(game_mode):
		var data: Dictionary = GameState.get_level_data(level_number)
		var button := Button.new()
		var is_locked: bool = game_mode == "singleplayer" and level_number > GameState.unlocked_level
		button.text = (tr("LOCKED • ") if is_locked else "") + "%02d  %s" % [level_number, tr(str(data.name))]
		button.custom_minimum_size = Vector2(252, 108)
		button.icon = _level_preview(level_number)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.025, 0.12, 0.17, 0.96), Color(0.12, 0.52, 0.66, 0.8), 7))
		button.add_theme_stylebox_override("hover", _panel_style(Color(0.05, 0.32, 0.4, 0.98), Color(0.35, 0.9, 1.0, 1.0), 7))
		button.disabled = is_locked
		_bind_accept_sound(button)
		button.pressed.connect(func(): GameState.start_level(level_number, game_mode))
		grid.add_child(button)
	_show_modal(body, Vector2(1130, 650))

func _show_armory() -> void:
	# ShopAndCustomize.unity built this screen at runtime from UI set 11.  Its
	# recovered reference canvas is 960x640: weapon preview on the left,
	# comparison/readout on the right and the category rail along the bottom.
	_close_modal()
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var store := Control.new()
	store.name = "RecoveredUnityStore"
	store.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(store)

	var backdrop := TextureRect.new()
	backdrop.texture = _component("store_backdrop")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.modulate = Color(0.72, 0.78, 0.8, 1.0)
	store.add_child(backdrop)
	var scan := ColorRect.new()
	scan.color = Color(0.0, 0.04, 0.055, 0.42)
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	store.add_child(scan)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 24)
	safe.add_theme_constant_override("margin_top", 18)
	safe.add_theme_constant_override("margin_right", 24)
	safe.add_theme_constant_override("margin_bottom", 18)
	store.add_child(safe)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	safe.add_child(page)

	var nav := HBoxContainer.new()
	nav.custom_minimum_size.y = 60
	nav.add_theme_constant_override("separation", 9)
	page.add_child(nav)
	var back := Button.new()
	back.text = tr("◀  BACK")
	back.custom_minimum_size = Vector2(150, 54)
	back.add_theme_stylebox_override("normal", _recovered_button_style("button_normal", Color(0.78, 0.95, 1.0)))
	back.pressed.connect(func(): AudioDirector.play_ui("back"); _close_modal())
	nav.add_child(back)
	var title := _label(tr("STORE"), 31, Color(0.72, 1.0, 1.0))
	title.custom_minimum_size.x = 230
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(title)
	var customize := Button.new()
	customize.text = tr("CUSTOMIZE")
	customize.custom_minimum_size = Vector2(175, 54)
	customize.disabled = true
	nav.add_child(customize)
	var nav_space := Control.new()
	nav_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_space)
	store_currency_label = _label("", 19, Color(1.0, 0.77, 0.2))
	store_currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(store_currency_label)
	_update_store_currency_label()

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	page.add_child(main)
	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio = 1.7
	preview_panel.add_theme_stylebox_override("panel", _store_panel_style(Color(0.0, 0.025, 0.035, 0.82), Color(0.04, 0.72, 0.82, 0.75)))
	main.add_child(preview_panel)
	var preview_column := VBoxContainer.new()
	preview_panel.add_child(preview_column)
	var preview_header := _label(tr("EQUIPMENT DISPLAY"), 15, Color(0.32, 0.92, 1.0))
	preview_column.add_child(preview_header)
	var preview_container := SubViewportContainer.new()
	preview_container.stretch = true
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_container.custom_minimum_size = Vector2(500, 300)
	preview_column.add_child(preview_container)
	store_preview_viewport = SubViewport.new()
	store_preview_viewport.size = Vector2i(640, 380)
	store_preview_viewport.transparent_bg = true
	store_preview_viewport.own_world_3d = true
	store_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(store_preview_viewport)
	var preview_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.28, 0.55, 0.65)
	environment.ambient_light_energy = 1.8
	preview_environment.environment = environment
	store_preview_viewport.add_child(preview_environment)
	var light := DirectionalLight3D.new()
	light.light_color = Color(0.62, 0.92, 1.0)
	light.light_energy = 2.2
	light.rotation_degrees = Vector3(-38, -28, 0)
	store_preview_viewport.add_child(light)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.34, 0.08)
	rim.light_energy = 1.2
	rim.rotation_degrees = Vector3(25, 145, 0)
	store_preview_viewport.add_child(rim)
	# Some source MTL files have a black diffuse multiplier despite carrying a
	# valid albedo texture. A camera-side fill light matches Unity's store rig.
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.4, 1.8, 3.3)
	fill.light_color = Color(0.72, 0.94, 1.0)
	fill.light_energy = 5.0
	fill.omni_range = 12.0
	fill.shadow_enabled = false
	store_preview_viewport.add_child(fill)
	var preview_camera := Camera3D.new()
	preview_camera.position = Vector3(0, 0.25, 4.4)
	preview_camera.current = true
	store_preview_viewport.add_child(preview_camera)
	preview_camera.look_at(Vector3.ZERO, Vector3.UP)
	store_preview_root = Node3D.new()
	store_preview_root.name = "WeaponTurntable"
	store_preview_viewport.add_child(store_preview_root)

	var details := PanelContainer.new()
	details.custom_minimum_size.x = 390
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_stylebox_override("panel", _store_panel_style(Color(0.018, 0.035, 0.04, 0.96), Color(0.06, 0.83, 0.76, 0.85)))
	main.add_child(details)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 10)
	details.add_child(detail_column)
	store_name = _label("", 30, Color.WHITE)
	detail_column.add_child(store_name)
	store_type = _label("", 15, Color(0.3, 0.9, 1.0))
	detail_column.add_child(store_type)
	var divider := HSeparator.new()
	detail_column.add_child(divider)
	store_stats = _label("", 18, Color(0.82, 0.94, 0.96))
	store_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	store_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(store_stats)
	store_price = _label("", 21, Color(1.0, 0.72, 0.16))
	detail_column.add_child(store_price)
	store_equipped = _label("", 15, Color(0.3, 1.0, 0.54))
	detail_column.add_child(store_equipped)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 10)
	detail_column.add_child(slot_row)
	var slot_label := _label(tr("LOADOUT SLOT"), 14, Color(0.58, 0.82, 0.9))
	slot_label.custom_minimum_size.x = 130
	slot_row.add_child(slot_label)
	store_slot_picker = OptionButton.new()
	store_slot_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_slot_picker.item_selected.connect(func(index: int):
		store_selected_slot = index
		_select_store_weapon(store_selected_weapon)
	)
	slot_row.add_child(store_slot_picker)
	_rebuild_store_loadout_picker()
	store_equip_button = Button.new()
	store_equip_button.text = tr("EQUIP")
	store_equip_button.custom_minimum_size.y = 58
	store_equip_button.add_theme_font_size_override("font_size", 22)
	store_equip_button.add_theme_stylebox_override("normal", _recovered_button_style("button_equip", Color(0.74, 1.0, 0.95)))
	store_equip_button.pressed.connect(_equip_store_selection)
	detail_column.add_child(store_equip_button)
	store_notice = _label("", 13, Color(1.0, 0.58, 0.26))
	store_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	store_notice.custom_minimum_size.y = 22
	detail_column.add_child(store_notice)

	var tabs := HBoxContainer.new()
	tabs.custom_minimum_size.y = 42
	tabs.add_theme_constant_override("separation", 6)
	page.add_child(tabs)
	store_category_buttons.clear()
	var category_group := ButtonGroup.new()
	category_group.allow_unpress = false
	for tab_name in ["RIFLE", "SHOTGUN", "HEAVY", "SPECIAL", "MELEE", "ALL"]:
		var tab := Button.new()
		tab.text = tr(tab_name)
		tab.custom_minimum_size = Vector2(128, 38)
		tab.toggle_mode = true
		tab.button_group = category_group
		tab.button_pressed = tab_name == store_category
		tab.pressed.connect(_select_store_category.bind(tab_name))
		store_category_buttons[tab_name] = tab
		tabs.add_child(tab)
	var rail := ScrollContainer.new()
	rail.custom_minimum_size.y = 118
	rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(rail)
	store_weapon_row = HBoxContainer.new()
	store_weapon_row.add_theme_constant_override("separation", 7)
	rail.add_child(store_weapon_row)
	_rebuild_store_weapon_row()
	_select_store_weapon(GameState.selected_weapon)

func _select_store_weapon(weapon_id: String) -> void:
	if not GameState.WEAPONS.has(weapon_id):
		return
	store_selected_weapon = weapon_id
	var weapon: Dictionary = GameState.WEAPONS[weapon_id]
	store_name.text = str(weapon.name)
	store_name.add_theme_color_override("font_color", Color(weapon.color))
	store_type.text = tr("TYPE %02d   /   AIM HUD %02d") % [int(weapon.type), int(weapon.aim_id)]
	store_stats.text = tr("DAMAGE                 %d\nRATE OF FIRE          %.2f / SEC\nENERGY PER SHOT       %d\nEFFECTIVE RANGE       %d\n\nRecovered directly from the original equipment database.") % [int(weapon.damage), float(weapon.fire_rate), int(weapon.energy), int(weapon.range)]
	if int(weapon.mithril) > 0:
		store_price.text = tr("PRICE  #%s MITHRIL") % _format_store_price(int(weapon.mithril))
	else:
		store_price.text = tr("PRICE  $%s CREDITS") % _format_store_price(int(weapon.price))
	var owned := GameState.is_weapon_owned(weapon_id)
	var rank_unlocked := GameState.is_weapon_rank_unlocked(weapon_id)
	var equipped_slot := GameState.battle_weapons.find(weapon_id)
	if not rank_unlocked and not owned:
		store_equipped.text = tr("LOCKED • REQUIRES RANK %d") % (int(weapon.unlock) + 1)
		store_equip_button.text = tr("RANK %d REQUIRED") % (int(weapon.unlock) + 1)
		store_equip_button.disabled = true
	elif not owned:
		store_equipped.text = tr("UNLOCKED • AVAILABLE FOR PURCHASE")
		store_equip_button.text = tr("PURCHASE")
		store_equip_button.disabled = false
	elif equipped_slot == store_selected_slot:
		store_equipped.text = tr("EQUIPPED / LOADOUT SLOT %d") % (equipped_slot + 1)
		store_equip_button.text = tr("EQUIPPED")
		store_equip_button.disabled = true
	else:
		store_equipped.text = tr("OWNED") + (tr(" / CURRENTLY IN SLOT %d") % (equipped_slot + 1) if equipped_slot >= 0 else "")
		store_equip_button.text = tr("EQUIP TO SLOT %d") % (store_selected_slot + 1)
		store_equip_button.disabled = false
	_rebuild_store_preview(weapon)
	AudioDirector.play_ui("switch", -5.0)

func _equip_store_selection() -> void:
	if store_selected_weapon.is_empty():
		return
	store_notice.text = ""
	var purchased_now := false
	if not GameState.is_weapon_owned(store_selected_weapon):
		var purchase_result := GameState.purchase_weapon(store_selected_weapon)
		match purchase_result:
			"rank_locked":
				store_notice.text = tr("Reach the required rank before purchasing this weapon.")
				return
			"not_enough_credits":
				store_notice.text = tr("Not enough credits.")
				return
			"not_enough_mithril":
				store_notice.text = tr("Not enough mithril.")
				return
			"purchased":
				purchased_now = true
				store_notice.text = tr("PURCHASE COMPLETE")
				AudioDirector.play_ui("money")
			_:
				return
	# The original Unity StoreUI always replaced battle-weapon slot zero after
	# a purchase. Preserve that behaviour; owned weapons can still be moved to
	# any of the eight recovered bag slots with the picker.
	if purchased_now:
		store_selected_slot = 0
	if not GameState.set_loadout_weapon(store_selected_slot, store_selected_weapon):
		store_notice.text = tr("Unable to equip this weapon in the selected slot.")
		return
	AudioDirector.play_ui("mount_weapon")
	_rebuild_store_loadout_picker()
	_rebuild_store_weapon_row()
	_update_store_currency_label()
	_select_store_weapon(store_selected_weapon)

func _select_store_category(category: String) -> void:
	store_category = category
	_rebuild_store_weapon_row()
	var visible_ids := _get_store_weapon_ids()
	if not visible_ids.has(store_selected_weapon) and not visible_ids.is_empty():
		_select_store_weapon(visible_ids[0])

func _get_store_weapon_ids() -> Array[String]:
	var result: Array[String] = []
	for weapon_id: String in GameState.get_weapon_ids():
		if _weapon_matches_store_category(GameState.WEAPONS[weapon_id], store_category):
			result.append(weapon_id)
	return result

func _weapon_matches_store_category(weapon: Dictionary, category: String) -> bool:
	var type_id := int(weapon.type)
	match category:
		"RIFLE":
			return type_id in [1, 5, 23]
		"SHOTGUN":
			return type_id in [2, 15]
		"HEAVY":
			return type_id in [3, 4, 8, 11, 14, 21, 24, 43]
		"SPECIAL":
			return type_id in [7, 9, 10, 13, 17, 18, 19, 20, 40, 41, 42]
		"MELEE":
			return type_id in [12, 16]
	return true

func _rebuild_store_weapon_row() -> void:
	if not is_instance_valid(store_weapon_row):
		return
	for child in store_weapon_row.get_children():
		child.free()
	for weapon_id: String in _get_store_weapon_ids():
		var weapon: Dictionary = GameState.WEAPONS[weapon_id]
		var button := Button.new()
		var owned := GameState.is_weapon_owned(weapon_id)
		var rank_unlocked := GameState.is_weapon_rank_unlocked(weapon_id)
		var status := tr("OWNED") if owned else (tr("BUY") if rank_unlocked else tr("RANK %d") % (int(weapon.unlock) + 1))
		button.text = status
		button.tooltip_text = "%s / %s" % [str(weapon.name), status]
		button.icon = Atlas.weapon_icon(int(weapon.id))
		button.add_theme_constant_override("icon_max_width", 82)
		button.expand_icon = true
		button.custom_minimum_size = Vector2(142, 102)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 11)
		var normal_fill := Color(0.02, 0.05, 0.06, 0.95) if rank_unlocked or owned else Color(0.018, 0.022, 0.026, 0.95)
		var normal_border := Color(weapon.color, 0.38) if rank_unlocked or owned else Color(0.24, 0.29, 0.32, 0.65)
		button.add_theme_stylebox_override("normal", _store_panel_style(normal_fill, normal_border))
		button.add_theme_stylebox_override("hover", _store_panel_style(Color(weapon.color, 0.14), Color(weapon.color, 1.0)))
		button.modulate = Color.WHITE if rank_unlocked or owned else Color(0.48, 0.53, 0.56)
		button.pressed.connect(_select_store_weapon.bind(weapon_id))
		store_weapon_row.add_child(button)

func _rebuild_store_loadout_picker() -> void:
	if not is_instance_valid(store_slot_picker):
		return
	store_slot_picker.clear()
	for slot in range(GameState.battle_weapons.size()):
		var weapon_id := GameState.battle_weapons[slot]
		var weapon_name := str(GameState.WEAPONS.get(weapon_id, {}).get("name", tr("EMPTY")))
		store_slot_picker.add_item(tr("SLOT %d / %s") % [slot + 1, weapon_name])
	if GameState.battle_weapons.size() < GameState.LOADOUT_MAX_SLOTS:
		store_slot_picker.add_item(tr("SLOT %d / EMPTY") % (GameState.battle_weapons.size() + 1))
	store_selected_slot = clampi(store_selected_slot, 0, maxi(0, store_slot_picker.item_count - 1))
	store_slot_picker.select(store_selected_slot)

func _update_store_currency_label() -> void:
	if is_instance_valid(store_currency_label):
		store_currency_label.text = tr("CREDITS  %s   /   MITHRIL  %s") % [
			_format_store_price(GameState.credits),
			_format_store_price(GameState.mithril),
		]

func _rebuild_store_preview(weapon: Dictionary) -> void:
	if not is_instance_valid(store_preview_root):
		return
	if store_preview_tween and store_preview_tween.is_valid():
		store_preview_tween.kill()
	for child in store_preview_root.get_children():
		child.free()
	var mesh_path := "res://assets/models/weapons/%s.obj" % str(weapon.model)
	var preview_mesh := load(mesh_path) as Mesh if ResourceLoader.exists(mesh_path) else null
	if preview_mesh == null:
		_build_store_fallback_preview(weapon)
		_start_store_preview_rotation()
		return
	var preview := MeshInstance3D.new()
	preview.mesh = preview_mesh
	# Preserve every recovered texture while neutralising legacy Kd=0 values
	# which otherwise turn several weapons into black silhouettes in Godot.
	for surface_index in preview.mesh.get_surface_count():
		var source_material := preview.mesh.surface_get_material(surface_index)
		if source_material is StandardMaterial3D:
			var material := source_material.duplicate() as StandardMaterial3D
			if material.albedo_texture != null:
				material.albedo_color = Color.WHITE
			preview.set_surface_override_material(surface_index, material)
	var bounds := preview.mesh.get_aabb()
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var factor := 5.0 / longest if longest > 0.001 else 1.0
	preview.scale = Vector3.ONE * factor
	preview.position = -(bounds.position + bounds.size * 0.5) * factor
	store_preview_root.add_child(preview)
	_start_store_preview_rotation()

func _build_store_fallback_preview(weapon: Dictionary) -> void:
	var color := Color(weapon.color)
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.42)
	material.metallic = 0.72
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = color * 0.35
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(2.5, 0.58, 0.62)
	body_mesh.material = material
	body.mesh = body_mesh
	store_preview_root.add_child(body)
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.16
	barrel_mesh.bottom_radius = 0.2
	barrel_mesh.height = 2.2
	barrel_mesh.material = material
	barrel.mesh = barrel_mesh
	barrel.rotation_degrees.z = 90.0
	barrel.position.x = 1.65
	store_preview_root.add_child(barrel)

func _start_store_preview_rotation() -> void:
	store_preview_root.rotation_degrees = Vector3(-8, -28, 4)
	store_preview_tween = store_preview_root.create_tween().set_loops()
	store_preview_tween.tween_property(store_preview_root, "rotation_degrees:y", 332.0, 12.0).from(-28.0)

func _format_store_price(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result

func _store_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _panel_style(fill, border, 2)
	style.set_border_width_all(2)
	return style

func _show_options() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 15)
	body.add_child(_label(tr("OPTIONS"), 28, Color(0.72, 0.94, 1.0)))
	body.add_child(_slider_row(tr("SOUND VOLUME"), "sfx", 0.0, 1.0, 0.05))
	body.add_child(_slider_row(tr("MUSIC VOLUME"), "music", 0.0, 1.0, 0.05))
	body.add_child(_slider_row(tr("LOOK SENSITIVITY"), "look_sensitivity", 0.08, 0.65, 0.01))
	body.add_child(_quality_row())
	body.add_child(_language_row())
	var invert := CheckButton.new()
	invert.text = tr("INVERT VERTICAL LOOK")
	invert.button_pressed = bool(GameState.settings.invert_y)
	invert.toggled.connect(func(value): GameState.set_setting("invert_y", value))
	body.add_child(invert)
	if OS.has_feature("mobile"):
		var touch := CheckButton.new()
		touch.text = tr("SHOW MOBILE TOUCH CONTROLS")
		touch.button_pressed = bool(GameState.settings.show_touch_controls)
		touch.toggled.connect(func(value): GameState.set_setting("show_touch_controls", value))
		body.add_child(touch)
	_show_modal(body, Vector2(650, 560))

func _quality_row() -> Control:
	var labels := {"low": tr("LOW"), "medium": tr("MEDIUM"), "high": tr("HIGH")}
	var options: Array[String] = []
	for key: String in GameState.QUALITY_ORDER:
		options.append(str(labels.get(key, key)))
	var current := GameState.QUALITY_ORDER.find(str(GameState.settings.quality))
	return _option_row(tr("GRAPHICS QUALITY"), options, maxi(0, current), func(index: int):
		GameState.set_setting("quality", GameState.QUALITY_ORDER[index])
	)

func _language_row() -> Control:
	# Selecting a language rebuilds the menu so every recovered string is drawn
	# in the new locale straight away.
	var codes := Localization.SUPPORTED_LOCALES
	var options: Array[String] = []
	var current := 0
	# Resolve the stored preference (which may be "" for auto) to a concrete
	# supported code so the dropdown always highlights the active language,
	# regardless of how the TranslationServer normalises the locale string.
	var active := Localization.resolve_locale(str(GameState.settings.language))
	for i in range(codes.size()):
		options.append(Localization.locale_display_name(codes[i]))
		if codes[i] == active:
			current = i
	return _option_row(tr("LANGUAGE"), options, current, func(index: int):
		GameState.set_setting("language", codes[index])
		AudioDirector.play_ui("accept")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)

func _option_row(label_text: String, options: Array[String], selected_index: int, on_select: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := _label(label_text, 15, Color.WHITE)
	label.custom_minimum_size.x = 220
	row.add_child(label)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(300, 40)
	for option_text in options:
		picker.add_item(option_text)
	picker.select(clampi(selected_index, 0, maxi(0, options.size() - 1)))
	picker.item_selected.connect(func(index: int): on_select.call(index))
	row.add_child(picker)
	return row

func _show_help() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.add_child(_label(tr("FIELD MANUAL"), 28, Color(0.72, 0.94, 1.0)))
	body.add_child(_label(tr("DESKTOP"), 18, Color(1.0, 0.78, 0.24)))
	body.add_child(_label(tr("WASD move  •  Mouse aim  •  LMB fire  •  RMB focus  •  R previous weapon  •  Shift dash"), 15, Color.WHITE))
	body.add_child(_label(tr("1–4 switch weapon  •  Mouse wheel camera distance  •  Esc pause"), 15, Color.WHITE))
	body.add_child(_label(tr("CONTROLLER"), 18, Color(1.0, 0.78, 0.24)))
	body.add_child(_label(tr("Left stick move  •  Right stick aim  •  RB fire  •  LB focus  •  X previous weapon"), 15, Color.WHITE))
	body.add_child(_label(tr("MOBILE"), 18, Color(1.0, 0.78, 0.24)))
	body.add_child(_label(tr("Left thumbstick move  •  Drag right half to aim  •  FIRE / PREV / DASH buttons"), 15, Color.WHITE))
	body.add_child(_label(tr("Solo campaign and retired multiplayer maps now have separate offline entry points."), 13, Color(0.55, 0.72, 0.8)))
	_show_modal(body, Vector2(870, 410))

func _show_modal(body: Control, minimum_size: Vector2) -> void:
	_close_modal()
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.01, 0.03, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	var panel := PanelContainer.new()
	var viewport_size := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(
		minf(minimum_size.x, maxf(480.0, viewport_size.x - 32.0)),
		minf(minimum_size.y, maxf(360.0, viewport_size.y - 24.0))
	)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.065, 0.095, 0.985), Color(0.17, 0.78, 0.94, 0.9), 14))
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	panel.add_child(outer)
	outer.add_child(body)
	var close := Button.new()
	close.text = tr("BACK")
	close.custom_minimum_size.y = 45
	close.pressed.connect(func():
		AudioDirector.play_ui("back")
		_close_modal()
	)
	outer.add_child(close)
	call_deferred("_focus_control", close)

func _close_modal() -> void:
	if not is_instance_valid(modal_layer):
		return
	if store_preview_tween and store_preview_tween.is_valid():
		store_preview_tween.kill()
	store_preview_tween = null
	for child in modal_layer.get_children():
		child.queue_free()
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _slider_row(label_text: String, key: String, min_value: float, max_value: float, step: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := _label(label_text, 15, Color.WHITE)
	label.custom_minimum_size.x = 220
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(300, 36)
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = float(GameState.settings[key])
	slider.value_changed.connect(func(value): GameState.set_setting(key, value))
	row.add_child(slider)
	return row

func _menu_button(title_text: String, subtitle: String) -> Button:
	var button := Button.new()
	button.text = title_text + "\n" + subtitle
	button.custom_minimum_size = Vector2(450, 50)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.79, 0.92, 0.96))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _main_menu_button_style(Color(0.012, 0.024, 0.032, 0.78), Color(0.32, 0.43, 0.47, 0.82), 2))
	button.add_theme_stylebox_override("hover", _main_menu_button_style(Color(0.025, 0.105, 0.13, 0.9), Color(0.18, 0.82, 0.92, 1.0), 3))
	button.add_theme_stylebox_override("pressed", _main_menu_button_style(Color(0.035, 0.16, 0.19, 0.94), Color(0.42, 0.94, 1.0, 1.0), 3))
	button.add_theme_stylebox_override("focus", _main_menu_button_style(Color(0.02, 0.08, 0.1, 0.84), Color(0.18, 0.82, 0.92, 1.0), 3))
	return button

func _focus_control(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree():
		control.grab_focus()

func _main_menu_button_style(fill: Color, border: Color, left_border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = left_border
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
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
	# The plates are 2x source art, where a nine-patch would draw its corner
	# slices at native texture size - twice their intended scale - and buckle the
	# chamfered ends into visible steps. Leaving the texture margins at zero
	# stretches the plate whole, which holds its shape at any button size and
	# loses nothing, because the source has resolution to spare.
	style.content_margin_left = 20
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _bind_accept_sound(button: BaseButton) -> void:
	button.pressed.connect(func(): AudioDirector.play_ui("accept"))

func _level_preview(level_number: int) -> AtlasTexture:
	var index := GameState.CAMPAIGN_LEVELS.find(level_number)
	if index < 8:
		var rects := [
			Rect2(0, 0, 332, 180), Rect2(338, 0, 332, 180), Rect2(675, 0, 333, 180),
			Rect2(0, 184, 332, 180), Rect2(338, 184, 332, 180), Rect2(675, 184, 333, 180),
			Rect2(0, 369, 332, 178), Rect2(338, 369, 332, 178)
		]
		return Atlas.region("res://assets/original/ui/pages/15.png", rects[index])
	var late_rects := [
		Rect2(0, 0, 332, 180), Rect2(338, 0, 332, 180), Rect2(675, 0, 333, 180),
		Rect2(0, 184, 332, 180), Rect2(338, 184, 332, 180), Rect2(675, 184, 333, 180),
		Rect2(0, 369, 332, 180), Rect2(338, 369, 332, 180), Rect2(675, 369, 333, 180)
	]
	return Atlas.region("res://assets/original/ui/pages/20.png", late_rects[(index - 8) % late_rects.size()])

func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 19
	style.content_margin_right = 19
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	return style

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _start_music() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = &"Music"
	var path := "res://assets/original/audio/menu/menumusic.wav"
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream is AudioStreamWAV:
			stream = stream.duplicate()
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		music_player.stream = stream
		add_child(music_player)
		music_player.play()
