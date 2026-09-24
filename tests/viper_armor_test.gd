extends Node3D

const Visuals = preload("res://scripts/game/armor_visuals.gd")
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("VIPER_ARMOR: " + message)


func _run() -> void:
	GameState.save_path = "user://viper_armor_test_profile.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_weapon = "gun00"
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	var avatar := player.recovered_avatar
	var skeleton := player.recovered_skeleton
	var scene_path := Visuals.reworked_scene_path(0)
	var angular := scene_path == "res://assets/armors/angular/armor_00.scn"
	var expected_shader := "res://assets/armors/angular/armor_surface.gdshader" if angular else "res://assets/armors/viper/painted_armor.gdshader"
	var expected_revision := "angular_armor_v1" if angular else "viper_original_refined"
	var template := (load(scene_path) as PackedScene).instantiate()
	var triangle_count := 0
	var part_count := 0
	for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
		var part := avatar.find_child(prefix + "00", true, false) as MeshInstance3D
		_check(part != null and part.has_meta("armor_rework"), prefix + " was not replaced")
		if part == null:
			continue
		var authored := template.find_child(str(part.name), true, false) as MeshInstance3D
		_check(authored != null and part.mesh == authored.mesh, prefix + " does not use the shared loader's Viper geometry")
		_check(part.get_meta("armor_rework", "") == expected_revision, prefix + " has the wrong Viper revision")
		part_count += 1
		_check(part.visible and part.skin != null, prefix + " is hidden or has no skin")
		_check(part.get_node_or_null(part.skeleton) == skeleton, prefix + " uses another skeleton")
		for bind in part.skin.get_bind_count():
			var bone := skeleton.find_bone(part.skin.get_bind_name(bind))
			_check(bone >= 0, prefix + " has an unknown named bind")
			if bone >= 0:
				var identity := skeleton.get_bone_global_rest(bone) * part.skin.get_bind_pose(bind)
				_check(identity.is_equal_approx(Transform3D.IDENTITY), prefix + " inverse bind changes the rest pose")
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as ShaderMaterial
			_check(material != null and material.shader.resource_path == expected_shader, prefix + " lost the selected Viper surface shader")
			_check(authored != null and material == authored.get_active_material(surface), prefix + " has an unexpected material override")
			if material != null:
				var texture := material.get_shader_parameter("albedo_texture") as Texture2D
				_check(texture != null and texture.resource_path.begins_with("res://assets/armors/viper/textures/"), prefix + " lost its Viper paint")
				if angular:
					_check(float(material.get_shader_parameter("readable_fill")) <= 0.25, prefix + " lost dynamic lighting")
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangle_count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			for vertex in vertices.size():
				_check(vertices[vertex].is_finite() and normals[vertex].is_finite(), prefix + " non-finite geometry")
				_check(normals[vertex].length() > 0.95, prefix + " invalid normals")
				var sum := 0.0
				for influence in range(4):
					var index := vertex * 4 + influence
					_check(bones[index] >= 0 and bones[index] < part.skin.get_bind_count(), prefix + " invalid bone index")
					sum += weights[index]
				_check(absf(sum - 1.0) < 0.0001, prefix + " unnormalized weights")
	_check(part_count == 4, "Viper does not have four exchangeable parts")
	# Repeated swaps must not accumulate nodes or restore old materials on Viper.
	var child_count := skeleton.get_child_count()
	for cycle in range(3):
		GameState.equipped_armor = {"head": "armor_head_02", "body": "armor_body_00", "arms": "armor_arms_21", "legs": "armor_legs_00", "bag": "armor_bag_00"}
		player._apply_recovered_armor_visibility()
		_check_visible(avatar, ["ArmorHead_02", "ArmorBody_00", "ArmorHand_21", "ArmorFoot_00"])
		GameState.equipped_armor = GameState._default_armor_equipment()
		player._apply_recovered_armor_visibility()
		_check_visible(avatar, ["ArmorHead_00", "ArmorBody_00", "ArmorHand_00", "ArmorFoot_00"])
	var after_initial_swap := skeleton.get_child_count()
	for cycle in range(10):
		player._apply_recovered_armor_visibility()
	_check(skeleton.get_child_count() == after_initial_swap, "repeated equip duplicates meshes")
	_check(after_initial_swap >= child_count, "rework deleted unrelated nodes")
	avatar.remove_meta("unity_armor_materials_restored")
	Visuals.ensure_parts(avatar, {"head": 0})
	var head := avatar.find_child("ArmorHead_00", true, false) as MeshInstance3D
	var authored_head := template.find_child("ArmorHead_00", true, false) as MeshInstance3D
	_check(head.get_active_material(0) == authored_head.get_active_material(0), "material restore overwrote Viper")
	var legacy := avatar.find_child("ArmorHead_02", true, false) as MeshInstance3D
	var legacy_template := (load(Visuals.reworked_scene_path(2)) as PackedScene).instantiate()
	var authored_legacy := legacy_template.find_child("ArmorHead_02", true, false) as MeshInstance3D
	_check(legacy.mesh == authored_legacy.mesh and legacy.get_active_material(0) == authored_legacy.get_active_material(0), "Viper equip changed accepted set 02")
	legacy_template.free()
	template.free()
	player.queue_free()
	await get_tree().process_frame
	print("VIPER_ARMOR_%s parts=%d triangles=%d mixed_equipment=true named_binds=true materials=true" % ["PASS" if failures.is_empty() else "FAIL", part_count, triangle_count])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_visible(avatar: Node3D, expected: Array) -> void:
	var actual: Array[String] = []
	for candidate: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if candidate.visible:
			actual.append(candidate.name)
	_check(actual.size() == expected.size(), "mixed equipment displays extra pieces")
	for name: String in expected:
		_check(actual.has(name), "mixed equipment is missing " + name)
