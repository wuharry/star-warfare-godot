class_name WarfareScopeOverlay
extends Control

# A transparent aperture over the existing game camera: no second viewport,
# baked scenery, or scaled bitmap mask. Each optic owns its own reticle; the
# recovered AimID sprite is used only outside this view.
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
	var outer_radius := size.length()
	var aperture := _aperture_points(center, radius)
	# Extend each edge away from the live center to cover the entire viewport.
	for index in aperture.size():
		var a := aperture[index]
		var b := aperture[(index + 1) % aperture.size()]
		draw_colored_polygon(PackedVector2Array([
			a, center + (a - center).normalized() * outer_radius,
			center + (b - center).normalized() * outer_radius, b,
		]), Color(0.008, 0.012, 0.016))
	draw_colored_polygon(aperture, Color(optic.lens_tint))
	aperture.append(aperture[0])
	draw_polyline(aperture, Color(0.055, 0.065, 0.08), 24.0 * ui_scale, true)
	draw_polyline(aperture, Color(optic.rim_color), 10.0 * ui_scale, true)
	draw_polyline(aperture, Color(optic.rim_color).lightened(0.25), ui_scale, true)
	_draw_reticle(center, ui_scale)
	var font := ThemeDB.fallback_font
	var font_size := maxi(12, roundi(19.0 * ui_scale))
	var text := str(magnification).trim_suffix(".0") + "×"
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_at := center + Vector2(-extent.x * 0.5, radius * 0.62)
	draw_string_outline(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(optic.reticle_color))

func _aperture_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if str(optic.aperture) == "pentagon":
		for point: Vector2 in [Vector2(0, -1), Vector2(0.95, -0.5), Vector2(0.95, 0.88), Vector2(-0.95, 0.88), Vector2(-0.95, -0.5)]:
			points.append(center + point * radius)
	elif str(optic.aperture) in ["portrait_screen", "square_screen"]:
		var width := 0.76 if str(optic.aperture) == "portrait_screen" else 0.93
		var bevel := 0.10
		for point: Vector2 in [Vector2(-width + bevel, -0.95), Vector2(width - bevel, -0.95), Vector2(width, -0.85), Vector2(width, 0.85), Vector2(width - bevel, 0.95), Vector2(-width + bevel, 0.95), Vector2(-width, 0.85), Vector2(-width, -0.85)]:
			points.append(center + point * radius)
	else:
		for index in SEGMENTS:
			points.append(center + Vector2.from_angle(TAU * float(index) / SEGMENTS) * radius)
	return points

func _draw_reticle(center: Vector2, ui_scale: float) -> void:
	# The central dot/tip always denotes the camera's actual firing ray. The
	# remaining marks guide orientation, not unimplemented ballistic ranging.
	match str(optic.reticle):
		"duplex":
			for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_line(center, direction * 7.0, direction * 90.0, ui_scale)
			draw_circle(center, 1.6 * ui_scale, Color(optic.reticle_color))
		"ladder":
			_line(center, Vector2(-8, 0), Vector2(8, 0), ui_scale)
			_line(center, Vector2(0, -8), Vector2(0, 10), ui_scale)
			for index in range(1, 4):
				var width := 10.0 + index * 6.0
				var y := index * 23.0
				_line(center, Vector2(-width, y), Vector2(width, y), ui_scale)
				_line(center, Vector2(0, y - 4), Vector2(0, y + 4), ui_scale)
		"chevron":
			_line(center, Vector2(-10, 10), Vector2.ZERO, ui_scale)
			_line(center, Vector2.ZERO, Vector2(10, 10), ui_scale)
			_line(center, Vector2(0, 28), Vector2(0, 96), ui_scale)
			for direction: float in [-1.0, 1.0]:
				_line(center, Vector2(direction * 35, 0), Vector2(direction * 110, 0), ui_scale)
		"grid_cross":
			_line(center, Vector2(-70, 0), Vector2(70, 0), ui_scale)
			_line(center, Vector2(0, -70), Vector2(0, 70), ui_scale)
			for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
				for tick in [-2, -1, 1, 2]:
					var point := axis * float(tick) * 24.0
					var half_tick := axis.orthogonal() * 4.0
					_line(center, point - half_tick, point + half_tick, ui_scale)
		"ring":
			for index in 4:
				var angle := index * PI * 0.5
				draw_arc(center, 23.0 * ui_scale, angle + 0.15, angle + PI * 0.5 - 0.15, 16, Color.BLACK, 4.0 * ui_scale, true)
				draw_arc(center, 23.0 * ui_scale, angle + 0.15, angle + PI * 0.5 - 0.15, 16, Color(optic.reticle_color), 1.6 * ui_scale, true)
			draw_circle(center, 1.8 * ui_scale, Color(optic.reticle_color))
			_line(center, Vector2(-9, -40), Vector2(0, -30), ui_scale)
			_line(center, Vector2(0, -30), Vector2(9, -40), ui_scale)

func _line(center: Vector2, start: Vector2, end: Vector2, ui_scale: float) -> void:
	draw_line(center + start * ui_scale, center + end * ui_scale, Color(0, 0, 0, 0.65), 3.0 * ui_scale, true)
	draw_line(center + start * ui_scale, center + end * ui_scale, Color(optic.reticle_color), 1.3 * ui_scale, true)
