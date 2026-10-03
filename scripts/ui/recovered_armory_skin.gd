extends RefCounted
## Shared menu skin based on the armory's SW1 metal modules + CoM controls.
## Metal frames come from recovered atlases; nine-slicing preserves corner shapes.

const COMPONENTS := "res://assets/ui/components/"
const COM_ATLAS := "res://assets/recovered_sources/com/ui/CommonUI.png"
const COM_REGIONS := "res://assets/recovered_sources/com/ui/CommonUI.json"
const FONT := preload("res://assets/original/fonts/ZEROTWOS.ttf")
const DROPDOWN_CHECK := preload("res://assets/ui/components/dropdown_check.svg")
const DROPDOWN_CHECK_DISABLED := preload("res://assets/ui/components/dropdown_check_disabled.svg")
const DROPDOWN_CHECK_BLANK := preload("res://assets/ui/components/dropdown_check_blank.svg")
const CYAN := Color(0.40, 1.0, 1.0)
static var _frames: Dictionary = {}
static var _scaled_textures: Dictionary = {}


static func logical_texture(texture: Texture2D, key: String, scale: float) -> ImageTexture:
	if not _scaled_textures.has(key):
		# Keep every source pixel; only change the texture's logical drawing size.
		# Nine-patch margins are measured in this size, not the HD atlas pixels.
		var result := ImageTexture.create_from_image(texture.get_image())
		result.set_size_override(Vector2i(texture.get_size() * scale))
		_scaled_textures[key] = result
	return _scaled_textures[key]


static func com_sprite(key: String) -> AtlasTexture:
	if _frames.is_empty():
		_frames = JSON.parse_string(FileAccess.get_file_as_string(COM_REGIONS)).frames
	var r: Dictionary = _frames[key].frame
	var texture := AtlasTexture.new()
	texture.atlas = load(COM_ATLAS)
	texture.region = Rect2(r.x, r.y, r.w, r.h)
	texture.filter_clip = true
	return texture


static func sliced(texture: Texture2D, border: float, padding := Vector4(12, 8, 12, 8)) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, border)
		style.set_content_margin(side, padding[side])
	return style


static func plate(state := "normal", padding := Vector4(14, 4, 14, 4)) -> StyleBoxTexture:
	# CoM's compact button plates have complete bevels inside their named frame.
	# At half-size the 8px slices include the entire corner, with a thin rim.
	var frame := "PUTONG" if state in ["hover", "pressed"] else "HUIKUANG"
	var result := sliced(logical_texture(com_sprite(frame), frame, 0.5), 8, padding)
	if state == "normal":
		result.modulate_color = Color(0.50, 0.64, 0.70)
	if state == "hover":
		result.modulate_color = Color(1.1, 1.25, 1.25)
	if state == "disabled":
		result.modulate_color = Color(0.32, 0.40, 0.44)
	return result


static func panel() -> StyleBoxTexture:
	return sliced(logical_texture(load(COMPONENTS + "armory_detail_panel.png"), "panel", 0.25), 14, Vector4(14, 14, 14, 14))


static func focus() -> StyleBoxTexture:
	var result := plate("hover", Vector4.ZERO)
	result.draw_center = false
	return result


static func header() -> StyleBoxTexture:
	var texture := AtlasTexture.new()
	texture.atlas = load(COMPONENTS + "armory_nav_bar.png")
	# SW1's authored striped center, excluding baked phone currency symbols.
	texture.region = Rect2(360, 0, 900, 160)
	texture.filter_clip = true
	return sliced(texture, 20, Vector4.ZERO)


static func make_theme(include_menu_controls := false) -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 14
	# Opt in on the modal subtree only: the approved outer menu and shop keep
	# their original themes and authored button art.
	if include_menu_controls:
		_add_menu_controls(result)
	result.set_stylebox("panel", "PopupMenu", panel())
	result.set_stylebox("hover", "PopupMenu", plate("hover"))
	result.set_stylebox("panel", "TooltipPanel", panel())
	result.set_color("font_color", "TooltipLabel", Color(0.88, 0.96, 0.98))
	result.set_font_size("font_size", "TooltipLabel", 13)
	for key: String in ["font_color", "font_hover_color", "font_accelerator_color"]:
		result.set_color(key, "PopupMenu", CYAN if key == "font_hover_color" else Color(0.82, 0.93, 0.95))
	result.set_color("font_disabled_color", "PopupMenu", Color(0.42, 0.49, 0.51))
	result.set_constant("v_separation", "PopupMenu", 12)
	result.set_constant("h_separation", "PopupMenu", 10)
	result.set_constant("item_start_padding", "PopupMenu", 8)
	result.set_constant("item_end_padding", "PopupMenu", 12)
	result.set_constant("icon_max_width", "PopupMenu", 22)
	for key: String in ["checked", "radio_checked", "checked_disabled", "radio_checked_disabled"]:
		result.set_icon(key, "PopupMenu", com_sprite("xuanjiao"))
	for key: String in ["unchecked", "radio_unchecked", "unchecked_disabled", "radio_unchecked_disabled"]:
		result.set_icon(key, "PopupMenu", com_sprite("TransparentRect"))
	for type_name: String in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type_name, sliced(com_sprite("huadongtiao-3"), 3, Vector4(6, 6, 6, 6)))
		result.set_stylebox("scroll_focus", type_name, focus())
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var style := sliced(com_sprite("huadongtiao-1"), 3, Vector4(6, 10, 6, 10))
			style.modulate_color = Color.WHITE if state == "grabber" else CYAN
			result.set_stylebox(state, type_name, style)
		for key: String in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]:
			result.set_icon(key, type_name, com_sprite("TransparentRect"))
	return result


static func _add_menu_controls(result: Theme) -> void:
	for type_name: String in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			result.set_stylebox(state, type_name, plate("hover" if state == "hover_pressed" else state))
		result.set_stylebox("focus", type_name, focus())
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			result.set_color(key, type_name, _button_font_color(key))
		result.set_constant("outline_size", type_name, 0)
	var unchecked := logical_texture(com_sprite("baikuang"), "checkbox_empty", 0.22)
	for type_name: String in ["CheckButton", "CheckBox"]:
		for key: String in ["checked", "checked_disabled", "checked_mirrored", "checked_disabled_mirrored"]:
			result.set_icon(key, type_name, com_sprite("xuanjiao"))
		for key: String in ["unchecked", "unchecked_disabled", "unchecked_mirrored", "unchecked_disabled_mirrored"]:
			result.set_icon(key, type_name, unchecked)
		result.set_constant("h_separation", type_name, 12)
	result.set_stylebox("normal", "LineEdit", plate("normal", Vector4(12, 8, 12, 8)))
	result.set_stylebox("read_only", "LineEdit", plate("disabled", Vector4(12, 8, 12, 8)))
	result.set_stylebox("focus", "LineEdit", focus())
	result.set_color("font_color", "LineEdit", Color(0.88, 0.96, 0.98))
	result.set_color("font_placeholder_color", "LineEdit", Color(0.45, 0.53, 0.56))
	result.set_color("caret_color", "LineEdit", CYAN)
	result.set_color("selection_color", "LineEdit", Color(0.08, 0.48, 0.57, 0.9))
	result.set_stylebox("slider", "HSlider", sliced(com_sprite("huadongtiao-3"), 3, Vector4(3, 3, 3, 3)))
	for key: String in ["grabber_area", "grabber_area_highlight"]:
		var track := sliced(com_sprite("huadongtiao-1"), 3, Vector4(3, 3, 3, 3))
		track.modulate_color = CYAN if key == "grabber_area_highlight" else Color(0.50, 0.75, 0.80)
		result.set_stylebox(key, "HSlider", track)
	for key: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		result.set_icon(key, "HSlider", com_sprite("huadongtiao-1" if key == "grabber" else "huadongtiao-2"))
	result.set_stylebox("panel", "PanelContainer", panel())


static func _button_font_color(key: String) -> Color:
	if key == "font_disabled_color":
		return Color(0.45, 0.53, 0.56)
	return CYAN if key == "font_color" else Color.WHITE


static func style_button(button: Button, padding := Vector4(14, 4, 14, 4)) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, plate("hover" if state == "hover_pressed" else state, padding))
	button.add_theme_stylebox_override("focus", focus())
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(key, _button_font_color(key))


static func style_picker(picker: OptionButton, theme: Theme) -> void:
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		picker.add_theme_stylebox_override(state, plate(state, Vector4(16, 4, 36, 4)))
	picker.add_theme_stylebox_override("focus", focus())
	picker.add_theme_color_override("font_color", CYAN)
	picker.add_theme_color_override("font_hover_color", Color.WHITE)
	picker.add_theme_color_override("font_pressed_color", Color.WHITE)
	picker.add_theme_color_override("font_disabled_color", Color(0.45, 0.53, 0.56))
	picker.add_theme_icon_override("arrow", com_sprite("TransparentRect"))
	var popup := picker.get_popup()
	popup.theme = theme
	popup.prefer_native_menu = false
	# A small check denotes the saved choice; the metal hover frame denotes
	# keyboard/mouse focus. Equal icon extents keep every item label aligned.
	for key: String in ["checked", "radio_checked"]:
		popup.add_theme_icon_override(key, DROPDOWN_CHECK)
	for key: String in ["checked_disabled", "radio_checked_disabled"]:
		popup.add_theme_icon_override(key, DROPDOWN_CHECK_DISABLED)
	for key: String in ["unchecked", "radio_unchecked", "unchecked_disabled", "radio_unchecked_disabled"]:
		popup.add_theme_icon_override(key, DROPDOWN_CHECK_BLANK)
	# OptionButton's PopupMenu is a Window; explicitly assign the same skin.
	# It retains native focus, arrow keys, wheel scrolling and Escape handling.
	var arrow := chevron(picker, false)
	arrow.name = "RecoveredDropdownArrow"
	arrow.rotation_degrees = -90
	var place := func(): arrow.position = Vector2(picker.size.x - 32, (picker.size.y - 18) * 0.5)
	picker.resized.connect(place)
	place.call()
	popup.visibility_changed.connect(func(): arrow.rotation_degrees = 90 if popup.visible else -90)


static func chevron(parent: Control, right: bool) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = com_sprite("back")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(24, 18)
	icon.pivot_offset = icon.size * 0.5
	icon.flip_h = right
	parent.add_child(icon)
	return icon
