class_name TouchActionButton
extends Control

const Atlas = preload("res://scripts/ui/original_atlas.gd")

signal pressed
signal released

@export var caption := "FIRE"
@export var accent := Color(0.15, 0.78, 1.0)

var active_touch := -1
var held := false
var recovered_background: Texture2D
var recovered_font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	recovered_background = Atlas.hud("skill_bk")
	var font_path := "res://assets/original/fonts/ZEROTWOS.ttf"
	if ResourceLoader.exists(font_path):
		recovered_font = load(font_path)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and active_touch < 0 and get_global_rect().has_point(event.position):
			active_touch = event.index
			held = true
			pressed.emit()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == active_touch:
			active_touch = -1
			held = false
			released.emit()
			queue_redraw()
			get_viewport().set_input_as_handled()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.45
	if recovered_background:
		var extent := Vector2.ONE * radius * 2.0
		var tint := Color(accent.r, accent.g, accent.b, 1.0 if held else 0.76)
		draw_texture_rect(recovered_background, Rect2(center - extent * 0.5, extent), false, tint)
	else:
		var fill := Color(accent.r, accent.g, accent.b, 0.68 if held else 0.32)
		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 48, Color(accent.r, accent.g, accent.b, 0.98), 3.0 if held else 2.0, true)
	var font := recovered_font if recovered_font else ThemeDB.fallback_font
	var font_size := int(clampf(radius * 0.34, 13.0, 23.0))
	var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center - Vector2(text_size.x * 0.5, -text_size.y * 0.28), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
