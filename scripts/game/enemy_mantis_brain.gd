extends "res://scripts/game/enemy_boss_brain.gd"

# Mantis.cs + MainMantis/AssistMantis/CoopMantis. Partner is weak: each actor
# owns one brain; neither a corpse nor an aborted arena retains the other.
var flying := false
var phase_elapsed := 0.0
var shot_count := 0
var partner: WeakRef
var assist_active := false
var coop_pending := false
var coop_attacks_left := 0
var coop_dive_left := 0
var solo_elapsed := 0.0
var defend_left := 0.0
var partner_dead := false
var joined_combat := false
var beam_yaw := 0.0
var beam_left := 0.0
var rush_direction := Vector3.ZERO
var rush_target := Vector3.ZERO
# Scenes/Level6.unity: BossAssistTarget objects, Unity Z reflected for Godot.
const COOP_POINTS := [Vector3(2, 0.1, -5), Vector3(12, 0.1, -3),
	Vector3(-13, 0.1, -16), Vector3(23, 0.1, -16), Vector3(-13, 0.1, 10), Vector3(23, 0.1, 10)]
var coop_point := 0
var current_point := 0
var beam_base_direction := Vector3.FORWARD


func configure(data: Dictionary) -> void:
	super.configure(data)
	clips = {"init": "idle" if monster_id == 9 else ("attack02" if monster_id == 11 else "attack"), "idle": "idle",
		"chase": "run", "slash": "attack", "critical": "attack02", "takeoff": "up",
		"landing": "down", "fly_idle": "fly_idle", "fly_chase": "fly_walk",
		"fly_slash": "fly_attack01", "shot": "fly_attack01", "laser": "fly_attack02",
		"boomerang": "fly_attack03", "dive_start": "fuchong01", "dive": "fuchong02",
		"dive_end": "fuchong03", "stagger": "attacked", "fly_stagger": "fly_attacked",
		"rage": "rage", "watch": "idle02", "assist_idle": "idle",
		"assist_shot": "stand_attack01", "assist_laser": "stand_laser",
		"coop_join": "up", "coop_idle": "fly_idle", "coop_laser": "fly_attack180",
		"coop_shot": "fly_attack01", "coop_dive_start": "fuchong01", "coop_dive": "fuchong02",
		"intro": "rage", "intro_wait": "idle", "intro_takeoff": "up", "intro_dive_start": "fuchong01",
		"intro_dive": "fuchong02", "intro_land": "down", "coop_move": "fly_walk", "watch_pose": "idle02"}
	coop_point = 1 if monster_id == 11 else 0


func link_partner(other: Node) -> void:
	partner = weakref(other)


func partner_actor():
	return partner.get_ref() if partner else null


func partner_alive() -> bool:
	var other = partner_actor()
	return is_instance_valid(other) and not other.dead


func start_action(actor, action: String) -> void:
	super.start_action(actor, action)
	beam_left = 0.0
	if action == "init" and monster_id == 9: duration = 2.0
	if action in ["shot", "assist_shot", "coop_shot"]: shot_count = 0
	if action == "takeoff": phase_elapsed = 0.0
	if action == "landing": phase_elapsed = 0.0
	if action in ["dive", "coop_dive"]:
		rush_target = COOP_POINTS[coop_point] if action == "coop_dive" else actor.target.global_position + actor.source_target_direction() * 10.0
		rush_direction = (rush_target - actor.global_position).normalized()
		actor._face_planar_direction(rush_direction)
	if action == "intro_dive":
		rush_target = COOP_POINTS[1]
		rush_direction = (rush_target - actor.global_position).normalized()
		actor._face_planar_direction(rush_direction)
	if action in ["coop_dive", "intro_dive"]: animation_speed = 2.0
	if action == "rage":
		enraged = true
		rage_pending = false
		if partner_dead: defend_left = 30.0
	if action in ["laser", "assist_laser", "coop_laser"]:
		actor._face_planar_direction(actor.source_target_direction())
		beam_yaw = 80.0 if action == "coop_laser" else 40.0
		if action == "coop_laser": actor._face_planar_direction(COOP_POINTS[coop_point] - actor.global_position)


func damage_received(amount: float, _spawning := false) -> float:
	# The untouched assistant's watch balcony has its hit collider disabled.
	# AssistMantis keeps mHitCheckCollider disabled even while shooting from
	# its balcony. CoopMantisJoinStartFlyState enables it after joining.
	if monster_id == 12 and not joined_combat and partner_alive(): return 0.0
	return float(int(amount) / 10) if defend_left > 0.0 else amount


func on_damage(actor) -> void:
	if actor.health <= 0.0: return
	var loss: float = 1.0 - actor.health / actor.max_health
	if not enraged and loss > float(spec.rage_loss): rage_pending = true
	var fraction_per_hit := 0.2 if monster_id == 11 else 0.15
	if loss <= hit_threshold * fraction_per_hit: return
	hit_threshold += 1
	coop_attacks_left = 0
	coop_dive_left = 0
	solo_elapsed = 0.0
	# CoopMantis.ChangeStateAfterHit cancels BOTH counters. Otherwise the
	# unhurt main waits forever for an assistant that resumed solo attacks.
	if partner_alive():
		var other = partner_actor()
		other.source_brain.coop_attacks_left = 0
		other.source_brain.coop_dive_left = 0
		other.source_brain.solo_elapsed = 0.0
	if monster_id == 11 and partner_alive():
		var other = partner_actor()
		if loss > 0.6 and loss <= 0.8:
			coop_pending = true
			other.source_brain.coop_pending = true
		elif loss > 0.2 and loss <= 0.6:
			other.source_brain.assist_active = true
			other.source_brain.start_action(other, "assist_idle")
	start_action(actor, "fly_stagger" if flying else "stagger")


func on_death(_actor) -> void:
	if partner_alive():
		var other = partner_actor()
		other.source_brain.partner_dead = true
		other.source_brain.rage_pending = true
		other.source_brain.coop_pending = false
		other.source_brain.coop_attacks_left = 0
		other.source_brain.coop_dive_left = 0
		other.source_brain.assist_active = false
		other.source_brain.start_action(other, "landing" if other.source_brain.flying else "rage")


func death_animation() -> String:
	return "fly_dead" if flying else "dead"


func step(actor, delta: float, distance: float, direction: Vector3, sight: bool) -> Vector3:
	advance(delta)
	phase_elapsed += delta
	solo_elapsed += delta
	defend_left = maxf(0.0, defend_left - delta)
	beam_left = maxf(0.0, beam_left - delta)
	vertical_control = true
	var height := 0.5 if flying else 0.0
	var result := Vector3(0.0, hover(actor, height, delta), 0.0)
	if state not in ["watch", "init"]: touch(actor, 200.0 if monster_id == 9 else 400.0, 2.5)
	match state:
		"init":
			if elapsed >= duration + (1.2 if monster_id == 12 else 0.0):
				start_action(actor, "intro" if monster_id == 9 else "intro_wait")
		"intro":
			if elapsed >= duration: start_action(actor, "takeoff")
		"intro_wait":
			if elapsed >= (1.2 if monster_id == 12 else 0.0): start_action(actor, "intro_takeoff")
		"intro_takeoff":
			flying = true
			result.y = clampf((8.5 - actor.global_position.y) / maxf(delta, 0.001), -17.0, 17.0)
			actor._face_planar_direction(COOP_POINTS[coop_point] - actor.global_position)
			if elapsed >= duration: start_action(actor, "intro_land" if monster_id == 12 else "intro_dive_start")
		"intro_land":
			result.y = hover(actor, 0.0, delta)
			if elapsed >= duration:
				flying = false
				start_action(actor, "watch")
		"intro_dive_start":
			if elapsed >= duration: start_action(actor, "intro_dive")
		"intro_dive":
			result = rush_direction * 28.0
			strike(actor, 2800.0, 9.5, 45.0, 2.0, 0.22)
			if state_time > 5.0 or (rush_target - actor.global_position).dot(rush_direction) < 1.0:
				start_action(actor, "dive_end")
		"watch":
			if not partner_alive(): start_action(actor, "rage")
			elif elapsed > 1.0 and rng.randi_range(0, 99) < 30: start_action(actor, "watch_pose")
		"watch_pose":
			if elapsed >= duration: start_action(actor, "watch")
		"idle", "fly_idle", "assist_idle":
			actor._face_planar_direction(actor.source_target_direction())
			if elapsed >= (0.4 if enraged else 1.0):
				_decide(actor, distance, sight)
		"chase", "fly_chase":
			actor._face_planar_direction(direction)
			result += direction.normalized() * (14.0 if flying else 12.0)
			if elapsed > 5.0 or distance < (6.0 if flying else 8.0):
				start_action(actor, "fly_idle" if flying else "idle")
		"slash", "critical", "fly_slash":
			if fraction() < 0.2: actor._face_planar_direction(actor.source_target_direction())
			var active := window(0.43, 0.71)
			if state == "critical": active = window(0.25, 0.43) or window(0.57, 0.74)
			if state == "fly_slash": active = window(0.46, 0.70)
			if active: strike(actor, float(spec.damage), 10.5 if flying else 11.5, 70.0, 2.0, 0.0 if state == "fly_slash" else 0.16)
			if elapsed >= duration: _idle(actor)
		"takeoff", "coop_join":
			flying = true
			result.y = clampf((8.5 - actor.global_position.y) / maxf(delta, 0.001), -17.0, 17.0) if state == "coop_join" else hover(actor, 0.5, delta)
			if elapsed >= duration:
				phase_elapsed = 0.0
				if state == "coop_join":
					joined_combat = true
					assist_active = false
				start_action(actor, "coop_move" if state == "coop_join" else "fly_idle")
		"coop_move":
			var goal: Vector3 = COOP_POINTS[coop_point] + Vector3.UP * 0.5
			actor._face_planar_direction(goal - actor.global_position)
			result = (goal - actor.global_position).normalized() * 14.0
			if actor.global_position.distance_to(goal) < 3.0 or elapsed > 5.0:
				current_point = coop_point
				start_action(actor, "coop_idle")
		"landing":
			result.y = hover(actor, 0.0, delta)
			if elapsed >= duration:
				flying = false
				phase_elapsed = 0.0
				start_action(actor, "rage" if rage_pending else "idle")
		"shot", "assist_shot", "coop_shot":
			actor._face_planar_direction(actor.source_target_direction())
			if event("shot", 0.52): actor.source_mantis_shot(800.0 if monster_id == 9 else 1444.0)
			if elapsed >= duration:
				shot_count += 1
				if state == "shot" and shot_count < (3 if enraged else 1):
					var count := shot_count
					start_action(actor, "shot")
					shot_count = count
				else: _idle(actor)
		"boomerang":
			if event("boomerang", 0.52): actor.source_mantis_boomerang(800.0 if monster_id == 9 else 1600.0)
			if elapsed >= duration: _idle(actor)
		"laser", "assist_laser", "coop_laser":
			var begin := 0.41 if state == "coop_laser" else 0.47
			var end := 0.77 if state == "coop_laser" else 0.83
			if window(begin, end):
				if not events.has("aim"):
					events.aim = true
					var aim: Vector3 = COOP_POINTS[coop_point] if state == "coop_laser" else actor.target.global_position
					beam_base_direction = (aim + Vector3.UP * 0.5 - actor.source_laser_origin()).normalized()
				beam_yaw -= (130.0 if state == "coop_laser" else 60.0) * delta
				var beam_dir: Vector3 = beam_base_direction.rotated(Vector3.UP, -deg_to_rad(beam_yaw))
				actor.source_set_beam(true, beam_dir, 45.0, Color(0.7, 0.15, 1.0), 0.3)
				if beam_left <= 0.0 and actor.source_beam_hits(beam_dir, 45.0, 0.6):
					actor.source_damage_target(1111.0 if monster_id == 9 else 2222.0)
					beam_left = 0.2
			else: actor.source_set_beam(false)
			if elapsed >= duration: _idle(actor)
		"dive_start", "coop_dive_start":
			actor._face_planar_direction(COOP_POINTS[coop_point] - actor.global_position if state == "coop_dive_start" else actor.source_target_direction())
			if elapsed >= duration: start_action(actor, "coop_dive" if state == "coop_dive_start" else "dive")
		"dive", "coop_dive":
			result = rush_direction * 28.0
			strike(actor, 1400.0 if monster_id == 9 else 2800.0, 9.5, 45.0, 2.0, 0.22)
			if state_time > 5.0 or (rush_target - actor.global_position).dot(rush_direction) <= 1.0 or (state_time > 0.2 and actor.is_on_wall()):
				if state == "coop_dive":
					current_point = coop_point
					start_action(actor, "coop_idle")
				else: start_action(actor, "dive_end")
		"dive_end":
			if elapsed >= duration: _idle(actor)
		"stagger", "fly_stagger":
			if elapsed >= duration:
				if rage_pending: start_action(actor, "landing" if flying else "rage")
				else: _idle(actor)
		"rage":
			if elapsed >= duration: start_action(actor, "takeoff")
		"coop_idle":
			if not partner_alive() or (coop_attacks_left == 0 and coop_dive_left == 0 and partner_actor().source_brain.state != "coop_idle"):
				solo_elapsed = 0.0
				start_action(actor, "fly_idle" if flying else "idle")
			elif monster_id == 11 and elapsed > 0.1 and partner_actor().source_brain.state == "coop_idle":
				var other = partner_actor()
				if coop_dive_left > 0:
					coop_dive_left -= 1
					coop_point = int({2: 3, 3: 5, 5: 4, 4: 2}.get(current_point, 1 - current_point))
					other.source_brain.coop_point = int({2: 3, 3: 5, 5: 4, 4: 2}.get(other.source_brain.current_point, 1 - other.source_brain.current_point))
					start_action(actor, "coop_dive_start")
					other.source_brain.start_action(other, "coop_dive_start")
				elif coop_attacks_left > 0:
					coop_attacks_left -= 1
					var go_top := rng.randi_range(0, 99) < 50
					coop_point = _attack_point(current_point, go_top)
					other.source_brain.coop_point = _attack_point(other.source_brain.current_point, go_top)
					var next := "coop_laser" if rng.randi_range(0, 99) < (44 if current_point < 2 else 50) else "coop_shot"
					start_action(actor, next)
					other.source_brain.start_action(other, next)
				else:
					solo_elapsed = 0.0
					other.source_brain.solo_elapsed = 0.0
					start_action(actor, "fly_idle")
					other.source_brain.start_action(other, "fly_idle")
	return result


func _idle(actor) -> void:
	if partner_alive() and (state.begins_with("coop_") or state == "dive_end" and coop_attacks_left > 0):
		start_action(actor, "coop_move" if state in ["coop_shot", "coop_laser"] else "coop_idle")
	elif monster_id == 12 and assist_active and partner_alive(): start_action(actor, "assist_idle")
	else: start_action(actor, "fly_idle" if flying else "idle")


func _decide(actor, distance: float, sight: bool) -> void:
	if rage_pending:
		start_action(actor, "landing" if flying else "rage")
		return
	if monster_id == 11 and partner_alive() and (coop_pending or solo_elapsed > 24.0 and 1.0 - actor.health / actor.max_health > 0.6):
		coop_pending = false
		coop_attacks_left = 3
		coop_dive_left = 1
		var other = partner_actor()
		var main_left: bool = actor.global_position.x < other.global_position.x
		if rng.randi_range(0, 99) < 50:
			coop_point = 0 if main_left else 1
			other.source_brain.coop_point = 1 if main_left else 0
		else:
			coop_point = 4 if main_left else 5
			other.source_brain.coop_point = 3 if main_left else 2
		other.source_brain.coop_attacks_left = 3
		other.source_brain.coop_pending = false
		start_action(actor, "coop_join")
		other.source_brain.start_action(other, "coop_join")
		return
	var roll := rng.randi_range(0, 99)
	if monster_id == 12 and assist_active and partner_alive():
		start_action(actor, "boomerang" if distance > 32.0 else ("assist_shot" if roll < 50 else "assist_laser"))
	elif not flying:
		if phase_elapsed > (10.0 if enraged else 8.0) or distance >= 26.0: start_action(actor, "takeoff")
		elif distance < 8.0 and sight: start_action(actor, "slash" if roll < (50 if enraged else 70) else "critical")
		else: start_action(actor, "chase")
	elif phase_elapsed > (25.0 if enraged else 18.0): start_action(actor, "landing")
	elif not sight: start_action(actor, "fly_chase")
	elif distance < 6.0: start_action(actor, "fly_slash" if roll < (75 if enraged else 80) else "laser")
	elif distance < 26.0:
		start_action(actor, "fly_chase" if roll < (20 if enraged else 30) else ("laser" if roll < (60 if enraged else 70) else "shot"))
	else: start_action(actor, "boomerang" if roll < (70 if enraged else 80) else "dive_start")


func _attack_point(point: int, go_top: bool) -> int:
	if point in [2, 4]: return 1
	if point in [3, 5]: return 0
	if point == 0: return 2 if go_top else 4
	return 5 if go_top else 3
