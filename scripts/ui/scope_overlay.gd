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
	# Same stroke weight/color, distinct silhouettes. Only the ring optic uses
	# the CoM reference's segmented arcs; other optics are project designs.
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
		"open_chevron":
			# Compact sight: one open apex and two short side brackets.
			_stroke(center, Vector2(-21, 23), Vector2.ZERO, ui_scale)
			_stroke(center, Vector2.ZERO, Vector2(21, 23), ui_scale)
			for side: float in [-1.0, 1.0]:
				_stroke(center, Vector2(side * 48, -8), Vector2(side * 48, 12), ui_scale)
				_stroke(center, Vector2(side * 48, 12), Vector2(side * 61, 12), ui_scale)
		"precision_cross":
			# Display optic: fine long axes and evenly spaced index marks.
			for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_line(center, direction * 7.0 * ui_scale, direction * aperture * 0.88, ui_scale, 0.78)
				for tick in range(1, 5):
					var point := direction * float(tick) * 26.0
					var half_tick := direction.orthogonal() * (6.0 if tick % 2 == 0 else 3.0)
					_stroke(center, point - half_tick, point + half_tick, ui_scale)
		"bracket_diamond":
			# Electronic display: four disconnected corners, no circular ring.
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := corner * 41.0
				_stroke(center, point - Vector2(corner.x * 19.0, 0), point, ui_scale)
				_stroke(center, point, point - Vector2(0, corner.y * 19.0), ui_scale)
			var diamond: Array[Vector2] = [Vector2(0, -14), Vector2(14, 0), Vector2(0, 14), Vector2(-14, 0)]
			for index in diamond.size():
				_stroke(center, diamond[index], diamond[(index + 1) % diamond.size()], ui_scale)
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
	# All five styles keep this exact center on the camera's firing ray.
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
