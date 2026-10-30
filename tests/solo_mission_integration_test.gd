extends Node

var failures: Array[String] = []
var spawn_cases := 0

class SpawnWorld extends WarfareGameWorld:
	func _begin_level() -> void:
		pass
	func _start_music() -> void:
		# This rapid map-loading fixture checks spawning, not music playback.
		pass


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	GameState.selected_level = 1
	GameState.selected_substage = 0
	GameState.selected_game_mode = "singleplayer"
	GameState.credits = 0
	GameState.experience = 0
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.solo_completed.clear()
	GameState.solo_stage_bonuses.clear()
	GameState.settled_runs.clear()
	var world := WarfareGameWorld.new()
	add_child(world)
	world.player.set_physics_process(false)
	await get_tree().create_timer(2.1).timeout
	check(is_instance_valid(world.mission_director), "Original solo did not create its mission director")
	if is_instance_valid(world.mission_director):
		world.mission_director.set_process(false)
		world.set_process(false)
		for tick in 500:
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.get_parent() == world and not enemy.dead:
					# Finish the authored emergence before attacking. Source enemies
					# correctly ignore hits while still below the ground.
					enemy._physics_process(1.0)
					enemy.set_physics_process(false)
					enemy.take_damage(10000000.0, enemy.global_position, world.player)
			world.progress.advance(0.1)
			world.mission_director.tick(1.0)
			if world.completed:
				break
			await get_tree().physics_frame
		check(not world.mission_director.failed, "Original mission aborted on a spawn")
		check(world.total_spawned == 35 and world.kills == 35, "First source mission must spawn/resolve 35 enemies")
		check(world.current_wave == 11, "First source mission must traverse 11 source groups")
		check(world.completed and bool(world.settled_stats.get("saved", false)), "Original mission did not settle victory")
		check(GameState.credits == world.battle_credits and GameState.experience == world.battle_experience, "Live mission cash/XP did not match settlement")
		check(GameState.is_solo_mission_unlocked(1, 1), "Live mission completion did not unlock its successor")
	world.completed = true
	for audio: AudioStreamPlayer3D in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	# Let the audio thread release stopped enemy streams before engine shutdown.
	await get_tree().create_timer(0.2, true).timeout
	get_tree().paused = false
	await _check_campaign_spawns()
	if failures.is_empty():
		print("SOLO_MISSION_INTEGRATION_TEST_PASS source_enemies=35 groups=11 maps=8 spawn_cases=%d live_rewards=unlock=PASS" % spawn_cases)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_campaign_spawns() -> void:
	# Validate each distinct monster + entrance used by all six authored tables
	# against the actual map collisions and recovered models, without replaying
	# thousands of duplicate schedule entries already covered by the data tests.
	for level in range(1, 9):
		GameState.selected_level = level
		GameState.selected_substage = 0
		var world := SpawnWorld.new()
		add_child(world)
		world.set_process(false)
		world.player.set_physics_process(false)
		await get_tree().physics_frame
		var cases := {}
		for mission: Dictionary in SoloMissions.get_missions(level):
			for row: Array in mission.rows:
				for group in 3:
					if int(row[2 + group * 2]) > 0:
						cases["%d:%d" % [row[1 + group * 2], row[7]]] = {"monster_id": int(row[1 + group * 2]), "spawn_from": int(row[7]), "difficulty": int(mission.base_difficulty)}
		for request: Dictionary in cases.values():
			var context := "map=%d monster=%d from=%d" % [level, request.monster_id, request.spawn_from]
			check(world.spawn_mission_enemy(request), "Authored spawn failed: " + context)
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.get_parent() == world:
					check(enemy.recovered_enemy and enemy.configuration_error.is_empty(), "Missing source model: " + context)
					check((enemy.spawn_left > 0.0) == (int(request.spawn_from) == 1), "Wrong grave/door emergence: " + context)
					check(enemy.position.is_finite(), "Invalid spawn coordinates: " + context)
					for audio: AudioStreamPlayer3D in enemy.find_children("*", "AudioStreamPlayer3D", true, false):
						audio.stop()
					enemy.free()
			world.alive_enemies = 0
			spawn_cases += 1
		world.completed = true
		world.free()
		AudioDirector.stop_all_sfx()
		await get_tree().create_timer(0.2).timeout
