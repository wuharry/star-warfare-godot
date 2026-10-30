class_name SoloMissions
extends RefCounted
## Original solo campaign only. Legacy start_level/custom waves stay separate.
## StageChoiseUI.cs:185, EnemySpawnScript.cs:85, StatisticsUI.cs:569.

const WaveData = preload("res://scripts/core/solo_wave_data.gd")
const LEVEL_COUNT := 8
const SUBSTAGE_COUNT := 6
const SURVIVAL_SUBSTAGE := 5
const STAGE_BONUSES := [20000, 50000, 80000, 120000, 200000, 300000, 500000, 700000]


static func mission_id(level_number: int, substage: int) -> String:
	if level_number < 1 or level_number > LEVEL_COUNT or substage < 0 or substage >= SUBSTAGE_COUNT:
		return ""
	return "%d:%d" % [level_number, substage]


static func get_mission(level_number: int, substage: int) -> Dictionary:
	var id := mission_id(level_number, substage)
	if id.is_empty():
		return {}
	var index := (level_number - 1) * SUBSTAGE_COUNT + substage
	var rows: Array = WaveData.TABLES[index].duplicate(true)
	var total := 0
	for row: Array in rows:
		total += int(row[2]) + int(row[4]) + int(row[6])
	var endless := substage == SURVIVAL_SUBSTAGE
	return {
		"id": id, "level_number": level_number, "substage": substage,
		"table_id": WaveData.FIRST_TABLE + index, "endless": endless,
		"base_difficulty": (level_number - 1) * 3 + (0 if endless else substage / 2),
		"round_count": rows.size(), "total_enemies": total, "rows": rows,
	}


static func get_by_id(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return {}
	var level_number := int(parts[0])
	var substage := int(parts[1])
	if mission_id(level_number, substage) != id:
		return {}
	return get_mission(level_number, substage)


static func get_missions(level_number: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if level_number >= 1 and level_number <= LEVEL_COUNT:
		for substage in SUBSTAGE_COUNT:
			result.append(get_mission(level_number, substage))
	return result


static func is_unlocked(id: String, completed_ids: Dictionary) -> bool:
	var mission := get_by_id(id)
	if mission.is_empty():
		return false
	var level_number := int(mission.level_number)
	var substage := int(mission.substage)
	# UserState.Init opens the first mission AND survival on each unlocked map.
	var map_open: bool = level_number == 1 or completed_ids.get(mission_id(level_number - 1, 4), false) == true
	if not map_open:
		return false
	return substage in [0, SURVIVAL_SUBSTAGE] or completed_ids.get(mission_id(level_number, substage - 1), false) == true


static func difficulty_for_round(mission: Dictionary, round_index: int) -> int:
	var base := int(mission.get("base_difficulty", 0))
	return base + (maxi(0, round_index) / 13 if bool(mission.get("endless", false)) else 0)


static func stage_bonus(level_number: int) -> int:
	return int(STAGE_BONUSES[level_number - 1]) if level_number >= 1 and level_number <= LEVEL_COUNT else 0


static func next_mission_id(id: String) -> String:
	var mission := get_by_id(id)
	if mission.is_empty() or bool(mission.endless):
		return ""
	var level_number := int(mission.level_number)
	var substage := int(mission.substage)
	if substage < 4:
		return mission_id(level_number, substage + 1)
	# StatisticsUI.Exit wraps the last map back to the first.
	return mission_id(level_number % LEVEL_COUNT + 1, 0)


static func complete(id: String, completed_ids: Dictionary, stage_bonuses: Dictionary = {}) -> Dictionary:
	var result := {"valid": false, "first_clear": false, "bonus": 0,
		"completed_ids": completed_ids.duplicate(true), "stage_bonuses": stage_bonuses.duplicate(true),
		"next_mission_id": ""}
	var mission := get_by_id(id)
	# An endless run can pay run rewards, but can never clear/unlock a mission.
	if mission.is_empty() or bool(mission.endless):
		return result
	result.valid = true
	result.first_clear = completed_ids.get(id, false) != true
	result.completed_ids[id] = true
	var level_key := str(mission.level_number)
	if bool(result.first_clear) and int(mission.substage) == 4 and stage_bonuses.get(level_key, false) != true:
		result.bonus = stage_bonus(int(mission.level_number))
		result.stage_bonuses[level_key] = true
	result.next_mission_id = next_mission_id(id)
	return result
