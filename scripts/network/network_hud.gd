extends CanvasLayer
const Rules = preload("res://scripts/core/match_rules.gd")
var world: Node3D
var root: Control
var status: Label
var health: Label
var objective: Label
var scoreboard: Label
var overlay: PanelContainer
var result_label: Label
var resume_button: Button
var rematch_button: Button
var retry_button: Button
var refresh_left := 0.0
const ITEM_KEYS := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_COMMA]
var skill_buttons: Dictionary = {}
var item_buttons: Dictionary = {}
var skill_order: Array[int] = []
var action_panel: VBoxContainer
var item_grid: GridContainer
var item_signature := ""
var action_status: Label
var buff_status: Label
var was_dead := false

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	status = _label(Vector2(20, 16), 19)
	objective = _label(Vector2(20, 46), 17)
	health = _label(Vector2(20, 82), 17)
	scoreboard = _label(Vector2(20, 124), 16)
	scoreboard.visible = false
	var reticle := _label(Vector2.ZERO, 26)
	reticle.text = "+"
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.position -= Vector2(8, 17)
	var hint := _label(Vector2(20, 670), 14)
	hint.text = tr("WASD move · Mouse aim/fire · R reload · Shift dash · 1-4/wheel weapons · Tab scores · Esc menu")
	_build_actions()
	overlay = PanelContainer.new()
	overlay.position = Vector2(340, 180)
	overlay.custom_minimum_size = Vector2(600, 300)
	root.add_child(overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	overlay.add_child(box)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(580, 120)
	box.add_child(result_label)
	resume_button = _button(box, tr("RESUME"), func(): _show_menu(false))
	rematch_button = _button(box, tr("RETURN TO LOBBY (HOST)"), func(): NetworkSession.return_to_lobby())
	retry_button = _button(box, "RETRY SAVING REWARDS", func(): world.settle_local_result())
	_button(box, tr("LEAVE CONNECTION"), func(): NetworkSession.leave())
	overlay.hide()
	if bool(GameState.settings.show_touch_controls) or OS.has_feature("mobile"):
		_build_touch()

func _label(at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(label)
	return label

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = tr(caption)
	button.custom_minimum_size.y = 42
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_touch() -> void:
	var joystick := preload("res://scripts/ui/virtual_joystick.gd").new()
	joystick.position = Vector2(24, 485)
	joystick.size = Vector2(200, 200)
	joystick.vector_changed.connect(world.player.set_touch_move)
	root.add_child(joystick)
	for i in range(4):
		var button := preload("res://scripts/ui/touch_action_button.gd").new()
		button.caption = ["FIRE", "RELOAD", "DASH", "GUN"][i]
		button.position = Vector2(1120 - i * 105, 570)
		button.size = Vector2(100, 100)
		match i:
			0:
				button.pressed.connect(func(): world.player.set_touch_fire(true))
				button.released.connect(func(): world.player.set_touch_fire(false))
			1: button.pressed.connect(world.player.request_touch_reload)
			2: button.pressed.connect(world.player.request_touch_dash)
			3: button.pressed.connect(func(): world.player.cycle_weapon(1))
		root.add_child(button)
	var menu := Button.new()
	menu.text = tr("MENU")
	menu.position = Vector2(1160, 20)
	menu.size = Vector2(100, 48)
	menu.pressed.connect(func(): _show_menu(true))
	root.add_child(menu)

func _build_actions() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(917, 117)
	panel.custom_minimum_size.x = 346
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.035, 0.05, 0.88)
	style.border_color = Color(0.15, 0.45, 0.55, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	action_panel = VBoxContainer.new()
	action_panel.size.x = 330
	action_panel.add_theme_constant_override("separation", 5)
	panel.add_child(action_panel)
	var title := Label.new()
	title.text = tr("ARMOR POWERS")
	action_panel.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	action_panel.add_child(grid)
	var power: Node = world.player.armor_power_controller
	skill_order.assign(power.get_available_skill_indices())
	for slot in skill_order.size():
		var index := skill_order[slot]
		var button := _button(grid, "", func(): world.network_actions.request_action("skill", index))
		button.custom_minimum_size = Vector2(160, 48)
		button.add_theme_font_size_override("font_size", 11)
		var state: Dictionary = power.get_skill_state(index)
		button.tooltip_text = tr(str(state.summary))
		skill_buttons[index] = button
	title.visible = not skill_order.is_empty()
	var items_title := Label.new()
	items_title.text = tr("BATTLE ITEMS")
	action_panel.add_child(items_title)
	item_grid = GridContainer.new()
	item_grid.columns = 4
	action_panel.add_child(item_grid)
	buff_status = Label.new()
	buff_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buff_status.add_theme_font_size_override("font_size", 13)
	buff_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	action_panel.add_child(buff_status)
	action_status = Label.new()
	action_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_status.add_theme_font_size_override("font_size", 12)
	action_panel.add_child(action_status)
	_refresh_actions()

func _refresh_actions() -> void:
	var actor: Node = world.player
	var power: Node = actor.armor_power_controller
	for index: int in skill_buttons:
		var state: Dictionary = power.get_skill_state(index)
		var button: Button = skill_buttons[index]
		var timer := float(state.active_left) if bool(state.active) else float(state.cooldown_left)
		button.text = "F%d %s\n%s" % [skill_order.find(index) + 1, tr(str(state.name)), "%.1f" % timer if timer > 0.0 else tr("READY")]
		button.disabled = NetworkSession.phase != "playing" or not bool(state.ready)
		button.add_theme_color_override("font_disabled_color", Color(0.5, 1.0, 0.7) if bool(state.active) else Color(0.7, 0.75, 0.8))
	var items: Node = actor.battle_items
	var entries: Array = items.get_slots()
	var signature := str(items.inventory.get_package_slots())
	if signature != item_signature:
		item_signature = signature
		for child in item_grid.get_children():
			item_grid.remove_child(child)
			child.queue_free()
		item_buttons.clear()
		for entry: Dictionary in entries:
			var index := int(entry.slot)
			var button := _button(item_grid, OS.get_keycode_string(ITEM_KEYS[index]), func(): world.network_actions.request_action("prop", index))
			button.custom_minimum_size = Vector2(76, 48)
			button.icon = load("res://assets/ui/components/props_item_%02d.png" % int(entry.item.index))
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 30)
			button.tooltip_text = tr(str(entry.item.name)) + "\n" + tr(str(entry.item.description))
			item_buttons[index] = button
	var pending: Dictionary = NetworkSession.get_meta("pending_prop_consumptions", {})
	for index: int in item_buttons:
		item_buttons[index].disabled = NetworkSession.phase != "playing" or not items.can_use(index) or not pending.is_empty()
		var key := str(items.inventory.get_package_slots()[index])
		if GameState.PROPS.has(key) and GameState.PROPS[key].effects.has("revive_ratio"):
			var row: Dictionary = world.rules_view.get("players", {}).get(NetworkSession.local_id(), {})
			item_buttons[index].disabled = item_buttons[index].disabled or float(row.get("death_elapsed", 0.0)) < Rules.DEATH_SECONDS or float(row.get("revive_left", 0.0)) <= 0.0
	var buffs: Array[String] = []
	for key: String in items.active_effects:
		buffs.append("%s %.1fs" % [tr(str(GameState.PROPS[key].name)), float(items.active_effects[key].remaining)])
	buff_status.text = "\n".join(buffs)
	action_status.text = ""
	if not pending.is_empty(): action_status.text = tr("Could not save a consumed battle item. Retrying; further item use is blocked.")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_menu(not overlay.visible)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not overlay.visible and NetworkSession.phase == "playing":
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key >= KEY_F1 and key <= KEY_F10:
			var slot := key - KEY_F1
			if slot < skill_order.size(): world.network_actions.request_action("skill", skill_order[slot])
			get_viewport().set_input_as_handled()
		elif ITEM_KEYS.has(key):
			world.network_actions.request_action("prop", ITEM_KEYS.find(key))
			get_viewport().set_input_as_handled()

func _show_menu(show_menu: bool) -> void:
	var finished := NetworkSession.phase == "finished"
	overlay.visible = show_menu or finished
	resume_button.visible = not finished
	rematch_button.visible = finished and NetworkSession.is_host()
	retry_button.visible = finished and not world.local_receipt.is_empty() and not bool(world.settlement_result.get("saved", false))
	if not finished:
		result_label.text = tr("The match continues while this menu is open.") + "\n" + Rules.description(NetworkSession.room.mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if overlay.visible else Input.MOUSE_MODE_CAPTURED
	if overlay.visible:
		world.player.touch_fire = false
		resume_button.grab_focus()

func _process(delta: float) -> void:
	refresh_left -= delta
	if refresh_left > 0.0 or world.player == null:
		return
	refresh_left = 0.1
	_refresh_actions()
	var state: Dictionary = world.rules_view
	var mode := str(NetworkSession.room.mode)
	status.text = tr("IP / LAN • %s • %s • %02d:%02d") % [tr(mode), tr("HOST") if NetworkSession.is_host() else tr("CLIENT"), int(state.get("elapsed", 0.0)) / 60, int(state.get("elapsed", 0.0)) % 60]
	var rows: Dictionary = state.get("players", {})
	var id := NetworkSession.local_id()
	var me: Dictionary = rows.get(id, {})
	var p = world.player
	if p.dead and not was_dead: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not p.dead and was_dead and not overlay.visible: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	was_dead = p.dead
	health.text = tr("HP %d/%d  SHIELD %d  %s  %s%s") % [p.health, p.max_health, p.shield,
		tr(p.current_weapon.get("name", p.current_weapon_id)), tr("AMMO %d") % p._magazine_rounds() if p._uses_magazine() else tr("ENERGY %d") % p.energy,
		tr("  RELOADING %.1f") % p.reload_left if p.reload_left > 0.0 else ""]
	if p.dead:
		health.text = tr("DOWN • WATCH YOUR TEAM") if Rules.is_coop(mode) else tr("RESPAWN IN %.1f") % float(me.get("respawn", 0.0))
		if float(me.get("death_elapsed", 0.0)) < Rules.DEATH_SECONDS:
			health.text = tr("DEATH ANIMATION %.1fs") % (Rules.DEATH_SECONDS - float(me.get("death_elapsed", 0.0)))
		elif float(me.get("revive_left", 0.0)) > 0.0:
			health.text = tr("FIRST AID • %.1fs LEFT") % float(me.revive_left)
	var teams: Dictionary = state.get("team_scores", {0: 0, 1: 0})
	objective.text = tr("BLUE %d  :  RED %d  / %d") % [teams[0], teams[1], int(NetworkSession.room.score_limit)] if Rules.is_team(mode) else tr("SCORE %d / %d") % [int(me.get("score", 0)), int(NetworkSession.room.score_limit)]
	if mode in ["CTF_FFA", "CTF_TDM"]:
		var carrier := int(state.get("flag_carrier", 0))
		objective.text += tr(" • FLAG %s • %.1fs") % [str(rows.get(carrier, {}).get("name", tr("GOLD FLAG ON MAP"))), float(state.get("flag_left", 40.0))]
	elif mode == "VIP":
		objective.text += tr(" • VIP %s • %.1fs") % [str(rows.get(int(state.get("vip_id", 0)), {}).get("name", "")), float(state.get("vip_left", 50.0))]
	elif Rules.is_coop(mode):
		objective.text = tr("WAVE %d • ENEMIES %d") % [int(state.get("wave", 0)), world.enemies.size()]
		for enemy: Node in world.enemies.values():
			if is_instance_valid(enemy) and enemy.is_boss_enemy():
				objective.text += tr(" • BOSS %d/%d") % [enemy.health, enemy.max_health]
	scoreboard.visible = Input.is_physical_key_pressed(KEY_TAB) or bool(state.get("ended", false))
	var lines: Array[String] = [tr("PLAYER                  SCORE     K / D")]
	for peer_id: int in rows:
		var row: Dictionary = rows[peer_id]
		lines.append("%s  %s    %d      %d / %d" % [tr("BLUE") if int(row.team) == 0 else tr("RED"), row.name, row.score, row.kills, row.deaths])
	scoreboard.text = "\n".join(lines)
	if bool(state.get("ended", false)):
		var result: Dictionary = state.result
		var verdict := tr("DRAW") if bool(result.draw) else (tr("VICTORY") if id in result.winners else tr("DEFEAT"))
		var banked: Dictionary = world.settlement_result
		var reward_text := tr("REWARDS NOT SAVED - RETRY")
		if bool(banked.get("saved", false)):
			reward_text = tr("SAVED: %d CREDITS · %d XP · %d MITHRIL") % [int(banked.get("credits", 0)), int(banked.get("experience", 0)), int(banked.get("mithril", 0))]
		result_label.text = "%s • %s\n%s\n%s" % [verdict, tr(str(result.reason)), "\n".join(lines), reward_text]
		_show_menu(true)
