extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PROJECTILE VFX TEST: " + message)

func _run() -> void:
	_test_weapon_groups()
	_test_tracer_cadence()
	_test_hd_assets()
	await _test_runtime_visuals()
	if failures.is_empty():
		print("PROJECTILE_VFX_TEST_PASS modern=3 legacy_hd=37 recovered_effects=6 original_rocket=1")
		get_tree().quit(0)
	else:
		print("PROJECTILE_VFX_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _test_weapon_groups() -> void:
	for gun_id in [0, 1, 2, 3, 4, 5, 40]:
		var data: Dictionary = GameState.WEAPONS["gun%02d" % gun_id]
		_check(data.tracer_style == "rifle" and int(data.tracer_every) == 3, "gun%02d is not a modern rifle tracer" % gun_id)
	for gun_id in [24, 25, 39]:
		var data: Dictionary = GameState.WEAPONS["gun%02d" % gun_id]
		_check(data.tracer_style == "machinegun" and int(data.tracer_every) == 5, "gun%02d is not a modern machinegun tracer" % gun_id)
	for gun_id in [17, 18, 19, 26]:
		var data: Dictionary = GameState.WEAPONS["gun%02d" % gun_id]
		_check(data.tracer_style == "laser" and int(data.tracer_every) == 1, "gun%02d is not a modern blue laser" % gun_id)
	for gun_id in [34, 35, 43]:
		_check(GameState.WEAPONS["gun%02d" % gun_id].tracer_style == "sniper_legacy_hd", "gun%02d lost its legacy HD sniper texture" % gun_id)

func _test_tracer_cadence() -> void:
	var player := WarfarePlayer.new()
	player.current_weapon_id = "gun00"
	var rifle_pattern: Array[bool] = []
	for index in range(4):
		rifle_pattern.append(player._consume_tracer_slot("rifle", 3))
	_check(rifle_pattern == [true, false, false, true], "rifle tracer cadence is not one in three")
	player.current_weapon_id = "gun24"
	var machine_pattern: Array[bool] = []
	for index in range(6):
		machine_pattern.append(player._consume_tracer_slot("machinegun", 5))
	_check(machine_pattern == [true, false, false, false, false, true], "machinegun tracer cadence is not one in five")
	_check(player._consume_tracer_slot("laser", 1), "blue laser skipped a beam")
	player.free()

func _test_hd_assets() -> void:
	var root := "res://assets/vfx/legacy_hd/"
	var required := [
		"laser_02_hd.png", "l_001_hd.png", "shandian_005_hd.png",
		"plasma_bolt1_red_hd.png", "gun0910_hd.png", "gun0506_hd.png",
		"bug_RPG6_hd.png", "gun_up_1_slf_sfx_hd.png", "joke_force_hd.png",
		"joke_warning01_hd.png", "xmas_light01_r_hd.png", "HotWing_D_hd.png",
		"S2_Fireflys_hd.png", "Skill_1_01_hd.png", "VD5_Rush_01_hd.png",
		"bc_002_hd.png", "dg_test_002_hd.png", "glow_002_hd.png",
		"bc_002_a_hd.png", "dg_test_002_a_hd.png", "glow_002_a_hd.png",
		"fd_01_hd.png", "fire_00302_hd.png", "fire_smook_001_hd.png",
		"gunpoint_01_hd.png", "gunpoint_02_hd.png", "gunpoint_03_hd.png",
		"gunpoint_m_01_hd.png", "gunpoint_m_02_hd.png", "gunpoint_m_03_hd.png",
		"gunpoint_blue_01_hd.png", "gunpoint_blue_02_hd.png", "gunpoint_blue_03_hd.png",
		"gunburst_01_hd.png", "gunburst_02_hd.png", "gunburst_03_hd.png", "laserParticle_hd.png",
	]
	for file_name: String in required:
		var path: String = root + file_name
		_check(ResourceLoader.exists(path), "missing HD projectile texture: " + file_name)
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			_check(texture != null and mini(texture.get_width(), texture.get_height()) >= 256, file_name + " is not HD-sized")
	_check(ResourceLoader.exists("res://assets/models/projectiles/original_rocket.obj"), "missing converted Unity Effect/Projectile mesh")
	_check(ResourceLoader.exists("res://assets/models/projectiles/gun0910_hd.png"), "missing HD original rocket atlas")
	if ResourceLoader.exists("res://assets/models/projectiles/gun0910_hd.png"):
		var rocket_atlas := load("res://assets/models/projectiles/gun0910_hd.png") as Texture2D
		_check(rocket_atlas != null and mini(rocket_atlas.get_width(), rocket_atlas.get_height()) >= 1024, "original rocket atlas was not HD-remastered")

func _test_runtime_visuals() -> void:
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	world.completed = true
	var from := Vector3(0.0, 2.0, 0.0)
	var to := Vector3(0.0, 2.0, -30.0)
	var rifle := world.spawn_tracer(from, to, Color(1.0, 0.64, 0.08), "rifle")
	var machinegun := world.spawn_tracer(from + Vector3.RIGHT, to + Vector3.RIGHT, Color(1.0, 0.72, 0.08), "machinegun")
	var laser := world.spawn_tracer(from + Vector3.RIGHT * 2.0, to + Vector3.RIGHT * 2.0, Color(0.08, 0.78, 1.0), "laser")
	var sniper := world.spawn_tracer(from + Vector3.RIGHT * 3.0, to + Vector3.RIGHT * 3.0, Color(0.75, 0.2, 1.0), "sniper_legacy_hd")
	_check(rifle.name == "ModernRifleTracer" and float(rifle.get_meta("segment_length")) <= 5.6, "rifle is not a short moving streak")
	_check(machinegun.name == "ModernMachinegunTracer" and float(machinegun.get_meta("segment_length")) <= 3.4, "machinegun streak is not thinner and shorter")
	var machine_muzzle := world.spawn_machinegun_muzzle_fx(from + Vector3.RIGHT, Vector3.FORWARD)
	_check(machine_muzzle.get_node_or_null("MuzzleHeatWave") != null and machine_muzzle.get_node_or_null("EjectedCasing") != null, "machinegun lacks muzzle heat or casing ejection")
	var rifle_muzzle := world.spawn_muzzle_effect(from, Vector3.FORWARD, "rifle")
	var recovered_machine_muzzle := world.spawn_muzzle_effect(from + Vector3.RIGHT, Vector3.FORWARD, "machinegun")
	var laser_muzzle := world.spawn_muzzle_effect(from + Vector3.RIGHT * 2.0, Vector3.FORWARD, "laser")
	_check(rifle_muzzle.get_meta("source_effect") == "Effect/GunFire" and _mesh_texture_paths(rifle_muzzle).size() == 3, "rifle did not restore Effect/GunFire")
	_check(recovered_machine_muzzle.get_meta("source_effect") == "Effect/GunFire_M" and _mesh_texture_paths(recovered_machine_muzzle).size() == 3, "machinegun did not restore Effect/GunFire_M")
	_check(laser_muzzle.get_meta("source_effect") == "Effect/GunFire_Laser" and _mesh_texture_paths(laser_muzzle).size() == 3, "laser did not restore Effect/GunFire_Laser")
	_check(laser.name == "ModernBlueLaser" and laser.get_node_or_null("LaserEndpointLight") != null, "blue laser lacks its layered beam or endpoint light")
	_check(laser.get_node_or_null("WhiteEnergyCore") != null and laser.get_node_or_null("CyanEnergyFlow") != null and laser.get_node_or_null("BlueOuterGlow") != null, "blue laser is missing an energy layer")
	_check(laser.get_node_or_null("LaserEmissionParticles") != null and laser.get_node_or_null("LaserEmissionLight") != null, "blue laser lacks independent muzzle particles or light")
	var laser_impact := world.spawn_impact(to, Vector3.BACK, Color(0.08, 0.78, 1.0), "laser")
	_check(laser_impact.get_node_or_null("ElectricArcs") != null and laser_impact.get_node_or_null("LaserImpactLight") != null, "blue laser lacks independent impact arcs or light")
	var gun_impact := world.spawn_impact(to + Vector3.RIGHT, Vector3.BACK, Color.ORANGE, "rifle")
	_check(gun_impact.get_node_or_null("RecoveredGunBurst") != null and gun_impact.get_node("RecoveredGunBurst").get_meta("source_effect") == "Effect/GunBurst", "hitscan impact did not restore Effect/GunBurst")
	_check(laser_impact.get_node_or_null("RecoveredLaserHit") != null and laser_impact.get_node("RecoveredLaserHit").get_meta("source_effect") == "Effect/LaserHit", "laser impact did not restore Effect/LaserHit")
	_check(sniper.name == "LegacyHDSniperTracer" and sniper.get_node_or_null("RecoveredLaserPlane00") != null, "sniper does not use the restored HD beam")
	var variants := [
		["plasma", "gun20", ["l_001_hd.png", "shandian_005_hd.png"]],
		["rocket", "gun11", ["gun0910_hd.png", "plasma_bolt1_red.png", "fire_00302_hd.png", "fire_smook_001_hd.png"]],
		["rocket", "gun30", ["bug_RPG6_hd.png", "gun_up_1_slf_sfx_hd.png", "fire_00302_hd.png", "fire_smook_001_hd.png"]],
		["grenade", "gun14", ["gun0506_hd.png"]],
		["grenade", "gun41", ["joke_force_hd.png", "joke_warning01_hd.png", "xmas_light01_r_hd.png"]],
		["fly_grenade", "gun45", ["HotWing_D_hd.png", "S2_Fireflys_hd.png", "Skill_1_01_hd.png", "VD5_Rush_01_hd.png"]],
		["tracking", "gun36", ["dg_test_002_hd.png", "bc_002_hd.png", "glow_002_hd.png"]],
		["spring", "gun42", ["dg_test_002_a_hd.png", "bc_002_a_hd.png", "glow_002_a_hd.png"]],
		["ricochet", "gun37", ["fd_01_hd.png"]],
	]
	for record in variants:
		var projectile := WarfareProjectile.new()
		projectile.configure(world.player, Vector3.FORWARD, 12.0, 10.0, 1.0, Color.WHITE, false, record[0], "", record[1])
		world.add_child(projectile)
		var texture_paths := _mesh_texture_paths(projectile)
		for expected_texture: String in record[2]:
			_check(texture_paths.any(func(path: String): return path.ends_with(expected_texture)), "%s %s does not use %s" % [record[0], record[1], expected_texture])
		if record[0] == "rocket" and record[1] == "gun11":
			var original_body := projectile.get_node_or_null("ProjectileVisual/OriginalUnityRocket") as MeshInstance3D
			_check(original_body != null, "standard RPG does not instantiate the original Unity projectile")
			if original_body != null:
				_check(original_body.get_meta("source_prefab", "") == "Effect/Projectile", "standard RPG lost its Unity prefab provenance")
				_check(original_body.mesh != null and original_body.mesh.get_surface_count() == 4, "original RPG body/flame mesh does not have its four recovered surfaces")
			_check(projectile.get_node_or_null("ProjectileVisual/OriginalRocketSmokeLong") != null, "original RPG is missing its long smoke emitter")
			_check(projectile.get_node_or_null("ProjectileVisual/OriginalRocketSmokeHot") != null, "original RPG is missing its hot smoke emitter")
		projectile.queue_free()
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame

func _mesh_texture_paths(node: Node) -> Array[String]:
	var paths: Array[String] = []
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		_append_mesh_texture_paths(paths, mesh_instance.mesh, mesh_instance)
	for particle_node in node.find_children("*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		if particles.draw_pass_1 != null:
			_append_mesh_texture_paths(paths, particles.draw_pass_1)
	return paths

func _append_mesh_texture_paths(paths: Array[String], mesh: Mesh, mesh_instance: MeshInstance3D = null) -> void:
	for surface_index in mesh.get_surface_count():
		var material: Material
		if mesh_instance != null:
			material = mesh_instance.get_surface_override_material(surface_index)
		if material == null:
			material = mesh.surface_get_material(surface_index)
		if material is StandardMaterial3D:
			var standard := material as StandardMaterial3D
			if standard.albedo_texture != null:
				paths.append(standard.albedo_texture.resource_path)
