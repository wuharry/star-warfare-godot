extends "res://scripts/game/enemy_boss_brain.gd"

# Spider.cs (EnemyType.Beetle) and Earthworm.cs share spit/charge decisions,
# but not jump/drill, damage, rage threshold, or their movement trajectories.
var earthworm := false
var rush_direction := Vector3.ZERO
var rush_target := Vector3.ZERO
var rush_count := 0
var jump_velocity := Vector3.ZERO
var shot_left := 0.0
var super_elapsed := 0.0
var hidden := false
var super_count := 0


func configure(data: Dictionary) -> void:
	super.configure(data)
	earthworm = monster_id == 13
	clips = {"init": "out" if earthworm else "attack02", "idle": "idle", "chase": "run",
		"attack": "attack" if earthworm else "attack04", "double": "attack03",
		"shot": "attack_spit1" if earthworm else "attack",
		"continuous": "attack_spit2" if earthworm else "attack02",
		"rush_start": "attack_dash_start" if earthworm else "try_run",
		"rush": "attack_dash_idle" if earthworm else "chong",
		"rush_end": "attack_dash_over" if earthworm else "idle",
		"jump_start": "jump01", "jump_up": "jump01", "jump_hover": "jump02",
		"jump_down": "jump02", "jump_end": "jump03", "drill_in": "ground_in",
		"drill_idle": "idle", "drill_out": "out", "super_start": "attack_dash_start",
		"super_rush": "attack_dash_fastidle", "super_end": "attack_dash_over",
		"stagger": "attacked", "rage": "rage" if earthworm else "attack02"}


func start_action(actor, action: String) -> void:
	super.start_action(actor, action)
	shot_left = 0.0
	vertical_control = action.begins_with("jump_") or action == "super_start"
	if action == "drill_in": animation_speed = 1.2
	if action == "rush" and not earthworm: animation_speed = 2.0
	if action == "rage":
		enraged = true
		rage_pending = false
	if action in ["rush", "super_rush"]:
		rush_direction = actor.source_target_direction()
		rush_target = actor.target.global_position + rush_direction * 10.0
		if earthworm:
			var wall: Dictionary = actor.source_wall_point(actor.target.global_position, rush_direction)
			if not wall.is_empty():
				if action == "super_rush" and super_count < 2: rush_target = Vector3(wall.position) + rush_direction * 64.0
				elif Vector3(wall.position).distance_to(actor.target.global_position) < 16.0: rush_target = Vector3(wall.position) - rush_direction * 6.0
			vertical_control = true
		actor._face_planar_direction(rush_direction)
	if action == "super_start" and super_count > 0:
		actor.source_relocate_super_rush(rng)
		elapsed = minf(1.0, duration * 0.9)
	if action == "super_rush":
		super_count += 1
		animation_speed = 2.0
	if action == "jump_start":
		var target_delta: Vector3 = actor.target.global_position - actor.global_position
		target_delta.y = 0.0
		jump_velocity = target_delta / (20.0 / (9.81 * 4.0)) + Vector3.UP * 20.0
	if action == "jump_down": jump_velocity = Vector3.ZERO
	if action == "drill_idle":
		hidden = true
		actor.source_set_hidden(true)
	if action == "drill_out":
		hidden = false
		actor.source_set_hidden(false)
	if earthworm and action in ["rush", "super_start", "super_rush"]: actor.collision_mask = 0
	elif actor.collision_mask == 0 and not actor.dead: actor.collision_mask = 1


func damage_received(amount: float, _spawning := false) -> float:
	return 0.0 if hidden else amount


func on_damage(actor) -> void:
	# These movements cannot be interrupted by HP-threshold stagger.
	if state.begins_with("jump_") or state.begins_with("drill_"): return
	super.on_damage(actor)


func step(actor, delta: float, distance: float, direction: Vector3, sight: bool) -> Vector3:
	advance(delta)
	super_elapsed += delta
	shot_left = maxf(0.0, shot_left - delta)
	var result := Vector3.ZERO
	if not hidden and state not in ["rush", "super_rush"] and not state.begins_with("jump_") and not state.begins_with("drill_"):
		touch(actor, 1200.0 if earthworm else 400.0, 3.0)
	match state:
		"init":
			if elapsed >= duration: start_action(actor, "idle")
		"idle":
			if elapsed >= ((0.1 if enraged else 0.2) if earthworm else (0.64 if enraged else 1.0)):
				_decide(actor, distance, sight)
		"chase":
			actor._face_planar_direction(direction)
			result = direction.normalized() * float(spec.speed)
			if elapsed > 5.0 or distance < float(spec.attack_range): start_action(actor, "idle")
		"attack", "double":
			if fraction() < 0.2: actor._face_planar_direction(-actor.source_target_direction() if earthworm else actor.source_target_direction())
			if earthworm:
				if window(0.51, 0.61) and fire_left <= 0.0:
					if actor.source_damage_near(actor.source_tail_center(), 7.0, 6400.0, 0.16): fire_left = 2.0
			elif (state == "attack" and window(0.45, 0.70)) or (state == "double" and (window(0.22, 0.44) or window(0.70, 0.92))):
				strike(actor, 2200.0, 9.0, 75.0, 2.0, 0.16)
			if elapsed >= duration: start_action(actor, "idle")
		"shot":
			if not events.has("shot"): actor._face_planar_direction(actor.source_target_direction())
			if event("shot", 0.48): actor.source_boss_spit(earthworm, 0.0, 0.0, 2.2 if earthworm else 1.0)
			if elapsed >= duration: start_action(actor, "idle")
		"continuous":
			if fraction() < 0.27: actor._face_planar_direction(actor.source_target_direction())
			if window(0.27, 0.73) and shot_left <= 0.0:
				actor.source_boss_spit(earthworm, rng.randf_range(-36.0, 36.0), rng.randf_range(-16.0 if earthworm else -10.0, 16.0 if earthworm else 10.0), rng.randf_range(1.1, 1.5) if earthworm else rng.randf_range(0.5, 0.8))
				shot_left = 0.16 if earthworm else (0.1 if fraction() < 0.57 else 0.2)
			if elapsed >= duration: start_action(actor, "idle")
		"rush_start", "super_start":
			actor._face_planar_direction(actor.source_target_direction())
			if elapsed >= duration: start_action(actor, "super_rush" if state == "super_start" else "rush")
		"rush", "super_rush":
			var super_rush := state == "super_rush"
			result = rush_direction * (50.0 if super_rush else (42.0 if earthworm else 32.0))
			strike(actor, 7200.0 if super_rush else (5600.0 if earthworm else 2800.0), 7.0, 60.0, 2.0, 0.36 if super_rush else 0.24)
			if state_time > 5.0 or (state_time > 0.15 and (rush_target - actor.global_position).dot(rush_direction) <= (4.0 if earthworm else 1.0)) or (not earthworm and state_time > 0.2 and actor.is_on_wall()):
				if super_rush and super_count < 3: start_action(actor, "super_start")
				elif super_rush:
					super_count = 0
					start_action(actor, "super_end")
				else: start_action(actor, "rush_end")
		"rush_end":
			if elapsed >= duration:
				rush_count += 1
				if rush_count < (1 if earthworm else (2 if enraged else 1)): start_action(actor, "rush_start")
				else:
					rush_count = 0
					start_action(actor, "idle")
		"super_end":
			if elapsed >= duration: start_action(actor, "idle")
		"jump_start":
			if event("launch", 0.54): start_action(actor, "jump_up")
		"jump_up":
			result = jump_velocity
			jump_velocity.y -= 9.81 * 4.0 * delta
			if jump_velocity.y <= 0.0: start_action(actor, "jump_hover")
		"jump_hover":
			if elapsed >= (0.15 if enraged else 0.3): start_action(actor, "jump_down")
		"jump_down":
			jump_velocity.y -= 9.81 * 8.0 * delta
			result = jump_velocity
			if actor.global_position.y <= actor.source_floor_height() + 0.12 or actor.is_on_floor():
				actor.source_shockwave(5.0, 9.0, 3600.0, 880.0, 0.24, 0.08)
				start_action(actor, "jump_end")
		"jump_end":
			if elapsed >= duration: start_action(actor, "idle")
		"drill_in":
			if elapsed >= duration: start_action(actor, "drill_idle")
		"drill_idle":
			var wait := 3.0 if enraged else 4.4
			if elapsed >= wait - 3.0 and not events.has("warning"):
				events.warning = true
				actor.source_relocate_drill(rng)
				actor.source_telegraph(actor.global_position, 20.0, 3.0)
			if elapsed >= wait: start_action(actor, "drill_out")
		"drill_out":
			if window(0.42, 0.50) and touch_left <= 0.0 and actor.source_damage_near(actor.global_position, 10.0, 7200.0, 0.24): touch_left = 2.0
			if window(0.50, 0.60) and touch_left <= 0.0 and actor.source_damage_near(actor.global_position, 20.0, 3600.0, 0.08): touch_left = 2.0
			if fraction() > 0.5: animation_speed = 1.5
			if elapsed >= duration: start_action(actor, "idle")
		"stagger":
			if elapsed >= duration: start_action(actor, "rage" if rage_pending else "idle")
		"rage":
			if earthworm:
				if (window(0.32, 0.42) or window(0.65, 0.75)) and fire_left <= 0.0:
					if actor.source_damage_near(actor.source_tail_center(), 7.0, 6400.0, 0.16): fire_left = 2.0
				if window(0.27, 0.73) and shot_left <= 0.0:
					actor.source_boss_spit(true, rng.randf_range(-50.0, 50.0), rng.randf_range(-20.0, 20.0), rng.randf_range(1.1, 1.5))
					shot_left = 0.12
			if elapsed >= duration: start_action(actor, "idle")
	return result


func _decide(actor, distance: float, sight: bool) -> void:
	if rage_pending:
		start_action(actor, "rage")
		return
	var roll := rng.randi_range(0, 99)
	if earthworm and enraged and super_elapsed > 24.0 and roll < 20:
		super_elapsed = 0.0
		start_action(actor, "super_start")
	elif distance < float(spec.attack_range) and sight:
		start_action(actor, "attack" if earthworm or roll < (50 if enraged else 70) else "double")
	elif distance >= (32.0 if earthworm else 29.0): start_action(actor, "rush_start")
	elif not sight: start_action(actor, "chase")
	else:
		var cuts: Array = ([25, 55, 70, 85] if enraged else [35, 50, 85, 100]) if earthworm else ([20, 50, 68, 90] if enraged else [28, 46, 76, 100])
		if roll < int(cuts[0]): start_action(actor, "chase")
		elif roll < int(cuts[1]): start_action(actor, "continuous")
		elif roll < int(cuts[2]): start_action(actor, "shot")
		elif roll < int(cuts[3]): start_action(actor, "drill_in" if earthworm else "jump_start")
		else: start_action(actor, "rush_start")
