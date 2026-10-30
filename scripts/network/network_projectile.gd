extends "res://scripts/game/projectile.gd"
## Reuse recovered configuration, visuals and UFO movement. Host collision and
## team filtering are adapted here; replicas never run damage or target search.
const Area = preload("res://scripts/network/network_weapon_area.gd")
var network_id := 0
var visual_target := Vector3.ZERO
var detonated := false
var age := 0.0
var tracking_position := Vector3.ZERO
var tracking_sample_time := -0.5
var robot_target := Vector3.ZERO
var robot_tracking := false
var weapon_level := 1
var search_radius := 30.0
var search_time := 0.0
var damage_category := ""
var source: Node:
	get: return owner_node
	set(value): owner_node = value
var kind: String:
	get: return projectile_kind
	set(value): projectile_kind = value

func configure_network(actor: Node, travel: Vector3, travel_speed: float, amount: float, radius: float, shot_kind: String, weapon: Dictionary = {}, variant := 0) -> void:
	var is_enemy := not "peer_id" in actor
	super.configure(actor, travel, travel_speed, amount, radius, weapon.get("color", Color.ORANGE), is_enemy, shot_kind, str(weapon.get("explosion_sound", "")), str(weapon.get("key", "")))
	joke_variant = variant
	search_radius = float(weapon.get("range", 30.0))
	if not is_enemy:
		var damage_kind := "sword" if shot_kind == "windblade" else ("tracking" if shot_kind == "spring" else shot_kind)
		damage_category = actor.network_damage_category_for_kind(damage_kind)
		weapon_level = int(actor.profile.get("weapon_levels", {}).get(visual_variant, 1))
		lifetime = 3.0 if kind == "fly_grenade" else (5.0 if kind in ["tracking", "spring"] else 8.0)
		if bool(weapon.get("pvp", false)):
			if kind == "rocket": speed *= 2.0 # VSMath.RPG_FLY_BOOTH
			if kind == "grenade": grenade_velocity *= 1.5 # GL_FLY_BOOTH

func _ready() -> void:
	super._ready()
	if not NetworkSession.is_host() or hostile: return
	if kind == "tracking":
		homing_target = _nearest_aim_target()
	elif kind in ["energy_fist", "spring"] or visual_variant == "gun44":
		var aimed: Node = EnemyHitGeometry.resolve(owner_node.get_aim_solution().get("collider"))
		homing_target = aimed if get_parent().can_damage_target(source, aimed) else null
	else:
		homing_target = null

func _build_legacy_hd_visual() -> bool:
	if not OriginalWeaponEffect.catalog().has(visual_variant): return super._build_legacy_hd_visual()
	var path := "Effect/TrackingGrenadeShot" if visual_variant == "gun41" and joke_variant > 0 else str(OriginalWeaponEffect.catalog()[visual_variant][0])
	var effect := OriginalWeaponEffect.create(path)
	if effect == null: return false
	if kind == "windblade": effect.rotate_object_local(Vector3.BACK, deg_to_rad(45 if randi() % 2 == 0 else -45))
	visual_root.add_child(effect)
	return true

func _find_nearest_enemy() -> Node3D:
	if not NetworkSession.is_host() or not is_instance_valid(source): return null
	return get_parent().nearest_damage_target(source, global_position)

func _nearest_visible_target(radius: float) -> Node3D:
	var nearest: Node3D
	var distance := radius * radius
	for target: Node3D in get_parent().actors.values() + get_parent().enemies.values():
		if not get_parent().can_damage_target(source, target): continue
		var separation := global_position.distance_squared_to(target.global_position)
		if separation < distance and get_parent().has_line_of_sight(global_position + Vector3.UP * 0.1, target.global_position + Vector3.UP):
			nearest = target
			distance = separation
	return nearest

func _nearest_aim_target() -> Node3D:
	var result: Node3D
	var best := INF
	var camera: Camera3D = source.camera
	var screen_size := camera.get_viewport().get_visible_rect().size
	for target: Node3D in get_parent().actors.values() + get_parent().enemies.values() + get_parent().gifts.values():
		if not get_parent().can_damage_target(source, target): continue
		if camera.is_position_behind(target.global_position): continue
		var screen_point := camera.unproject_position(target.global_position)
		if not Rect2(Vector2.ZERO, screen_size).has_point(screen_point): continue
		var distance := screen_point.distance_squared_to(screen_size * 0.5)
		if distance < best and get_parent().has_line_of_sight(camera.global_position, target.global_position + Vector3.UP):
			result = target
			best = distance
	return result

func _physics_process(delta: float) -> void:
	if NetworkSession.phase != "playing" or detonated: return
	if not NetworkSession.is_host():
		position = position.lerp(visual_target, minf(delta * 22.0, 1.0))
		_update_visual_orientation()
		return
	if not is_instance_valid(source):
		_retire()
		return
	age += delta
	lifetime -= delta
	if wall_fuse >= 0.0:
		wall_fuse -= delta
		if wall_fuse <= 0.0:
			_impact(global_position, null)
			return
	if lifetime <= 0.0:
		if joke_robot: _impact(global_position, null)
		elif kind == "fly_grenade": _impact(global_position + Vector3.DOWN * 8.0, null)
		else: _retire()
		return
	if kind == "fly_grenade":
		search_time -= delta
		if not is_instance_valid(homing_target) and search_time <= 0.0:
			search_time = 0.2
			var floor_query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 100.0, 1)
			var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_query)
			var ground := Vector3(floor_hit.get("position", Vector3.ZERO)).y
			if global_position.y > ground + 7.0:
				homing_target = _nearest_visible_target(search_radius)
		_advance_ufo(delta)
		return
	if joke_robot:
		_advance_robot(delta)
		return
	if is_instance_valid(homing_target):
		speed += 3.0 * delta # ProjectileScript.trackingFlyAcceleration
		if age < 5.1 and get_parent().can_damage_target(source, homing_target):
			if age - tracking_sample_time >= 0.5:
				tracking_sample_time = age
				tracking_position = homing_target.global_position + Vector3.UP
			var desired := (tracking_position - global_position).normalized()
			direction = direction.slerp(desired, clampf((age - tracking_sample_time) / 2.0, 0.0, 1.0)).normalized()
	if gravity_strength > 0.0:
		grenade_velocity += Vector3.DOWN * gravity_strength * delta
		direction = grenade_velocity.normalized()
	visual_spin += visual_spin_speed * delta
	_update_visual_orientation()
	var next_position := global_position + (grenade_velocity if gravity_strength > 0.0 else direction * speed) * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position, 7)
	if source is CollisionObject3D: query.exclude = [source.get_rid()]
	# A penetrating projectile can cross several colliders in one physics tick.
	for _hit_index in 32:
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		var target: Node = EnemyHitGeometry.resolve(hit.collider)
		var actor_hit := is_instance_valid(target) and target.has_method("take_damage")
		if kind == "grenade" and not actor_hit:
			if visual_variant == "gun41" and joke_variant > 0 and Vector3(hit.normal).y > 0.5:
				joke_robot = true
				lifetime = 2.0
				wall_fuse = -1.0
				global_position = hit.position + Vector3.UP * 0.05
				_build_robot_visual()
				return
			if absf(Vector3(hit.normal).y) < 0.5:
				if wall_fuse < 0.0: wall_fuse = 1.2 if get_parent().pvp_arena else 1.5
				grenade_velocity = grenade_velocity.bounce(hit.normal) * 0.3
				global_position = hit.position + hit.normal * 0.05
				return
		if kind in ["windblade", "ricochet"] and actor_hit:
			var id := target.get_instance_id()
			if age - float(pierced.get(id, -1.0)) > 0.3:
				pierced[id] = age
				get_parent().damage_target(source, target, damage, hit.position, damage_category)
			var excluded := query.exclude
			excluded.append(hit.rid)
			query.exclude = excluded
			continue
		if kind in ["ricochet", "spring"] and not actor_hit and direction.angle_to(hit.normal) < deg_to_rad(155.0) and (kind == "ricochet" or bounces_left > 0):
			bounces_left -= 1
			direction = direction.bounce(hit.normal).normalized()
			global_position = hit.position + hit.normal * 0.08
			return
		_impact(hit.position, target)
		return
	global_position = next_position

func _advance_robot(delta: float) -> void:
	if not robot_tracking:
		var target := _nearest_visible_target(8.0)
		if is_instance_valid(target):
			robot_tracking = true
			robot_target = target.global_position
			lifetime = 2.0
	if not robot_tracking: return
	var offset := robot_target - global_position
	offset.y = 0.0
	if offset.length_squared() < 1.0:
		_impact(global_position, null)
		return
	direction = offset.normalized()
	global_position += direction * 10.0 * delta
	_update_visual_orientation()

func _build_robot_visual() -> void:
	for child in visual_root.get_children(): child.queue_free()
	var robot := OriginalWeaponEffect.create("Effect/TrackingRobot")
	if robot != null: visual_root.add_child(robot)

func _impact(at: Vector3, direct_target: Node) -> void:
	if detonated or not NetworkSession.is_host(): return
	detonated = true
	var world := get_parent()
	if is_instance_valid(source):
		if kind == "fly_grenade":
			_spawn_area(at, damage, 0.3, 4, 0.0, 8.0, "rain")
		elif splash_radius > 0.0:
			world.apply_explosion(source, at, damage, 5.0 if kind == "energy_fist" else splash_radius, false, damage_category)
		else:
			world.damage_target(source, direct_target, damage, at, damage_category)
		if visual_variant == "gun41" and joke_variant == 2:
			var poison := float(int(24.0 * weapon_level))
			if world.pvp_arena: poison = float(int(poison / 20.0))
			_spawn_area(at, poison, 0.6, 6, 0.6, 1.0, "slime")
	var effect := {"type": "projectile_impact", "position": at, "weapon": visual_variant, "radius": splash_radius, "tint": tint}
	world._play_effect(effect)
	NetworkSession.broadcast_effect(effect)
	_retire()

func _spawn_area(at: Vector3, amount: float, interval_value: float, ticks: int, initial_delay: float, height_value: float, area_kind: String) -> void:
	var area := Area.new()
	area.source = source
	area.damage = amount
	area.damage_category = damage_category
	area.radius = 3.5 if area_kind == "slime" else splash_radius
	area.interval = interval_value
	area.ticks_left = ticks
	area.delay = initial_delay
	area.height = height_value
	area.kind = area_kind
	area.position = at
	get_parent().add_child(area)

func _retire() -> void:
	get_parent().projectiles.erase(network_id)
	queue_free()

func network_state() -> Dictionary:
	return {"position": position, "direction": direction, "kind": kind, "weapon": visual_variant,
		"tint": tint, "hostile": hostile, "joke_variant": joke_variant, "robot": joke_robot, "spin": visual_spin}

func apply_network_state(state: Dictionary) -> void:
	visual_target = state.position
	direction = state.direction
	visual_spin = float(state.get("spin", 0.0))
	if bool(state.get("robot", false)) and not joke_robot:
		joke_robot = true
		_build_robot_visual()
