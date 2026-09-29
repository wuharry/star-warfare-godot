class_name WarfareScopeOverlay
extends Control

# Live camera view with a translucent surround. CoM reference and design
# differences are recorded in docs/WEAPON_AIMING.md; no recovered scope bitmap.
const SEGMENTS := 128
var optic: Dictionary = {}
var magnification := 2.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	hide()

func configure(profile: Dictionary, zoom: float) -> void:
	if optic != profile or not is_equal_approx(magnification, zoom):
		optic = profile
		magnification = zoom
		queue_redraw()

func aperture_radius() -> float:
	return minf(size.x, size.y) * 0.43

func _draw() -> void:
	if optic.is_empty():
		return
	var center := size * 0.5
	var radius := aperture_radius()
	var ui_scale := minf(size.x / 960.0, size.y / 640.0)
	_draw_surround(center, radius)
	draw_circle(center, radius, Color(optic.lens_tint))
	var rim := Color(optic.reticle_color)
	rim.a = 0.48
	draw_arc(center, radius, 0.0, TAU, SEGMENTS + 1, rim, maxf(1.0, ui_scale), true)
	_draw_reticle(center, radius, ui_scale)
	var font := ThemeDB.fallback_font
	var font_size := maxi(12, roundi(19.0 * ui_scale))
	var text := str(magnification).trim_suffix(".0") + "×"
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# Keep the label clear of the bottom guide line and touch controls.
	var text_at := center + Vector2(radius * 0.25 - extent.x * 0.5, radius * 0.69)
	draw_string_outline(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.04, 0.03, 0.01, 0.7))
	draw_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(optic.reticle_color))

func _draw_surround(center: Vector2, radius: float) -> void:
	# Vertex alpha darkens the periphery without replacing the scene with solid
	# panels. The center remains the same magnified camera; this is not PIP zoom.
	var outer_radius := size.length()
	var colors := PackedColorArray([
		Color(0.015, 0.025, 0.035, 0.46), Color(0.015, 0.025, 0.035, 0.76),
		Color(0.015, 0.025, 0.035, 0.76), Color(0.015, 0.025, 0.035, 0.46),
	])
	for index in SEGMENTS:
		var a := Vector2.from_angle(TAU * float(index) / SEGMENTS)
		var b := Vector2.from_angle(TAU * float(index + 1) / SEGMENTS)
		draw_polygon(PackedVector2Array([
			center + a * radius, center + a * outer_radius,
			center + b * outer_radius, center + b * radius,
		]), colors)

func _draw_reticle(center: Vector2, aperture: float, ui_scale: float) -> void:
	# All optics share the amber ring/cross family. Ring size and small ticks
	# belong to each weapon's optic, independently of its hip-fire AimID.
	var scale := ui_scale * float(optic.reticle_scale)
	var ring := 32.0 * scale
	var color := Color(optic.reticle_color)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_line(center, direction * aperture * 0.43, direction * aperture * 0.93, ui_scale, 0.48)
		_line(center, direction * 18.0 * scale, direction * 48.0 * scale, ui_scale)
	_arc(center, ring, 0.0, TAU, color, 1.6 * ui_scale)
	# Static index marks, not a charge meter or a claim of ballistic ranging.
	for start: float in [-PI * 0.5, PI * 0.5]:
		for index in 6:
			var angle := start + float(index) * 0.22
			_arc(center, 44.0 * scale, angle + 0.025, angle + 0.18, color, 4.0 * ui_scale)
	for index in int(optic.reticle_ticks):
		var y := 65.0 * scale + float(index) * 18.0 * scale
		var width := (5.0 + float(index) * 2.0) * scale
		_line(center, Vector2(-width, y), Vector2(width, y), ui_scale, 0.72)
	# This dot, not a ring edge, denotes the actual camera firing ray.
	draw_circle(center, 3.1 * ui_scale, Color(0.06, 0.045, 0.015, 0.6))
	draw_circle(center, 1.5 * ui_scale, color)

func _arc(center: Vector2, radius: float, start: float, end: float, color: Color, width: float) -> void:
	var points := maxi(4, ceili((end - start) / TAU * SEGMENTS))
	draw_arc(center, radius, start, end, points, Color(0.06, 0.045, 0.015, 0.35), width + 1.5, true)
	draw_arc(center, radius, start, end, points, color, width, true)

func _line(center: Vector2, start: Vector2, end: Vector2, ui_scale: float, opacity: float = 1.0) -> void:
	var color := Color(optic.reticle_color)
	color.a *= opacity
	draw_line(center + start, center + end, Color(0.06, 0.045, 0.015, 0.3 * opacity), 3.0 * ui_scale, true)
	draw_line(center + start, center + end, color, 1.5 * ui_scale, true)
