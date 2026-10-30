extends Node

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const PART_NAMES := ["ArmorHead", "ArmorBody", "ArmorHand", "ArmorFoot"]
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CALLOFMINI GAMEPLAY TEST: " + message)


func _run() -> void:
	if not GameState.save_path.begins_with("user://star_warfare_test_"):
		push_error("Run with -- --test-profile=<unique_identifier>")
		get_tree().quit(1)
		return
	var test_save := GameState.save_path
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	# This suite tests fitting and whole-suit ownership, not low-rank rejection.
	# Fund the exact recovered catalog totals; never depend on a player's save.
	GameState.credits = 0
	GameState.mithril = 0
	GameState.experience = 20000000
	for row: Dictionary in Catalog.CoMSource.ARMOR_SETS.values():
		GameState.credits += int(row.credits)
		GameState.mithril += int(row.premium)
	GameState.equipped_armor = {"head": "armor_head_00", "body": "armor_body_00", "arms": "armor_arms_00", "legs": "armor_legs_00", "bag": "armor_bag_00"}
	GameState.owned_armor.assign(GameState.equipped_armor.values())
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	var skeleton: Skeleton3D = player.recovered_skeleton
	var animation_player: AnimationPlayer = player.recovered_animation_player
	var original_avatar := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	for instance: MeshInstance3D in player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			if instance.has_meta("armor_rework"):
				continue # Viper intentionally uses the retained painted-armor shader.
			var material := instance.get_active_material(surface) as BaseMaterial3D
			_check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s lost Unity's unlit armor shader" % instance.name)
	var bag_material := player.backpack_visual.get_active_material(0) as BaseMaterial3D
	_check(bag_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "starter backpack still depends on dark scene lighting")
	_check(bag_material.albedo_color.is_equal_approx(Color.WHITE), "starter backpack applied the source shader's unused gray _Color")
	GameState.equipped_armor.bag = "armor_bag_15"
	player._refresh_recovered_backpack()
	await get_tree().process_frame
	for surface in player.backpack_visual.mesh.get_surface_count():
		var special_material := player.backpack_visual.get_active_material(surface) as BaseMaterial3D
		var special_source := player.backpack_visual.mesh.surface_get_material(surface) as BaseMaterial3D
		_check(special_material.shading_mode == special_source.shading_mode, "starter backpack fix altered the special bag 15 material")
	GameState.equipped_armor.bag = "armor_bag_00"
	player._refresh_recovered_backpack()
	await get_tree().process_frame
	animation_player.play("idle_rifle")
	animation_player.seek(0.0, true)
	animation_player.pause()
	var original_bounds := _posed_bounds(player.recovered_avatar, skeleton)
	print("CALLOFMINI_BASELINE idle_size=", original_bounds.size, " min=", original_bounds.position)
	for set_id in range(21, 29):
		var source_row: Dictionary = Catalog.CoMSource.ARMOR_SETS[str(set_id)]
		var credit_before := GameState.credits
		var mithril_before := GameState.mithril
		var owned_before := GameState.owned_armor.size()
		var first_key := Catalog.item_key(0, set_id)
		_check(bool(GameState.ARMOR_ITEMS[first_key].purchase_whole_set), "CoM item lost its whole-suit contract")
		_check(GameState.purchase_armor(first_key) == "purchased", "could not purchase whole suit %d" % set_id)
		_check(credit_before - GameState.credits == int(source_row.credits) and mithril_before - GameState.mithril == int(source_row.premium), "whole suit did not charge the exact source price: %d" % set_id)
		_check(GameState.owned_armor.size() == owned_before + 4, "whole suit must grant exactly four parts")
		credit_before = GameState.credits
		mithril_before = GameState.mithril
		for part in range(4):
			var key := Catalog.item_key(part, set_id)
			_check(GameState.is_armor_owned(key), "whole-suit purchase did not grant " + key)
			_check(GameState.purchase_armor(key) == "owned", "repeat suit-part purchase must return owned: " + key)
		_check(GameState.credits == credit_before and GameState.mithril == mithril_before and GameState.owned_armor.size() == owned_before + 4, "owned suit parts were charged or granted twice")
		_check(GameState.equip_armor_set(set_id), "could not equip set %d" % set_id)
		_validate_visible_parts(player.recovered_avatar, [set_id, set_id, set_id, set_id])
		_check(player.recovered_avatar.find_children("*", "Skeleton3D", true, false).size() == 1, "additional armor created a second skeleton")
		_check(animation_player.get_animation_list().size() == 79, "additional armor replaced the animation library")
		_check(player.gun_socket.bone_name == "r hand gun" and player.backpack_socket.bone_name == "fly_bag", "additional armor broke weapon/backpack sockets")
		for part in range(4):
			var mesh := player.recovered_avatar.find_child("%s_%02d" % [PART_NAMES[part], set_id], true, false) as MeshInstance3D
			_validate_skin(mesh, skeleton)
			var thumbnail := "res://assets/ui/armor_thumbnails/armor_%s_%02d.png" % [Catalog.PART_KEYS[part], set_id]
			_check(ResourceLoader.exists(thumbnail), "missing thumbnail " + thumbnail)
		_validate_source_geometry(player.recovered_avatar, set_id)
		animation_player.play("idle_rifle")
		animation_player.seek(0.0, true)
		animation_player.pause()
		var bounds := _posed_bounds(player.recovered_avatar, skeleton)
		var ratio := bounds.size / original_bounds.size
		_check(ratio.y > 0.85 and ratio.y < 1.12, "set %d height differs from current armor: %s" % [set_id, ratio])
		_check(ratio.x > 0.75 and ratio.x < 1.25, "set %d width differs from current armor: %s" % [set_id, ratio])
		_check(absf(bounds.position.y - original_bounds.position.y) < 0.16, "set %d boots drifted away from the ground" % set_id)
		print("CALLOFMINI_FIT set=%d idle_size=%s ratio=%s" % [set_id, bounds.size, ratio])
		animation_player.play("run_rifle")
		animation_player.seek(0.0, true)
		var legs := player.recovered_avatar.find_child("ArmorFoot_%02d" % set_id, true, false) as MeshInstance3D
		var before := _posed_vertices(legs, skeleton)
		animation_player.seek(0.2, true)
		animation_player.pause()
		var after := _posed_vertices(legs, skeleton)
		var largest_motion := 0.0
		for vertex in before.size():
			largest_motion = maxf(largest_motion, before[vertex].distance_to(after[vertex]))
		_check(largest_motion > 0.1, "set %d legs did not deform with the run animation" % set_id)
	# Mix original and additional parts, then return to the starter set; repeated
	# selection must reuse the same meshes and never leave a hidden whole suit.
	for part in range(4):
		var mixed_id: int = [21, 0, 27, 28][part]
		_check(GameState.equip_armor(Catalog.item_key(part, mixed_id)), "could not equip mixed part")
	_validate_visible_parts(player.recovered_avatar, [21, 0, 27, 28])
	_check(GameState.get_equipped_set_id() == -1, "mixed originals/additions retained a full set")
	_check(GameState.equip_armor_set(0), "could not return to Viper")
	_validate_visible_parts(player.recovered_avatar, [0, 0, 0, 0])
	_check(player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false).size() == 116, "armor selection duplicated meshes")
	player.free()
	original_avatar.free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.25).timeout
	_check(GameState.save_path == test_save, "test changed its isolated profile path")
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = test_save + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("CALLOFMINI_GAMEPLAY_TEST_PASS sets=8 parts=32 source_topology=true whole_suit=true mixed=true animation=true")
	get_tree().quit(0 if failures.is_empty() else 1)


func _validate_visible_parts(avatar: Node3D, ids: Array) -> void:
	var visible: Array[String] = []
	for instance: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if instance.visible:
			visible.append(instance.name)
	_check(visible.size() == 4, "expected four visible armor parts, got %s" % [visible])
	for part in range(4):
		_check(visible.has("%s_%02d" % [PART_NAMES[part], ids[part]]), "missing selected armor part")


func _validate_skin(instance: MeshInstance3D, skeleton: Skeleton3D) -> void:
	_check(instance != null and instance.skin != null, "additional armor has no Skin")
	if instance == null or instance.skin == null:
		return
	_check(instance.get_node_or_null(instance.skeleton) == skeleton, "%s does not use the player's skeleton" % instance.name)
	_check(instance.skin.get_bind_count() == skeleton.get_bone_count(), "%s changed the target rig's bind count" % instance.name)
	for bind in instance.skin.get_bind_count():
		var bone_name := instance.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(bone_name)
		_check(not bone_name.is_empty() and bone >= 0, "%s has an unknown named bind" % instance.name)
		if bone >= 0:
			_check((skeleton.get_bone_global_rest(bone) * instance.skin.get_bind_pose(bind)).is_equal_approx(Transform3D.IDENTITY), "%s changed its retargeted bind pose" % instance.name)
	for surface in instance.mesh.get_surface_count():
		var material := instance.get_active_material(surface) as BaseMaterial3D
		var texture_path := material.albedo_texture.resource_path if material != null and material.albedo_texture != null else ""
		var set_id := int(String(instance.name).get_slice("_", 1))
		var source_directory := "res://assets/callOfMini/enhanced/%s/" % Catalog.SET_NAMES[set_id]
		_check(texture_path.begins_with(source_directory), "additional armor lost its own original CoM atlas: " + texture_path)
		_check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "additional armor lost its baked-lighting material mode")
		var arrays := instance.mesh.surface_get_arrays(surface)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for vertex in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			var weight_sum := 0.0
			for influence in range(4):
				var index := vertex * 4 + influence
				weight_sum += weights[index]
				_check(bones[index] >= 0 and bones[index] < instance.skin.get_bind_count(), "invalid skin bind index")
			_check(absf(weight_sum - 1.0) < 0.002, "vertex weights do not sum to one")


func _validate_source_geometry(avatar: Node3D, set_id: int) -> void:
	var source_path := "res://assets/callOfMini/enhanced/%s/%s.tscn" % [Catalog.SET_NAMES[set_id], Catalog.CALLOFMINI_MODELS[set_id - Catalog.CALLOFMINI_FIRST_ID]]
	var original := (load(source_path) as PackedScene).instantiate()
	var source_faces: Dictionary = {}
	var runtime_faces: Dictionary = {}
	var materials: Dictionary = {}
	for source: MeshInstance3D in original.find_children("*", "MeshInstance3D", true, false):
		_add_source_faces(source, source_faces)
		for surface in source.mesh.get_surface_count():
			var material := source.get_active_material(surface) as BaseMaterial3D
			_check(material != null and material.albedo_texture != null, "source CoM surface has no atlas")
			if material != null and material.albedo_texture != null:
				materials[material.albedo_texture.resource_path] = material
	for part in range(4):
		var instance := avatar.find_child("%s_%02d" % [PART_NAMES[part], set_id], true, false) as MeshInstance3D
		if instance == null: continue # Missing parts are asserted by visibility/skin checks.
		_add_source_faces(instance, runtime_faces)
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as BaseMaterial3D
			if material == null or material.albedo_texture == null: continue
			var source := materials.get(material.albedo_texture.resource_path) as BaseMaterial3D
			_check(source != null, str(instance.name) + " uses an atlas absent from its original suit")
			if source == null: continue
			_check(material.albedo_texture == source.albedo_texture and material.albedo_color == source.albedo_color, str(instance.name) + " changed original texture or tint")
			_check(material.transparency == source.transparency and material.cull_mode == source.cull_mode and material.texture_filter == source.texture_filter, str(instance.name) + " changed original material rendering")
	# Retargeting changes vertex positions to fit the player, while preserving
	# every source triangle's ordered UV corners and material, exactly once.
	_check(not source_faces.is_empty() and runtime_faces == source_faces, "set %d replaced/subdivided/lost source triangles or UV/material assignments" % set_id)
	original.free()


func _add_source_faces(instance: MeshInstance3D, faces: Dictionary) -> void:
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := instance.get_active_material(surface) as BaseMaterial3D
		if material == null or material.albedo_texture == null: continue
		_check(indices.size() > 0 and indices.size() % 3 == 0, str(instance.name) + " has incomplete source triangle topology")
		for offset in range(0, indices.size(), 3):
			var corners := PackedVector2Array()
			for corner in range(3):
				corners.append(uv[indices[offset + corner]])
			var key := material.albedo_texture.resource_path + ":" + corners.to_byte_array().hex_encode()
			faces[key] = int(faces.get(key, 0)) + 1


func _posed_bounds(avatar: Node3D, skeleton: Skeleton3D) -> AABB:
	var bounds := AABB()
	var started := false
	for instance: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if not instance.visible:
			continue
		for point: Vector3 in _posed_vertices(instance, skeleton):
			bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return bounds


func _posed_vertices(instance: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			var point := Vector3.ZERO
			for influence in range(4):
				var index := vertex * 4 + influence
				if weights[index] <= 0.0:
					continue
				var bind_index := bones[index]
				var bone := skeleton.find_bone(instance.skin.get_bind_name(bind_index))
				point += (skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind_index) * vertices[vertex]) * weights[index]
			points.append(point)
	return points
