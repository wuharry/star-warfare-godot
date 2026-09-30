extends Node

# Observe real damage rays and spawned projectiles. A passing helper alone
# would not prove that _try_fire actually uses the new spread state.
var failures: Array[String] = []
var checks := 0
var shot_count := 0
var world: WarfareGameWorld
var player: WarfarePlayer
var target: HitRecorder

class HitRecorder:
	extends StaticBody3D
	var hits: Array[Vector3] = []

	func take_damage(_amount: float, position_value: Vector3, _source: Node) -> void:
		hits.append(position_value)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("HIP FIRE SPREAD TEST: " + message)

func _on_shot(_weapon: Dictionary) -> void:
	shot_count += 1

func _equip(id: String) -> void:
	Input.action_release("aim")
	Input.action_release("fire")
	player.touch_aim = false
	player.touch_fire = false
	player.equip_weapon(id, false)
	player.shot_cooldown = 0.0
	player.auto_reload_left = -1.0
	player.energy = player.max_energy
	player.armor_skills = {}
	player.velocity = Vector3.ZERO
	if player._uses_magazine():
		player._set_magazine_rounds(int(player.current_weapon.magazine_size))

func _fire() -> void:
	# Remove resource/cadence limits only; the real successful-fire branch must
	# still choose its ray, consume ammo and increment bloom itself.
	player.shot_cooldown = 0.0
	player.energy = player.max_energy
	if player._uses_magazine():
		player._set_magazine_rounds(int(player.current_weapon.magazine_size))
	player._try_fire()

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_level = 1
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	GameState.settings.show_touch_controls = "--mobile" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", GameState.settings.show_touch_controls)
	world = (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	world.completed = true
	world.set_physics_process(false)
	player = world.player
	player.set_physics_process(false)
	player.global_position = Vector3(0, 100, 0)
	player.gravity = 0.0
	player.shot_fired.connect(_on_shot)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for frame in 120:
		player._update_camera_controller(1.0 / 60.0)
	await get_tree().physics_frame
	_create_target()
	await get_tree().physics_frame
	_check_catalog()
	_check_hitscan_paths()
	_check_projectile_path()
	await _check_shotgun_baseline()
	_check_blocked_triggers()
	_check_recovery_and_movement()
	_check_focus_and_melee()
	_check_reticle()
	await _check_pause()
	Input.action_release("aim")
	Input.action_release("fire")
	Input.action_release("move_forward")
	get_tree().paused = false
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	var mode := "mobile" if GameState.settings.show_touch_controls else "desktop"
	print("HIP_FIRE_SPREAD_TEST_PASS mode=%s checks=%d real_rays=true projectile=true" % [mode, checks] if failures.is_empty() else "HIP_FIRE_SPREAD_TEST_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

const TARGET_DISTANCE := 25.0

func _create_target() -> void:
	target = HitRecorder.new()
	target.collision_layer = 2
	target.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 30, 0.2)
	collision.shape = box
	target.add_child(collision)
	world.add_child(target)
	_place_target(TARGET_DISTANCE)

func _place_target(distance: float) -> void:
	# Recovered weapon ranges differ by an order of magnitude: gun06 reaches
	# 8 m while a rifle reaches over 100. A wall outside the weapon's own range
	# records no hits at all and would read as a spread regression.
	var aim := player.get_aim_solution(distance * 2.0)
	target.global_basis = player.camera.global_basis
	target.global_position = Vector3(aim.origin) + Vector3(aim.direction) * distance

func _check_catalog() -> void:
	var ranges: Dictionary = {}
	for id: String in GameState.WEAPONS:
		var weapon: Dictionary = GameState.WEAPONS[id]
		var profile: Dictionary = weapon.get("hip_spread", {})
		_check(not profile.is_empty(), id + " has no spread profile")
		if profile.is_empty():
			continue
		for field: String in ["min_degrees", "max_degrees", "per_shot_degrees", "recovery_delay", "recovery_degrees_per_second", "reticle_max_scale"]:
			_check(profile.has(field), id + " missing " + field)
		_check(is_zero_approx(float(profile.min_degrees)), id + " no longer starts precise")
		if str(weapon.kind) == "sword":
			_check(is_zero_approx(float(profile.max_degrees)), id + " melee has bloom")
		else:
			_check(float(profile.max_degrees) > 0.0 and float(profile.max_degrees) <= 3.0, id + " cone is absent or exceeds the small-spread design")
			_check(float(profile.per_shot_degrees) > 0.0 and float(profile.per_shot_degrees) < float(profile.max_degrees), id + " cannot grow gradually")
			_check(float(profile.recovery_degrees_per_second) > 0.0 and float(profile.recovery_delay) >= 0.0, id + " cannot recover")
			_check(float(profile.reticle_max_scale) > 1.0 and float(profile.reticle_max_scale) <= 1.5, id + " reticle expansion is absent or excessive")
			ranges[float(profile.max_degrees)] = true
	_check(ranges.size() > 1, "every gun uses one identical spread range")

func _check_hitscan_paths() -> void:
	for id: String in ["gun00", "gun17", "gun24", "gun01"]:
		_equip(id)
		var peak := float(player.current_weapon.hip_spread.max_degrees)
		var max_observed := 0.0
		for shot in 18:
			target.hits.clear()
			var aim := player.get_aim_solution(float(player.current_weapon.range))
			var before := player.get_hip_spread_degrees()
			var count_before := shot_count
			_fire()
			_check(shot_count == count_before + 1, id + " test shot was blocked")
			_check(target.hits.size() == 1, id + " real hitscan missed the wide target")
			if not target.hits.is_empty():
				var observed := rad_to_deg(Vector3(aim.direction).angle_to((target.hits[0] - Vector3(aim.origin)).normalized()))
				_check(observed <= before + 0.015, id + " actual ray exceeded its pre-shot cone")
				if shot == 0:
					_check(observed < 0.015, id + " first shot did not hit the center ray")
				max_observed = maxf(max_observed, observed)
			_check(player.get_hip_spread_degrees() <= peak + 0.0001, id + " exceeded cap")
		_check(max_observed > peak * 0.25, id + " fired center rays despite accumulated spread")
		_check(is_equal_approx(player.get_hip_spread_degrees(), peak), id + " sustained fire never reached cap")
		_check(is_equal_approx(player.get_hip_reticle_scale(), float(player.current_weapon.hip_spread.reticle_max_scale)), id + " cap is disconnected from reticle")

func _check_projectile_path() -> void:
	_equip("gun11")
	var max_observed := 0.0
	for shot in 12:
		var aim := player.get_aim_solution(float(player.current_weapon.range))
		var allowed := player.get_hip_spread_degrees()
		var child_count := world.get_child_count()
		_fire()
		var projectile: WarfareProjectile
		for index in range(child_count, world.get_child_count()):
			if world.get_child(index) is WarfareProjectile:
				projectile = world.get_child(index) as WarfareProjectile
		_check(is_instance_valid(projectile), "rocket _try_fire did not spawn a projectile")
		if not is_instance_valid(projectile):
			continue
		# Reconstruct the point where the actual muzzle ray reaches the camera's
		# target plane, so shoulder-camera parallax is not mistaken for bloom.
		var forward: Vector3 = aim.direction
		var distance := (Vector3(aim.target) - projectile.global_position).dot(forward) / projectile.direction.dot(forward)
		var endpoint := projectile.global_position + projectile.direction * distance
		var observed := rad_to_deg(forward.angle_to((endpoint - Vector3(aim.origin)).normalized()))
		_check(observed <= allowed + 0.025, "spawned rocket direction exceeded its cone")
		if shot == 0:
			_check(observed < 0.015, "first rocket failed to converge on camera center")
		max_observed = maxf(max_observed, observed)
		# Match gameplay cleanup: let the renderer finish this frame before
		# releasing the freshly created rocket and its materials.
		projectile.queue_free()
	_check(max_observed > float(player.current_weapon.hip_spread.max_degrees) * 0.25, "rocket initial direction ignored hip bloom")

func _check_shotgun_baseline() -> void:
	_equip("gun06")
	_place_target(float(player.current_weapon.range) * 0.6)
	await get_tree().physics_frame
	target.hits.clear()
	_check(float(player.current_weapon.spread) > 0.0, "shotgun pellet baseline was erased")
	_fire()
	_check(target.hits.size() == int(player.current_weapon.pellets), "shotgun no longer fires all pellets")
	var widest := 0.0
	for hit in target.hits:
		widest = maxf(widest, hit.distance_to(target.hits[0]))
	_check(widest > 0.05, "precise initial hip aim collapsed the shotgun pellet pattern")
	_place_target(TARGET_DISTANCE)
	await get_tree().physics_frame

func _check_blocked_triggers() -> void:
	_equip("gun00")
	_fire()
	var before := player.get_hip_spread_degrees()
	var count_before := shot_count
	player._try_fire()
	_check(is_equal_approx(player.get_hip_spread_degrees(), before) and shot_count == count_before, "cooldown rejection increased spread")
	player.shot_cooldown = 0.0
	player.energy = 0.0
	player._try_fire()
	_check(is_equal_approx(player.get_hip_spread_degrees(), before) and shot_count == count_before, "empty-energy rejection increased spread")
	player.energy = player.max_energy
	player._set_magazine_rounds(0)
	player._try_fire()
	_check(is_equal_approx(player.get_hip_spread_degrees(), before) and shot_count == count_before, "empty-magazine rejection increased spread")
	_check(player.reload_left > 0.0, "blocked magazine did not start reload")
	player._try_fire()
	_check(is_equal_approx(player.get_hip_spread_degrees(), before) and shot_count == count_before, "reload rejection increased spread")
	player._cancel_reload(false)
	player.dead = true
	player._try_fire()
	_check(is_equal_approx(player.get_hip_spread_degrees(), before) and shot_count == count_before, "dead-player rejection increased spread")
	player.dead = false
	_equip("gun24")
	_check(is_zero_approx(player.get_hip_spread_degrees()), "weapon swap retained the previous gun's bloom")

func _check_recovery_and_movement() -> void:
	_equip("gun00")
	for shot in 12:
		_fire()
	var peak := player.get_hip_spread_degrees()
	var delay := player.hip_spread_recovery_left
	player._update_hip_spread(delay * 0.5)
	_check(is_equal_approx(player.get_hip_spread_degrees(), peak), "spread recovered before its delay")
	player._update_hip_spread(delay * 0.5 + 0.05)
	_check(player.get_hip_spread_degrees() < peak and player.get_hip_spread_degrees() > 0.0, "recovery did not begin gradually after the delay")
	var still := player.get_hip_spread_degrees()
	player.velocity = Vector3(8.2, 0, 0)
	Input.action_press("move_forward")
	_check(is_equal_approx(player.get_hip_spread_degrees(), still), "movement alone added bloom")
	# Compare identical elapsed recovery with real player movement input set.
	player._update_hip_spread(0.1)
	var moving := player.get_hip_spread_degrees()
	player.hip_spread_degrees = still
	player.velocity = Vector3.ZERO
	Input.action_release("move_forward")
	player._update_hip_spread(0.1)
	_check(is_equal_approx(player.get_hip_spread_degrees(), moving), "movement changed spread recovery")
	player._set_magazine_rounds(1)
	player._start_reload()
	player._update_hip_spread(10.0)
	_check(is_zero_approx(player.get_hip_spread_degrees()) and is_zero_approx(player.get_hip_spread_ratio()), "reload prevented return to precise baseline")
	_check(is_equal_approx(player.get_hip_reticle_scale(), 1.0), "recovery did not restore reticle baseline")
	player._cancel_reload(false)

func _check_focus_and_melee() -> void:
	for id: String in ["gun00", "gun01"]:
		_equip(id)
		_fire()
		var hip_before := player.hip_spread_degrees
		Input.action_press("aim")
		for shot in 4:
			target.hits.clear()
			var aim := player.get_aim_solution(float(player.current_weapon.range))
			_fire()
			_check(target.hits.size() == 1, id + " focused ray missed target")
			if not target.hits.is_empty():
				_check(Vector3(aim.direction).angle_to((target.hits[0] - Vector3(aim.origin)).normalized()) < 0.0003, id + " focus firing applied hip spread")
		_check(player.hip_spread_degrees <= hip_before, id + " focus fire accumulated new hip bloom")
		Input.action_release("aim")
	for id: String in GameState.WEAPONS:
		if str(GameState.WEAPONS[id].kind) == "sword":
			_equip(id)
			_fire()
			_check(is_zero_approx(player.get_hip_spread_degrees()) and is_equal_approx(player.get_hip_reticle_scale(), 1.0), id + " melee expanded the reticle")

func _check_reticle() -> void:
	_equip("gun00")
	world.hud.fire_reticle_left = 0.0
	world.hud._resize_crosshair()
	world.hud._update_fire_reticle_visibility()
	var base_size: Vector2 = world.hud.crosshair.size
	var original_texture := world.hud.crosshair.texture
	var viewport_center := get_viewport().get_visible_rect().get_center()
	_check(world.hud.find_child("HipSpreadBrackets", true, false) == null, "extra hip-fire frame was recreated")
	_fire()
	var first_size: Vector2 = world.hud.fire_crosshair.size
	_check(first_size.x > base_size.x, "first shot did not expand the original reticle")
	_check(first_size.x < base_size.x * float(player.current_weapon.hip_spread.reticle_max_scale), "first shot jumped straight to full expansion")
	for shot in 12:
		_fire()
	world.hud._resize_crosshair()
	world.hud._update_fire_reticle_visibility()
	_check(world.hud.fire_crosshair.visible and not world.hud.crosshair.visible, "bloom did not select fire reticle")
	var peak_size := base_size * float(player.current_weapon.hip_spread.reticle_max_scale)
	_check(world.hud.crosshair.size.is_equal_approx(peak_size), "original reticle did not reach this gun's expansion limit")
	_check(world.hud.crosshair.texture == original_texture and world.hud.fire_crosshair.texture == original_texture, "firing replaced the original reticle image")
	_check(world.hud.fire_crosshair.size.is_equal_approx(world.hud.crosshair.size), "reticle layers have different sizes")
	_check(world.hud.fire_crosshair.get_global_rect().get_center().distance_to(viewport_center) < 0.01, "reticle moved away from viewport center")
	world.hud.fire_reticle_left = 0.0
	world.hud._update_fire_reticle_visibility()
	_check(world.hud.fire_crosshair.visible, "short fire flash expiry hid ongoing recovery")
	player._update_hip_spread(player.hip_spread_recovery_left + 0.1)
	world.hud._update_fire_reticle_visibility()
	_check(world.hud.fire_crosshair.size.x < peak_size.x and world.hud.fire_crosshair.size.x > base_size.x, "original reticle did not shrink gradually")
	player._update_hip_spread(10.0)
	world.hud._resize_crosshair()
	world.hud._update_fire_reticle_visibility()
	_check(world.hud.crosshair.visible and not world.hud.fire_crosshair.visible, "recovery did not restore idle reticle")
	_check(world.hud.crosshair.size.is_equal_approx(base_size), "recovery did not restore original reticle size")
	_check(world.hud.crosshair.get_global_rect().get_center().distance_to(viewport_center) < 0.01, "idle reticle moved away from viewport center")

func _check_pause() -> void:
	_equip("gun00")
	for shot in 5:
		_fire()
	var before := player.hip_spread_degrees
	var delay_before := player.hip_spread_recovery_left
	# Re-enable the real player callback: pause must stop that callback even
	# though this test node continues and can observe elapsed process frames.
	player.set_physics_process(true)
	get_tree().paused = true
	for frame in 4:
		await get_tree().process_frame
	_check(is_equal_approx(player.hip_spread_degrees, before) and is_equal_approx(player.hip_spread_recovery_left, delay_before), "pause advanced spread or its recovery timer")
	player.set_physics_process(false)
	get_tree().paused = false
