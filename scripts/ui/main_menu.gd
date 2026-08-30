extends Control

const Atlas = preload("res://scripts/ui/original_atlas.gd")

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

	var hero_texture := Atlas.region("res://assets/original/ui/pages/16.png", Rect2(0, 0, 1024, 650))
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
	content.add_theme_constant_override("separation", 12)
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
	var profile := _label("OFFLINE OPERATIVE", 16, Color(0.43, 0.9, 1.0))
	status.add_child(profile)
	status.add_child(_label("CREDITS  %07d" % GameState.credits, 25, Color(0.98, 0.77, 0.24)))
	status.add_child(_label("LOCAL SAVE • NO SERVER REQUIRED", 12, Color(0.62, 0.72, 0.78)))

	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)

func _build_main_buttons() -> void:
	var logo_texture := Atlas.region("res://assets/original/ui/pages/2.png", Rect2(5, 180, 500, 112))
	if logo_texture:
		var logo := TextureRect.new()
		logo.texture = logo_texture
		logo.custom_minimum_size = Vector2(460, 103)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The legacy atlas packs a yellow reward coin partly over the title's
		# rectangular bounds. It was a separate widget in NGUI, so discard only
		# that packed yellow overlay when drawing the standalone logo.
		var logo_shader := Shader.new()
		logo_shader.code = "shader_type canvas_item; void fragment(){ vec4 c = texture(TEXTURE, UV); if(c.r > .72 && c.g > .52 && c.b < .22) c.a = 0.0; COLOR = c * COLOR; }"
		var logo_material := ShaderMaterial.new()
		logo_material.shader = logo_shader
		logo.material = logo_material
		content.add_child(logo)
		var subtitle_texture := Atlas.region("res://assets/original/ui/pages/2.png", Rect2(4, 495, 415, 60))
		var subtitle_logo := TextureRect.new()
		subtitle_logo.texture = subtitle_texture
		subtitle_logo.custom_minimum_size = Vector2(410, 54)
		subtitle_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		subtitle_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		subtitle_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(subtitle_logo)
	else:
		content.add_child(_label("STAR WARFARE", 62, Color(0.95, 0.99, 1.0)))
	content.add_child(_label("LOCAL OFFLINE RESTORATION", 14, Color(0.33, 0.82, 0.94)))

	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	content.add_child(gap)

	var play := _menu_button("START", "SOLO MISSION")
	_bind_accept_sound(play)
	play.pressed.connect(_show_level_select)
	content.add_child(play)
	var armory := _menu_button("SHOP & CUSTOMIZE", "47 RECOVERED WEAPONS")
	_bind_accept_sound(armory)
	armory.pressed.connect(_show_armory)
	content.add_child(armory)
	var options := _menu_button("OPTIONS", "Audio, aim and touch controls")
	_bind_accept_sound(options)
	options.pressed.connect(_show_options)
	content.add_child(options)
	var help := _menu_button("FIELD MANUAL", "Desktop, controller and mobile controls")
	_bind_accept_sound(help)
	help.pressed.connect(_show_help)
	content.add_child(help)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := _menu_button("QUIT", "Return to desktop")
		_bind_accept_sound(quit)
		quit.pressed.connect(get_tree().quit)
		content.add_child(quit)

func _build_footer() -> void:
	var footer := Label.new()
	footer.text = "COMM-LINK OFFLINE   •   ORIGINAL ONLINE SERVICES RETIRED   •   GODOT 4 RESTORATION"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.38, 0.58, 0.67))
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.position = Vector2(56, -35)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)

func _show_level_select() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.add_child(_label("SELECT SECTOR", 28, Color(0.72, 0.94, 1.0)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1050, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 9)
	scroll.add_child(grid)
	for level_number in GameState.CAMPAIGN_LEVELS:
		var data: Dictionary = GameState.get_level_data(level_number)
		var button := Button.new()
		button.text = "%02d  %s" % [level_number, str(data.name)]
		button.custom_minimum_size = Vector2(252, 108)
		button.icon = _level_preview(level_number)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.025, 0.12, 0.17, 0.96), Color(0.12, 0.52, 0.66, 0.8), 7))
		button.add_theme_stylebox_override("hover", _panel_style(Color(0.05, 0.32, 0.4, 0.98), Color(0.35, 0.9, 1.0, 1.0), 7))
		_bind_accept_sound(button)
		button.pressed.connect(func(): GameState.start_level(level_number))
		grid.add_child(button)
	_show_modal(body, Vector2(1130, 665))

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
	backdrop.texture = Atlas.region("res://assets/original/ui/pages/4.png", Rect2(1568, 0, 480, 640))
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
	back.text = "◀  BACK"
	back.custom_minimum_size = Vector2(150, 54)
	back.add_theme_stylebox_override("normal", _recovered_button_style(Rect2(632, 0, 361, 56), Color(0.78, 0.95, 1.0)))
	back.pressed.connect(func(): AudioDirector.play_ui("back"); _close_modal())
	nav.add_child(back)
	var title := _label("STORE", 31, Color(0.72, 1.0, 1.0))
	title.custom_minimum_size.x = 230
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(title)
	var customize := Button.new()
	customize.text = "CUSTOMIZE"
	customize.custom_minimum_size = Vector2(175, 54)
	customize.disabled = true
	nav.add_child(customize)
	var nav_space := Control.new()
	nav_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_space)
	var credits := _label("CREDITS  %07d" % GameState.credits, 21, Color(1.0, 0.77, 0.2))
	credits.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(credits)

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
	var preview_header := _label("EQUIPMENT DISPLAY", 15, Color(0.32, 0.92, 1.0))
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
	store_equip_button = Button.new()
	store_equip_button.text = "EQUIP"
	store_equip_button.custom_minimum_size.y = 58
	store_equip_button.add_theme_font_size_override("font_size", 22)
	store_equip_button.add_theme_stylebox_override("normal", _recovered_button_style(Rect2(632, 428, 361, 56), Color(0.74, 1.0, 0.95)))
	store_equip_button.pressed.connect(_equip_store_selection)
	detail_column.add_child(store_equip_button)

	var tabs := HBoxContainer.new()
	tabs.custom_minimum_size.y = 42
	tabs.add_theme_constant_override("separation", 6)
	page.add_child(tabs)
	for tab_name in ["RIFLE", "SHOTGUN", "HEAVY", "SPECIAL", "MELEE", "ALL"]:
		var tab := Button.new()
		tab.text = tab_name
		tab.custom_minimum_size = Vector2(128, 38)
		tab.disabled = tab_name != "ALL"
		tabs.add_child(tab)
	var rail := ScrollContainer.new()
	rail.custom_minimum_size.y = 118
	rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(rail)
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 7)
	rail.add_child(weapon_row)
	for weapon_id: String in GameState.get_weapon_ids():
		var weapon: Dictionary = GameState.WEAPONS[weapon_id]
		var button := Button.new()
		button.tooltip_text = str(weapon.name)
		button.icon = Atlas.weapon_icon(int(weapon.id))
		button.expand_icon = true
		button.custom_minimum_size = Vector2(142, 102)
		button.add_theme_stylebox_override("normal", _store_panel_style(Color(0.02, 0.05, 0.06, 0.95), Color(weapon.color, 0.38)))
		button.add_theme_stylebox_override("hover", _store_panel_style(Color(weapon.color, 0.14), Color(weapon.color, 1.0)))
		button.pressed.connect(_select_store_weapon.bind(weapon_id))
		weapon_row.add_child(button)
	_select_store_weapon(GameState.selected_weapon)

func _select_store_weapon(weapon_id: String) -> void:
	if not GameState.WEAPONS.has(weapon_id):
		return
	store_selected_weapon = weapon_id
	var weapon: Dictionary = GameState.WEAPONS[weapon_id]
	store_name.text = str(weapon.name)
	store_name.add_theme_color_override("font_color", Color(weapon.color))
	store_type.text = "TYPE %02d   •   AIM HUD %02d" % [int(weapon.type), int(weapon.aim_id)]
	store_stats.text = "DAMAGE                 %d\nRATE OF FIRE          %.2f / SEC\nENERGY PER SHOT       %d\nEFFECTIVE RANGE       %d\n\nRecovered directly from the original equipment database." % [int(weapon.damage), float(weapon.fire_rate), int(weapon.energy), int(weapon.range)]
	store_price.text = "PRICE  %s CREDITS" % _format_store_price(int(weapon.price))
	store_equipped.text = "CURRENTLY EQUIPPED" if weapon_id == GameState.selected_weapon else "AVAILABLE IN OFFLINE RESTORATION"
	store_equip_button.text = "EQUIPPED" if weapon_id == GameState.selected_weapon else "EQUIP"
	store_equip_button.disabled = weapon_id == GameState.selected_weapon
	_rebuild_store_preview(weapon)
	AudioDirector.play_ui("switch", -5.0)

func _equip_store_selection() -> void:
	if store_selected_weapon.is_empty():
		return
	GameState.set_weapon(store_selected_weapon)
	AudioDirector.play_ui("mount_weapon")
	_select_store_weapon(store_selected_weapon)

func _rebuild_store_preview(weapon: Dictionary) -> void:
	if not is_instance_valid(store_preview_root):
		return
	for child in store_preview_root.get_children():
		child.queue_free()
	var mesh_path := "res://assets/models/weapons/%s.obj" % str(weapon.model)
	if not ResourceLoader.exists(mesh_path):
		return
	var preview := MeshInstance3D.new()
	preview.mesh = load(mesh_path)
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
	store_preview_root.rotation_degrees = Vector3(-8, -28, 4)
	var tween := store_preview_root.create_tween().set_loops()
	tween.tween_property(store_preview_root, "rotation_degrees:y", 332.0, 12.0).from(-28.0)

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
	body.add_child(_label("OPTIONS", 28, Color(0.72, 0.94, 1.0)))
	body.add_child(_slider_row("SOUND VOLUME", "sfx", 0.0, 1.0, 0.05))
	body.add_child(_slider_row("MUSIC VOLUME", "music", 0.0, 1.0, 0.05))
	body.add_child(_slider_row("LOOK SENSITIVITY", "look_sensitivity", 0.08, 0.65, 0.01))
	var invert := CheckButton.new()
	invert.text = "INVERT VERTICAL LOOK"
	invert.button_pressed = bool(GameState.settings.invert_y)
	invert.toggled.connect(func(value): GameState.set_setting("invert_y", value))
	body.add_child(invert)
	if OS.has_feature("mobile"):
		var touch := CheckButton.new()
		touch.text = "SHOW MOBILE TOUCH CONTROLS"
		touch.button_pressed = bool(GameState.settings.show_touch_controls)
		touch.toggled.connect(func(value): GameState.set_setting("show_touch_controls", value))
		body.add_child(touch)
	_show_modal(body, Vector2(650, 430))

func _show_help() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.add_child(_label("FIELD MANUAL", 28, Color(0.72, 0.94, 1.0)))
	body.add_child(_label("DESKTOP", 18, Color(1.0, 0.78, 0.24)))
	body.add_child(_label("WASD move  •  Mouse aim  •  LMB fire  •  RMB focus  •  R previous weapon  •  Shift dash", 15, Color.WHITE))
	body.add_child(_label("1–4 switch weapon  •  Mouse wheel camera distance  •  Esc pause", 15, Color.WHITE))
	body.add_child(_label("CONTROLLER", 18, Color(1.0, 0.78, 0.24)))
	body.add_child(_label("Left stick move  •  Right stick aim  •  RB fire  •  LB focus  •  X previous weapon", 15, Color.WHITE))
	body.add_child(_label("MOBILE", 18, Color(1.0, 0.78, 0.24)))
	body.add_child(_label("Left thumbstick move  •  Drag right half to aim  •  FIRE / PREV / DASH buttons", 15, Color.WHITE))
	body.add_child(_label("The retired network modes are intentionally replaced by offline campaign play.", 13, Color(0.55, 0.72, 0.8)))
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
	panel.custom_minimum_size = minimum_size
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.065, 0.095, 0.985), Color(0.17, 0.78, 0.94, 0.9), 14))
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	panel.add_child(outer)
	outer.add_child(body)
	var close := Button.new()
	close.text = "BACK"
	close.custom_minimum_size.y = 45
	close.pressed.connect(func():
		AudioDirector.play_ui("back")
		_close_modal()
	)
	outer.add_child(close)

func _close_modal() -> void:
	if not is_instance_valid(modal_layer):
		return
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
	button.custom_minimum_size = Vector2(450, 58)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.79, 0.92, 0.96))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _recovered_button_style(Rect2(632, 0, 361, 56), Color(0.72, 0.92, 1.0, 0.96)))
	button.add_theme_stylebox_override("hover", _recovered_button_style(Rect2(632, 60, 361, 56), Color.WHITE))
	button.add_theme_stylebox_override("pressed", _recovered_button_style(Rect2(632, 120, 361, 56), Color(0.72, 1.0, 1.0)))
	return button

func _recovered_button_style(rectangle: Rect2, tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = Atlas.region("res://assets/original/ui/pages/4.png", rectangle)
	style.modulate_color = tint
	style.set_texture_margin_all(12)
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
