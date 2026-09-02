extends Node

# Guards the fixed per-sector lighting.
#
# None of the 17 original Unity scenes ships a directional light or a skybox:
# every one sets m_Sun to nothing and m_AmbientMode to flat, lighting the level
# from m_AmbientSkyColor alone. That ambient is the one piece of real per-map
# lighting data the exporter recovered, and it genuinely differs between maps,
# so this asserts the game actually puts it on screen instead of substituting a
# look of its own. It also pins the lighting down as *fixed*: no clock, no
# drift, the same sector built twice is lit identically.

const SAMPLE_LEVELS := [1, 2, 3, 5, 13, 20, 21]

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SECTOR LIGHTING TEST: " + message)

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	_test_no_clock_remains()
	await _test_recovered_ambient()
	await _test_lighting_is_fixed()

	if failures.is_empty():
		print("SECTOR_LIGHTING_TEST_PASS levels=%d" % SAMPLE_LEVELS.size())
		get_tree().quit(0)
	else:
		print("SECTOR_LIGHTING_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _test_no_clock_remains() -> void:
	# The day/night cycle was removed in favour of the original fixed lighting.
	# These are the seams it used to hang off; if any of them come back without
	# the rest, the sectors would drift again.
	_check(not GameState.has_method("get_world_hour"), "GameState still exposes a world clock")
	_check(not GameState.has_method("advance_world_time"), "GameState can still advance a world clock")
	_check(not GameState.settings.has("day_length"), "a day-length setting is still shipped")
	_check(not GameState.settings.has("frozen_hour"), "a frozen-hour setting is still shipped")
	_check(not ResourceLoader.exists("res://scripts/game/day_night_cycle.gd"), "the day/night cycle script is still in the build")

func _level_metadata(level_number: int) -> Dictionary:
	var path := "res://assets/models/levels/level_%02d/level.json" % level_number
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _build_sector(level_number: int) -> WarfareGameWorld:
	GameState.selected_level = level_number
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	return world

func _environment_of(world: WarfareGameWorld) -> Environment:
	for child in world.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
	return null

func _test_recovered_ambient() -> void:
	var seen: Array[Color] = []
	for level_number: int in SAMPLE_LEVELS:
		var metadata := _level_metadata(level_number)
		var render_settings: Dictionary = metadata.get("render_settings", {})
		_check(not render_settings.is_empty(), "level %d has no recovered render settings" % level_number)
		if render_settings.is_empty():
			continue

		var world := _build_sector(level_number)
		await get_tree().process_frame
		var environment := _environment_of(world)
		_check(environment != null, "sector %d built no environment" % level_number)
		if environment == null:
			world.queue_free()
			continue

		var expected_values: Array = render_settings.get("ambient_color", [])
		var expected := Color(float(expected_values[0]), float(expected_values[1]), float(expected_values[2]))
		var actual := environment.ambient_light_color
		_check(
			is_equal_approx(actual.r, expected.r) and is_equal_approx(actual.g, expected.g) and is_equal_approx(actual.b, expected.b),
			"sector %d ambient is %s, recovered value is %s" % [level_number, actual, expected]
		)
		var expected_energy := maxf(0.15, float(render_settings.get("ambient_intensity", 1.0)))
		_check(
			is_equal_approx(environment.ambient_light_energy, expected_energy),
			"sector %d ambient energy is %f, expected %f" % [level_number, environment.ambient_light_energy, expected_energy]
		)
		# The originals had no skybox, so a flat background is the faithful
		# reproduction rather than a shortcut.
		_check(environment.background_mode == Environment.BG_COLOR, "sector %d invented a sky the original did not have" % level_number)
		seen.append(actual)
		world.queue_free()
		await get_tree().process_frame

	# The whole point of reading the recovered value is that maps differ: the
	# opening outposts sit at 0.2 grey, sectors 02-04 at full white, the late
	# multiplayer maps at near-black violet. If these ever collapse to one
	# value, the recovered data has stopped being used.
	_check(seen.size() >= 3, "not enough sectors were sampled to compare")
	if seen.size() >= 3:
		var brightest := 0.0
		var darkest := 1.0
		for colour in seen:
			var level := (colour.r + colour.g + colour.b) / 3.0
			brightest = maxf(brightest, level)
			darkest = minf(darkest, level)
		_check(brightest - darkest > 0.3, "every sector is lit the same; the recovered ambient is being ignored")

func _test_lighting_is_fixed() -> void:
	var restore_quality := str(GameState.settings.quality)
	GameState.settings.quality = "high"

	var first := _build_sector(1)
	await get_tree().process_frame
	var first_light := first.get_node_or_null("KeyLight") as DirectionalLight3D
	_check(first_light != null, "a sector built no key light")
	if first_light == null:
		first.queue_free()
		GameState.settings.quality = restore_quality
		return
	var rotation := first_light.rotation_degrees
	var colour := first_light.light_color
	var energy := first_light.light_energy
	_check(first_light.shadow_enabled, "the key light casts no shadows at high quality")

	# Held for a while: nothing may move it.
	for _frame in range(20):
		await get_tree().process_frame
	_check(first_light.rotation_degrees.is_equal_approx(rotation), "the key light drifted while the sector was running")
	_check(first_light.light_color == colour, "the key light colour changed while the sector was running")
	_check(is_equal_approx(first_light.light_energy, energy), "the key light energy changed while the sector was running")
	first.queue_free()
	await get_tree().process_frame

	# ... and rebuilding the same sector reproduces it exactly.
	var second := _build_sector(1)
	await get_tree().process_frame
	var second_light := second.get_node_or_null("KeyLight") as DirectionalLight3D
	_check(second_light != null, "the rebuilt sector has no key light")
	if second_light != null:
		_check(second_light.rotation_degrees.is_equal_approx(rotation), "the same sector was lit from a different angle on a rebuild")
		_check(second_light.light_color == colour, "the same sector was lit in a different colour on a rebuild")
	second.queue_free()
	await get_tree().process_frame

	# Quality still governs shadows.
	GameState.settings.quality = "low"
	var low := _build_sector(1)
	await get_tree().process_frame
	var low_light := low.get_node_or_null("KeyLight") as DirectionalLight3D
	_check(low_light != null and not low_light.shadow_enabled, "low quality still casts sector shadows")
	low.queue_free()
	await get_tree().process_frame
	GameState.settings.quality = restore_quality
