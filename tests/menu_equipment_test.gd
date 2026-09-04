extends Node

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MENU EQUIPMENT TEST: " + message)


func _run() -> void:
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(menu.design_root.size.is_equal_approx(Vector2(960, 640)), "menu does not retain Unity's 960x640 design canvas")
	_check(menu.design_root.position.x >= 0.0 and menu.design_root.position.y >= 0.0, "centered design canvas escaped the viewport")
	_check(menu.main_page.get_node_or_null("ExpanseButton") == null, "removed Expanse entry returned to the main menu")
	var recovered_backdrop := menu.get_node_or_null("RecoveredMainBackdrop") as TextureRect
	_check(recovered_backdrop != null and recovered_backdrop.texture != null, "menu margins do not use the recovered Unity backdrop")
	_check(menu.main_page.find_children("*", "ColorRect", true, false).is_empty(), "main menu reintroduced generated colour overlays or divider lines")
	_check(menu.main_page.find_children("*", "Panel", true, false).is_empty(), "main menu reintroduced generated background panels")
	_check(menu.drawer.find_children("*", "Panel", true, false).is_empty(), "navigation drawer reintroduced generated background panels")
	var deployment_strip := menu.main_page.get_node_or_null("DeploymentStrip") as Control
	var solo_button := menu.main_page.get_node_or_null("DeploymentStrip/SoloButton") as TextureButton
	var online_button := menu.main_page.get_node_or_null("DeploymentStrip/MultiplayerButton") as TextureButton
	_check(deployment_strip != null and is_zero_approx(deployment_strip.position.x) and deployment_strip.position.y >= 490.0 and deployment_strip.position.y <= 640.0, "original bottom menu strip is not animating into Unity's y=490 position")
	_check(solo_button != null and solo_button.position.is_equal_approx(Vector2(90, 35)) and solo_button.size.is_equal_approx(Vector2(348, 87)), "SINGLE button does not use the original Unity placement")
	_check(online_button != null and online_button.position.is_equal_approx(Vector2(521, 35)) and online_button.size.is_equal_approx(Vector2(348, 87)), "ONLINE button does not use the original Unity placement")
	_check(menu.drawer.position.is_equal_approx(Vector2(0, -257)), "collapsed navigation drawer does not match the original top-right rank tab")
	var drawer_rank := menu.drawer_toggle.get_node_or_null("RankIcon") as TextureRect
	_check(drawer_rank != null and drawer_rank.position.is_equal_approx(Vector2(40, 15)), "main-menu rank emblem is not aligned to NavigationMenuUI's authored frame offset")
	menu._toggle_drawer(true, false)
	_check(menu.drawer.position.is_equal_approx(Vector2.ZERO), "expanded navigation drawer does not align to the top edge")
	_check(menu.drawer.get_node_or_null("OptionsButton") is TextureButton, "original OPTIONS entry is missing")
	_check(menu.drawer.get_node_or_null("BankButton") is TextureButton, "original BANK entry is missing")
	_check(menu.drawer.get_node_or_null("CustomizeButton") is TextureButton, "original CUSTOMIZE entry is missing")
	_check(menu.drawer.get_node_or_null("StoreButton") is TextureButton, "original STORE entry is missing")
	_check(menu.drawer.get_node_or_null("EditNameButton") is TextureButton, "original EDIT NAME entry is missing")
	menu._toggle_drawer(false, false)
	menu._show_armory("store")
	await get_tree().process_frame
	var shell: UnityEquipmentShell = menu.equipment_shell
	_check(is_instance_valid(shell), "shared Store/Customize shell was not created")
	if is_instance_valid(shell):
		var comparison := shell.get_node_or_null("OverallComparison") as Control
		_check(comparison != null and comparison.position.is_equal_approx(Vector2(706, 104)) and comparison.size.is_equal_approx(Vector2(240, 130)), "StoreUI overall comparison block is not at its original position")
		_check(shell.comparison_rows.size() == 3, "StoreUI is missing the authored HP/POW/SPD comparison meters")
		_check(shell.action_button.position.is_equal_approx(Vector2(43, 286)) and shell.action_button.size.is_equal_approx(Vector2(150, 58)), "StoreUI action plate does not match the original 150x58 dialog button")
		_check(not shell.currency_label.text.contains("RANK"), "StoreUI energy counter still displays the player rank")
		var store_rank_badge := shell.get_node_or_null("OriginalNavigationBar/RankBadge") as TextureRect
		var store_rank_icon: TextureRect = null
		if store_rank_badge != null:
			store_rank_icon = store_rank_badge.get_node_or_null("RankIcon") as TextureRect
		_check(store_rank_badge != null and store_rank_badge.position.is_equal_approx(Vector2(840, -14)), "StoreUI rank tab does not preserve NavigationMenuUI's off-screen origin")
		_check(store_rank_icon != null and store_rank_icon.position.is_equal_approx(Vector2(40, 15)), "StoreUI rank emblem is not aligned to its authored frame offset")
		var owned_weapons_before: Array[String] = GameState.owned_weapons.duplicate()
		GameState.owned_weapons.assign(["gun00"])
		var purchasable_weapon := ""
		for weapon_key: String in GameState.get_weapon_ids():
			if weapon_key != "gun00" and GameState.is_weapon_rank_unlocked(weapon_key):
				purchasable_weapon = weapon_key
				break
		_check(not purchasable_weapon.is_empty(), "StoreUI test could not find a rank-unlocked purchase candidate")
		if not purchasable_weapon.is_empty():
			shell._select_category("gun", false)
			shell._select_item(purchasable_weapon, false)
			_check(shell.action_button.text.ends_with("\n" + tr("BUY")), "StoreUI price and BUY label are not combined inside the original action plate")
		GameState.owned_weapons = owned_weapons_before
		shell._select_category("gun", false)
		var expected_tabs := ["head", "body", "arms", "legs", "bag", "gun"]
		_check(shell.category_buttons.keys().size() == expected_tabs.size(), "equipment shell does not expose six Unity categories")
		var selected_tag := shell.category_buttons.get("gun") as Button
		var adjacent_tag := shell.category_buttons.get("bag") as Button
		var distant_tag := shell.category_buttons.get("body") as Button
		_check(selected_tag.get_theme_stylebox("normal") is StyleBoxTexture, "selected category lost the recovered module-17 frame")
		_check(adjacent_tag.get_theme_stylebox("normal") is StyleBoxTexture, "inactive category lost the recovered module-17 frame")
		_check(adjacent_tag.modulate.is_equal_approx(Color.WHITE), "inactive category icon is still artificially dimmed")
		_check(selected_tag.z_index > adjacent_tag.z_index and adjacent_tag.z_index > distant_tag.z_index, "category draw order does not follow UISliderTag scale sorting")
		var hp_track_glow := shell.get_node_or_null("OverallComparison/HPComparison/AuthoredMeter/TrackGlow") as TextureRect
		_check(hp_track_glow != null and hp_track_glow.modulate.a >= 0.2, "upper-right comparison slot is still too dark")
		_check(shell.slot_picker.get_theme_stylebox("normal") is StyleBoxFlat, "loadout slot picker has no bright custom frame")
		for category_key: String in expected_tabs:
			_check(shell.category_buttons.has(category_key), "missing category tab: " + category_key)
			shell._select_category(category_key, false)
			await get_tree().process_frame
			var expected_count := GameState.get_weapon_ids().size() if category_key == "gun" else GameState.get_armor_ids(category_key).size()
			_check(shell.item_row.get_child_count() == expected_count, "%s carousel count differs from GameState" % category_key)
		var horizontal_bar := shell.item_scroll.get_h_scroll_bar()
		_check(not horizontal_bar.visible or is_zero_approx(horizontal_bar.self_modulate.a), "equipment carousel exposes a desktop scrollbar")
		shell._select_category("gun", false)
		var weapon_ids := GameState.get_weapon_ids()
		var swipe_start := shell.selected_item_key
		var swipe_start_index := weapon_ids.find(swipe_start)
		shell.item_swipe_distance = -shell.SWIPE_THRESHOLD - 1.0
		shell._commit_item_swipe()
		_check(shell.selected_item_key == weapon_ids[posmod(swipe_start_index + 1, weapon_ids.size())], "left swipe does not select the next equipment item")
		shell.item_swipe_distance = shell.SWIPE_THRESHOLD + 1.0
		shell._commit_item_swipe()
		_check(shell.selected_item_key == swipe_start, "right swipe does not select the previous equipment item")
		shell.category_swipe_distance = -shell.SWIPE_THRESHOLD - 1.0
		shell._commit_category_swipe()
		_check(shell.selected_category == "head", "category carousel does not loop forward from gun to head")
		shell.category_swipe_distance = shell.SWIPE_THRESHOLD + 1.0
		shell._commit_category_swipe()
		_check(shell.selected_category == "gun", "category carousel does not loop backward from head to gun")
		_check(shell.slot_picker.item_count >= 1, "Gun customize screen has no bag-slot picker")
		for material_case: Dictionary in [
			{"key": "gun22", "effects": [1, 2], "solid": 0, "blend": BaseMaterial3D.BLEND_MODE_MIX},
			{"key": "gun23", "effects": [0, 1], "solid": 2, "blend": BaseMaterial3D.BLEND_MODE_ADD},
			{"key": "gun37", "effects": [1, 2], "solid": 0, "blend": BaseMaterial3D.BLEND_MODE_ADD},
		]:
			shell._select_item(str(material_case.key), false)
			await get_tree().process_frame
			var preview_mesh := _first_preview_mesh(shell.preview_root)
			_check(is_instance_valid(preview_mesh), "%s store preview mesh was not created" % material_case.key)
			if is_instance_valid(preview_mesh):
				var solid := preview_mesh.get_surface_override_material(int(material_case.solid)) as StandardMaterial3D
				_check(solid != null and solid.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "%s solid surface is not opaque" % material_case.key)
				for surface_index: int in material_case.effects:
					var effect := preview_mesh.get_surface_override_material(surface_index) as StandardMaterial3D
					_check(effect != null and effect.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "%s effect surface lacks alpha blending" % material_case.key)
					_check(effect != null and effect.cull_mode == BaseMaterial3D.CULL_DISABLED and effect.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s effect surface did not recover the two-sided unshaded Unity material" % material_case.key)
					_check(effect != null and effect.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and effect.blend_mode == int(material_case.blend), "%s effect surface has the wrong depth/blend mode" % material_case.key)
		for effect_case: Dictionary in [
			{"key": "gun28", "name": "passer-standard_1", "blend": BaseMaterial3D.BLEND_MODE_MIX},
			{"key": "gun34", "name": "sniper_effect", "blend": BaseMaterial3D.BLEND_MODE_MIX},
			{"key": "gun41", "name": "gunchristmas_02", "blend": BaseMaterial3D.BLEND_MODE_ADD},
			{"key": "gun41", "name": "orig_standard_7", "blend": BaseMaterial3D.BLEND_MODE_MIX},
			{"key": "gun45", "name": "hotwing_qiangkou", "blend": BaseMaterial3D.BLEND_MODE_ADD},
		]:
			shell._select_item(str(effect_case.key), false)
			await get_tree().process_frame
			var effect_preview := _first_preview_mesh(shell.preview_root)
			var named_effect := _preview_material_by_name(effect_preview, str(effect_case.name))
			_check(named_effect != null, "%s preview is missing classified material %s" % [effect_case.key, effect_case.name])
			_check(named_effect != null and named_effect.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and named_effect.blend_mode == int(effect_case.blend), "%s material %s has the wrong Unity blend mode" % [effect_case.key, effect_case.name])
		for solid_key: String in ["gun24", "gun44"]:
			shell._select_item(solid_key, false)
			await get_tree().process_frame
			var solid_preview := _first_preview_mesh(shell.preview_root)
			var solid_material := solid_preview.get_surface_override_material(0) as StandardMaterial3D
			_check(solid_material != null and solid_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, solid_key + " black-Kd solid material became transparent")
			_check(solid_material != null and solid_material.albedo_color.r > 0.99 and solid_material.albedo_color.g > 0.99 and solid_material.albedo_color.b > 0.99, solid_key + " black-Kd solid material was not normalized to white")
		shell.set_mode("customize", false)
		shell._select_category("head", false)
		await get_tree().process_frame
		var preview_head_key := GameState.get_armor_ids("head")[-1]
		shell._select_item(preview_head_key, false)
		await get_tree().process_frame
		var expected_visual_ids := {}
		for part_key: String in ["head", "body", "arms", "legs"]:
			var armor_key := preview_head_key if part_key == "head" else GameState.get_equipped_armor_key(part_key)
			expected_visual_ids[part_key] = int(GameState.get_armor_item(armor_key).get("visual_id", 0))
		var expected_mesh_names := [
			"ArmorHead_%02d" % int(expected_visual_ids.head),
			"ArmorBody_%02d" % int(expected_visual_ids.body),
			"ArmorHand_%02d" % int(expected_visual_ids.arms),
			"ArmorFoot_%02d" % int(expected_visual_ids.legs),
		]
		var visible_armor_names: Array[String] = []
		var all_armor_names: Array[String] = []
		for candidate in shell.preview_root.find_children("*", "MeshInstance3D", true, false):
			var armor_mesh := candidate as MeshInstance3D
			all_armor_names.append(armor_mesh.name)
			if armor_mesh.visible:
				visible_armor_names.append(armor_mesh.name)
		_check(visible_armor_names.size() == 4, "animated armor preview does not show exactly four equipped pieces")
		for expected_mesh_name: String in expected_mesh_names:
			_check(visible_armor_names.has(expected_mesh_name), "animated armor preview is missing " + expected_mesh_name)
		for visual_id in range(21):
			for mesh_prefix: String in ["ArmorHead", "ArmorBody", "ArmorHand", "ArmorFoot"]:
				var variant_name := "%s_%02d" % [mesh_prefix, visual_id]
				_check(all_armor_names.has(variant_name), "animated armor preview scene is missing " + variant_name)
		_check(shell.preview_root.find_child("RecoveredArmorAvatar", true, false) != null, "armor preview did not instance animated/player.gltf")
		var preview_animation_player: AnimationPlayer = null
		for candidate in shell.preview_root.find_children("*", "AnimationPlayer", true, false):
			preview_animation_player = candidate as AnimationPlayer
			break
		_check(preview_animation_player != null and preview_animation_player.has_animation("idle_rifle"), "armor preview has no recovered idle animation")
		if preview_animation_player != null and preview_animation_player.has_animation("idle_rifle"):
			_check(preview_animation_player.get_animation("idle_rifle").loop_mode == Animation.LOOP_LINEAR, "armor preview idle animation is not looping")
		var exp_item_key := ""
		for part_key: String in ["head", "body", "arms", "legs", "bag"]:
			for armor_key: String in GameState.get_armor_ids(part_key):
				if not is_zero_approx(float(GameState.get_armor_item(armor_key).skills.get("exp_boost", 0.0))):
					exp_item_key = armor_key
					shell._select_category(part_key, false)
					break
			if not exp_item_key.is_empty():
				break
		_check(not exp_item_key.is_empty(), "armor catalog has no EXP boost sample")
		if not exp_item_key.is_empty():
			shell._select_item(exp_item_key, false)
			var exp_value := float(GameState.get_armor_item(exp_item_key).skills.exp_boost)
			var exp_notice := tr("EXP BOOST %s • XP SYSTEM NOT RESTORED") % shell._compact_value(exp_value)
			_check(shell.description_text.text.contains(exp_notice), "inactive EXP boost is not disclosed in the armor UI")
		var armor_before_set_exp: Dictionary = GameState.equipped_armor.duplicate(true)
		for set_part_key: String in ["head", "body", "arms", "legs"]:
			GameState.equipped_armor[set_part_key] = "armor_%s_08" % set_part_key
		shell._select_category("head", false)
		shell._select_item("armor_head_08", false)
		var set_exp_value := float(GameState.ARMOR_SET_BONUSES[8].skills.exp_boost)
		var set_exp_notice := tr("SET EXP BOOST %s • XP SYSTEM NOT RESTORED") % shell._compact_value(set_exp_value)
		_check(shell.description_text.text.contains(set_exp_notice), "inactive full-set EXP boost is not disclosed in the armor UI")
		GameState.equipped_armor = armor_before_set_exp
		shell._select_category("bag", false)
		for bag_key: String in GameState.get_armor_ids("bag"):
			var resource_id := int(GameState.get_armor_item(bag_key).get("visual_id", 0))
			var resource_name := "ArmorBag_%02d" % resource_id
			var resource_path := "res://assets/models/player/animated/bags/%s/%s.obj" % [resource_name, resource_name]
			_check(ResourceLoader.exists(resource_path), "bag preview resource is missing " + resource_path)
		var preview_bag_key := GameState.get_armor_ids("bag")[-1]
		shell._select_item(preview_bag_key, false)
		await get_tree().process_frame
		var bag_visual_id := int(GameState.get_armor_item(preview_bag_key).get("visual_id", 0))
		var bag_mesh_name := "ArmorBag_%02d" % bag_visual_id
		_check(shell.preview_root.find_child(bag_mesh_name, true, false) is MeshInstance3D, "bag preview did not load " + bag_mesh_name + ".obj")
		var bag_bounds := _visible_preview_bounds(shell.preview_root)
		_check(not bag_bounds.size.is_zero_approx(), "bag preview has no visible geometry")
		_check((bag_bounds.position + bag_bounds.size * 0.5).length() < 0.05, "bag preview is not centered on the turntable")
		var loadout_before_small_bag: Array[String] = GameState.battle_weapons.duplicate()
		var owned_before_small_bag: Array[String] = GameState.owned_weapons.duplicate()
		var armor_before_small_bag: Dictionary = GameState.equipped_armor.duplicate(true)
		GameState.battle_weapons.assign(["gun00", "gun01", "gun02", "gun03"])
		GameState.owned_weapons.assign(["gun00", "gun01", "gun02", "gun03"])
		GameState.equipped_armor["bag"] = "armor_bag_00"
		shell._select_category("gun", false)
		shell._select_item("gun03", false)
		_check(shell._get_item_state("gun02") == "equipped", "weapon inside the small bag is not shown as equipped")
		_check(shell._get_item_state("gun03") == "owned", "weapon beyond the small bag capacity is not shown as stored/owned")
		_check(shell.action_button.text == tr("EQUIP") and not shell.action_button.disabled, "stored overflow weapon cannot be assigned to an active bag slot")
		shell._refresh_loadout_summary()
		var loadout_lines := shell.loadout_label.text.split("\n")
		_check(loadout_lines.size() >= 2 and loadout_lines[1].ends_with("3/3"), "small-bag summary reports stored weapons as active slots")
		GameState.battle_weapons = loadout_before_small_bag
		GameState.owned_weapons = owned_before_small_bag
		GameState.equipped_armor = armor_before_small_bag
		shell._select_category("head", false)
		await get_tree().process_frame
		var equipped_head := GameState.get_equipped_armor_key("head")
		shell._select_item(equipped_head, false)
		_check(shell._get_item_state(equipped_head) == "equipped", "equipped armor is not identified as equipped")
		_check(shell.action_button.disabled and shell.action_button.text == tr("EQUIPPED"), "Customize does not lock the already-equipped item")
		for child in shell.get_children():
			if child is Control:
				var control := child as Control
				var rect := Rect2(control.position, control.size)
				_check(rect.position.x >= -0.1 and rect.position.y >= -0.1 and rect.end.x <= 960.1 and rect.end.y <= 640.1, "%s overflows the 960x640 shell" % control.name)
	menu.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	var native_viewport := SubViewport.new()
	native_viewport.size = Vector2i(960, 640)
	native_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(native_viewport)
	var native_menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	native_viewport.add_child(native_menu)
	await get_tree().process_frame
	_check(native_menu.design_root.scale.is_equal_approx(Vector2.ONE), "960x640 viewport does not render the Unity canvas at native scale")
	_check(native_menu.design_root.position.is_equal_approx(Vector2.ZERO), "960x640 viewport unnecessarily letterboxes the Unity canvas")
	native_menu._show_armory("store")
	await get_tree().process_frame
	for child in native_menu.equipment_shell.get_children():
		if child is Control:
			var native_control := child as Control
			var native_rect := Rect2(native_control.position, native_control.size)
			_check(native_rect.position.x >= -0.1 and native_rect.position.y >= -0.1 and native_rect.end.x <= 960.1 and native_rect.end.y <= 640.1, "%s overflows the native 960x640 viewport" % native_control.name)
	native_viewport.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("MENU_EQUIPMENT_TEST_PASS tabs=6 armor=%d weapons=%d" % [GameState.ARMOR_ITEMS.size(), GameState.WEAPONS.size()])
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _first_preview_mesh(root: Node) -> MeshInstance3D:
	var selected_weapon := root.find_child("SelectedWeapon", true, false) as MeshInstance3D
	if selected_weapon != null and selected_weapon.visible:
		return selected_weapon
	for child in root.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D and (child as MeshInstance3D).visible:
			return child as MeshInstance3D
	return null


func _visible_preview_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var root_inverse := root.global_transform.affine_inverse()
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if not mesh_instance.visible or mesh_instance.mesh == null:
			continue
		var relative_transform := root_inverse * mesh_instance.global_transform
		var candidate_bounds: AABB = relative_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(candidate_bounds) if has_bounds else candidate_bounds
		has_bounds = true
	return bounds


func _preview_material_by_name(preview_mesh: MeshInstance3D, material_name: String) -> StandardMaterial3D:
	if preview_mesh == null or preview_mesh.mesh == null:
		return null
	for surface_index in preview_mesh.mesh.get_surface_count():
		var source := preview_mesh.mesh.surface_get_material(surface_index)
		if source != null and source.resource_name.to_lower() == material_name:
			return preview_mesh.get_surface_override_material(surface_index) as StandardMaterial3D
	return null
