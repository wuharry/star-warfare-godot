extends "res://scripts/game/armor_power_controller.gd"
## Reuse source skill durations/buffs. Only the host runs their effects; client
## snapshots build plain visual nodes, never simulated waves or target modifiers.

const Rules = preload("res://scripts/core/match_rules.gd")

var actions: Node
var _wave_sequence := 0
var _replica_visuals: Dictionary = {}


func _authoritative() -> bool:
	return NetworkSession.is_host() and NetworkSession.phase == "playing" and is_instance_valid(combat_world) and not combat_world.rules.ended


func request_activate(skill_index: int) -> bool:
	return is_instance_valid(actions) and actions.request_action("skill", skill_index) >= 0


func activate_authoritative(skill_index: int) -> bool:
	if not _authoritative() or _player_is_dead():
		return false
	return super.activate_authoritative(skill_index)


func advance_simulation(delta: float) -> void:
	if _authoritative():
		super.advance_simulation(delta)


func on_damage_dealt(actual_damage: float) -> void:
	if _authoritative():
		super.on_damage_dealt(actual_damage)


func _heal_player(amount: float) -> float:
	if not _authoritative() or _player_is_dead() or not is_finite(amount):
		return 0.0
	return super._heal_player(amount)


func _enemy_root(candidate: Node) -> Node3D:
	var current := candidate
	while is_instance_valid(current) and current != combat_world:
		if current is Node3D and current.has_method("take_damage"):
			return current if _can_affect(current) else null
		current = current.get_parent()
	return null


func _can_affect(target: Node) -> bool:
	return _authoritative() and not _player_is_dead() and combat_world.can_damage_target(controlled_player, target)


func _targets_in_radius(center: Vector3, radius: float) -> Array[Node3D]:
	var targets: Array[Node3D] = []
	if not _authoritative(): return targets
	var space := _direct_space_state()
	if space == null: return targets
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 6 # Source enemies/gifts (2) and network players (4).
	for hit: Dictionary in space.intersect_shape(query, 512):
		var target := _enemy_root(hit.get("collider") as Node)
		if is_instance_valid(target) and not targets.has(target):
			targets.append(target)
	return targets


func _damage_enemies_in_radius(center: Vector3, radius: float, base_damage: float) -> void:
	for target: Node3D in _targets_in_radius(center, radius):
		_deal_enemy_damage(target, base_damage, "attack_shield")


func _hit_wave_targets(wave: Dictionary) -> bool:
	var visual: Node3D = wave.get("visual") as Node3D
	if not is_instance_valid(visual): return false
	var targets: Array[Node3D] = []
	var contacted := false
	if wave.has("initial_left"):
		# Source prefab BoxCollider, not the explosion radius. ScaleScript grows
		# impact 0.5 -> 0.65 at 2 * VSMath.IMPACT_WAVE_SPEED_BOOTH (0.1/s).
		var age := float(wave.initial_left) - float(wave.left)
		var scale_value := minf(0.65, (0.5 if str(wave.kind) == "impact" else 1.0) + age * 0.1)
		wave.source_scale = scale_value
		visual.scale = Vector3.ONE * scale_value
		var shape := BoxShape3D.new()
		shape.size = (Vector3(5.19, 1.41, 1.5) if str(wave.kind) == "impact" else Vector3(1.14, 1.05, 1.07)) * scale_value
		var previous: Vector3 = wave.previous_position
		var travel := visual.global_position - previous
		var steps := maxi(1, ceili(travel.length() / (minf(shape.size.x, minf(shape.size.y, shape.size.z)) * 0.5)))
		var parameters := PhysicsShapeQueryParameters3D.new()
		parameters.shape = shape
		parameters.collision_mask = 7
		if controlled_player is CollisionObject3D: parameters.exclude = [controlled_player.get_rid()]
		for sample in range(1, mini(steps, 128) + 1):
			var center := previous.lerp(visual.global_position, float(sample) / mini(steps, 128))
			if str(wave.kind) == "impact": center += Vector3(wave.direction) * 1.5 * scale_value
			parameters.transform = Transform3D(Basis.looking_at(wave.direction, Vector3.FORWARD if absf(Vector3(wave.direction).y) > 0.98 else Vector3.UP), center)
			for hit: Dictionary in _direct_space_state().intersect_shape(parameters, 512):
				contacted = true
				var target := _enemy_root(hit.get("collider") as Node)
				if is_instance_valid(target) and not targets.has(target): targets.append(target)
			if contacted and not bool(wave.penetrating):
				# TrackWave detonates on terrain too, then marks one target in
				# its original 3-unit explosion radius (TrackWaveScript).
				targets = _targets_in_radius(center, float(wave.radius))
				break
		wave.previous_position = visual.global_position
	else:
		targets = _targets_in_radius(visual.global_position, float(wave.radius))
	for target: Node3D in targets:
		var id := target.get_instance_id()
		var elapsed := float(wave.get("initial_left", 0.0)) - float(wave.get("left", 0.0))
		if wave.hit_ids.has(id) and elapsed - float(wave.hit_ids[id]) <= 0.3: continue
		wave.hit_ids[id] = elapsed
		var dealt := _deal_enemy_damage(target, float(wave.damage), str(wave.kind))
		if str(wave.kind) == "impact" and not is_skill_active(4):
			_heal_player(dealt * 0.5)
		elif str(wave.kind) == "track" and dealt > 0.0:
			_apply_tracking_mark(target)
		if not bool(wave.penetrating): return true
	return contacted and not bool(wave.penetrating)


func _deal_enemy_damage(target: Node3D, base_damage: float, damage_kind: String) -> float:
	if not _can_affect(target): return 0.0
	var damage: float = base_damage if damage_kind == "track" else modify_outgoing_damage(base_damage) * combat_world.rules.damage_multiplier(int(controlled_player.peer_id))
	if combat_world.pvp_arena and damage_kind != "track":
		damage = Rules.vs_damage(damage, "armor_power")
		# LocalPlayer.ImpactWave applies VSMath.IMPACT_WAVE_DAMAGE_BOOTH
		# after GetDamageInVS. Other active skills do not share that multiplier.
		if damage_kind == "impact": damage *= 2.5
	# take_damage already notifies the source of actual damage (life steal).
	return combat_world.damage_target(controlled_player, target, damage, target.global_position, "")


func _spawn_wave(kind: String, speed: float, radius: float, damage: float, lifetime: float, penetrating: bool) -> void:
	if not _authoritative(): return
	var previous := _waves.size()
	super._spawn_wave(kind, speed, radius, damage, lifetime, penetrating)
	if _waves.size() > previous:
		_wave_sequence += 1
		var wave: Dictionary = _waves.back()
		wave.network_id = _wave_sequence
		wave.initial_left = lifetime
		wave.source_scale = 0.5 if kind == "impact" else 0.65
		var visual: Node3D = wave.visual
		if controlled_player.has_method("get_enemy_knockback_forward"):
			visual.global_position = controlled_player.global_position + Vector3.UP + controlled_player.get_enemy_knockback_forward() * 0.5
			wave.direction = (Vector3(_aim_solution(1000.0).target) - visual.global_position).normalized()
		wave.previous_position = visual.global_position
		visual.scale = Vector3.ONE * float(wave.source_scale)


func _apply_tracking_mark(target: Node3D) -> void:
	if not _can_affect(target): return
	var id := target.get_instance_id()
	if _tracked_targets.has(id):
		_tracked_targets[id].left = TRACK_MARK_DURATION
		return
	var property := "move_speed" if "peer_id" in target else "speed"
	if property not in target: return
	var speed := float(target.get(property))
	# Several casters can mark one enemy. The final mark restores the original
	# speed; removing one caster must not undo another caster's live slow.
	var owners: Dictionary = target.get_meta("network_track_owners", {})
	if owners.is_empty():
		target.set_meta("network_track_speed", speed)
	owners[get_instance_id()] = true
	target.set_meta("network_track_owners", owners)
	target.set(property, float(target.get_meta("network_track_speed")) * 0.7)
	var marker := _create_orb_visual(SKILL_COLORS[7], 0.34, 0.38)
	target.add_child(marker)
	marker.position = Vector3.UP * 2.0
	_tracked_targets[id] = {"target": target, "property": property,
		"left": TRACK_MARK_DURATION, "marker": marker}


func _remove_tracking_mark(target_id: int, restore_speed: bool) -> void:
	if not _tracked_targets.has(target_id): return
	var record: Dictionary = _tracked_targets[target_id]
	if is_instance_valid(record.get("target")):
		var target: Node3D = record.target
		var owners: Dictionary = target.get_meta("network_track_owners", {})
		owners.erase(get_instance_id())
		target.set_meta("network_track_owners", owners)
		if restore_speed and owners.is_empty():
			target.set(str(record.property), float(target.get_meta("network_track_speed", target.get(str(record.property)))))
	if is_instance_valid(record.get("marker")): record.marker.queue_free()
	_tracked_targets.erase(target_id)


func _begin_gravity_force() -> void:
	if _authoritative(): super._begin_gravity_force()


func _update_gravity_force(delta: float) -> void:
	if is_instance_valid(_gravity_target) and not _can_affect(_gravity_target):
		_clear_gravity_force()
		return
	if _authoritative(): super._update_gravity_force(delta)


func snapshot() -> Dictionary:
	var visuals: Array[Dictionary] = []
	for wave: Dictionary in _waves:
		var visual: Node3D = wave.get("visual") as Node3D
		if is_instance_valid(visual):
			visuals.append({"id": "wave:%d" % int(wave.network_id), "kind": str(wave.kind), "position": visual.global_position, "scale": visual.scale})
	for id: int in _tracked_targets:
		var target: Node3D = _tracked_targets[id].get("target") as Node3D
		if is_instance_valid(target):
			visuals.append({"id": "mark:%d" % id, "kind": "mark", "position": target.global_position + Vector3.UP * 2.0})
	if is_instance_valid(_gravity_target):
		visuals.append({"id": "gravity", "kind": "gravity", "position": _gravity_target.global_position + Vector3.UP * 1.25})
	return {"active": active_left.duplicate(), "cooldown": cooldown_left.duplicate(), "visuals": visuals}


func apply_snapshot(state: Dictionary) -> void:
	if NetworkSession.is_host(): return
	var active: Array = state.get("active", [])
	var cooling: Array = state.get("cooldown", [])
	if active.size() != SKILL_KEYS.size() or cooling.size() != SKILL_KEYS.size(): return
	for index in SKILL_KEYS.size():
		active_left[index] = clampf(float(active[index]), 0.0, DURATIONS[index])
		cooldown_left[index] = clampf(float(cooling[index]), 0.0, COOLDOWNS[index])
		if active_left[index] > 0.0 and not _active_auras.has(index):
			_create_active_aura(index)
		elif active_left[index] <= 0.0:
			_remove_active_aura(index)
		skill_state_changed.emit(index)
	var seen := {}
	for data: Dictionary in state.get("visuals", []):
		var id := str(data.id)
		seen[id] = true
		if not _replica_visuals.has(id):
			var kind := str(data.kind)
			var skill_index := 6 if kind == "impact" else (9 if kind == "gravity" else 7)
			var radius := 0.42 if kind == "impact" else (0.48 if kind == "gravity" else 0.28)
			var visual := _create_orb_visual(SKILL_COLORS[skill_index], radius, 0.55 if kind == "gravity" else 0.78)
			combat_world.add_child(visual)
			_replica_visuals[id] = visual
		_replica_visuals[id].global_position = Vector3(data.position)
		_replica_visuals[id].scale = data.get("scale", Vector3.ONE)
	for id: String in _replica_visuals.keys():
		if not seen.has(id):
			_replica_visuals[id].queue_free()
			_replica_visuals.erase(id)


func _exit_tree() -> void:
	super._exit_tree()
	for visual: Node3D in _replica_visuals.values():
		if is_instance_valid(visual): visual.queue_free()
	_replica_visuals.clear()
