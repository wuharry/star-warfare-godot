extends Node

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MENU EQUIPMENT TEST: " + message)


func _run() -> void:
	# Exercise the actual purchase/equip signals without touching the player's save.
	var original_save_path := GameState.save_path
	var test_save_path := "user://menu_equipment_test_%d.json" % Time.get_ticks_usec()
	GameState.save_path = test_save_path
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
		_check(shell.desktop_layout and shell.size.is_equal_approx(UnityEquipmentShell.DESKTOP_DESIGN_SIZE), "widescreen armory did not activate the desktop canvas")
		_check(shell.section_buttons.size() == 2, "desktop armory is missing GEAR/SUPPLY navigation")
		_check(shell.desktop_equipment_buttons.size() == 6, "desktop armory does not expose all six equipment categories")
		_check(shell.supply_buttons.size() == 3, "desktop armory does not expose all three original supply categories")
		_check(shell.category_layer.visible, "equipment catalog has no visible category controls")
		var gear_section := shell.section_buttons.get("equipment") as Button
		var gun_catalog := shell.desktop_equipment_buttons.get("gun") as Button
		var gear_style := gear_section.get_theme_stylebox("normal") as StyleBoxTexture
		var gun_style := gun_catalog.get_theme_stylebox("normal") as StyleBoxTexture
		_check(gear_style != null and gear_style.texture.resource_path.begins_with("res://assets/ui/components/"), "shelf switch does not use the recovered UI art")
		_check(gun_style != null and gun_style.texture.resource_path.ends_with("button_pressed.png"), "desktop category does not use the original long button plate")
		_check(shell.weapon_filter_picker is OptionButton and shell.weapon_filter_picker.item_count == 6, "desktop armory is missing the compact weapon type filter")
		_check_store_layout(shell)
		_check(shell.comparison_rows.size() == 3, "StoreUI is missing the authored HP/POW/SPD comparison meters")
		_check(not shell.currency_label.text.contains("RANK"), "StoreUI energy counter still displays the player rank")
		var store_rank_badge := shell.get_node_or_null("OriginalNavigationBar/RankBadge") as Control
		var store_rank_icon: TextureRect = null
		if store_rank_badge != null:
			store_rank_icon = store_rank_badge.get_node_or_null("RankIcon") as TextureRect
		_check(store_rank_badge != null and _contains_control(shell, store_rank_badge), "StoreUI rank badge is clipped outside the screen")
		_check(store_rank_icon != null and store_rank_icon.texture != null, "StoreUI rank emblem is missing")
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
			_check(shell.action_button.text == tr("BUY") and not shell.action_button.disabled, "purchasable weapon has no enabled single-line BUY action")
			_check(shell.price_label.is_visible_in_tree() and not shell.price_label.text.is_empty(), "purchase price is not visible separately from BUY")
		GameState.owned_weapons = owned_weapons_before
		shell._select_category("gun", false)
		var expected_tabs := ["head", "body", "arms", "legs", "bag", "gun"]
		_check(shell.category_buttons.keys().size() == expected_tabs.size(), "equipment shell does not expose six Unity categories")
		var selected_tag := shell.category_buttons.get("gun") as Button
		var adjacent_tag := shell.category_buttons.get("bag") as Button
		var category_positions := {}
		for category_key: String in expected_tabs:
			category_positions[category_key] = (shell.category_buttons[category_key] as Button).position
		_check(selected_tag.get_theme_stylebox("normal") is StyleBoxTexture, "selected category lost the recovered module-17 frame")
		_check(adjacent_tag.get_theme_stylebox("normal") is StyleBoxTexture, "inactive category lost the recovered module-17 frame")
		_check(adjacent_tag.modulate.is_equal_approx(Color.WHITE), "inactive category icon is still artificially dimmed")
		_check(selected_tag.scale.is_equal_approx(Vector2.ONE) and adjacent_tag.scale.is_equal_approx(Vector2.ONE), "fixed category hit targets change size on selection")
		var hp_track_glow := shell.comparison_panel.get_node_or_null("HPComparison/AuthoredMeter/TrackGlow") as TextureRect
		_check(hp_track_glow != null and hp_track_glow.modulate.a >= 0.2, "upper-right comparison slot is still too dark")
		_check(shell.slot_picker.get_theme_stylebox("normal") is StyleBoxFlat, "loadout slot picker has no bright custom frame")
		for supply_case: Dictionary in [
			{"key": "health", "count": 6},
			{"key": "aid", "count": 2},
			{"key": "assist", "count": 3},
		]:
			shell._select_supply_category(str(supply_case.key), false)
			await get_tree().process_frame
			_check(shell.item_row.get_child_count() == int(supply_case.count), "%s supply shelf has the wrong item count" % supply_case.key)
			_check(not shell.category_layer.visible and not shell.comparison_panel.visible, "mobile equipment controls remain visible on the supply shelf")
			var supply_card := shell.item_row.get_child(0) as Button
			var supply_art := supply_card.get_node_or_null("SupplyArt") as TextureRect
			_check(supply_art != null and supply_art.texture != null, "%s supply shelf is missing recovered Unity art" % supply_case.key)
		_check(shell.supply_preview_art.visible and shell.supply_preview_art.texture != null, "selected supply has no large preview art")
		shell.set_weapon_filter("RIFLE")
		_check(shell.selected_section == "equipment" and shell.selected_category == "gun", "weapon filter does not return from supplies to equipment")
		shell.set_weapon_filter("ALL")
		for category_key: String in expected_tabs:
			_check(shell.category_buttons.has(category_key), "missing category tab: " + category_key)
			shell._select_category(category_key, false)
			await get_tree().process_frame
			var expected_count := GameState.get_weapon_ids().size() if category_key == "gun" else GameState.get_armor_ids(category_key).size()
			_check(shell.item_row.get_child_count() == expected_count, "%s carousel count differs from GameState" % category_key)
			if category_key != "gun":
				var armor_card := shell.item_row.get_child(0) as Button
				var armor_art := armor_card.get_node_or_null("ArmorArt") as TextureRect
				_check(armor_art != null and armor_art.texture != null, "%s carousel does not show the actual armor-part thumbnail" % category_key)
			for stable_key: String in expected_tabs:
				_check((shell.category_buttons[stable_key] as Button).position.is_equal_approx(category_positions[stable_key]), "category %s moved while selecting %s" % [stable_key, category_key])
		var horizontal_bar := shell.item_scroll.get_h_scroll_bar()
		_check(not horizontal_bar.visible, "product grid unexpectedly requires horizontal scrolling")
		shell._select_category("gun", false)
		var weapon_ids := GameState.get_weapon_ids()
		_check(_item_key_order(shell) == weapon_ids, "product grid does not begin in catalog order")
		shell._select_item(weapon_ids[-1], false)
		for _frame in range(3):
			await get_tree().process_frame
		_check(_item_key_order(shell) == weapon_ids, "selecting a weapon rearranges the product grid")
		_check(_contains_control(shell.item_scroll, shell.item_row.get_child(weapon_ids.size() - 1) as Control), "selected final weapon is not scrolled fully into view")
		var next_item := shell.get_node_or_null("EquipmentCatalog/NextItem") as Button
		var previous_item := shell.get_node_or_null("EquipmentCatalog/PreviousItem") as Button
		if next_item != null and previous_item != null:
			next_item.pressed.emit()
			_check(shell.selected_item_key == weapon_ids[0], "next-item button does not loop forward from the final weapon")
			previous_item.pressed.emit()
			_check(shell.selected_item_key == weapon_ids[-1], "previous-item button does not loop backward from the first weapon")
		_check(shell.preview_tween == null, "store character preview still starts an automatic turntable tween")
		shell._select_preferred_item(false)
		var keyboard_start := shell.selected_item_key
		var keyboard_start_index := weapon_ids.find(keyboard_start)
		_send_key(shell, KEY_D)
		_check(shell.selected_item_key == weapon_ids[posmod(keyboard_start_index + 1, weapon_ids.size())], "D does not select the next product")
		_send_key(shell, KEY_A)
		_check(shell.selected_item_key == keyboard_start, "A does not select the previous product")
		_send_key(shell, KEY_E)
		_check(shell.selected_category == "head", "E does not loop forward from gun to head")
		_send_key(shell, KEY_Q)
		_check(shell.selected_category == "gun", "Q does not loop backward from head to gun")
		for filter_key: String in ["RIFLE", "SHOTGUN", "HEAVY", "SPECIAL", "MELEE"]:
			shell.set_weapon_filter(filter_key)
			var filtered_ids := shell._get_category_ids()
			_check(not filtered_ids.is_empty() and filtered_ids.size() < weapon_ids.size(), "%s filter does not narrow the weapon catalog" % filter_key)
			_check(_item_key_order(shell) == filtered_ids and filtered_ids.has(shell.selected_item_key), "%s filter left stale cards or an invalid selection" % filter_key)
		shell.set_weapon_filter("ALL")
		_check(_item_key_order(shell) == weapon_ids, "ALL filter does not restore every weapon")
		await _check_catalog_scroll_input(shell)
		_check(shell.slot_picker.item_count >= 1, "Gun customize screen has no bag-slot picker")
		_check_purchase_and_equip(shell)
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
					var effect := preview_mesh.get_surface_override_material(surface_index)
					_check_effect_material(effect, int(material_case.blend), "%s surface %d" % [material_case.key, surface_index])
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
			_check_effect_material(named_effect, int(effect_case.blend), "%s material %s" % [effect_case.key, effect_case.name])
		for solid_key: String in ["gun24", "gun44"]:
			shell._select_item(solid_key, false)
			await get_tree().process_frame
			var solid_preview := _first_preview_mesh(shell.preview_root)
			var solid_material := solid_preview.get_surface_override_material(0) as StandardMaterial3D
			_check(solid_material != null and solid_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, solid_key + " black-Kd solid material became transparent")
			_check(solid_material != null and solid_material.albedo_color.r > 0.99 and solid_material.albedo_color.g > 0.99 and solid_material.albedo_color.b > 0.99, solid_key + " black-Kd solid material was not normalized to white")
		shell._select_item("gun22", false)
		var store_weapon := shell.preview_root.find_child("SelectedWeapon", true, false) as MeshInstance3D
		_check(store_weapon != null and shell.preview_root.find_child("RecoveredStoreAvatar", true, false) == null, "store does not showcase the selected weapon on its own")
		shell.set_mode("customize", false)
		_check(shell.selected_item_key == "gun22", "switching to Customize loses the selected weapon")
		var customize_weapon := shell.preview_root.find_child("SelectedWeapon", true, false) as MeshInstance3D
		_check(customize_weapon != null and shell.preview_root.find_child("RecoveredStoreAvatar", true, false) != null, "Customize no longer shows the weapon on the equipped avatar")
		if customize_weapon != null:
			var customize_solid := customize_weapon.get_surface_override_material(0) as StandardMaterial3D
			var customize_effect := customize_weapon.get_surface_override_material(1) as StandardMaterial3D
			_check(customize_solid != null and customize_solid.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Customize weapon solid material became transparent")
			_check(customize_effect != null and customize_effect.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Customize weapon effect material lost alpha blending")
		shell._select_item("gun23", false)
		var customize_additive := _first_preview_mesh(shell.preview_root)
		_check(customize_additive != null, "Customize additive weapon preview is missing")
		if customize_additive != null:
			_check_effect_material(customize_additive.get_surface_override_material(0), BaseMaterial3D.BLEND_MODE_ADD, "Customize additive weapon")
			var additive_weapon_solid := customize_additive.get_surface_override_material(2) as StandardMaterial3D
			_check(additive_weapon_solid != null and additive_weapon_solid.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Customize additive weapon solid surface became transparent")
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
				for surface_index in armor_mesh.mesh.get_surface_count():
					var material := armor_mesh.get_active_material(surface_index)
					if armor_mesh.has_meta("armor_rework"):
						_check(material is ShaderMaterial and material.shader.resource_path == "res://assets/armors/viper/painted_armor.gdshader", "shop preview lost refined armor material")
					else:
						_check(material is BaseMaterial3D and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "shop preview lost the original unlit armor shader")
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
		shell._select_item("armor_bag_00", false)
		var starter_bag_preview := shell.preview_root.find_child("ArmorBag_00", true, false) as MeshInstance3D
		_check(starter_bag_preview != null, "starter backpack preview is missing")
		if starter_bag_preview != null:
			var starter_bag_material := starter_bag_preview.get_active_material(0) as BaseMaterial3D
			_check(starter_bag_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and starter_bag_material.albedo_color.is_equal_approx(Color.WHITE), "starter backpack preview lost its original unlit white tint")
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
				var active_size := shell._active_design_size()
				_check(rect.position.x >= -0.1 and rect.position.y >= -0.1 and rect.end.x <= active_size.x + 0.1 and rect.end.y <= active_size.y + 0.1, "%s overflows the active equipment shell" % control.name)
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
	_check(not native_menu.equipment_shell.desktop_layout, "960x640 viewport should use the compact catalog layout")
	_check(native_menu.equipment_shell.category_layer.visible, "960x640 viewport lost the fixed equipment categories")
	_check_store_layout(native_menu.equipment_shell)
	var native_shell: UnityEquipmentShell = native_menu.equipment_shell
	native_shell._select_item("gun22", false)
	var stable_grid := native_shell.item_row
	native_viewport.size = Vector2i(1280, 720)
	for _frame in range(3):
		await get_tree().process_frame
	_check(native_shell.desktop_layout and native_shell.size.is_equal_approx(UnityEquipmentShell.DESKTOP_DESIGN_SIZE), "resizing an open store does not activate the wide layout")
	_check(native_shell.item_row == stable_grid and native_shell.selected_item_key == "gun22", "resizing an open store recreates the grid or loses selection")
	_check_store_layout(native_shell)
	native_viewport.size = Vector2i(960, 640)
	for _frame in range(3):
		await get_tree().process_frame
	_check(not native_shell.desktop_layout and native_shell.selected_item_key == "gun22", "resizing back to compact layout loses selection or layout")
	for child in native_menu.equipment_shell.get_children():
		if child is Control:
			var native_control := child as Control
			var native_rect := Rect2(native_control.position, native_control.size)
			_check(native_rect.position.x >= -0.1 and native_rect.position.y >= -0.1 and native_rect.end.x <= 960.1 and native_rect.end.y <= 640.1, "%s overflows the native 960x640 viewport" % native_control.name)
	native_viewport.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	GameState.save_path = original_save_path
	for candidate: String in [test_save_path, test_save_path + ".tmp", test_save_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	if failures.is_empty():
		print("MENU_EQUIPMENT_TEST_PASS tabs=6 armor=%d weapons=%d" % [GameState.ARMOR_ITEMS.size(), GameState.WEAPONS.size()])
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _check_store_layout(shell: UnityEquipmentShell) -> void:
	var catalog := shell.get_node_or_null("EquipmentCatalog") as Control
	var details := shell.get_node_or_null("EquipmentDetails") as Control
	_check(catalog != null and details != null, "store has no distinct catalog and product-details panels")
	if catalog == null or details == null:
		return
	_check(catalog.get_global_rect().end.x <= details.get_global_rect().position.x, "catalog and product-details panels overlap")
	_check(_contains_control(shell, catalog) and _contains_control(shell, details), "store panels overflow the design canvas")
	_check(shell.item_row is GridContainer and shell.item_row.columns == 3, "catalog is not a three-column product grid")
	_check(catalog.is_ancestor_of(shell.item_scroll), "product scroll does not belong to the catalog panel")
	_check(catalog.get_node_or_null("PreviousItem") is Button and catalog.get_node_or_null("NextItem") is Button, "catalog has no previous/next product controls")
	for control: Control in [shell.name_label, shell.price_label, shell.action_button, shell.comparison_panel]:
		_check(details.is_ancestor_of(control) and _contains_control(details, control), "%s is detached from or overflows product details" % control.name)
	_check(not shell.price_label.get_global_rect().intersects(shell.action_button.get_global_rect()), "price collides with the purchase action")
	_check(shell.item_scroll.get_global_rect().position.y >= shell.category_layer.get_global_rect().end.y, "product grid covers the category controls")
	var category_rects: Array[Rect2] = []
	for category_key: String in shell.category_buttons:
		var category_button := shell.category_buttons[category_key] as Button
		_check(_contains_control(catalog, category_button), "category %s is outside the catalog" % category_key)
		for previous_rect: Rect2 in category_rects:
			_check(not category_button.get_global_rect().intersects(previous_rect), "category hit targets overlap")
		category_rects.append(category_button.get_global_rect())
	for card: Button in shell.item_row.get_children():
		var item_name := card.get_node_or_null("ItemName") as Label
		var item_state := card.get_node_or_null("ItemState") as Label
		_check(item_name != null and not item_name.text.is_empty(), "%s has no product name" % card.name)
		_check(item_state != null and not item_state.text.is_empty(), "%s has no purchase/ownership state" % card.name)


func _contains_control(parent: Control, child: Control) -> bool:
	return parent.get_global_rect().grow(0.5).encloses(child.get_global_rect())


func _item_key_order(shell: UnityEquipmentShell) -> Array[String]:
	var keys: Array[String] = []
	for child in shell.item_row.get_children():
		keys.append(str(child.get_meta("item_key", "")))
	return keys


func _send_key(shell: UnityEquipmentShell, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	shell._unhandled_key_input(event)


func _check_catalog_scroll_input(shell: UnityEquipmentShell) -> void:
	shell._select_item("gun00", false)
	for _frame in range(3):
		await get_tree().process_frame
	var scroll_before := shell.item_scroll.scroll_vertical
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = shell.item_scroll.get_global_rect().get_center()
	get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	_check(shell.item_scroll.scroll_vertical > scroll_before, "mouse wheel does not scroll the product catalog vertically")
	_check(shell.selected_item_key == "gun00", "mouse-wheel browsing unexpectedly selects another product")
	shell._select_item("gun00", false)
	for _frame in range(3):
		await get_tree().process_frame
	scroll_before = shell.item_scroll.scroll_vertical
	var touch_origin := shell.item_scroll.get_global_rect().get_center()
	# Route touch through Input so Godot also emits the corresponding pointer
	# events for ScrollContainer; push_input alone bypasses that conversion.
	var emulate_touch_before := Input.emulate_touch_from_mouse
	var emulate_mouse_before := Input.emulate_mouse_from_touch
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = touch_origin
	Input.parse_input_event(touch)
	Input.flush_buffered_events()
	await get_tree().process_frame
	for step in range(1, 5):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = touch_origin - Vector2(0, step * 28)
		drag.relative = Vector2(0, -28)
		drag.velocity = Vector2(0, -300)
		Input.parse_input_event(drag)
		Input.flush_buffered_events()
		await get_tree().process_frame
	touch.pressed = false
	touch.position = touch_origin - Vector2(0, 112)
	Input.parse_input_event(touch)
	Input.flush_buffered_events()
	await get_tree().process_frame
	_check(shell.item_scroll.scroll_vertical > scroll_before, "touch drag does not scroll the product catalog vertically")
	_check(shell.selected_item_key == "gun00", "touch-drag browsing accidentally selected a product")
	await get_tree().create_timer(0.6).timeout
	shell._select_item("gun00", false)
	for _frame in range(3):
		await get_tree().process_frame
	var next_card := shell.item_row.get_child(1) as Button
	var tap_down := InputEventScreenTouch.new()
	tap_down.index = 0
	tap_down.position = next_card.get_global_rect().get_center()
	tap_down.pressed = true
	get_viewport().push_input(tap_down, true)
	await get_tree().process_frame
	var tap_up := InputEventScreenTouch.new()
	tap_up.index = 0
	tap_up.position = tap_down.position
	tap_up.pressed = false
	get_viewport().push_input(tap_up, true)
	await get_tree().process_frame
	_check(shell.selected_item_key == str(next_card.get_meta("item_key")), "tapping a product card does not select it after touch scrolling")
	Input.emulate_touch_from_mouse = emulate_touch_before
	Input.emulate_mouse_from_touch = emulate_mouse_before


func _check_purchase_and_equip(shell: UnityEquipmentShell) -> void:
	var owned_before: Array[String] = GameState.owned_weapons.duplicate()
	var loadout_before: Array[String] = GameState.battle_weapons.duplicate()
	var selected_before := GameState.selected_weapon
	var credits_before := GameState.credits
	var mithril_before := GameState.mithril
	GameState.owned_weapons.assign(["gun00"])
	GameState.battle_weapons.assign(["gun00"])
	GameState.credits = 0
	GameState.mithril = 0
	shell.set_mode("store", false)
	shell._select_category("gun", false)
	shell._select_item("gun01", false)
	shell.action_button.pressed.emit()
	_check(not GameState.owned_weapons.has("gun01") and GameState.credits == 0, "failed purchase changed ownership or funds")
	_check(shell.notice_label.text == tr("Not enough credits."), "failed purchase is not explained in product details")
	GameState.credits = int(GameState.WEAPONS.gun01.price)
	shell.action_button.pressed.emit()
	_check(GameState.owned_weapons.has("gun01") and GameState.credits == 0, "BUY did not purchase the selected weapon exactly once")
	_check(shell.action_button.disabled and shell.action_button.text == tr("OWNED"), "purchased weapon action did not refresh to OWNED")
	_check(shell._get_item_state("gun01") == "equipped" and GameState.battle_weapons[0] == "gun01", "purchase no longer mounts the weapon in slot zero")
	shell.set_mode("customize", false)
	_check(shell.selected_item_key == "gun01", "Store to Customize switch loses the purchased selection")
	_check(shell.slot_picker.is_visible_in_tree(), "Customize has no visible loadout slot picker")
	_check(shell.action_button.disabled and shell.action_button.text == tr("EQUIPPED"), "Customize does not show the automatically equipped purchase")
	shell.selected_slot = 0
	shell._select_item("gun00", false)
	_check(shell.action_button.text == tr("EQUIP") and not shell.action_button.disabled, "displaced weapon cannot be re-equipped")
	shell.action_button.pressed.emit()
	_check(GameState.battle_weapons[0] == "gun00", "EQUIP did not restore the displaced weapon")
	shell._select_item("gun01", false)
	shell.action_button.pressed.emit()
	_check(GameState.battle_weapons[0] == "gun01", "EQUIP does not assign the purchased weapon to the selected slot")
	_check(shell.action_button.disabled and shell.action_button.text == tr("EQUIPPED"), "EQUIP does not refresh to EQUIPPED")
	var unlocked_level_before := GameState.unlocked_level
	var best_scores_before: Dictionary = GameState.best_scores.duplicate(true)
	GameState.unlocked_level = 1
	GameState.best_scores = {}
	shell.set_mode("store", false)
	shell._select_item("gun36", false)
	_check(shell._get_item_state("gun36") == "locked" and shell.action_button.disabled, "rank-locked weapon has an enabled purchase action")
	_check(shell.state_label.text.contains(str(shell._selected_unlock_rank() + 1)) or shell.action_button.text.contains(str(shell._selected_unlock_rank() + 1)), "rank-locked product does not display the required rank")
	GameState.unlocked_level = unlocked_level_before
	GameState.best_scores = best_scores_before
	GameState.owned_weapons = owned_before
	GameState.battle_weapons = loadout_before
	GameState.selected_weapon = selected_before
	GameState.credits = credits_before
	GameState.mithril = mithril_before
	shell.set_mode("store", false)
	shell._select_category("gun", false)


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


func _check_effect_material(material: Material, blend_mode: int, context: String) -> void:
	if blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		var additive := material as ShaderMaterial
		_check(additive != null and additive.shader == UnityEquipmentShell.AdditivePreviewShader, context + " does not use the transparent-preview additive shader")
		if additive != null:
			_check(additive.get_shader_parameter("effect_texture") is Texture2D, context + " has no recovered effect texture")
			_check(additive.get_shader_parameter("effect_tint") is Color, context + " has no effect tint")
		return
	var alpha_mix := material as StandardMaterial3D
	_check(alpha_mix != null and alpha_mix.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, context + " lacks alpha blending")
	_check(alpha_mix != null and alpha_mix.cull_mode == BaseMaterial3D.CULL_DISABLED and alpha_mix.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, context + " lost the recovered two-sided unshaded material")
	_check(alpha_mix != null and alpha_mix.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and alpha_mix.blend_mode == blend_mode, context + " has the wrong depth/blend mode")


func _preview_material_by_name(preview_mesh: MeshInstance3D, material_name: String) -> Material:
	if preview_mesh == null or preview_mesh.mesh == null:
		return null
	for surface_index in preview_mesh.mesh.get_surface_count():
		var source := preview_mesh.mesh.surface_get_material(surface_index)
		if source != null and source.resource_name.to_lower() == material_name:
			return preview_mesh.get_surface_override_material(surface_index)
	return null
