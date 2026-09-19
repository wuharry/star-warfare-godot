extends Node

const Source = preload("res://scripts/core/recovered_com_data.gd")
const Media = preload("res://scripts/core/recovered_source_assets.gd")
const Armor = preload("res://scripts/core/armor_catalog.gd")
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("SOURCE RECONSTRUCTION: " + message)

func _run() -> void:
	var original_save_hash := FileAccess.get_sha256(GameState.SAVE_PATH)
	GameState.save_path = "user://source_reconstruction_test.json"
	GameState.experience = 0
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.credits = 999999999999
	GameState.mithril = 99999999
	_check(GameState.get_com_level() == 1, "CoM base level")
	GameState.experience = 249
	_check(GameState.get_com_level() == 1, "premature level unlock")
	GameState.experience = 250
	_check(GameState.get_com_level() == 2, "250 XP threshold")
	GameState.experience = 500
	_check(GameState.get_com_level() == 3, "original current-level XP lookup")
	GameState.experience = 0
	var before := GameState.credits
	_check(GameState.purchase_armor("armor_head_21") == "rank_locked", "Assault unlock gate")
	_check(GameState.credits == before, "locked purchase consumed currency")
	GameState.experience = 20000000
	for set_id in range(21, 29):
		var row: Dictionary = Source.ARMOR_SETS[str(set_id)]
		var hp_sum := 0.0
		var shield_sum := 0.0
		var credit_before := GameState.credits
		var premium_before := GameState.mithril
		var result := GameState.purchase_armor(Armor.item_key(0, set_id))
		_check(result == "purchased", "suit purchase %d" % set_id)
		_check(credit_before - GameState.credits == int(row.credits), "whole-suit credit price %d" % set_id)
		_check(premium_before - GameState.mithril == int(row.premium), "whole-suit premium price %d" % set_id)
		for part in range(4):
			var key := Armor.item_key(part, set_id)
			_check(GameState.is_armor_owned(key), "purchase must grant all four parts")
			hp_sum += float(GameState.ARMOR_ITEMS[key].skills.hp)
			shield_sum += float(GameState.ARMOR_ITEMS[key].skills.shield)
		_check(is_equal_approx(hp_sum, float(row.hp)), "HP multiplied by four")
		_check(is_equal_approx(shield_sum, float(row.shield)), "shield multiplied by four")
		_check(GameState.purchase_armor(Armor.item_key(3, set_id)) == "owned", "duplicate suit charge")
		_check(GameState.equip_armor_set(set_id), "equip recovered set")
		var profile := GameState.get_source_shield_profile()
		_check(profile.delay == row.shield_delay and profile.fraction == row.shield_recovery_fraction, "shield source fields")
		var icon := Media.sprite("com", "Equipments", str(row.icon))
		_check(icon != null and icon.region.size == Vector2(150, 100), "native atlas treated as 2x")
	GameState.experience = 0
	GameState.equip_armor_set(22)
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	# Combat Suit: 200 HP + original player base 1 + SW1 starter backpack 200.
	_check(player.max_health == 401.0 and player.max_shield == 150.0, "live player ignored source armor")
	player.take_damage(50.0)
	_check(player.shield == 100.0 and player.health == 401.0, "shield absorption")
	player._update_source_shield(5.5)
	_check(player.shield == 100.0, "shield recovered before original six seconds")
	player._update_source_shield(1.0)
	_check(is_equal_approx(player.shield, 115.0), "delay crossing must restore only remaining half-second")
	var healing_audio_playing := false
	for child in AudioDirector.get_children():
		if child is AudioStreamPlayer3D and child.stream != null:
			healing_audio_playing = healing_audio_playing or (child.playing and child.stream.resource_path.ends_with("/sfx_amour_heal_01.wav"))
	_check(healing_audio_playing, "shield recovery did not play original prefab's heal clip")
	player.take_damage(10.0)
	player._update_source_shield(5.0)
	_check(is_equal_approx(player.shield, 105.0), "new hit did not reset delay")
	player._update_source_shield(10.0)
	_check(player.shield == 150.0, "shield cap")
	GameState.equip_armor("armor_head_00")
	_check(GameState.get_equipped_set_id() == -1 and player.source_shield_profile.is_empty(), "mixed set retained complete-suit passive")
	_check(is_equal_approx(player.max_shield, 137.5), "mixed shield contributions")
	GameState.equip_armor_set(0)
	_check(player.max_health == 1400.0 and player.max_shield == 100.0, "SW1 baseline changed")
	player.shield = 0.0
	GameState.equip_armor_set(22)
	GameState.equip_armor_set(0)
	_check(player.shield == 0.0, "cycling suits refilled depleted shield")
	player.free()
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.owned_armor.append("armor_head_21")
	GameState._normalize_armor_state()
	_check(GameState.is_armor_owned("armor_legs_21"), "legacy part ownership not migrated to complete suit")
	AudioDirector.stop_all_sfx()
	var paths := {}
	for path: String in Media.catalog().audio.values():
		paths[path] = true
	for path: String in paths:
		var stream := load(path) as AudioStream
		_check(stream != null and stream.get_length() > 0.0, "unplayable mapped audio: " + path)
	for entry: Dictionary in Media.catalog().ui.values():
		var texture := load(str(entry.texture)) as Texture2D
		_check(texture != null, "unloadable UI atlas")
	var ui_player := AudioDirector.play_source_2d("com", "UI_buy", -40.0)
	_check(ui_player != null and ui_player.playing, "CoM purchase audio not connected")
	AudioDirector.stop_all_sfx()
	if "--source-capture" in OS.get_cmdline_user_args():
		await _capture_store()
	_check(FileAccess.get_sha256(GameState.SAVE_PATH) == original_save_hash, "real save modified")
	await get_tree().process_frame
	var report := {"status": "PASS" if failures.is_empty() else "FAIL", "suits": 8, "parts": 32, "unique_audio_paths": paths.size(), "ui_atlases": Media.catalog().ui.size(), "failures": failures}
	var file := FileAccess.open("res://test_output/source_reconstruction/runtime_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	Media._atlases.clear()
	print("SOURCE_RECONSTRUCTION_TEST_PASS" if failures.is_empty() else "SOURCE_RECONSTRUCTION_TEST_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture_store() -> void:
	GameState.owned_armor = GameState._default_owned_armor()
	GameState.experience = 20000000
	GameState.settings.language = "zh_TW"
	Localization.apply_locale("zh_TW")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(0.4).timeout
	menu._show_armory("store")
	var shell: UnityEquipmentShell = menu.equipment_shell
	shell._select_category("head", false)
	shell._select_item("armor_head_21", false)
	_check(shell.stats_text.text.contains("32.50") and shell.stats_text.text.contains("62.50"), "store rounded recovered fractional part stats")
	shell._select_item("armor_head_27", false)
	_check(shell.description_text.text.contains("5.5"), "store rounded original half-second shield delay")
	shell._select_item("armor_head_21", false)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/source_reconstruction/store_applied.png")
	_check(shell.action_button.text == "購買整套", "store omitted whole-suit purchase")
	_check(not shell.description_text.text.contains("Viper stats"), "stale placeholder stats description")
	menu.free()
