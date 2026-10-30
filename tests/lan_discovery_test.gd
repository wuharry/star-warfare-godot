extends Node

const Discovery = preload("res://scripts/network/lan_discovery.gd")
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var host := Discovery.new()
	var client := Discovery.new()
	add_child(host)
	add_child(client)
	var room := {"mode": "VS_FFA", "level": 13, "players": 1, "max_players": 4, "name": "LOCAL TEST"}
	var port := 26000 + randi_range(0, 10000)
	check(host.advertise(room, 24597, port) == OK, "LAN host failed to bind")
	check(client.browse("127.0.0.1", port) == OK, "LAN browser failed to bind")
	await get_tree().create_timer(0.4).timeout
	var discovered := client.get_rooms()
	check(discovered.size() == 1, "UDP query did not find the LAN room")
	if discovered.size() == 1:
		check(discovered[0].address == "127.0.0.1" and discovered[0].port == 24597, "Discovery used an advertised address rather than packet source")
		check(discovered[0].mode == "VS_FFA" and discovered[0].players == 1, "Room metadata was corrupted")
	room.players = 2
	host.advertise(room, 24597, port)
	client.refresh()
	await get_tree().create_timer(0.35).timeout
	discovered = client.get_rooms()
	check(discovered.size() == 1 and discovered[0].players == 2, "Room refresh duplicated or failed to update")

	var fake := PacketPeerUDP.new()
	check(fake.bind(0) == OK, "Invalid-packet fixture failed to bind")
	fake.set_dest_address("127.0.0.1", client.browser.get_local_port())
	var packet := {"magic": Discovery.MAGIC, "version": Discovery.PROTOCOL,
		"kind": "room", "nonce": "wrong", "room": room}
	packet.room = room.duplicate()
	packet.room.port = 24599
	fake.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await get_tree().create_timer(0.1).timeout
	check(client.get_rooms().size() == 1, "Unsolicited response bypassed nonce check")
	packet.nonce = client.query_nonce
	packet.room.players = 1000
	fake.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await get_tree().create_timer(0.1).timeout
	check(client.get_rooms().size() == 1, "Malformed occupancy was accepted")
	check(Discovery._decode("x".repeat(1025).to_utf8_buffer()).is_empty(), "Oversized UDP message was accepted")
	check(Discovery._clean_room({"mode": "VS_FFA", "level": 13, "players": NAN, "max_players": 4}, 24597).is_empty(), "NaN occupancy was accepted")
	check(Discovery._clean_room({"mode": "VS_FFA", "level": 1, "players": 1, "max_players": 4}, 24597).is_empty(), "Wrong mode/map combination was accepted")
	host.stop_advertising()
	for key: String in client.rooms:
		client.rooms[key].seen_at = Time.get_ticks_msec() - Discovery.ROOM_TTL_MS - 1
	client._process(0.0)
	check(client.get_rooms().is_empty(), "Closed room did not expire")
	fake.close()
	host.free()
	client.free()
	print("LAN_DISCOVERY_TEST_%s query=refresh=nonce=validation=expiry" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
