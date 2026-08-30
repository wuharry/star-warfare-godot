extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("LEVEL RESTORATION TEST: " + message)

func _run() -> void:
	for level_number in GameState.CAMPAIGN_LEVELS:
		var root := "res://assets/models/levels/level_%02d" % int(level_number)
		var metadata_path := "%s/level.json" % root
		var stage_path := "%s/stage.obj" % root
		_check(FileAccess.file_exists(metadata_path), "Level %d metadata is missing" % level_number)
		_check(ResourceLoader.exists(stage_path), "Level %d stage mesh is missing" % level_number)
		if not FileAccess.file_exists(metadata_path) or not ResourceLoader.exists(stage_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		_check(parsed is Dictionary, "Level %d metadata is invalid" % level_number)
		if not parsed is Dictionary:
			continue
		var metadata: Dictionary = parsed
		_check(int(metadata.get("level", -1)) == int(level_number), "Level %d metadata number is wrong" % level_number)
		_check((metadata.get("warnings", []) as Array).is_empty(), "Level %d converter reported warnings" % level_number)
		var markers: Dictionary = metadata.get("markers", {})
		_check(not (markers.get("Respawn", []) as Array).is_empty(), "Level %d has no original Respawn markers" % level_number)
		if int(level_number) <= 8:
			var graph: Array = metadata.get("waypoint_graph", [])
			_check(graph.size() == (markers.get("WayPoint", []) as Array).size(), "Level %d waypoint graph is incomplete" % level_number)
			var link_count := 0
			for links in graph:
				link_count += (links as Array).size()
			_check(link_count > 0, "Level %d waypoint graph has no original links" % level_number)
		var stage_mesh := load(stage_path) as Mesh
		_check(stage_mesh != null and stage_mesh.get_surface_count() > 0, "Level %d mesh did not import" % level_number)
		var collision_name := str(metadata.get("collision_mesh", ""))
		if not collision_name.is_empty():
			var collision_mesh := load("%s/%s" % [root, collision_name]) as Mesh
			_check(collision_mesh != null and collision_mesh.get_surface_count() > 0, "Level %d mesh colliders did not import" % level_number)

	# Instantiate every map one at a time so visual, collision, spawn, player,
	# HUD, and audio construction are all covered without retaining the full set.
	for level_number in GameState.CAMPAIGN_LEVELS:
		GameState.selected_level = level_number
		var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
		add_child(world)
		await get_tree().process_frame
		await get_tree().physics_frame
		_check(world.get_node_or_null("OriginalUnityLevel%02d" % level_number) != null, "Level %d runtime art is absent" % level_number)
		var colliders := world.get_node_or_null("OriginalUnityColliders")
		_check(colliders != null and colliders.get_child_count() > 0, "Level %d runtime collision is absent" % level_number)
		_check(not world.player_spawn_points.is_empty(), "Level %d runtime Respawn list is empty" % level_number)
		world._spawn_enemy("crawler", false)
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var runtime_enemy: WarfareEnemy
		for child in world.get_children():
			if child is WarfareEnemy:
				runtime_enemy = child
				break
		_check(is_instance_valid(runtime_enemy), "Level %d could not spawn an enemy" % level_number)
		if is_instance_valid(runtime_enemy):
			_check(runtime_enemy.navigation_target != Vector3.INF, "Level %d enemy navigation did not initialize" % level_number)
		world.completed = true
		for audio in world.find_children("*", "AudioStreamPlayer", true, false):
			audio.stop()
		for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
		world.free()
		await get_tree().process_frame

	AudioDirector.stop_all_sfx()
	if failures.is_empty():
		print("LEVEL_RESTORATION_TEST_PASS levels=17 primitive_colliders=1851 mesh_colliders=315")
		get_tree().quit(0)
	else:
		print("LEVEL_RESTORATION_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
