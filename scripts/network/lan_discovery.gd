extends Node
## Small UDP query/reply protocol for rooms on the same local network. It never
## supplies profile data and never acts as an Internet matchmaking service.
signal rooms_changed

const Rules = preload("res://scripts/core/match_rules.gd")
const DISCOVERY_PORT := 24598
const PROTOCOL := 1
const MAGIC := "star-warfare-godot-lan"
const ROOM_TTL_MS := 5000
const MAX_PACKET_BYTES := 1024
const MAX_ROOMS := 64
var advertisement: Dictionary = {}
var rooms: Dictionary = {}
var responder: PacketPeerUDP
var browser: PacketPeerUDP
var query_address := "255.255.255.255"
var query_port := DISCOVERY_PORT
var query_nonce := ""
var query_left := 0.0
var reply_times: Dictionary = {}


func advertise(room: Dictionary, game_port: int, discovery_port := DISCOVERY_PORT) -> Error:
	var clean := _clean_room(room, game_port)
	if clean.is_empty() or discovery_port < 1024 or discovery_port > 65535:
		return ERR_INVALID_PARAMETER
	if responder == null:
		responder = PacketPeerUDP.new()
		var error := responder.bind(discovery_port)
		if error != OK:
			responder = null
			return error
	advertisement = clean
	return OK


func stop_advertising() -> void:
	if responder != null:
		responder.close()
	responder = null
	advertisement.clear()
	reply_times.clear()


func browse(address := "255.255.255.255", discovery_port := DISCOVERY_PORT) -> Error:
	if not address.is_valid_ip_address() or discovery_port < 1024 or discovery_port > 65535:
		return ERR_INVALID_PARAMETER
	stop_browsing()
	browser = PacketPeerUDP.new()
	var error := browser.bind(0)
	if error != OK:
		browser = null
		return error
	browser.set_broadcast_enabled(true)
	query_address = address
	query_port = discovery_port
	query_nonce = Crypto.new().generate_random_bytes(12).hex_encode()
	refresh()
	return OK


func stop_browsing() -> void:
	if browser != null:
		browser.close()
	browser = null
	query_nonce = ""
	if not rooms.is_empty():
		rooms.clear()
		rooms_changed.emit()


func refresh() -> void:
	if browser == null:
		return
	query_left = 1.5
	if browser.set_dest_address(query_address, query_port) == OK:
		browser.put_packet(JSON.stringify({"magic": MAGIC, "version": PROTOCOL,
			"kind": "query", "nonce": query_nonce}).to_utf8_buffer())


func get_rooms() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Dictionary in rooms.values():
		result.append(room.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.key) < str(b.key))
	return result


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if responder != null:
		_read_queries(now)
	if browser != null:
		_read_rooms(now)
		query_left -= delta
		if query_left <= 0.0:
			refresh()
	var expired := false
	for key: String in rooms.keys():
		if now - int(rooms[key].seen_at) > ROOM_TTL_MS:
			rooms.erase(key)
			expired = true
	if expired:
		rooms_changed.emit()
	for address: String in reply_times.keys():
		if now - int(reply_times[address]) > ROOM_TTL_MS:
			reply_times.erase(address)


func _read_queries(now: int) -> void:
	# Bound work and response size so a noisy LAN cannot monopolize a frame.
	for packet_index in mini(32, responder.get_available_packet_count()):
		var packet := responder.get_packet()
		var address := responder.get_packet_ip()
		var port := responder.get_packet_port()
		var request := _decode(packet)
		if request.get("kind") != "query" or not _valid_nonce(request.get("nonce")):
			continue
		if now - int(reply_times.get(address, -1000)) < 250 or reply_times.size() >= MAX_ROOMS and not reply_times.has(address):
			continue
		reply_times[address] = now
		var response := {"magic": MAGIC, "version": PROTOCOL, "kind": "room",
			"nonce": request.nonce, "room": advertisement}
		if responder.set_dest_address(address, port) == OK:
			responder.put_packet(JSON.stringify(response).to_utf8_buffer())


func _read_rooms(now: int) -> void:
	for packet_index in mini(32, browser.get_available_packet_count()):
		var packet := browser.get_packet()
		var address := browser.get_packet_ip()
		var response := _decode(packet)
		if response.get("kind") != "room" or response.get("nonce") != query_nonce or not response.get("room") is Dictionary:
			continue
		var raw: Dictionary = response.room
		var port_value: Variant = raw.get("port")
		if not _whole_number(port_value, 1024, 65535):
			continue
		var room := _clean_room(raw, int(port_value))
		if room.is_empty():
			continue
		var key := "%s:%d" % [address, int(room.port)]
		if rooms.size() >= MAX_ROOMS and not rooms.has(key):
			continue
		room.merge({"key": key, "address": address, "seen_at": now})
		var changed := not rooms.has(key)
		if not changed:
			var previous: Dictionary = rooms[key].duplicate()
			previous.seen_at = now
			changed = previous != room
		rooms[key] = room
		if changed:
			rooms_changed.emit()


static func _decode(packet: PackedByteArray) -> Dictionary:
	if packet.size() > MAX_PACKET_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(packet.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	return data if data.get("magic") == MAGIC and data.get("version") == PROTOCOL else {}


static func _valid_nonce(value: Variant) -> bool:
	return value is String and value.length() == 24 and value.is_valid_hex_number(false)


static func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


static func _clean_room(raw: Dictionary, game_port: int) -> Dictionary:
	if raw.get("mode") not in Rules.MODES or game_port < 1024 or game_port > 65535:
		return {}
	for key: String in ["level", "players", "max_players"]:
		if not _whole_number(raw.get(key), 1, 21 if key == "level" else 8):
			return {}
	if int(raw.players) > int(raw.max_players):
		return {}
	var mode := str(raw.mode)
	if int(raw.level) not in (range(1, 9) if Rules.is_coop(mode) else range(13, 22)):
		return {}
	if not _whole_number(raw.get("boss_index", 0), 0, 5):
		return {}
	var label := str(raw.get("name", "PLAYER")).left(24).replace("\n", " ").replace("\r", " ")
	return {"mode": mode, "level": int(raw.level), "boss_index": int(raw.get("boss_index", 0)),
		"players": int(raw.players), "max_players": int(raw.max_players), "name": label, "port": game_port}


func _exit_tree() -> void:
	stop_advertising()
	stop_browsing()
