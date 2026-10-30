extends Node

const Missions = preload("res://scripts/core/solo_missions.gd")
const Director = preload("res://scripts/game/mission_director.gd")
var failures: Array[String] = []
var checks := 0

class FakeWorld extends Node:
	var alive_enemies := 0
	var completed := false
	var requests: Array[Dictionary] = []
	var reject := false
	var peak_alive := 0
	func spawn_mission_enemy(request: Dictionary) -> bool:
		if reject:
			return false
		requests.append(request.duplicate(true))
		alive_enemies += 1
		peak_alive = maxi(peak_alive, alive_enemies)
		return true


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("SOLO MISSIONS: " + message)


func _run() -> void:
	_check(GameState.save_path != GameState.SAVE_PATH, "run with --test-profile=solo_modules before autoload reads")
	_test_catalog()
	_test_progress()
	_test_timing_capacity_completion()
	_test_pause_failure()
	_test_endless_and_elites()
	await _test_process()
	print("SOLO_MISSIONS_TEST_PASS checks=%d" % checks if failures.is_empty() else "SOLO_MISSIONS_TEST_FAIL: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_catalog() -> void:
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/data/recovered_data_v1/tables.json"))
	for level in range(1, 9):
		_check(Missions.get_missions(level).size() == 6, "missing substage menu entries")
		for substage in 6:
			var mission := Missions.get_mission(level, substage)
			var table_id := 19 + (level - 1) * 6 + substage
			var expected_rows: Array = audit.tables[table_id].data
			# Godot JSON decodes every number as float; Array equality preserves types.
			# Reject fractional source values before normalizing this test fixture.
			for row: Array in expected_rows:
				for column in row.size():
					_check(float(row[column]) == floorf(float(row[column])), "fractional source table value")
					row[column] = int(row[column])
			_check(mission.table_id == table_id and mission.rows == expected_rows, "runtime differs from source table %d" % table_id)
			_check(Missions.get_by_id(mission.id) == mission, "mission ID does not round trip")
	var first := Missions.get_mission(1, 0)
	_check(first.round_count == 11 and first.total_enemies == 35, "first substage is not the original 35-enemy schedule")
	first.rows[0][2] = 999
	_check(Missions.get_mission(1, 0).rows[0][2] == 4, "caller mutated shared catalog data")
	for id: String in ["", "1", "01:0", "1:6", "0:0", "9:0", "1:-1", "1:0:1"]:
		_check(Missions.get_by_id(id).is_empty() and not Missions.is_unlocked(id, {}), "invalid mission accepted: " + id)
	_check(Missions.get_mission(8, 4).base_difficulty == 23, "campaign difficulty index differs")
	var survival := Missions.get_mission(8, 5)
	_check(Missions.difficulty_for_round(survival, 12) == 21 and Missions.difficulty_for_round(survival, 13) == 22, "survival difficulty threshold differs")
	_check(Missions.difficulty_for_round(Missions.get_mission(1, 4), 100) == 2, "finite mission difficulty rose per wave")


func _test_progress() -> void:
	var completed: Dictionary = {}
	var bonuses: Dictionary = {}
	_check(Missions.is_unlocked("1:0", completed) and Missions.is_unlocked("1:5", completed), "fresh player needs first mission and first survival")
	_check(not Missions.is_unlocked("2:0", completed) and not Missions.is_unlocked("1:1", completed), "fresh player skipped progress")
	var total_bonus := 0
	for level in range(1, 9):
		_check(Missions.is_unlocked("%d:5" % level, completed), "survival not opened with map")
		for substage in 5:
			var id := Missions.mission_id(level, substage)
			_check(Missions.is_unlocked(id, completed), "sequential mission remains locked: " + id)
			var snapshot := completed.duplicate(true)
			var clear := Missions.complete(id, completed, bonuses)
			_check(completed == snapshot, "completion mutated caller state before save transaction")
			_check(clear.valid and clear.first_clear, "first completion rejected")
			_check(int(clear.bonus) == (Missions.stage_bonus(level) if substage == 4 else 0), "bonus paid on wrong substage")
			completed = clear.completed_ids
			bonuses = clear.stage_bonuses
			total_bonus += int(clear.bonus)
			var replay := Missions.complete(id, completed, bonuses)
			_check(not replay.first_clear and replay.bonus == 0, "replay awarded another first-clear bonus")
	_check(total_bonus == 1970000 and bonuses.size() == 8 and completed.size() == 40, "campaign payout or completion count differs")
	_check(Missions.next_mission_id("1:4") == "2:0" and Missions.next_mission_id("8:4") == "1:0", "map transition differs from source")
	var endless_clear := Missions.complete("1:5", {}, {})
	_check(not endless_clear.valid and endless_clear.bonus == 0 and endless_clear.completed_ids.is_empty(), "survival incorrectly unlocks campaign")
	_check(Missions.complete("1:4", {}, {"1": true}).bonus == 0, "persisted stage bonus was paid again")


func _fixture(rows: Array, endless := false, substage := 0) -> Dictionary:
	return {"id": "test", "level_number": 1, "substage": substage,
		"base_difficulty": 0, "endless": endless, "rows": rows}


func _test_timing_capacity_completion() -> void:
	var world := FakeWorld.new()
	var director := Director.new()
	var completions: Array[Dictionary] = []
	director.mission_completed.connect(func(mission: Dictionary): completions.append(mission))
	_check(director.configure(world, _fixture([[2, 0, 9, 0, 0, 0, 0, 0], [1, 2, 1, 0, 0, 0, 0, 1]])), "valid fixture refused")
	director.tick(1.9)
	_check(world.requests.is_empty(), "first spawn ignored intermission")
	director.tick(0.1)
	_check(world.requests.size() == 1, "first spawn did not occur at intermission")
	director.tick(0.49)
	_check(world.requests.size() == 1, "members spawned faster than 0.5 seconds")
	director.tick(0.01)
	for index in 6:
		director.tick(0.5)
	_check(world.requests.size() == 8, "wrong simultaneous spawn limit")
	director.tick(100.0)
	_check(world.requests.size() == 8, "full arena exceeded source cap")
	world.alive_enemies -= 1
	director.tick(0.49)
	_check(world.requests.size() == 8, "capacity wait banked spawn delay")
	director.tick(0.01)
	_check(world.requests.size() == 8, "capacity poll consumed the member interval")
	director.tick(0.49)
	_check(world.requests.size() == 8, "member spawned before the post-capacity interval")
	director.tick(0.01)
	world.alive_enemies -= 1
	director.tick(0.99)
	_check(world.requests.size() == 9, "next row ignored its delay")
	director.tick(0.01)
	_check(world.requests.size() == 10 and world.requests[-1].spawn_from == 1, "next row incorrectly waited for arena clear or lost Grave flag")
	_check(world.peak_alive == 8 and world.requests[-1].round_index == 1, "source scheduling metadata differs")
	director.tick(1.0)
	_check(completions.is_empty(), "mission completed while enemies remained")
	world.alive_enemies = 0
	director.tick(0.0)
	_check(completions.is_empty(), "completion delay started before the last enemy died")
	director.tick(0.99)
	_check(completions.is_empty(), "victory skipped its post-clear delay")
	director.tick(0.01)
	_check(completions.size() == 1, "post-clear delay did not finish at one second")
	director.tick(100.0)
	_check(completions.size() == 1 and director.finished, "completion was lost or emitted twice")
	director.free()
	world.free()


func _test_pause_failure() -> void:
	var world := FakeWorld.new()
	var director := Director.new()
	var errors: Array[String] = []
	director.mission_failed.connect(func(reason: String): errors.append(reason))
	director.configure(world, _fixture([[1, 0, 1, 0, 0, 0, 0, 0]]))
	director.tick(0.5)
	director.set_running(false)
	director.tick(100.0)
	_check(world.requests.is_empty(), "revival pause did not freeze mission")
	director.set_running(true)
	director.tick(0.5)
	_check(world.requests.size() == 1, "resume lost remaining delay")
	world.completed = true
	world.alive_enemies = 0
	director.tick(10.0)
	_check(not director.finished and not director.get_progress().running, "world defeat became mission victory")
	world.completed = false
	world.reject = true
	director.configure(world, _fixture([[1, 1, 1, 0, 0, 0, 0, 0]]))
	director.tick(1.0)
	director.tick(100.0)
	_check(director.failed and not director.finished and director.spawned == 0 and errors.size() == 1, "rejected source enemy was skipped or retried as success")
	_check(not director.configure(world, _fixture([[1, 0, -1, 0, 0, 0, 0, 0]])), "negative enemy count accepted")
	_check(not director.configure(world, _fixture([[1, 0, 0, 0, 0, 0, 0, 0]])), "empty mission can award victory")
	director.free()
	world.free()


func _test_endless_and_elites() -> void:
	var world := FakeWorld.new()
	var director := Director.new()
	var survival := Missions.get_mission(1, 5)
	director.rng.seed = 731
	director.configure(world, survival)
	for index in int(survival.total_enemies) * 2 + 1:
		world.alive_enemies = 0
		director.tick(100.0)
	_check(not director.finished and director.cycle_index == 2, "survival ended instead of looping source table")
	_check(world.requests[-1].round_index == 102 and world.requests[-1].difficulty == 7, "survival reset its round/difficulty at table loop")
	var elite_seen := false
	for request: Dictionary in world.requests:
		_check(int(request.difficulty) == int(request.round_index) / 13, "wrong survival difficulty")
		if int(request.monster_id) in [3, 4]:
			_check(not request.elite, "Boomer/Tank became elite")
		elite_seen = elite_seen or bool(request.elite)
	_check(elite_seen, "seeded eligible later mission never generated an elite")
	world.requests.clear()
	world.alive_enemies = 0
	director.configure(world, _fixture([[0, 0, 100, 3, 50, 4, 50, 0]], false, 2))
	for index in 200:
		world.alive_enemies = 0
		director.tick(100.0)
	for request: Dictionary in world.requests:
		_check(not request.elite, "introductory substages generated an elite")
	director.free()
	world.free()


func _test_process() -> void:
	var world := FakeWorld.new()
	add_child(world)
	var director := Director.new()
	world.add_child(director)
	director.configure(world, _fixture([[0, 0, 1, 0, 0, 0, 0, 0]]))
	# Leave only a fraction of a frame for the actual Node _process callback.
	director.tick(0.49999)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(world.requests.size() == 1, "SceneTree did not drive the director")
	world.free()
