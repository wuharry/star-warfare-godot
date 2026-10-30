extends SceneTree
## Run this external script with --main-pack <exported.pck>. The tests directory
## is excluded from the pack; resources checked below come from that export.

func _initialize() -> void:
	var failures: Array[String] = []
	var directories: Array[String] = []
	for level in range(1, 9):
		directories.append("res://assets/models/levels/level_%02d" % level)
	for level in range(13, 22):
		directories.append("res://assets/models/levels/level_%02d" % level)
	for boss in range(1, 7):
		directories.append("res://assets/models/boss_arenas/boss_%02d" % boss)
	for directory: String in directories:
		var path := directory + "/level.json"
		if not FileAccess.file_exists(path):
			failures.append("Missing packed metadata: " + path)
			continue
		var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not metadata is Dictionary or (metadata.get("primitive_colliders", []).is_empty() and metadata.get("mesh_colliders", []).is_empty()):
			failures.append("Missing packed collisions: " + path)
			continue
		for visual: String in ["stage.obj", str(metadata.get("visual_with_uv2", "stage.obj"))]:
			if not ResourceLoader.exists(directory.path_join(visual)):
				failures.append("Missing packed art: " + directory.path_join(visual))
	for model: String in ["bug01", "bug02", "bug03", "bug04", "bug05", "bug06", "bug07", "bug08", "boss01", "boss02", "boss02-1", "boss03", "boss05", "boss06"]:
		if not ResourceLoader.exists("res://assets/models/enemies/animated/%s/%s.gltf" % [model, model]):
			failures.append("Missing packed enemy: " + model)
	var effect_data_available := true
	for path: String in ["res://assets/weapon_effects/effects.json", "res://assets/weapon_effects/hd.json", "res://assets/scene_effects/effects.json"]:
		if not FileAccess.file_exists(path):
			failures.append("Missing packed effects metadata: " + path)
			effect_data_available = false
		elif not JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary:
			failures.append("Invalid packed effects metadata: " + path)
			effect_data_available = false
	var effects_checked := 0
	if effect_data_available:
		var source_effects: GDScript = load("res://scripts/game/original_weapon_effect.gd")
		var catalog: Dictionary = source_effects.catalog()
		if catalog.size() != 17:
			failures.append("Incomplete packed weapon catalog: %d entries" % catalog.size())
		for weapon: String in catalog:
			var entry: Array = catalog[weapon]
			if entry.size() != 4:
				failures.append("Invalid packed weapon catalog entry: " + weapon)
				continue
			# Catalog fields are projectile, impact, firing audio, impact audio.
			for path: String in entry.slice(0, 2):
				var effect: Node3D = source_effects.create(path)
				if effect == null or effect.get_child_count() == 0:
					failures.append("Missing packed weapon effect: " + path)
				else:
					effects_checked += 1
				if effect != null:
					effect.free()
			for sound: String in entry.slice(2, 4):
				if not sound.is_empty() and not ResourceLoader.exists(source_effects.ROOT + "audio/" + sound):
					failures.append("Missing packed weapon audio: " + sound)
	for failure: String in failures:
		push_error(failure)
	print("PACK_CONTENT_PROBE_%s arenas=23 enemies=14 effects=%d" % ["PASS" if failures.is_empty() else "FAIL", effects_checked])
	quit(0 if failures.is_empty() else 1)
