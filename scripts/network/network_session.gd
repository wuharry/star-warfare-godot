extends Node
## ENet direct IP transport; intentionally no account, relay or matchmaking API.
signal lobby_changed
signal match_started
signal session_closed(reason: String)
signal player_left(id: int)
signal command_received(id: int, command: Dictionary)
signal snapshot_received(state: Dictionary)
signal effect_received(effect: Dictionary)
signal world_activated
signal progress_event(event: Dictionary)
signal action_requested(peer_id: int, sequence: int, kind: String, index: int)
signal action_ack(data: Dictionary)

const Rules = preload("res://scripts/core/match_rules.gd")
const PROTOCOL := 1
const DEFAULT_PORT := 24597
const MAX_COMMAND_AGE_MS := 300

var roster: Dictionary = {}
var room: Dictionary = Rules.normalized_config({})
var phase := "offline"
var status := "Direct IP / LAN connection. Original official matchmaking is not restored."
var peer: ENetMultiplayerPeer
var local_profile: Dictionary = {}
var loaded: Dictionary = {}
var last_sequences: Dictionary = {}
var command_times: Dictionary = {}
var countdown := 0.0
var auto_change_scene := true
var generation := 0
var room_id := ""
var boss_clears: Dictionary = {}
var last_snapshot: Dictionary = {}
var snapshot_sequence := 0
var receiving_sequence := -1
var receiving_parts: Dictionary = {}
var action_sequence := 0
var action_sequences: Dictionary = {}
var action_times: Dictionary = {}
var reopen_lobby_on_menu := false
var pending_registrations: Dictionary = {}
var lan_advertiser: Node
var game_port := DEFAULT_PORT
var discovery_status := ""
var inventory_retry_left := 0.0

func _ready() -> void:
	lan_advertiser = preload("res://scripts/network/lan_discovery.gd").new()
	add_child(lan_advertiser)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): leave("Connection failed. Check the IP, UDP port and firewall."))
	multiplayer.server_disconnected.connect(func(): leave("The host disconnected. This direct connection has ended."))
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.peer_connected.connect(_peer_connected)

func _process(delta: float) -> void:
	if phase in ["offline", "lobby"]:
		inventory_retry_left -= delta
		if inventory_retry_left <= 0.0:
			inventory_retry_left = 1.0
			retry_pending_consumptions()
	if is_host():
		for id: int in pending_registrations.keys():
			if Time.get_ticks_msec() >= int(pending_registrations[id]):
				pending_registrations.erase(id)
				peer.disconnect_peer(id)
	if phase in ["connecting", "loading"]:
		countdown -= delta
		if countdown <= 0.0:
			leave("Connection or loading timed out. Left the room.")

func is_host() -> bool:
	return peer != null and multiplayer.is_server()

func local_id() -> int:
	return multiplayer.get_unique_id() if peer != null else 0

func profile_from_local() -> Dictionary:
	retry_pending_consumptions()
	return {"name": str(GameState.settings.get("nickname", "PLAYER")),
		"weapons": GameState.battle_weapons.duplicate(), "outfit": GameState.equipped_armor.duplicate(),
		"weapon_levels": GameState.weapon_levels.duplicate(), "armor_levels": GameState.armor_set_levels.duplicate(),
		"package_slots": GameState.get_package_slots(), "prop_counts": GameState.owned_props.duplicate()}

func retry_pending_consumptions() -> bool:
	var pending: Dictionary = get_meta("pending_prop_consumptions", {})
	if pending.is_empty(): return true
	var inventory_script = load("res://scripts/network/network_inventory.gd")
	var saved: bool = inventory_script.retry_pending_consumptions()
	lobby_changed.emit()
	return saved

func _clean_profile(raw: Dictionary) -> Dictionary:
	var weapons: Array[String] = []
	var requested: Variant = raw.get("weapons", [])
	if requested is Array:
		for key: Variant in requested.slice(0, 8):
			if key is String and GameState.WEAPONS.has(key) and not weapons.has(key):
				weapons.append(key)
	if weapons.is_empty():
		weapons.append("gun00")
	var outfit := {}
	var supplied: Variant = raw.get("outfit", {})
	for part: String in ["head", "body", "arms", "legs", "bag"]:
		var fallback := GameState.ArmorCatalogData.item_key(GameState.ArmorCatalogData.PART_KEYS.find(part), 0)
		var key := str(supplied.get(part, fallback)) if supplied is Dictionary else fallback
		if not GameState.ARMOR_ITEMS.has(key) or str(GameState.ARMOR_ITEMS[key].part_key) != part:
			key = fallback
		outfit[part] = key
	var capacity := clampi(int(GameState.ARMOR_ITEMS[outfit.bag].get("bag_slots", 4)), 1, 8)
	weapons.resize(mini(weapons.size(), capacity))
	var weapon_levels := {}
	var supplied_levels: Variant = raw.get("weapon_levels", {})
	for key: String in weapons:
		var value: Variant = supplied_levels.get(key, 1) if supplied_levels is Dictionary else 1
		weapon_levels[key] = clampi(value, 1, GameState.Source.WEAPON_UPGRADE_ROWS.size()) if value is int else 1
	var armor_levels := {}
	var supplied_armor: Variant = raw.get("armor_levels", {})
	for key: String in outfit.values():
		var set_id := str(GameState.ARMOR_ITEMS[key].set_id)
		var value: Variant = supplied_armor.get(set_id, 1) if supplied_armor is Dictionary else 1
		armor_levels[set_id] = clampi(value, 1, GameState.UpgradeRules.COM_MAX_LEVEL) if value is int else 1
	var slots: Array[String] = []
	slots.resize(capacity)
	var raw_slots: Variant = raw.get("package_slots", [])
	var raw_counts: Variant = raw.get("prop_counts", {})
	var counts := {}
	var seen_weapons: Array[String] = []
	if raw_slots is Array and raw_counts is Dictionary:
		for index in mini(capacity, raw_slots.size()):
			var key := str(raw_slots[index])
			if weapons.has(key) and not seen_weapons.has(key):
				slots[index] = key
				seen_weapons.append(key)
			elif GameState.PROPS.has(key):
				var value: Variant = raw_counts.get(key, 0)
				var count := clampi(value, 0, 99) if value is int else 0
				if slots.count(key) < count:
					slots[index] = key
					counts[key] = count
	# Weapons occupy the same bag cells as props. Preserve original slot IDs for
	# local consume acknowledgements, but never admit a loadout over capacity.
	for key: String in weapons:
		if slots.has(key): continue
		var empty := slots.find("")
		if empty < 0:
			for index in range(slots.size() - 1, -1, -1):
				if GameState.PROPS.has(slots[index]):
					empty = index
					break
		if empty >= 0: slots[empty] = key
	return {"name": str(raw.get("name", "PLAYER")).strip_edges().replace("\n", " ").left(24),
		"weapons": weapons, "outfit": outfit, "weapon_levels": weapon_levels, "armor_levels": armor_levels,
		"package_slots": slots, "prop_counts": counts, "team": 0, "ready": false}

func host_room(config: Dictionary, port := DEFAULT_PORT, profile: Dictionary = {}) -> Error:
	if phase != "offline" or port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	var had_debt: bool = not get_meta("pending_prop_consumptions", {}).is_empty()
	if not retry_pending_consumptions(): return ERR_FILE_CANT_WRITE
	if had_debt and not profile.is_empty():
		profile.package_slots = GameState.get_package_slots()
		profile.prop_counts = GameState.owned_props.duplicate()
	room = Rules.normalized_config(config)
	peer = ENetMultiplayerPeer.new()
	# Capacity may change in the lobby; logical limits are enforced on register.
	var error := peer.create_server(port, 8)
	if error != OK:
		peer = null
		status = tr("Cannot host: the UDP port may already be in use (%d).") % error
		lobby_changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	game_port = port
	phase = "lobby"
	room_id = Crypto.new().generate_random_bytes(16).hex_encode()
	boss_clears.clear()
	local_profile = _clean_profile(profile_from_local() if profile.is_empty() else profile)
	roster = {1: local_profile.duplicate(true)}
	status = tr("HOST • UDP %d • Share your local LAN IP with friends") % port
	_publish_lobby()
	return OK

func join_room(address: String, port := DEFAULT_PORT, profile: Dictionary = {}) -> Error:
	if phase != "offline" or not address.is_valid_ip_address() or port < 1024 or port > 65535:
		status = "Enter a valid IP and UDP port (1024-65535)."
		lobby_changed.emit()
		return ERR_INVALID_PARAMETER
	var had_debt: bool = not get_meta("pending_prop_consumptions", {}).is_empty()
	if not retry_pending_consumptions(): return ERR_FILE_CANT_WRITE
	if had_debt and not profile.is_empty():
		profile.package_slots = GameState.get_package_slots()
		profile.prop_counts = GameState.owned_props.duplicate()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		peer = null
		return error
	multiplayer.multiplayer_peer = peer
	local_profile = _clean_profile(profile_from_local() if profile.is_empty() else profile)
	phase = "connecting"
	countdown = 12.0
	status = tr("Connecting directly to %s:%d...") % [address, port]
	lobby_changed.emit()
	return OK

func _connected() -> void:
	_register.rpc_id(1, PROTOCOL, local_profile)

func _peer_connected(id: int) -> void:
	if not is_host(): return
	pending_registrations[id] = Time.get_ticks_msec() + 5000
	if phase != "lobby":
		_reject_peer(id, "The match has started. Wait for the host to return to the lobby.")

func _reject_peer(id: int, reason: String) -> void:
	_reject.rpc_id(id, reason)
	# Give the reliable explanation time to arrive, then reclaim the ENet slot.
	pending_registrations[id] = mini(int(pending_registrations.get(id, Time.get_ticks_msec() + 300)), Time.get_ticks_msec() + 300)

@rpc("any_peer", "call_remote", "reliable")
func _register(version: int, profile: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if phase != "lobby" or version != PROTOCOL or roster.size() >= int(room.max_players) or roster.has(id):
		_reject_peer(id, "Incompatible version, room full, or match already started.")
		return
	pending_registrations.erase(id)
	var clean := _clean_profile(profile)
	var teams := [0, 0]
	for row: Dictionary in roster.values():
		teams[int(row.team)] += 1
	clean.team = 0 if teams[0] <= teams[1] else 1
	roster[id] = clean
	_publish_lobby()

@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	leave(reason)

func configure_room(config: Dictionary) -> bool:
	if not is_host() or phase != "lobby":
		return false
	var next := Rules.normalized_config(config)
	if int(next.max_players) < roster.size():
		return false
	room = next
	for row: Dictionary in roster.values():
		row.ready = false
	_publish_lobby()
	return true

func set_ready(ready: bool, team: int) -> void:
	if phase != "lobby":
		return
	if is_host():
		_apply_ready(1, ready, team)
	else:
		_request_ready.rpc_id(1, ready, team)

@rpc("any_peer", "call_remote", "reliable")
func _request_ready(ready: bool, team: int) -> void:
	if is_host():
		_apply_ready(multiplayer.get_remote_sender_id(), ready, team)

func _apply_ready(id: int, ready: bool, team: int) -> void:
	if phase != "lobby" or not roster.has(id) or team not in [0, 1]:
		return
	var count := 0
	for other: int in roster:
		if other != id and int(roster[other].team) == team:
			count += 1
	if Rules.is_team(room.mode) and count >= 4:
		return
	roster[id].team = team
	roster[id].ready = ready
	_publish_lobby()

func start_problem() -> String:
	if not is_host() or phase != "lobby":
		return "Only the host can start a match."
	if roster.size() < 2 and not Rules.is_coop(room.mode):
		return "At least two connected players are required."
	var teams := {}
	for row: Dictionary in roster.values():
		if not row.ready:
			return "Waiting for every player to be ready."
		teams[int(row.team)] = true
	if Rules.is_team(room.mode) and teams.size() < 2:
		return "Both teams need players."
	return ""

func start_match() -> bool:
	if not start_problem().is_empty():
		return false
	generation += 1
	_begin.rpc(room, roster, generation, room_id)
	return true

func _publish_lobby() -> void:
	_update_advertisement()
	_lobby.rpc(room, roster)
	lobby_changed.emit()

func _update_advertisement() -> void:
	if not is_host() or phase != "lobby" or lan_advertiser == null: return
	var error: Error = lan_advertiser.advertise({"mode": room.mode, "level": room.level,
		"boss_index": room.boss_index, "players": roster.size(), "max_players": room.max_players,
		"name": room.room_name}, game_port)
	discovery_status = "" if error == OK else tr("LAN discovery unavailable; direct IP is still available.")

@rpc("authority", "call_remote", "reliable")
func _lobby(config: Dictionary, players: Dictionary) -> void:
	room = config
	roster = players
	phase = "lobby"
	status = "CONNECTED • Direct IP / LAN"
	lobby_changed.emit()

@rpc("authority", "call_local", "reliable")
func _begin(config: Dictionary, players: Dictionary, round_id: int, unique_room: String) -> void:
	lan_advertiser.stop_advertising()
	room = config
	roster = players
	generation = round_id
	room_id = unique_room
	phase = "loading"
	countdown = 90.0
	loaded.clear()
	last_sequences.clear()
	action_sequences.clear()
	action_times.clear()
	action_sequence = 0
	command_times.clear()
	last_snapshot.clear()
	receiving_sequence = -1
	receiving_parts.clear()
	match_started.emit()
	if auto_change_scene:
		get_tree().change_scene_to_file.call_deferred("res://scenes/network_game.tscn")

func mark_world_loaded() -> void:
	if is_host():
		_mark_loaded(1, generation)
	else:
		_world_loaded.rpc_id(1, generation)

@rpc("any_peer", "call_remote", "reliable")
func _world_loaded(round_id: int) -> void:
	if is_host():
		_mark_loaded(multiplayer.get_remote_sender_id(), round_id)

func _mark_loaded(id: int, round_id: int) -> void:
	if phase != "loading" or round_id != generation or not roster.has(id):
		return
	loaded[id] = true
	if loaded.size() == roster.size():
		_activate.rpc(generation)

@rpc("authority", "call_local", "reliable")
func _activate(round_id: int) -> void:
	if round_id == generation and phase == "loading":
		phase = "playing"
		world_activated.emit()

func submit_command(sequence: int, move: Vector2, aim: Vector2, buttons: int, slot: int) -> void:
	if phase != "playing":
		return
	if is_host():
		_accept_command(1, generation, sequence, move, aim, buttons, slot)
	else:
		_input_command.rpc_id(1, generation, sequence, move, aim, buttons, slot)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _input_command(round_id: int, sequence: int, move: Vector2, aim: Vector2, buttons: int, slot: int) -> void:
	if is_host():
		_accept_command(multiplayer.get_remote_sender_id(), round_id, sequence, move, aim, buttons, slot)

func _accept_command(id: int, round_id: int, sequence: int, move: Vector2, aim: Vector2, buttons: int, slot: int) -> void:
	if phase != "playing" or round_id != generation or not roster.has(id) or sequence <= int(last_sequences.get(id, -1)):
		return
	if not move.is_finite() or not aim.is_finite() or slot < 0 or slot >= roster[id].weapons.size():
		return
	last_sequences[id] = sequence
	command_times[id] = Time.get_ticks_msec()
	command_received.emit(id, {"move": move.limit_length(1.0),
		"aim": Vector2(wrapf(aim.x, -PI, PI), clampf(aim.y, -1.2, 1.2)),
		"buttons": buttons & 7, "slot": slot})

func command_is_current(id: int) -> bool:
	return Time.get_ticks_msec() - int(command_times.get(id, -1000)) < MAX_COMMAND_AGE_MS

func submit_action(kind: String, index: int) -> int:
	if phase != "playing": return -1
	action_sequence += 1
	if is_host():
		_accept_action(1, room_id, generation, action_sequence, kind, index)
	else:
		_action_request.rpc_id(1, room_id, generation, action_sequence, kind, index)
	return action_sequence

@rpc("any_peer", "call_remote", "reliable", 4)
func _action_request(unique_room: String, round_id: int, sequence: int, kind: String, index: int) -> void:
	if is_host():
		_accept_action(multiplayer.get_remote_sender_id(), unique_room, round_id, sequence, kind, index)

func _accept_action(id: int, unique_room: String, round_id: int, sequence: int, kind: String, index: int) -> void:
	if phase != "playing" or unique_room != room_id or round_id != generation or not roster.has(id): return
	if sequence <= int(action_sequences.get(id, 0)) or kind not in ["prop", "skill"]: return
	if index < 0 or index >= (10 if kind == "skill" else roster[id].package_slots.size()): return
	action_sequences[id] = sequence
	# Bound malicious action floods independently from held movement/fire input.
	var now := Time.get_ticks_msec()
	if now - int(action_times.get(id, -1000)) < 50:
		send_action_ack(id, {"sequence": sequence, "kind": kind, "index": index, "accepted": false})
		return
	action_times[id] = now
	action_requested.emit(id, sequence, kind, index)

func send_action_ack(id: int, data: Dictionary) -> void:
	if not is_host() or not roster.has(id): return
	var receipt := data.duplicate(true)
	receipt.room_id = room_id
	receipt.generation = generation
	if id == 1:
		_action_ack(room_id, generation, receipt)
	else:
		_action_ack.rpc_id(id, room_id, generation, receipt)

@rpc("authority", "call_remote", "reliable", 4)
func _action_ack(unique_room: String, round_id: int, data: Dictionary) -> void:
	if unique_room == room_id and round_id == generation and phase in ["playing", "finished"]:
		action_ack.emit(data)

func broadcast_snapshot(state: Dictionary, final := false) -> void:
	if not is_host() or phase not in ["playing", "finished"]:
		return
	if final:
		_final_state.rpc(generation, state)
	else:
		# Keep UDP messages below ENet's MTU, even with a full enemy wave.
		var payload := var_to_bytes(state).compress(FileAccess.COMPRESSION_DEFLATE)
		var count := ceili(float(payload.size()) / 1000.0)
		snapshot_sequence += 1
		for index in range(count):
			_state_part.rpc(generation, snapshot_sequence, index, count, payload.slice(index * 1000, (index + 1) * 1000))
	last_snapshot = state

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _state_part(round_id: int, sequence: int, index: int, count: int, payload: PackedByteArray) -> void:
	if round_id != generation or phase != "playing" or sequence < receiving_sequence:
		return
	if count < 1 or count > 64 or index < 0 or index >= count or payload.size() > 1000:
		return
	if sequence > receiving_sequence:
		receiving_sequence = sequence
		receiving_parts.clear()
	receiving_parts[index] = payload
	if receiving_parts.size() != count:
		return
	var combined := PackedByteArray()
	for part in range(count):
		if not receiving_parts.has(part):
			return
		combined.append_array(receiving_parts[part])
	var decoded: Variant = bytes_to_var(combined.decompress_dynamic(262144, FileAccess.COMPRESSION_DEFLATE))
	if decoded is Dictionary:
		last_snapshot = decoded
		snapshot_received.emit(decoded)
	receiving_parts.clear()

@rpc("authority", "call_local", "reliable")
func _final_state(round_id: int, state: Dictionary) -> void:
	if round_id == generation:
		phase = "finished"
		last_snapshot = state
		snapshot_received.emit(state)

func broadcast_effect(effect: Dictionary) -> void:
	if is_host() and phase == "playing":
		_effect.rpc(generation, effect)

func send_progress(id: int, event: Dictionary) -> void:
	if not is_host() or phase != "playing":
		return
	if id == 1:
		_progress_event(generation, event)
	elif roster.has(id):
		_progress_event.rpc_id(id, generation, event)

@rpc("authority", "call_remote", "reliable")
func _progress_event(round_id: int, event: Dictionary) -> void:
	if round_id == generation and phase == "playing":
		progress_event.emit(event)

@rpc("authority", "call_remote", "unreliable", 3)
func _effect(round_id: int, effect: Dictionary) -> void:
	if round_id == generation and phase == "playing":
		effect_received.emit(effect)

func _peer_left(id: int) -> void:
	pending_registrations.erase(id)
	if not is_host() or not roster.has(id):
		return
	roster.erase(id)
	loaded.erase(id)
	last_sequences.erase(id)
	command_times.erase(id)
	if phase == "lobby":
		_publish_lobby()
	elif phase == "loading":
		leave("A player disconnected while loading. Please create a new room.")
	else:
		player_left.emit(id)

func return_to_lobby() -> void:
	if is_host() and phase == "finished":
		_back_to_lobby.rpc(room, roster)

@rpc("authority", "call_local", "reliable")
func _back_to_lobby(config: Dictionary, players: Dictionary) -> void:
	room = config
	roster = players
	phase = "lobby"
	for row: Dictionary in roster.values():
		row.ready = false
	status = "Back in the lobby. Ready up for the next match."
	_update_advertisement()
	if auto_change_scene:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
	lobby_changed.emit()

func leave(reason := "Left the direct-connect room.") -> void:
	var in_game := phase in ["loading", "playing", "finished"]
	reopen_lobby_on_menu = in_game
	phase = "offline"
	if lan_advertiser != null: lan_advertiser.stop_advertising()
	discovery_status = ""
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	pending_registrations.clear()
	loaded.clear()
	last_sequences.clear()
	command_times.clear()
	last_snapshot.clear()
	status = reason
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	session_closed.emit(reason)
	lobby_changed.emit()
	if in_game and auto_change_scene:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
