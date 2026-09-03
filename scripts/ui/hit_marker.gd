class_name WarfareHitMarker
extends Control

# TRANSITIONAL FEEDBACK ART
# This procedural marker is an intentionally replaceable bridge, not approved
# final art. Keep the signal contract (show_hit/show_kill) when replacing it
# with authored textures or animation. See docs/TRANSITIONAL_HITMARKER.md.

const HIT_DURATION := 0.085
const KILL_DURATION := 0.155
const HIT_COLOR := Color(0.56, 0.96, 1.0)
const KILL_COLOR := Color(1.0, 0.73, 0.2)

var feedback_kind := &""
var elapsed := 0.0
var duration := HIT_DURATION
var _last_hit_audio_msec := -1000
var _last_kill_audio_msec := -1000

func _ready() -> void:
	custom_minimum_size = Vector2(112.0, 112.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)

func show_hit(_actual_damage := 0.0) -> void:
	# Shotguns and splash weapons can confirm several damage applications on
	# one frame. Restart the visual but gate the UI tick so it stays crisp.
	# A splash hit enumerated after a lethal target must not downgrade the more
	# important kill confirmation that is already on screen.
	if feedback_kind == &"kill" and elapsed < KILL_DURATION:
		return
	feedback_kind = &"hit"
	elapsed = 0.0
	duration = HIT_DURATION
	visible = true
	set_process(true)
	queue_redraw()
	var now := Time.get_ticks_msec()
	if now - _last_hit_audio_msec >= 55:
		_last_hit_audio_msec = now
		# Recovered 82 ms UI chirp used only as transitional sound design.
		AudioDirector.play_2d("menu/exp.wav", -14.0, 1.08)

func show_kill() -> void:
	feedback_kind = &"kill"
	elapsed = 0.0
	duration = KILL_DURATION
	visible = true
	set_process(true)
	queue_redraw()
	# The original short combo cue keeps this pass asset-free. It is explicitly
	# temporary and should be replaced together with final hit-confirm art.
	var now := Time.get_ticks_msec()
	if now - _last_kill_audio_msec >= 65:
		_last_kill_audio_msec = now
		AudioDirector.play_2d("pickup/killcombo.wav", -9.0, 1.02)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		feedback_kind = &""
		visible = false
		set_process(false)
	queue_redraw()

func _draw() -> void:
	if feedback_kind == &"":
		return
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	var alpha := _feedback_alpha(progress)
	var center := size * 0.5
	var is_kill := feedback_kind == &"kill"
	var accent := KILL_COLOR if is_kill else HIT_COLOR
	var travel := 1.0 - pow(1.0 - progress, 3.0)
	var inner_radius := lerpf(13.5, 17.0 if is_kill else 15.5, travel)
	var outer_radius := lerpf(22.0, 29.0 if is_kill else 25.0, travel)

	for direction in [
		Vector2(-1.0, -1.0).normalized(),
		Vector2(1.0, -1.0).normalized(),
		Vector2(1.0, 1.0).normalized(),
		Vector2(-1.0, 1.0).normalized(),
	]:
		_draw_marker_arm(center, direction, inner_radius, outer_radius, accent, alpha)
		if is_kill:
			# A separated outer segment makes a kill legible without enlarging the
			# central X or covering the recovered crosshair texture.
			_draw_marker_arm(center, direction, outer_radius + 3.0, outer_radius + 7.5, Color.WHITE, alpha * 0.88, 1.25)

func _feedback_alpha(progress: float) -> float:
	var attack := clampf(progress / 0.14, 0.0, 1.0)
	var release := pow(clampf(1.0 - progress, 0.0, 1.0), 1.35)
	return attack * release

func _draw_marker_arm(
	center: Vector2,
	direction: Vector2,
	inner_radius: float,
	outer_radius: float,
	color: Color,
	alpha: float,
	core_width := 1.7
) -> void:
	var start := center + direction * inner_radius
	var finish := center + direction * outer_radius
	var perpendicular := Vector2(-direction.y, direction.x)
	# Dark separation and a restrained cyan/gold bloom keep the fine core
	# readable over both the bright snow arenas and the dark spacecraft maps.
	draw_line(start, finish, Color(0.0, 0.025, 0.05, alpha * 0.72), core_width + 3.6, true)
	draw_line(start, finish, Color(color.r, color.g, color.b, alpha * 0.18), core_width + 5.2, true)
	var taper := PackedVector2Array([
		start - perpendicular * core_width * 0.72,
		finish - perpendicular * core_width * 0.35,
		finish + perpendicular * core_width * 0.35,
		start + perpendicular * core_width * 0.72,
	])
	draw_colored_polygon(taper, Color(color.r, color.g, color.b, alpha))
	draw_line(start + direction * 1.0, finish - direction * 1.0, Color(1.0, 1.0, 1.0, alpha * 0.82), 0.75, true)
