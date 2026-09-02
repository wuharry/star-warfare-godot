class_name WarfareExpanseWorld
extends WarfareGameWorld

# THE EXPANSE — one continuous 3000x3000 continent instead of a walled arena.
#
# It extends the campaign world on purpose rather than replacing it: the player,
# enemies, projectiles and pickups all reach their world through get_parent()
# and call spawn_tracer / spawn_explosion / request_attack_token /
# has_line_of_sight on it, so inheriting keeps every one of those contracts
# intact and this file only has to replace what actually differs — the ground,
# the landmarks planted in it, and a roaming encounter director in place of
# waves.

const TerrainScript = preload("res://scripts/game/expanse_terrain.gd")
const LandmarkScript = preload("res://scripts/game/sector_landmark.gd")

const WORLD_SEED := 0x5A17E
const LANDMARK_LEVELS := [1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21]
const LANDMARK_COLUMNS := 5
# Districts stay inside this radius so no plateau is ever cut into the border
# ridges, which leaves the outer band as open wilderness to cross.
const LANDMARK_HALF_EXTENT := 1150.0
const CELL_SIZE := Vector2(460.0, 575.0)
# Jitter is bounded so neighbouring plateaus (96 footprint + 78 blend at worst)
# can never reach each other: 460 - 2*50 = 360 apart, 348 needed.
const CELL_JITTER := Vector2(50.0, 60.0)

const LANDMARK_BUILD_RADIUS := 720.0
const LANDMARK_FREE_RADIUS := 1020.0

# Roaming encounters. Hostiles arrive just outside a comfortable engagement
# range, and anything the player walks away from is recycled rather than left
# to trail across the continent forever.
const ENCOUNTER_POPULATION := 8
const ENCOUNTER_INTERVAL := 0.85
const SPAWN_MIN_DISTANCE := 58.0
const SPAWN_MAX_DISTANCE := 98.0
const DESPAWN_DISTANCE := 240.0
const SPAWN_MAX_SLOPE := 0.74
const STREAM_INTERVAL := 0.2

var terrain: WarfareExpanseTerrain
var districts: Array[Dictionary] = []
var roamers: Array[WarfareEnemy] = []
var current_district := -1
var encounter_timer := 2.5
var stream_timer := 0.0
var landmark_build_queue: Array[int] = []
var banked := false
var boss_alive := false
# Set by the encounter director immediately before it calls the inherited
# spawner, which asks for a position through _choose_restored_enemy_spawn.
var pending_spawn_position := Vector3.INF

func _ready() -> void:
	# Deliberately does not call the campaign _ready: there is no sector to load,
	# no arena to build and no wave schedule to start.
	level_data = _expanse_level_data()
	arena_size = WarfareExpanseTerrain.HALF_EXTENT
	difficulty_profile = GameState.get_difficulty_profile()
	max_attack_tokens = int(difficulty_profile.get("attack_slots", 99))
	GameState.apply_viewport_quality()
	rng.seed = WORLD_SEED

	_build_terrain()
	_plan_districts()
	_build_environment()
	_build_boundary()
	var start := _player_start()
	terrain.prime(start, 320.0)
	player_spawn_points = [start]
	_build_player()
	_build_hud()
	_start_music()
	terrain.update_streaming(player.global_position)
	_stream_landmarks(player.global_position)
	_flush_landmark_queue(true)
	call_deferred("_begin_expedition")

func _process(delta: float) -> void:
	super(delta)
	if completed or not is_instance_valid(player):
		return
	var focus := player.global_position
	stream_timer -= delta
	if stream_timer <= 0.0:
		stream_timer = STREAM_INTERVAL
		terrain.update_streaming(focus)
		_stream_landmarks(focus)
		_report_district(focus)
	_flush_landmark_queue(false)
	_update_encounters(delta, focus)

func _exit_tree() -> void:
	super()
	_bank_run()

# --- world construction -----------------------------------------------------

func _expanse_level_data() -> Dictionary:
	# The HUD, the music picker and the result screen all read a level record,
	# so the expedition presents itself as one.
	return {
		"number": 22,
		"name": "THE EXPANSE",
		"waves": 0,
		"base_enemies": ENCOUNTER_POPULATION,
		"enemy_health": 60.0,
		"boss": false,
		"palette": [Color("2a2018"), Color("6d5b40"), Color("dcc08a")],
		"arena_size": WarfareExpanseTerrain.HALF_EXTENT,
	}

func _build_terrain() -> void:
	terrain = TerrainScript.new()
	terrain.name = "Terrain"
	terrain.configure(WORLD_SEED)
	add_child(terrain)

func _plan_districts() -> void:
	# Seventeen recovered sectors laid out on a jittered grid. Registering each
	# footprint with the terrain flattens the ground under it, so the original
	# geometry lands on a plateau at exactly its own base height.
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = WORLD_SEED + 7
	for index in range(LANDMARK_LEVELS.size()):
		var level_number := int(LANDMARK_LEVELS[index])
		var column := index % LANDMARK_COLUMNS
		var row := index / LANDMARK_COLUMNS
		var centre := Vector2(
			-LANDMARK_HALF_EXTENT + CELL_SIZE.x * (float(column) + 0.5),
			-LANDMARK_HALF_EXTENT + CELL_SIZE.y * (float(row) + 0.5)
		)
		centre += Vector2(
			layout_rng.randf_range(-CELL_JITTER.x, CELL_JITTER.x),
			layout_rng.randf_range(-CELL_JITTER.y, CELL_JITTER.y)
		)
		var metadata := _load_level_metadata(level_number)
		var radius := _footprint_radius(metadata)
		var base_y := terrain.register_landmark(centre, radius)
		districts.append({
			"level": level_number,
			"centre": centre,
			"radius": radius,
			"base_y": base_y,
			"spawn_local": _first_respawn(metadata),
			"node": null,
			"name": str(GameState.get_level_data(level_number).get("name", "SECTOR")),
			"boss": bool(GameState.get_level_data(level_number).get("boss", false)),
			"enemy_health": float(GameState.get_level_data(level_number).get("enemy_health", 60.0)),
		})

func _load_level_metadata(level_number: int) -> Dictionary:
	var path := "res://assets/models/levels/level_%02d/level.json" % level_number
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _footprint_radius(metadata: Dictionary) -> float:
	# The playable core is whatever the original spawn, waypoint and objective
	# markers cover; everything past it was horizon dressing.
	var markers: Dictionary = metadata.get("markers", {})
	var extent := 0.0
	for marker_name in markers:
		for record in markers[marker_name]:
			if not record is Dictionary:
				continue
			var values: Variant = record.get("position", [])
			if values is Array and values.size() >= 3:
				extent = maxf(extent, maxf(absf(float(values[0])), absf(float(values[2]))))
	if extent <= 0.0:
		return 72.0
	return clampf(extent + 20.0, 56.0, 96.0)

func _first_respawn(metadata: Dictionary) -> Vector3:
	var markers: Dictionary = metadata.get("markers", {})
	for key in ["Respawn", "FlagSpawn", "EnemySpawnPoint"]:
		for record in markers.get(key, []):
			if not record is Dictionary:
				continue
			var values: Variant = record.get("position", [])
			if values is Array and values.size() >= 3:
				return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO

func _player_start() -> Vector3:
	if districts.is_empty():
		return Vector3(0.0, terrain.height_at(0.0, 0.0) + 1.0, 0.0)
	var home: Dictionary = districts[0]
	var centre: Vector2 = home.centre
	var local: Vector3 = home.spawn_local
	var position := Vector3(centre.x + local.x, 0.0, centre.y + local.z)
	position.y = maxf(terrain.height_at(position.x, position.z), float(home.base_y) + local.y) + 1.2
	return position

func _environment_fill_radius() -> float:
	# The campaign scales its bounce light to the arena. Out here that would be
	# a 1500-unit omni light, so the bounce is sized to the fight instead.
	return 120.0

func _build_environment() -> void:
	# The recovered sectors are lit by the flat ambient their Unity scenes
	# shipped with, and the campaign builder reproduces that. None of it suits
	# open country: its fog density is tuned to hide an arena wall 30 units away
	# and would close the horizon in at 300, and a sector with no skybox is
	# fine indoors and wrong under an open sky. So the expedition carries its
	# own fixed environment -- still fixed, just built for a landscape.
	var quality: Dictionary = GameState.get_quality_profile()
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Warm, because out here the bounce comes off sand rather than off a blue
	# sky: a neutral ambient greys the whole continent out.
	environment.ambient_light_color = Color(0.62, 0.57, 0.48)
	environment.ambient_light_energy = 0.5
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = bool(quality.get("glow", true))
	environment.glow_intensity = 0.85

	if bool(quality.get("sky", true)):
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.20, 0.38, 0.66)
		sky_material.sky_horizon_color = Color(0.78, 0.74, 0.64)
		sky_material.ground_horizon_color = Color(0.30, 0.26, 0.21)
		sky_material.ground_bottom_color = Color(0.18, 0.15, 0.12)
		sky_material.sky_curve = 0.18
		sky_material.sun_angle_max = 8.0
		sky_material.sun_curve = 0.09
		sky_material.use_debanding = true
		var sky := Sky.new()
		sky.sky_material = sky_material
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		environment.sky = sky
		environment.background_mode = Environment.BG_SKY
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.62, 0.60, 0.54)

	# Aerial perspective only: enough to settle the far ridges back and to cover
	# the streaming boundary, never enough to shorten the map.
	environment.fog_enabled = bool(quality.get("fog", true))
	# 0.0022 put roughly half the fog colour over anything 300 units out, which
	# flattened the dunes into pale grey long before they were far away. This
	# keeps the far ridges settled back without bleaching the mid ground.
	environment.fog_light_color = Color(0.72, 0.67, 0.58)
	environment.fog_light_energy = 0.7
	environment.fog_density = 0.0013
	environment.fog_sky_affect = 0.3
	environment.fog_aerial_perspective = 0.25
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	# 1.55 blew the sand out to flat white under the filmic curve; the dunes
	# only keep their shape at roughly the campaign's key intensity.
	sun.light_energy = 1.18
	sun.shadow_enabled = bool(quality.get("shadows", true))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(0.0, 7.0, 0.0)
	fill.light_color = Color(0.58, 0.60, 0.66)
	fill.light_energy = 5.0
	fill.omni_range = _environment_fill_radius()
	add_child(fill)

	effects_root = Node3D.new()
	effects_root.name = "Effects"
	add_child(effects_root)

func _build_boundary() -> void:
	# The border ridges are already too steep to climb; these are the backstop
	# that keeps a stray dash or a knockback from leaving the map.
	var half := WarfareExpanseTerrain.HALF_EXTENT
	var thickness := 8.0
	var height := 400.0
	var walls := {
		"BoundaryNorth": [Vector3(half * 2.0, height, thickness), Vector3(0.0, height * 0.5, -half)],
		"BoundarySouth": [Vector3(half * 2.0, height, thickness), Vector3(0.0, height * 0.5, half)],
		"BoundaryWest": [Vector3(thickness, height, half * 2.0), Vector3(-half, height * 0.5, 0.0)],
		"BoundaryEast": [Vector3(thickness, height, half * 2.0), Vector3(half, height * 0.5, 0.0)],
	}
	for wall_name: String in walls:
		var record: Array = walls[wall_name]
		var body := StaticBody3D.new()
		body.name = wall_name
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = record[1]
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = record[0]
		collision.shape = shape
		body.add_child(collision)
		add_child(body)

func _begin_expedition() -> void:
	hud.announce(tr("THE EXPANSE • FREE DEPLOYMENT"), 2.4)
	await get_tree().create_timer(2.2).timeout
	if not completed and not districts.is_empty():
		current_district = 0
		hud.announce(tr("ENTERING %s") % tr(str(districts[0].name)), 1.6)

# --- landmark streaming -----------------------------------------------------

func _stream_landmarks(focus: Vector3) -> void:
	var focus_2d := Vector2(focus.x, focus.z)
	for index in range(districts.size()):
		var district: Dictionary = districts[index]
		var distance := focus_2d.distance_to(district.centre as Vector2)
		var node: Node = district.node
		if distance <= LANDMARK_BUILD_RADIUS:
			if node == null and not landmark_build_queue.has(index):
				landmark_build_queue.append(index)
		elif distance > LANDMARK_FREE_RADIUS:
			landmark_build_queue.erase(index)
			if node != null:
				if is_instance_valid(node):
					node.queue_free()
				district.node = null

func _flush_landmark_queue(build_all: bool) -> void:
	# Clipping a sector costs a few milliseconds, so only one is rebuilt per
	# frame unless the caller is the initial load and nothing is on screen yet.
	while not landmark_build_queue.is_empty():
		var index: int = landmark_build_queue.pop_front()
		_build_landmark(index)
		if not build_all:
			return

func _build_landmark(index: int) -> void:
	var district: Dictionary = districts[index]
	if district.node != null:
		return
	var landmark := LandmarkScript.new()
	landmark.name = "District%02d" % int(district.level)
	add_child(landmark)
	if not landmark.configure(int(district.level), float(district.radius)):
		landmark.queue_free()
		return
	var centre: Vector2 = district.centre
	landmark.position = Vector3(centre.x, float(district.base_y), centre.y)
	district.node = landmark

# --- roaming encounters -----------------------------------------------------

func _update_encounters(delta: float, focus: Vector3) -> void:
	var live: Array[WarfareEnemy] = []
	for enemy in roamers:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		if enemy.global_position.distance_to(focus) > DESPAWN_DISTANCE:
			# Recycled, not killed: it never reaches _on_enemy_died, so the
			# counter is corrected by hand and no reward is paid out.
			alive_enemies = maxi(0, alive_enemies - 1)
			release_attack_token(enemy)
			enemy.queue_free()
			continue
		live.append(enemy)
	roamers = live

	encounter_timer -= delta
	if encounter_timer > 0.0 or roamers.size() >= ENCOUNTER_POPULATION:
		return
	encounter_timer = ENCOUNTER_INTERVAL
	_spawn_roamer(focus)

func _spawn_roamer(focus: Vector3) -> void:
	var position := _find_spawn_position(focus)
	if position == Vector3.INF:
		return
	var district := _district_at(Vector2(focus.x, focus.z))
	var kind := _choose_roamer_kind(district)
	if kind == "boss":
		boss_alive = true
	# The campaign spawner reads the sector's health from level_data, which out
	# here changes with whichever district the player is standing in: fighting
	# near the final breach is meant to be nothing like the opening outpost.
	level_data.enemy_health = float(district.get("enemy_health", 60.0)) if not district.is_empty() else 60.0
	pending_spawn_position = position
	var spawned := _spawn_enemy(kind, rng.randf() < 0.18)
	if spawned != null:
		roamers.append(spawned)

func _choose_roamer_kind(district: Dictionary) -> String:
	if not district.is_empty() and bool(district.get("boss", false)) and not boss_alive and rng.randf() < 0.09:
		return "boss"
	var roll := rng.randf()
	if roll < 0.18:
		return "spitter"
	if roll < 0.32:
		return "brute"
	return "crawler"

func _find_spawn_position(focus: Vector3) -> Vector3:
	for _attempt in range(12):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(SPAWN_MIN_DISTANCE, SPAWN_MAX_DISTANCE)
		var x := focus.x + cos(angle) * distance
		var z := focus.z + sin(angle) * distance
		if not terrain.is_inside(x, z):
			continue
		if terrain.normal_at(x, z).y < SPAWN_MAX_SLOPE:
			continue
		return Vector3(x, terrain.height_at(x, z) + 0.6, z)
	return Vector3.INF

# --- campaign hooks the expedition replaces ---------------------------------

func _choose_restored_enemy_spawn(_kind: String) -> Vector3:
	# The campaign picks from the sector's recovered spawn markers. Out here the
	# encounter director has already chosen the spot.
	var chosen := pending_spawn_position
	pending_spawn_position = Vector3.INF
	return chosen

func _check_wave_complete() -> void:
	# There are no waves to complete, and without this override an empty field
	# would read as "sector cleared" and end the expedition.
	pass

func _on_enemy_died(enemy: WarfareEnemy, death_position: Vector3, reward: int, score_value_amount: int) -> void:
	if is_instance_valid(enemy) and enemy.enemy_kind == "boss":
		boss_alive = false
	super(enemy, death_position, reward, score_value_amount)

func _on_player_died() -> void:
	_bank_run()
	super()

func _report_district(focus: Vector3) -> void:
	var index := _district_index_at(Vector2(focus.x, focus.z))
	if index == current_district:
		return
	current_district = index
	if index < 0:
		hud.announce(tr("OPEN GROUND"), 1.2)
	else:
		hud.announce(tr("ENTERING %s") % tr(str(districts[index].name)), 1.6)

func _district_index_at(point: Vector2) -> int:
	for index in range(districts.size()):
		var district: Dictionary = districts[index]
		if point.distance_to(district.centre as Vector2) <= float(district.radius) + 40.0:
			return index
	return -1

func _district_at(point: Vector2) -> Dictionary:
	# Nearest district, whether or not the player is standing inside it: it is
	# what decides how hard the local wildlife hits.
	var best: Dictionary = {}
	var best_distance := INF
	for district in districts:
		var distance := point.distance_to(district.centre as Vector2)
		if distance < best_distance:
			best_distance = distance
			best = district
	return best

func _bank_run() -> void:
	if banked:
		return
	banked = true
	GameState.complete_expanse_run(score, battle_credits)
