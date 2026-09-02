extends Node

# Guards THE EXPANSE: the terrain height field (determinism, continuity, the
# plateaus that let a recovered sector sit on procedural ground), the mesh
# clipper that cuts each sector down to its playable core, chunk streaming, and
# the roaming encounter director that replaces the campaign's wave schedule.

const TerrainScript = preload("res://scripts/game/expanse_terrain.gd")
const LandmarkScript = preload("res://scripts/game/sector_landmark.gd")

var failures: Array[String] = []
var restore_credits := 0
var restore_best: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("EXPANSE TEST: " + message)

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	restore_credits = GameState.credits
	restore_best = GameState.best_scores.duplicate(true)

	_test_terrain_field()
	_test_plateaus()
	_test_streaming()
	_test_mesh_clipping()
	await _test_world()
	_test_banking()

	GameState.credits = restore_credits
	GameState.best_scores = restore_best
	GameState._save()

	if failures.is_empty():
		print("EXPANSE_TEST_PASS")
		get_tree().quit(0)
	else:
		print("EXPANSE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _make_terrain(seed_value := 12345) -> WarfareExpanseTerrain:
	var terrain: WarfareExpanseTerrain = TerrainScript.new()
	terrain.configure(seed_value)
	add_child(terrain)
	return terrain

func _test_terrain_field() -> void:
	var first := _make_terrain()
	var second := _make_terrain()

	# The height field has to be a pure function of the seed: the mesh, the
	# collider, the spawner and these tests all read it independently and must
	# agree on where the ground is.
	for sample in [Vector2(0, 0), Vector2(431.5, -280.25), Vector2(-1100, 940), Vector2(77, 77)]:
		var a := first.height_at(sample.x, sample.y)
		var b := second.height_at(sample.x, sample.y)
		_check(is_equal_approx(a, b), "the height field is not deterministic at %s (%f vs %f)" % [sample, a, b])
		_check(is_finite(a), "the height field returned a non-finite value at %s" % sample)

	# Continuity: a small step in world space must not produce a cliff, or the
	# mesh would tear and characters would catch on the seam.
	var worst := 0.0
	for index in range(240):
		var x := -900.0 + float(index) * 7.5
		var z := 220.0 - float(index) * 3.1
		worst = maxf(worst, absf(first.height_at(x + 0.05, z) - first.height_at(x, z)))
	_check(worst < 0.5, "the height field is discontinuous (%f over a 5cm step)" % worst)

	# Open ground has to stay walkable for a CharacterBody3D, so most of the map
	# must sit well under the 45 degree floor limit. Ridges are allowed to be
	# steep; they are the walls.
	var steep := 0
	var samples := 0
	for row in range(-8, 9):
		for column in range(-8, 9):
			var x := float(column) * 120.0
			var z := float(row) * 120.0
			if maxf(absf(x), absf(z)) > 1100.0:
				continue
			samples += 1
			if first.normal_at(x, z).y < 0.72:
				steep += 1
	_check(samples > 100, "the walkability sweep did not sample the map")
	_check(float(steep) / float(samples) < 0.25, "%d of %d open-ground samples are too steep to walk" % [steep, samples])

	_check(first.is_inside(0.0, 0.0), "the map centre is reported as out of bounds")
	_check(not first.is_inside(WarfareExpanseTerrain.HALF_EXTENT + 1.0, 0.0), "the map has no eastern bound")

	first.queue_free()
	second.queue_free()

func _test_plateaus() -> void:
	var terrain := _make_terrain()
	var centre := Vector2(240.0, -160.0)
	var radius := 80.0
	var raw_far := terrain.height_at(centre.x + 400.0, centre.y)
	var base_y := terrain.register_landmark(centre, radius)

	# Inside the footprint the ground is dead flat at the height the sector was
	# planted at, which is the only reason recovered geometry can sit on
	# procedural terrain without a seam.
	for offset: Vector2 in [Vector2.ZERO, Vector2(radius * 0.5, 0.0), Vector2(0.0, -radius * 0.9), Vector2(radius * 0.6, radius * 0.6)]:
		var point := centre + offset
		if offset.length() > radius:
			continue
		var height := terrain.height_at(point.x, point.y)
		_check(absf(height - base_y) < 0.01, "the plateau is not flat at %s (%f vs %f)" % [offset, height, base_y])
	_check(terrain.normal_at(centre.x, centre.y).y > 0.999, "the plateau surface is not level")

	# ... and outside the blend it is the untouched landscape again.
	var outside := centre + Vector2(radius + WarfareExpanseTerrain.PLATEAU_BLEND + 60.0, 0.0)
	var blended := terrain.height_at(outside.x, outside.y)
	var second := _make_terrain()
	_check(
		is_equal_approx(blended, second.height_at(outside.x, outside.y)),
		"the plateau leaked past its blend radius"
	)
	_check(is_equal_approx(raw_far, second.height_at(centre.x + 400.0, centre.y)), "registering a landmark changed distant ground")

	terrain.queue_free()
	second.queue_free()

func _test_streaming() -> void:
	var terrain := _make_terrain()
	var focus := Vector3(0.0, 0.0, 0.0)
	terrain.prime(focus, 320.0)
	var primed := terrain.loaded_chunk_count()
	_check(primed > 0, "priming built no ground under the spawn")
	_check(terrain.collision_chunk_count() == primed, "primed chunks were left without collision")

	for _tick in range(200):
		terrain.update_streaming(focus)
	var loaded := terrain.loaded_chunk_count()
	_check(loaded > primed, "streaming never grew past the primed area")
	_check(
		terrain.collision_chunk_count() < loaded,
		"every visible chunk carries collision; the collision radius is not doing anything"
	)

	# Walking away has to release the ground behind you, or a long expedition
	# would accumulate the whole continent.
	var far := Vector3(2400.0, 0.0, 2400.0)
	for _tick in range(120):
		terrain.update_streaming(far)
	_check(terrain.loaded_chunk_count() < loaded, "chunks are never freed when the player leaves")
	terrain.queue_free()

func _test_mesh_clipping() -> void:
	var mesh_path := "res://assets/models/levels/level_01/stage.obj"
	if not ResourceLoader.exists(mesh_path):
		_check(false, "level 01 stage art is missing")
		return
	var source := load(mesh_path) as Mesh
	_check(source != null, "level 01 stage art failed to load")
	if source == null:
		return
	var radius := 70.0
	var clipped := LandmarkScript.clip_mesh(source, radius, LandmarkScript.MAX_LOCAL_HEIGHT)
	var mesh: ArrayMesh = clipped.mesh
	_check(mesh != null, "clipping level 01 produced no mesh")
	if mesh == null:
		return
	_check(int(clipped.kept_triangles) > 200, "clipping level 01 kept almost nothing (%d)" % int(clipped.kept_triangles))
	_check(
		int(clipped.kept_triangles) < int(clipped.source_triangles),
		"clipping kept every triangle; the horizon shell is still attached"
	)
	_check(mesh.get_surface_count() > 0, "the clipped mesh has no surfaces")

	# Nothing may survive outside the footprint: that is the whole contract the
	# district layout relies on when it spaces the sectors out.
	var worst := 0.0
	var tallest := -INF
	for surface_index in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			worst = maxf(worst, Vector2(vertex.x, vertex.z).length())
			tallest = maxf(tallest, vertex.y)
	_check(worst <= radius + 0.01, "a clipped vertex sits %f from the centre, past the %f footprint" % [worst, radius])
	_check(tallest <= LandmarkScript.MAX_LOCAL_HEIGHT + 0.01, "the clipped mesh still reaches the horizon shell")

func _test_world() -> void:
	GameState.settings.quality = "medium"
	var world := (load("res://scenes/expanse.tscn") as PackedScene).instantiate() as WarfareExpanseWorld
	add_child(world)
	await get_tree().process_frame

	_check(world.terrain != null, "the expedition built no terrain")
	_check(world.districts.size() == 17, "expected 17 districts, built %d" % world.districts.size())
	var sun := world.get_node_or_null("KeyLight") as DirectionalLight3D
	_check(sun != null, "the expedition has no key light")
	if sun != null:
		_check(sun.light_energy > 1.0, "the expedition key light is not lighting anything")
	_check(is_instance_valid(world.player), "the expedition spawned no player")
	if world.terrain == null or not is_instance_valid(world.player):
		world.queue_free()
		return

	# Districts must not overlap, or two sectors would be clipped into each
	# other and their plateaus would fight.
	for i in range(world.districts.size()):
		for j in range(i + 1, world.districts.size()):
			var a: Dictionary = world.districts[i]
			var b: Dictionary = world.districts[j]
			var gap := (a.centre as Vector2).distance_to(b.centre as Vector2)
			var needed := float(a.radius) + float(b.radius) + WarfareExpanseTerrain.PLATEAU_BLEND
			_check(gap > needed, "districts %d and %d are only %f apart, need %f" % [int(a.level), int(b.level), gap, needed])
		var centre: Vector2 = (world.districts[i] as Dictionary).centre
		_check(
			world.terrain.is_inside(centre.x, centre.y),
			"district %d was planted outside the map" % int((world.districts[i] as Dictionary).level)
		)

	# The player has to start standing on the ground, not inside it or above it.
	var position := world.player.global_position
	var ground := world.terrain.height_at(position.x, position.z)
	_check(position.y > ground - 0.5, "the player spawned below the ground (%f vs %f)" % [position.y, ground])
	_check(position.y < ground + 30.0, "the player spawned far above the ground (%f vs %f)" % [position.y, ground])

	var home_built := false
	for district in world.districts:
		if district.node != null:
			home_built = true
			break
	_check(home_built, "no landmark was built around the spawn")

	# Encounters: the director keeps a population without ever exceeding it, and
	# an empty field must never read as a cleared sector.
	for _tick in range(30):
		world._update_encounters(1.0, world.player.global_position)
	_check(world.roamers.size() > 0, "the encounter director spawned nothing")
	_check(
		world.roamers.size() <= WarfareExpanseWorld.ENCOUNTER_POPULATION,
		"the encounter director overshot its population cap (%d)" % world.roamers.size()
	)
	for enemy in world.roamers:
		var distance := enemy.global_position.distance_to(world.player.global_position)
		_check(distance <= WarfareExpanseWorld.DESPAWN_DISTANCE, "a roamer spawned outside the despawn radius (%f)" % distance)

	var population := world.roamers.size()
	world._check_wave_complete()
	_check(not world.completed, "an empty wave check ended the expedition")

	# Walking away recycles the pack. The director is expected to immediately
	# start repopulating around the new position, so what matters is that none
	# of the old roamers were left stranded across the continent.
	_check(population > 0, "no population to recycle")
	var stale := world.roamers.duplicate()
	var away := world.player.global_position + Vector3(600.0, 0.0, 600.0)
	world._update_encounters(0.1, away)
	var stranded := 0
	for enemy in stale:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			stranded += 1
	_check(stranded == 0, "%d roamers were left behind when the player walked away" % stranded)
	_check(
		world.alive_enemies == world.roamers.size(),
		"the alive counter (%d) drifted from the live pack (%d) after recycling" % [world.alive_enemies, world.roamers.size()]
	)
	for enemy in world.roamers:
		var replacement_distance := enemy.global_position.distance_to(away)
		_check(
			replacement_distance <= WarfareExpanseWorld.DESPAWN_DISTANCE,
			"a replacement roamer spawned outside the despawn radius (%f)" % replacement_distance
		)

	world.queue_free()
	await get_tree().process_frame

func _test_banking() -> void:
	var before := GameState.credits
	GameState.complete_expanse_run(4200, 130)
	_check(GameState.credits >= before + 130, "an expedition did not bank its credits")
	_check(int(GameState.best_scores.get("expanse", 0)) >= 4200, "an expedition did not record its score")
	GameState.complete_expanse_run(10, 0)
	_check(int(GameState.best_scores.get("expanse", 0)) >= 4200, "a worse run overwrote the expedition best")
