extends Node

const StateScript = preload("res://scripts/core/game_state.gd")
const SAVE := "user://solo_progress_behavior_test.json"
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	_cleanup()
	var state := StateScript.new()
	state.save_path = SAVE
	add_child(state)
	check(state.is_solo_mission_unlocked(1, 0), "First original mission is locked")
	check(state.is_solo_mission_unlocked(1, 5), "First map survival is locked")
	check(not state.is_solo_mission_unlocked(1, 1) and not state.is_solo_mission_unlocked(2, 0), "New campaign skipped its progression")
	var receipt: Dictionary = state.settle_solo_run(1, 0, true, {"run_id": "first", "credits": 100, "experience": 300, "score": 125})
	check(receipt.saved and state.credits == 100 and state.experience == 300, "Victory rewards did not bank exactly once")
	check(receipt.next_mission == {"level": 1, "substage": 1} and state.is_solo_mission_unlocked(1, 1), "First mission did not open the second")
	check(state.get_rank_id() == 1, "Rank did not follow source XP threshold")
	state.settle_solo_run(1, 0, true, {"run_id": "first", "credits": 100, "experience": 300, "score": 125})
	check(state.credits == 100 and state.experience == 300, "Duplicate run receipt paid twice")
	state.free()
	state = StateScript.new()
	state.save_path = SAVE
	add_child(state)
	state.settle_solo_run(1, 0, true, {"run_id": "first", "credits": 100, "experience": 300})
	check(state.credits == 100 and state.is_solo_mission_unlocked(1, 1), "Progress/receipt was lost after load")
	for substage in range(1, 5):
		receipt = state.settle_solo_run(1, substage, true, {"run_id": "mission%d" % substage, "credits": 100, "experience": 100})
	check(state.credits == 20500 and int(receipt.stage_bonus) == 20000, "Original first map completion bonus is missing")
	check(state.is_solo_mission_unlocked(2, 0) and not state.is_solo_mission_unlocked(2, 1), "Next map unlock is incorrect")
	state.settle_solo_run(1, 4, true, {"run_id": "replay", "credits": 50})
	check(state.credits == 20550, "Replaying a map duplicated its first clear bonus")
	receipt = state.settle_solo_run(2, 0, false, {"run_id": "death", "credits": 70, "experience": 20})
	check(state.credits == 20620 and state.experience == 720, "Defeat discarded earned cash or XP")
	check(not state.is_solo_mission_unlocked(2, 1), "Defeat unlocked the next mission")
	state.unlocked_level = 8
	state.best_scores["8"] = 99999
	state.experience = 0
	check(state.get_rank_id() == 0, "Map access or score still grants rank")
	state.save_path = "user://missing_solo_progress_test_directory/profile.json"
	var credits_before: int = state.credits
	receipt = state.settle_solo_run(8, 4, true, {"run_id": "failed", "credits": 50, "experience": 50})
	check(not receipt.saved and state.credits == credits_before and state.experience == 0, "Failed settlement kept rewards in memory")
	check(not state.solo_completed.has("8:4") and not state.solo_stage_bonuses.has("8") and not state.settled_runs.has("failed"), "Failed save consumed the first-clear bonus or receipt")
	state.save_path = SAVE
	state.unlocked_level = 1
	var boss_reward := {"run_id": "boss_network", "boss_encounter": true, "campaign_progress": false, "credits": 300, "experience": 10}
	var boss_receipt: Dictionary = state.settle_solo_run(1, -1, true, boss_reward)
	check(int(boss_receipt.mithril) == 1 and state.mithril == 1, "Boss encounter did not pay the approved one Mithril")
	state.settle_solo_run(1, -1, true, boss_reward)
	check(state.mithril == 1 and state.unlocked_level == 1, "Network Boss duplicated Mithril or unlocked the solo campaign")
	boss_reward.run_id = "boss_loss"
	state.settle_solo_run(1, -1, false, boss_reward)
	check(state.mithril == 1, "Losing a Boss encounter paid Mithril")
	state.free()
	_cleanup()
	if failures.is_empty():
		print("SOLO_PROGRESS_TEST_PASS unlock=bonus=defeat=idempotency=save_rollback=rank=PASS")
	get_tree().quit(0 if failures.is_empty() else 1)


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE + suffix))
