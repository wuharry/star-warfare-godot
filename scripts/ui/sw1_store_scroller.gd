extends Control
## UIScroller.cs: circular gear/tag lists, bounded vertical supplies, inertia + snap.

signal moved
signal settled(index: int)
signal tapped(position: Vector2)

var count := 0
var spacing := 120.0
var looping := true
var vertical := false
var max_velocity := 30.0
var offset := 0.0
var velocity := 0.0
var finger := -1
var moving := false
var enabled := true
var _last_position := Vector2.ZERO
var _press_position := Vector2.ZERO
var _travel := 0.0
var _selection := 0
var _interrupted_motion := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visibility_changed.connect(cancel)


func configure(item_count: int, index := 0) -> void:
	cancel()
	count = item_count
	select(index)


func select(index: int) -> void:
	cancel()
	_selection = posmod(index, count) if count > 0 else 0
	offset = _selection * spacing
	moved.emit()


func cancel() -> void:
	finger = -1
	velocity = 0.0
	moving = false
	_travel = 0.0
	offset = _selection * spacing
	moved.emit()


func distance(index: int) -> float:
	var value := index * spacing - offset
	if looping and count > 0:
		value = wrapf(value, -count * spacing * 0.5, count * spacing * 0.5)
	return value


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel()


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree() or count == 0:
		return
	var point := Vector2.ZERO
	var pointer := -1
	var press := false
	var release := false
	var drag := false
	var canceled := false
	if event is InputEventScreenTouch:
		point = event.position
		pointer = event.index
		press = event.pressed
		release = not event.pressed
		canceled = event.canceled
	elif event is InputEventScreenDrag:
		point = event.position
		pointer = event.index
		drag = true
	elif event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		point = event.position
		pointer = 10000
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			press = event.pressed
			release = not event.pressed
		elif event is InputEventMouseMotion:
			drag = true
	else:
		return
	point = get_global_transform_with_canvas().affine_inverse() * point
	if press and finger == -1 and Rect2(Vector2.ZERO, size).has_point(point):
		_interrupted_motion = moving
		finger = pointer
		_press_position = point
		_last_position = point
		_travel = 0.0
		velocity = 0.0
		moving = false
	elif pointer != finger:
		return
	elif canceled:
		cancel()
	elif drag:
		var change := (_last_position - point).y if vertical else (_last_position - point).x
		_travel += absf(change)
		_last_position = point
		if _travel > 4.0:
			offset += change
			velocity = clampf(change, -max_velocity, max_velocity)
			moving = true
			_bound()
			moved.emit()
	elif release:
		finger = -1
		if _travel <= 4.0 and not moving and not _interrupted_motion:
			tapped.emit(point)
		else:
			moving = true
	else:
		return
	get_viewport().set_input_as_handled()


func _bound() -> void:
	if looping:
		offset = fposmod(offset, maxf(spacing, count * spacing))
	else:
		offset = clampf(offset, 0.0, maxi(0, count - 1) * spacing)


func _process(delta: float) -> void:
	if not moving or finger != -1 or count == 0:
		return
	# Integrate in short steps so a stalled/mobile frame cannot jump over a snap.
	var remaining := minf(delta, 0.1)
	while remaining > 0.0 and moving:
		var step := minf(remaining, 0.016)
		remaining -= step
		if absf(velocity) > 5.0:
			velocity = move_toward(velocity, 0.0, 60.0 * step)
			offset += velocity * step * 100.0
			_bound()
		else:
			var target := roundf(offset / spacing) * spacing
			offset = move_toward(offset, target, 1000.0 * step)
			if absf(target - offset) <= 0.01:
				_selection = posmod(roundi(target / spacing), count)
				offset = _selection * spacing
				velocity = 0.0
				moving = false
				settled.emit(_selection)
		moved.emit()
