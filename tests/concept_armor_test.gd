extends Node3D

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const REVISION := "concept_painted_cygni_trial_v2"
var failures: Array[String] = []
var records: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CONCEPT_ARMOR: " + message)


func _run() -> void:
	# Cygni now uses the adopted runtime asset by default. Its dedicated test
	# validates the legacy-plus-appended binds; the old assertions below remain
	# specific to explicitly requested historical trial scenes.
	if not "--cygni-helmet-repair" in OS.get_cmdline_user_args() and not "--cygni-painted-trial" in OS.get_cmdline_user_args():
		var error := get_tree().change_scene_to_file("res://tests/cygni_v2_test.tscn")
		if error != OK:
			push_error("Cannot load adopted Cygni test: " + error_string(error))
			get_tree().quit(1)
		return
	var real_save := GameState.save_path
	var real_hash := _hash(real_save)
	GameState.save_path = "user://concept_armor_test.json"
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://concept_armor_test.json"
	var player: WarfarePlayer = fixture.player
	var skeleton := player.recovered_skeleton
	var rests: Array[Transform3D] = []
	var repaired := "--cygni-helmet-repair" in OS.get_cmdline_user_args()
	var revision := "concept_cygni_connected_shell_v4" if repaired else REVISION
	for bone: int in skeleton.get_bone_count():
		rests.append(skeleton.get_bone_rest(bone))
	for id: int in Catalog.SET_NAMES.size():
		var path := Visuals.reworked_scene_path(id)
		if id == 11 and repaired:
			_check(path == Visuals.CONCEPT_ARMOR_DIR + "painted/repaired_cygni_helmet.scn", "Missing repaired helmet")
		elif id == 11 and "--cygni-painted-trial" in OS.get_cmdline_user_args():
			_check(path == Visuals.CONCEPT_ARMOR_DIR + "painted/armor_11.scn", "Missing painted Cygni trial")
		elif id == 6:
			_check(path == "res://assets/armors/thunder/thunder.scn", "Adopted Thunder changed")
		elif id == 0:
			_check(path == "res://assets/armors/angular/armor_00.scn", "Existing Viper changed")
		else:
			_check(path == "res://assets/equipment_refined/armors/armor_%02d.scn" % id, "Replaced retained Phoenix/later/CoM set " + str(id))
	var trial_enabled := repaired or "--cygni-painted-trial" in OS.get_cmdline_user_args()
	var baseline := (load("res://assets/equipment_refined/armors/armor_11.scn") as PackedScene).instantiate()
	for id: int in [11]:
		_equip(player, id)
		var parts := _visible(player)
		_check(parts.size() == 4, "Wrong visible parts for %02d" % id)
		var triangles := 0
		for part: MeshInstance3D in parts:
			_check(str(part.name).ends_with("_%02d" % id), "Visible part belongs to another set")
			if trial_enabled:
				_check(part.get_meta("armor_rework", "") == revision, "Old armor selected " + str(part.name))
			_check(part.skin != null and part.get_node_or_null(part.skeleton) == skeleton, "Wrong skeleton " + str(part.name))
			var original := baseline.find_child(str(part.name), true, false) as MeshInstance3D
			_check(part.transform.is_equal_approx(original.transform), "Original attachment transform changed")
			_check(part.skin.get_bind_count() == original.skin.get_bind_count(), "Original skin binding count changed")
			for bind: int in part.skin.get_bind_count():
				_check(part.skin.get_bind_name(bind) == original.skin.get_bind_name(bind) and part.skin.get_bind_pose(bind).is_equal_approx(original.skin.get_bind_pose(bind)), "Original skin binding changed")
			for surface: int in part.mesh.get_surface_count():
				var arrays := part.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				triangles += part.mesh.surface_get_array_index_len(surface)/3
				_check(normals.size() == vertices.size() and weights.size() == vertices.size()*4, "Incomplete attributes")
				if trial_enabled:
					_check(colors.size() == vertices.size(), "Painted layer walls lack vertex shade")
					if repaired and part.name == "ArmorHead_11":
						var clay := part.get_active_material(surface) as StandardMaterial3D
						_check(clay != null and clay.vertex_color_use_as_albedo and clay.albedo_texture == null, "Geometry review must not use a misleading texture")
						_check(part.mesh.surface_get_array_index_len(surface) != original.mesh.surface_get_array_index_len(surface), "Repaired helmet reused the old model")
						# The technical UV is deliberately unfinished during the
						# shape review; skin/normal checks still run below.
					else:
						_check_paint(part, original, surface, repaired)
				for i: int in vertices.size():
					_check(vertices[i].is_finite() and normals[i].is_finite() and absf(normals[i].length()-1.0)<.03, "Invalid vertex/normal")
					var sum := 0.0
					for j: int in 4:
						_check(bones[i*4+j] >= 0 and bones[i*4+j] < part.skin.get_bind_count(), "Invalid bone index")
						sum += weights[i*4+j]
					_check(absf(sum-1.0)<.001, "Skin weights not normalized")
		_check(triangles <= 8000, "Candidate exceeded provisional triangle budget")
		for clip: String in ["idle_rifle", "run_rifle"]:
			player.recovered_animation_tree.active = false
			player._play_recovered_animation(clip, 0, true)
			for time: float in [.0, .25, .5]:
				player.recovered_animation_player.seek(time, true)
				skeleton.force_update_all_bone_transforms()
				for part: MeshInstance3D in parts:
					_check(_posed_bounds(part, skeleton).size.length()<3.5, "Mesh exploded during " + clip)
		fixture.begin("gun00", 0)
		fixture.advance_to(fixture.duration*.5)
		for part: MeshInstance3D in parts:
			_check(_posed_bounds(part, skeleton).size.length()<3.5, "Mesh exploded during reload")
		var head := player.recovered_avatar.find_child("ArmorHead_%02d" % id, true, false) as MeshInstance3D
		records.append({"id": id, "triangles": triangles, "head_bind_bounds": {"position": str(head.mesh.get_aabb().position), "size": str(head.mesh.get_aabb().size)}})
	baseline.free()
	for bone: int in skeleton.get_bone_count():
		_check(skeleton.get_bone_rest(bone).is_equal_approx(rests[bone]), "Original proportions changed at bone " + skeleton.get_bone_name(bone))
	# Retained parts can still mix with newly authored parts without duplicated
	# nodes or losing the stable equipment IDs / original animations.
	GameState.equipped_armor = {"head":"armor_head_11", "body":"armor_body_10", "arms":"armor_arms_09", "legs":"armor_legs_12", "bag":"armor_bag_00"}
	player._apply_recovered_armor_visibility()
	var names: Array[String] = []
	for part: MeshInstance3D in _visible(player):
		names.append(str(part.name))
	for name_key: String in ["ArmorHead_11", "ArmorBody_10", "ArmorHand_09", "ArmorFoot_12"]:
		_check(name_key in names, "Mixed equipment lost " + name_key)
	_check(names.size() == 4, "Mixed equipment has extra pieces")
	var node_count := skeleton.get_child_count()
	for cycle: int in 5:
		player._apply_recovered_armor_visibility()
	_check(skeleton.get_child_count() == node_count, "Repeated equip duplicated nodes")
	# Store and customize use the exact same loader as combat.
	var shell := UnityEquipmentShell.new()
	shell.setup("store", true)
	add_child(shell)
	for mode: String in ["store", "customize"]:
		shell.set_mode(mode, false)
		for id: int in [11]:
			for index: int in 4:
				shell._select_category(Catalog.PART_KEYS[index], false)
				shell._select_item(Catalog.item_key(index, id), false)
				var shown := shell.preview_root.find_child(Visuals.ORIGINAL_PART_PREFIXES[index]+"%02d"%id, true, false) as MeshInstance3D
				_check(shown != null and shown.visible, "Store/customize lost armor part")
				if trial_enabled:
					_check(shown.get_meta("armor_rework", "") == revision, "Store/customize uses stale geometry")
	shell.queue_free()
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_hash(real_save) == real_hash, "Real user save changed")
	GameState.save_path = real_save
	var report := FileAccess.open("res://test_output/armor_concept_runtime/runtime_test.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL", "sets":records, "failures":failures, "save_unchanged":_hash(real_save)==real_hash}, "\t"))
	print("CONCEPT_ARMOR_TEST_%s sets=%d failures=%d save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", records.size(), failures.size(), str(_hash(real_save)==real_hash)])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_paint(part: MeshInstance3D, original: MeshInstance3D, surface: int, repaired: bool) -> void:
	var material := part.get_active_material(surface) as ShaderMaterial
	_check(material != null and material.get_shader_parameter("albedo_texture") != null, "Textureless body material installed")
	if material == null:
		return
	var texture := material.get_shader_parameter("albedo_texture") as Texture2D
	if part.name == "ArmorHead_11":
		_check(texture.resource_path == "res://assets/armors/concept_runtime/textures/cygni_head.png", "Wrong old style trial atlas")
		var tint: Color = material.get_shader_parameter("albedo_tint")
		_check(is_equal_approx(tint.r, tint.g) and is_equal_approx(tint.g, tint.b), "Cygni helmet is still tinted red")
	else:
		_check(texture == original.get_active_material(surface).get_shader_parameter("albedo_texture"), "Original body texture was replaced")
		if repaired:
			var actual := part.mesh.surface_get_arrays(surface)
			# Original body cage is exactly retained in this head-only repair.
			var raw := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
			var raw_part := raw.find_child(str(part.name), true, false) as MeshInstance3D
			var expected := raw_part.mesh.surface_get_arrays(surface)
			_check(actual[Mesh.ARRAY_VERTEX] == expected[Mesh.ARRAY_VERTEX] and actual[Mesh.ARRAY_INDEX] == expected[Mesh.ARRAY_INDEX], "Head repair changed the body cage")
			raw.free()


func _equip(player: WarfarePlayer, id: int) -> void:
	for part: int in 4:
		GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, id)
	player._apply_recovered_armor_visibility()


func _visible(player: WarfarePlayer) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	for part: MeshInstance3D in player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if part.visible:
			parts.append(part)
	return parts


func _posed_bounds(part: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var transforms: Array[Transform3D] = []
	for bind: int in part.skin.get_bind_count():
		var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
		_check(bone >= 0, "Unknown bind")
		if bone < 0:
			return AABB()
		transforms.append(skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
	var first := true
	var bounds := AABB()
	for surface: int in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		for vertex: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for influence: int in 4:
				var index := vertex*4+influence
				if arrays[Mesh.ARRAY_WEIGHTS][index] > 0:
					point += (transforms[arrays[Mesh.ARRAY_BONES][index]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * arrays[Mesh.ARRAY_WEIGHTS][index]
			_check(point.is_finite(), "Non-finite posed vertex")
			bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
			first = false
	return bounds


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
