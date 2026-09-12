extends "res://tests/reload_catalog_fixture.gd"

var failures: Array[String] = []
var results: Dictionary = {}

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("RELOAD CATALOG: " + message)

func _ready() -> void:
	setup()
	await get_tree().process_frame
	var skeleton := player.recovered_skeleton
	var left := skeleton.find_bone("Bip01 L Hand")
	var right := skeleton.find_bone("Bip01 R Hand")
	for key: String in GameState.RELOAD_PROFILES:
		var stats := {"max_contact": 0.0, "max_grip_error": 0.0, "variants": []}
		var variant_count := int(GameState.RELOAD_PROFILES[key].reload_variants)
		for variant in range(variant_count):
			for walk in [false, true]:
				begin(key, variant, walk, 1)
				var grip := (skeleton.global_transform * skeleton.get_bone_global_pose(right)).affine_inverse() * player.gun_mount.global_transform
				if player.reload_prop_mesh != null:
					var body := player.gun_mount.get_node("WeaponVisual/Recovered_" + key) as MeshInstance3D
					var prop := player.attached_reload_part.get_node("OriginalMagazine") as MeshInstance3D
					check(body.global_transform.is_equal_approx(prop.global_transform), key + " assembled part changed coordinates/scale")
					if key == "gun45":
						for instance in [body, prop]:
							var restored := 0
							for surface in instance.mesh.get_surface_count():
								var source: Material = instance.mesh.surface_get_material(surface)
								if source.resource_name.begins_with("_HotWing-Material_25_"):
									var material := instance.get_active_material(surface) as ShaderMaterial
									check(material != null, "UFO body/chamber lost Unity overlay shader")
									if material != null:
										check(material.get_shader_parameter("base_texture") == load("res://assets/models/weapons/HotWing_D.png"), "UFO base atlas missing")
										check(material.get_shader_parameter("overlay_texture") == load("res://assets/models/weapons/HotWing_L.png"), "UFO light atlas missing")
									restored += 1
							check(restored > 0, "UFO body/chamber has no restored surfaces")
				for progress in [0.12, 0.21, 0.32, 0.44, 0.60, 0.70, 0.79, 0.85, 0.94]:
					advance_to(duration * progress)
					await get_tree().process_frame
					var current_grip := (skeleton.global_transform * skeleton.get_bone_global_pose(right)).affine_inverse() * player.gun_mount.global_transform
					var grip_error := current_grip.origin.distance_to(grip.origin)
					stats.max_grip_error = maxf(stats.max_grip_error, grip_error)
					check(grip_error < 0.003, key + " lost right hand grip")
					if is_instance_valid(player.reload_hand_prop):
						var distance := skeleton.to_global(skeleton.get_bone_global_pose(left).origin).distance_to(player.reload_hand_prop.global_position)
						stats.max_contact = maxf(stats.max_contact, distance)
						check(distance < 0.11, "%s variant=%d moving=%s p=%.2f wrist_distance=%.3f" % [key, variant, walk, progress, distance])
					check(player.active_reload_variant == variant, key + " variant changed inside reload")
				advance_to(duration)
				if player.reload_left > 0:
					step(player.reload_left)
				check(player._magazine_rounds() == int(player.current_weapon.magazine_size) and player.reload_left == 0, key + " failed to refill")
				check(not is_instance_valid(player.reload_hand_prop), key + " left held prop after completion")
			stats.variants.append(variant)
		results[key] = stats
		print("RELOAD_CATALOG_WEAPON ", key, " ", JSON.stringify(stats))
		# Check selection at real reload boundaries, including repeated shell cycles.
		var seen: Dictionary = {}
		for sample in range(60):
			begin(key, -1, false, 2)
			var chosen := player.active_reload_variant
			seen[chosen] = true
			check(chosen >= 0 and chosen < variant_count, key + " selected invalid variant")
			if str(player.current_weapon.reload_style) == "shotgun_shell":
				step(player.reload_total)
				check(player.reload_left > 0 and player.active_reload_variant == chosen and not player.reload_first_cycle, key + " shell continuation rerolled variant")
			player._cancel_reload()
			check(not is_instance_valid(player.reload_hand_prop), key + " cancel leaked prop")
		check(seen.size() == variant_count, key + " random reload never selected all variants")
		for progress in [0.50, 0.85]:
			begin(key, 0, false, 1)
			var before := player._magazine_rounds()
			advance_to(duration * progress)
			check(player._magazine_rounds() == before, key + " credited ammo before reload completion")
			player.camera_yaw = 1.1
			player._update_body_facing(0.2, Vector3.ZERO)
			check(is_equal_approx(player.camera_yaw, 1.1) and is_zero_approx(player.body_yaw), key + " reload locked free camera")
			player._cancel_reload()
			check(player._magazine_rounds() == before and not is_instance_valid(player.reload_hand_prop), key + " mid-cycle cancel changed ammo or left a held part")
			if is_instance_valid(player.attached_reload_part):
				check(player.attached_reload_part.visible == (not bool(player.current_weapon.consume_reload_part)), key + " cancelled attachment state is wrong")
		begin(key, 0, false, 1)
		advance_to(duration * 0.50)
		player.equip_weapon("gun17", false)
		check(player.reload_left == 0 and not is_instance_valid(player.reload_hand_prop), key + " weapon switch did not clean up reload")
	DirAccess.make_dir_recursive_absolute("res://test_output/reload_catalog")
	var file := FileAccess.open("res://test_output/reload_catalog/verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"weapons": results, "failures": failures}, "\t"))
	file.close()
	cleanup()
	await get_tree().process_frame
	if failures.is_empty():
		print("RELOAD_CATALOG_TEST_PASS weapons=24 variants=55 random=true")
	get_tree().quit(0 if failures.is_empty() else 1)
