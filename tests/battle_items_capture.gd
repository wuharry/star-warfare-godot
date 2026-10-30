extends Node

const ShellScript = preload("res://scripts/ui/unity_equipment_shell.gd")
var failures: Array[String] = []

class CaptureWorld extends WarfareGameWorld:
	func _begin_level() -> void:
		pass


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.save_path = "user://battle_items_capture_profile.json"
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	GameState.owned_weapons.assign(["gun00"])
	for key: String in GameState.get_armor_ids(4):
		var item: Dictionary = GameState.ARMOR_ITEMS[key]
		if int(item.get("capacity", 0)) >= 8:
			GameState.owned_armor.append(key)
			GameState.equipped_armor.bag = key
			break
	GameState.owned_props = {"prop00": 3, "prop05": 2, "prop06": 2, "prop07": 2, "prop08": 2, "prop09": 2}
	GameState.package_slots.assign(["gun00", "prop00", "prop05"])
	GameState.settings.show_touch_controls = false
	var world := CaptureWorld.new()
	add_child(world)
	world.current_wave = 1
	world.alive_enemies = 1 # Keep the quiet capture scene from ending on revive.
	world.player.health = world.player.max_health * 0.35
	world.player.health_changed.emit(world.player.health, world.player.shield)
	for key: String in ["prop07", "prop08", "prop09"]:
		world.player.battle_items.apply_item(GameState.PROPS[key])
	await _capture("battle_items_hud")
	world.player._die()
	world.player.health = 0.0
	world.hud.toggle_pause()
	if world.hud.revival_overlay.visible or not world.hud.pause_overlay.visible:
		failures.append("Pause did not take priority over revival")
	world.hud.toggle_pause()
	if not world.hud.revival_overlay.visible or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		failures.append("Resume hid the revival cursor or overlay")
	await _capture("battle_items_revival")
	if not world.player.battle_items.use_slot(2) or world.player.dead or world.completed:
		failures.append("Revival failed in live world")
	if world.hud.revival_overlay != null or world.revival_left != 0.0:
		failures.append("Revival overlay/countdown remained after use")
	world.completed = true
	world.queue_free()
	await get_tree().process_frame
	var shell := ShellScript.new()
	shell.setup("customize", false)
	add_child(shell)
	shell._select_desktop_section("package")
	await _capture("battle_items_package")
	shell.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := GameState.save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("BATTLE_ITEMS_CAPTURE_PASS viewport=1280x720 renderer=gl_compatibility world_revival=PASS")
	else:
		push_error(str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture(filename: String) -> void:
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.save_png("res://test_output/%s.png" % filename) != OK:
		failures.append("Capture failed: " + filename)
