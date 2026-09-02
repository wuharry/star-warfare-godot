extends Node

# Guards the campaign unlock gate.
#
# CAMPAIGN_FULLY_UNLOCKED opens every singleplayer sector for testing, so this
# asserts the whole campaign really is reachable and that no locked card is
# left disabled in the level select. It also pins down what the switch must not
# do: unlocked_level has to keep tracking real progress underneath, or turning
# progression back on would wipe everyone's place in the campaign.

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CAMPAIGN ACCESS TEST: " + message)

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	_test_gate()
	_test_pvp_wave_guard()
	await _test_level_select()
	_test_progress_still_tracked()

	if failures.is_empty():
		print("CAMPAIGN_ACCESS_TEST_PASS solo=%d multiplayer=%d" % [
			GameState.SINGLEPLAYER_LEVELS.size(), GameState.MULTIPLAYER_LEVELS.size()
		])
		get_tree().quit(0)
	else:
		print("CAMPAIGN_ACCESS_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _test_gate() -> void:
	_check(GameState.CAMPAIGN_FULLY_UNLOCKED, "the campaign is not fully unlocked")

	# Deliberately from the worst case: a save that has never finished a sector.
	var restore := GameState.unlocked_level
	GameState.unlocked_level = 1
	for level_number: int in GameState.SINGLEPLAYER_LEVELS:
		_check(
			GameState.is_level_unlocked(level_number, "singleplayer"),
			"solo sector %d is locked on a fresh save" % level_number
		)
	for level_number: int in GameState.MULTIPLAYER_LEVELS:
		_check(
			GameState.is_level_unlocked(level_number, "multiplayer"),
			"multiplayer map %d is locked" % level_number
		)
		var arena := GameState.get_level_data(level_number)
		_check(bool(arena.get("pvp", false)), "multiplayer map %d is not marked PVP" % level_number)
		_check(str(arena.get("mode", "")) == "pvp", "multiplayer map %d has the wrong mode" % level_number)
		_check(int(arena.get("waves", -1)) == 0, "multiplayer map %d still has PVE waves" % level_number)
		_check(int(arena.get("base_enemies", -1)) == 0, "multiplayer map %d still spawns PVE enemies" % level_number)
		_check(not bool(arena.get("boss", true)), "multiplayer map %d is still treated as a PVE boss stage" % level_number)
	GameState.unlocked_level = restore

func _test_pvp_wave_guard() -> void:
	var world := WarfareGameWorld.new()
	world.pvp_arena = true
	world.level_data = GameState.get_level_data(GameState.MULTIPLAYER_LEVELS[0])
	world._start_next_wave()
	_check(world.current_wave == 0, "PVP arena entered the PVE wave loop")
	_check(world.total_spawned == 0, "PVP arena spawned a PVE enemy")
	world.free()

func _test_level_select() -> void:
	var restore := GameState.unlocked_level
	GameState.unlocked_level = 1
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame

	menu._show_level_select("singleplayer")
	await get_tree().process_frame
	var cards := _level_cards(menu)
	_check(
		cards.size() == GameState.SINGLEPLAYER_LEVELS.size(),
		"the solo level select shows %d cards, expected %d" % [cards.size(), GameState.SINGLEPLAYER_LEVELS.size()]
	)
	var disabled := 0
	var labelled_locked := 0
	for card in cards:
		if card.disabled:
			disabled += 1
		if tr("LOCKED • ") in card.text or "LOCKED" in card.text:
			labelled_locked += 1
	_check(disabled == 0, "%d solo sectors are still disabled in the level select" % disabled)
	_check(labelled_locked == 0, "%d solo sectors are still labelled as locked" % labelled_locked)

	menu.queue_free()
	await get_tree().process_frame
	GameState.unlocked_level = restore

func _level_cards(node: Node) -> Array[Button]:
	# Level cards are the only buttons in the menu carrying a preview icon.
	var result: Array[Button] = []
	if node is Button and (node as Button).icon != null:
		result.append(node as Button)
	for child in node.get_children():
		result.append_array(_level_cards(child))
	return result

func _test_progress_still_tracked() -> void:
	# The switch opens the doors; it must not stop the game recording which
	# sectors have actually been cleared.
	var restore_unlocked := GameState.unlocked_level
	var restore_credits := GameState.credits
	var restore_best := GameState.best_scores.duplicate(true)
	var restore_mode := GameState.selected_game_mode

	GameState.selected_game_mode = "singleplayer"
	GameState.unlocked_level = 1
	GameState.complete_level(1, 1234, 0)
	_check(
		GameState.unlocked_level >= 2,
		"clearing sector 01 no longer advances progress (unlocked_level=%d)" % GameState.unlocked_level
	)

	GameState.unlocked_level = restore_unlocked
	GameState.credits = restore_credits
	GameState.best_scores = restore_best
	GameState.selected_game_mode = restore_mode
	GameState._save()
