extends "res://tests/reload_catalog_fixture.gd"

const OUTPUT := "res://test_output/reload_catalog"
const FPS := 20
const STAGES := {"idle": 0.0, "raise": 0.16, "extract": 0.21, "take": 0.40, "carry": 0.55, "align": 0.70, "seat": 0.83, "return": 0.94, "end": 1.0}

func _ready() -> void:
	setup()
	var directory := OUTPUT + "/captures"
	DirAccess.make_dir_recursive_absolute(directory)
	var args := OS.get_cmdline_user_args()
	var sequence := "--sequence" in args
	var walk := "--moving" in args
	var selected: Array[String] = []
	for arg in args:
		if arg.begins_with("--weapon="):
			selected.append(arg.trim_prefix("--weapon="))
	var manifest := {"fps": FPS, "renderer": RenderingServer.get_current_rendering_method(), "viewport": [get_viewport().size.x, get_viewport().size.y], "weapons": {}}
	for key: String in GameState.RELOAD_PROFILES:
		if not selected.is_empty() and key not in selected:
			continue
		var entry := {"name": GameState.WEAPONS[key].name, "profile": GameState.RELOAD_PROFILES[key], "variants": {}}
		for variant in range(int(GameState.RELOAD_PROFILES[key].reload_variants)):
			begin(key, variant, walk)
			var variant_key := char(97 + variant)
			var records: Array[Dictionary] = []
			var samples: Array[Dictionary] = []
			for stage: String in STAGES:
				samples.append({"time": duration * float(STAGES[stage]), "key": stage})
			if sequence:
				for frame in range(ceili(duration * FPS) + 1):
					samples.append({"time": minf(duration, float(frame) / FPS), "key": "%03d" % frame, "frame": frame})
			samples.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.time) < float(b.time))
			for sample in samples:
				advance_to(float(sample.time))
				if float(sample.time) >= duration and player.reload_left > 0:
					step(player.reload_left)
				for view: String in VIEWS:
					set_view(view)
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var filename := "%s_%s_%s_%s%s.jpg" % [key, variant_key, view, sample.key, "_moving" if walk else ""]
					var error := get_viewport().get_texture().get_image().save_jpg(directory + "/" + filename, 0.88)
					if error != OK:
						push_error("Capture failed: " + filename)
						get_tree().quit(1)
						return
					var record := {"time": sample.time, "view": view, "path": "captures/" + filename, "stage": sample.key}
					if sample.has("frame"):
						record["frame"] = sample.frame
					records.append(record)
			entry.variants[variant_key] = {"duration": duration, "captures": records}
		manifest.weapons[key] = entry
		print("RELOAD_CATALOG_CAPTURE_WEAPON ", key)
	var suffix := "_moving" if walk else ""
	if not selected.is_empty():
		suffix += "_selection"
	var file := FileAccess.open(OUTPUT + "/manifest" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	cleanup()
	await get_tree().process_frame
	print("RELOAD_CATALOG_CAPTURE_PASS")
	get_tree().quit()
