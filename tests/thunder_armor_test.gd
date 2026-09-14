extends Node3D

const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const SCENE := "res://assets/armors/thunder/thunder.scn"
const REVISION := "thunder_detail_v4"
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("THUNDER_ARMOR: " + message)


func _run() -> void:
	# Set before player creation; never save into the user's equipped profile.
	GameState.save_path = "user://thunder_armor_test_profile.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	_set_thunder()
	GameState.selected_weapon = "gun00"
	_check(Visuals.REWORKED_SCENES.get(6, "") == SCENE, "set 06 does not load the new scene")
	_check(Visuals.REWORKED_SCENES.get(0, "") == "res://assets/armors/viper/viper.scn", "Viper mapping changed")
	if not ResourceLoader.exists(SCENE):
		_check(false, "Thunder scene has not been compiled")
		_finish(0, 0)
		return
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	var avatar := player.recovered_avatar
	var skeleton := player.recovered_skeleton
	var template := (load(SCENE) as PackedScene).instantiate() as Node3D
	var parts: Array[MeshInstance3D] = []
	var triangle_count := 0
	for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
		var part_name := prefix + "06"
		var part := avatar.find_child(part_name, true, false) as MeshInstance3D
		_check(part != null, "missing exchangeable part " + part_name)
		if part == null:
			continue
		parts.append(part)
		_check(part.get_meta("armor_rework", "") == REVISION, part_name + " uses an old rework")
		_check(part.visible and part.skin != null, part_name + " is hidden or has no skin")
		_check(part.get_node_or_null(part.skeleton) == skeleton, part_name + " uses another skeleton")
		var authored := template.find_child(part_name, true, false) as MeshInstance3D
		_check(authored != null and part.mesh == authored.mesh, part_name + " does not use compiled mesh")
		if part.skin == null or part.mesh == null:
			continue
		for bind in part.skin.get_bind_count():
			var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
			_check(bone >= 0, part_name + " has an unknown named bind")
			if bone >= 0:
				var identity := skeleton.get_bone_global_rest(bone) * part.skin.get_bind_pose(bind)
				_check(identity.is_equal_approx(Transform3D.IDENTITY), part_name + " changes the skeleton rest pose")
		triangle_count += _validate_mesh(part)
		var paired_helmet_surfaces := 0
		for surface in part.mesh.get_surface_count():
			_check(part.get_active_material(surface) != null, part_name + " has missing material")
			_check(part.get_active_material(surface) == authored.get_active_material(surface), part_name + " has a material override")
			var finish := part.get_active_material(surface) as ShaderMaterial
			if finish != null and finish.resource_name.begins_with("ThunderPainted_"):
				var paint := finish.get_shader_parameter("albedo_texture") as Texture2D
				_check(paint != null and paint.resource_path.begins_with("res://assets/armors/thunder/textures/"), part_name + " uses an old body atlas")
			if finish != null and finish.resource_name == "Thunder_PairedHelmet":
				paired_helmet_surfaces += 1
				_validate_helmet_detail(part, surface, finish)
		_check(paired_helmet_surfaces == (1 if part_name == "ArmorHead_06" else 0), part_name + " has missing or misplaced paired helmet material")
	_check(parts.size() == 4, "Thunder must have four exchangeable parts")
	_check(triangle_count > 0, "mesh validation did not count any triangles")
	_check_visible(avatar, ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"])
	# An ordinary set must retain its own mesh; only Thunder receives this redesign.
	var legacy_template := (load("res://assets/equipment_refined/armors/armor_02.scn") as PackedScene).instantiate() as Node3D
	for cycle in range(3):
		GameState.equipped_armor = {"head": "armor_head_06", "body": "armor_body_00", "arms": "armor_arms_21", "legs": "armor_legs_02", "bag": "armor_bag_00"}
		player._apply_recovered_armor_visibility()
		_check_visible(avatar, ["ArmorHead_06", "ArmorBody_00", "ArmorHand_21", "ArmorFoot_02"])
		var legacy := avatar.find_child("ArmorFoot_02", true, false) as MeshInstance3D
		_check(legacy.mesh == (legacy_template.find_child("ArmorFoot_02", true, false) as MeshInstance3D).mesh, "set 02 mesh changed during Thunder equip")
		_check(legacy.get_meta("armor_rework", "") != REVISION, "Thunder metadata leaked into set 02")
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
		var authored := template.find_child(str(part.name), true, false) as MeshInstance3D
		for surface in part.mesh.get_surface_count():
			_check(part.get_active_material(surface) == authored.get_active_material(surface), str(part.name) + " material restore overwrote Thunder")
	_validate_animation(player, parts)
	_validate_store_preview(template)
	legacy_template.free()
	template.free()
	player.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
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
		var complete := vertices.size() == normals.size() and vertices.size() == uv.size() and bones.size() == vertices.size() * 4 and weights.size() == bones.size()
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
	return triangles


func _validate_helmet_detail(part: MeshInstance3D, surface: int, finish: ShaderMaterial) -> void:
	_check(finish.shader != null and finish.shader.resource_path == "res://assets/armors/thunder/helmet_detail.gdshader", "paired helmet does not use its normal-mapped shader")
	var bindings := {
		"albedo_texture": "helmet_detail_albedo",
		"source_albedo_texture": "helmet_source_albedo",
		"normal_texture": "helmet_detail_normal",
		"emission_texture": "helmet_detail_emission",
	}
	for binding: String in bindings:
		var stem: String = bindings[binding]
		var texture := finish.get_shader_parameter(binding) as Texture2D
		_check(texture != null and texture.resource_path == "res://assets/armors/thunder/textures/%s.res" % stem, "paired helmet is missing runtime " + binding)
		if texture == null:
			continue
		# Unity uses even transparent texels' RGB for surface/normal data. The
		# portable texture must retain those bytes, not apply alpha-border repair.
		var source := Image.new()
		var png_path := "res://assets/armors/thunder/textures/%s.png" % stem
		var decoded := source.load_png_from_buffer(FileAccess.get_file_as_bytes(png_path))
		_check(decoded == OK, "cannot decode paired helmet source " + binding)
		var runtime := texture.get_image()
		_check(runtime != null and not runtime.is_empty(), "paired helmet has no runtime image " + binding)
		if decoded != OK or runtime == null or runtime.is_empty():
			continue
		_check(not runtime.has_mipmaps(), "paired helmet unexpectedly generated mipmaps for " + binding)
		_check(not runtime.is_compressed(), "paired helmet unexpectedly compressed image channels for " + binding)
		_check(runtime.get_format() == source.get_format() and runtime.get_size() == source.get_size(), "paired helmet image format or size changed for " + binding)
		_check(runtime.get_data() == source.get_data(), "paired helmet lost raw source RGB/alpha data for " + binding)
	var strength: Variant = finish.get_shader_parameter("normal_strength")
	# The headless dummy renderer can return null for an unset shader default.
	# Check a material override when present; the shader supplies 0.85 otherwise.
	if strength != null:
		_check((strength is float or strength is int) and is_finite(float(strength)) and float(strength) > 0.0, "helmet engraved normal detail is disabled")
	var arrays := part.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var complete := not vertices.is_empty() and normals.size() == vertices.size() and uv.size() == vertices.size() and tangents.size() == vertices.size() * 4
	_check(complete, "normal-mapped helmet needs one complete tangent frame per vertex")
	if not complete:
		return
	var uv_bounds := Rect2(uv[0], Vector2.ZERO)
	for vertex in vertices.size():
		uv_bounds = uv_bounds.expand(uv[vertex])
		var tangent := Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2])
		var handedness := tangents[vertex * 4 + 3]
		_check(tangent.is_finite() and is_finite(handedness), "helmet has a non-finite tangent frame")
		_check(absf(tangent.length() - 1.0) < 0.03, "helmet tangent is not normalized")
		_check(absf(tangent.dot(normals[vertex])) < 0.03, "helmet tangent is not perpendicular to its normal")
		_check(absf(absf(handedness) - 1.0) < 0.001, "helmet tangent lost mirrored UV handedness")
	_check(uv_bounds.size.x > 0.5 and uv_bounds.size.y > 0.5, "helmet UVs collapse its paired texture atlas")


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
			shell._select_item(Catalog.item_key(index, 6), false)
			var preview := shell.preview_root.find_child(part_name, true, false) as MeshInstance3D
			var authored := template.find_child(part_name, true, false) as MeshInstance3D
			_check(preview != null and preview.visible, mode + " preview is missing " + part_name)
			if preview == null:
				continue
			_check(preview.get_meta("armor_rework", "") == REVISION and preview.mesh == authored.mesh, mode + " preview uses old " + part_name)
			for surface in preview.mesh.get_surface_count():
				_check(preview.get_active_material(surface) == authored.get_active_material(surface), mode + " preview overwrote " + part_name + " material")
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
		var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
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
	print("THUNDER_ARMOR_%s parts=%d triangles=%d named_binds=true mixed_equipment=true animation=true store_customize=true" % ["PASS" if failures.is_empty() else "FAIL", part_count, triangle_count])
	get_tree().quit(0 if failures.is_empty() else 1)
