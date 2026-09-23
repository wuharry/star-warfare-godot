extends Node

class SwarmWorld extends WarfareGameWorld:
	# The test starts a late regular wave itself, without the two-second intro.
	func _begin_level() -> void:
		pass

var failures: Array[String] = []
var active_world: SwarmWorld

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _process(_delta: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
		if is_instance_valid(active_world) and is_instance_valid(active_world.hud) and is_instance_valid(active_world.hud.pause_overlay):
			active_world.hud.pause_overlay.hide()

func _input(event: InputEvent) -> void:
	# A desktop Escape key left over from another window must not freeze the
	# capture scene while its timed wave is running.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SWARM WAVE TEST: " + message)

func _run() -> void:
	var level_number := 8
	var wave_number := 5
	var output_path := ""
	var overview_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			level_number = int(argument.trim_prefix("--level="))
		elif argument.begins_with("--wave="):
			wave_number = int(argument.trim_prefix("--wave="))
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--overview="):
			overview_path = argument.trim_prefix("--overview=")
	GameState.save_path = "user://swarm_wave_test_profile.json"
	GameState.selected_level = level_number
	GameState.settings.quality = "low"
	GameState.settings.difficulty = "veteran"
	GameState.settings.show_touch_controls = false
	var world := SwarmWorld.new()
	active_world = world
	add_child(world)
	world.player.max_health = 1000000.0
	world.player.health = 1000000.0
	world.player.max_shield = 1000000.0
	world.player.shield = 1000000.0

	world.current_wave = wave_number - 1
	var expected_count := -1
	if level_number == 1 and wave_number == 3:
		expected_count = 20
	elif level_number == 8 and wave_number == 5:
		expected_count = 35
	elif level_number == 8 and wave_number == 6:
		expected_count = 14
	_check(expected_count > 0, "unsupported swarm test scenario")
	world._start_next_wave()
	var started := Time.get_ticks_msec()
	while world.total_spawned < WarfareGameWorld.SWARM_GROUP_SIZE and Time.get_ticks_msec() - started < 12000:
		await get_tree().process_frame
	var first_group: Array[Vector3] = []
	for child in world.get_children():
		if child is WarfareEnemy:
			first_group.append((child as WarfareEnemy).global_position)
	_check(first_group.size() >= WarfareGameWorld.SWARM_GROUP_SIZE, "first group never arrived")
	if first_group.size() >= WarfareGameWorld.SWARM_GROUP_SIZE:
		var unique_positions: Array[Vector3] = []
		for position in first_group:
			var seen := false
			for unique_position in unique_positions:
				if position.distance_to(unique_position) < 0.5:
					seen = true
					break
			if not seen:
				unique_positions.append(position)
		_check(unique_positions.size() >= 4, "first group stacked on one spawn point")

	while world.spawning and Time.get_ticks_msec() - started < 20000:
		await get_tree().process_frame
	_check(not world.spawning, "late wave never finished spawning")
	_check(world.total_spawned == expected_count, "wave did not spawn its full population")
	if wave_number == 6:
		var bosses := 0
		for child in world.get_children():
			if child is WarfareEnemy and (child as WarfareEnemy).enemy_kind == "boss":
				bosses += 1
		_check(bosses == 1, "final wave must contain exactly one boss")
	_check(world.alive_enemies <= WarfareGameWorld.MAX_ACTIVE_ENEMIES, "active enemy limit was exceeded")
	_check(not world.completed, "wave ended before enemies were defeated")
	var spawn_ms := Time.get_ticks_msec() - started

	if DisplayServer.get_name() == "headless" and (not output_path.is_empty() or not overview_path.is_empty()):
		_check(false, "screenshots require a graphical renderer")
		output_path = ""
		overview_path = ""
	if not output_path.is_empty():
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		_check(image != null and image.get_width() > 0, "renderer produced an empty image")
		if image != null and image.get_width() > 0:
			_check(image.save_png(output_path) == OK, "could not save the swarm capture")
		print("SWARM_CAPTURE %s viewport=%s renderer=%s" % [output_path, get_viewport().get_visible_rect().size, RenderingServer.get_current_rendering_method()])
	if not overview_path.is_empty():
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.global_position = world.player.global_position + Vector3(0.0, 28.0, 32.0)
		camera.look_at(world.player.global_position, Vector3.UP)
		camera.fov = 65.0
		camera.current = true
		await RenderingServer.frame_post_draw
		var overview := get_viewport().get_texture().get_image()
		_check(overview != null and overview.get_width() > 0, "renderer produced an empty overview")
		if overview != null and overview.get_width() > 0:
			_check(overview.save_png(overview_path) == OK, "could not save the swarm overview")
		print("SWARM_OVERVIEW %s" % overview_path)

	var spawned_count := world.total_spawned
	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	if failures.is_empty():
		print("SWARM_WAVE_TEST_PASS spawned=%d spawn_ms=%d" % [spawned_count, spawn_ms])
		get_tree().quit(0)
	else:
		print("SWARM_WAVE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
