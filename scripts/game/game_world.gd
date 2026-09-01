class_name WarfareGameWorld
extends Node3D

const PlayerScript = preload("res://scripts/game/player.gd")
const EnemyScript = preload("res://scripts/game/enemy.gd")
const PickupScript = preload("res://scripts/game/pickup.gd")
const HUDScript = preload("res://scripts/ui/hud.gd")

var level_data: Dictionary
var player: WarfarePlayer
var hud: WarfareHUD
var current_wave := 0
var alive_enemies := 0
var total_spawned := 0
var kills := 0
var score := 0
var battle_credits := 0
var elapsed_time := 0.0
var spawning := false
var completed := false
var arena_size := 30.0
var rng := RandomNumberGenerator.new()
var effects_root: Node3D
var music: AudioStreamPlayer
var stage_metadata: Dictionary = {}
var player_spawn_points: Array[Vector3] = []
var enemy_spawn_points: Array[Vector3] = []
var boss_spawn_points: Array[Vector3] = []
var waypoint_positions: Array[Vector3] = []
var waypoint_graph: Array = []

const MAX_ACTIVE_ENEMIES := 8

func _ready() -> void:
	level_data = GameState.get_level_data(GameState.selected_level)
	arena_size = float(level_data.arena_size)
	GameState.apply_viewport_quality()
	rng.seed = 0x5A17 + int(level_data.number) * 991
	_load_stage_metadata()
	_build_environment()
	_build_arena()
	_build_player()
	_build_hud()
	_start_music()
	call_deferred("_begin_level")

func _process(delta: float) -> void:
	if not completed:
		elapsed_time += delta

func _exit_tree() -> void:
	if is_instance_valid(music):
		music.stop()
		music.stream = null

func _build_environment() -> void:
	var palette: Array = level_data.palette
	var restored_settings: Dictionary = stage_metadata.get("render_settings", {})
	var quality: Dictionary = GameState.get_quality_profile()
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(palette[0]).darkened(0.34)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if restored_settings.is_empty():
		environment.ambient_light_color = Color(palette[2])
		environment.ambient_light_energy = 0.48
	else:
		environment.ambient_light_color = _color_from_json(restored_settings.get("ambient_color", [0.2, 0.2, 0.2, 1.0]))
		environment.ambient_light_energy = maxf(0.15, float(restored_settings.get("ambient_intensity", 1.0)))
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = bool(quality.glow)
	environment.glow_intensity = 0.85
	environment.fog_enabled = bool(quality.fog) and bool(restored_settings.get("fog_enabled", true))
	environment.fog_light_color = _color_from_json(restored_settings.get("fog_color", [Color(palette[1]).r, Color(palette[1]).g, Color(palette[1]).b, 1.0]))
	environment.fog_light_energy = 0.45
	environment.fog_density = float(restored_settings.get("fog_density", 0.008))
	environment.fog_sky_affect = 0.55
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -32, 0)
	sun.light_color = Color(palette[2])
	sun.light_energy = 1.35
	sun.shadow_enabled = bool(quality.shadows)
	sun.directional_shadow_max_distance = 65.0
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 7, 0)
	fill.light_color = Color(palette[1])
	fill.light_energy = 8.0
	fill.omni_range = arena_size * 1.25
	add_child(fill)
	effects_root = Node3D.new()
	effects_root.name = "Effects"
	add_child(effects_root)

func _build_arena() -> void:
	if _build_restored_arena():
		return
	var palette: Array = level_data.palette
	var ground_material := _material(Color(palette[0]).lightened(0.08), 0.92, 0.05)
	_add_static_box("Ground", Vector3(arena_size * 2.0, 0.45, arena_size * 2.0), Vector3(0, -0.25, 0), ground_material)
	var wall_material := _material(Color(palette[1]).darkened(0.28), 0.72, 0.22)
	var wall_height := 4.8
	_add_static_box("NorthWall", Vector3(arena_size * 2.0 + 2.0, wall_height, 1.0), Vector3(0, wall_height * 0.5, -arena_size), wall_material)
	_add_static_box("SouthWall", Vector3(arena_size * 2.0 + 2.0, wall_height, 1.0), Vector3(0, wall_height * 0.5, arena_size), wall_material)
	_add_static_box("WestWall", Vector3(1.0, wall_height, arena_size * 2.0), Vector3(-arena_size, wall_height * 0.5, 0), wall_material)
	_add_static_box("EastWall", Vector3(1.0, wall_height, arena_size * 2.0), Vector3(arena_size, wall_height * 0.5, 0), wall_material)

	var prop_material := _material(Color(palette[1]), 0.58, 0.42)
	var glow_material := _material(Color(palette[2]).darkened(0.15), 0.3, 0.35, Color(palette[2]) * 0.55)
	var prop_count := 10 + int(level_data.number) % 7
	for i in range(prop_count):
		var angle := TAU * float(i) / float(prop_count) + rng.randf_range(-0.16, 0.16)
		var radius := rng.randf_range(arena_size * 0.32, arena_size * 0.72)
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var size := Vector3(rng.randf_range(1.4, 3.2), rng.randf_range(1.5, 4.6), rng.randf_range(1.4, 3.4))
		_add_static_box("Cover_%02d" % i, size, pos + Vector3.UP * size.y * 0.5, prop_material)
		if i % 3 == 0:
			_add_visual_box("Beacon_%02d" % i, Vector3(0.16, size.y * 0.72, 0.18), pos + Vector3(0, size.y * 0.58, 0), glow_material)
	for i in range(18):
		var strip_angle := TAU * float(i) / 18.0
		var strip_pos := Vector3(cos(strip_angle) * (arena_size - 1.15), 0.06, sin(strip_angle) * (arena_size - 1.15))
		var strip := _add_visual_box("BoundaryGlow", Vector3(2.9, 0.08, 0.16), strip_pos, glow_material)
		strip.rotation.y = -strip_angle

func _build_player() -> void:
	player = PlayerScript.new()
	add_child(player)
	if player_spawn_points.is_empty():
		player.position = Vector3(0, 0.04, arena_size * 0.32)
	else:
		player.position = player_spawn_points[0] + Vector3.UP * 0.04
	player.died.connect(_on_player_died)

func _build_hud() -> void:
	hud = HUDScript.new()
	hud.setup(self, player, level_data)
	add_child(hud)

func _start_music() -> void:
	music = AudioStreamPlayer.new()
	music.bus = &"Music"
	var path := "res://assets/original/audio/%s" % ("boss_final.mp3" if bool(level_data.boss) else "normal.mp3")
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream is AudioStreamMP3:
			stream = stream.duplicate()
			(stream as AudioStreamMP3).loop = true
		music.stream = stream
		add_child(music)
		music.play()

func _begin_level() -> void:
	hud.announce(tr("SECTOR %02d • %s") % [int(level_data.number), tr(str(level_data.name))], 2.2)
	await get_tree().create_timer(2.0).timeout
	if not completed:
		_start_next_wave()

func _start_next_wave() -> void:
	if spawning or completed:
		return
	current_wave += 1
	if current_wave > int(level_data.waves):
		_victory()
		return
	spawning = true
	hud.announce(tr("WAVE %d INBOUND") % current_wave, 1.35)
	var count := int(level_data.base_enemies) + (current_wave - 1) * 2
	count = mini(count, 22)
	var boss_wave := bool(level_data.boss) and current_wave == int(level_data.waves)
	if boss_wave:
		count = maxi(3, int(count * 0.36))
	for i in range(count):
		if completed:
			break
		while alive_enemies >= MAX_ACTIVE_ENEMIES and not completed:
			await get_tree().create_timer(0.18).timeout
		if completed:
			break
		var kind := _choose_enemy_kind(i, boss_wave)
		_spawn_enemy(kind, i > 0 and current_wave >= 3 and i % 7 == 0)
		await get_tree().create_timer(0.2 if boss_wave else 0.34).timeout
	spawning = false
	_check_wave_complete()

func _choose_enemy_kind(index: int, boss_wave: bool) -> String:
	if boss_wave and index == 0:
		return "boss"
	if current_wave >= 2 and index % 5 == 2:
		return "spitter"
	if current_wave >= 3 and index % 7 == 4:
		return "brute"
	return "crawler"

func _spawn_enemy(kind: String, elite: bool) -> void:
	var enemy := EnemyScript.new()
	var health_value := float(level_data.enemy_health) * (1.0 + (current_wave - 1) * 0.12)
	enemy.configure(player, kind, health_value, elite)
	add_child(enemy)
	var spawn_position := _choose_restored_enemy_spawn(kind)
	if spawn_position == Vector3.INF:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(arena_size * 0.72, arena_size * 0.9)
		spawn_position = Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		if spawn_position.distance_to(player.global_position) < 12.0:
			spawn_position = -spawn_position
	enemy.position = spawn_position
	enemy.died.connect(_on_enemy_died)
	enemy.health_reported.connect(_on_enemy_health_reported.bind(enemy))
	alive_enemies += 1
	total_spawned += 1

func _on_enemy_died(_enemy: WarfareEnemy, death_position: Vector3, reward: int, score_value_amount: int) -> void:
	alive_enemies = maxi(0, alive_enemies - 1)
	kills += 1
	score += score_value_amount
	if rng.randf() < 0.72:
		spawn_pickup(death_position + Vector3.UP * 0.4, "credits", reward)
	if rng.randf() < 0.18:
		spawn_pickup(death_position + Vector3(rng.randf_range(-0.7, 0.7), 0.4, rng.randf_range(-0.7, 0.7)), "energy", 22.0)
	elif rng.randf() < 0.14:
		spawn_pickup(death_position + Vector3.UP * 0.4, "ammo", 18.0)
	_check_wave_complete()

func _on_enemy_health_reported(current: float, maximum: float, is_boss: bool, enemy: WarfareEnemy) -> void:
	if is_boss and is_instance_valid(hud) and not enemy.dead:
		hud.report_boss(current, maximum, "ALIEN OVERLORD")

func _check_wave_complete() -> void:
	if spawning or alive_enemies > 0 or completed:
		return
	if current_wave >= int(level_data.waves):
		_victory()
	else:
		hud.announce(tr("WAVE CLEAR"), 1.3)
		await get_tree().create_timer(2.1).timeout
		_start_next_wave()

func _victory() -> void:
	if completed:
		return
	completed = true
	var time_bonus := maxi(0, 7200 - int(elapsed_time * 20.0))
	score += time_bonus
	GameState.complete_level(int(level_data.number), score, battle_credits)
	await get_tree().create_timer(0.75).timeout
	hud.show_result(true, {"score": score, "kills": kills, "credits": battle_credits, "time": elapsed_time})

func _on_player_died() -> void:
	if completed:
		return
	completed = true
	await get_tree().create_timer(1.1).timeout
	hud.show_result(false, {"score": score, "kills": kills, "credits": battle_credits, "time": elapsed_time})

func add_battle_credits(amount: int) -> void:
	battle_credits += maxi(0, amount)

func spawn_pickup(position_value: Vector3, kind: String, amount: float) -> void:
	var pickup := PickupScript.new()
	pickup.configure(kind, amount)
	add_child(pickup)
	pickup.global_position = position_value

func spawn_tracer(from: Vector3, to: Vector3, color: Color, heavy := false) -> void:
	var distance := from.distance_to(to)
	if distance < 0.05:
		return
	var tracer := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025 if not heavy else 0.065
	mesh.bottom_radius = mesh.top_radius
	mesh.height = distance
	mesh.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 4.5
	mesh.material = material
	tracer.mesh = mesh
	effects_root.add_child(tracer)
	tracer.global_position = (from + to) * 0.5
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "scale", Vector3(0.05, 1.0, 0.05), 0.11)
	tween.tween_callback(tracer.queue_free)

func spawn_impact(position_value: Vector3, normal: Vector3, color: Color) -> void:
	var impact := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	impact.mesh = mesh
	impact.position = position_value + normal * 0.03
	effects_root.add_child(impact)
	var tween := impact.create_tween()
	tween.tween_property(impact, "scale", Vector3.ONE * 2.8, 0.12)
	tween.tween_property(impact, "scale", Vector3.ZERO, 0.18)
	tween.tween_callback(impact.queue_free)

func spawn_explosion(position_value: Vector3, color: Color, radius: float, recovered_sound := "") -> void:
	var explosion := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 7
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.78)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 5.0
	mesh.material = material
	explosion.mesh = mesh
	explosion.position = position_value
	effects_root.add_child(explosion)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 7.0
	light.omni_range = maxf(4.0, radius * 1.8)
	explosion.add_child(light)
	var target_scale := Vector3.ONE * maxf(1.6, radius * 2.0)
	var tween := explosion.create_tween()
	tween.set_parallel(true)
	tween.tween_property(explosion, "scale", target_scale, 0.22).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.tween_property(light, "light_energy", 0.0, 0.32)
	tween.chain().tween_callback(explosion.queue_free)
	if not recovered_sound.is_empty():
		AudioDirector.play_3d(recovered_sound, position_value, -1.0, rng.randf_range(0.96, 1.04))
	else:
		AudioDirector.play_3d("gl/grenade_launcher_boom.wav", position_value, -2.0, rng.randf_range(0.92, 1.06))

func _add_static_box(node_name: String, size: Vector3, position_value: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = position_value
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	visual.mesh = mesh
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func _add_visual_box(node_name: String, size: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	visual.mesh = mesh
	visual.position = position_value
	add_child(visual)
	return visual

func _material(color: Color, roughness: float, metallic: float, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 2.1
	return material

func _load_stage_metadata() -> void:
	var level_number := int(level_data.number)
	var metadata_path := "res://assets/models/levels/level_%02d/level.json" % level_number
	if not FileAccess.file_exists(metadata_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary:
		push_warning("Invalid restored level metadata: %s" % metadata_path)
		return
	stage_metadata = parsed
	var markers: Dictionary = stage_metadata.get("markers", {})
	player_spawn_points = _marker_positions(markers.get("Respawn", []))
	enemy_spawn_points = _marker_positions(markers.get("EnemySpawnPoint", []))
	boss_spawn_points = _marker_positions(markers.get("BossSpawnPoint", []))
	waypoint_positions = _marker_positions(markers.get("WayPoint", []))
	waypoint_graph = stage_metadata.get("waypoint_graph", [])
	if enemy_spawn_points.is_empty():
		# Levels 13–21 are the original multiplayer arenas. Their Respawn and
		# FlagSpawn markers are the authored edge spawn locations.
		enemy_spawn_points = _marker_positions(markers.get("FlagSpawn", []))
		if enemy_spawn_points.is_empty():
			enemy_spawn_points = player_spawn_points.duplicate()
	var gameplay_markers: Array[Vector3] = player_spawn_points.duplicate()
	gameplay_markers.append_array(enemy_spawn_points)
	gameplay_markers.append_array(boss_spawn_points)
	for point in gameplay_markers:
		arena_size = maxf(arena_size, Vector2(point.x, point.z).length() + 6.0)

func _marker_positions(records: Variant) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not records is Array:
		return result
	for record in records:
		if not record is Dictionary:
			continue
		var values: Variant = record.get("position", [])
		if values is Array and values.size() >= 3:
			result.append(Vector3(float(values[0]), float(values[1]), float(values[2])))
	return result

func _build_restored_arena() -> bool:
	if stage_metadata.is_empty():
		return false
	var level_number := int(level_data.number)
	var level_root := "res://assets/models/levels/level_%02d" % level_number
	var visual_path := "%s/stage.obj" % level_root
	if not ResourceLoader.exists(visual_path):
		push_warning("Restored level art is missing: %s" % visual_path)
		return false
	var stage_mesh := load(visual_path) as Mesh
	if stage_mesh == null:
		push_warning("Restored level art failed to load: %s" % visual_path)
		return false
	var restored := MeshInstance3D.new()
	restored.name = "OriginalUnityLevel%02d" % level_number
	restored.mesh = stage_mesh
	restored.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(restored)

	var physics_body := StaticBody3D.new()
	physics_body.name = "OriginalUnityColliders"
	physics_body.collision_layer = 1
	physics_body.collision_mask = 0
	add_child(physics_body)
	for record in stage_metadata.get("primitive_colliders", []):
		if record is Dictionary:
			_add_restored_primitive_collider(physics_body, record)
	var collision_file := str(stage_metadata.get("collision_mesh", ""))
	if not collision_file.is_empty():
		var collision_path := "%s/%s" % [level_root, collision_file]
		if ResourceLoader.exists(collision_path):
			var collision_mesh := load(collision_path) as Mesh
			if collision_mesh:
				var collision_shape := CollisionShape3D.new()
				collision_shape.name = "OriginalMeshColliders"
				collision_shape.shape = collision_mesh.create_trimesh_shape()
				if collision_shape.shape:
					physics_body.add_child(collision_shape)
	return true

func _add_restored_primitive_collider(parent: StaticBody3D, record: Dictionary) -> void:
	var transform_values: Variant = record.get("transform", [])
	if not transform_values is Array or transform_values.size() < 16:
		return
	var source_transform := _transform_from_json(transform_values)
	var source_scale := source_transform.basis.get_scale().abs()
	var normalized_basis := source_transform.basis.orthonormalized()
	var collision := CollisionShape3D.new()
	collision.name = str(record.get("name", "Collider"))
	collision.transform = Transform3D(normalized_basis, source_transform.origin)
	var collider_type := str(record.get("type", "box"))
	if collider_type == "box":
		var size := _vector3_from_json(record.get("size", [1.0, 1.0, 1.0]))
		var shape := BoxShape3D.new()
		shape.size = size * source_scale
		collision.shape = shape
	elif collider_type == "sphere":
		var shape := SphereShape3D.new()
		shape.radius = float(record.get("radius", 0.5)) * maxf(source_scale.x, maxf(source_scale.y, source_scale.z))
		collision.shape = shape
	elif collider_type == "capsule":
		var direction := int(record.get("direction", 1))
		var axis_scale := source_scale.y
		var radius_scale := maxf(source_scale.x, source_scale.z)
		var axis_rotation := Basis.IDENTITY
		if direction == 0:
			axis_scale = source_scale.x
			radius_scale = maxf(source_scale.y, source_scale.z)
			axis_rotation = Basis(Vector3.FORWARD, -PI * 0.5)
		elif direction == 2:
			axis_scale = source_scale.z
			radius_scale = maxf(source_scale.x, source_scale.y)
			axis_rotation = Basis(Vector3.RIGHT, PI * 0.5)
		collision.transform.basis = normalized_basis * axis_rotation
		var shape := CapsuleShape3D.new()
		shape.radius = float(record.get("radius", 0.5)) * radius_scale
		shape.height = maxf(shape.radius * 2.0, float(record.get("height", 2.0)) * axis_scale)
		collision.shape = shape
	if collision.shape:
		parent.add_child(collision)

func _transform_from_json(values: Array) -> Transform3D:
	var basis := Basis(
		Vector3(float(values[0]), float(values[4]), float(values[8])),
		Vector3(float(values[1]), float(values[5]), float(values[9])),
		Vector3(float(values[2]), float(values[6]), float(values[10]))
	)
	return Transform3D(basis, Vector3(float(values[3]), float(values[7]), float(values[11])))

func _vector3_from_json(values: Variant) -> Vector3:
	if values is Array and values.size() >= 3:
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ONE

func _color_from_json(values: Variant) -> Color:
	if values is Array and values.size() >= 3:
		return Color(float(values[0]), float(values[1]), float(values[2]), float(values[3]) if values.size() > 3 else 1.0)
	return Color.WHITE

func _choose_restored_enemy_spawn(kind: String) -> Vector3:
	var candidates := boss_spawn_points if kind == "boss" and not boss_spawn_points.is_empty() else enemy_spawn_points
	if candidates.is_empty():
		return Vector3.INF
	var start_index := rng.randi_range(0, candidates.size() - 1)
	var best := candidates[start_index]
	var best_distance := best.distance_to(player.global_position)
	for offset in range(candidates.size()):
		var candidate := candidates[(start_index + offset) % candidates.size()]
		var distance := candidate.distance_to(player.global_position)
		if distance >= 12.0:
			return candidate + Vector3.UP * 0.05
		if distance > best_distance:
			best = candidate
			best_distance = distance
	return best + Vector3.UP * 0.05

func get_enemy_navigation_target(from: Vector3, destination: Vector3) -> Vector3:
	if waypoint_positions.is_empty() or waypoint_graph.size() != waypoint_positions.size():
		return destination
	if _has_clear_static_path(from, destination):
		return destination
	var start_index := _nearest_visible_waypoint(from)
	var goal_index := _nearest_visible_waypoint(destination)
	if start_index < 0 or goal_index < 0:
		return destination
	if start_index == goal_index:
		return waypoint_positions[goal_index]
	var next_index := _next_waypoint_astar(start_index, goal_index)
	return waypoint_positions[next_index] if next_index >= 0 else destination

func _has_clear_static_path(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * 0.75,
		to + Vector3.UP * 0.75,
		1
	)
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _nearest_visible_waypoint(origin: Vector3) -> int:
	var best_index := -1
	var best_distance := INF
	for index in range(waypoint_positions.size()):
		var distance := origin.distance_squared_to(waypoint_positions[index])
		if distance >= best_distance:
			continue
		if _has_clear_static_path(origin, waypoint_positions[index]):
			best_index = index
			best_distance = distance
	return best_index

func _next_waypoint_astar(start_index: int, goal_index: int) -> int:
	var count := waypoint_positions.size()
	var open: Array[int] = [start_index]
	var closed: Array[bool] = []
	var came_from: Array[int] = []
	var costs: Array[float] = []
	closed.resize(count)
	came_from.resize(count)
	costs.resize(count)
	closed.fill(false)
	came_from.fill(-1)
	costs.fill(INF)
	costs[start_index] = 0.0
	while not open.is_empty():
		var current_slot := 0
		var current := open[0]
		var current_score := costs[current] + waypoint_positions[current].distance_to(waypoint_positions[goal_index])
		for slot in range(1, open.size()):
			var candidate := open[slot]
			var score := costs[candidate] + waypoint_positions[candidate].distance_to(waypoint_positions[goal_index])
			if score < current_score:
				current = candidate
				current_slot = slot
				current_score = score
		open.remove_at(current_slot)
		if current == goal_index:
			var step := goal_index
			while came_from[step] >= 0 and came_from[step] != start_index:
				step = came_from[step]
			return step
		closed[current] = true
		var neighbours: Variant = waypoint_graph[current]
		if not neighbours is Array:
			continue
		for neighbour_value in neighbours:
			var neighbour := int(neighbour_value)
			if neighbour < 0 or neighbour >= count or closed[neighbour]:
				continue
			var tentative := costs[current] + waypoint_positions[current].distance_to(waypoint_positions[neighbour])
			if tentative >= costs[neighbour]:
				continue
			came_from[neighbour] = current
			costs[neighbour] = tentative
			if not open.has(neighbour):
				open.append(neighbour)
	return -1
