class_name WarfareExpanseTerrain
extends Node3D

# The continuous ground of THE EXPANSE.
#
# Height is a pure function of (x, z): layered noise for the continent, hills
# and surface detail, a ridged band for the impassable spines, a rim that walls
# the map in, and finally a plateau pass that flattens the ground under every
# recovered sector so the original geometry can sit on it without a seam.
# Keeping it a pure function is what lets the mesh, the collider, enemy spawn
# points and the tests all agree on where the ground is without asking physics.
#
# The mesh itself is streamed in chunks around the player; nothing outside the
# build radius exists, and the atmospheric fog is dense enough at that distance
# to hide the edge.

const CHUNK_SIZE := 250.0
const CHUNK_RESOLUTION := 24
const HALF_EXTENT := 1500.0

# Visual chunks reach further than collision: you can see a ridge long before
# you can walk on it, and trimesh colliders are the expensive half.
const BUILD_RADIUS := 850.0
const FREE_RADIUS := 1150.0
const COLLISION_RADIUS := 420.0
const CHUNKS_PER_FRAME := 2

# Slopes stay walkable across the continent and hills; only the ridge band and
# the border rim are steep enough to stop a CharacterBody3D.
const CONTINENT_AMPLITUDE := 42.0
const HILL_AMPLITUDE := 7.5
const DETAIL_AMPLITUDE := 1.4
const RIDGE_AMPLITUDE := 108.0
const RIM_HEIGHT := 165.0
const RIM_START := 1180.0
const RIM_END := 1470.0

# How far past a sector's own footprint the ground keeps being flattened before
# it blends back into the landscape.
const PLATEAU_BLEND := 78.0

# Rock scatter. The open country between districts is most of the map, so it
# carries its own cover: deterministic boulder fields, drawn per chunk as a
# single MultiMesh and collided only while the chunk is close enough to matter.
const ROCKS_PER_CHUNK := 14
const ROCK_MIN_SCALE := 1.3
const ROCK_MAX_SCALE := 5.2
const ROCK_MIN_NORMAL := 0.80
const ROCK_DISTRICT_CLEARANCE := 26.0

var world_seed := 0x5A17
var landmarks: Array[Dictionary] = []

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _ridge_mask := FastNoiseLite.new()

var _rock_mesh: Mesh
var _rock_material: StandardMaterial3D
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _material: StandardMaterial3D

func configure(seed_value: int) -> void:
	world_seed = seed_value
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.seed = seed_value
	_continent.frequency = 0.00115
	_continent.fractal_octaves = 3
	_continent.fractal_lacunarity = 2.1
	_continent.fractal_gain = 0.42

	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.seed = seed_value + 17
	_hills.frequency = 0.0062
	_hills.fractal_octaves = 3

	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.seed = seed_value + 41
	_detail.frequency = 0.021
	_detail.fractal_octaves = 2

	# Ridged noise: the absolute value of a smooth field folds every zero
	# crossing into a crest, which is what reads as a mountain spine instead of
	# a rolling dune.
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.seed = seed_value + 73
	_ridge.frequency = 0.0019
	_ridge.fractal_octaves = 2

	_ridge_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_mask.seed = seed_value + 131
	_ridge_mask.frequency = 0.0009

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	_material.metallic = 0.0

	_rock_material = StandardMaterial3D.new()
	_rock_material.albedo_color = Color(0.42, 0.37, 0.31)
	_rock_material.roughness = 0.92
	_rock_material.metallic = 0.02
	# A coarse sphere is all a boulder needs at this distance; the varied
	# non-uniform scale and rotation per instance does the shaping.
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.7
	rock.radial_segments = 7
	rock.rings = 4
	rock.material = _rock_material
	_rock_mesh = rock

func register_landmark(centre: Vector2, radius: float) -> float:
	# Returns the height the sector should be planted at, which is the raw
	# landscape height at its centre before any flattening. Registering it then
	# makes every later height query honour the plateau.
	var base_y := _landscape_height(centre.x, centre.y)
	landmarks.append({"centre": centre, "radius": radius, "base_y": base_y})
	return base_y

func height_at(x: float, z: float) -> float:
	var height := _landscape_height(x, z)
	for landmark in landmarks:
		var centre: Vector2 = landmark.centre
		var distance := Vector2(x, z).distance_to(centre)
		var outer: float = float(landmark.radius) + PLATEAU_BLEND
		if distance >= outer:
			continue
		var weight := 1.0 - smoothstep(float(landmark.radius), outer, distance)
		height = lerpf(height, float(landmark.base_y), weight)
	return height

func normal_at(x: float, z: float) -> Vector3:
	var step := 2.0
	var dx := height_at(x + step, z) - height_at(x - step, z)
	var dz := height_at(x, z + step) - height_at(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()

func is_inside(x: float, z: float) -> bool:
	return absf(x) < HALF_EXTENT and absf(z) < HALF_EXTENT

func prime(focus: Vector3, radius: float) -> void:
	# Builds and collides everything within radius up front, ignoring the
	# per-frame budget. Without this the player would spawn before the chunk
	# under their feet exists and drop straight through the world.
	var reach := int(ceil(radius / CHUNK_SIZE))
	var centre_chunk := Vector2i(int(floor(focus.x / CHUNK_SIZE)), int(floor(focus.z / CHUNK_SIZE)))
	for cz in range(centre_chunk.y - reach, centre_chunk.y + reach + 1):
		for cx in range(centre_chunk.x - reach, centre_chunk.x + reach + 1):
			var key := Vector2i(cx, cz)
			if _chunks.has(key) or not _chunk_in_bounds(key):
				continue
			if _chunk_distance(key, focus) > radius:
				continue
			_pending.erase(key)
			_build_chunk(key, focus)
			_attach_collision(key)

func update_streaming(focus: Vector3) -> void:
	var centre_chunk := Vector2i(
		int(floor(focus.x / CHUNK_SIZE)),
		int(floor(focus.z / CHUNK_SIZE))
	)
	var reach := int(ceil(BUILD_RADIUS / CHUNK_SIZE))
	for cz in range(centre_chunk.y - reach, centre_chunk.y + reach + 1):
		for cx in range(centre_chunk.x - reach, centre_chunk.x + reach + 1):
			var key := Vector2i(cx, cz)
			if _chunks.has(key) or _pending.has(key):
				continue
			if not _chunk_in_bounds(key):
				continue
			if _chunk_distance(key, focus) <= BUILD_RADIUS:
				_pending.append(key)

	for key: Vector2i in _chunks.keys():
		if _chunk_distance(key, focus) > FREE_RADIUS:
			_free_chunk(key)

	var built := 0
	while built < CHUNKS_PER_FRAME and not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		if _chunks.has(key):
			continue
		_build_chunk(key, focus)
		built += 1

	# Collision follows the player more tightly than the visual mesh, so it is
	# added and dropped independently of whether the chunk is drawn.
	for key: Vector2i in _chunks.keys():
		var record: Dictionary = _chunks[key]
		var wants_collision := _chunk_distance(key, focus) <= COLLISION_RADIUS
		var has_collision := is_instance_valid(record.collision)
		if wants_collision and not has_collision:
			_attach_collision(key)
		elif not wants_collision and has_collision:
			_detach_collision(key)

func loaded_chunk_count() -> int:
	return _chunks.size()

func collision_chunk_count() -> int:
	var total := 0
	for key: Vector2i in _chunks.keys():
		if is_instance_valid((_chunks[key] as Dictionary).collision):
			total += 1
	return total

func _chunk_in_bounds(key: Vector2i) -> bool:
	var origin := Vector2(float(key.x) * CHUNK_SIZE, float(key.y) * CHUNK_SIZE)
	return origin.x >= -HALF_EXTENT and origin.y >= -HALF_EXTENT \
		and origin.x < HALF_EXTENT and origin.y < HALF_EXTENT

func _chunk_distance(key: Vector2i, focus: Vector3) -> float:
	var centre := Vector2(
		(float(key.x) + 0.5) * CHUNK_SIZE,
		(float(key.y) + 0.5) * CHUNK_SIZE
	)
	return centre.distance_to(Vector2(focus.x, focus.z))

func _build_chunk(key: Vector2i, _focus: Vector3) -> void:
	var origin := Vector2(float(key.x) * CHUNK_SIZE, float(key.y) * CHUNK_SIZE)
	var step := CHUNK_SIZE / float(CHUNK_RESOLUTION)
	var side := CHUNK_RESOLUTION + 1

	# Sample one ring wider than the chunk so normals at the seam are computed
	# from real neighbours instead of being clamped, which is what stops the
	# lighting from creasing along every chunk border.
	var padded := side + 2
	var heights := PackedFloat32Array()
	heights.resize(padded * padded)
	for row in range(padded):
		for column in range(padded):
			var wx := origin.x + float(column - 1) * step
			var wz := origin.y + float(row - 1) * step
			heights[row * padded + column] = height_at(wx, wz)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	colors.resize(side * side)
	uvs.resize(side * side)

	for row in range(side):
		for column in range(side):
			var padded_index := (row + 1) * padded + (column + 1)
			var height := heights[padded_index]
			var local := Vector3(float(column) * step, height, float(row) * step)
			var index := row * side + column
			vertices[index] = local
			var dx := heights[padded_index + 1] - heights[padded_index - 1]
			var dz := heights[padded_index + padded] - heights[padded_index - padded]
			var normal := Vector3(-dx, 2.0 * step, -dz).normalized()
			normals[index] = normal
			colors[index] = _ground_colour(height, normal)
			uvs[index] = Vector2(float(column), float(row)) * 0.5

	var indices := PackedInt32Array()
	indices.resize(CHUNK_RESOLUTION * CHUNK_RESOLUTION * 6)
	var cursor := 0
	for row in range(CHUNK_RESOLUTION):
		for column in range(CHUNK_RESOLUTION):
			var top_left := row * side + column
			var top_right := top_left + 1
			var bottom_left := top_left + side
			var bottom_right := bottom_left + 1
			indices[cursor] = top_left
			indices[cursor + 1] = bottom_left
			indices[cursor + 2] = top_right
			indices[cursor + 3] = top_right
			indices[cursor + 4] = bottom_left
			indices[cursor + 5] = bottom_right
			cursor += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)

	var instance := MeshInstance3D.new()
	instance.name = "Chunk_%d_%d" % [key.x, key.y]
	instance.mesh = mesh
	instance.position = Vector3(origin.x, 0.0, origin.y)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)

	var rocks := _scatter_rocks(key)
	var rock_instance: MultiMeshInstance3D = null
	if not rocks.is_empty():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _rock_mesh
		multi.instance_count = rocks.size()
		for slot in range(rocks.size()):
			multi.set_instance_transform(slot, rocks[slot])
		rock_instance = MultiMeshInstance3D.new()
		rock_instance.name = "Rocks_%d_%d" % [key.x, key.y]
		rock_instance.multimesh = multi
		rock_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(rock_instance)

	_chunks[key] = {"instance": instance, "collision": null, "rocks": rocks, "rock_instance": rock_instance}

func _attach_collision(key: Vector2i) -> void:
	var record: Dictionary = _chunks[key]
	var instance: MeshInstance3D = record.instance
	if not is_instance_valid(instance):
		return
	var shape := (instance.mesh as ArrayMesh).create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = "ChunkBody_%d_%d" % [key.x, key.y]
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = instance.position
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	# The boulders are collided with spheres sized to their own scale: close
	# enough for cover and a fraction of the cost of another trimesh.
	for rock: Transform3D in record.rocks:
		var rock_shape := SphereShape3D.new()
		var rock_scale := rock.basis.get_scale()
		rock_shape.radius = maxf(0.6, (rock_scale.x + rock_scale.z) * 0.42)
		var rock_collision := CollisionShape3D.new()
		rock_collision.shape = rock_shape
		rock_collision.position = rock.origin - Vector3(instance.position.x, 0.0, instance.position.z) + Vector3.DOWN * rock_scale.y * 0.15
		body.add_child(rock_collision)

	add_child(body)
	record.collision = body

func _detach_collision(key: Vector2i) -> void:
	var record: Dictionary = _chunks[key]
	if is_instance_valid(record.collision):
		(record.collision as Node).queue_free()
	record.collision = null

func _free_chunk(key: Vector2i) -> void:
	var record: Dictionary = _chunks[key]
	if is_instance_valid(record.instance):
		(record.instance as Node).queue_free()
	if is_instance_valid(record.rock_instance):
		(record.rock_instance as Node).queue_free()
	if is_instance_valid(record.collision):
		(record.collision as Node).queue_free()
	_chunks.erase(key)

func _scatter_rocks(key: Vector2i) -> Array[Transform3D]:
	# Seeded from the chunk coordinates, so a boulder field is identical every
	# time that chunk streams back in and the collider always matches the art.
	var placements: Array[Transform3D] = []
	var scatter := RandomNumberGenerator.new()
	scatter.seed = hash(Vector2i(key.x, key.y)) ^ world_seed
	var origin := Vector2(float(key.x) * CHUNK_SIZE, float(key.y) * CHUNK_SIZE)
	for _attempt in range(ROCKS_PER_CHUNK):
		var x := origin.x + scatter.randf() * CHUNK_SIZE
		var z := origin.y + scatter.randf() * CHUNK_SIZE
		if _inside_district(x, z, ROCK_DISTRICT_CLEARANCE):
			continue
		if normal_at(x, z).y < ROCK_MIN_NORMAL:
			continue
		var scale_value := scatter.randf_range(ROCK_MIN_SCALE, ROCK_MAX_SCALE)
		var basis := Basis(Vector3.UP, scatter.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3(
			scale_value * scatter.randf_range(0.8, 1.35),
			scale_value * scatter.randf_range(0.55, 1.1),
			scale_value * scatter.randf_range(0.8, 1.35)
		))
		# Sunk slightly so the sphere reads as an outcrop rather than a ball
		# resting on the surface.
		var height := height_at(x, z) - scale_value * 0.22
		placements.append(Transform3D(basis, Vector3(x, height, z)))
	return placements

func _inside_district(x: float, z: float, clearance: float) -> bool:
	for landmark in landmarks:
		var centre: Vector2 = landmark.centre
		if Vector2(x, z).distance_to(centre) <= float(landmark.radius) + clearance:
			return true
	return false

func _landscape_height(x: float, z: float) -> float:
	var height := _continent.get_noise_2d(x, z) * CONTINENT_AMPLITUDE
	height += _hills.get_noise_2d(x, z) * HILL_AMPLITUDE
	height += _detail.get_noise_2d(x, z) * DETAIL_AMPLITUDE

	# Ridges only exist where the mask says so, so the map keeps open ground to
	# fight in instead of turning into wall-to-wall mountains.
	var mask := clampf((_ridge_mask.get_noise_2d(x, z) + 0.04) * 2.2, 0.0, 1.0)
	if mask > 0.0:
		var crest := 1.0 - absf(_ridge.get_noise_2d(x, z))
		height += pow(crest, 3.0) * RIDGE_AMPLITUDE * mask

	var rim := smoothstep(RIM_START, RIM_END, maxf(absf(x), absf(z)))
	height += rim * rim * RIM_HEIGHT
	return height

func _ground_colour(height: float, normal: Vector3) -> Color:
	# Slope and altitude pick the material: dust in the basins, dry scrub on the
	# flats, bare rock wherever the ground is too steep to hold anything, and
	# pale stone on the high ridges.
	var basin := Color(0.44, 0.42, 0.33)
	var dust := Color(0.62, 0.52, 0.36)
	var rock := Color(0.36, 0.33, 0.30)
	var peak := Color(0.70, 0.71, 0.74)

	# The thresholds follow the amplitudes above: pale stone is meant to mark the
	# genuine ridges, not every rise in a landscape that now swings 40 units.
	var ground := basin.lerp(dust, clampf((height + 30.0) / 70.0, 0.0, 1.0))
	ground = ground.lerp(peak, clampf((height - 88.0) / 70.0, 0.0, 1.0))
	var slope := clampf((1.0 - normal.y) * 3.4, 0.0, 1.0)
	return ground.lerp(rock, slope)
