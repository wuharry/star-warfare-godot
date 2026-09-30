class_name WarfareScopeOverlay
extends Control

# Live camera view with a translucent surround. CoM reference and design
# differences are recorded in docs/WEAPON_AIMING.md; no recovered scope bitmap.
const SEGMENTS := 128
# Every reticle reports one thing about its own weapon. The shapes and colors
# are the accepted 2026-09-30 designs; only these readouts are new, and each
# reads live state the player already tracks. See docs/WEAPON_AIMING.md.
const READOUT_KEYS := ["cooldown_ratio", "magazine_rounds", "magazine_size", "uses_magazine",
	"target_distance", "weapon_range", "spread_ratio", "impact_offset", "on_enemy"]
const ALERT := Color(1.0, 0.36, 0.28, 0.95)
var optic: Dictionary = {}
var magnification := 2.0
var readout: Dictionary = {}

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

func set_readout(values: Dictionary) -> void:
	# Redraw only when a displayed value actually moved. The HUD refreshes this
	# every frame, and the surround is the most expensive part of _draw().
	for key: String in READOUT_KEYS:
		var before: Variant = readout.get(key)
		var after: Variant = values.get(key)
		if typeof(before) != typeof(after) or not _same(before, after):
			readout = values.duplicate()
			queue_redraw()
			return

func _same(before: Variant, after: Variant) -> bool:
	if before is float:
		return is_equal_approx(snappedf(float(before), 0.004), snappedf(float(after), 0.004))
	if before is Vector2:
		return Vector2(before).snapped(Vector2.ONE).is_equal_approx(Vector2(after).snapped(Vector2.ONE))
	return before == after

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
			# Upper marks stay static; the lower six are the magazine. A 0.24 s
			# cooldown is unreadable, but an automatic rifle does run dry, and
			# the ammo count is off-screen while scoped.
			for index in 6:
				_arc(center, 44.0 * ui_scale, -PI * 0.5 + float(index) * 0.22 + 0.025,
					-PI * 0.5 + float(index) * 0.22 + 0.18, color, 4.0 * ui_scale)
			_draw_magazine_gauge(center, ui_scale, color)
		"ladder":
			_stroke(center, Vector2(-8, 0), Vector2(8, 0), ui_scale)
			_stroke(center, Vector2(0, -8), Vector2(0, 10), ui_scale)
			for index in range(1, 4):
				var width := 10.0 + index * 6.0
				var y := index * 23.0
				_line(center, Vector2(-width, y) * ui_scale, Vector2(width, y) * ui_scale, ui_scale, 0.45)
				_line(center, Vector2(0, y - 4) * ui_scale, Vector2(0, y + 4) * ui_scale, ui_scale, 0.45)
			# The only arcing weapon. Its centre cross is the launch direction,
			# which is not where the grenade lands, so mark the solved impact.
			_draw_impact_marker(center, aperture, ui_scale, color)
		"precision_cross":
			# Display optic: fine long axes and evenly spaced index marks.
			for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_line(center, direction * 7.0 * ui_scale, direction * aperture * 0.88, ui_scale, 0.78)
				for tick in range(1, 5):
					var point := direction * float(tick) * 26.0
					var half_tick := direction.orthogonal() * (6.0 if tick % 2 == 0 else 3.0)
					_stroke(center, point - half_tick, point + half_tick, ui_scale)
			# 1000 damage on a 1.5 s cooldown: knowing when the next shot is
			# available matters more than any other readout on this weapon.
			_draw_cooldown_ring(center, aperture, ui_scale, color)
		"ring":
			for index in 4:
				var angle := index * PI * 0.5
				draw_arc(center, 23.0 * ui_scale, angle + 0.15, angle + PI * 0.5 - 0.15, 16, Color.BLACK, 4.0 * ui_scale, true)
				draw_arc(center, 23.0 * ui_scale, angle + 0.15, angle + PI * 0.5 - 0.15, 16, Color(optic.reticle_color), 1.6 * ui_scale, true)
			draw_circle(center, 1.8 * ui_scale, Color(optic.reticle_color))
			_stroke(center, Vector2(-9, -40), Vector2(0, -30), ui_scale)
			_stroke(center, Vector2(0, -30), Vector2(9, -40), ui_scale)
			# At 6x everything inside 180 m looks the same size, so the player
			# cannot tell whether the target is still in range.
			_draw_range_scale(center, aperture, ui_scale, color)
		"t_post":
			# Long tube: clear upper half, horizontal wings and a lower post.
			for side: float in [-1.0, 1.0]:
				_line(center, Vector2(side * 18.0 * ui_scale, 0), Vector2(side * aperture * 0.87, 0), ui_scale, 0.8)
				for tick in range(1, 4):
					var x := side * float(tick) * 34.0
					_stroke(center, Vector2(x, 0), Vector2(x, 7), ui_scale)
			_line(center, Vector2(0, 7.0 * ui_scale), Vector2(0, aperture * 0.86), ui_scale, 0.8)
			# 6.67 rounds a second under a 6x optic. The post counts how long
			# the trigger has been held. Scoped fire has no cone of its own, so
			# these rungs are feedback on trigger discipline, not a hit area.
			var held := ceili(float(readout.get("spread_ratio", 0.0)) * 3.0 - 0.001)
			for tick in range(1, 4):
				var y := float(tick) * 30.0
				var half_width := 5.0 + float(tick) * 5.0
				if tick <= held:
					draw_line(center + Vector2(-half_width, y) * ui_scale, center + Vector2(half_width, y) * ui_scale,
						Color(0.06, 0.045, 0.015, 0.35), 5.4 * ui_scale, true)
					draw_line(center + Vector2(-half_width, y) * ui_scale, center + Vector2(half_width, y) * ui_scale,
						color.lightened(0.35), 3.4 * ui_scale, true)
				else:
					_line(center, Vector2(-half_width, y) * ui_scale, Vector2(half_width, y) * ui_scale, ui_scale, 0.55)
	# The ladder crosses at the firing ray; the compact ring draws its own dot.
	if str(optic.reticle) not in ["ladder", "ring"]:
		draw_circle(center, 3.1 * ui_scale, Color(0.06, 0.045, 0.015, 0.6))
		draw_circle(center, 1.5 * ui_scale, color)

func _draw_magazine_gauge(center: Vector2, ui_scale: float, color: Color) -> void:
	if not bool(readout.get("uses_magazine", false)):
		return
	var capacity := maxi(1, int(readout.get("magazine_size", 1)))
	var rounds := clampi(int(readout.get("magazine_rounds", capacity)), 0, capacity)
	var filled := ceili(float(rounds) / float(capacity) * 6.0)
	var low := rounds > 0 and float(rounds) / float(capacity) <= 0.25
	for index in 6:
		var angle := PI * 0.5 + float(index) * 0.22
		var segment := Color(color, color.a * 0.22) if index >= filled else (ALERT if low else color)
		_arc(center, 44.0 * ui_scale, angle + 0.025, angle + 0.18, segment, 4.0 * ui_scale)

func _draw_cooldown_ring(center: Vector2, aperture: float, ui_scale: float, color: Color) -> void:
	var ready := 1.0 - clampf(float(readout.get("cooldown_ratio", 0.0)), 0.0, 1.0)
	var radius := aperture * 0.97
	draw_arc(center, radius, 0.0, TAU, SEGMENTS, Color(color, color.a * 0.16), 2.4 * ui_scale, true)
	if ready <= 0.004:
		return
	# A closed ring means the next shot is available; the gap is the wait.
	_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * 0.999 * ready,
		color if ready > 0.995 else color.lightened(0.3), 2.4 * ui_scale)

func _draw_range_scale(center: Vector2, aperture: float, ui_scale: float, color: Color) -> void:
	var maximum := maxf(1.0, float(readout.get("weapon_range", 180.0)))
	var distance := float(readout.get("target_distance", maximum))
	var x := aperture * 0.70
	var top := -aperture * 0.5
	var bottom := aperture * 0.5
	_line(center, Vector2(x, top), Vector2(x, bottom), ui_scale, 0.42)
	for index in 7:
		var y := lerpf(top, bottom, float(index) / 6.0)
		var width := 8.0 if index % 3 == 0 else 4.0
		_line(center, Vector2(x, y), Vector2(x + width * ui_scale, y), ui_scale, 0.5)
	# Nothing was hit inside the weapon's range, so the ray ran to its end.
	var beyond := distance >= maximum - 0.5
	var mark := lerpf(top, bottom, clampf(distance / maximum, 0.0, 1.0))
	var marker := ALERT if beyond else color
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(x - 11.0 * ui_scale, mark - 5.0 * ui_scale),
		center + Vector2(x - 2.0 * ui_scale, mark),
		center + Vector2(x - 11.0 * ui_scale, mark + 5.0 * ui_scale),
	]), marker)
	var font := ThemeDB.fallback_font
	var font_size := maxi(10, roundi(14.0 * ui_scale))
	var label := "OUT" if beyond else str(roundi(distance))
	var at := center + Vector2(x + 13.0 * ui_scale, mark + font_size * 0.35)
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.04, 0.03, 0.01, 0.7))
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, marker)

func _draw_impact_marker(center: Vector2, aperture: float, ui_scale: float, color: Color) -> void:
	var offset: Variant = readout.get("impact_offset", Vector2.INF)
	if not offset is Vector2 or not Vector2(offset).is_finite():
		return
	# The solve runs the same arc projectile.gd integrates, so the ring marks
	# the ground the grenade actually reaches, not a guessed drop.
	var point := Vector2(offset).limit_length(aperture * 0.84)
	# A lofted grenade lands above the aim line at close range and below it
	# further out, so the connector has to work in both directions.
	var gap := 12.0 * ui_scale
	var reach := 9.0 * ui_scale
	if point.length() > gap + reach + 1.0:
		var along := point.normalized()
		draw_line(center + along * gap, center + point - along * reach,
			Color(color, color.a * 0.42), 1.4 * ui_scale, true)
	_arc(center + point, 9.0 * ui_scale, 0.0, TAU, color, 2.2 * ui_scale)
	draw_circle(center + point, 1.6 * ui_scale, color)

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
