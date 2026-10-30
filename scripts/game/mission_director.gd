class_name MissionDirector
extends Node
## EnemySpawnScript.cs:243-395. Each row is a timed group, not a clear-all wave.
## World contract: alive_enemies:int, completed:bool,
## spawn_mission_enemy(request:Dictionary)->bool (increments alive_enemies on success).
## Connect mission_completed to the world's victory path; pause during revival.

signal round_started(round_index: int, difficulty: int)
signal mission_completed(mission: Dictionary)
signal mission_failed(reason: String)

const Missions = preload("res://scripts/core/solo_missions.gd")
const MAX_ALIVE := 8
const MEMBER_INTERVAL := 0.5
const FINISH_DELAY := 1.0

var rng := RandomNumberGenerator.new()
var mission: Dictionary = {}
var configuration_error := ""
var finished := false
var failed := false
var spawned := 0
var round_index := -1
var cycle_index := 0

var _world: Node
var _entries: Array[Dictionary] = []
var _entry_index := 0
var _running := false
var _waiting_for_slot := true
var _slot_retry_left := 0.0
var _delay_left := 0.0
var _draining := false
var _finish_delay_started := false


func _init() -> void:
	set_process(false)


func configure(world: Node, mission_data: Dictionary) -> bool:
	stop()
	_world = world
	mission = mission_data.duplicate(true)
	_entries.clear()
	_entry_index = 0
	spawned = 0
	round_index = -1
	cycle_index = 0
	finished = false
	failed = false
	_draining = false
	_finish_delay_started = false
	_waiting_for_slot = true
	_slot_retry_left = 0.0
	_delay_left = 0.0
	configuration_error = ""
	if not is_instance_valid(world) or not world.has_method("spawn_mission_enemy"):
		return _fail("World must implement spawn_mission_enemy(request) -> bool")
	if not world.get("alive_enemies") is int or not world.get("completed") is bool:
		return _fail("World must expose alive_enemies:int and completed:bool")
	var rows: Variant = mission.get("rows")
	if not rows is Array or rows.is_empty() or not mission.get("endless") is bool:
		return _fail("Mission requires nonempty rows and endless:bool")
	if not mission.get("base_difficulty") is int or int(mission.base_difficulty) < 0:
		return _fail("Mission requires a nonnegative base_difficulty:int")
	for row_id in rows.size():
		var row: Variant = rows[row_id]
		if not row is Array or row.size() != 8:
			return _fail("Invalid row %d: expected eight integer columns" % row_id)
		for value: Variant in row:
			if not value is int or int(value) < 0:
				return _fail("Invalid row %d: negative or noninteger value" % row_id)
		if int(row[7]) not in [0, 1]:
			return _fail("Invalid spawn_from in row %d" % row_id)
		for group in 3:
			var monster_id := int(row[1 + group * 2])
			if monster_id > 7:
				return _fail("Solo campaign rows support original monster IDs 0..7")
			for member in int(row[2 + group * 2]):
				var delay := float(row[0]) if group == 0 and member == 0 else 0.0
				_entries.append({"monster_id": monster_id, "spawn_from": int(row[7]),
					"row": row_id, "delay": delay if delay > 0.0 else MEMBER_INTERVAL})
	if _entries.is_empty():
		return _fail("Mission contains no enemies")
	mission.round_count = rows.size()
	mission.total_enemies = _entries.size()
	set_running(true)
	return true


func set_running(value: bool) -> void:
	_running = value and not finished and not failed and not _entries.is_empty()
	set_process(_running)


func stop() -> void:
	_running = false
	set_process(false)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not _running or not is_finite(delta) or delta < 0.0:
		return
	if not is_instance_valid(_world):
		_fail("Mission world was freed")
		return
	if bool(_world.get("completed")):
		stop()
		return
	var alive := maxi(0, int(_world.get("alive_enemies")))
	if _draining:
		# EnemySpawnScript exits its spawn loop only after the arena is clear,
		# then waits one second before OnWin; alive time cannot consume that wait.
		if not _finish_delay_started:
			if alive > 0:
				return
			_finish_delay_started = true
			_delay_left = FINISH_DELAY
			return
		_delay_left = maxf(0.0, _delay_left - delta)
		if _delay_left <= 0.000001 and alive == 0:
			finished = true
			stop()
			mission_completed.emit(mission.duplicate(true))
		return
	var entry: Dictionary = _entries[_entry_index]
	var delay_delta := delta
	if _waiting_for_slot:
		# Source polls a full arena every half second, then starts the member wait.
		# Never bank overshoot from a capacity wait toward a spawn interval.
		if _slot_retry_left > 0.0:
			_slot_retry_left = maxf(0.0, _slot_retry_left - delta)
			if _slot_retry_left > 0.000001:
				return
			_slot_retry_left = 0.0
			delay_delta = 0.0
		if alive >= MAX_ALIVE:
			_slot_retry_left = MEMBER_INTERVAL
			return
		_delay_left = float(entry.delay)
		_waiting_for_slot = false
	elif alive >= MAX_ALIVE:
		return
	_delay_left = maxf(0.0, _delay_left - delay_delta)
	if _delay_left > 0.000001:
		return
	var absolute_round := cycle_index * int(mission.round_count) + int(entry.row)
	var difficulty := Missions.difficulty_for_round(mission, absolute_round)
	var monster_id := int(entry.monster_id)
	var beginner := int(mission.get("level_number", 1)) == 1 and int(mission.get("substage", 0)) < 3
	var elite := not beginner and monster_id not in [3, 4] and rng.randi_range(0, 99) < 5
	var request := {"monster_id": monster_id, "spawn_from": int(entry.spawn_from),
		"difficulty": difficulty, "elite": elite, "round_index": absolute_round}
	var accepted: Variant = _world.call("spawn_mission_enemy", request)
	if not accepted is bool or not bool(accepted):
		_fail("Spawn rejected: mission=%s monster=%d round=%d" % [str(mission.get("id", "")), monster_id, absolute_round])
		return
	spawned += 1
	if absolute_round != round_index:
		round_index = absolute_round
		round_started.emit(round_index, difficulty)
	_entry_index += 1
	_waiting_for_slot = true
	# As with Unity's yield between spawns, one tick emits at most one enemy.
	if _entry_index == _entries.size():
		if bool(mission.endless):
			cycle_index += 1
			_entry_index = 0
		else:
			_draining = true


func get_progress() -> Dictionary:
	return {"running": _running, "finished": finished, "failed": failed,
		"spawned": spawned, "round_index": round_index, "cycle_index": cycle_index,
		"total_enemies": int(mission.get("total_enemies", 0)), "error": configuration_error}


func _fail(reason: String) -> bool:
	configuration_error = reason
	failed = true
	stop()
	mission_failed.emit(reason)
	return false
