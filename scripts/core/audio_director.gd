extends Node

const AUDIO_ROOT := "res://assets/original/audio/"

const UI_EVENTS := {
	"accept": "menu/click_ok.wav",
	"back": "menu/click_back.wav",
	"cancel": "menu/back_cancle.wav",
	"pause": "menu/pause.wav",
	"resume": "menu/pause_back.wav",
	"switch": "menu/switch_items.wav",
	"mount_weapon": "menu/mount_weapon.wav",
	"mount_gear": "menu/mount_gears.wav",
	"rank_up": "menu/rankup.wav",
	"money": "pickup/moneyup.wav"
}

var _keyed_players: Dictionary = {}

func play_ui(event_name: String, volume_db := 0.0) -> void:
	var relative_path := str(UI_EVENTS.get(event_name, "menu/click_ok.wav"))
	play_2d(relative_path, volume_db)

func play_2d(relative_path: String, volume_db := 0.0, pitch := 1.0, key := "") -> AudioStreamPlayer:
	var stream := _load_stream(relative_path)
	if stream == null:
		return null
	if not key.is_empty():
		stop(key)
	var player := AudioStreamPlayer.new()
	player.name = "Audio_%s" % _safe_name(relative_path)
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	add_child(player)
	if not key.is_empty():
		_keyed_players[key] = player
	player.finished.connect(_release_player.bind(player, key))
	player.play()
	return player

func play_3d(relative_path: String, world_position: Vector3, volume_db := 0.0, pitch := 1.0, key := "") -> AudioStreamPlayer3D:
	var stream := _load_stream(relative_path)
	if stream == null:
		return null
	if not key.is_empty():
		stop(key)
	var player := AudioStreamPlayer3D.new()
	player.name = "Audio3D_%s" % _safe_name(relative_path)
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = 100.0
	player.unit_size = 3.0
	add_child(player)
	player.global_position = world_position
	if not key.is_empty():
		_keyed_players[key] = player
	player.finished.connect(_release_player.bind(player, key))
	player.play()
	return player

func play_loop_3d(relative_path: String, world_position: Vector3, key: String, volume_db := 0.0) -> AudioStreamPlayer3D:
	if is_playing(key):
		var active := _keyed_players[key] as AudioStreamPlayer3D
		active.global_position = world_position
		return active
	var source := _load_stream(relative_path)
	if source == null:
		return null
	var stream := source.duplicate(true)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	var player := AudioStreamPlayer3D.new()
	player.name = "AudioLoop_%s" % _safe_name(key)
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 100.0
	player.unit_size = 3.0
	add_child(player)
	player.global_position = world_position
	_keyed_players[key] = player
	player.play()
	return player

func stop(key: String) -> void:
	var player: Node = _keyed_players.get(key)
	_keyed_players.erase(key)
	if not is_instance_valid(player):
		return
	if player.has_method("stop"):
		player.stop()
	player.queue_free()

func stop_all_sfx() -> void:
	_keyed_players.clear()
	for player in get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
			player.stop()
			player.queue_free()

func is_playing(key: String) -> bool:
	var player: Node = _keyed_players.get(key)
	return is_instance_valid(player) and bool(player.get("playing"))

func _load_stream(relative_path: String) -> AudioStream:
	var path := AUDIO_ROOT + relative_path.replace("\\", "/")
	if not ResourceLoader.exists(path):
		push_warning("Recovered audio is missing: %s" % path)
		return null
	return load(path) as AudioStream

func _release_player(player: Node, key: String) -> void:
	if not key.is_empty() and _keyed_players.get(key) == player:
		_keyed_players.erase(key)
	if is_instance_valid(player):
		player.queue_free()

func _safe_name(value: String) -> String:
	return value.get_file().get_basename().replace(" ", "_").replace("-", "_")
