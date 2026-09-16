extends Node

const Source = preload("res://scripts/core/recovered_game_data.gd")
const Monsters = preload("res://scripts/core/monster_catalog.gd")
const StateScript = preload("res://scripts/core/game_state.gd")
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("RECOVERED DATA: " + message)


func _run() -> void:
	var save_hash := FileAccess.get_sha256(GameState.SAVE_PATH)
	GameState.save_path = "user://recovered_data_test_runtime.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.selected_game_mode = "singleplayer"
	GameState.settings.difficulty = "recruit"
	GameState.experience = 0
	_check(Source.SOURCE_SHA256 == FileAccess.get_sha256("res://assets/starwarfare_data/resDataSets_raw.bin"), "generated data is stale")
	_check(GameState.WEAPONS.size() == 47 and GameState.ARMOR_ITEMS.size() == 141, "catalog items were lost")
	for row: Array in Source.WEAPON_ROWS:
		var weapon: Dictionary = GameState.WEAPONS["gun%02d" % int(row[0])]
		_check(weapon.damage == row[2] and is_equal_approx(weapon.cooldown, float(row[3])) and weapon.energy == row[4], "weapon combat fields differ: " + str(row[1]))
		_check(weapon.price == row[11] and weapon.mithril == row[12] and weapon.unlock == row[8], "weapon shop fields differ: " + str(row[1]))
	var rocket: Dictionary = GameState.WEAPONS.gun11
	_check(rocket.magazine_size == 1 and is_equal_approx(rocket.cooldown, 1.4) and rocket.energy == 120 and rocket.unlock == 3, "RPG columns mistaken for magazine or rank")
	_check(is_equal_approx(rocket.speed_drag, -2.0), "signed speed drag was lost")
	_check(GameState.WEAPONS.gun32.range == 100.0 and GameState.WEAPONS.gun32.splash_damage == 0.0, "Morpheus range confused with splash damage")
	_check(GameState.PROPS.prop08.effects.damage_reduction == 0.5, "signed Force Shield reduction was lost")
	_check(Monsters.get_monster(10).name == "龙" and Monsters.get_monster(10).hp == 80000, "Dragon shifted by JSON display order")
	_check(Monsters.get_monster(12).experience == 0 and Monsters.get_monster(12).credits == 0, "zero-reward Assist Mantis changed")
	_check(Monsters.get_monster(15).is_empty(), "invalid monster ID should not alias a real enemy")
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	world.completed = true
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	_check(world.player.max_health == 1400.0, "Viper plus starter backpack HP must be 350 + 400 + 200 + 250 + 200, without the old 1/100 scale")
	var expected := {"crawler": [0, 45, 4, 70, 90, 10], "spitter": [2, 35, 3, 100, 160, 15], "brute": [3, 25, 6, 300, 130, 20], "boss": [10, 80000, 3, 700, 299999, 60000]}
	for kind: String in expected:
		var enemy := world._spawn_enemy(kind, false)
		enemy.set_physics_process(false)
		var e: Array = expected[kind]
		_check(enemy.source_monster_id == e[0] and enemy.max_health == e[1] and enemy.speed == e[2], "live spawn has wrong monster stats: " + kind)
		_check(enemy.attack_damage == e[3] and enemy.reward == e[4] and enemy.experience_value == e[5], "live combat or reward mismatch: " + kind)
		if kind == "crawler":
			var health_before := world.player.health
			world.player.shield = 0.0
			enemy._melee_attack()
			_check(world.player.health == health_before - 70.0, "source damage did not reach the player")
			enemy.take_damage(20.0, Vector3.ZERO, world.player)
			_check(enemy.health == 25.0, "source HP/damage is not used in combat")
			enemy.take_damage(100.0, Vector3.ZERO, world.player)
			enemy.take_damage(100.0, Vector3.ZERO, world.player)
			_check(world.battle_credits == 90 and GameState.experience == 10 and world.kills == 1, "kill did not award original cash/XP exactly once")
		if kind == "spitter":
			_check(enemy.attack_interval == 5.0 and enemy.attack_range == 18.0 and enemy.projectile_speed == 14.0, "Scorpion attack table is not used")
	var elite := world._spawn_enemy("crawler", true)
	_check(is_equal_approx(elite.max_health, 45.0 * 1.65) and elite.experience_value == 20 and elite.reward == 180, "elite modifiers were lost or doubled")
	world.free()
	AudioDirector.stop_all_sfx()
	_test_save_and_ranks()
	_check(FileAccess.get_sha256(GameState.SAVE_PATH) == save_hash, "real user profile was modified")
	await get_tree().process_frame
	print("RECOVERED_DATA_TEST_PASS" if failures.is_empty() else "RECOVERED_DATA_TEST_FAIL: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_save_and_ranks() -> void:
	var path := "user://recovered_data_test_migration.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"save_version": 3, "unlocked_level": 8, "credits": 999999999999, "mithril": 99999999, "best_scores": {"8": 1}, "owned_weapons": ["gun00"]}))
	file.close()
	var state := StateScript.new()
	state.save_path = path
	add_child(state)
	_check(state.experience == 0 and state.get_rank_id() == 8, "old profile lost its unlock floor")
	_check(state.credits == 999999999999 and state.mithril == 99999999, "test funds were changed by migration")
	state.unlocked_level = 1
	state.best_scores.clear()
	state.experience = 299
	_check(state.get_rank_id() == 0, "rank advanced before threshold")
	state.add_experience(1)
	_check(state.get_rank_id() == 1, "rank did not advance at 300 XP")
	state.experience = 20000000
	_check(state.get_rank_id() == 11, "maximum original rank is unreachable")
	state._save()
	state.free()
	var restored := StateScript.new()
	restored.save_path = path
	add_child(restored)
	_check(restored.experience == 20000000 and restored.get_rank_id() == 11, "XP/rank did not survive save round-trip")
	restored.free()
