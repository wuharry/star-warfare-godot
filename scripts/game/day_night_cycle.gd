class_name WarfareDayNightCycle
extends Node3D

# GTA-style timecycle for the restored sectors.
#
# The sun and moon are placed geometrically from the hour (elevation/azimuth),
# and the hand-authored keyframe table below supplies nothing but colour and
# intensity. Splitting it that way is what makes the light land where you
# expect it: shadows stretch out on their own at 06:00 and 18:30 because the
# light really is grazing the horizon, and the table only has to decide how
# orange it is. One linear ramp from "day" to "night" cannot do that.
#
# Every sector keeps its identity because the recovered Unity palette and
# ambient tint are blended over the sampled look instead of replacing it.

# The solar arc runs 06:00 -> 19:00 so both ends land exactly on the SUNRISE
# and SUNSET keyframes: the light grazes the horizon in the same frame the sky
# turns orange.
const SUNRISE_HOUR := 6.0
const SUNSET_HOUR := 19.0
const MAX_SUN_ELEVATION := 66.0
const MAX_MOON_ELEVATION := 54.0

# A directional light below the horizon still lights the level, from
# underneath, which reads as a lighting bug. Fade it out over the few degrees
# it takes to sink past the sunset keyframe instead of cutting it dead.
const HORIZON_FADE_START := -6.0
const HORIZON_FADE_END := 0.5

# Even the fastest cycle moves under one in-game minute per real second, so
# refreshing the environment five times a second is already finer than anyone
# can see, and it keeps the sky radiance map off the per-frame budget.
const REFRESH_INTERVAL := 0.2

const BASE_FILL_ENERGY := 8.0

# Fog here is aerial perspective: enough to push the far ridges back and to
# catch the sunrise colour, never enough to hide the sector. Every recovered
# Unity scene shipped with fog disabled, so the density they carry is a dead
# value and this default stands in for it.
const DEFAULT_FOG_DENSITY := 0.0035

# hour, sun colour/energy, moon energy, ambient colour/energy, sky zenith,
# sky horizon, sky ground, fog colour, fog density scale, glow, fill scale.
const KEYFRAMES: Array[Dictionary] = [
	{
		"h": 0.0,
		"sun": Color(0.30, 0.44, 0.74), "sun_e": 0.0, "moon_e": 0.58,
		"amb": Color(0.22, 0.30, 0.50), "amb_e": 0.30,
		"top": Color(0.015, 0.025, 0.060), "hor": Color(0.050, 0.075, 0.140),
		"gnd": Color(0.020, 0.030, 0.050),
		"fog": Color(0.050, 0.080, 0.150), "fog_s": 0.95,
		"glow": 1.15, "fill": 0.50, "sky_e": 0.35,
	},
	{
		"h": 4.5,
		"sun": Color(0.52, 0.54, 0.80), "sun_e": 0.0, "moon_e": 0.44,
		"amb": Color(0.28, 0.33, 0.52), "amb_e": 0.34,
		"top": Color(0.040, 0.070, 0.170), "hor": Color(0.200, 0.195, 0.315),
		"gnd": Color(0.045, 0.055, 0.090),
		"fog": Color(0.180, 0.200, 0.320), "fog_s": 1.25,
		"glow": 1.05, "fill": 0.52, "sky_e": 0.55,
	},
	{
		"h": 6.0,
		"sun": Color(1.00, 0.56, 0.30), "sun_e": 1.15, "moon_e": 0.05,
		"amb": Color(0.44, 0.40, 0.46), "amb_e": 0.54,
		"top": Color(0.100, 0.200, 0.420), "hor": Color(0.950, 0.520, 0.320),
		"gnd": Color(0.130, 0.110, 0.120),
		"fog": Color(0.780, 0.480, 0.380), "fog_s": 1.15,
		"glow": 1.10, "fill": 0.62, "sky_e": 1.00,
	},
	{
		"h": 7.5,
		"sun": Color(1.00, 0.80, 0.58), "sun_e": 1.40, "moon_e": 0.0,
		"amb": Color(0.48, 0.52, 0.62), "amb_e": 0.50,
		"top": Color(0.160, 0.340, 0.620), "hor": Color(0.780, 0.720, 0.660),
		"gnd": Color(0.200, 0.190, 0.180),
		"fog": Color(0.660, 0.660, 0.680), "fog_s": 1.05,
		"glow": 0.90, "fill": 0.70, "sky_e": 1.00,
	},
	{
		"h": 10.0,
		"sun": Color(1.00, 0.95, 0.86), "sun_e": 1.72, "moon_e": 0.0,
		"amb": Color(0.55, 0.62, 0.72), "amb_e": 0.60,
		"top": Color(0.180, 0.400, 0.740), "hor": Color(0.620, 0.760, 0.900),
		"gnd": Color(0.240, 0.240, 0.240),
		"fog": Color(0.660, 0.760, 0.880), "fog_s": 0.80,
		"glow": 0.75, "fill": 0.85, "sky_e": 1.05,
	},
	{
		"h": 12.5,
		"sun": Color(1.00, 0.98, 0.94), "sun_e": 1.95, "moon_e": 0.0,
		"amb": Color(0.60, 0.68, 0.78), "amb_e": 0.66,
		"top": Color(0.160, 0.400, 0.800), "hor": Color(0.680, 0.820, 0.940),
		"gnd": Color(0.260, 0.260, 0.260),
		"fog": Color(0.720, 0.820, 0.920), "fog_s": 0.62,
		"glow": 0.70, "fill": 0.90, "sky_e": 1.10,
	},
	{
		"h": 15.0,
		"sun": Color(1.00, 0.93, 0.80), "sun_e": 1.75, "moon_e": 0.0,
		"amb": Color(0.58, 0.62, 0.70), "amb_e": 0.60,
		"top": Color(0.170, 0.380, 0.740), "hor": Color(0.700, 0.780, 0.860),
		"gnd": Color(0.250, 0.240, 0.220),
		"fog": Color(0.740, 0.780, 0.860), "fog_s": 0.75,
		"glow": 0.75, "fill": 0.84, "sky_e": 1.05,
	},
	{
		"h": 17.5,
		"sun": Color(1.00, 0.74, 0.44), "sun_e": 1.48, "moon_e": 0.0,
		"amb": Color(0.56, 0.50, 0.49), "amb_e": 0.56,
		"top": Color(0.200, 0.340, 0.600), "hor": Color(0.940, 0.680, 0.420),
		"gnd": Color(0.220, 0.180, 0.150),
		"fog": Color(0.860, 0.620, 0.420), "fog_s": 1.00,
		"glow": 1.00, "fill": 0.74, "sky_e": 1.00,
	},
	{
		"h": 19.0,
		"sun": Color(1.00, 0.42, 0.20), "sun_e": 1.10, "moon_e": 0.02,
		"amb": Color(0.44, 0.37, 0.43), "amb_e": 0.52,
		"top": Color(0.130, 0.180, 0.420), "hor": Color(0.960, 0.360, 0.220),
		"gnd": Color(0.130, 0.100, 0.110),
		"fog": Color(0.720, 0.340, 0.280), "fog_s": 1.10,
		"glow": 1.25, "fill": 0.68, "sky_e": 0.95,
	},
	{
		"h": 20.0,
		"sun": Color(0.62, 0.34, 0.42), "sun_e": 0.20, "moon_e": 0.32,
		"amb": Color(0.30, 0.31, 0.50), "amb_e": 0.34,
		"top": Color(0.050, 0.080, 0.220), "hor": Color(0.360, 0.240, 0.360),
		"gnd": Color(0.060, 0.060, 0.100),
		"fog": Color(0.320, 0.260, 0.380), "fog_s": 1.20,
		"glow": 1.30, "fill": 0.52, "sky_e": 0.60,
	},
	{
		"h": 21.5,
		"sun": Color(0.40, 0.42, 0.70), "sun_e": 0.0, "moon_e": 0.55,
		"amb": Color(0.21, 0.29, 0.48), "amb_e": 0.29,
		"top": Color(0.020, 0.035, 0.080), "hor": Color(0.080, 0.110, 0.200),
		"gnd": Color(0.025, 0.035, 0.060),
		"fog": Color(0.070, 0.100, 0.180), "fog_s": 1.00,
		"glow": 1.20, "fill": 0.49, "sky_e": 0.40,
	},
]

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var fill: OmniLight3D
var sky_material: ProceduralSkyMaterial

var environment: Environment
var palette_shadow := Color(0.09, 0.12, 0.20)
var palette_mid := Color(0.40, 0.50, 0.60)
var palette_accent := Color(0.70, 0.85, 1.00)
var ambient_tint := Color.WHITE
var ambient_scale := 1.0
var base_fog_density := 0.008
var fog_authored := true
var shadows_allowed := true
var fog_allowed := true
var glow_allowed := true
var sky_allowed := true

var _refresh_timer := 0.0
var _state: Dictionary = {}

static func sample(hour: float) -> Dictionary:
	var target := fposmod(hour, 24.0)
	var count := KEYFRAMES.size()
	var next_index := 0
	while next_index < count and float(KEYFRAMES[next_index].h) <= target:
		next_index += 1
	var previous_index := (next_index - 1 + count) % count
	next_index = next_index % count
	var previous: Dictionary = KEYFRAMES[previous_index]
	var upcoming: Dictionary = KEYFRAMES[next_index]
	var span := float(upcoming.h) - float(previous.h)
	if span <= 0.0:
		span += 24.0
	var offset := target - float(previous.h)
	if offset < 0.0:
		offset += 24.0
	# Ease the blend so the light settles on each authored look for a moment
	# instead of sliding through it at a constant rate.
	var weight := smoothstep(0.0, 1.0, clampf(offset / span, 0.0, 1.0))
	var blended := {}
	for key in previous:
		var from_value: Variant = previous[key]
		var to_value: Variant = upcoming[key]
		if from_value is Color:
			blended[key] = (from_value as Color).lerp(to_value, weight)
		else:
			blended[key] = lerpf(float(from_value), float(to_value), weight)
	blended["h"] = target
	return blended

static func sun_elevation_degrees(hour: float) -> float:
	var target := fposmod(hour, 24.0)
	var day_length := SUNSET_HOUR - SUNRISE_HOUR
	if target >= SUNRISE_HOUR and target <= SUNSET_HOUR:
		return MAX_SUN_ELEVATION * sin(PI * (target - SUNRISE_HOUR) / day_length)
	var night_offset := target - SUNSET_HOUR
	if night_offset < 0.0:
		night_offset += 24.0
	return -MAX_MOON_ELEVATION * sin(PI * night_offset / (24.0 - day_length))

static func sun_azimuth_degrees(hour: float) -> float:
	# +90 at sunrise (light travelling west), -90 at sunset, then carrying on
	# the same way through the night so the arc never snaps back.
	var target := fposmod(hour, 24.0)
	var day_length := SUNSET_HOUR - SUNRISE_HOUR
	if target >= SUNRISE_HOUR and target <= SUNSET_HOUR:
		return 90.0 - 180.0 * (target - SUNRISE_HOUR) / day_length
	var night_offset := target - SUNSET_HOUR
	if night_offset < 0.0:
		night_offset += 24.0
	return -90.0 - 180.0 * night_offset / (24.0 - day_length)

static func phase_key(hour: float) -> String:
	var target := fposmod(hour, 24.0)
	if target < 4.5:
		return "NIGHT"
	if target < 5.9:
		return "DAWN"
	if target < 7.3:
		return "SUNRISE"
	if target < 11.2:
		return "MORNING"
	if target < 13.4:
		return "NOON"
	if target < 16.4:
		return "AFTERNOON"
	if target < 18.4:
		return "GOLDEN HOUR"
	if target < 19.7:
		return "SUNSET"
	if target < 20.9:
		return "DUSK"
	return "NIGHT"

static func format_clock(hour: float) -> String:
	var minutes := int(round(fposmod(hour, 24.0) * 60.0)) % 1440
	return "%02d:%02d" % [minutes / 60, minutes % 60]

func configure(target_environment: Environment, palette: Array, restored_settings: Dictionary, quality: Dictionary, fill_radius: float) -> void:
	environment = target_environment
	if palette.size() >= 3:
		palette_shadow = Color(palette[0])
		palette_mid = Color(palette[1])
		palette_accent = Color(palette[2])
	shadows_allowed = bool(quality.get("shadows", true))
	fog_allowed = bool(quality.get("fog", true))
	glow_allowed = bool(quality.get("glow", true))
	sky_allowed = bool(quality.get("sky", true))

	# The recovered Unity render settings survive as a per-sector tint and a
	# density base. They can no longer be absolute values: the hour of the day
	# decides how bright a sector is, or every map would read as flat noon.
	ambient_tint = _normalized_tint(_color_from_json(restored_settings.get("ambient_color", [1.0, 1.0, 1.0, 1.0])))
	ambient_scale = clampf(float(restored_settings.get("ambient_intensity", 1.0)), 0.45, 1.6)
	fog_authored = bool(restored_settings.get("fog_enabled", false))
	base_fog_density = DEFAULT_FOG_DENSITY
	if fog_authored:
		base_fog_density = clampf(float(restored_settings.get("fog_density", DEFAULT_FOG_DENSITY)), 0.0015, 0.0055)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.directional_shadow_max_distance = 85.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.06
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.directional_shadow_max_distance = 60.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.shadow_bias = 0.08
	add_child(moon)

	# Kept from the original build: a soft bounce over the arena so the side of
	# a crate facing away from the sun never goes fully black.
	fill = OmniLight3D.new()
	fill.name = "SkyBounce"
	fill.position = Vector3(0.0, 7.0, 0.0)
	fill.omni_range = fill_radius
	add_child(fill)

	if environment != null and sky_allowed:
		sky_material = ProceduralSkyMaterial.new()
		sky_material.sky_curve = 0.18
		sky_material.ground_curve = 0.04
		sky_material.sun_curve = 0.09
		sky_material.use_debanding = true
		var sky := Sky.new()
		sky.sky_material = sky_material
		# Compatibility also runs on phones here, so the radiance map stays
		# small and is rebuilt across frames rather than all at once.
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		environment.sky = sky
		environment.background_mode = Environment.BG_SKY
	elif environment != null:
		environment.background_mode = Environment.BG_COLOR

	apply(GameState.get_world_hour())

func _process(delta: float) -> void:
	GameState.advance_world_time(delta)
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		apply(GameState.get_world_hour())

func _exit_tree() -> void:
	# Leaving a sector is the natural place to commit the clock, so the next
	# mission starts where this one finished even if the game is closed.
	GameState.flush_world_time()

func current_state() -> Dictionary:
	return _state

func current_phase() -> String:
	return phase_key(float(_state.get("h", 12.0)))

func apply(hour: float) -> void:
	var state := sample(hour)
	_state = state
	var elevation := sun_elevation_degrees(hour)
	var azimuth := sun_azimuth_degrees(hour)
	var sun_above := smoothstep(HORIZON_FADE_START, HORIZON_FADE_END, elevation)
	var moon_above := smoothstep(HORIZON_FADE_START, HORIZON_FADE_END, -elevation)

	var sun_energy := float(state.sun_e) * sun_above
	if is_instance_valid(sun):
		sun.rotation_degrees = Vector3(-elevation, azimuth, 0.0)
		sun.light_color = (state.sun as Color).lerp(palette_accent, 0.16)
		sun.light_energy = sun_energy
		sun.visible = sun_energy > 0.004
		sun.shadow_enabled = shadows_allowed and sun_energy > 0.22
		# A grazing sun casts shadows across whole surfaces, where a normal
		# bias tuned for noon turns into acne stripes. Open it up near the
		# horizon and close it again once the sun is overhead.
		sun.shadow_normal_bias = lerpf(2.2, 0.9, clampf(elevation / 45.0, 0.0, 1.0))

	var moon_energy := float(state.moon_e) * moon_above
	if is_instance_valid(moon):
		moon.rotation_degrees = Vector3(elevation, azimuth + 180.0, 0.0)
		moon.light_color = Color(0.52, 0.62, 0.95).lerp(palette_accent, 0.22)
		moon.light_energy = moon_energy
		moon.visible = moon_energy > 0.004
		# Only ever one shadow-casting directional light: two sets of shadows
		# at dusk would cross each other and cost twice as much for nothing.
		moon.shadow_enabled = shadows_allowed and moon_energy > 0.12 and sun_energy <= 0.22

	if is_instance_valid(fill):
		fill.light_color = palette_mid.lerp(state.amb, 0.35)
		fill.light_energy = BASE_FILL_ENERGY * float(state.fill)

	if environment == null:
		return

	var ambient := (state.amb as Color).lerp(palette_mid, 0.28) * ambient_tint
	environment.ambient_light_color = ambient
	environment.ambient_light_energy = maxf(0.05, float(state.amb_e) * ambient_scale)

	var horizon := (state.hor as Color).lerp(palette_mid, 0.18)
	environment.background_color = horizon.lerp(palette_shadow, 0.3)
	environment.background_energy_multiplier = float(state.sky_e)
	if sky_material != null:
		sky_material.sky_top_color = (state.top as Color).lerp(palette_shadow, 0.22)
		sky_material.sky_horizon_color = horizon
		sky_material.ground_horizon_color = (state.gnd as Color).lerp(palette_shadow, 0.45)
		sky_material.ground_bottom_color = (state.gnd as Color).lerp(palette_shadow, 0.75)
		# A low sun reads bigger and softer through the atmosphere, which is
		# most of what sells a sunset before the colours even land.
		sky_material.sun_angle_max = lerpf(13.0, 5.0, clampf(elevation / 45.0, 0.0, 1.0))

	environment.fog_enabled = fog_allowed
	environment.fog_light_color = (state.fog as Color).lerp(palette_mid, 0.2)
	environment.fog_light_energy = lerpf(0.35, 1.0, clampf(float(state.amb_e) / 0.6, 0.0, 1.0))
	environment.fog_density = base_fog_density * float(state.fog_s)
	environment.fog_sun_scatter = clampf(sun_above * 0.45, 0.0, 0.45)

	environment.glow_enabled = glow_allowed
	environment.glow_intensity = float(state.glow)

func _normalized_tint(color: Color) -> Color:
	# The recovered ambient colours range from 0.2 grey to pure white. Only
	# their hue is worth keeping; their level would fight the timecycle.
	var peak := maxf(color.r, maxf(color.g, color.b))
	if peak <= 0.001:
		return Color.WHITE
	return Color(color.r / peak, color.g / peak, color.b / peak)

func _color_from_json(values: Variant) -> Color:
	if values is Array and values.size() >= 3:
		return Color(float(values[0]), float(values[1]), float(values[2]))
	return Color.WHITE
