extends RefCounted

# Dragon.cs and its *State.cs classes, single-player branch. Clip names and
# event fractions are the recovered AnimationString bindings. Collision cones
# replace Unity's prefab bone colliders (declared as a presentation/geometry
# gap in the catalog), but damage, timings, volleys and phase rules are sourced.
const CLIPS := {
	"init": "idle", "intro": "rage", "ground_idle": "idle", "chase": "run",
	"bite": "attack", "pounce": "pu", "ground_shot": "attack", "flame": "flame",
	"takeoff": "up", "fly_idle": "fly_idle", "fly_chase": "fly_walk",
	"fly_shot": "fly_attack", "fly_flame": "fly_attack01", "dive": "fly_Sprint",
	"rush_start": "up", "rush": "fly_Sprint02", "rush_end": "fly_Sprint_down",
	"landing": "down", "rage": "rage", "stagger": "attacked", "fly_stagger": "fly_attacked",
}
const FLAME_WINDOWS := [
	[0.45, 0.57, -45.0, -10.0, 10.0], [0.57, 0.73, -40.0, -5.0, 14.0],
	[0.73, 0.82, -50.0, 5.0, 18.0], [0.82, 0.89, -20.0, 60.0, 18.0],
	[0.89, 0.93, 0.0, 65.0, 18.0],
]
var state := "init"
var elapsed := 0.0
var phase_elapsed := 0.0
var duration := 1.0
var airborne := false
var vertical_control := false
var enraged := false
var rage_pending := false
var next_hit_fraction := 0.15
var fire_cooldown := 0.0
var touch_cooldown := 0.0
var fired := false
var volleys := 0
var locked_direction := Vector3.FORWARD
var rush_target := Vector3.ZERO
var dive_target := Vector3.ZERO
var pounce_speed := 0.0
var ground_y := 0.0
var arena_center := Vector3(-10.0, 0.0, 2.5) # Unity +Z converted to Godot -Z.
var arena_radius := 17.0
var rng := RandomNumberGenerator.new()


func configure(_spec: Dictionary) -> void:
	rng.randomize()


func animation_name() -> String:
	return str(CLIPS.get(state, "idle"))


func on_damage(actor: Node3D) -> void:
	if actor.health <= 0.0:
		return
	var loss: float = 1.0 - actor.health / actor.max_health
	# Source increments once per hit, not once per frame or pellet cooldown.
	if loss > next_hit_fraction:
		next_hit_fraction += 0.15
		rage_pending = not enraged and loss > 0.60
		start_action(actor, "fly_stagger" if airborne else "stagger")


func start_action(actor: Node3D, action: String) -> void:
	state = action
	elapsed = 0.0
	fired = false
	duration = actor.source_clip_length(animation_name(), 1.0)
	actor._play_recovered_animation(animation_name(), 0.08, true)
	actor.source_set_flame(false)
	if action in ["ground_shot", "fly_shot", "pounce", "bite", "flame", "rush_start"]:
		actor._face_planar_direction(actor.source_target_direction())
	if action == "pounce":
		pounce_speed = actor.source_planar_distance()
	if action == "takeoff":
		airborne = true
		phase_elapsed = 0.0
	if action in ["dive", "rush"]:
		if action == "dive" or rush_target == Vector3.ZERO:
			_lock_rush(actor)
		locked_direction = (dive_target - actor.global_position).normalized() if action == "dive" else (rush_target - actor.global_position).normalized()
		actor._face_planar_direction(locked_direction)
	if action == "rush_start":
		rush_target = Vector3.ZERO
	if action in ["intro", "rage"]:
		actor.source_sound("enemy/dragon/long_housheng_1.wav")
	elif action in ["dive", "rush"]:
		actor.source_sound("enemy/dragon/long_fly_dive.wav")
	elif action in ["landing", "rush_end", "bite"]:
		actor.source_sound("enemy/dragon/long_luodi.wav")


func step(actor: Node3D, delta: float, distance: float, planar: Vector3, sight: bool) -> Vector3:
	elapsed += delta
	phase_elapsed += delta
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	touch_cooldown = maxf(0.0, touch_cooldown - delta)
	ground_y = actor.source_floor_height()
	vertical_control = airborne or state in ["rush_start", "rush", "dive", "landing"]
	var movement := Vector3.ZERO
	var progress := elapsed / maxf(duration, 0.01)
	if state not in ["init", "intro", "stagger", "fly_stagger", "rage"] and touch_cooldown <= 0.0:
		if actor.global_position.distance_to(actor.target.global_position) < 2.0:
			actor.source_damage_target(700.0, 0.08)
			touch_cooldown = 2.0
	match state:
		"init":
			if elapsed >= 2.0: start_action(actor, "intro")
		"intro":
			if progress >= 1.0: start_action(actor, "takeoff")
		"takeoff":
			if progress >= 0.37:
				movement.y = minf(10.0, maxf(0.0, (ground_y + 5.0 - actor.global_position.y) / maxf(delta, 0.001)))
				actor._face_planar_direction(actor.source_target_direction())
			if progress >= 1.0: start_action(actor, "fly_idle")
		"ground_idle", "fly_idle":
			if state == "fly_idle":
				movement.y = clampf((ground_y + 5.0 - actor.global_position.y) / maxf(delta, 0.001), -10.0, 10.0)
				actor._face_planar_direction(actor.source_target_direction())
			if phase_elapsed >= (20.0 if airborne else 12.0):
				start_action(actor, "landing" if airborne else "takeoff")
			elif elapsed >= (0.36 if enraged else 0.9):
				_choose_action(actor, distance, sight)
		"chase", "fly_chase":
			actor._face_planar_direction(planar)
			movement = planar.normalized() * (14.0 if airborne else 12.0)
			if airborne: movement.y = clampf(ground_y + 5.0 - actor.global_position.y, -10.0, 10.0)
			if elapsed > (4.4 if enraged else 5.0):
				_idle(actor)
			elif distance < 10.0 and sight:
				_choose_near_action(actor)
		"ground_shot", "fly_shot":
			if airborne: actor._face_planar_direction(actor.source_target_direction())
			if not fired and progress >= (0.6 if airborne else 0.52):
				fired = true
				actor.source_dragon_shot(airborne)
			if progress >= 1.0:
				volleys += 1
				if volleys < ((3 if airborne else 2) if enraged else 1):
					start_action(actor, state)
				else:
					volleys = 0
					_idle(actor)
		"flame", "fly_flame":
			var active := progress >= (0.3 if airborne else 0.4) and progress <= (0.85 if airborne else 0.86)
			actor.source_set_flame(active)
			if active and fire_cooldown <= 0.0 and _flame_hits(actor, progress, distance):
				actor.source_damage_target(3500.0)
				fire_cooldown = 1.0
			if airborne and not active: actor._face_planar_direction(actor.source_target_direction())
			if progress >= 1.0: _idle(actor)
		"bite":
			if progress >= 0.36 and progress < 0.47:
				movement = actor.source_forward() * minf(distance * 3.0, 20.0)
			if progress >= 0.36 and progress <= 0.6: _contact_attack(actor, 3500.0, 6.0)
			if progress >= 1.0: _idle(actor)
		"pounce":
			actor._face_planar_direction(actor.source_target_direction())
			if progress >= 0.11:
				if progress >= 0.41: pounce_speed = maxf(0.0, pounce_speed - pounce_speed * delta * 2.0)
				movement = actor.source_forward() * pounce_speed
				_contact_attack(actor, 5200.0, 6.0)
			if progress >= 1.0: _idle(actor)
		"rush_start":
			actor._face_planar_direction(actor.source_target_direction())
			if progress >= 1.0: start_action(actor, "rush")
		"dive":
			movement = locked_direction * 32.0
			_contact_attack(actor, 4200.0, 8.2)
			if actor.global_position.y <= ground_y + 0.5:
				start_action(actor, "rush")
		"rush":
			movement = locked_direction * 32.0
			_contact_attack(actor, 4200.0, 8.2)
			var remaining := rush_target - actor.global_position
			# End when we reach/pass the locked target or strike a wall. A distant
			# dodging player must not keep the rush alive forever.
			if remaining.length() < 6.0 or remaining.dot(locked_direction) <= 0.0 or actor.is_on_wall() or elapsed > 5.0:
				start_action(actor, "takeoff" if airborne else "rush_end")
				movement = Vector3.ZERO
		"rush_end", "landing":
			movement.y = maxf(-15.0, minf(0.0, (ground_y - actor.global_position.y) / maxf(delta, 0.001)))
			if progress >= 1.0 and actor.global_position.y <= ground_y + 0.5:
				airborne = false
				phase_elapsed = 0.0
				if rage_pending:
					_begin_rage(actor)
				else: _idle(actor)
		"stagger", "fly_stagger":
			if progress >= 1.0:
				if rage_pending:
					if airborne: start_action(actor, "landing")
					else: _begin_rage(actor)
				else: _idle(actor)
		"rage":
			if progress >= 1.0:
				phase_elapsed = 0.0
				_idle(actor)
	return movement


func _choose_action(actor: Node3D, distance: float, sight: bool) -> void:
	if not sight:
		start_action(actor, "fly_chase" if airborne else "chase")
	elif distance < 10.0:
		_choose_near_action(actor)
	elif distance >= 27.0:
		start_action(actor, "dive" if airborne else "rush_start")
	elif airborne:
		start_action(actor, "fly_chase" if rng.randi_range(0, 99) < (30 if enraged else 40) else "fly_shot")
	else:
		var roll := rng.randi_range(0, 99)
		if roll < 15: start_action(actor, "chase")
		elif roll < 45: start_action(actor, "pounce")
		elif roll < (60 if enraged else 65): start_action(actor, "flame")
		else: start_action(actor, "ground_shot")


func _choose_near_action(actor: Node3D) -> void:
	var roll := rng.randi_range(0, 99)
	if airborne:
		start_action(actor, "fly_flame" if roll < (50 if enraged else 70) else "fly_shot")
	else:
		start_action(actor, "bite" if roll < (50 if enraged else 70) else "flame")


func _flame_hits(actor: Node3D, progress: float, distance: float) -> bool:
	if airborne:
		return actor.source_target_in_cone(18.0, 25.0)
	var angle: float = actor.source_target_angle()
	for window: Array in FLAME_WINDOWS:
		if progress > float(window[0]) and progress < float(window[1]) and angle > float(window[2]) and angle < float(window[3]) and distance < float(window[4]):
			return true
	return false


func _contact_attack(actor: Node3D, damage: float, reach: float) -> void:
	if fire_cooldown <= 0.0 and actor.source_target_in_cone(reach, 35.0):
		actor.source_damage_target(damage, 0.16 if state == "bite" else (0.2 if state == "pounce" else 0.22))
		fire_cooldown = 1.0


func _lock_rush(actor: Node3D) -> void:
	rush_target = actor.target.global_position
	var direction: Vector3 = actor.source_target_direction()
	var offset := rush_target - arena_center
	offset.y = 0.0
	if offset.length() < arena_radius:
		rush_target += direction * minf(10.0, (arena_radius - offset.length()) * 0.5)
	rush_target.y = ground_y
	dive_target = actor.global_position.lerp(rush_target, 0.5)
	dive_target.y = ground_y


func _begin_rage(actor: Node3D) -> void:
	enraged = true
	rage_pending = false
	start_action(actor, "rage")


func _idle(actor: Node3D) -> void:
	start_action(actor, "fly_idle" if airborne else "ground_idle")
