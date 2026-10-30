extends Node
## Two-process regression: repeated rejected registrations cannot extend the
## disconnect deadline; a subsequent valid client can still use the room.
var role := "host"
var port := 24750
var elapsed := 0.0
var reject_started := 0.0
var send_left := 0.0
var rejects_sent := 0
var disconnected := false
var rejoining := false
var saw_rejected_peer := false
var done := false

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	NetworkSession.auto_change_scene = false
	if role == "host":
		NetworkSession.multiplayer.peer_disconnected.connect(func(_id): saw_rejected_peer = true)
		var error := NetworkSession.host_room({"mode": "Boss", "max_players": 1}, port)
		if error != OK: _finish(false, "host open failed")
		if not NetworkSession.configure_room({"mode": "VS_FFA", "max_players": 8}):
			_finish(false, "capacity change failed")
	else:
		# The attacker deliberately ignores _reject by replacing the transport
		# callback, not by patching production validation or sending a fake roster.
		NetworkSession.set_script(preload("res://tests/network_rejecting_peer.gd"))
		NetworkSession.auto_change_scene = false
		NetworkSession.multiplayer.connected_to_server.disconnect(NetworkSession._connected)
		NetworkSession.multiplayer.server_disconnected.connect(func():
			if not rejoining: disconnected = true
		)
		NetworkSession.join_room("127.0.0.1", port)

func _process(delta: float) -> void:
	if done: return
	elapsed += delta
	if elapsed > 12.0:
		_finish(false, "timeout")
		return
	if role == "host":
		if saw_rejected_peer and NetworkSession.roster.size() == 2:
			set_process(false)
			await get_tree().create_timer(1.0).timeout
			_finish(true, "rejected peer evicted; valid client joined after room capacity increased")
		return
	if not rejoining and NetworkSession.peer != null and NetworkSession.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if reject_started == 0.0: reject_started = elapsed
		send_left -= delta
		if send_left <= 0.0:
			send_left = 0.1
			rejects_sent += 1
			NetworkSession._register.rpc_id(1, -1, {})
	# _reject normally makes an honest client leave; this adversarial fixture
	# suppresses that call with an RPC script override installed below.
	if disconnected and not rejoining:
		if rejects_sent < 2 or elapsed - reject_started > 1.5:
			_finish(false, "deadline extended or repeated flood not exercised")
			return
		rejoining = true
		NetworkSession.multiplayer.connected_to_server.connect(NetworkSession._connected)
		NetworkSession.join_room("127.0.0.1", port)
	elif rejoining and NetworkSession.phase == "lobby" and NetworkSession.roster.size() == 2:
		set_process(false)
		await get_tree().create_timer(0.2).timeout
		_finish(true, "registration flood disconnected within bounded deadline; rejoin confirmed")

func _finish(success: bool, message: String) -> void:
	if done: return
	done = true
	print("NETWORK_TRANSPORT_%s role=%s %s" % ["PASS" if success else "FAIL", role, message])
	NetworkSession.leave()
	get_tree().quit(0 if success else 1)
