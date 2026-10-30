extends Node3D

const StateScript = preload("res://scripts/core/game_state.gd")
const PlayerScript = preload("res://scripts/game/player.gd")
const ItemsScript = preload("res://scripts/game/battle_items.gd")
var failures: Array[String] = []
var state: Node
var actor: WarfarePlayer
var items: WarfareBattleItems
const SAVE := "user://battle_items_behavior_test.json"


func _ready() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


func equip_item(key: String) -> int:
	state.owned_props[key] = 2
	state.package_slots.assign(["gun00", key])
	state.battle_weapons.assign(["gun00"])
	return 1


func _run() -> void:
	_cleanup()
	state = StateScript.new()
	state.save_path = SAVE
	add_child(state)
	actor = PlayerScript.new()
	add_child(actor)
	actor.set_physics_process(false)
	actor.armor_skills = {}
	actor.max_health = 10000.0
	actor.health = 10000.0
	actor.shield = 0.0
	items = ItemsScript.new()
	items.configure(actor, state)
	actor.battle_items = items
	actor.add_child(items)
	items.set_process(false)
	var slot := equip_item("prop00")
	check(not items.use_slot(slot), "Full HP must not waste a health item")
	check(state.get_prop_count("prop00") == 2, "Rejected use changed inventory")
	actor.health = 100.0
	check(items.use_slot(slot), "Equipped health item was not usable")
	check(is_equal_approx(actor.health, 900.0), "Minor health must restore source 800 HP")
	check(state.get_prop_count("prop00") == 1 and state.get_package_slots()[slot] == "", "Use must consume one copy and clear its bag slot")
	check(not items.use_slot(slot), "Empty slot allowed a duplicate use")
	var loaded := StateScript.new()
	loaded.save_path = SAVE
	add_child(loaded)
	check(loaded.get_prop_count("prop00") == 1 and loaded.get_package_slots()[slot] == "", "Consumed item returned after reload")
	loaded.free()
	for key: String in ["prop00", "prop01", "prop02", "prop03", "prop04", "prop10"]:
		actor.max_health = 50000.0
		actor.health = 100.0
		equip_item(key)
		var expected := minf(actor.max_health, 100.0 + float(state.PROPS[key].effects.heal))
		check(items.use_slot(slot) and actor.health == expected, "Health item amount incorrect: " + key)
	actor.max_health = 10000.0

	actor.health = 100.0
	equip_item("prop04")
	check(items.use_slot(slot) and actor.health == actor.max_health, "Full health did not fill HP")
	equip_item("prop07")
	check(items.use_slot(slot) and items.get_bonus("speed_boost") == 2.0, "Booster must add source two units of speed")
	var damage_before := actor._current_weapon_damage()
	equip_item("prop09")
	check(items.use_slot(slot), "Hyper clip was not usable")
	check(is_equal_approx(actor._current_weapon_damage(), damage_before * 2.0), "Hyper clip must double damage, not refill ammo")
	items.advance(25.0)
	equip_item("prop09")
	items.use_slot(slot)
	check(is_equal_approx(actor._current_weapon_damage(), damage_before * 2.0), "Repeated assist stacked its strength")
	items.advance(6.0)
	check(items.get_bonus("speed_boost") == 0.0 and items.get_bonus("attack_boost") == 1.0, "Independent buff expiration/refresh is incorrect")
	equip_item("prop08")
	items.use_slot(slot)
	actor.health = 5000.0
	actor.take_damage(100.0)
	check(is_equal_approx(actor.health, 4950.0), "Force shield must reduce damage by 50 percent")
	items.advance(31.0)
	check(items.active_effects.is_empty() and is_equal_approx(actor._current_weapon_damage(), damage_before), "Expired assists still affect combat")

	equip_item("prop05")
	check(not items.use_slot(slot), "A living player used a revival kit")
	actor._die()
	actor.health = 0.0
	actor.camera_pitch = -0.65
	actor.pitch_node.rotation.x = actor.camera_pitch
	var magazine_before := actor._magazine_rounds()
	check(items.has_revival_item() and items.use_slot(slot), "Dead player could not use small first aid")
	check(not actor.dead and actor.health == 3000.0, "Small first aid must revive at 30 percent maximum HP")
	check(actor.camera_pitch == 0.0 and actor.pitch_node.rotation.x == 0.0, "Revival did not reset the rendered camera pitch")
	check(actor._magazine_rounds() == magazine_before, "Revival refilled the magazine")
	equip_item("prop06")
	actor._die()
	actor.health = 0.0
	check(items.use_slot(slot) and actor.health == actor.max_health, "Big first aid must fully revive")

	equip_item("prop00")
	actor.health = 100.0
	get_tree().paused = true
	check(not items.use_slot(slot), "Paused battle consumed an item")
	get_tree().paused = false
	state.save_path = "user://missing_battle_items_test_directory/profile.json"
	check(not items.use_slot(slot), "Failed persistence still granted an item effect")
	check(actor.health == 100.0 and state.get_prop_count("prop00") == 2 and state.get_package_slots()[slot] == "prop00", "Failed persistence did not roll inventory back")
	var original_outfit: Dictionary = state.equipped_armor.duplicate()
	state.owned_armor.append("armor_head_01")
	var preview := original_outfit.duplicate()
	preview.head = "armor_head_01"
	preview.gun = "gun00"
	check(not state.apply_equipment_preview(preview), "Failed outfit save was reported as successful")
	check(state.equipped_armor == original_outfit, "Failed package save left a partially applied outfit")
	state.save_path = SAVE
	items.enabled = false
	check(not items.use_slot(slot), "Finished battle consumed an item")
	actor.free()
	state.free()
	_cleanup()
	if failures.is_empty():
		print("BATTLE_ITEMS_TEST_PASS healing=6 revival=2 assists=3 save_rollback=pause=expiry=PASS")
	get_tree().quit(0 if failures.is_empty() else 1)


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE + suffix))
