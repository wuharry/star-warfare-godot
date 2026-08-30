class_name WarfareVirtualJoystick
extends Control

const Atlas = preload("res://scripts/ui/original_atlas.gd")

signal vector_changed(value: Vector2)
signal engaged
signal released

var active_touch := -1
var value := Vector2.ZERO
var knob_position := Vector2.ZERO
var radius := 78.0
var deadzone := 0.12
var recovered_background: Texture2D
var recovered_knob: Texture2D
var background_sprite := "hud_37"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	recovered_background = Atlas.hud(background_sprite)
	recovered_knob = Atlas.hud("hud_38")
	knob_position = size * 0.5
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		knob_position = size * 0.5 if active_touch < 0 else knob_position
		queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and active_touch < 0 and get_global_rect().has_point(event.position):
			active_touch = event.index
			engaged.emit()
			_update_from_screen(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == active_touch:
			active_touch = -1
			value = Vector2.ZERO
			knob_position = size * 0.5
			vector_changed.emit(value)
			released.emit()
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == active_touch:
		_update_from_screen(event.position)
		get_viewport().set_input_as_handled()

func _update_from_screen(screen_position: Vector2) -> void:
	var local_position := screen_position - global_position
	var center := size * 0.5
	var offset := local_position - center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	knob_position = center + offset
	value = offset / radius
	if value.length() < deadzone:
		value = Vector2.ZERO
	else:
		value = value.normalized() * inverse_lerp(deadzone, 1.0, minf(value.length(), 1.0))
	vector_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	if recovered_background and recovered_knob:
		var background_size := Vector2.ONE * (radius + 18.0) * 2.0
		draw_texture_rect(recovered_background, Rect2(center - background_size * 0.5, background_size), false, Color(1, 1, 1, 0.72))
		var knob_size := Vector2(72, 72)
		draw_texture_rect(recovered_knob, Rect2(knob_position - knob_size * 0.5, knob_size), false, Color(1, 1, 1, 0.88))
	else:
		draw_circle(center, radius + 10.0, Color(0.02, 0.09, 0.13, 0.38))
		draw_arc(center, radius + 10.0, 0.0, TAU, 64, Color(0.18, 0.76, 0.94, 0.58), 2.0, true)
		draw_circle(knob_position, 31.0, Color(0.19, 0.77, 0.94, 0.72))
