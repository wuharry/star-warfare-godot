extends Node
## Transport lives in NetworkSession. This adapter owns combat validation and
## translates confirmed actions into the existing props/powers implementations.

const Inventory = preload("res://scripts/network/network_inventory.gd")
const Power = preload("res://scripts/network/network_armor_power.gd")
const Items = preload("res://scripts/game/battle_items.gd")

var world: Node3D
var _handled: Dictionary = {}
var _pending: Dictionary = {}
var _save_retry_left := 0.0


func configure(combat_world: Node3D) -> void:
	world = combat_world
	_retry_consumptions()
	if not NetworkSession.action_requested.is_connected(_on_action_requested):
		NetworkSession.action_requested.connect(_on_action_requested)
	if not NetworkSession.action_ack.is_connected(_on_action_ack):
		NetworkSession.action_ack.connect(_on_action_ack)


func setup_actor(actor: Node3D) -> void:
	var id := int(actor.peer_id)
	if not NetworkSession.roster.has(id) or is_instance_valid(actor.battle_items):
		return
	var inventory := Inventory.new()
	inventory.name = "NetworkInventory"
	inventory.configure(id, NetworkSession.roster[id])
	actor.add_child(inventory)
	var items := Items.new()
	items.name = "BattleItems"
	items.configure(actor, inventory)
	actor.battle_items = items
	actor.add_child(items)
	# Only the adapter advances host buff timers. Replicas receive the host state.
	items.set_process(false)
	var power := Power.new()
	power.name = "ArmorPower"
	power.actions = self
	power.configure(actor, world)
	actor.set_armor_power_controller(power)
	actor.add_child(power)


func _process(delta: float) -> void:
	_save_retry_left -= delta
	if _save_retry_left <= 0.0:
		_save_retry_left = 1.0
		_retry_consumptions()
	if not is_instance_valid(world):
		return
	var playing: bool = NetworkSession.phase == "playing" and not world.rules.ended
	for actor: Node in world.actors.values():
		if not is_instance_valid(actor) or not is_instance_valid(actor.battle_items):
			continue
		actor.battle_items.enabled = playing
		if playing and NetworkSession.is_host():
			actor.battle_items.advance(delta)


func request_action(kind: String, index: int) -> int:
	if kind == "armor": kind = "skill"
	if NetworkSession.phase != "playing" or not is_instance_valid(world):
		return -1
	var id := NetworkSession.local_id()
	if not world.actors.has(id) or kind not in ["prop", "skill"]:
		return -1
	var actor: Node = world.actors[id]
	var key := ""
	if kind == "prop":
		if not NetworkSession.get_meta("pending_prop_consumptions", {}).is_empty():
			return -1
		var slots: Array = actor.battle_items.inventory.get_package_slots()
		if index < 0 or index >= slots.size() or not GameState.PROPS.has(str(slots[index])):
			return -1
		key = str(slots[index])
	elif index < 0 or index >= Power.SKILL_KEYS.size():
		return -1
	# Register before submit_action: the host's local acknowledgement is synchronous.
	var sequence := NetworkSession.action_sequence + 1
	_pending[sequence] = {"kind": kind, "index": index, "key": key,
		"room_id": NetworkSession.room_id, "generation": NetworkSession.generation}
	var submitted := NetworkSession.submit_action(kind, index)
	if submitted < 0: _pending.erase(sequence)
	return submitted


func _on_action_requested(id: int, sequence: int, kind: String, index: int) -> void:
	if not NetworkSession.is_host() or not is_instance_valid(world):
		return
	if NetworkSession.phase != "playing" or world.rules.ended or not NetworkSession.roster.has(id):
		return
	if not world.actors.has(id) or sequence <= int(_handled.get(id, 0)):
		return
	_handled[id] = sequence
	var actor: Node = world.actors[id]
	var accepted := false
	var key := ""
	if is_instance_valid(actor) and int(actor.peer_id) == id and world.rules.players.has(id):
		if kind == "skill" and not actor.dead and bool(world.rules.players[id].alive):
			accepted = actor.armor_power_controller.activate_authoritative(index)
		elif kind == "prop" and _can_use_prop(actor, index):
			key = str(actor.battle_items.inventory.get_package_slots()[index])
			accepted = actor.battle_items.use_slot(index)
	NetworkSession.send_action_ack(id, {"sequence": sequence, "kind": kind,
		"index": index, "key": key, "accepted": accepted})


func _can_use_prop(actor: Node, index: int) -> bool:
	if not is_instance_valid(actor.battle_items) or not actor.battle_items.can_use(index):
		return false
	var items: Node = actor.battle_items
	var key := str(items.inventory.get_package_slots()[index])
	var effects: Dictionary = GameState.PROPS[key].effects
	var row: Dictionary = world.rules.players.get(int(actor.peer_id), {})
	if effects.has("revive_ratio"):
		# The host rules own the source death-animation/aid window, including
		# the final co-op player and paid PvP revival. A completed respawn closes
		# that window before a late item request can spend another copy.
		return bool(world.rules.can_revive(int(actor.peer_id)))
	return not actor.dead and bool(row.get("alive", false))


func _on_action_ack(data: Dictionary) -> void:
	if str(data.get("room_id", "")) != NetworkSession.room_id or int(data.get("generation", -1)) != NetworkSession.generation:
		return
	var sequence := int(data.get("sequence", -1))
	if not _pending.has(sequence):
		return
	var pending: Dictionary = _pending[sequence]
	if str(data.get("kind", "")) != pending.kind or int(data.get("index", -1)) != pending.index:
		return
	if pending.room_id != NetworkSession.room_id or int(pending.generation) != NetworkSession.generation:
		return
	if not bool(data.get("accepted", false)) or pending.kind != "prop":
		_pending.erase(sequence)
		return
	if str(data.get("key", "")) != pending.key:
		return
	# The session outlives the scene; duplicate receipts cannot spend a second
	# bag cell even if an adapter is rebuilt during this same match.
	_pending.erase(sequence)
	_queue_consumption({"generation": pending.generation, "index": pending.index, "key": pending.key})
	_retry_consumptions()


func _queue_consumption(record: Dictionary) -> void:
	var receipt_id := "%s:%d:%d" % [NetworkSession.room_id, int(record.generation), int(record.index)]
	var receipts: Dictionary = NetworkSession.get_meta("consumed_actions", {})
	if receipts.has(receipt_id): return
	var pending: Dictionary = NetworkSession.get_meta("pending_prop_consumptions", {})
	pending[receipt_id] = record.duplicate()
	NetworkSession.set_meta("pending_prop_consumptions", pending)


func _retry_consumptions() -> void:
	NetworkSession.retry_pending_consumptions()


func snapshot_actor(actor: Node) -> Dictionary:
	if not is_instance_valid(actor.battle_items) or not is_instance_valid(actor.armor_power_controller):
		return {}
	var items: Dictionary = actor.battle_items.inventory.snapshot()
	items.effects = actor.battle_items.active_effects.duplicate(true)
	return {"items": items, "power": actor.armor_power_controller.snapshot(), "move_speed": actor.move_speed}


func apply_actor_state(actor: Node, state: Dictionary) -> void:
	if NetworkSession.is_host() or state.is_empty() or not is_instance_valid(actor.battle_items):
		return
	var items: Dictionary = state.get("items", {})
	actor.battle_items.inventory.apply_snapshot(items)
	actor.battle_items.active_effects = items.get("effects", {}).duplicate(true)
	actor.battle_items.changed.emit()
	actor.move_speed = float(state.get("move_speed", actor.move_speed))
	actor.armor_power_controller.apply_snapshot(state.get("power", {}))
	if int(actor.peer_id) == NetworkSession.local_id():
		for record: Dictionary in items.get("used_slots", []):
			if int(record.get("generation", -1)) >= 0 and int(record.generation) <= NetworkSession.generation:
				_queue_consumption(record)
		_retry_consumptions()
