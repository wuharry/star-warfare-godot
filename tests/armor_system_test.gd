extends Node

const GameStateScript = preload("res://scripts/core/game_state.gd")
const ArmorCatalogData = preload("res://scripts/core/armor_catalog.gd")

var failures: Array[String] = []
var test_paths: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ARMOR SYSTEM TEST: " + message)

func _new_state(suffix: String) -> Node:
	var state := GameStateScript.new()
	state.save_path = "user://armor_system_test_%s.json" % suffix
	test_paths.append(state.save_path)
	_remove_test_save(state.save_path)
	add_child(state)
	return state

func _run() -> void:
	var state := _new_state("main")
	_check(state.ARMOR_ITEMS.size() == 109, "Unity catalog must contain all 109 armor items")
	var expected_counts := [21, 21, 21, 21, 25]
	for part in range(expected_counts.size()):
		_check(state.get_armor_ids(part).size() == expected_counts[part], "%s item count is incomplete" % ArmorCatalogData.PART_KEYS[part])
	_check(state.owned_armor.size() == 5, "new saves must own only the five starter pieces")
	for part in range(5):
		var starter_key := ArmorCatalogData.item_key(part, 0)
		_check(state.is_armor_owned(starter_key), "%s starter armor is not owned" % ArmorCatalogData.PART_KEYS[part])
		_check(state.get_equipped_armor_key(part) == starter_key, "%s starter armor is not equipped" % ArmorCatalogData.PART_KEYS[part])

	var titan_chest: Dictionary = state.get_armor_item("armor_body_05")
	_check(is_equal_approx(float(titan_chest.skills.speed_boost), -1.0), "signed Unity speed byte 246 was not decoded as -1")
	_check(state.get_bag_capacity() == 3, "starter VB-03-II pack must expose three slots")

	var loadout_signal_count := [0]
	state.loadout_changed.connect(func(): loadout_signal_count[0] += 1)
	state.credits = 25000
	_check(state.purchase_weapon("gun01") == "purchased", "Unity-style weapon purchase failed")
	_check(state.selected_weapon == "gun01", "purchased weapon was not selected")
	_check(state.battle_weapons[0] == "gun01", "purchased weapon was not mounted into bag slot zero")
	_check(state.is_weapon_owned("gun00"), "slot-zero replacement discarded ownership of the previous gun")
	_check(loadout_signal_count[0] == 1, "weapon purchase did not notify the combat loadout")

	state.credits = 20000
	_check(state.purchase_armor("armor_head_01") == "purchased", "credit armor purchase failed")
	_check(state.credits == 0, "credit armor used the wrong currency or amount")
	_check(state.get_equipped_armor_key("head") == "armor_head_01", "purchased armor was not auto-equipped")
	_check(state.purchase_armor("armor_head_01") == "owned", "owned armor purchase was not rejected")
	_check(state.purchase_armor("armor_head_14") == "rank_locked", "rank locked armor was purchasable")
	state.unlocked_level = 2
	state.mithril = 8
	state.credits = 999999
	_check(state.purchase_armor("armor_bag_03") == "purchased", "mithril pack purchase failed")
	_check(state.mithril == 0 and state.credits == 999999, "mithril-priced pack incorrectly consumed credits")

	for part in range(4):
		state.owned_armor.append(ArmorCatalogData.item_key(part, 4))
	state._normalize_armor_state()
	_check(state.equip_armor_set(4), "owned Strike set could not be equipped")
	_check(state.get_equipped_set_id() == 4, "four matching pieces did not activate their set")
	var strike_skills: Dictionary = state.get_armor_skills()
	# Strike: 8,800 part HP + 800 set HP + the currently equipped 300 HP pack.
	_check(is_equal_approx(float(strike_skills.hp), 9900.0), "Strike set HP or bag contribution is incorrect")
	_check(is_equal_approx(float(strike_skills.attack_boost), 0.40), "Strike set attack bonus or equipped pack contribution is incorrect")
	state.owned_armor.append("armor_head_00")
	state.equip_armor("armor_head_00")
	_check(state.get_equipped_set_id() == -1, "mixed main armor incorrectly retained a full-set bonus")

	state.owned_weapons = state.get_weapon_ids()
	state.battle_weapons.clear()
	for weapon_index in range(8):
		state.battle_weapons.append("gun%02d" % weapon_index)
	state._normalize_store_state()
	state.equip_armor("armor_bag_00")
	_check(state.get_bag_capacity() == 3, "equipped starter bag capacity changed")
	_check(state.battle_weapons.size() == 8, "smaller bag destructively truncated an existing loadout")

	state.unlocked_level = 8
	state.best_scores.clear()
	_check(state.get_rank_id() == 7, "opening the final sector should award only rank 7")
	state.best_scores["8"] = 1
	_check(state.get_rank_id() == 8, "completing the final sector did not award rank 8")

	state._normalize_armor_state()
	state._save()
	var roundtrip_path: String = state.save_path
	var equipped_before: Dictionary = state.equipped_armor.duplicate(true)
	var owned_before: Array = state.owned_armor.duplicate()
	state.free()
	var restored := GameStateScript.new()
	restored.save_path = roundtrip_path
	add_child(restored)
	_check(restored.equipped_armor == equipped_before, "equipped armor did not survive save round-trip")
	_check(restored.owned_armor == owned_before, "owned armor did not survive save round-trip")
	restored.free()

	var migration_path := "user://armor_system_test_migration.json"
	test_paths.append(migration_path)
	_remove_test_save(migration_path)
	var migration_file := FileAccess.open(migration_path, FileAccess.WRITE)
	migration_file.store_string(JSON.stringify({"credits": 123, "owned_weapons": ["gun00"], "battle_weapons": ["gun00"]}))
	migration_file.close()
	var migrated := GameStateScript.new()
	migrated.save_path = migration_path
	add_child(migrated)
	_check(migrated.owned_armor.size() == 5, "pre-armor save migration did not grant exactly the starter pieces")
	_check(not migrated.is_armor_owned("armor_head_01"), "pre-armor migration incorrectly unlocked the catalog")
	migrated.free()

	var numeric_path := "user://armor_system_test_numeric_migration.json"
	test_paths.append(numeric_path)
	_remove_test_save(numeric_path)
	var numeric_file := FileAccess.open(numeric_path, FileAccess.WRITE)
	numeric_file.store_string(JSON.stringify({
		"owned_weapons": ["gun00"], "battle_weapons": ["gun00"],
		"owned_armor": {"head": [0, 2], "body": [0, 3], "arms": [0, 4], "legs": [0, 5], "bag": [0, 6]},
		"equipped_armor": {"head": 2, "body": 3, "arms": 4, "legs": 5, "bag": 6}
	}))
	numeric_file.close()
	var numeric_migrated := GameStateScript.new()
	numeric_migrated.save_path = numeric_path
	add_child(numeric_migrated)
	_check(numeric_migrated.get_equipped_armor_key("head") == "armor_head_02", "numeric JSON head id did not migrate")
	_check(numeric_migrated.get_equipped_armor_key("bag") == "armor_bag_06", "numeric JSON bag id did not migrate")
	_check(numeric_migrated.is_armor_owned("armor_arms_04"), "numeric JSON owned armor did not migrate")
	numeric_migrated.free()

	var recovery_path := "user://armor_system_test_recovery.json"
	test_paths.append(recovery_path)
	_remove_test_save(recovery_path)
	var corrupt_primary := FileAccess.open(recovery_path, FileAccess.WRITE)
	corrupt_primary.store_string("{not valid json")
	corrupt_primary.close()
	var valid_backup := FileAccess.open(recovery_path + ".bak", FileAccess.WRITE)
	valid_backup.store_string(JSON.stringify({
		"credits": 321,
		"selected_level": 999,
		"owned_weapons": ["gun00"],
		"battle_weapons": ["gun00"],
		"best_scores": {"8": 12, "999": 999}
	}))
	valid_backup.close()
	var recovered := GameStateScript.new()
	recovered.save_path = recovery_path
	add_child(recovered)
	_check(recovered.credits == 321, "corrupt primary save did not recover from its backup")
	_check(recovered.selected_level == 1, "invalid selected level was not clamped during recovery")
	_check(recovered.best_scores == {"8": 12}, "invalid best-score keys survived save validation")
	recovered.free()

	for path in test_paths:
		_remove_test_save(path)
	if failures.is_empty():
		print("ARMOR_SYSTEM_TEST_PASS")
		get_tree().quit(0)
	else:
		print("ARMOR_SYSTEM_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _remove_test_save(path: String) -> void:
	for candidate in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
