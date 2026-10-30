extends Node

# Exercise the actual GameWorld resource-directory loader without starting a
# mission, saving progress, spawning enemies, or altering the user's equipment.
class ArenaProbe extends "res://scripts/game/game_world.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


const MaterialRestorer = preload("res://scripts/core/unity_material_restorer.gd")
const ColliderBuilder = preload("res://scripts/core/unity_collider_builder.gd")
const OUTPUT := "res://test_output/boss_arenas"
var failures: Array[String] = []
var checks := 0
var capture := false
var results: Array[Dictionary] = []


func _ready() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("BOSS ARENA: " + message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for number in range(1, 7):
		await _check_arena(number)
	var destination := OUTPUT.path_join("capture.json" if capture else "validation.json")
	var file := FileAccess.open(destination, FileAccess.WRITE)
	_check(file != null, "Could not write validation report")
	var report := {"checks": checks, "failures": failures, "arenas": results,
		"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"capture": capture, "viewport": [1280, 720], "quality": GameState.settings.get("quality", "high")}
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("BOSS ARENAS %s: %d checks, %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_arena(number: int) -> void:
	var label := "Boss%d" % number
	var directory := "res://assets/models/boss_arenas/boss_%02d" % number
	var world := ArenaProbe.new()
	world.level_data = {"number": number, "boss": true, "resource_directory": directory}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if capture else SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(world)
	world._load_stage_metadata()
	var metadata: Dictionary = world.stage_metadata
	_check(not metadata.is_empty(), label + " GameWorld metadata load")
	_check(metadata.get("format", 0) == 3, label + " format 3")
	_check(metadata.get("warnings", ["missing"]).is_empty(), label + " no exporter warnings")
	_check(world.player_spawn_points.size() == 3, label + " source player spawns")
	_check(world.boss_spawn_points.size() == (2 if number == 4 else 1), label + " source boss spawns")
	_check(world._build_restored_arena(), label + " GameWorld arena build")
	var stage := world.get_node_or_null("OriginalUnityLevel%02d" % number) as MeshInstance3D
	var body := world.get_node_or_null("OriginalUnityColliders") as StaticBody3D
	_check(stage != null and stage.mesh != null, label + " GLB visual mesh")
	_check(body != null and body.get_child_count() > 0, label + " collision shapes")
	if stage == null or stage.mesh == null or body == null:
		viewport.free()
		return
	var reference := load(directory.path_join("stage.obj")) as Mesh
	_check(reference != null, label + " OBJ compatibility")
	if reference != null:
		_check(stage.mesh.get_aabb().position.distance_to(reference.get_aabb().position) < 0.02, label + " GLB/OBJ minimum bounds")
		_check(stage.mesh.get_aabb().size.distance_to(reference.get_aabb().size) < 0.02, label + " GLB/OBJ size parity")
		_check(stage.mesh.get_faces().size() == reference.get_faces().size(), label + " GLB/OBJ triangle count")
	var states: Dictionary = metadata.get("material_render_modes", {})
	var lightmapped := 0
	for surface in stage.mesh.get_surface_count():
		var source := stage.mesh.surface_get_material(surface) as StandardMaterial3D
		var restored := stage.get_surface_override_material(surface)
		_check(source != null and source.albedo_texture != null, label + " source material texture %d" % surface)
		_check(restored != null, label + " material override %d" % surface)
		if source == null:
			continue
		_check(states.has(source.resource_name), label + " material state " + source.resource_name)
		var state: Dictionary = states.get(source.resource_name, {})
		if state.has("lightmap_texture"):
			lightmapped += 1
			var arrays := stage.mesh.surface_get_arrays(surface)
			_check(arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() == arrays[Mesh.ARRAY_VERTEX].size(), label + " source UV2 %d" % surface)
			_check(restored is ShaderMaterial, label + " lightmap shader %d" % surface)
			if restored is ShaderMaterial:
				var texture: Texture2D = restored.get_shader_parameter("lightmap_texture")
				_check(texture != null and texture.resource_path == state.lightmap_texture, label + " lightmap binding %d" % surface)
				_check(is_equal_approx(float(restored.get_shader_parameter("lightmap_multiplier")), float(state.lightmap_multiplier)), label + " source lightmap multiplier %d" % surface)
	var expected_shapes := 0
	for record: Dictionary in metadata.get("primitive_colliders", []):
		if not str(record.name).to_lower().begins_with("pathfinding"):
			expected_shapes += 1
	if not str(metadata.get("collision_mesh", "")).is_empty():
		expected_shapes += 1
	_check(body.get_child_count() == expected_shapes, label + " all source collider shapes built")
	for child in body.get_children():
		_check(child is CollisionShape3D and child.shape != null, label + " valid collider " + child.name)
	for _frame in 3:
		await get_tree().physics_frame
	var ground_hits: Array[Dictionary] = []
	for tag: String in ["PlayerSpawnInBoss", "BossSpawnPoint"]:
		var records: Array = metadata.get("markers", {}).get(tag, [])
		for index in records.size():
			var point := ColliderBuilder.vector3_from_json(records[index].position)
			var snapped := world._snap_enemy_spawn_to_ground(point)
			_check(snapped != Vector3.INF, "%s %s[%d] ray hits restored floor" % [label, tag, index])
			if snapped == Vector3.INF:
				continue
			_check(absf(snapped.x - point.x) < 0.001 and absf(snapped.z - point.z) < 0.001, label + " ground snap retains source XZ")
			ground_hits.append({"tag": tag, "index": index, "source": [point.x, point.y, point.z], "ground": [snapped.x, snapped.y - 0.02, snapped.z]})
			if tag == "PlayerSpawnInBoss":
				await _check_player_stands(world, snapped, label + " player %d" % index)
	var result := {"boss": number, "surfaces": stage.mesh.get_surface_count(), "triangles": stage.mesh.get_faces().size() / 3,
		"lightmapped_surfaces": lightmapped, "collision_shapes": body.get_child_count(), "spawn_floor_hits": ground_hits}
	if capture:
		await _capture_arena(world, viewport, number)
		result["image"] = "boss_%02d.png" % number
	results.append(result)
	print("BOSS ARENA CHECK: " + JSON.stringify(result))
	# Avoid dummy-renderer teardown warnings for per-surface overrides.
	stage.mesh = null
	viewport.free()
	await get_tree().process_frame


func _check_player_stands(world: Node3D, point: Vector3, label: String) -> void:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	body.add_child(collision)
	world.add_child(body)
	body.global_position = point + Vector3.UP * 0.05
	for _frame in 12:
		await get_tree().physics_frame
		body.velocity = Vector3.DOWN * 3.0
		body.move_and_slide()
	_check(body.is_on_floor(), label + " CharacterBody stands on source collision")
	_check(body.global_position.y > point.y - 0.2, label + " does not fall through floor")
	body.free()


func _capture_arena(world: Node3D, viewport: SubViewport, number: int) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.03, 0.045)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var ambient: Array = world.stage_metadata.render_settings.ambient_color
	environment.environment.ambient_light_color = Color(ambient[0], ambient[1], ambient[2])
	environment.environment.ambient_light_energy = 1.0
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	# Use the authored spawn region, not the enormous decorative sky bounds.
	var center := Vector3.ZERO
	var points: Array[Vector3] = world.player_spawn_points.duplicate()
	points.append_array(world.boss_spawn_points)
	for point: Vector3 in points:
		center += point
	center /= float(points.size())
	center.y = 0.0
	camera.position = center + Vector3(0, 38, -43)
	camera.fov = 65.0
	camera.far = 1500.0
	camera.look_at(center + Vector3(0, 0, 4))
	camera.make_current()
	for _frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := viewport.get_texture().get_image()
	_check(shot != null and not shot.is_empty(), "Boss%d rendered capture" % number)
	if shot != null:
		_check(shot.save_png(OUTPUT.path_join("boss_%02d.png" % number)) == OK, "Boss%d capture saved" % number)
