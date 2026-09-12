extends Node

var failures: Array[String] = []
var hit_count := 0
var kill_count := 0

class DamageReporter:
	extends Node
	var actual_damage := 0.0
	var defeated_count := 0

	func on_damage_dealt(amount: float) -> void:
		actual_damage += amount

	func on_enemy_defeated() -> void:
		defeated_count += 1

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CAMERA / HIT FEEDBACK TEST: " + message)

func _run() -> void:
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	GameState.settings.show_touch_controls = false
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	var player := world.player
	var marker := world.hud.hit_marker
	var fire_crosshair := world.hud.fire_crosshair
	_check(is_instance_valid(player), "player was not created")
	_check(is_instance_valid(marker), "transitional hit marker was not created")
	_check(is_instance_valid(fire_crosshair), "original 1.2x fire crosshair was not created")
	_check(marker.get_parent() == world.hud.crosshair.get_parent(), "hit marker did not stay in the crosshair layer")
	_check(marker != world.hud.crosshair, "hit feedback replaced the recovered crosshair")
	_check(marker.HIT_DURATION >= 0.15, "ordinary hit confirmation is still too brief to read during recoil")
	_check(marker.KILL_DURATION >= 0.22, "kill confirmation is still too brief to distinguish from an ordinary hit")
	_check(fire_crosshair.texture == world.hud.crosshair.texture, "fire crosshair does not use the recovered AimID texture")
	_check(
		fire_crosshair.custom_minimum_size.is_equal_approx(world.hud.crosshair.custom_minimum_size * 1.2),
		"fire crosshair is not exactly 1.2x the normal reticle"
	)
	_check(is_zero_approx(float(GameState.WEAPONS.gun00.spread)), "assault rifle retained random spread")
	_check(is_zero_approx(float(GameState.WEAPONS.gun17.spread)), "laser rifle retained random spread")
	_check(is_zero_approx(float(GameState.WEAPONS.gun24.spread)), "machine gun retained random spread")
	_check(float(GameState.WEAPONS.gun06.spread) > 0.0, "shotgun lost its weapon-specific spread")

	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.body_yaw = 0.0
	player.model.rotation.y = 0.0
	var yaw_before_look := player.model.rotation.y
	player._apply_look_delta(Vector2(80.0, 0.0))
	_check(not is_equal_approx(player.camera_yaw, 0.0), "look input did not rotate the camera")
	_check(is_equal_approx(player.model.rotation.y, yaw_before_look), "orbit look still rotated the idle avatar")

	player.camera_yaw = 0.0
	player.body_yaw = 0.0
	player._update_body_facing(0.5, Vector3.RIGHT)
	_check(absf(angle_difference(player.body_yaw, -PI * 0.5)) < 0.02, "moving avatar did not face its travel direction")

	player.body_yaw = 0.0
	player.model.rotation.y = 0.0
	player.camera_yaw = PI * 0.75
	player.camera_rig.rotation.y = player.camera_yaw
	Input.action_press("aim")
	player._update_body_facing(1.0 / 60.0, Vector3.ZERO)
	var first_turn := player.body_yaw
	_check(first_turn > 0.0, "aiming did not begin aligning the avatar to the camera")
	_check(first_turn < player.camera_yaw - 0.1, "aiming snapped the avatar to the camera in one frame")
	player._update_combat_aim_pose(1.0 / 60.0)
	var aim := player.get_aim_solution(float(player.current_weapon.range))
	var muzzle_direction := -player.gun_mount.global_transform.basis.z.normalized()
	var expected_direction := (Vector3(aim.target) - player.gun_mount.global_position).normalized()
	_check(muzzle_direction.dot(expected_direction) > 0.999, "weapon muzzle did not immediately match the camera aim ray")
	for _frame in range(30):
		player._update_body_facing(1.0 / 60.0, Vector3.ZERO)
	Input.action_release("aim")
	_check(absf(angle_difference(player.body_yaw, player.camera_yaw)) < 0.01, "combat turn did not settle on the camera direction")
	player.shoot_pose_left = 0.0
	player._update_combat_aim_pose(1.0)
	_check(not player.upper_body_aim_override_active, "upper-body aim override persisted after combat")
	_check_fr28a_reload_camera(player)

	player.shot_fired.emit(player.current_weapon)
	_check(fire_crosshair.visible and not world.hud.crosshair.visible, "successful shot did not switch to the 1.2x fire reticle")
	world.hud.fire_reticle_left = 0.0
	world.hud._update_fire_reticle_visibility()
	_check(not fire_crosshair.visible and world.hud.crosshair.visible, "fire reticle did not return to the normal AimID sprite")

	player.hit_confirmed.connect(_on_hit_confirmed)
	player.kill_confirmed.connect(_on_kill_confirmed)
	var enemy := world._spawn_enemy("crawler", false)
	_check(is_instance_valid(enemy), "damage confirmation target was not created")
	enemy.take_damage(12.0, enemy.global_position, player)
	_check(hit_count == 1, "accepted damage did not emit hit confirmation")
	_check(marker.feedback_kind == &"hit" and marker.visible, "HUD did not show ordinary hit feedback")
	enemy.take_damage(0.0, enemy.global_position, player)
	_check(hit_count == 1, "zero damage emitted a false hit confirmation")
	enemy.take_damage(enemy.health + 1.0, enemy.global_position, player)
	_check(hit_count == 2, "lethal accepted damage did not emit hit confirmation")
	_check(kill_count == 1, "enemy defeat did not emit kill confirmation")
	_check(marker.feedback_kind == &"kill" and marker.visible, "kill feedback did not override the ordinary hit marker")
	marker.show_hit(3.0)
	_check(marker.feedback_kind == &"kill", "a later splash hit downgraded active kill confirmation")

	var pvp_source := DamageReporter.new()
	world.add_child(pvp_source)
	player.armor_skills["block_rate"] = 0.0
	player.health = 100.0
	player.shield = 20.0
	player.take_damage(30.0, player.global_position, pvp_source)
	_check(is_equal_approx(pvp_source.actual_damage, 30.0), "PvP target did not report accepted shield/health damage to its attacker")
	player.shield = 0.0
	player.health = 5.0
	player.take_damage(10.0, player.global_position, pvp_source)
	_check(pvp_source.defeated_count == 1, "PvP defeat did not report kill confirmation to its attacker")

	world.completed = true
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.1).timeout
	if failures.is_empty():
		print("CAMERA_HIT_FEEDBACK_TEST_PASS orbit=true smooth_turn=true confirmed_hit=true kill=true")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _check_fr28a_reload_camera(player: WarfarePlayer) -> void:
	var saved_weapon_id := player.current_weapon_id
	var saved_magazines := player.weapon_magazines.duplicate(true)
	var saved_auto_reload := player.auto_reload_left
	var saved_body_yaw := player.body_yaw
	var saved_model_rotation := player.model.rotation
	var saved_camera_yaw := player.camera_yaw
	var saved_camera_rotation := player.camera_rig.rotation
	var saved_mount_transform := player.gun_mount.transform
	var saved_velocity := player.velocity
	var saved_shoot_pose := player.shoot_pose_left
	var saved_touch_fire := player.touch_fire
	var saved_aim_pressed := Input.is_action_pressed("aim")
	var saved_fire_pressed := Input.is_action_pressed("fire")
	Input.action_release("aim")
	Input.action_release("fire")
	player.touch_fire = false
	player.shoot_pose_left = 0.0
	player.equip_weapon("gun00", false)
	player._set_magazine_rounds(0)
	player._start_reload()
	player._update_reload(player.reload_total * 0.5)
	_check(player.reload_left > 0.0, "FR28a camera checks did not enter reload")
	player.velocity = Vector3.ZERO
	player.camera_yaw = PI * 0.75
	player.camera_rig.rotation.y = player.camera_yaw
	for trigger: String in ["none", "aim", "fire", "touch", "shoot_pose", "all"]:
		Input.action_release("aim")
		Input.action_release("fire")
		if trigger in ["aim", "all"]:
			Input.action_press("aim")
		if trigger in ["fire", "all"]:
			Input.action_press("fire")
		player.touch_fire = trigger in ["touch", "all"]
		player.shoot_pose_left = 0.25 if trigger in ["shoot_pose", "all"] else 0.0
		player.body_yaw = 0.0
		player.model.rotation.y = 0.0
		_check(not player.is_combat_aim_active(), "FR28a reload still enables combat aim with %s" % trigger)
		player._update_body_facing(0.5, Vector3.ZERO)
		player._update_combat_aim_pose(1.0 / 60.0)
		_check(is_zero_approx(player.body_yaw) and is_zero_approx(player.model.rotation.y), "stationary FR28a reload turned toward the camera with %s" % trigger)
		_check(not player.upper_body_aim_override_active, "FR28a reload retained upper-body camera aim with %s" % trigger)

	# Keep all triggers held: reloading must still permit orbit and travel facing.
	var camera_before := player.camera_yaw
	player._apply_look_delta(Vector2(80.0, 0.0))
	_check(not is_equal_approx(player.camera_yaw, camera_before), "FR28a reload blocked camera look input")
	_check(is_equal_approx(player.camera_rig.rotation.y, player.camera_yaw), "FR28a reload failed to apply camera orbit")
	_check(is_zero_approx(player.model.rotation.y), "FR28a reload orbit rotated the stationary avatar")
	player._update_body_facing(0.5, Vector3.RIGHT)
	_check(absf(angle_difference(player.body_yaw, -PI * 0.5)) < 0.02, "moving FR28a reload followed the camera instead of travel")

	# Exercise the real per-frame methods at one fixed pose. Repeating an
	# unchanged reload progress must not add another tilt on every frame.
	player._update_combat_aim_pose(1.0 / 60.0)
	player._update_reload_pose()
	var first_rotation := player.gun_mount.global_basis.get_rotation_quaternion()
	_check((-player.gun_mount.global_basis.z).normalized().y > 0.05, "FR28a reload did not raise the barrel")
	for _frame in range(120):
		player._update_combat_aim_pose(1.0 / 60.0)
		player._update_reload_pose()
	var rotation_drift := first_rotation.angle_to(player.gun_mount.global_basis.get_rotation_quaternion())
	_check(rotation_drift < 0.001, "FR28a reload pose accumulated rotation at fixed progress (%.3f degrees)" % rad_to_deg(rotation_drift))
	var rotation_before_orbit := player.gun_mount.global_basis.get_rotation_quaternion()
	player._apply_look_delta(Vector2(80.0, 0.0))
	player._update_combat_aim_pose(1.0 / 60.0)
	player._update_reload_pose()
	_check(rotation_before_orbit.angle_to(player.gun_mount.global_basis.get_rotation_quaternion()) < 0.001, "FR28a reload weapon followed the orbiting camera")

	player._update_reload(player.reload_total)
	_check(is_zero_approx(player.reload_left), "FR28a camera checks did not finish reload")
	Input.action_release("aim")
	Input.action_release("fire")
	player.touch_fire = false
	player.shoot_pose_left = 0.0
	for action: String in ["aim", "fire"]:
		player.body_yaw = 0.0
		player.model.rotation.y = 0.0
		player.camera_yaw = 1.0
		player.camera_rig.rotation.y = player.camera_yaw
		Input.action_press(action)
		_check(player.is_combat_aim_active(), "FR28a %s did not restore combat aim after reload" % action)
		player._update_body_facing(1.0 / 60.0, Vector3.ZERO)
		player._update_combat_aim_pose(1.0 / 60.0)
		_check(player.body_yaw > 0.0, "FR28a %s did not resume turning toward the camera after reload" % action)
		_check_weapon_aim_direction(player, "FR28a %s after reload" % action)
		Input.action_release(action)
		player._update_combat_aim_pose(1.0)

	# The staged reload contract now applies to every catalog weapon. Camera
	# orbit stays free while hands operate the model-specific loading part;
	# held aim must resume after cancellation/completion.
	for key: String in GameState.RELOAD_PROFILES:
		player.equip_weapon(key, false)
		player._set_magazine_rounds(0)
		player._start_reload()
		player.body_yaw = 0.0
		player.model.rotation.y = 0.0
		Input.action_press("aim")
		_check(not player.is_combat_aim_active(), key + " reload enabled camera-driven gun aim")
		var before_orbit := player.camera_yaw
		player._apply_look_delta(Vector2(40, 0))
		player._update_body_facing(1.0 / 60.0, Vector3.ZERO)
		player._update_combat_aim_pose(1.0 / 60.0)
		_check(not is_equal_approx(before_orbit, player.camera_yaw), key + " reload blocked orbit input")
		_check(is_zero_approx(player.body_yaw) and not player.upper_body_aim_override_active, key + " reload followed the orbiting camera")
		player._cancel_reload()
		_check(player.is_combat_aim_active(), key + " did not restore held aim after cancellation")
		player._update_combat_aim_pose(1.0 / 60.0)
		_check_weapon_aim_direction(player, key + " after reload cancellation")
		Input.action_release("aim")

	player._cancel_reload()
	player.equip_weapon(saved_weapon_id, false)
	player.weapon_magazines = saved_magazines
	player.auto_reload_left = saved_auto_reload
	player.body_yaw = saved_body_yaw
	player.model.rotation = saved_model_rotation
	player.camera_yaw = saved_camera_yaw
	player.camera_rig.rotation = saved_camera_rotation
	player.gun_mount.transform = saved_mount_transform
	player.velocity = saved_velocity
	player.shoot_pose_left = saved_shoot_pose
	player.touch_fire = saved_touch_fire
	if saved_aim_pressed:
		Input.action_press("aim")
	if saved_fire_pressed:
		Input.action_press("fire")
	player._emit_ammo()

func _check_weapon_aim_direction(player: WarfarePlayer, context: String) -> void:
	var aim := player.get_aim_solution(float(player.current_weapon.range))
	var muzzle_direction := -player.gun_mount.global_transform.basis.z.normalized()
	var expected_direction := (Vector3(aim.target) - player.gun_mount.global_position).normalized()
	_check(muzzle_direction.dot(expected_direction) > 0.999, "%s weapon did not follow the camera aim ray" % context)

func _on_hit_confirmed(_amount: float) -> void:
	hit_count += 1

func _on_kill_confirmed() -> void:
	kill_count += 1
