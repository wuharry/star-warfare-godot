extends Node

const CareerData = preload("res://scripts/core/career_progress.gd")
const BattleData = preload("res://scripts/game/battle_progress.gd")
const PanelScript = preload("res://scripts/ui/career_panel.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("CAREER: " + message)


func _run() -> void:
	# This suite never reads/writes a profile. The flag also isolates autoload init.
	_check(str(GameState.save_path).begins_with("user://star_warfare_test_"), "run with -- --test-profile=career_unique_name")
	_test_kills_and_notifications()
	_test_boss_categories()
	_test_spending_and_upgrades()
	_test_inventory_and_migration()
	_test_combo_and_rewards()
	_test_results_and_no_hit()
	_test_save_roundtrip_and_corruption()
	await _test_panel()
	print("CAREER_PROGRESS_%s: %d checks%s" % ["PASS" if failures.is_empty() else "FAIL", checks, "" if failures.is_empty() else str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_kills_and_notifications() -> void:
	var career := CareerData.new()
	var events: Array[String] = []
	career.achievement_unlocked.connect(func(id: String) -> void: events.append(id))
	_check(career.get_achievements().size() == 23 and career.get_statistics().achievements_completed == 0, "fresh profile should have 23 locked source achievements")
	career.record_enemy_kill()
	_check(career.is_unlocked("a1") and not career.is_unlocked("a2"), "first enemy threshold")
	for index in range(98):
		career.record_enemy_kill()
	_check(not career.is_unlocked("a2"), "99 kills must not grant Debugger")
	career.record_enemy_kill()
	_check(career.is_unlocked("a2") and career.get_statistics().enemy_kills == 100, "100 kills must grant Debugger")
	for index in range(49):
		career.record_enemy_kill(true)
	_check(not career.is_unlocked("a11"), "49 multiplayer alien kills")
	career.record_enemy_kill(true)
	_check(career.is_unlocked("a11") and not career.is_unlocked("a12"), "50 multiplayer alien kills")
	for index in range(449):
		career.record_enemy_kill(true)
	_check(not career.is_unlocked("a12"), "499 multiplayer alien kills")
	career.record_enemy_kill(true)
	_check(career.is_unlocked("a12") and career.get_statistics().enemy_kills == 600, "500 multiplayer kills also count as aliens")
	_check(events.count("a1") == 1 and events.count("a2") == 1, "unlock notifications must fire only once")
	_check(not career.is_unlocked("a10"), "a kill alone does not invent a session")
	career.record_multiplayer_start()
	_check(career.is_unlocked("a10"), "OnceCoop is granted on multiplayer start")


func _test_boss_categories() -> void:
	var career := CareerData.new()
	_check(not career.record_boss_kill(-1) and not career.record_boss_kill(3), "invalid boss category rejected")
	for category in range(3):
		for index in range(5):
			career.record_boss_kill(category)
	_check(career.is_unlocked("a3") and not career.is_unlocked("a22"), "15 bosses split 5/5/5 must not grant same-category 10")
	for index in range(4):
		career.record_boss_kill(1)
	_check(not career.is_unlocked("a22"), "same-category 9 does not grant 10")
	career.record_boss_kill(1)
	_check(career.is_unlocked("a22"), "same-category 10 grants boss achievement")
	for index in range(89):
		career.record_boss_kill(1)
	_check(not career.is_unlocked("a23"), "same-category 99 does not grant 100")
	career.record_boss_kill(1)
	_check(career.is_unlocked("a23"), "same-category 100 grants boss achievement")
	_check(career.get_statistics().boss_kills == [5, 100, 5], "source boss buckets must persist separately")


func _test_spending_and_upgrades() -> void:
	var career := CareerData.new()
	_check(not career.record_spend(-30) and not career.record_spend(0), "refunds and free transactions are not spending")
	career.record_spend(999999)
	_check(not career.is_unlocked("a4"), "million credit threshold - 1")
	career.record_spend(1)
	_check(career.is_unlocked("a4") and not career.is_unlocked("a5"), "million credit threshold")
	career.record_spend(8999999)
	_check(not career.is_unlocked("a5"), "ten million credit threshold - 1")
	career.record_spend(1)
	_check(career.is_unlocked("a5"), "ten million credit threshold")
	_check(not career.record_full_upgrade("armor_head_21") and not career.record_full_upgrade("gun47"), "CoM armor or a non-source weapon cannot grant source upgrades")
	_check(career.record_full_upgrade("gun00") and not career.record_full_upgrade("gun00"), "full upgrade notification must be idempotent")
	_check(career.is_unlocked("a6") and not career.is_unlocked("a7"), "first fully upgraded weapon")
	for index in range(1, 4):
		career.record_full_upgrade("gun%02d" % index)
	_check(not career.is_unlocked("a7"), "four upgraded weapons are not five")
	career.record_full_upgrade("gun04")
	_check(career.is_unlocked("a7"), "five fully upgraded weapons")
	# Parent transactions can roll back both money and achievements on save failure.
	var before := career.serialize()
	career.record_spend(1234)
	career.record_full_upgrade("gun05")
	career.load_data(before)
	_check(career.serialize() == before, "save failure rollback must restore all career data")


func _test_inventory_and_migration() -> void:
	var career := CareerData.new()
	var armor: Array = []
	for set_id in range(6):
		for part: String in ["head", "body", "arms", "legs"]:
			armor.append("armor_%s_%02d" % [part, set_id])
	career.sync_inventory(armor, {})
	_check(career.is_unlocked("a8") and not career.is_unlocked("a9"), "six complete suits do not grant source TenSuit (seven)")
	armor.append_array(["armor_head_06", "armor_body_06", "armor_arms_06", "armor_bag_06"])
	career.sync_inventory(armor, {})
	_check(career.get_statistics().suits_collected == 6, "backpack cannot replace missing legs")
	armor.append("armor_legs_06")
	career.sync_inventory(armor, {})
	_check(career.is_unlocked("a9") and career.get_statistics().suits_collected == 7, "seven complete source suits, not ten")
	for part: String in ["head", "body", "arms", "legs"]:
		armor.append("armor_%s_21" % part)
	career.sync_inventory(armor, {})
	_check(career.get_statistics().suits_collected == 7, "CoM suits must not silently expand SW1 collection rules")
	career.sync_inventory([], {})
	_check(career.is_unlocked("a9") and career.get_statistics().suits_collected == 0, "earned achievements remain after inventory changes")
	var events: Array[String] = []
	career.achievement_unlocked.connect(func(id: String) -> void: events.append(id))
	career.load_save_section({"save_version": 5, "owned_armor": armor,
		"weapon_levels": {"gun00": 8.0, "gun01": 7.0}, "best_scores": {"1": 5432.0},
		"credits": 10000000, "experience": 9000000, "unlocked_level": 8})
	var stats := career.get_statistics()
	_check(stats.suits_collected == 7 and stats.full_upgrades == 1 and stats.high_score == 5432, "old save should recover only provable inventory/upgrades/scores")
	_check(stats.enemy_kills == 0 and stats.credits_spent == 0 and stats.wins == 0 and not career.is_unlocked("a14"), "old cash/XP/unlock level do not prove historical activity")
	_check(events.is_empty(), "migration should not replay unlock notifications")
	_check(not career.record_full_upgrade("gun00"), "legacy full upgrade baseline prevents double counting")
	career.load_save_section({})
	_check(career.get_statistics().achievements_completed == 0, "loading a missing career must reset previous profile")


func _test_combo_and_rewards() -> void:
	var career := CareerData.new()
	var battle := BattleData.new()
	battle.start(career)
	_check(battle.combo == 0 and not career.is_unlocked("a13"), "starting a run is not a combo")
	battle.record_enemy_kill()
	_check(battle.combo == 1 and career.is_unlocked("a13"), "source combo achievement starts with first kill")
	battle.advance(3.0)
	_check(battle.combo == 1, "exactly 3 seconds is still inside source window")
	battle.record_enemy_kill()
	_check(battle.combo == 2, "kill at exactly 3 seconds continues chain")
	battle.advance(3.0001)
	_check(battle.combo == 0 and battle.max_combo == 2, "more than 3 seconds clears current but keeps maximum")
	battle.record_enemy_kill()
	_check(battle.combo == 1, "a new chain starts at one")
	battle.advance(-5.0)
	battle.advance(NAN)
	battle.advance(INF)
	_check(battle.combo == 1 and is_finite(battle.elapsed), "invalid delta cannot corrupt the timer")
	# No advance call while paused: querying bonus/UI has no wall-clock effects.
	for index in range(49):
		battle.advance(0.01)
		battle.record_enemy_kill()
		var expected := 1.0 if battle.combo >= 10 else (0.5 if battle.combo >= 8 else (0.2 if battle.combo >= 5 else (0.1 if battle.combo >= 3 else 0.0)))
		_check(is_equal_approx(battle.get_combo_bonus_rate(), expected), "source combo payout at kill %d" % battle.combo)
		if battle.combo == 9:
			_check(not career.is_unlocked("a20"), "combo 9 must not grant 10")
		if battle.combo == 49:
			_check(not career.is_unlocked("a21"), "combo 49 must not grant 50")
	_check(battle.max_combo == 50 and career.is_unlocked("a20") and career.is_unlocked("a21"), "combo 10/50 source milestones")
	_check(career.get_statistics().credits_spent == 0, "battle helper must not issue a financial transaction")
	var before: int = career.get_statistics().enemy_kills
	var first := battle.finish(true, 1234)
	var repeated := battle.finish(false, 99999)
	_check(first == repeated and career.get_statistics().wins == 1 and career.get_statistics().losses == 0, "first result wins; repeated finish cannot settle twice")
	battle.record_enemy_kill()
	_check(career.get_statistics().enemy_kills == before, "late kill after settlement ignored")
	battle.start(career)
	_check(battle.combo == 0 and battle.max_combo == 0 and battle.kills == 0, "new run must reset all transient combat state")
	_check(career.get_statistics().max_combo == 50, "new run must not reset lifetime combo")
	battle.stop()
	_check(battle.finish(true).is_empty() and career.get_statistics().wins == 1, "abandoning a run cannot grant victory")


func _test_results_and_no_hit() -> void:
	var career := CareerData.new()
	var battle := BattleData.new()
	for stage in [0, 2, 4]:
		var id: String = {0: "a14", 2: "a15", 4: "a16"}[stage]
		battle.start(career, {"source_stage": stage, "source_substage": 3})
		battle.finish(true)
		_check(not career.is_unlocked(id), "source substage 3 cannot grant chapter achievement")
		battle.start(career, {"source_stage": stage, "source_substage": 5})
		battle.finish(true)
		_check(not career.is_unlocked(id), "source survival substage 5 cannot grant chapter achievement")
		battle.start(career, {"source_stage": stage, "source_substage": 4})
		battle.finish(false)
		_check(not career.is_unlocked(id), "loss at source checkpoint cannot grant chapter achievement")
		battle.start(career, {"source_stage": stage, "source_substage": 4})
		battle.finish(true)
		_check(career.is_unlocked(id), "source stage %d/substage 4 win must grant checkpoint" % stage)
	career = CareerData.new()
	battle.start(career, {"multiplayer": true, "pve": false, "source_stage": 0, "source_substage": 4})
	battle.finish(true)
	_check(career.is_unlocked("a10") and not career.is_unlocked("a14") and not career.is_unlocked("a17"), "VS match cannot grant campaign/Ghost achievements")
	battle.start(career)
	battle.record_damage(1.0)
	battle.record_damage(-100.0)
	battle.finish(true)
	_check(not career.is_unlocked("a17"), "healing does not undo a hit")
	battle.start(career)
	battle.record_revival()
	battle.finish(true)
	_check(career.is_unlocked("a18") and not career.is_unlocked("a17"), "reviving disqualifies Ghost")
	for index in range(98):
		career.record_revival()
	_check(not career.is_unlocked("a19"), "99 revivals must not grant Phoenix")
	career.record_revival()
	_check(career.is_unlocked("a19"), "100 revivals grant Phoenix")
	battle.start(career)
	battle.record_damage(0.0)
	battle.record_damage(NAN)
	battle.finish(false)
	_check(not career.is_unlocked("a17"), "unhurt loss is not Ghost")
	battle.start(career, {"level_key": "survival:1"})
	battle.record_damage(0.0)
	battle.record_damage(-50.0)
	battle.record_enemy_kill(2)
	battle.finish(true, 500)
	_check(career.is_unlocked("a17") and career.get_statistics().boss_kills == [0, 0, 1], "unhurt PvE victory grants Ghost and boss kill records once")
	career.record_run({"won": false, "score": 800, "kills": 12, "level_key": "survival:1"})
	career.record_run({"won": true, "score": 30, "level_key": "survival:1"})
	_check(career.get_statistics().high_score == 800 and career.get_statistics().best_scores["survival:1"] == 800 and career.get_statistics().high_kills == 12, "scores include finished losses and never decrease")
	var snapshot := career.serialize()
	_check(not career.record_run({"score": 9999}) and career.serialize() == snapshot, "malformed result cannot mutate career")


func _test_save_roundtrip_and_corruption() -> void:
	var career := CareerData.new()
	career.record_enemy_kill(true)
	career.record_boss_kill(0)
	career.record_full_upgrade("gun03")
	career.record_spend(54321)
	career.record_revival()
	career.record_multiplayer_start()
	career.record_run({"won": true, "pve": true, "never_hit": true, "score": 901,
		"kills": 1, "max_combo": 1, "level_key": "campaign:1", "source_stage": 0, "source_substage": 4})
	var snapshot := career.serialize()
	var restored := CareerData.new()
	var events: Array[String] = []
	restored.achievement_unlocked.connect(func(id: String) -> void: events.append(id))
	restored.load_save_section({"career_progress": JSON.parse_string(JSON.stringify(snapshot)), "best_scores": {"bogus": 99999}})
	_check(restored.serialize() == snapshot and events.is_empty(), "JSON roundtrip must preserve every statistic without notifications or legacy overwrite")
	var exported := restored.serialize()
	exported.stats.enemy_kills = 999999
	exported.boss_kills[0] = 99
	exported.best_scores.clear()
	_check(restored.serialize() == snapshot, "serialize must not expose mutable internal dictionaries/arrays")
	var rows := restored.get_achievements()
	rows[0].target = 999
	_check(restored.get_achievements()[0].target == 1, "UI snapshots cannot mutate achievement definitions")
	for invalid: Variant in [null, "broken", [], 99]:
		restored.load_data(invalid)
		_check(restored.get_statistics().enemy_kills == 0 and restored.get_statistics().achievements_completed == 0, "invalid root must initialize safely")
	restored.load_data({"stats": {"enemy_kills": "100", "team_kills": -1, "max_combo": NAN,
		"credits_spent": INF, "revivals": 1.5, "wins": true}, "boss_kills": ["100", -1, null, 100],
		"best_scores": {"a": "99", "b": NAN, "c": -5, "d": 2.5},
		"full_weapon_ids": ["fake", "armor_head_00", 7], "unlocked": ["platform.fake", 1]})
	_check(restored.get_statistics().achievements_completed == 0 and restored.get_statistics().boss_kills == [0, 0, 0] and restored.get_statistics().best_scores.is_empty(), "malformed fields must not invent counters or unlocks")
	restored.load_data({"stats": {"enemy_kills": 101.0, "max_combo": 51.0, "revivals": 101.0, "credits_spent": 10000001.0}, "unlocked": ["a14"]})
	_check(restored.is_unlocked("a1") and restored.is_unlocked("a2") and restored.is_unlocked("a13") and restored.is_unlocked("a20") and restored.is_unlocked("a21") and restored.is_unlocked("a19") and restored.is_unlocked("a5"), "migration above a source == boundary must repair missed achievements")
	_check(restored.is_unlocked("a14"), "known completed flags survive incomplete old counter records")
	restored.load_data({"stats": {"credits_spent": CareerData.MAX_COUNTER}})
	restored.record_spend(1000000)
	_check(restored.get_statistics().credits_spent == CareerData.MAX_COUNTER, "counter addition must not overflow JSON-safe range")


func _test_panel() -> void:
	var career := CareerData.new()
	var panel := PanelScript.new()
	var previous := Button.new()
	previous.text = "PROFILE"
	add_child(previous)
	previous.grab_focus()
	add_child(panel)
	panel.show_progress(career)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.visible and panel._achievement_rows.size() == 23, "panel exposes all source achievements")
	_check(get_viewport().get_visible_rect().encloses(panel.panel.get_global_rect()), "overlay content must stay inside viewport after text reflow")
	_check(panel.completion_label.get_line_count() == 1 and panel._stat_values.enemy_kills.get_line_count() == 1, "numeric columns must not wrap into vertical digits")
	_check(get_viewport().gui_get_focus_owner() == panel.close_button, "opening panel moves keyboard focus inside")
	career.record_enemy_kill()
	await get_tree().process_frame
	_check(panel.completion_label.text == "1 / 23" and panel._stat_values.enemy_kills.text == "1", "visible panel reacts to live data changes")
	panel.tabs.current_tab = 1
	get_tree().root.size = Vector2i(720, 480)
	get_tree().root.content_scale_size = Vector2i(720, 480)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_viewport().get_visible_rect().encloses(panel.panel.get_global_rect()), "compact overlay must keep header and Back inside viewport")
	var scroll := panel.tabs.get_node("ACHIEVEMENTS/AchievementScroll") as ScrollContainer
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await get_tree().process_frame
	_check(scroll.get_global_rect().intersects(panel._achievement_rows.a23.card.get_global_rect()), "last achievement must be reachable by scrolling")
	panel.filter.select(2)
	panel.filter.item_selected.emit(2)
	_check(panel._achievement_rows.a1.card.visible and not panel._achievement_rows.a2.card.visible, "completed filter must match achieved rows")
	panel.filter.select(1)
	panel.filter.item_selected.emit(1)
	_check(not panel._achievement_rows.a1.card.visible and panel._achievement_rows.a2.card.visible, "in-progress filter must hide completed rows")
	var other := CareerData.new()
	panel.bind_progress(other)
	await get_tree().process_frame
	_check(panel.completion_label.text == "0 / 23" and not career.changed.is_connected(panel._queue_refresh), "rebinding must detach the previous profile")
	var close_events: Array[bool] = []
	panel.dismissed.connect(func() -> void: close_events.append(true))
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	panel._input(cancel)
	panel.close()
	_check(not panel.visible and close_events.size() == 1 and get_viewport().gui_get_focus_owner() == previous, "cancel closes once and restores profile focus")
	panel.queue_free()
	previous.queue_free()
	await get_tree().process_frame
