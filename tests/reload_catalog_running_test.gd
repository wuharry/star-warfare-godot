extends "res://tests/reload_catalog_fixture.gd"

var failures: Array[String] = []
var results: Array[Dictionary] = []

func _ready() -> void:
	setup()
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	add_child(floor_body)
	player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	Engine.time_scale = 3.0
	for key: String in GameState.RELOAD_PROFILES:
		for flying in [false, true]:
			var count := 1 if flying else int(GameState.RELOAD_PROFILES[key].reload_variants)
			for variant in range(count):
				begin(key, variant, true, 3)
				player.position = Vector3.ZERO
				player.armor_skills["fly"] = 1.0 if flying else 0.0
				var skeleton := player.recovered_skeleton
				var left := skeleton.find_bone("Bip01 L Hand")
				var thigh := skeleton.find_bone("Bip01 L Thigh")
				var thigh_start := Quaternion.IDENTITY
				var thigh_angle := 0.0
				var max_contact := 0.0
				var contacts := 0
				Input.action_press("move_forward")
				player.set_physics_process(true)
				for tick in range(240):
					await get_tree().physics_frame
					await get_tree().process_frame
					if tick == 4:
						thigh_start = skeleton.get_bone_pose_rotation(thigh)
					elif tick > 4:
						thigh_angle = maxf(thigh_angle, thigh_start.angle_to(skeleton.get_bone_pose_rotation(thigh)))
					if player.reload_left <= 0:
						break
					if player.active_reload_variant != variant:
						failures.append(key + " moving reload changed variant")
					if is_instance_valid(player.reload_hand_prop):
						contacts += 1
						var distance := skeleton.to_global(skeleton.get_bone_global_pose(left).origin).distance_to(player.reload_hand_prop.global_position)
						max_contact = maxf(max_contact, distance)
				Input.action_release("move_forward")
				player.set_physics_process(false)
				var result := {"weapon": key, "variant": variant, "flying": flying, "max_contact": max_contact, "contacts": contacts, "distance": player.position.length(), "thigh_angle": thigh_angle}
				results.append(result)
				if max_contact > 0.11 or contacts < 3 or player.position.length() < 1.5 or (not flying and thigh_angle < 0.35) or player.reload_left > 0:
					failures.append(JSON.stringify(result))
					push_error("RELOAD MOVEMENT: " + JSON.stringify(result))
		print("RELOAD_MOVEMENT_WEAPON ", key)
	Engine.time_scale = 1.0
	var file := FileAccess.open("res://test_output/reload_catalog/movement_verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples": results, "failures": failures}, "\t"))
	file.close()
	cleanup()
	await get_tree().process_frame
	if failures.is_empty():
		print("RELOAD_CATALOG_MOVEMENT_PASS run_variants=55 fly_weapons=24")
	get_tree().quit(0 if failures.is_empty() else 1)
