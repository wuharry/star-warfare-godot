extends Node3D

const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const SOURCE_AVATAR_PATH := "res://assets/models/player/animated/player.gltf"
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("THUNDER_ARMOR: " + message)


func _run() -> void:
	if not GameState.save_path.begins_with("user://star_warfare_test_"):
		_check(false, "Run with -- --test-profile=<unique_identifier>")
		_finish(0, 0)
		return
	GameState.equipped_armor = GameState._default_armor_equipment()
	_set_thunder()
	GameState.selected_weapon = "gun00"
	_check(Visuals.reworked_scene_path(6).is_empty(), "Thunder must use source avatar set 06")
	_check(Visuals.REWORKED_SCENES.get(0, "") == "res://assets/armors/viper/viper.scn", "Viper mapping changed")
	if not ResourceLoader.exists(SOURCE_AVATAR_PATH):
		_check(false, "Original SW1 avatar is missing")
		_finish(0, 0)
		return
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	var avatar := player.recovered_avatar
	var skeleton := player.recovered_skeleton
	var template := (load(SOURCE_AVATAR_PATH) as PackedScene).instantiate() as Node3D
	var source_skeleton := template.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var parts: Array[MeshInstance3D] = []
	var triangle_count := 0
	for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
		var part_name := prefix + "06"
		var part := avatar.find_child(part_name, true, false) as MeshInstance3D
		var authored := template.find_child(part_name, true, false) as MeshInstance3D
		_check(part != null and authored != null, "missing source exchangeable part " + part_name)
		if part == null or authored == null:
			continue
		parts.append(part)
		_check(not part.has_meta("armor_rework"), part_name + " still uses a custom rework")
		_check(part.visible and part.skin != null, part_name + " is hidden or has no skin")
		_check(part.get_node_or_null(part.skeleton) == skeleton, part_name + " uses another skeleton")
		_check(part.mesh != null and part.mesh == authored.mesh, part_name + " does not use the original source mesh")
		_check(part.transform.is_equal_approx(authored.transform), part_name + " changed its source attachment transform")
		if part.skin == null or part.mesh == null:
			continue
		_check(part.skin.get_bind_count() == authored.skin.get_bind_count(), part_name + " changed source bind count")
		for bind in part.skin.get_bind_count():
			var bone := _bind_bone(part.skin, bind, skeleton)
			_check(bone >= 0 and bone < skeleton.get_bone_count(), part_name + " has an unknown bind")
			if bind < authored.skin.get_bind_count():
				_check(part.skin.get_bind_name(bind) == authored.skin.get_bind_name(bind) and part.skin.get_bind_bone(bind) == authored.skin.get_bind_bone(bind), part_name + " changed source bone mapping")
				_check(part.skin.get_bind_pose(bind).is_equal_approx(authored.skin.get_bind_pose(bind)), part_name + " changed source bind pose")
			if bone >= 0 and bone < skeleton.get_bone_count():
				# Source glTF retains its authored bind frame; only the retired
				# generated suit normalized every rest*bind product to identity.
				var source_bone := source_skeleton.find_bone(skeleton.get_bone_name(bone))
				_check(source_bone >= 0, part_name + " bind is absent from the source skeleton")
				if source_bone >= 0:
					_check(skeleton.get_bone_global_rest(bone).is_equal_approx(source_skeleton.get_bone_global_rest(source_bone)), part_name + " changed the source skeleton rest pose")
		triangle_count += _validate_mesh(part)
		_validate_source_materials(part, authored)
	_check(parts.size() == 4, "Thunder must have four exchangeable parts")
	_check(triangle_count > 0, "mesh validation did not count any triangles")
	_check_visible(avatar, ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"])
	var viper := (load(Visuals.reworked_scene_path(0)) as PackedScene).instantiate() as Node3D
	var com := (load(Catalog.gameplay_scene_path(21)) as PackedScene).instantiate() as Node3D
	for cycle in range(3):
		GameState.equipped_armor = {"head": "armor_head_06", "body": "armor_body_00", "arms": "armor_arms_21", "legs": "armor_legs_02", "bag": "armor_bag_00"}
		player._apply_recovered_armor_visibility()
		_check_visible(avatar, ["ArmorHead_06", "ArmorBody_00", "ArmorHand_21", "ArmorFoot_02"])
		for record: Array in [["ArmorHead_06", template], ["ArmorBody_00", viper], ["ArmorHand_21", com], ["ArmorFoot_02", template]]:
			var equipped := avatar.find_child(record[0], true, false) as MeshInstance3D
			var original := record[1].find_child(record[0], true, false) as MeshInstance3D
			_check(equipped != null and original != null and equipped.mesh == original.mesh and equipped.skin == original.skin, "mixed equip changed source/accepted geometry or skin: " + record[0])
		_set_thunder()
		player._apply_recovered_armor_visibility()
		_check_visible(avatar, ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"])
	var child_count := skeleton.get_child_count()
	for cycle in range(10):
		player._apply_recovered_armor_visibility()
	_check(skeleton.get_child_count() == child_count, "repeated equip duplicates meshes")
	avatar.remove_meta("unity_armor_materials_restored")
	Visuals.ensure_parts(avatar, {"head": 6})
	for part: MeshInstance3D in parts:
		_validate_source_materials(part, template.find_child(str(part.name), true, false) as MeshInstance3D)
	_validate_animation(player, parts)
	await _validate_store_preview(template)
	viper.free()
	com.free()
	template.free()
	player.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.25).timeout
	_finish(parts.size(), triangle_count)


func _validate_mesh(part: MeshInstance3D) -> int:
	var triangles := 0
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
		var complete := not vertices.is_empty() and vertices.size() == normals.size() and vertices.size() == uv.size() and bones.size() == vertices.size() * 4 and weights.size() == bones.size()
		_check(complete, str(part.name) + " has incomplete vertex attributes")
		if not complete:
			continue
		for vertex in vertices.size():
			_check(vertices[vertex].is_finite() and normals[vertex].is_finite() and uv[vertex].is_finite(), str(part.name) + " has non-finite geometry")
			_check(absf(normals[vertex].length() - 1.0) < 0.03, str(part.name) + " has invalid normals")
			var total := 0.0
			for influence in range(4):
				var index := vertex * 4 + influence
				_check(bones[index] >= 0 and bones[index] < part.skin.get_bind_count(), str(part.name) + " has invalid bone index")
				_check(is_finite(weights[index]) and weights[index] >= 0.0, str(part.name) + " has invalid weight")
				total += weights[index]
			_check(absf(total - 1.0) < 0.0001, str(part.name) + " has unnormalized weights")
		for index: int in indices:
			_check(index >= 0 and index < vertices.size(), str(part.name) + " has invalid triangle index")
	return triangles


func _validate_source_materials(part: MeshInstance3D, authored: MeshInstance3D) -> void:
	_check(part.material_override == null, str(part.name) + " has a whole-mesh material override")
	_check(part.mesh.get_surface_count() == authored.mesh.get_surface_count(), str(part.name) + " changed source surface mapping")
	for surface in part.mesh.get_surface_count():
		var material := part.get_active_material(surface) as BaseMaterial3D
		var source := authored.get_active_material(surface) as BaseMaterial3D
		_check(material != null and source != null, str(part.name) + " lost the original material")
		if material == null or source == null:
			continue
		_check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, str(part.name) + " lost Unity's unlit material behavior")
		_check(material.albedo_texture != null and material.albedo_texture == source.albedo_texture, str(part.name) + " changed original atlas")
		_check(material.albedo_texture.resource_path.begins_with("res://assets/models/player/animated/"), str(part.name) + " borrowed a custom armor texture")
		_check(material.albedo_color == source.albedo_color and material.transparency == source.transparency and material.cull_mode == source.cull_mode, str(part.name) + " changed source color/transparency/culling")
		_check(material.uv1_scale == source.uv1_scale and material.uv1_offset == source.uv1_offset, str(part.name) + " changed source UV mapping")


func _bind_bone(skin: Skin, bind: int, skeleton: Skeleton3D) -> int:
	var bone_name := skin.get_bind_name(bind)
	return skeleton.find_bone(bone_name) if not bone_name.is_empty() else skin.get_bind_bone(bind)


func _validate_store_preview(template: Node3D) -> void:
	var shell := UnityEquipmentShell.new()
	shell.setup("store", true)
	add_child(shell)
	for mode: String in ["store", "customize"]:
		shell.set_mode(mode, false)
		for index in range(4):
			var category: String = Catalog.PART_KEYS[index]
			var part_name: String = Visuals.ORIGINAL_PART_PREFIXES[index] + "06"
			shell._select_category(category, false)
			await get_tree().process_frame
			shell._select_item(Catalog.item_key(index, 6), false)
			await get_tree().process_frame
			var preview := shell.preview_root.find_child(part_name, true, false) as MeshInstance3D
			var authored := template.find_child(part_name, true, false) as MeshInstance3D
			_check(preview != null and preview.visible, mode + " preview is missing " + part_name)
			if preview == null:
				continue
			_check(not preview.has_meta("armor_rework") and preview.mesh == authored.mesh and preview.skin == authored.skin, mode + " preview changed source geometry or skin " + part_name)
			_validate_source_materials(preview, authored)
	shell.queue_free()


func _validate_animation(player: WarfarePlayer, parts: Array[MeshInstance3D]) -> void:
	var animation := player.recovered_animation_player
	var skeleton := player.recovered_skeleton
	player.recovered_animation_tree.active = false
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var initial: Dictionary = {}
	var moved: Dictionary = {}
	for clip: String in ["idle_rifle", "run_rifle"]:
		_check(animation.has_animation(clip), "missing animation " + clip)
		if not animation.has_animation(clip):
			continue
		animation.play(clip)
		for time: float in [0.0, 0.2, 0.5]:
			animation.seek(time, true)
			skeleton.force_update_all_bone_transforms()
			for part: MeshInstance3D in parts:
				var bounds := _posed_bounds(part, skeleton)
				_check(bounds.position.is_finite() and bounds.size.is_finite(), str(part.name) + " produces invalid posed vertices")
				_check(bounds.size.length() > 0.01 and bounds.size.length() < 3.0, str(part.name) + " explodes or collapses during " + clip)
				if not initial.has(part.name):
					initial[part.name] = bounds
				elif not bounds.is_equal_approx(initial[part.name]):
					moved[part.name] = true
	for part: MeshInstance3D in parts:
		_check(moved.has(part.name), str(part.name) + " did not follow animated bones")


func _posed_bounds(part: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var transforms: Array[Transform3D] = []
	for bind in part.skin.get_bind_count():
		var bone := _bind_bone(part.skin, bind, skeleton)
		transforms.append(skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
	var result := AABB()
	var started := false
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		for vertex: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for influence in range(4):
				var index := vertex * 4 + influence
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][index]
				if weight > 0:
					point += (transforms[arrays[Mesh.ARRAY_BONES][index]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * weight
			result = result.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return result


func _set_thunder() -> void:
	for part in range(4):
		GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, 6)


func _check_visible(avatar: Node3D, expected: Array) -> void:
	var actual: Array[String] = []
	for part: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if part.visible:
			actual.append(str(part.name))
	_check(actual.size() == expected.size(), "equip displays extra pieces")
	for part_name: String in expected:
		_check(actual.has(part_name), "equip is missing " + part_name)


func _finish(part_count: int, triangle_count: int) -> void:
	print("THUNDER_ARMOR_%s parts=%d triangles=%d source_bindings=true mixed_equipment=true animation=true store_customize=true" % ["PASS" if failures.is_empty() else "FAIL", part_count, triangle_count])
	get_tree().quit(0 if failures.is_empty() else 1)
