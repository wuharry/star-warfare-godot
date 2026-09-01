extends Node

# Renders THE EXPANSE from four viewpoints into one sheet: the spawn inside a
# recovered sector, the seam where that sector meets the procedural ground, the
# same country at night, and an aerial pass over the continent with the
# atmosphere lifted so the district layout is actually visible.
# Run it with a real display (no --headless), same as the other captures.

const OUTPUT_PATH := "res://tests/expanse_preview.png"

var world: WarfareExpanseWorld
var tile_size: Vector2i
var sheet: Image

func _ready() -> void:
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	GameState.settings.day_length = "frozen"
	GameState.settings.frozen_hour = 17.4

	var viewport_size := get_viewport().get_visible_rect().size
	tile_size = Vector2i(int(viewport_size.x) / 2, int(viewport_size.y) / 2)
	sheet = Image.create_empty(tile_size.x * 2, tile_size.y * 2, false, Image.FORMAT_RGBA8)

	world = (load("res://scenes/expanse.tscn") as PackedScene).instantiate() as WarfareExpanseWorld
	add_child(world)
	for _frame in range(24):
		await get_tree().process_frame

	await _capture_into(0)
	await _capture_seam(1)
	await _capture_night(2)
	await _capture_aerial(3)

	var error := sheet.save_png(OUTPUT_PATH)
	if error == OK:
		print("EXPANSE_CAPTURE_PASS %s" % OUTPUT_PATH)
		get_tree().quit(0)
	else:
		push_error("Could not save the expanse sheet: %s" % error_string(error))
		get_tree().quit(1)

func _capture_into(slot: int) -> void:
	for _frame in range(3):
		await get_tree().process_frame
	var shot := get_viewport().get_texture().get_image()
	shot.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_LANCZOS)
	if shot.get_format() != sheet.get_format():
		shot.convert(sheet.get_format())
	sheet.blit_rect(
		shot,
		Rect2i(Vector2i.ZERO, tile_size),
		Vector2i((slot % 2) * tile_size.x, (slot / 2) * tile_size.y)
	)

func _place_camera(position: Vector3, look_at: Vector3, fov := 62.0) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "CaptureCamera"
	camera.fov = fov
	camera.far = 4000.0
	world.add_child(camera)
	camera.global_position = position
	camera.look_at(look_at, Vector3.UP)
	camera.current = true
	return camera

func _capture_seam(slot: int) -> void:
	# Stands outside the first district looking in, so the sheet shows the
	# recovered Unity geometry meeting the generated ground it is planted in.
	var district: Dictionary = world.districts[0]
	var centre: Vector2 = district.centre
	var radius := float(district.radius)
	var eye := Vector3(centre.x + radius + 95.0, 0.0, centre.y + radius * 0.5)
	eye.y = world.terrain.height_at(eye.x, eye.z) + 26.0
	var target := Vector3(centre.x, float(district.base_y) + 6.0, centre.y)
	var camera := _place_camera(eye, target, 66.0)
	await _capture_into(slot)
	camera.queue_free()

func _capture_night(slot: int) -> void:
	GameState.settings.frozen_hour = 22.2
	world.day_night.apply(22.2)
	var origin := world.player.global_position
	var eye := Vector3(origin.x + 60.0, 0.0, origin.z + 60.0)
	eye.y = world.terrain.height_at(eye.x, eye.z) + 14.0
	var camera := _place_camera(eye, Vector3(origin.x, origin.y + 2.0, origin.z), 64.0)
	await _capture_into(slot)
	camera.queue_free()

func _capture_aerial(slot: int) -> void:
	# Destructive on purpose, so it runs last: streaming is frozen, the whole
	# continent is forced resident and the haze is switched off, none of which
	# is survivable for normal play.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	# Late afternoon rather than noon: the long shadows are what make the relief
	# of a landscape legible from the air.
	world.day_night.apply(16.4)
	world.day_night.environment.fog_enabled = false
	world.terrain.prime(Vector3.ZERO, 1500.0)
	for index in range(world.districts.size()):
		if not world.landmark_build_queue.has(index):
			world.landmark_build_queue.append(index)
	world._flush_landmark_queue(true)
	if is_instance_valid(world.hud):
		world.hud.visible = false
	var camera := _place_camera(Vector3(-180.0, 720.0, 1520.0), Vector3(0.0, 0.0, -180.0), 70.0)
	await _capture_into(slot)
	camera.queue_free()
