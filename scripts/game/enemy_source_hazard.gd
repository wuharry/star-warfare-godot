extends Node3D

# Poison pools share their owner's timer, as Spider/EarthwormSlimeScript do.
# GasScript has one independent 0.2s timer per cloud. Slow modifiers are keyed
# by pool so leaving one of two overlapping pools cannot cancel the other.
var source: Node
var target: Node3D
var radius := 3.0
var damage := 440.0
var interval := 0.6
var lifetime := 12.0
var slow_multiplier := 1.0
var shared_timer := true
var ground_only := true
var growth_time := 0.2
var elapsed := 0.0
var tick_left := 0.0
var touching: Array[Node3D] = []
var visual: MeshInstance3D
var tint := Color(0.3, 0.7, 0.1, 0.55)


func _ready() -> void:
	add_to_group("enemy_source_effects")
	set_meta("visual_provenance", "procedural source poison volume")
	visual = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.08 if ground_only else 2.4
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	visual.mesh = mesh
	add_child(visual)


func _physics_process(delta: float) -> void:
	elapsed += delta
	tick_left = maxf(0.0, tick_left - delta)
	if elapsed > lifetime:
		queue_free()
		return
	var growth := clampf(elapsed / maxf(growth_time, 0.001), 0.0, 1.0)
	visual.scale = Vector3(growth, 1.0, growth)
	var current: Array[Node3D] = []
	var candidates: Array[Node] = get_tree().get_nodes_in_group("player")
	if is_instance_valid(target) and not candidates.has(target): candidates.append(target)
	for candidate in candidates:
		if not candidate is Node3D or not candidate.has_method("take_damage"): continue
		if "dead" in candidate and candidate.dead: continue
		if ground_only and "armor_skills" in candidate and float(candidate.armor_skills.get("fly", 0.0)) > 0.0: continue
		var offset: Vector3 = candidate.global_position - global_position
		if Vector2(offset.x, offset.z).length() > radius * growth or absf(offset.y) > (1.8 if ground_only else 3.5): continue
		current.append(candidate)
		_set_slow(candidate, slow_multiplier)
		var timer_ready := tick_left <= 0.0
		if shared_timer and is_instance_valid(source):
			var clocks: Dictionary = source.get_meta("source_slime_ticks", {})
			var key := candidate.get_instance_id()
			var now := Time.get_ticks_msec() / 1000.0
			timer_ready = now >= float(clocks.get(key, 0.0))
			if timer_ready:
				clocks[key] = now + interval
				source.set_meta("source_slime_ticks", clocks)
		if timer_ready:
			candidate.take_damage(damage, global_position, source if is_instance_valid(source) else null)
	for previous in touching:
		if is_instance_valid(previous) and not current.has(previous): _set_slow(previous, 1.0)
	if not current.is_empty() and tick_left <= 0.0: tick_left = interval
	touching = current


func _set_slow(player: Node3D, multiplier: float) -> void:
	if slow_multiplier >= 1.0: return
	var modifiers: Dictionary = player.get_meta("enemy_slow_sources", {})
	if multiplier < 1.0: modifiers[get_instance_id()] = multiplier
	else: modifiers.erase(get_instance_id())
	var combined := 1.0
	for value in modifiers.values(): combined = minf(combined, float(value))
	player.set_meta("enemy_slow_sources", modifiers)
	player.set_meta("enemy_move_multiplier", combined)


func _exit_tree() -> void:
	for player in touching:
		if is_instance_valid(player): _set_slow(player, 1.0)
