extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("RELOAD SYSTEM TEST: " + message)

func _run() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	var player := world.player
	player.set_physics_process(false)

	var cases := {
		"gun00": {"style": "rifle", "capacity": 30, "drops": true},
		"gun35": {"style": "sniper", "capacity": 5, "drops": true},
		"gun06": {"style": "shotgun_shell", "capacity": 6, "drops": false},
		"gun11": {"style": "rocket", "capacity": 1, "drops": true},
		"gun14": {"style": "grenade_drum", "capacity": 4, "drops": true},
	}
	var styles: Dictionary = {}
	for weapon_id: String in cases:
		var expected: Dictionary = cases[weapon_id]
		player.equip_weapon(weapon_id, false)
		_check(str(player.current_weapon.resource_model) == "magazine", "%s has no magazine resource model" % weapon_id)
		_check(str(player.current_weapon.reload_style) == str(expected.style), "%s uses the wrong reload style" % weapon_id)
		styles[str(player.current_weapon.reload_style)] = true
		_check(player._magazine_rounds() == int(expected.capacity), "%s did not start with a full magazine" % weapon_id)
		player.shot_cooldown = 0.0
		var energy_before := player.energy
		player._try_fire()
		_check(player._magazine_rounds() == int(expected.capacity) - 1, "%s did not consume one magazine round" % weapon_id)
		_check(player.energy < energy_before, "%s stopped consuming the recovered Energy value" % weapon_id)

		player._set_magazine_rounds(0)
		var debris_before := get_tree().get_nodes_in_group("reload_debris").size()
		player._start_reload()
		_check(player.reload_left > 0.0, "%s did not begin reloading" % weapon_id)
		player._update_reload(player.reload_total * 0.50)
		var debris_after := get_tree().get_nodes_in_group("reload_debris").size()
		_check(debris_after == debris_before + (1 if bool(expected.drops) else 0), "%s spawned the wrong dropped reload prop count" % weapon_id)
		_check(is_instance_valid(player.reload_hand_prop), "%s did not put a fresh reload prop in motion" % weapon_id)
		player._update_reload(player.reload_total)
		if str(expected.style) == "shotgun_shell":
			_check(player._magazine_rounds() == 1, "shotgun did not insert exactly one shell per cycle")
			_check(player.reload_left > 0.0, "shotgun did not continue its per-shell reload")
			player._cancel_reload()
		else:
			_check(player._magazine_rounds() == int(expected.capacity), "%s did not refill its magazine" % weapon_id)
			_check(is_zero_approx(player.reload_left), "%s reload did not finish" % weapon_id)

	_check(styles.size() == 5, "the vertical slice does not expose five distinct reload actions")

	player.equip_weapon("gun06", false)
	player._set_magazine_rounds(2)
	player.shot_cooldown = 0.0
	player._start_reload()
	player.touch_fire_started = true
	player._handle_weapon_input()
	_check(is_zero_approx(player.reload_left), "shotgun fire did not interrupt per-shell reload")
	_check(player._magazine_rounds() == 1, "shotgun interrupt did not immediately fire the loaded shell")

	player.equip_weapon("gun00", false)
	player._set_magazine_rounds(0)
	player._start_reload()
	player.equip_weapon("gun35", false)
	_check(is_zero_approx(player.reload_left), "weapon switching did not cancel reload")

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.15).timeout
	if failures.is_empty():
		print("RELOAD_SYSTEM_TEST_PASS weapons=5 styles=5 infinite_reserve=true physical_drops=true")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
