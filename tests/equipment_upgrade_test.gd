extends Node

var failures: Array[String] = []
var paths: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("EQUIPMENT UPGRADE: " + message)

func _run() -> void:
	var original_save := GameState.save_path
	var original_hash := FileAccess.get_sha256(original_save)
	var isolated := "user://equipment_upgrade_%d.json" % Time.get_ticks_usec()
	paths.append(isolated)
	GameState.save_path = isolated
	GameState.owned_weapons.assign(["gun00"])
	GameState.battle_weapons.assign(["gun00"])
	GameState.selected_weapon = "gun00"
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.weapon_levels.clear()
	GameState.armor_set_levels.clear()
	GameState.experience = 0
	GameState.credits = 4499
	GameState.mithril = 1000
	var quote := GameState.get_upgrade_quote("gun00")
	_check(quote.credits == 4500 and quote.current.POW == 20.0 and quote.next.POW == 23.0, "FR28a source LV1→2 quote")
	_check(GameState.upgrade_equipment("gun00") == "not_enough_credits", "insufficient credits allowed")
	_check(GameState.upgrade_equipment("gun01") == "not_owned", "unowned weapon upgraded")
	_check(GameState.upgrade_equipment("armor_head_00") == "unsupported", "invented SW1 armor progression")
	_check(GameState.upgrade_equipment("invalid") == "unsupported", "unknown item accepted")
	_check(GameState.credits == 4499 and GameState.weapon_levels.is_empty(), "rejected upgrades mutated state")
	GameState.credits = 1000000
	var source_costs := [4500, 7500, 10500, 15000, 30000, 45000, 67500]
	var source_damage := [23.0, 27.0, 32.0, 38.0, 46.0, 56.0, 70.0]
	for level in range(1, 8):
		var cash := GameState.credits
		_check(GameState.upgrade_equipment("gun00", level) == "upgraded", "FR28a transaction level %d" % level)
		_check(cash - GameState.credits == source_costs[level - 1], "SW1 upgrade fee used wrong row")
		_check(is_equal_approx(GameState.get_weapon_data("gun00").damage, source_damage[level - 1]), "SW1 damage compounded or missed stage")
		var after := GameState.credits
		_check(GameState.upgrade_equipment("gun00", level) == "stale" and GameState.credits == after, "repeated confirmation charged twice")
	_check(GameState.upgrade_equipment("gun00") == "max_level", "LV8 should be final")
	_check(GameState.WEAPONS.gun00.damage == 20.0 and GameState.get_weapon_data("gun00").cooldown == 0.24, "base data or firerate changed")
	# Every current weapon uses the SW1 source profile, including premium weapons.
	GameState.owned_weapons.assign(GameState.get_weapon_ids())
	for key: String in GameState.get_weapon_ids():
		GameState.weapon_levels[key] = 8
		var weapon := GameState.get_weapon_data(key)
		_check(is_equal_approx(weapon.damage, float(GameState.WEAPONS[key].damage) * 3.5), "missing weapon progression: " + key)
		_check(weapon.splash_damage == GameState.WEAPONS[key].splash_damage, "SW1 upgrade incorrectly scaled secondary splash")
	GameState.weapon_levels.gun02 = 1
	quote = GameState.get_upgrade_quote("gun02")
	_check(quote.credits == 12000 and quote.mithril == 0, "MS06 mithril purchase price used for upgrade")
	# CoM source index 0 = displayed LV1. All four pieces share a level/payment.
	for set_id in range(21, 29):
		for part in range(4):
			GameState.owned_armor.append(GameState.ArmorCatalogData.item_key(part, set_id))
	GameState.equip_armor_set(21)
	GameState.credits = 1000000
	GameState.mithril = 1000
	var com_credits := [2000, 5000, 10000, 0, 0, 0]
	var com_premium := [0, 0, 0, 25, 49, 99]
	var com_factors := [1.2, 1.4, 1.6, 1.8, 2.1, 2.5]
	for level in range(1, 7):
		var cash := GameState.credits
		var premium := GameState.mithril
		quote = GameState.get_upgrade_quote("armor_arms_21")
		_check(quote.credits == com_credits[level - 1] and quote.mithril == com_premium[level - 1], "CoM next-level currency row")
		if level == 4:
			GameState.mithril = 24
			_check(GameState.upgrade_equipment("armor_arms_21") == "not_enough_mithril" and GameState.credits == cash, "premium failure partially debited credits")
			GameState.mithril = premium
		_check(GameState.upgrade_equipment("armor_arms_21", level) == "upgraded", "CoM upgrade failed")
		_check(cash - GameState.credits == com_credits[level - 1] and premium - GameState.mithril == com_premium[level - 1], "CoM suit charged more than once")
		for part in range(4):
			var key := GameState.ArmorCatalogData.item_key(part, 21)
			_check(GameState.get_equipment_level(key) == level + 1, "suit part levels diverged")
			_check(is_equal_approx(GameState.get_armor_item(key).skills.hp, 32.5 * com_factors[level - 1]), "CoM contribution must be 1/4 of upgraded suit")
	_check(GameState.upgrade_equipment("armor_head_21") == "max_level", "CoM LV7 cap")
	_check(is_equal_approx(GameState.get_armor_skills().hp, 526.0), "full suit HP plus player base and backpack")
	_check(is_equal_approx(GameState.get_armor_skills().shield, 625.0), "full suit shield must be 2.5x")
	for set_id in range(21, 29):
		GameState.armor_set_levels[str(set_id)] = 7
		var raw: Dictionary = GameState.ArmorCatalogData.CoMSource.ARMOR_SETS[str(set_id)]
		var hp := 0.0
		for part in range(4):
			hp += float(GameState.get_armor_item(GameState.ArmorCatalogData.item_key(part, set_id)).skills.hp)
		_check(is_equal_approx(hp, float(raw.hp) * 2.5), "missing CoM suit: %d" % set_id)
	# Combat consumes upgraded stats on spawn and when an upgrade completes.
	GameState.weapon_levels.gun00 = 1
	GameState.armor_set_levels["21"] = 1
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	_check(player.max_health == 331.0 and player.max_shield == 250.0, "CoM base player stats")
	player._set_magazine_rounds(7)
	player.reload_left = 0.5
	_check(GameState.upgrade_equipment("gun00", 1) == "upgraded", "live weapon upgrade")
	_check(is_equal_approx(player._current_weapon_damage(), 23.0), "shots still use catalog base damage")
	_check(player._magazine_rounds() == 7 and player.reload_left == 0.5, "upgrade refilled magazine or canceled reload")
	_check(GameState.upgrade_equipment("armor_body_21", 1) == "upgraded", "live armor upgrade")
	_check(is_equal_approx(player.max_health, 357.0) and is_equal_approx(player.max_shield, 300.0), "live armor pools did not update")
	player.queue_free()
	await get_tree().process_frame
	# Save/reload and migration from the pre-upgrade schema.
	_check(GameState._save(), "save failed")
	GameState.weapon_levels.clear()
	GameState.armor_set_levels.clear()
	GameState._load_save()
	_check(GameState.get_equipment_level("gun00") == 2 and GameState.get_equipment_level("armor_legs_21") == 2, "upgrade progress lost after reload")
	var wallet := GameState.credits
	var old_level := GameState.get_equipment_level("gun00")
	GameState.save_path = "user://missing_upgrade_%d/save.json" % Time.get_ticks_usec()
	_check(GameState.upgrade_equipment("gun00") == "save_failed", "unwritable save accepted")
	_check(GameState.credits == wallet and GameState.get_equipment_level("gun00") == old_level, "failed save retained payment or upgrade")
	GameState.save_path = isolated
	var old_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(isolated))
	old_save.erase("weapon_levels")
	old_save.erase("armor_set_levels")
	old_save.save_version = 4
	_write_save(old_save)
	GameState._load_save()
	_check(GameState.get_equipment_level("gun00") == 1 and GameState.get_equipment_level("armor_head_21") == 1 and GameState.credits == wallet, "old save migration changed wallet or invented upgrades")
	old_save.weapon_levels = {"gun00": 99999, "gun02": -10, "gun03": "8", "gun04": [8], "fake": 8}
	old_save.armor_set_levels = {"21": 99999, "0": 7, "22": 2.25}
	_write_save(old_save)
	GameState._load_save()
	_check(GameState.get_equipment_level("gun00") == 8 and GameState.get_equipment_level("gun02") == 1, "numeric saved levels not clamped")
	_check(not GameState.weapon_levels.has("gun03") and not GameState.weapon_levels.has("gun04") and not GameState.weapon_levels.has("fake"), "invalid saved level types accepted")
	_check(GameState.armor_set_levels == {"21": 7}, "invalid suit progress accepted")
	_check(GameState._read_upgrade_levels({"gun00": NAN, "gun02": INF}, true).is_empty(), "non-finite progress accepted")
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.25).timeout
	for path: String in paths:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	GameState.save_path = original_save
	_check(FileAccess.get_sha256(original_save) == original_hash, "test modified real save")
	print("EQUIPMENT_UPGRADE_PASS" if failures.is_empty() else "EQUIPMENT_UPGRADE_FAIL: %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _write_save(value: Dictionary) -> void:
	var file := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
