class_name WarfareHipReticle
extends Control

# Translate regions of the recovered AimID sprite. Source pixels always use
# the same UI scale: only the gaps grow, never the strokes or the centre mark.
const Atlas = preload("res://scripts/ui/original_atlas.gd")

# Visual feedback owns its recovery curve independently from bullet spread.
# Sample an analytic curve so recovery is identical at different frame rates.
class Bloom:
	extends RefCounted
	const SHOT_STEP := 0.12
	const RECOVERY_DELAY := 0.08
	const RECOVERY_ACCELERATION := 6.0
	var ratio := 0.0
	var since_shot := 0.0
	var recovery_origin := 0.0

	func reset() -> void:
		ratio = 0.0
		since_shot = 0.0
		recovery_origin = 0.0

	func fire() -> void:
		ratio = minf(1.0, ratio + SHOT_STEP)
		recovery_origin = ratio
		since_shot = 0.0

	func advance(delta: float) -> void:
		if ratio <= 0.0:
			return
		since_shot += maxf(0.0, delta)
		var recovering_seconds := maxf(0.0, since_shot - RECOVERY_DELAY)
		ratio = maxf(0.0, recovery_origin - 0.5 * RECOVERY_ACCELERATION * recovering_seconds * recovering_seconds)

var texture: Texture2D
var source_scale := 1.0
var segment_offset := Vector2.ZERO
var _pieces: Array[Dictionary] = []

func configure(source: Texture2D, aim_id: int) -> void:
	texture = source
	_pieces.clear()
	if texture != null:
		_build_pieces(aim_id)
	queue_redraw()

func update_spread(ui_scale: float, spread_ratio: float, max_scale: float) -> void:
	if texture == null:
		return
	var next_scale := ui_scale / Atlas.SOURCE_PIXEL_SCALE
	var base_size := texture.get_size() * next_scale
	var next_offset := base_size * maxf(0.0, max_scale - 1.0) * 0.5 * clampf(spread_ratio, 0.0, 1.0)
	if not is_equal_approx(source_scale, next_scale) or not segment_offset.is_equal_approx(next_offset):
		source_scale = next_scale
		segment_offset = next_offset
		queue_redraw()
	# This is padding for translated pieces, not a scale applied to the sprite.
	custom_minimum_size = base_size + segment_offset * 2.0
	size = custom_minimum_size
	pivot_offset = size * 0.5

func _draw() -> void:
	if texture == null:
		return
	var origin := (size - texture.get_size() * source_scale) * 0.5
	if segment_offset.is_zero_approx():
		draw_texture_rect(texture, Rect2(origin, texture.get_size() * source_scale), false)
		return
	for piece: Dictionary in _pieces:
		if piece.has("polygon"):
			var atlas: Texture2D = texture.atlas if texture is AtlasTexture else texture
			draw_set_transform(origin + Vector2(piece.direction) * segment_offset, 0.0, Vector2.ONE * source_scale)
			draw_polygon(piece.polygon, PackedColorArray([Color.WHITE]), piece.uvs, atlas)
			draw_set_transform(Vector2.ZERO)
			continue
		var source: Rect2 = piece.region
		var destination := Rect2(origin + source.position * source_scale + Vector2(piece.direction) * segment_offset, source.size * source_scale)
		draw_texture_rect_region(texture, destination, source)

func _build_pieces(aim_id: int) -> void:
	var logical_size := Atlas.logical_size(texture)
	var centre := logical_size * 0.5
	# AimIDs contain different shapes. Split in their empty spaces so brackets,
	# arcs and ticks move as complete groups rather than being cut into tiles.
	match aim_id:
		0:
			_add_horizontal_bands(logical_size, centre.y - 2.5, centre.y + 2.5, 2.5)
			return
		1:
			_add_vertical_sides(logical_size, centre.x - 4.0, centre.x + 4.0)
			return
		3:
			# Preserve the T/ladder's vertical spine, spread its horizontal arms.
			_add_piece(Rect2(0, 0, centre.x - 1.0, logical_size.y), Vector2.LEFT)
			_add_piece(Rect2(centre.x - 1.0, 0, 2.0, logical_size.y), Vector2.ZERO)
			_add_piece(Rect2(centre.x + 1.0, 0, logical_size.x - centre.x - 1.0, logical_size.y), Vector2.RIGHT)
			return
		4:
			# Keep the inner circle whole; the three surrounding lobes translate
			# radially, instead of breaking their curves at rectangular tile edges.
			_add_radial_piece(0.0, 7.0, 0.0, TAU, Vector2.ZERO)
			for lobe in 3:
				var start := deg_to_rad(-150.0 + float(lobe) * 120.0)
				var middle := start + deg_to_rad(60.0)
				_add_radial_piece(7.0, logical_size.y * 0.5, start, start + deg_to_rad(120.0), Vector2(cos(middle), sin(middle)))
			return
		5:
			# Six separate arcs, with the point remaining in the middle.
			_add_corner_bands(logical_size, 9.0, 9.0)
			return
		6:
			_add_piece(Rect2(0, 0, logical_size.x, centre.y), Vector2.UP)
			_add_piece(Rect2(0, centre.y, logical_size.x, centre.y), Vector2.DOWN)
			return
		7:
			# Preserve the complete inner sight ring and four ticks. The outer
			# upper-left and lower-right arcs move as two coherent groups.
			_add_radial_piece(0.0, 12.5, 0.0, TAU, Vector2.ZERO)
			_add_radial_piece(12.5, logical_size.y * 0.5, deg_to_rad(135.0), deg_to_rad(315.0), Vector2(-1, -1))
			_add_radial_piece(12.5, logical_size.y * 0.5, deg_to_rad(315.0), deg_to_rad(495.0), Vector2(1, 1))
			return
		8:
			# Move each whole row; keep all the central sight ticks together.
			_add_horizontal_bands(logical_size, centre.y - 10.0, centre.y + 10.0, centre.x)
			return
		9:
			# This sprite's cross is above its frame centre. Do not recenter it.
			_add_piece(Rect2(0, 0, logical_size.x, centre.y + 1.5), Vector2.ZERO)
			_add_piece(Rect2(0, centre.y + 1.5, logical_size.x, logical_size.y - centre.y - 1.5), Vector2.DOWN)
			return
		13:
			# Central plus and side brackets overlap in X but not in Y.
			# Include the plus's faint antialias fringe in the fixed region.
			_add_corner_bands(logical_size, 9.5, 7.5, true)
			return
	var half_centre := Vector2(6.0, 6.0)
	var x_bounds := [0.0, centre.x - half_centre.x, centre.x + half_centre.x, logical_size.x]
	var y_bounds := [0.0, centre.y - half_centre.y, centre.y + half_centre.y, logical_size.y]
	for row in 3:
		for column in 3:
			_add_piece(Rect2(Vector2(x_bounds[column], y_bounds[row]), Vector2(x_bounds[column + 1] - x_bounds[column], y_bounds[row + 1] - y_bounds[row])), Vector2(column - 1, row - 1))

func _add_radial_piece(inner: float, outer: float, start: float, end: float, direction: Vector2) -> void:
	var centre := texture.get_size() * 0.5
	var points := PackedVector2Array()
	# Use the same angular grid for adjoining masks, so their edges match.
	var steps := maxi(1, int(round((end - start) / TAU * 360.0)))
	var outer_points := steps if inner <= 0.0 and is_equal_approx(end - start, TAU) else steps + 1
	for step in outer_points:
		var angle := lerpf(start, end, float(step) / float(steps))
		points.append(centre + Vector2(cos(angle), sin(angle)) * outer * Atlas.SOURCE_PIXEL_SCALE)
	if inner > 0.0:
		for step in range(steps, -1, -1):
			var angle := lerpf(start, end, float(step) / float(steps))
			points.append(centre + Vector2(cos(angle), sin(angle)) * inner * Atlas.SOURCE_PIXEL_SCALE)
	var uvs := PackedVector2Array()
	var atlas_size: Vector2 = texture.atlas.get_size() if texture is AtlasTexture else texture.get_size()
	var atlas_origin: Vector2 = texture.region.position if texture is AtlasTexture else Vector2.ZERO
	for point: Vector2 in points:
		uvs.append((atlas_origin + point) / atlas_size)
	_pieces.append({"polygon": points, "uvs": uvs, "direction": direction})

func _add_horizontal_bands(frame: Vector2, top: float, bottom: float, half_middle: float) -> void:
	var left := frame.x * 0.5 - half_middle
	var right := frame.x * 0.5 + half_middle
	_add_piece(Rect2(0, 0, frame.x, top), Vector2.UP)
	_add_piece(Rect2(0, top, left, bottom - top), Vector2.LEFT)
	_add_piece(Rect2(left, top, right - left, bottom - top), Vector2.ZERO)
	_add_piece(Rect2(right, top, frame.x - right, bottom - top), Vector2.RIGHT)
	_add_piece(Rect2(0, bottom, frame.x, frame.y - bottom), Vector2.DOWN)

func _add_vertical_sides(frame: Vector2, left: float, right: float) -> void:
	_add_piece(Rect2(0, 0, left, frame.y), Vector2.LEFT)
	_add_piece(Rect2(left, 0, right - left, frame.y * 0.5), Vector2.UP)
	_add_piece(Rect2(left, frame.y * 0.5, right - left, frame.y * 0.5), Vector2.DOWN)
	_add_piece(Rect2(right, 0, frame.x - right, frame.y), Vector2.RIGHT)

func _add_corner_bands(frame: Vector2, half_width: float, half_height: float, sideways_only := false) -> void:
	var centre := frame * 0.5
	var top := centre.y - half_height
	var bottom := centre.y + half_height
	for side in 2:
		var x := float(side) * centre.x
		var direction := float(side * 2 - 1)
		_add_piece(Rect2(x, 0, centre.x, top), Vector2(direction, 0.0 if sideways_only else -1.0))
		_add_piece(Rect2(x, bottom, centre.x, frame.y - bottom), Vector2(direction, 0.0 if sideways_only else 1.0))
	_add_piece(Rect2(0, top, centre.x - half_width, bottom - top), Vector2.LEFT)
	_add_piece(Rect2(centre.x - half_width, top, half_width * 2.0, bottom - top), Vector2.ZERO)
	_add_piece(Rect2(centre.x + half_width, top, centre.x - half_width, bottom - top), Vector2.RIGHT)

func _add_piece(logical_region: Rect2, direction: Vector2) -> void:
	if logical_region.size.x <= 0.0 or logical_region.size.y <= 0.0:
		return
	_pieces.append({
		"region": Rect2(logical_region.position * Atlas.SOURCE_PIXEL_SCALE, logical_region.size * Atlas.SOURCE_PIXEL_SCALE),
		"direction": direction,
	})
