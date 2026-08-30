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
	menu._close_modal()
	await get_tree().process_frame
	menu._show_level_select()
	await get_tree().process_frame
	var preview_buttons := _buttons_with_icons(menu.modal_layer)
	_check(preview_buttons.size() == GameState.CAMPAIGN_LEVELS.size(), "level selector is missing original preview cards")
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("RESTORATION_TEST_PASS weapons=47 armory_icons=47 level_cards=%d" % preview_buttons.size())
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
		if button.icon != null and not button.tooltip_text.is_empty():
			result.append(button)
	for child in node.get_children():
		result.append_array(_store_weapon_buttons(child))
	return result
