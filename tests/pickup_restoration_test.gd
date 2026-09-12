extends Node3D

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PICKUP TEST: " + message)

func _drop(world: WarfareGameWorld, kind: String, value: float) -> WarfarePickup:
	world.spawn_pickup(world.player.global_position + Vector3(8, 1, 0), kind, value)
	var pickup := world.get_child(world.get_child_count() - 1) as WarfarePickup
	pickup.set_process(false)
	return pickup

func _run() -> void:
	GameState.selected_level = 1
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	world.completed = true
	world.set_process(false)
	world.player.set_physics_process(false)
	var money := _drop(world, "credits", 13.0)
	var energy := _drop(world, "energy", 22.0)
	var ammo := _drop(world, "ammo", 18.0)
	_check(money.model.prefab_name == "Money", "credits do not use original Money mesh")
	_check(energy.model.prefab_name == "Enegy" and ammo.model.prefab_name == "Enegy", "energy/ammo mapping is incorrect")
	_check(money.halo.prefab_name == "Halo", "white original halo is missing")
	var energy_mesh := energy.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_check(energy_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] == energy_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV], "single-UV energy mesh is not shared by both texture stages")
	_check(energy_mesh.material_override.get_shader_parameter("overlay_texture") != null, "energy glow lost danjia_l texture")
	var credits_before := world.battle_credits
	var non_player := Node3D.new()
	money._on_body_entered(non_player) # Non-player collision must do nothing.
	non_player.free()
	_check(not money.collected, "non-player collected the drop")
	money._on_body_entered(world.player)
	money._on_body_entered(world.player)
	_check(world.battle_credits == credits_before + 13, "credits were not awarded exactly once")
	world.player.energy = world.player.max_energy - 30
	var shield_before := world.player.shield
	energy._on_body_entered(world.player)
	energy._on_body_entered(world.player)
	_check(world.player.energy == world.player.max_energy - 8, "energy was not restored exactly once")
	ammo._on_body_entered(world.player)
	_check(world.player.energy == world.player.max_energy, "ammo alias did not clamp energy")
	_check(world.player.shield == shield_before, "energy pickup changed shield")
	var effects: Array[OriginalPickupVisual] = []
	for child: Node in world.player.get_children():
		if child is OriginalPickupVisual:
			effects.append(child)
	_check(effects.size() == 3, "one effect per consumed drop was not created")
	for effect: OriginalPickupVisual in effects:
		effect.set_process(false)
		_check(effect.position == Vector3.UP, "effect is not at player + 1")
		_check(effect.find_children("*", "MeshInstance3D", true, false).size() == 3, "original three animated rings are missing")
		_check(effect.emitters.size() == 1, "original star emitter is missing")
		effect.advance(0.25)
		_check(effect.emitters[0].node.emitting, "star emitter did not start after delay")
		var alpha_tracks := 0
		for track: Dictionary in effect.tracks:
			if track.channel.kind == "alpha":
				alpha_tracks += 1
				_check(float(track.material.get_shader_parameter("alpha")) > 0.0, "ring remains invisible after pickup")
		_check(alpha_tracks == 3, "ring alpha animations were not recovered")
	await get_tree().process_frame
	_check(not is_instance_valid(money) and not is_instance_valid(energy), "consumed drops survived")
	var effect_start := effects[0].global_position
	world.player.position += Vector3.RIGHT * 2.0
	_check(effects[0].global_position.is_equal_approx(effect_start + Vector3.RIGHT * 2.0), "effect does not follow player")
	for effect: OriginalPickupVisual in effects:
		effect.advance(0.6)
		_check(not effect.emitters[0].node.emitting, "star emitter did not stop")
		for track: Dictionary in effect.tracks:
			if track.channel.kind == "alpha":
				_check(absf(float(track.material.get_shader_parameter("alpha"))) < 0.001, "ring failed to fade out")
		effect._process(1.2)
	await get_tree().process_frame
	_check(not is_instance_valid(effects[0]), "effect leaked after original two-second lifetime")
	# Exercise the actual Area3D signal as well as the guarded callback above.
	credits_before = world.battle_credits
	world.spawn_pickup(world.player.global_position + Vector3.UP, "credits", 7)
	for frame in 20:
		if world.battle_credits == credits_before + 7:
			break
		await get_tree().physics_frame
	await get_tree().process_frame
	_check(world.battle_credits == credits_before + 7, "physics overlap did not collect the drop")
	var expired := _drop(world, "credits", 1)
	expired._process(60.0)
	_check(expired.is_queued_for_deletion(), "uncollected drop never expires")
	world.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.2).timeout
	if failures.is_empty():
		print("PICKUP_RESTORATION_TEST_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
