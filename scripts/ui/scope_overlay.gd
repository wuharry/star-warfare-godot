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
	var rim := Color(1.0, 0.72, 0.20, 0.48)
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
	# Keep the three accepted amber styles. Vox-07 and R700 restore the
	# first design's ladder and compact ring; both use their original colors.
	var color := Color(optic.reticle_color)
	match str(optic.reticle):
		"segmented_ring":
			for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_line(center, direction * aperture * 0.43, direction * aperture * 0.93, ui_scale, 0.48)
				_stroke(center, direction * 18.0, direction * 48.0, ui_scale)
			_arc(center, 32.0 * ui_scale, 0.0, TAU, color, 1.6 * ui_scale)
			# Static direction marks, not a charge meter.
			for start: float in [-PI * 0.5, PI * 0.5]:
				for index in 6:
					var angle := start + float(index) * 0.22
					_arc(center, 44.0 * ui_scale, angle + 0.025, angle + 0.18, color, 4.0 * ui_scale)
		"ladder":
			_stroke(center, Vector2(-8, 0), Vector2(8, 0), ui_scale)
			_stroke(center, Vector2(0, -8), Vector2(0, 10), ui_scale)
			for index in range(1, 4):
				var width := 10.0 + index * 6.0
				var y := index * 23.0
				_stroke(center, Vector2(-width, y), Vector2(width, y), ui_scale)
				_stroke(center, Vector2(0, y - 4), Vector2(0, y + 4), ui_scale)
		"precision_cross":
			# Display optic: fine long axes and evenly spaced index marks.
			for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_line(center, direction * 7.0 * ui_scale, direction * aperture * 0.88, ui_scale, 0.78)
				for tick in range(1, 5):
					var point := direction * float(tick) * 26.0
					var half_tick := direction.orthogonal() * (6.0 if tick % 2 == 0 else 3.0)
					_stroke(center, point - half_tick, point + half_tick, ui_scale)
		"ring":
			for index in 4:
				var angle := index * PI * 0.5
				draw_arc(center, 23.0 * ui_scale, angle + 0.15, angle + PI * 0.5 - 0.15, 16, Color.BLACK, 4.0 * ui_scale, true)
				draw_arc(center, 23.0 * ui_scale, angle + 0.15, angle + PI * 0.5 - 0.15, 16, Color(optic.reticle_color), 1.6 * ui_scale, true)
			draw_circle(center, 1.8 * ui_scale, Color(optic.reticle_color))
			_stroke(center, Vector2(-9, -40), Vector2(0, -30), ui_scale)
			_stroke(center, Vector2(0, -30), Vector2(9, -40), ui_scale)
		"t_post":
			# Long tube: clear upper half, horizontal wings and a lower post.
			for side: float in [-1.0, 1.0]:
				_line(center, Vector2(side * 18.0 * ui_scale, 0), Vector2(side * aperture * 0.87, 0), ui_scale, 0.8)
				for tick in range(1, 4):
					var x := side * float(tick) * 34.0
					_stroke(center, Vector2(x, 0), Vector2(x, 7), ui_scale)
			_line(center, Vector2(0, 7.0 * ui_scale), Vector2(0, aperture * 0.86), ui_scale, 0.8)
			for tick in range(1, 4):
				var y := float(tick) * 30.0
				var half_width := 5.0 + float(tick) * 5.0
				_stroke(center, Vector2(-half_width, y), Vector2(half_width, y), ui_scale)
	# The ladder crosses at the firing ray; the compact ring draws its own dot.
	if str(optic.reticle) not in ["ladder", "ring"]:
		draw_circle(center, 3.1 * ui_scale, Color(0.06, 0.045, 0.015, 0.6))
		draw_circle(center, 1.5 * ui_scale, color)

func _stroke(center: Vector2, start: Vector2, end: Vector2, ui_scale: float) -> void:
	_line(center, start * ui_scale, end * ui_scale, ui_scale)

func _arc(center: Vector2, radius: float, start: float, end: float, color: Color, width: float) -> void:
	var points := maxi(4, ceili((end - start) / TAU * SEGMENTS))
	draw_arc(center, radius, start, end, points, Color(0.06, 0.045, 0.015, 0.35), width + 1.5, true)
	draw_arc(center, radius, start, end, points, color, width, true)

func _line(center: Vector2, start: Vector2, end: Vector2, ui_scale: float, opacity: float = 1.0) -> void:
	var color := Color(optic.reticle_color)
	color.a *= opacity
	draw_line(center + start, center + end, Color(0.06, 0.045, 0.015, 0.3 * opacity), 3.0 * ui_scale, true)
	draw_line(center + start, center + end, color, 1.5 * ui_scale, true)
