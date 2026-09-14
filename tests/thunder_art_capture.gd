extends Node3D

# Captures the actual WarfarePlayer / equip loader, not a concept billboard.
# Requires a real renderer; --headless cannot validate the rendered appearance.
# godot --path . --rendering-method gl_compatibility res://tests/thunder_art_capture.tscn
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const OUT := "res://test_output/thunder_runtime/"
const SIZE := Vector2i(1000, 1200)
const VIEWS := {
	"front": Vector3(0, 1.55, -4),
	"three_quarter": Vector3(2.5, 1.8, -2.8),
	"rear": Vector3(-2.5, 1.8, 2.8),
}
var viewport: SubViewport
var fixture: Node3D
var manifest: Array[Dictionary] = []
var failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) != OK:
		push_error("Cannot create Thunder capture output")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(400, 480)
	get_window().title = "Thunder runtime art verification"
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	fixture = Fixture.new()
	viewport.add_child(fixture)
	fixture.setup()
	# Fixture setup already selects an isolated test profile before its player.
	GameState.save_path = "user://thunder_art_capture_profile.json"
	for part in range(4):
		GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, 6)
	fixture.player._apply_recovered_armor_visibility()
	var visible_parts := 0
	for part: MeshInstance3D in fixture.player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if part.visible:
			visible_parts += 1
			if part.get_meta("armor_rework", "") != "thunder_mk1_helmet_v2":
				push_error("Capture loaded an old Thunder part: " + str(part.name))
				failed = true
	if visible_parts != 4 or failed:
		push_error("Capture requires four new Thunder runtime parts")
		fixture.cleanup()
		get_tree().quit(1)
		return
	fixture.label.hide()
	fixture.player.backpack_socket.hide()
	fixture.player.gun_socket.hide()
	fixture.player.left_gun_socket.hide()
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.fill.light_energy = 0.65
	for child in fixture.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 1.0
			child.shadow_enabled = true
		elif child is WorldEnvironment:
			child.environment.background_color = Color(0.055, 0.055, 0.06)
			child.environment.ambient_light_energy = 0.8
	fixture.player.recovered_animation_tree.active = false
	fixture.player._play_recovered_animation("idle_rifle", 0, true)
	fixture.player.recovered_animation_player.advance(0)
	fixture.player.recovered_skeleton.force_update_all_bone_transforms()
	for view: String in VIEWS:
		_frame(view, false)
		await _save("full_" + view, "idle_rifle", 0.0)
	for view: String in ["front", "three_quarter"]:
		_frame(view, true)
		await _save("helmet_" + view, "idle_rifle", 0.0)
	fixture.player.gun_socket.show()
	fixture.player.left_gun_socket.show()
	_frame("three_quarter", false)
	await _save("armed_idle", "idle_rifle", 0.0)
	for fraction: float in [0.2, 0.52, 0.85]:
		fixture.begin("gun00", 0, true)
		fixture.advance_to(fixture.duration * fraction)
		for view: String in ["three_quarter", "rear"]:
			_frame(view, false)
			await _save("reload_%02d_%s" % [roundi(fraction * 100), view], "gun00_reload_variant_0_moving", fixture.elapsed)
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	var file := FileAccess.open(OUT + "capture_manifest.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write Thunder capture manifest")
		failed = true
	else:
		file.store_string(JSON.stringify({
			"status": "FAIL" if failed else "CAPTURED_REQUIRES_VISUAL_REVIEW",
			"renderer": RenderingServer.get_current_rendering_method(),
			"viewport": [SIZE.x, SIZE.y],
			"scene": "res://assets/armors/thunder/thunder.scn",
			"runtime_loader": "WarfarePlayer._apply_recovered_armor_visibility",
			"revision": "thunder_mk1_helmet_v2",
			"frames": manifest,
		}, "\t"))
		file.close()
	print("THUNDER_ART_CAPTURE_%s images=%d viewport=1000x1200" % ["FAIL" if failed else "PASS", manifest.size()])
	get_tree().quit(1 if failed else 0)


func _frame(view: String, close: bool) -> void:
	fixture.view_camera.size = 0.95 if close else 2.3
	fixture.view_camera.position = VIEWS[view]
	fixture.view_camera.look_at(Vector3(0, 1.57 if close else 1.0, 0))
	fixture.fill.position = fixture.view_camera.position


func _save(stem: String, pose: String, elapsed: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# macOS may stop drawing an occluded root window. The capture owns its
	# SubViewport and can explicitly draw it without waiting on desktop focus.
	RenderingServer.force_draw(false)
	var screenshot := viewport.get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_size() != SIZE:
		push_error("Invalid Thunder capture dimensions: " + stem)
		failed = true
		return
	if screenshot.save_png(ProjectSettings.globalize_path(OUT + stem + ".png")) != OK:
		push_error("Cannot save Thunder capture: " + stem)
		failed = true
		return
	manifest.append({"file": stem + ".png", "width": SIZE.x, "height": SIZE.y, "pose": pose, "time": elapsed})
