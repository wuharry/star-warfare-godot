extends "res://scripts/game/enemy.gd"

var network_id := 0
var last_attacker := 0
var target_position := Vector3.ZERO
var target_yaw := 0.0
var network_animation := ""

func apply_coop_scaling(player_count: int) -> void:
	# Enemy.LoadConfig: these multiply the authored/difficulty-adjusted values.
	var count := clampi(player_count, 1, 3) - 1
	if is_boss_enemy():
		# EnemyBoss.Init calls loadParameters AFTER Enemy.Init/LoadConfig: boss
		# HP and attack values overwrite the generic coop multipliers. Cash does
		# retain LoadConfig's player-count multiplier, without the solo discount.
		reward = int(float(MonsterCatalog.get_monster(source_monster_id).credits) * [1.0, 1.2, 1.5][count])
		return
	max_health = float(int(max_health * [1.0, 1.6, 2.0][count]))
	health = max_health
	var damage_scale: float = [1.0, 1.2, 1.5][count]
	attack_damage = float(int(attack_damage * damage_scale))
	if original_runtime:
		source_spec.hp = max_health
		source_spec.damage = attack_damage
		for attack: Dictionary in source_spec.get("attack_profiles", []):
			attack.damage = int(float(attack.damage) * damage_scale)
		reward = int(float(reward) * [1.0, 1.5, 1.8][count])
		experience_value = int(float(experience_value) * [1.0, 1.5, 1.8][count])
		source_brain.configure(source_spec)

func _physics_process(delta: float) -> void:
	if NetworkSession.phase != "playing":
		return
	if NetworkSession.is_host():
		target = get_parent().nearest_player(global_position)
		super._physics_process(delta)
	else:
		var movement := position.distance_to(target_position)
		position = position.lerp(target_position, minf(1.0, delta * 18.0))
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(1.0, delta * 18.0))
		spawn_left = maxf(0.0, spawn_left - delta)
		if not network_animation.is_empty():
			_play_recovered_animation(network_animation)
		else:
			_update_animation(delta, movement / maxf(delta, 0.001))

func take_damage(amount: float, hit_position := Vector3.ZERO, source: Node = null) -> void:
	if not NetworkSession.is_host() or NetworkSession.phase != "playing" or get_parent().rules.ended or dead:
		return
	last_attacker = int(source.peer_id) if source != null and "peer_id" in source else 0
	super.take_damage(amount, hit_position, source)

func _ranged_attack() -> void:
	attack_cooldown = attack_interval
	_play_recovered_animation("attack", 0.04)
	if is_instance_valid(target):
		var origin := global_position + Vector3.UP * 1.15
		get_parent().launch_projectile(self, origin, (_predicted_aim_point(projectile_speed) - origin).normalized(),
			projectile_speed, attack_damage, projectile_splash, "plasma")

func _boss_attack(distance: float) -> void:
	if distance > 3.0:
		attack_cooldown = attack_interval * 1.8
		var origin := global_position + Vector3.UP * 2.5
		for angle: float in [-0.22, 0.0, 0.22]:
			get_parent().launch_projectile(self, origin, (_predicted_aim_point(18.0) - origin).normalized().rotated(Vector3.UP, angle),
				18.0, attack_damage * 0.72, 1.6, "plasma")
	else:
		charge_timer = 0.72
		_melee_attack()

func network_state() -> Dictionary:
	var beam := {"active": is_instance_valid(source_beam) and source_beam.visible}
	if beam.active:
		beam.transform = source_beam.transform
		beam.radius = source_beam.mesh.top_radius
		beam.reach = source_beam.mesh.height
		beam.tint = source_beam.mesh.material.albedo_color
	return {"kind": enemy_kind, "position": position, "yaw": model.rotation.y, "rotation": rotation,
		"health": health, "maximum": max_health, "dead": dead, "original": original_runtime,
		"source_id": source_monster_id, "animation": recovered_animation_name,
		"model_position": model.position, "hidden": not model.visible, "beam": beam,
		"flame": is_instance_valid(source_flame) and source_flame.visible}

func apply_network_state(state: Dictionary) -> void:
	target_position = state.position
	target_yaw = state.yaw
	rotation = state.get("rotation", Vector3.ZERO)
	model.position = state.get("model_position", Vector3.ZERO)
	source_set_hidden(bool(state.get("hidden", false)))
	source_set_flame(bool(state.get("flame", false)))
	var beam: Dictionary = state.get("beam", {})
	if bool(beam.get("active", false)):
		source_set_beam(true, Vector3.FORWARD, float(beam.reach), beam.tint, float(beam.radius))
		source_beam.transform = beam.transform
	else: source_set_beam(false)
	network_animation = str(state.get("animation", ""))
	health = state.health
	max_health = state.maximum
	if bool(state.dead) and not dead:
		super._die()

func _source_projectile(origin: Vector3, travel: Vector3, gravity_value: float, direct: float, splash: float, radius: float, through_walls: bool) -> void:
	source_emit_projectile({"position": origin, "travel_velocity": travel, "gravity_strength": gravity_value,
		"direct_damage": direct, "area_damage": splash, "area_radius": radius, "ignore_blast_walls": through_walls,
		"tint": Color(1.0, 0.25, 0.03) if source_monster_id == 10 else Color(0.5, 0.85, 0.15)})

func source_telegraph(at: Vector3, radius: float, lifetime: float) -> void:
	super.source_telegraph(at, radius, lifetime)
	if NetworkSession.is_host():
		NetworkSession.broadcast_effect({"type": "telegraph", "enemy": network_id, "position": at, "radius": radius, "lifetime": lifetime})

func source_explode(damage: float, radius: float) -> void:
	if dead:
		return
	get_parent().apply_explosion(self, global_position, damage, radius)
	get_parent().network_explosion(global_position, radius)
	health = 0.0
	_die()
