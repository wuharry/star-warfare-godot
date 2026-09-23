extends Node3D

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const REVISION := "angular_armor_v1"
const SHADER := "res://assets/armors/angular/armor_surface.gdshader"
var failures: Array[String] = []
var triangle_count := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
		push_error("ANGULAR_ARMOR: " + message)


func _run() -> void:
	var real_save := GameState.save_path
	var save_hash := _hash(real_save)
	GameState.save_path = "user://angular_armor_test_profile.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_weapon = "gun00"
	_check("--armor-style=legacy" not in OS.get_cmdline_user_args(), "Run this regression with the current armor style")
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://angular_armor_test_profile.json"
	var player: WarfarePlayer = fixture.player
	var avatar := player.recovered_avatar
	var skeleton := player.recovered_skeleton
	var tested := 0
	for id: int in Catalog.SET_NAMES.size():
		if id == 6:
			continue
		var path := "res://assets/armors/angular/armor_%02d.scn" % id
		_check(ResourceLoader.exists(path), "Missing compiled armor %02d" % id)
		_check(Visuals.reworked_scene_path(id) == path, "Loader did not select angular armor %02d" % id)
		if not ResourceLoader.exists(path):
			continue
		_equip(player, id)
		var baseline_path := "res://assets/armors/viper/viper.scn" if id == 0 else "res://assets/equipment_refined/armors/armor_%02d.scn" % id
		var baseline := (load(baseline_path) as PackedScene).instantiate()
		var template := (load(path) as PackedScene).instantiate()
		var parts: Array[MeshInstance3D] = []
		var expected: Array[String] = []
		for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
			var part_name := prefix + "%02d" % id
			expected.append(part_name)
			var part := avatar.find_child(part_name, true, false) as MeshInstance3D
			var old := baseline.find_child(part_name, true, false) as MeshInstance3D
			var authored := template.find_child(part_name, true, false) as MeshInstance3D
			_check(part != null and old != null and authored != null, "Missing part " + part_name)
			if part == null or old == null or authored == null:
				continue
			parts.append(part)
			_check(part.visible and part.get_meta("armor_rework", "") == REVISION, part_name + " is hidden or has wrong revision")
			_check(part.mesh == authored.mesh and part.mesh != old.mesh, part_name + " does not use generated geometry")
			_check(part.transform.is_equal_approx(old.transform), part_name + " changed attachment transform")
			_check(part.get_node_or_null(part.skeleton) == skeleton, part_name + " uses another skeleton")
			_check(part.skin != null and part.skin.get_bind_count() == old.skin.get_bind_count(), part_name + " changed skin bind count")
			if part.skin == null:
				continue
			for bind: int in part.skin.get_bind_count():
				var bone_name := part.skin.get_bind_name(bind)
				_check(not bone_name.is_empty() and skeleton.find_bone(bone_name) >= 0, part_name + " has an unknown named bind")
				_check(bone_name == old.skin.get_bind_name(bind) and part.skin.get_bind_pose(bind).is_equal_approx(old.skin.get_bind_pose(bind)), part_name + " changed original skin binding")
			_check(part.mesh.get_surface_count() == old.mesh.get_surface_count(), part_name + " changed surface mapping")
			_validate_mesh(part)
			for surface: int in part.mesh.get_surface_count():
				var material := part.get_active_material(surface)
				_check(material != null and material == authored.get_active_material(surface), part_name + " lost authored material")
				if material is ShaderMaterial and material.shader.resource_path == SHADER:
					_check(float(material.get_shader_parameter("readable_fill")) <= 0.25, part_name + " is dominated by emission")
					_check(material.get_shader_parameter("albedo_texture") is Texture2D, part_name + " lost the original paint")
		_validate_visible(avatar, expected)
		_validate_animation(player, parts)
		baseline.free()
		template.free()
		tested += 1
	var thunder_path := Visuals.reworked_scene_path(6)
	_check(not thunder_path.begins_with("res://assets/armors/angular/"), "Thunder was replaced")
	_equip(player, 6)
	var thunder := (load(thunder_path) as PackedScene).instantiate()
	for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
		var part := avatar.find_child(prefix + "06", true, false) as MeshInstance3D
		var original := thunder.find_child(prefix + "06", true, false) as MeshInstance3D
		_check(part.mesh == original.mesh and part.skin == original.skin, "Thunder geometry or skin changed")
	thunder.free()
	for cycle: int in 3:
		GameState.equipped_armor = {"head": "armor_head_09", "body": "armor_body_06", "arms": "armor_arms_21", "legs": "armor_legs_00", "bag": "armor_bag_00"}
		player._apply_recovered_armor_visibility()
		_validate_visible(avatar, ["ArmorHead_09", "ArmorBody_06", "ArmorHand_21", "ArmorFoot_00"])
		fixture.begin("gun00", 0)
		fixture.advance_to(fixture.duration * 0.5)
		for part: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
			if part.visible:
				_validate_posed(part, skeleton, "mixed reload")
		fixture.player._cancel_reload()
	var child_count := skeleton.get_child_count()
	for cycle: int in 8:
		player._apply_recovered_armor_visibility()
	_check(skeleton.get_child_count() == child_count, "Repeated equip duplicated armor")
	_validate_store_preview()
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	_check(tested == Catalog.SET_NAMES.size() - 1, "Did not test all non-Thunder sets")
	_check(_hash(real_save) == save_hash, "Real player save changed")
	print("ANGULAR_ARMOR_%s sets=%d triangles=%d mixed_equipment=true animated_skin=true store_customize=true save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", tested, triangle_count, str(_hash(real_save) == save_hash)])
	get_tree().quit(0 if failures.is_empty() else 1)


func _validate_mesh(part: MeshInstance3D) -> void:
	for surface: int in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		triangle_count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
		var complete := vertices.size() > 0 and normals.size() == vertices.size() and uv.size() == vertices.size() and bones.size() == vertices.size() * 4 and weights.size() == bones.size()
		_check(complete, str(part.name) + " has incomplete attributes")
		if not complete:
			continue
		for vertex: int in vertices.size():
			_check(vertices[vertex].is_finite() and normals[vertex].is_finite() and uv[vertex].is_finite(), str(part.name) + " has non-finite geometry")
			_check(absf(normals[vertex].length() - 1.0) < 0.03, str(part.name) + " has non-unit normals")
			var total := 0.0
			for influence: int in 4:
				var index := vertex * 4 + influence
				_check(bones[index] >= 0 and bones[index] < part.skin.get_bind_count(), str(part.name) + " has invalid bone index")
				_check(is_finite(weights[index]) and weights[index] >= 0, str(part.name) + " has invalid skin weight")
				total += weights[index]
			_check(absf(total - 1.0) < 0.0001, str(part.name) + " has unnormalized skin weights")
		for index: int in indices:
			_check(index >= 0 and index < vertices.size(), str(part.name) + " has invalid triangle index")


func _validate_animation(player: WarfarePlayer, parts: Array[MeshInstance3D]) -> void:
	player.recovered_animation_tree.active = false
	var animation := player.recovered_animation_player
	var initial: Dictionary = {}
	var moved: Dictionary = {}
	for clip: String in ["idle_rifle", "run_rifle"]:
		_check(animation.has_animation(clip), "Missing clip " + clip)
		if not animation.has_animation(clip):
			continue
		animation.play(clip)
		for time: float in [0.0, 0.25, 0.5]:
			animation.seek(time, true)
			player.recovered_skeleton.force_update_all_bone_transforms()
			for part: MeshInstance3D in parts:
				var bounds := _validate_posed(part, player.recovered_skeleton, clip)
				if not initial.has(part.name):
					initial[part.name] = bounds
				elif not bounds.is_equal_approx(initial[part.name]):
					moved[part.name] = true
	for part: MeshInstance3D in parts:
		_check(moved.has(part.name), str(part.name) + " does not follow animated bones")


func _validate_posed(part: MeshInstance3D, skeleton: Skeleton3D, phase: String) -> AABB:
	var transforms: Array[Transform3D] = []
	for bind: int in part.skin.get_bind_count():
		var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
		if bone < 0:
			return AABB()
		transforms.append(skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
	var bounds := AABB()
	var first := true
	for surface: int in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		for vertex: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for influence: int in 4:
				var index := vertex * 4 + influence
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][index]
				if weight > 0:
					point += (transforms[arrays[Mesh.ARRAY_BONES][index]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * weight
			bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
			first = false
	_check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length() > 0.01 and bounds.size.length() < 3.5, str(part.name) + " explodes or collapses in " + phase)
	return bounds


func _validate_store_preview() -> void:
	var shell := UnityEquipmentShell.new()
	shell.setup("store", true)
	add_child(shell)
	for mode: String in ["store", "customize"]:
		shell.set_mode(mode, false)
		for id: int in [0, 9, 21, 28]:
			for index: int in 4:
				shell._select_category(Catalog.PART_KEYS[index], false)
				shell._select_item(Catalog.item_key(index, id), false)
				var name_key: String = Visuals.ORIGINAL_PART_PREFIXES[index] + "%02d" % id
				var preview := shell.preview_root.find_child(name_key, true, false) as MeshInstance3D
				_check(preview != null and preview.visible and preview.get_meta("armor_rework", "") == REVISION, mode + " preview uses old " + name_key)
	shell.queue_free()


func _equip(player: WarfarePlayer, id: int) -> void:
	for index: int in 4:
		GameState.equipped_armor[Catalog.PART_KEYS[index]] = Catalog.item_key(index, id)
	player._apply_recovered_armor_visibility()


func _validate_visible(avatar: Node3D, expected: Array) -> void:
	var actual: Array[String] = []
	for part: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if part.visible:
			actual.append(str(part.name))
	_check(actual.size() == expected.size(), "Equip displays extra armor parts")
	for part: String in expected:
		_check(part in actual, "Equip is missing " + part)


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
