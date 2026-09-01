class_name ArmorPowerController
extends Node3D

signal skills_changed
signal skill_state_changed(skill_index: int)
signal skill_activated(skill_index: int, skill_key: String)
# Networking is intentionally transport-agnostic. A real client emits this
# request and waits for its host/server integration to validate it and call
# activate_authoritative(). The current restoration has no MultiplayerPeer, so
# campaign and the locally simulated "multiplayer" sectors execute locally.
signal remote_activation_requested(skill_index: int)

const POWER_DAMAGE_SCALE := 0.01
const ANDROMEDA_HEAL := 10000.0 * POWER_DAMAGE_SCALE
const ATTACK_SHIELD_DAMAGE := 100.0 * POWER_DAMAGE_SCALE
const ATTACK_SHIELD_RADIUS := 4.0
const ATTACK_SHIELD_INTERVAL := 0.25
const IMPACT_WAVE_DAMAGE := 22000.0 * POWER_DAMAGE_SCALE
const TRACK_WAVE_DAMAGE := 1.0
const TRACK_MARK_DURATION := 5.0
const GRAVITY_FORCE_DURATION := 2.0
const GRAVITY_FORCE_SPEED := 20.0

const SKILL_KEYS: Array[String] = [
	"power_up", "speed_up", "defence_up", "andromeda_up", "health_steal",
	"attack_shield", "impact_wave", "track_wave", "hurt_health", "gravity_force"
]
const DISPLAY_NAMES: Array[String] = [
	"THUNDER ALL UP", "FLY SPEED UP", "DEFENCE UP", "ANDROMEDA UP", "HEALTH STEAL",
	"ATTACK SHIELD", "IMPACT WAVE", "TRACK WAVE", "HURT HEALTH", "GRAVITY FORCE"
]
const EFFECT_SUMMARIES: Array[String] = [
	"Damage x1.5 and speed +2", "Speed +2", "85% incoming damage reduction",
	"Restore 100 HP, speed +1 and 30% damage reduction",
	"Deal 65% damage and recover the actual damage dealt",
	"Damage nearby enemies every 0.25 seconds", "Fire a penetrating, life-stealing wave",
	"Fire a wave that marks and slows one enemy", "Convert incoming damage into 60% healing",
	"Pull the aimed enemy toward you"
]
const DURATIONS: Array[float] = [10.0, 30.0, 5.0, 15.0, 10.0, 10.0, 1.0, 1.0, 10.0, 1.0]
const COOLDOWNS: Array[float] = [30.0, 90.0, 40.0, 100.0, 120.0, 55.0, 60.0, 30.0, 60.0, 90.0]
const SKILL_COLORS: Array[Color] = [
	Color(1.0, 0.55, 0.08), Color(0.15, 0.55, 1.0), Color(0.2, 1.0, 0.45),
	Color(0.85, 0.2, 1.0), Color(1.0, 0.12, 0.58), Color(0.2, 0.9, 1.0),
	Color(1.0, 0.72, 0.12), Color(0.55, 0.18, 1.0), Color(1.0, 0.18, 0.18),
	Color(0.35, 0.08, 0.8)
]

var controlled_player: Node3D
var combat_world: Node3D
var available_skill_indices: Array[int] = []
var active_left: Array[float] = []
var cooldown_left: Array[float] = []

var _active_auras: Dictionary = {}
var _waves: Array[Dictionary] = []
var _tracked_targets: Dictionary = {}
var _attack_shield_tick_left := 0.0
var _gravity_target: Node3D
var _gravity_left := 0.0
var _gravity_marker: Node3D
var _dead_cancelled := false


func configure(player_node: Node3D, world_node: Node3D = null) -> void:
	controlled_player = player_node
	combat_world = world_node
	_ensure_timer_arrays()
	refresh_available_skills()


func _ready() -> void:
	_ensure_timer_arrays()
	if not is_instance_valid(controlled_player) and get_parent() is Node3D:
		controlled_player = get_parent() as Node3D
	refresh_available_skills()


func _physics_process(delta: float) -> void:
	advance_simulation(delta)


func _exit_tree() -> void:
	_clear_runtime_effects(true)


func _ensure_timer_arrays() -> void:
	if active_left.size() == SKILL_KEYS.size() and cooldown_left.size() == SKILL_KEYS.size():
		return
	active_left.resize(SKILL_KEYS.size())
	cooldown_left.resize(SKILL_KEYS.size())
	active_left.fill(0.0)
	cooldown_left.fill(0.0)


func refresh_available_skills() -> void:
	_ensure_timer_arrays()
	var skill_value: Variant = controlled_player.get("armor_skills") if is_instance_valid(controlled_player) else null
	var equipped_skills: Dictionary = skill_value if skill_value is Dictionary else {}
	var refreshed: Array[int] = []
	for skill_index in range(SKILL_KEYS.size()):
		if float(equipped_skills.get(SKILL_KEYS[skill_index], 0.0)) > 0.0:
			refreshed.append(skill_index)
	for skill_index in available_skill_indices:
		if not refreshed.has(skill_index):
			_cancel_skill(skill_index, true)
	available_skill_indices = refreshed
	skills_changed.emit()


func get_available_skill_indices() -> Array[int]:
	var result: Array[int] = []
	result.assign(available_skill_indices)
	return result


func get_skill_state(skill_index: int) -> Dictionary:
	if not _is_valid_skill_index(skill_index):
		return {}
	return {
		"index": skill_index,
		"key": SKILL_KEYS[skill_index],
		"name": DISPLAY_NAMES[skill_index],
		"summary": EFFECT_SUMMARIES[skill_index],
		"duration": DURATIONS[skill_index],
		"cooldown": COOLDOWNS[skill_index],
		"active_left": active_left[skill_index],
		"cooldown_left": cooldown_left[skill_index],
		"available": available_skill_indices.has(skill_index),
		"active": is_skill_active(skill_index),
		"ready": is_skill_ready(skill_index),
	}


func is_skill_active(skill_index: int) -> bool:
	return _is_valid_skill_index(skill_index) and active_left[skill_index] > 0.0


func is_skill_ready(skill_index: int) -> bool:
	return (
		_is_valid_skill_index(skill_index)
		and available_skill_indices.has(skill_index)
		and cooldown_left[skill_index] <= 0.0
		and not _player_is_dead()
	)


func request_activate(skill_index: int) -> bool:
	# This is the only method HUD/input should call. Once a real MultiplayerPeer
	# exists, clients stop here and ask the networking layer to forward the
	# request. No local prediction is performed, so this never masquerades as
	# synchronized multiplayer.
	if is_inside_tree():
		var multiplayer_api := get_multiplayer()
		if multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server():
			remote_activation_requested.emit(skill_index)
			return false
	return activate_authoritative(skill_index)


func activate_authoritative(skill_index: int) -> bool:
	# A future host RPC handler calls this after validating the requesting peer.
	# Availability and cooldown are revalidated here on the authoritative side.
	if not is_skill_ready(skill_index):
		return false
	active_left[skill_index] = DURATIONS[skill_index]
	cooldown_left[skill_index] = COOLDOWNS[skill_index]
	_dead_cancelled = false
	_create_active_aura(skill_index)
	_execute_activation(skill_index)
	skill_activated.emit(skill_index, SKILL_KEYS[skill_index])
	skill_state_changed.emit(skill_index)
	return true


func advance_simulation(delta: float) -> void:
	if delta <= 0.0:
		return
	if _player_is_dead():
		if not _dead_cancelled:
			# Tracking changes an enemy's authored movement speed. Always restore
			# it when the owning player dies instead of leaking the slow forever.
			_clear_runtime_effects(true)
			_dead_cancelled = true
		return
	_dead_cancelled = false

	for skill_index in range(SKILL_KEYS.size()):
		var was_active := active_left[skill_index] > 0.0
		var was_cooling_down := cooldown_left[skill_index] > 0.0
		active_left[skill_index] = maxf(0.0, active_left[skill_index] - delta)
		cooldown_left[skill_index] = maxf(0.0, cooldown_left[skill_index] - delta)
		if was_active and active_left[skill_index] <= 0.0:
			_remove_active_aura(skill_index)
			skill_state_changed.emit(skill_index)
		elif was_cooling_down and cooldown_left[skill_index] <= 0.0:
			skill_state_changed.emit(skill_index)

	_update_attack_shield(delta)
	_update_waves(delta)
	_update_tracking_marks(delta)
	_update_gravity_force(delta)


func get_speed_bonus() -> float:
	var bonus := 0.0
	if is_skill_active(0):
		bonus += 2.0
	if is_skill_active(1):
		bonus += 2.0
	if is_skill_active(3):
		bonus += 1.0
	return bonus


func modify_outgoing_damage(amount: float) -> float:
	var result := amount
	if is_skill_active(0):
		result *= 1.5
	if is_skill_active(4):
		result *= 0.65
	return maxf(0.0, result)


func modify_incoming_damage(amount: float) -> float:
	var result := amount
	if is_skill_active(2):
		result *= 0.15
	if is_skill_active(3):
		result *= 0.7
	if is_skill_active(8):
		result *= -0.6
	return result


func on_damage_dealt(actual_damage: float) -> void:
	if actual_damage > 0.0 and is_skill_active(4):
		_heal_player(actual_damage)


func cancel_all_active(reset_cooldowns := false) -> void:
	for skill_index in range(SKILL_KEYS.size()):
		_cancel_skill(skill_index, reset_cooldowns)
	_clear_runtime_effects(true)


func _execute_activation(skill_index: int) -> void:
	match skill_index:
		3:
			_heal_player(ANDROMEDA_HEAL)
		5:
			_attack_shield_tick_left = ATTACK_SHIELD_INTERVAL
		6:
			_spawn_wave("impact", 10.0, 3.0, IMPACT_WAVE_DAMAGE, 8.0, true)
		7:
			_spawn_wave("track", 20.0, 3.0, TRACK_WAVE_DAMAGE, 8.0, false)
		9:
			_begin_gravity_force()
	if skill_index in [6, 7] and is_instance_valid(controlled_player):
		AudioDirector.play_3d("light_sword/windblade.wav", controlled_player.global_position, -5.0)


func _cancel_skill(skill_index: int, reset_cooldown: bool) -> void:
	if not _is_valid_skill_index(skill_index):
		return
	active_left[skill_index] = 0.0
	if reset_cooldown:
		cooldown_left[skill_index] = 0.0
	_remove_active_aura(skill_index)


func _clear_runtime_effects(restore_tracking_speed: bool) -> void:
	for skill_index in _active_auras.keys():
		_remove_active_aura(int(skill_index))
	for wave in _waves:
		var visual: Node3D = wave.get("visual") as Node3D
		if is_instance_valid(visual):
			visual.queue_free()
	_waves.clear()
	_clear_gravity_force()
	for target_id in _tracked_targets.keys():
		_remove_tracking_mark(int(target_id), restore_tracking_speed)
	_attack_shield_tick_left = 0.0


func _update_attack_shield(delta: float) -> void:
	if not is_skill_active(5):
		return
	_attack_shield_tick_left -= delta
	while _attack_shield_tick_left <= 0.0:
		_attack_shield_tick_left += ATTACK_SHIELD_INTERVAL
		_damage_enemies_in_radius(controlled_player.global_position, ATTACK_SHIELD_RADIUS, ATTACK_SHIELD_DAMAGE)


func _damage_enemies_in_radius(center: Vector3, radius: float, base_damage: float) -> void:
	var space := _direct_space_state()
	if space == null:
		return
	var shape := SphereShape3D.new()
	shape.radius = radius
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = shape
	parameters.transform = Transform3D(Basis.IDENTITY, center)
	parameters.collision_mask = 2
	var damaged_ids: Dictionary = {}
	for hit in space.intersect_shape(parameters, 64):
		var enemy := _enemy_root(hit.get("collider") as Node)
		if not is_instance_valid(enemy) or damaged_ids.has(enemy.get_instance_id()):
			continue
		damaged_ids[enemy.get_instance_id()] = true
		_deal_enemy_damage(enemy, base_damage, "attack_shield")


func _spawn_wave(kind: String, speed: float, radius: float, damage: float, lifetime: float, penetrating: bool) -> void:
	if not is_instance_valid(controlled_player):
		return
	var world_parent := combat_world
	if not is_instance_valid(world_parent):
		world_parent = controlled_player.get_parent() as Node3D
	if not is_instance_valid(world_parent):
		return
	var aim := _aim_solution(1000.0)
	var origin := controlled_player.global_position + Vector3.UP + Vector3(0.0, 0.0, -0.5).rotated(Vector3.UP, controlled_player.rotation.y)
	var fallback_direction := -controlled_player.global_transform.basis.z
	var target_position := Vector3(aim.get("target", origin + fallback_direction * 1000.0))
	var direction := (target_position - origin).normalized()
	if direction.length_squared() <= 0.0001:
		direction = fallback_direction.normalized()

	var visual := Node3D.new()
	visual.name = "ArmorPower%sWave" % kind.capitalize()
	world_parent.add_child(visual)
	visual.global_position = origin
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.42 if kind == "impact" else 0.28
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = _effect_material(SKILL_COLORS[6 if kind == "impact" else 7], 0.78)
	orb.mesh = mesh
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(orb)
	_waves.append({
		"kind": kind, "visual": visual, "direction": direction, "speed": speed,
		"radius": radius, "damage": damage, "left": lifetime,
		"penetrating": penetrating, "hit_ids": {}
	})


func _update_waves(delta: float) -> void:
	for wave_index in range(_waves.size() - 1, -1, -1):
		var wave: Dictionary = _waves[wave_index]
		var visual: Node3D = wave.get("visual") as Node3D
		if not is_instance_valid(visual):
			_waves.remove_at(wave_index)
			continue
		wave.left = float(wave.left) - delta
		visual.global_position += Vector3(wave.direction) * float(wave.speed) * delta
		var consumed := _hit_wave_targets(wave)
		if float(wave.left) <= 0.0 or consumed:
			visual.queue_free()
			_waves.remove_at(wave_index)


func _hit_wave_targets(wave: Dictionary) -> bool:
	var space := _direct_space_state()
	var visual: Node3D = wave.get("visual") as Node3D
	if space == null or not is_instance_valid(visual):
		return false
	var shape := SphereShape3D.new()
	shape.radius = float(wave.radius)
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = shape
	parameters.transform = Transform3D(Basis.IDENTITY, visual.global_position)
	parameters.collision_mask = 2
	var hit_ids: Dictionary = wave.hit_ids
	for hit in space.intersect_shape(parameters, 64):
		var enemy := _enemy_root(hit.get("collider") as Node)
		if not is_instance_valid(enemy):
			continue
		var target_id := enemy.get_instance_id()
		if hit_ids.has(target_id):
			continue
		hit_ids[target_id] = true
		var dealt := _deal_enemy_damage(enemy, float(wave.damage), str(wave.kind))
		if str(wave.kind) == "impact" and not is_skill_active(4):
			_heal_player(dealt * 0.5)
		elif str(wave.kind) == "track":
			_apply_tracking_mark(enemy)
		if not bool(wave.penetrating):
			return true
	return false


func _deal_enemy_damage(enemy: Node3D, base_damage: float, _damage_kind: String) -> float:
	if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
		return 0.0
	var before_value: Variant = enemy.get("health")
	var before := float(before_value) if typeof(before_value) in [TYPE_INT, TYPE_FLOAT] else -1.0
	var adjusted_damage := modify_outgoing_damage(base_damage)
	enemy.take_damage(adjusted_damage, enemy.global_position, controlled_player)
	var after_value: Variant = enemy.get("health")
	if before >= 0.0 and typeof(after_value) in [TYPE_INT, TYPE_FLOAT]:
		return maxf(0.0, before - float(after_value))
	return adjusted_damage


func _apply_tracking_mark(enemy: Node3D) -> void:
	var target_id := enemy.get_instance_id()
	if _tracked_targets.has(target_id):
		_tracked_targets[target_id].left = TRACK_MARK_DURATION
		return
	var speed_value: Variant = enemy.get("speed")
	if not typeof(speed_value) in [TYPE_INT, TYPE_FLOAT]:
		return
	var marker := _create_orb_visual(SKILL_COLORS[7], 0.34, 0.38)
	enemy.add_child(marker)
	marker.position = Vector3.UP * 2.0
	_tracked_targets[target_id] = {
		"target": enemy, "original_speed": float(speed_value),
		"left": TRACK_MARK_DURATION, "marker": marker
	}
	enemy.set("speed", float(speed_value) * 0.7)


func _update_tracking_marks(delta: float) -> void:
	for target_id_value in _tracked_targets.keys():
		var target_id := int(target_id_value)
		var record: Dictionary = _tracked_targets[target_id]
		var target: Node3D = record.get("target") as Node3D
		if not is_instance_valid(target):
			_remove_tracking_mark(target_id, false)
			continue
		record.left = float(record.left) - delta
		if float(record.left) <= 0.0:
			_remove_tracking_mark(target_id, true)


func _remove_tracking_mark(target_id: int, restore_speed: bool) -> void:
	if not _tracked_targets.has(target_id):
		return
	var record: Dictionary = _tracked_targets[target_id]
	var target: Node3D = record.get("target") as Node3D
	if restore_speed and is_instance_valid(target):
		target.set("speed", float(record.original_speed))
	var marker: Node3D = record.get("marker") as Node3D
	if is_instance_valid(marker):
		marker.queue_free()
	_tracked_targets.erase(target_id)


func _begin_gravity_force() -> void:
	var aim := _aim_solution(180.0)
	_gravity_target = _enemy_root(aim.get("collider") as Node)
	_gravity_left = GRAVITY_FORCE_DURATION if is_instance_valid(_gravity_target) else 0.0
	if not is_instance_valid(_gravity_target):
		return
	_gravity_marker = _create_orb_visual(SKILL_COLORS[9], 0.48, 0.55)
	_gravity_target.add_child(_gravity_marker)
	_gravity_marker.position = Vector3.UP * 1.25


func _update_gravity_force(delta: float) -> void:
	if _gravity_left <= 0.0:
		return
	_gravity_left = maxf(0.0, _gravity_left - delta)
	if not is_instance_valid(_gravity_target) or bool(_gravity_target.get("dead")):
		_clear_gravity_force()
		return
	var offset := controlled_player.global_position - _gravity_target.global_position
	if offset.length_squared() > 4.0:
		_gravity_target.global_position += offset.normalized() * minf(GRAVITY_FORCE_SPEED * delta, maxf(0.0, offset.length() - 2.0))
	if _gravity_left <= 0.0:
		_clear_gravity_force()


func _clear_gravity_force() -> void:
	_gravity_left = 0.0
	_gravity_target = null
	if is_instance_valid(_gravity_marker):
		_gravity_marker.queue_free()
	_gravity_marker = null


func _create_active_aura(skill_index: int) -> void:
	if skill_index in [6, 7, 9] or not is_instance_valid(controlled_player):
		return
	_remove_active_aura(skill_index)
	var aura := _create_orb_visual(SKILL_COLORS[skill_index], 0.78 if skill_index != 5 else 1.05, 0.17)
	aura.name = "ArmorPowerAura_%d" % skill_index
	aura.position = Vector3.UP * 1.0
	add_child(aura)
	_active_auras[skill_index] = aura


func _remove_active_aura(skill_index: int) -> void:
	var aura: Node3D = _active_auras.get(skill_index) as Node3D
	if is_instance_valid(aura):
		aura.queue_free()
	_active_auras.erase(skill_index)


func _create_orb_visual(color: Color, radius: float, alpha: float) -> Node3D:
	var root := Node3D.new()
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = _effect_material(color, alpha)
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	return root


func _effect_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	return material


func _aim_solution(maximum_range: float) -> Dictionary:
	if is_instance_valid(controlled_player) and controlled_player.has_method("get_aim_solution"):
		var solution: Variant = controlled_player.get_aim_solution(maximum_range)
		return solution if solution is Dictionary else {}
	return {}


func _direct_space_state() -> PhysicsDirectSpaceState3D:
	if not is_instance_valid(controlled_player) or not controlled_player.is_inside_tree():
		return null
	return controlled_player.get_world_3d().direct_space_state


func _enemy_root(candidate: Node) -> Node3D:
	var current := candidate
	while is_instance_valid(current):
		if current is Node3D and current.is_in_group("enemies"):
			return current as Node3D
		current = current.get_parent()
	return null


func _heal_player(amount: float) -> float:
	if amount <= 0.0 or not is_instance_valid(controlled_player):
		return 0.0
	if controlled_player.has_method("heal_from_armor_power"):
		return float(controlled_player.heal_from_armor_power(amount))
	var health_value: Variant = controlled_player.get("health")
	var max_health_value: Variant = controlled_player.get("max_health")
	if not typeof(health_value) in [TYPE_INT, TYPE_FLOAT] or not typeof(max_health_value) in [TYPE_INT, TYPE_FLOAT]:
		return 0.0
	var before := float(health_value)
	controlled_player.set("health", minf(float(max_health_value), before + amount))
	return float(controlled_player.get("health")) - before


func _player_is_dead() -> bool:
	return not is_instance_valid(controlled_player) or bool(controlled_player.get("dead"))


func _is_valid_skill_index(skill_index: int) -> bool:
	return skill_index >= 0 and skill_index < SKILL_KEYS.size()
