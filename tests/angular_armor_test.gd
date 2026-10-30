extends Node3D

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const REVISION := "angular_armor_v1"
const SOURCE_AVATAR_PATH := "res://assets/models/player/animated/player.gltf"
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
	if not GameState.save_path.begins_with("user://star_warfare_test_"):
		push_error("Run with -- --test-profile=<unique_identifier>")
		get_tree().quit(1)
		return
	var test_save := GameState.save_path
	var save_hash := _hash(test_save)
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_weapon = "gun00"
	_check("--armor-style=legacy" not in OS.get_cmdline_user_args(), "Run this regression with the current armor style")
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	GameState.save_path = test_save
	var player: WarfarePlayer = fixture.player
	var avatar := player.recovered_avatar
	var skeleton := player.recovered_skeleton
	var tested := 0
	for id: int in Catalog.SET_NAMES.size():
		var selected := Visuals.reworked_scene_path(id)
		var original_path := _original_scene_path(id)
		var path := "res://assets/armors/angular/armor_00.scn" if id == 0 else original_path
		_check(selected == path if id == 0 else selected.is_empty(), "Runtime mapping must preserve Viper and use original non-Viper assets: %02d" % id)
		_check(ResourceLoader.exists(path) and ResourceLoader.exists(original_path), "Missing source/accepted armor %02d" % id)
		if not ResourceLoader.exists(path) or not ResourceLoader.exists(original_path):
			continue
		_equip(player, id)
		var baseline := (load(original_path) as PackedScene).instantiate()
		var template := (load(path) as PackedScene).instantiate() if id == 0 else baseline
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
			_check(part.visible, part_name + " is hidden")
			_check(part.get_meta("armor_rework", "") == REVISION if id == 0 else not part.has_meta("armor_rework"), part_name + " has incorrect source/rework provenance")
			_check(part.mesh == authored.mesh, part_name + " does not use its selected asset")
			_check(part.mesh != old.mesh if id == 0 else part.mesh == old.mesh, part_name + " changed accepted/source geometry")
			_check(part.transform.is_equal_approx(old.transform), part_name + " changed attachment transform")
			_check(part.get_node_or_null(part.skeleton) == skeleton, part_name + " uses another skeleton")
			_check(part.skin != null and part.skin.get_bind_count() == old.skin.get_bind_count(), part_name + " changed skin bind count")
			if part.skin == null:
				continue
			for bind: int in part.skin.get_bind_count():
				var bone_name := part.skin.get_bind_name(bind)
				if id == 0: _check(not bone_name.is_empty(), part_name + " lost its accepted named bind")
				var bone := _bind_bone(part.skin, bind, skeleton)
				_check(bone >= 0 and bone < skeleton.get_bone_count(), part_name + " has an unknown skin bind")
				if bind < old.skin.get_bind_count():
					_check(bone_name == old.skin.get_bind_name(bind) and part.skin.get_bind_bone(bind) == old.skin.get_bind_bone(bind) and part.skin.get_bind_pose(bind).is_equal_approx(old.skin.get_bind_pose(bind)), part_name + " changed original skin binding")
			_check(part.mesh.get_surface_count() == old.mesh.get_surface_count(), part_name + " changed surface mapping")
			_validate_mesh(part)
			var geometry_changed := false
			for surface: int in part.mesh.get_surface_count():
				var generated_arrays := part.mesh.surface_get_arrays(surface)
				var original_arrays := old.mesh.surface_get_arrays(surface)
				geometry_changed = geometry_changed or generated_arrays[Mesh.ARRAY_VERTEX] != original_arrays[Mesh.ARRAY_VERTEX]
				var material := part.get_active_material(surface)
				if id == 0:
					_check(material != null and material == authored.get_active_material(surface), part_name + " lost accepted Viper material")
					_check(material is ShaderMaterial and material.shader.resource_path == SHADER, part_name + " lacks the accepted angular surface shader")
					if material is ShaderMaterial and material.shader.resource_path == SHADER:
						_check(float(material.get_shader_parameter("readable_fill")) <= 0.25, part_name + " is dominated by emission")
						var original_material := old.get_active_material(surface) as ShaderMaterial
						_check(material.get_shader_parameter("albedo_texture") is Texture2D and material.get_shader_parameter("albedo_texture") == original_material.get_shader_parameter("albedo_texture"), part_name + " lost the original paint")
			_check(geometry_changed if id == 0 else not geometry_changed, part_name + " violated accepted/source geometry contract")
			if id != 0: _validate_original_materials(part, old, id)

		_validate_visible(avatar, expected)
		_validate_animation(player, parts)
		if template != baseline: template.free()
		baseline.free()
		tested += 1
	for cycle: int in 3:
		GameState.equipped_armor = {"head": "armor_head_09", "body": "armor_body_06", "arms": "armor_arms_21", "legs": "armor_legs_00", "bag": "armor_bag_00"}
		player._apply_recovered_armor_visibility()
		_validate_visible(avatar, ["ArmorHead_09", "ArmorBody_06", "ArmorHand_21", "ArmorFoot_00"])
		fixture.begin("gun00", 0)
		fixture.advance_to(fixture.duration * 0.5)
		for part: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
			if part.visible:
				var id := int(str(part.name).get_slice("_", 1))
				_check(part.get_meta("armor_rework", "") == REVISION if id == 0 else not part.has_meta("armor_rework"), str(part.name) + " has incorrect provenance during mixed equip")
				var original_path := Visuals.reworked_scene_path(0) if id == 0 else _original_scene_path(id)
				var original := (load(original_path) as PackedScene).instantiate()
				var source_part := original.find_child(str(part.name), true, false) as MeshInstance3D
				_check(source_part != null and part.mesh == source_part.mesh and part.skin == source_part.skin, str(part.name) + " mixed reload changed source geometry/skin")
				if id != 0: _validate_original_materials(part, source_part, id)
				original.free()
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
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.25).timeout
	_check(tested == Catalog.SET_NAMES.size(), "Did not test Viper and every original SW1/CoM armor")
	_check(GameState.save_path == test_save and _hash(test_save) == save_hash, "Isolated test save changed")
	print("ANGULAR_ARMOR_%s sets=%d triangles=%d mixed_equipment=true animated_skin=true store_customize=true save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", tested, triangle_count, str(_hash(test_save) == save_hash)])
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
		var bone := _bind_bone(part.skin, bind, skeleton)
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
		for id: int in Catalog.SET_NAMES.size():
			var path := Visuals.reworked_scene_path(0) if id == 0 else _original_scene_path(id)
			var template := (load(path) as PackedScene).instantiate()
			for index: int in 4:
				shell._select_category(Catalog.PART_KEYS[index], false)
				shell._select_item(Catalog.item_key(index, id), false)
				var name_key: String = Visuals.ORIGINAL_PART_PREFIXES[index] + "%02d" % id
				var preview := shell.preview_root.find_child(name_key, true, false) as MeshInstance3D
				var source := template.find_child(name_key, true, false) as MeshInstance3D
				_check(preview != null and preview.visible and source != null, mode + " preview is missing " + name_key)
				if preview == null or source == null: continue
				_check(preview.get_meta("armor_rework", "") == REVISION if id == 0 else not preview.has_meta("armor_rework"), mode + " preview has wrong provenance: " + name_key)
				_check(preview.mesh == source.mesh and preview.skin == source.skin, mode + " preview changed source/accepted geometry or skin: " + name_key)
				if id != 0: _validate_original_materials(preview, source, id)
			template.free()
	shell.queue_free()


func _original_scene_path(id: int) -> String:
	if id == 0: return "res://assets/armors/viper/viper.scn"
	return SOURCE_AVATAR_PATH if id < Catalog.CALLOFMINI_FIRST_ID else Catalog.gameplay_scene_path(id)


func _bind_bone(skin: Skin, bind: int, skeleton: Skeleton3D) -> int:
	var bone_name := skin.get_bind_name(bind)
	return skeleton.find_bone(bone_name) if not bone_name.is_empty() else skin.get_bind_bone(bind)


func _validate_original_materials(part: MeshInstance3D, source: MeshInstance3D, id: int) -> void:
	_check(part.material_override == null, str(part.name) + " has an unexpected whole-mesh override")
	for surface: int in part.mesh.get_surface_count():
		var material := part.get_active_material(surface)
		var original := source.get_active_material(surface)
		_check(material != null and original != null, str(part.name) + " lost original material")
		if id >= Catalog.CALLOFMINI_FIRST_ID:
			_check(material == original, str(part.name) + " changed original CoM adapter material")
			continue
		_check(material is BaseMaterial3D and original is BaseMaterial3D, str(part.name) + " replaced source SW1 material with a custom shader")
		if material is BaseMaterial3D and original is BaseMaterial3D:
			_check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, str(part.name) + " lost Unity unlit rendering")
			_check(material.albedo_texture != null and material.albedo_texture == original.albedo_texture, str(part.name) + " changed original atlas")
			_check(material.albedo_color == original.albedo_color and material.transparency == original.transparency and material.cull_mode == original.cull_mode, str(part.name) + " changed source color/transparency/culling")
			_check(material.uv1_scale == original.uv1_scale and material.uv1_offset == original.uv1_offset, str(part.name) + " changed source UV mapping")


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
