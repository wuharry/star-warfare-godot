extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("RESTORATION TEST: " + message)

func _run() -> void:
	_check(GameState.WEAPONS.size() == 47, "the recovered weapon database must contain 47 weapons")
	for weapon_id: String in GameState.get_weapon_ids():
		var weapon: Dictionary = GameState.WEAPONS[weapon_id]
		_check(weapon.has("animation"), "%s has no recovered animation profile" % weapon_id)
		for key in ["sound", "blank_sound", "loop_sound", "stop_sound", "explosion_sound"]:
			var relative_path := str(weapon[key])
			if not relative_path.is_empty():
				_check(ResourceLoader.exists("res://assets/original/audio/" + relative_path), "%s references missing audio %s" % [weapon_id, relative_path])
		for key in ["sound_variants", "swing_sounds", "hit_sounds"]:
			for relative_path: String in weapon[key]:
				_check(ResourceLoader.exists("res://assets/original/audio/" + relative_path), "%s references missing audio %s" % [weapon_id, relative_path])
	for relative_path: String in AudioDirector.UI_EVENTS.values():
		_check(ResourceLoader.exists(AudioDirector.AUDIO_ROOT + relative_path), "UI audio is missing: " + relative_path)

	var menu_scene := load("res://scenes/main_menu.tscn") as PackedScene
	var menu := menu_scene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._show_armory()
	await get_tree().process_frame
	var armory_buttons := _store_weapon_buttons(menu.modal_layer)
	_check(armory_buttons.size() == 47, "armory should render all 47 original weapons")
	for button: Button in armory_buttons:
		_check(button.icon != null, "armory weapon is missing its original atlas icon: " + button.text)
	_check(menu.store_slot_picker.item_count >= 1, "armory is missing the Unity battle-weapon slot picker")
	_check(menu.store_category_buttons.size() == 6, "armory is missing functional category tabs")
	menu._select_store_category("RIFLE")
	await get_tree().process_frame
	var rifle_buttons := _store_weapon_buttons(menu.modal_layer)
	_check(not rifle_buttons.is_empty() and rifle_buttons.size() < 47, "rifle category did not filter the Unity weapon catalog")
	menu._select_store_category("ALL")
	await get_tree().process_frame
	menu._close_modal()
	await get_tree().process_frame
	_check(GameState.SINGLEPLAYER_LEVELS.size() == 8, "single-player campaign must contain sectors 01-08")
	_check(GameState.MULTIPLAYER_LEVELS.size() == 9, "the original PvP set must contain maps 13-21")
	menu._show_level_select("singleplayer")
	await get_tree().process_frame
	var solo_preview_buttons := _buttons_with_icons(menu.modal_layer)
	_check(solo_preview_buttons.size() == GameState.SINGLEPLAYER_LEVELS.size(), "single-player selector does not contain exactly eight campaign cards")
	menu._close_modal()
	await get_tree().process_frame
	menu._show_level_select("multiplayer")
	await get_tree().process_frame
	# Counted by their sector number rather than by a thumbnail: the original UI
	# had no icon table for the retired PvP maps (it asked vUI[3] for a frame
	# that does not exist), so these cards deliberately carry no picture.
	var multiplayer_preview_buttons := _level_cards(menu.modal_layer, GameState.MULTIPLAYER_LEVELS)
	_check(multiplayer_preview_buttons.size() == GameState.MULTIPLAYER_LEVELS.size(), "multiplayer selector does not contain exactly nine original PvP arena cards")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("RESTORATION_TEST_PASS weapons=47 armory_icons=47 solo_cards=%d multiplayer_cards=%d" % [solo_preview_buttons.size(), multiplayer_preview_buttons.size()])
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _buttons_with_text(node: Node, token: String) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and token in (node as Button).text:
		result.append(node as Button)
	for child in node.get_children():
		result.append_array(_buttons_with_text(child, token))
	return result

func _level_cards(node: Node, levels: Array) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button:
		var text := (node as Button).text
		for level_number: int in levels:
			if text.begins_with("%02d
" % level_number):
				result.append(node as Button)
				break
	for child in node.get_children():
		result.append_array(_level_cards(child, levels))
	return result

func _buttons_with_icons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and (node as Button).icon != null:
		result.append(node as Button)
	for child in node.get_children():
		result.append_array(_buttons_with_icons(child))
	return result

func _store_weapon_buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button:
		var button := node as Button
		# Category buttons now use the recovered Unity atlas icons too. Weapon
		# cards carry their catalog key as metadata, so count those explicitly.
		if button.icon != null and str(button.get_meta("item_key", "")).begins_with("gun"):
			result.append(button)
	for child in node.get_children():
		result.append_array(_store_weapon_buttons(child))
	return result
