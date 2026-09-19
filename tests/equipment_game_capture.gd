extends Node3D

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const OUT := "res://test_output/equipment_refinement/preview/"
const CAPTURE_PROFILE := "user://equipment_game_capture_profile.json"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var real_save_path: String = GameState.save_path
	var real_save_hash := FileAccess.get_sha256(real_save_path) if FileAccess.file_exists(real_save_path) else "MISSING"
	GameState.save_path = CAPTURE_PROFILE
	get_window().size = Vector2i(800, 900)
	get_window().content_scale_size = Vector2i(800, 900)
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	# The fixture selects its own test profile; keep subsequent saves in this
	# capture's isolated profile, including the live game worlds below.
	GameState.save_path = CAPTURE_PROFILE
	fixture.label.hide()
	for sample in [[9, "gun00"], [14, "gun11"], [21, "gun01"], [28, "gun26"]]:
		_set_armor(sample[0])
		fixture.player._apply_recovered_armor_visibility()
		fixture.begin(sample[1], 0, true)
		fixture.advance_to(fixture.duration * .52)
		for view in ["front", "side", "rear"]:
			fixture.set_view(view)
			await _save("motion_%02d_%s_%s" % [sample[0], sample[1], view])
	fixture.cleanup()
	GameState.save_path = CAPTURE_PROFILE
	fixture.queue_free()
	await get_tree().process_frame
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	GameState.settings.show_touch_controls = false
	for level in [1, 3]:
		for sample in [[9, "gun00"], [21, "gun11"], [28, "gun26"]]:
			GameState.selected_level = level
			GameState.selected_weapon = sample[1]
			GameState.battle_weapons.assign([sample[1]])
			_set_armor(sample[0])
			var world := (load("res://scenes/game.tscn") as PackedScene).instantiate()
			add_child(world)
			for tick in 12: await get_tree().process_frame
			await _save("game_%d_%02d_%s" % [level, sample[0], sample[1]])
			world.queue_free()
			await get_tree().process_frame
	var final_save_hash := FileAccess.get_sha256(real_save_path) if FileAccess.file_exists(real_save_path) else "MISSING"
	if final_save_hash != real_save_hash:
		push_error("Real save changed during equipment game capture; external contents left untouched")
		get_tree().quit(1)
		return
	print("EQUIPMENT_GAME_CAPTURE_PASS motion=12 gameplay=6 save_unchanged=true")
	get_tree().quit()

func _set_armor(id: int) -> void:
	for part in 4:
		GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, id)

func _save(stem: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(OUT + stem + ".png") == OK)
