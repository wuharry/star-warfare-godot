extends Node

# Guards the day/night cycle: the campaign clock (rate, wrap, freeze,
# persistence), the sun/moon geometry that decides where shadows fall, and the
# timecycle table that decides what colour they are. All of it is pure data
# apart from the last block, which builds a real sector and asserts the
# environment actually moves when the hour does.

const RequiredKeys := [
	"h", "sun", "sun_e", "moon_e", "amb", "amb_e",
	"top", "hor", "gnd", "fog", "fog_s", "glow", "fill", "sky_e",
]

var failures: Array[String] = []
var restore_settings: Dictionary = {}
var restore_time := 0.0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("DAY NIGHT TEST: " + message)

func _run() -> void:
	restore_time = GameState.world_time
	restore_settings = {
		"day_length": GameState.settings.day_length,
		"frozen_hour": GameState.settings.frozen_hour,
		"quality": GameState.settings.quality,
	}

	_test_clock_rate()
	_test_frozen_clock()
	_test_persistence()
	_test_sun_geometry()
	_test_timecycle_table()
	await _test_sector_lighting()

	GameState.settings.day_length = restore_settings.day_length
	GameState.settings.frozen_hour = restore_settings.frozen_hour
	GameState.settings.quality = restore_settings.quality
	GameState.world_time = restore_time
	GameState.flush_world_time()

	if failures.is_empty():
		print("DAY_NIGHT_TEST_PASS")
		get_tree().quit(0)
	else:
		print("DAY_NIGHT_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _test_clock_rate() -> void:
	_check(GameState.DAY_LENGTH_ORDER == ["brisk", "standard", "slow", "frozen"], "day length order changed unexpectedly")
	for key: String in GameState.DAY_LENGTH_ORDER:
		_check(GameState.DAY_LENGTH_PROFILES.has(key), "missing day length profile: " + key)

	# The whole feature is "a full day takes 30-45 real minutes", so the three
	# live presets have to sit inside that window and stay ordered.
	var brisk := float(GameState.DAY_LENGTH_PROFILES["brisk"])
	var standard := float(GameState.DAY_LENGTH_PROFILES["standard"])
	var slow := float(GameState.DAY_LENGTH_PROFILES["slow"])
	_check(brisk >= 30.0 and slow <= 45.0, "day length presets left the 30-45 real minute window")
	_check(brisk < standard and standard < slow, "day length presets are not ordered")

	GameState.settings.day_length = "standard"
	_check(is_equal_approx(GameState.get_day_length_minutes(), 36.0), "standard cycle is not 36 real minutes")

	# 36 real minutes per day puts one in-game hour at exactly 90 real seconds.
	GameState.world_time = 0.0
	GameState.advance_world_time(90.0)
	_check(is_equal_approx(GameState.world_time, 1.0), "90 real seconds did not advance exactly one in-game hour, got %f" % GameState.world_time)

	GameState.world_time = 23.5
	GameState.advance_world_time(90.0)
	_check(is_equal_approx(GameState.world_time, 0.5), "the clock did not wrap past midnight, got %f" % GameState.world_time)

	GameState.settings.day_length = "brisk"
	GameState.world_time = 0.0
	GameState.advance_world_time(75.0)
	_check(is_equal_approx(GameState.world_time, 1.0), "the brisk preset does not put an in-game hour at 75 real seconds")

	# An unknown stored value must fall back to a running cycle, never freeze.
	GameState.settings.day_length = "eternal_afternoon"
	_check(is_equal_approx(GameState.get_day_length_minutes(), 36.0), "unknown day length did not fall back to standard")
	_check(not GameState.is_day_cycle_frozen(), "unknown day length froze the clock")

func _test_frozen_clock() -> void:
	GameState.settings.day_length = "frozen"
	GameState.settings.frozen_hour = 17.6
	GameState.world_time = 3.0
	_check(GameState.is_day_cycle_frozen(), "frozen preset did not freeze the clock")
	_check(is_equal_approx(GameState.get_world_hour(), 17.6), "frozen clock did not report the pinned hour")
	GameState.advance_world_time(600.0)
	_check(is_equal_approx(GameState.world_time, 3.0), "a frozen clock still advanced world time")

	for preset in GameState.FROZEN_HOUR_PRESETS:
		var hour := float(preset)
		_check(hour >= 0.0 and hour < 24.0, "frozen hour preset %f is out of range" % hour)

func _test_persistence() -> void:
	GameState.settings.day_length = "standard"
	GameState.world_time = 3.25
	GameState.flush_world_time()
	GameState.world_time = 11.0
	GameState._load_save()
	_check(is_equal_approx(GameState.world_time, 3.25), "world time did not survive a save/load round trip, got %f" % GameState.world_time)

func _test_sun_geometry() -> void:
	var sunrise := WarfareDayNightCycle.sun_elevation_degrees(WarfareDayNightCycle.SUNRISE_HOUR)
	var sunset := WarfareDayNightCycle.sun_elevation_degrees(WarfareDayNightCycle.SUNSET_HOUR)
	_check(absf(sunrise) < 0.001, "the sun is not on the horizon at the sunrise keyframe")
	_check(absf(sunset) < 0.001, "the sun is not on the horizon at the sunset keyframe")
	_check(WarfareDayNightCycle.sun_elevation_degrees(12.5) > 60.0, "midday sun is too low")
	_check(WarfareDayNightCycle.sun_elevation_degrees(0.0) < -40.0, "the sun did not sink at midnight")
	_check(WarfareDayNightCycle.sun_elevation_degrees(21.0) < 0.0, "the sun is still up at 21:00")
	_check(WarfareDayNightCycle.sun_elevation_degrees(4.0) < 0.0, "the sun is already up at 04:00")

	# East at sunrise, west at sunset, and the arc has to stay continuous
	# through the wrap or the shadows would snap around at 19:00.
	_check(is_equal_approx(WarfareDayNightCycle.sun_azimuth_degrees(6.0), 90.0), "the sun does not rise in the east")
	_check(is_equal_approx(WarfareDayNightCycle.sun_azimuth_degrees(18.99), -88.0) or WarfareDayNightCycle.sun_azimuth_degrees(18.99) < -85.0, "the sun does not set in the west")
	var before := WarfareDayNightCycle.sun_azimuth_degrees(18.999)
	var after := WarfareDayNightCycle.sun_azimuth_degrees(19.001)
	_check(absf(after - before) < 1.0, "the sun azimuth jumps at sunset (%f -> %f)" % [before, after])
	var midnight_before := WarfareDayNightCycle.sun_elevation_degrees(23.999)
	var midnight_after := WarfareDayNightCycle.sun_elevation_degrees(0.001)
	_check(absf(midnight_after - midnight_before) < 1.0, "the sun elevation jumps at midnight")

func _test_timecycle_table() -> void:
	var previous_hour := -1.0
	for frame: Dictionary in WarfareDayNightCycle.KEYFRAMES:
		for key: String in RequiredKeys:
			if key == "h":
				continue
			_check(frame.has(key), "keyframe %s is missing %s" % [str(frame.get("h", "?")), key])
		var hour := float(frame.h)
		_check(hour > previous_hour, "keyframes are not sorted by hour at %f" % hour)
		previous_hour = hour
	_check(is_equal_approx(float(WarfareDayNightCycle.KEYFRAMES[0].h), 0.0), "the table must open on midnight so the wrap has a target")

	var noon := WarfareDayNightCycle.sample(12.5)
	var midnight := WarfareDayNightCycle.sample(0.0)
	var sunset := WarfareDayNightCycle.sample(19.0)
	for key: String in RequiredKeys:
		_check(noon.has(key), "a sampled look is missing %s" % key)
	# Brightness is the sum of everything lighting the sector, not the ambient
	# term alone: the night deliberately keeps a lifted ambient so a moonlit
	# sector stays readable, which the ambient values alone would flag as a
	# regression.
	var noon_total := float(noon.sun_e) + float(noon.moon_e) + float(noon.amb_e)
	var midnight_total := float(midnight.sun_e) + float(midnight.moon_e) + float(midnight.amb_e)
	_check(noon_total > midnight_total * 2.5, "noon is not meaningfully brighter than midnight (%f vs %f)" % [noon_total, midnight_total])
	_check(float(noon.amb_e) > float(midnight.amb_e), "noon ambient does not sit above midnight ambient")
	_check(midnight_total > 0.6, "the night is too dark to fight in (%f)" % midnight_total)
	_check(float(noon.sun_e) > 1.5 and float(midnight.sun_e) <= 0.001, "the sun is not off at midnight")
	_check(float(midnight.moon_e) > 0.1 and float(noon.moon_e) <= 0.001, "the moon is not carrying the night")

	# Sunset has to be the warm end of the table and midnight the cold end,
	# which is the whole reason for hand-authoring keyframes.
	var sunset_sun: Color = sunset.sun
	var noon_sun: Color = noon.sun
	_check(sunset_sun.r - sunset_sun.b > noon_sun.r - noon_sun.b + 0.3, "sunset light is not warmer than noon light")
	var midnight_ambient: Color = midnight.amb
	_check(midnight_ambient.b > midnight_ambient.r, "midnight ambient is not a cool colour")

	# The blend has to close the loop, or the sky would pop at 00:00.
	var wrap_before: Color = WarfareDayNightCycle.sample(23.999).hor
	var wrap_after: Color = WarfareDayNightCycle.sample(0.001).hor
	var wrap_delta := absf(wrap_before.r - wrap_after.r) + absf(wrap_before.g - wrap_after.g) + absf(wrap_before.b - wrap_after.b)
	_check(wrap_delta < 0.01, "the horizon colour pops across midnight (delta %f)" % wrap_delta)

	_check(WarfareDayNightCycle.format_clock(17.6) == "17:36", "clock formatting is wrong: %s" % WarfareDayNightCycle.format_clock(17.6))
	_check(WarfareDayNightCycle.format_clock(24.0) == "00:00", "clock formatting does not wrap")
	_check(WarfareDayNightCycle.phase_key(12.5) == "NOON", "12:30 is not reported as noon")
	_check(WarfareDayNightCycle.phase_key(18.0) == "GOLDEN HOUR", "18:00 is not reported as golden hour")
	_check(WarfareDayNightCycle.phase_key(2.0) == "NIGHT", "02:00 is not reported as night")

func _test_sector_lighting() -> void:
	GameState.settings.quality = "high"
	GameState.settings.day_length = "standard"
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame

	var cycle: WarfareDayNightCycle = world.day_night
	_check(cycle != null, "the sector did not build a day/night cycle")
	if cycle == null:
		world.queue_free()
		return
	var environment: Environment = cycle.environment
	_check(environment != null, "the cycle has no environment to drive")
	_check(cycle.sky_material != null, "high quality did not build a sky")

	cycle.apply(12.5)
	var noon_sun := cycle.sun.light_energy
	var noon_ambient := environment.ambient_light_energy
	var noon_sky: Color = cycle.sky_material.sky_horizon_color
	_check(noon_sun > 1.5, "the midday sun is not lighting the sector")
	_check(cycle.sun.visible, "the midday sun is switched off")
	_check(cycle.moon.light_energy <= 0.001, "the moon is lit at midday")
	_check(cycle.sun.rotation_degrees.x < -60.0, "the midday sun is not overhead")

	cycle.apply(0.0)
	_check(cycle.sun.light_energy <= 0.001, "the sun still lights the sector at midnight")
	_check(not cycle.sun.visible, "the sun is still visible at midnight")
	_check(cycle.moon.light_energy > 0.1, "the moon does not light the sector at midnight")
	_check(environment.ambient_light_energy < noon_ambient, "midnight ambient is not darker than noon")
	_check(cycle.sky_material.sky_horizon_color != noon_sky, "the sky did not change between noon and midnight")

	# Right at the sunset keyframe the light has to still be on and grazing.
	cycle.apply(19.0)
	_check(cycle.sun.light_energy > 0.4, "the sunset light was faded out too early")
	_check(absf(cycle.sun.rotation_degrees.x) < 1.0, "the sunset sun is not grazing the horizon")
	_check(cycle.sun.light_color.r > cycle.sun.light_color.b + 0.3, "the sunset light is not warm")

	# An hour past sunset the sun is under the map: it must not light it.
	cycle.apply(20.0)
	_check(cycle.sun.light_energy <= 0.02, "the sun lights the sector from below after dusk")
	_check(not (cycle.sun.shadow_enabled and cycle.moon.shadow_enabled), "two directional lights cast shadows at once")

	# Low quality has to strip the sky and the shadows without losing the hour.
	GameState.settings.quality = "low"
	var low_world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(low_world)
	await get_tree().process_frame
	var low_cycle: WarfareDayNightCycle = low_world.day_night
	_check(low_cycle != null and low_cycle.sky_material == null, "low quality still builds a sky")
	if low_cycle != null:
		low_cycle.apply(12.5)
		_check(not low_cycle.sun.shadow_enabled, "low quality still casts sun shadows")
		_check(low_cycle.sun.light_energy > 1.5, "low quality lost the midday sun")
		_check(low_cycle.environment.background_mode == Environment.BG_COLOR, "low quality did not fall back to a flat background")
	low_world.queue_free()
	world.queue_free()
	await get_tree().process_frame
