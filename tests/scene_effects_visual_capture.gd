extends Node3D

const OUTPUT_ROOT := "res://test_output/armor_lighting/effects"
var failures: Array[String] = []
var captures: Array[Dictionary] = []


class CaptureWorld:
	extends WarfareGameWorld

	func _ready() -> void:
		# Exercise the real environment, restored stage, and effects attachment
		# without creating unrelated combat/HUD timers in a visual fixture.
		level_data = GameState.get_level_data(GameState.selected_level)
		arena_size = float(level_data.arena_size)
		completed = true
		GameState.apply_viewport_quality()
		_load_stage_metadata()
		_build_environment()
		_build_arena()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Scene effects capture requires the GL Compatibility renderer")
		get_tree().quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	GameState.settings.quality = "high"
	GameState.settings.show_touch_controls = false
	get_window().size = Vector2i(1280, 720)
	# These two source configurations cover all eight authored emitters: the
	# snow parameters and material are identical in Levels 8, 13, and 21.
	for level_number in [3, 8]:
		GameState.selected_level = level_number
		var world := CaptureWorld.new()
		add_child(world)
		var effects := world.get_node_or_null("OriginalUnitySceneEffects") as Node3D
		if effects == null:
			failures.append("Level %d did not attach the recovered scene effects" % level_number)
			world.free()
			continue
		var camera := Camera3D.new()
		camera.fov = 55.0
		camera.far = 1000.0
		add_child(camera)
		if level_number == 3:
			var glow := effects.get_node("sc_03_fire1_230") as CPUParticles3D
			camera.position = glow.global_position + Vector3(0.0, 2.0, 30.0)
			camera.look_at(glow.global_position, Vector3.UP)
		else:
			camera.position = Vector3(0.0, 18.0, 38.0)
			camera.look_at(Vector3(0.0, 18.0, -12.0), Vector3.UP)
		camera.make_current()
		# Only the camera moves. Wait for natural emission; do not relocate,
		# enlarge, prewarm, or increase the density of the source particles.
		await get_tree().create_timer(1.2).timeout
		await get_tree().process_frame
		await get_tree().process_frame
		var rendered := get_viewport().get_texture().get_image()
		var rendered_path := "%s/level_%02d_particles.png" % [OUTPUT_ROOT, level_number]
		if rendered.save_png(rendered_path) != OK:
			failures.append("Could not save " + rendered_path)
		# A same-camera reference proves the particles actually contributed
		# pixels; it also makes black rectangles around alpha edges reviewable.
		effects.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
		var reference := get_viewport().get_texture().get_image()
		var reference_path := "%s/level_%02d_reference.png" % [OUTPUT_ROOT, level_number]
		if reference.save_png(reference_path) != OK:
			failures.append("Could not save " + reference_path)
		var changed_pixels := _changed_pixels(rendered, reference)
		if changed_pixels == 0:
			failures.append("Level %d particles did not affect the rendered image" % level_number)
		captures.append({
			"level": level_number,
			"image": rendered_path,
			"reference": reference_path,
			"camera_position": [camera.position.x, camera.position.y, camera.position.z],
			"source_emitters": effects.get_child_count(),
			"changed_pixels": changed_pixels,
			"viewport": [rendered.get_width(), rendered.get_height()],
			"renderer": RenderingServer.get_current_rendering_method(),
			"wait_seconds": 1.2,
		})
		camera.free()
		world.free()
		await get_tree().process_frame
	var report := FileAccess.open(OUTPUT_ROOT.path_join("capture_report.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"captures": captures, "failures": failures}, "\t") + "\n")
		report.close()
	if failures.is_empty():
		print("SCENE_EFFECTS_VISUAL_CAPTURE_PASS " + JSON.stringify(captures))
		get_tree().quit(0)
	else:
		push_error("SCENE_EFFECTS_VISUAL_CAPTURE_FAIL: " + ", ".join(failures))
		get_tree().quit(1)


func _changed_pixels(rendered: Image, reference: Image) -> int:
	rendered.convert(Image.FORMAT_RGBA8)
	reference.convert(Image.FORMAT_RGBA8)
	var actual := rendered.get_data()
	var expected := reference.get_data()
	var changed := 0
	for offset in range(0, actual.size(), 4):
		if absi(int(actual[offset]) - int(expected[offset])) + absi(int(actual[offset + 1]) - int(expected[offset + 1])) + absi(int(actual[offset + 2]) - int(expected[offset + 2])) > 6:
			changed += 1
	return changed
