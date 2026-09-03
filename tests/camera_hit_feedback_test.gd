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

func _on_hit_confirmed(_amount: float) -> void:
	hit_count += 1

func _on_kill_confirmed() -> void:
	kill_count += 1
