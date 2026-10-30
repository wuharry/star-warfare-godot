extends Node3D

const Suit := preload("res://scripts/art/cartoon_viper.gd")
var failures: Array[String] = []

class MovementWorld extends WarfareGameWorld:
	func _ready() -> void:
		completed = true
		level_data = GameState.get_level_data(1)
		effects_root = Node3D.new()
		add_child(effects_root)
		var floor_body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = WorldBoundaryShape3D.new()
		floor_body.add_child(collision)
		add_child(floor_body)
		_build_player()
		player.position = Vector3(0, .04, 0)

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CARTOON_VIPER: " + message)

func _tick(count := 1) -> void:
	for frame in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	GameState.save_path = "user://cartoon_viper_test_profile.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	var world := MovementWorld.new()
	add_child(world)
	var player: WarfarePlayer = world.player
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _tick(10)
	var suit := Suit.new()
	suit.apply(player)
	_check(suit.originals.size() == 5, "armor comparison did not include all four parts and backpack")
	var skeleton := player.recovered_skeleton
	for entry: Dictionary in suit.originals:
		var mesh: MeshInstance3D = entry.node
		_check(mesh.mesh != null, "new armor mesh is missing")
		var paint := mesh.mesh.surface_get_material(0) as ShaderMaterial
		_check(paint != null and paint.get_shader_parameter("albedo_texture") != null, "new UV texture is missing")
		if mesh == player.backpack_visual:
			var bind := skeleton.get_bone_global_rest(skeleton.find_bone("fly_bag"))
			_check((bind * mesh.transform).is_equal_approx(Transform3D.IDENTITY), "backpack applies its bind transform twice")
			continue
		_check(mesh.skin.get_bind_count() == skeleton.get_bone_count(), "new skin lost rig bones")
		var arrays := mesh.mesh.surface_get_arrays(0)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var invalid_weights := 0
		for vertex in weights.size() / 4:
			var total := 0.0
			for influence in 4:
				var index := vertex * 4 + influence
				total += weights[index]
				if not is_finite(weights[index]) or weights[index] < 0 or bones[index] >= skeleton.get_bone_count():
					invalid_weights += 1
			if absf(total - 1) > .001:
				invalid_weights += 1
		_check(invalid_weights == 0, "%s has invalid skin weights" % mesh.name)

	# Start/stop through the actual player physics callback: releasing input
	# must not freeze the legs while the body is still coasting.
	player.set_touch_move(Vector2(0, -1))
	await _tick(1)
	var first_speed := Vector2(player.velocity.x, player.velocity.z).length()
	await _tick(25)
	var run_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(first_speed > 0 and first_speed < run_speed, "movement snapped to full speed")
	player.set_touch_move(Vector2.ZERO)
	await _tick(1)
	var coast_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(coast_speed > .1 * player.move_speed and coast_speed < run_speed, "release did not decelerate")
	_check(player.recovered_animation_name == "run_rifle", "legs became idle before deceleration finished")
	await _tick(25)
	_check(Vector2(player.velocity.x, player.velocity.z).is_zero_approx(), "player never came to rest")
	_check(player.recovered_animation_name == "idle_rifle", "stopped player did not return to idle")
	var yaw_before := player.body_yaw
	player.set_touch_move(Vector2.RIGHT)
	await _tick(1)
	var turn_step := absf(angle_difference(yaw_before, player.body_yaw))
	_check(turn_step > .01 and turn_step < PI / 3, "direction change snapped body orientation")
	player.set_touch_move(Vector2.ZERO)
	await _tick(25)

	# Collision cancels real travel even with input held; the new pose driver
	# must stop running at a wall, too.
	player.position = Vector3(0, .04, 0)
	player.velocity = Vector3.ZERO
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, .2)
	wall_collision.shape = box
	wall.add_child(wall_collision)
	wall.position = Vector3(0, 1, -.85)
	world.add_child(wall)
	player.set_touch_move(Vector2(0, -1))
	await _tick(35)
	_check(absf(player.velocity.z) < .01 and player.recovered_animation_name == "idle_rifle", "running continued against a blocking wall")
	wall.free()

	# The new weighted limbs must keep animating under held fire and reload.
	player.energy = player.max_energy
	player.set_touch_fire(true)
	var thigh := skeleton.find_bone("Bip01 L Thigh")
	var first_pose := Quaternion.IDENTITY
	var shoot_angle := 0.0
	var layered_frames := 0
	for frame in 75:
		await _tick()
		if frame == 10:
			first_pose = skeleton.get_bone_pose_rotation(thigh)
		elif frame > 10:
			shoot_angle = maxf(shoot_angle, first_pose.angle_to(skeleton.get_bone_pose_rotation(thigh)))
			if player.recovered_animation_tree.active and player.recovered_locomotion_name == "run_rifle":
				layered_frames += 1
	_check(layered_frames > 40 and shoot_angle > .35, "held shooting froze the running legs")
	player.set_touch_fire(false)
	player._cancel_reload()
	player.shoot_pose_left = 0
	player._set_magazine_rounds(0)
	player.request_touch_reload()
	await _tick(1)
	_check(player.reload_left > 0, "reload input did not start a reload")
	var reload_start := player.position
	var reload_angle := 0.0
	first_pose = skeleton.get_bone_pose_rotation(thigh)
	var max_contact := 0.0
	var contact_samples := 0
	var hand := skeleton.find_bone("Bip01 L Hand")
	for frame in 160:
		await _tick()
		reload_angle = maxf(reload_angle, first_pose.angle_to(skeleton.get_bone_pose_rotation(thigh)))
		if is_instance_valid(player.reload_hand_prop):
			var wrist := skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
			max_contact = maxf(max_contact, wrist.distance_to(player.reload_hand_prop.global_position))
			contact_samples += 1
		if player.reload_left <= 0:
			break
	_check(player.position.distance_to(reload_start) > 1.5 and reload_angle > .35, "reload stopped movement or froze the legs")
	_check(player.reload_left <= 0 and player._magazine_rounds() > 0, "reload did not complete")
	_check(contact_samples > 2 and max_contact < .11, "reload magazine left the hand")
	player.set_touch_move(Vector2.ZERO)
	var snapshots := suit.originals.duplicate()
	suit.restore()
	for entry: Dictionary in snapshots:
		_check(entry.node.mesh == entry.mesh and entry.node.skin == entry.skin and entry.node.transform.is_equal_approx(entry.transform), "comparison failed to restore original geometry")
		_check(entry.node.material_override == entry.material, "comparison failed to restore original material")
		for index in entry.overrides.size():
			_check(entry.node.get_surface_override_material(index) == entry.overrides[index], "comparison lost a surface override")
	world.free()
	AudioDirector.stop_all_sfx()
	await _tick(2)
	if failures.is_empty():
		print("CARTOON_VIPER_TEST_PASS skin=true restore=true acceleration=true deceleration=true wall=true turn=true shoot_thigh=%.3f reload_thigh=%.3f magazine_contact=%.3f" % [shoot_angle, reload_angle, max_contact])
	get_tree().quit(0 if failures.is_empty() else 1)
