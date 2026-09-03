extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MOUSE WEAPON CYCLE TEST: " + message)

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	var player := world.player
	player.weapon_order.assign(["gun00", "gun01", "gun02"])
	player.equip_weapon("gun01", false)
	player.camera_distance = 3.2

	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	player._unhandled_input(wheel_up)
	_check(player.current_weapon_id == "gun00", "wheel up did not select the previous weapon")
	_check(is_equal_approx(player.camera_distance, 3.2), "wheel up still changes camera distance")

	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	player._unhandled_input(wheel_down)
	_check(player.current_weapon_id == "gun01", "wheel down did not select the next weapon")
	_check(is_equal_approx(player.camera_distance, 3.2), "wheel down still changes camera distance")

	world.completed = true
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("MOUSE_WEAPON_CYCLE_TEST_PASS up=previous down=next camera=unchanged")
		get_tree().quit(0)
	else:
		print("MOUSE_WEAPON_CYCLE_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)
