extends Node

const GameStateScript = preload("res://scripts/core/game_state.gd")

var failures: Array[String] = []
var test_paths: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PROPS STORE TEST: " + message)


func _new_state(suffix: String) -> Node:
	var state := GameStateScript.new()
	state.save_path = "user://props_store_test_%s.json" % suffix
	test_paths.append(state.save_path)
	_remove_test_save(state.save_path)
	add_child(state)
	return state


func _run() -> void:
	var state := _new_state("main")
	_check(state.PROPS.size() == 11, "original Unity props catalog must contain 11 items")
	_check(state.get_prop_ids("health").size() == 6, "HEALTH shelf must contain six items")
	_check(state.get_prop_ids("aid").size() == 2, "AID-KIT shelf must contain two items")
	_check(state.get_prop_ids("assist").size() == 3, "ASSIST shelf must contain three items")
	_check(state.owned_props.is_empty(), "new save unexpectedly owns consumable supplies")

	state.credits = 5000
	_check(state.purchase_prop("prop00") == "purchased", "credit health-item purchase failed")
	_check(state.credits == 4000 and state.get_prop_count("prop00") == 1, "credit purchase did not update funds and storage")
	state.mithril = 1
	_check(state.purchase_prop("prop04") == "purchased", "mithril full-health purchase failed")
	_check(state.mithril == 0 and state.get_prop_count("prop04") == 1, "mithril purchase did not update funds and storage")
	state.owned_props["prop00"] = 99
	_check(state.purchase_prop("prop00") == "full", "99-item storage cap was not enforced")
	_check(state.credits == 4000, "rejected storage-cap purchase consumed currency")
	state._save()
	var saved_counts: Dictionary = state.owned_props.duplicate(true)
	state.free()

	var restored := GameStateScript.new()
	restored.save_path = test_paths[0]
	add_child(restored)
	_check(restored.owned_props == saved_counts, "supply inventory did not survive save round-trip")
	restored.free()

	for path in test_paths:
		_remove_test_save(path)
	if failures.is_empty():
		print("PROPS_STORE_TEST_PASS items=11 health=6 aid=2 assist=3")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _remove_test_save(path: String) -> void:
	for candidate in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
