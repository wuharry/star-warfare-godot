extends Node

# Exercise the input/physics path, not just the configured interval or rate.
var failures: Array[String] = []
var shot_frames: Array[int] = []
var pulse_count := 0
var world: WarfareGameWorld
var player: WarfarePlayer

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("WEAPON TRIGGER TEST: " + message)

func _on_shot(_weapon: Dictionary) -> void:
	shot_frames.append(Engine.get_physics_frames())

func _on_audio(node: Node) -> void:
	if node is AudioStreamPlayer3D and node.stream and "/weapon_shots/" in node.stream.resource_path:
		pulse_count += 1

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_level = 1
	world = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(world)
	world.completed = true
	player = world.player
	player.armor_skills = {}
	player.shot_fired.connect(_on_shot)
	AudioDirector.child_entered_tree.connect(_on_audio)
	# Keep the firing lane away from scenery; target behaviour is irrelevant.
	player.global_position = Vector3(0, 100, 0)
	player.gravity = 0.0
	player.velocity = Vector3.ZERO
	var counts: Dictionary = {}
	for weapon_id in ["gun00", "gun40", "gun24", "gun20"]:
		player.equip_weapon(weapon_id, false)
		player.shot_cooldown = 0.0
		player.energy = player.max_energy
		shot_frames.clear()
		pulse_count = 0
		Input.action_press("fire")
		for frame in range(120):
			await get_tree().physics_frame
		Input.action_release("fire")
		await get_tree().physics_frame
		counts[weapon_id] = shot_frames.size()
		_check(shot_frames.size() > 2, weapon_id + " did not sustain held fire")
		var nominal := player._current_shot_interval()
		var tick := 1.0 / float(Engine.physics_ticks_per_second)
		for i in range(1, shot_frames.size()):
			var interval := float(shot_frames[i] - shot_frames[i - 1]) * tick
			_check(interval >= nominal - 0.001 and interval <= nominal + tick + 0.001,
				"%s actual %.3f s differs from configured %.3f s" % [weapon_id, interval, nominal])
		if weapon_id == "gun24":
			_check(pulse_count == shot_frames.size(), "machinegun did not play exactly one pulse per shot")
			_check(not AudioDirector.is_playing("player_weapon_loop"), "machinegun still plays the long loop")
		print("HELD_FIRE %s shots=%d pulse_voices=%d" % [weapon_id, shot_frames.size(), pulse_count])
	_check(counts.gun40 > counts.gun00 and counts.gun00 > counts.gun20, "held-fire counts do not reflect weapon cadence")

	# An energy-starved continuous beam must stop rather than sounding loaded.
	player.equip_weapon("gun21", false)
	player.energy = float(player.current_weapon.energy)
	player.shot_cooldown = 0.0
	Input.action_press("fire")
	for frame in range(2):
		await get_tree().physics_frame
	_check(player.weapon_audio_active, "loaded beam did not start its continuous audio")
	for frame in range(28):
		await get_tree().physics_frame
	_check(not player.weapon_audio_active and not AudioDirector.is_playing("player_weapon_loop"), "empty-energy beam kept its loop playing")
	Input.action_release("fire")
	await get_tree().physics_frame

	# Reload and recoil must not write competing transforms.
	player.equip_weapon("gun00", false)
	player.energy = player.max_energy
	player.shot_cooldown = 0.0
	player._try_fire()
	player._start_reload()
	_check(not player.weapon_recoil_tween.is_running(), "recoil kept running during reload")
	player._cancel_reload()

	# Only test fixtures carry non-neutral movement data until originals exist.
	for weapon in GameState.WEAPONS.values():
		_check(is_equal_approx(float(weapon.move_speed_multiplier), 1.0), "unverified movement penalty shipped")
	player.equip_weapon("gun00", false)
	player.move_speed = 8.2
	Input.action_press("move_forward")
	for frame in range(40):
		await get_tree().physics_frame
	var base_speed := Vector2(player.velocity.x, player.velocity.z).length()
	player.current_weapon.move_speed_multiplier = 0.5
	for frame in range(40):
		await get_tree().physics_frame
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - base_speed * 0.5) < 0.03,
		"held-weapon movement multiplier is not connected")
	player.equip_weapon("gun40", false)
	for frame in range(40):
		await get_tree().physics_frame
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - base_speed) < 0.03,
		"weapon swap retained the previous movement penalty")
	Input.action_release("move_forward")
	AudioDirector.child_entered_tree.disconnect(_on_audio)
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("WEAPON_TRIGGER_TEST_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
