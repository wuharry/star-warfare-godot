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
	GameState.save_path = "user://callofmini_gameplay_test.json"
	GameState.selected_weapon = "gun00"
	GameState.credits = 200000
	GameState.equipped_armor = {"head": "armor_head_00", "body": "armor_body_00", "arms": "armor_arms_00", "legs": "armor_legs_00", "bag": "armor_bag_00"}
	GameState.owned_armor.assign(GameState.equipped_armor.values())
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	var skeleton: Skeleton3D = player.recovered_skeleton
	var animation_player: AnimationPlayer = player.recovered_animation_player
	for instance: MeshInstance3D in player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
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
		for part in range(4):
			var key := Catalog.item_key(part, set_id)
			_check(GameState.purchase_armor(key) == "purchased", "could not purchase " + key)
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
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = GameState.save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("CALLOFMINI_GAMEPLAY_TEST_PASS sets=8 parts=32 mixed=true animation=true")
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
	for surface in instance.mesh.get_surface_count():
		var material := instance.get_active_material(surface) as BaseMaterial3D
		_check(material != null and material.albedo_texture != null and material.albedo_texture.resource_path.begins_with("res://assets/callOfMini/enhanced/"), "additional armor lost its restored atlas")
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
