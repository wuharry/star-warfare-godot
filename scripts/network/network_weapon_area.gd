extends "res://scripts/game/original_weapon_area.gd"
## Original rain/slime cadence, with host ownership and multiplayer targets.
var kind := "rain"
var damage_category := "grenade_defence"

func _ready() -> void:
	if kind == "slime":
		var effect := {"type": "weapon_area", "position": position, "kind": kind}
		get_parent()._play_effect(effect)
		NetworkSession.broadcast_effect(effect)

func _physics_process(delta: float) -> void:
	if not NetworkSession.is_host() or NetworkSession.phase != "playing": return
	if not is_instance_valid(source) or get_parent().rules.ended:
		queue_free()
		return
	delay -= delta
	if delay > 0.0: return
	delay += interval
	var world := get_parent()
	var targets: Array[Node3D] = []
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 6
	# Slime's prefab sphere is centered 0.8 above the floor. Rain uses four
	# source spheres at 0/2/4/6, plus explicit planar player/boss coverage.
	for elevation: float in ([0.8] if kind == "slime" else [0.0, 2.0, 4.0, 6.0]):
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * elevation)
		for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 512):
			var target: Node3D = EnemyHitGeometry.resolve(hit.collider) as Node3D
			if is_instance_valid(target) and not targets.has(target): targets.append(target)
	if kind == "rain":
		for target: Node3D in world.actors.values() + world.enemies.values():
			if "peer_id" in target or (target.has_method("is_boss_enemy") and target.is_boss_enemy()):
				var offset := target.global_position - global_position
				if Vector2(offset.x, offset.z).length() < radius and not targets.has(target): targets.append(target)
	for target: Node3D in targets:
		if not world.can_damage_target(source, target): continue
		if kind == "slime" and "armor_skills" in target and float(target.armor_skills.get("fly", 0.0)) > 0.0: continue
		if kind == "rain" and "peer_id" in target and Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length() >= radius: continue
		var ray_from := global_position + Vector3.UP * (8.0 if kind == "rain" and "peer_id" in target else 0.1)
		if kind == "slime" or world.has_line_of_sight(ray_from, target.global_position + Vector3.UP):
			world.damage_target(source, target, damage, target.global_position + Vector3.UP, damage_category)
	ticks_left -= 1
	if ticks_left <= 0: queue_free()
