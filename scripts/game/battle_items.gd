class_name WarfareBattleItems
extends Node

signal changed
signal used(slot_index: int, prop_key: String)

var actor: Node
var inventory: Node
var enabled := true
var active_effects: Dictionary = {}


func configure(controlled_actor: Node, inventory_state: Node) -> void:
	actor = controlled_actor
	inventory = inventory_state


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	var expired := false
	for prop_key: String in active_effects.keys():
		active_effects[prop_key].remaining = maxf(0.0, float(active_effects[prop_key].remaining) - maxf(0.0, delta))
		if float(active_effects[prop_key].remaining) <= 0.0:
			active_effects.erase(prop_key)
			expired = true
	if expired:
		changed.emit()


func get_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(inventory):
		return result
	var slots: Array = inventory.get_package_slots()
	for slot_index in slots.size():
		var prop_key := str(slots[slot_index])
		if inventory.PROPS.has(prop_key):
			result.append({"slot": slot_index, "key": prop_key, "item": inventory.PROPS[prop_key]})
	return result


func can_use(slot_index: int) -> bool:
	if not enabled or not is_instance_valid(actor) or not is_instance_valid(inventory):
		return false
	var slots: Array = inventory.get_package_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var key := str(slots[slot_index])
	if not inventory.PROPS.has(key) or inventory.get_prop_count(key) <= 0:
		return false
	var effects: Dictionary = inventory.PROPS[key].effects
	if effects.has("revive_ratio"):
		return actor.dead
	if actor.dead:
		return false
	return not effects.has("heal") or float(actor.health) < float(actor.max_health)


func use_slot(slot_index: int) -> bool:
	if not can_use(slot_index) or (is_inside_tree() and get_tree().paused):
		return false
	var prop_key := str(inventory.get_package_slots()[slot_index])
	var item: Dictionary = inventory.PROPS[prop_key]
	if not inventory.consume_package_prop(slot_index):
		return false
	apply_item(item)
	used.emit(slot_index, prop_key)
	changed.emit()
	return true


func apply_item(item: Dictionary) -> void:
	var effects: Dictionary = item.effects
	if effects.has("revive_ratio"):
		actor.revive(float(effects.revive_ratio))
	elif effects.has("heal"):
		actor.restore("health", float(effects.heal))
	else:
		# Unity AssistItem combines the strongest boost of each kind, rather
		# than multiplying repeated consumables. Reusing one refreshes its time.
		active_effects[str(item.key)] = {"effects": effects.duplicate(), "remaining": float(item.duration)}


func get_bonus(effect_key: String) -> float:
	var result := 0.0
	for active: Dictionary in active_effects.values():
		result = maxf(result, float(active.effects.get(effect_key, 0.0)))
	return result


func has_revival_item() -> bool:
	for entry: Dictionary in get_slots():
		if entry.item.effects.has("revive_ratio"):
			return true
	return false
