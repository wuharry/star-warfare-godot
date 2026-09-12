extends Node3D

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("WEAPON POLISH: " + message)

func _run() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 10)
	add_child(camera)
	camera.current = true
	GameState.settings.quality = "high"
	_check(WeaponVfxPolish.beam(self, Vector3.ZERO, Vector3.ZERO, Color.CYAN) == null, "zero-length beam created invalid geometry")
	var beam := WeaponVfxPolish.beam(self, Vector3.LEFT * 3, Vector3.RIGHT * 3, Color.CYAN)
	beam.set_process(false)
	_check(beam.ribbon.get_surface_count() == 1, "beam has no soft ribbon")
	_check(beam.find_children("*", "CollisionObject3D", true, false).is_empty(), "presentation effect has gameplay collision")
	_check(not str(beam.ribbon_material.shader.code).contains("depth_test_disabled"), "beam ignores occlusion")
	beam._process(0.2)
	_check(beam.is_queued_for_deletion(), "beam never expires")
	await get_tree().process_frame
	var source := Node3D.new()
	add_child(source)
	var trail := WeaponVfxPolish.trail(source, Color.GREEN, "plasma")
	trail.set_process(false)
	for step in 60:
		source.position = Vector3(step * 0.06, sin(step * 0.12), 0)
		trail._process(0.002)
	_check(trail.points.size() <= WeaponVfxPolish.MAX_POINTS, "trail geometry exceeds point budget")
	_check(trail.points.size() > 10, "trail does not retain curved path history")
	var old_position := trail.points[0]
	source.position += Vector3.RIGHT
	trail._process(0.01)
	_check(trail.points[0] != source.position, "old trail moves with projectile")
	_check(old_position.distance_to(trail.points[0]) < 0.2, "old world-space sample was transformed")
	source.position += Vector3.RIGHT * 30.0
	trail._process(0.01)
	_check(trail.points.size() == 1, "teleport connects a screen-length trail")
	source.position += Vector3.UP
	trail._process(0.01)
	source.free()
	trail._process(0.02)
	_check(not trail.is_queued_for_deletion(), "trail disappears instantly on impact")
	trail._process(0.4)
	_check(trail.is_queued_for_deletion(), "detached trail leaks after fade")
	await get_tree().process_frame
	var burst := WeaponVfxPolish.burst(self, Vector3.ZERO, Vector3.UP, Color.CYAN)
	burst.set_process(false)
	var particles := burst.get_node("EnergyMotes") as CPUParticles3D
	_check(particles.one_shot and not particles.local_coords, "impact particles are not world-space one-shot")
	_check(particles.scale_amount_min >= 0.05, "impact motes are invisibly double-scaled")
	burst._process(0.5)
	_check(burst.is_queued_for_deletion(), "burst leaks after fade")
	await get_tree().process_frame
	GameState.settings.quality = "low"
	var admitted := 0
	for index in 30:
		var effect := WeaponVfxPolish.burst(self, Vector3.ZERO, Vector3.UP, Color.CYAN)
		if effect != null:
			admitted += 1
			effect.set_process(false)
			_check(effect.get_node_or_null("EnergyMotes") == null, "low quality retains secondary motes")
	_check(admitted == 18, "low-quality active effect limit is not enforced")
	for effect in get_tree().get_nodes_in_group(WeaponVfxPolish.GROUP): effect.queue_free()
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group(WeaponVfxPolish.GROUP).is_empty(), "effect budget does not recover after cleanup")
	print("WEAPON_POLISH_TEST_PASS" if failures.is_empty() else "WEAPON_POLISH_TEST_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
