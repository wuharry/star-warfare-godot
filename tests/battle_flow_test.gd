extends Node

var failures: Array[String] = []

class QuietPlayer extends WarfarePlayer:
	func _ready() -> void:
		set_physics_process(false)

class QuietHUD extends WarfareHUD:
	var reported_stats: Dictionary = {}
	func _ready() -> void:
		set_process(false)
	func announce(_message: String, _duration := 2.0) -> void:
		pass
	func show_result(_won: bool, stats: Dictionary) -> void:
		reported_stats = stats

class QuietExpanse extends WarfareExpanseWorld:
	func _ready() -> void:
		set_process(false)

class QuietWorld extends WarfareGameWorld:
	var starts := 0
	func _ready() -> void:
		set_process(false)
	func _start_next_wave() -> void:
		starts += 1
		current_wave += 1
		alive_enemies = 1


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var world := QuietWorld.new()
	world.level_data = {"number": 1, "waves": 5, "pvp": false}
	add_child(world)
	world.player = QuietPlayer.new()
	world.add_child(world.player)
	world.hud = QuietHUD.new()
	world.add_child(world.hud)
	world.current_wave = 1
	world._check_wave_complete()
	check(world.wave_pending, "Clear wave did not reserve its pending transition")
	world.player.dead = true
	world.player.dead = false
	world._on_player_revived()
	world._check_wave_complete()
	await get_tree().create_timer(2.2).timeout
	check(world.starts == 1 and world.current_wave == 2, "Revival during intermission scheduled a duplicate wave")
	world.alive_enemies = 0
	world._check_wave_complete()
	world.player.dead = true
	await get_tree().create_timer(2.2).timeout
	check(world.starts == 1 and not world.wave_pending, "Pending wave advanced while the player was dead")
	world.player.dead = false
	world._on_player_revived()
	await get_tree().create_timer(2.2).timeout
	check(world.starts == 2 and world.current_wave == 3, "Wave did not resume exactly once after revival")
	world.alive_enemies = 0
	world._check_wave_complete()
	world.completed = true
	await get_tree().create_timer(2.2).timeout
	check(world.starts == 2, "Queued transition started after the match finished")
	world.free()
	_test_settlement_retry()
	if failures.is_empty():
		print("BATTLE_FLOW_TEST_PASS intermission_revival=dead_wait=finished_wait=career_rollback=expanse_exit=PASS")
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_settlement_retry() -> void:
	var save_path: String = GameState.save_path
	GameState.career.load_data({})
	GameState.settled_runs.clear()
	GameState.credits = 0
	GameState.experience = 0
	GameState.selected_level = 1
	GameState.selected_substage = 4
	GameState.selected_game_mode = "singleplayer"
	GameState.solo_completed.clear()
	GameState.solo_stage_bonuses.clear()
	var world := QuietWorld.new()
	world.level_data = {"number": 1}
	world.run_id = "career_transaction"
	world.battle_credits = 20
	world.progress.start(GameState.career, {"source_stage": 1, "source_substage": 4})
	add_child(world)
	var before: Dictionary = GameState.career.serialize()
	GameState.save_path = "user://missing_battle_flow_directory/save.json"
	check(not world._settle_battle(true).saved, "Failed source run save was accepted")
	check(GameState.career.serialize() == before, "Failed run kept career win/chapter changes")
	check(not world.pending_career.is_empty(), "Failed run lost its pending career changes")
	var expected: Dictionary = world.pending_career.duplicate(true)
	GameState.save_path = save_path
	check(world._settle_battle(true).saved, "Retry did not persist the run")
	check(GameState.career.serialize() == expected, "Retry lost or duplicated career changes")
	var banked: int = GameState.credits
	world._settle_battle(true)
	check(GameState.credits == banked and GameState.career.serialize() == expected, "Repeated result paid or counted twice")
	world.free()

	var expanse := QuietExpanse.new()
	expanse.level_data = {"number": 22}
	expanse.run_id = "expanse_exit_transaction"
	expanse.battle_credits = 50
	expanse.progress.start(GameState.career)
	add_child(expanse)
	var ui := QuietHUD.new()
	ui.world = expanse
	ui.pause_overlay = Control.new()
	ui.add_child(ui.pause_overlay)
	add_child(ui)
	GameState.save_path = "user://missing_battle_flow_directory/save.json"
	check(not ui._prepare_leave(), "Expanse was allowed to leave with unsaved earnings")
	check(not expanse.banked and not ui.reported_stats.get("saved", true), "Failed exit did not retain a retry result")
	check(GameState.credits == banked and is_instance_valid(expanse), "Failed exit lost its world or kept unsaved money")
	GameState.save_path = save_path
	check(ui._prepare_leave() and expanse.banked, "Expanse could not leave after a successful retry")
	check(GameState.credits == banked + 50, "Expanse retry did not bank exactly once")
	ui.free()
	expanse.free()
	check(GameState.credits == banked + 50, "Exit-tree fallback duplicated the bank")
