extends Node
## Match inventory refers to the session roster, so rebuilding a world cannot
## replenish a used bag cell. It never writes another peer's local profile.

var PROPS: Dictionary = {}
var peer_id := 0
var profile: Dictionary = {}


func configure(id: int, validated_profile: Dictionary) -> void:
	peer_id = id
	profile = validated_profile
	PROPS = GameState.PROPS


func get_package_slots() -> Array:
	return profile.get("package_slots", []).duplicate()


func get_prop_count(key: String) -> int:
	return maxi(0, int(profile.get("prop_counts", {}).get(key, 0)))


func consume_package_prop(index: int) -> bool:
	if not NetworkSession.is_host() or NetworkSession.phase != "playing":
		return false
	if not NetworkSession.roster.has(peer_id):
		return false
	var slots := get_package_slots()
	if index < 0 or index >= slots.size():
		return false
	var key := str(slots[index])
	if not PROPS.has(key) or get_prop_count(key) <= 0:
		return false
	slots[index] = ""
	profile.package_slots = slots
	profile.prop_counts[key] = get_prop_count(key) - 1
	var used: Array = profile.get("used_slots", []).duplicate(true)
	used.append({"generation": NetworkSession.generation, "index": index, "key": key})
	profile.used_slots = used
	NetworkSession.roster[peer_id].package_slots = slots.duplicate()
	NetworkSession.roster[peer_id].prop_counts = profile.prop_counts.duplicate()
	NetworkSession.roster[peer_id].used_slots = used.duplicate(true)
	return true


func snapshot() -> Dictionary:
	return {"slots": get_package_slots(), "counts": profile.get("prop_counts", {}).duplicate(),
		"used_slots": profile.get("used_slots", []).duplicate(true)}


func apply_snapshot(state: Dictionary) -> void:
	if NetworkSession.is_host():
		return
	profile.package_slots = state.get("slots", []).duplicate()
	profile.prop_counts = state.get("counts", {}).duplicate()
	profile.used_slots = state.get("used_slots", []).duplicate(true)


static func persist_local_consumption(original_index: int, key: String) -> bool:
	# A confirmed use is a debt for an item, not for a mutable bag position.
	# After a failed save the player may leave and rearrange the package.
	if not GameState.PROPS.has(key) or GameState.get_prop_count(key) <= 0:
		return false
	var slots := GameState.get_package_slots()
	var index := original_index
	if index < 0 or index >= slots.size() or slots[index] != key:
		index = slots.find(key)
	if index >= 0:
		return GameState.consume_package_prop(index)
	# The used copy is now in storage. Saving its quantity directly keeps every
	# currently equipped cell intact, even when the bag has no free space.
	var previous := GameState.get_prop_count(key)
	GameState.owned_props[key] = previous - 1
	if not GameState._save():
		GameState.owned_props[key] = previous
		return false
	GameState.store_changed.emit()
	return true


static func retry_pending_consumptions() -> bool:
	# Session host/join must call this BEFORE profile_from_local; otherwise the
	# new host roster could advertise a copy just paid for by a pending receipt.
	var pending: Dictionary = NetworkSession.get_meta("pending_prop_consumptions", {})
	var receipts: Dictionary = NetworkSession.get_meta("consumed_actions", {})
	for receipt_id: String in pending.keys():
		if receipts.has(receipt_id):
			pending.erase(receipt_id)
			continue
		var record: Dictionary = pending[receipt_id]
		if not persist_local_consumption(int(record.index), str(record.key)):
			NetworkSession.status = "Could not save a consumed battle item. Retrying; further item use is blocked."
			continue
		receipts[receipt_id] = true
		pending.erase(receipt_id)
	NetworkSession.set_meta("consumed_actions", receipts)
	NetworkSession.set_meta("pending_prop_consumptions", pending)
	return pending.is_empty()
