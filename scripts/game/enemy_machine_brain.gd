extends "res://scripts/game/enemy_boss_brain.gd"

# SatanMachine.cs uses four one-use HP bands, not permanent low-HP rage.
const MISSILE_TIMES := [0.275, 0.325, 0.4, 0.475, 0.54, 0.625]
var rage_bands: Dictionary = {}
var rage_attacks := 0
var cooldowns := {"missile": 10.0, "laser": 30.0, "gift": 60.0, "stomp": 15.0}
var attacked := false
var beam_direction := Vector3.FORWARD


func configure(data: Dictionary) -> void:
	super.configure(data)
	clips = {"init": "idle", "idle": "idle", "idle_a": "idle01", "idle_b": "idle02",
		"chase": "run", "stomp": "attack", "missile_a": "attack02_christ",
		"missile_b": "attack03_christ", "laser": "attack01_christ", "gift": "attack04_christ",
		"rage": "head_christ", "whirl_start": "attack_begin_joky", "whirl": "attack_joky",
		"whirl_end": "attack_end_joky", "ball": "attack01_joky", "rage_end": "head_joky"}


func death_animation() -> String:
	return "death"


func on_damage(_actor) -> void:
	pass # Source machine takes damage without a normal HP-threshold stagger.


func start_action(actor, action: String) -> void:
	super.start_action(actor, action)
	if action == "laser":
		actor._face_planar_direction(actor.source_target_direction())
		beam_direction = (actor.target.global_position + Vector3.UP - actor.source_muzzle()).normalized()
	if action == "rage":
		enraged = true
		rage_attacks = 0
	if action == "rage_end": enraged = false
	if action == "ball": rage_attacks += 1


func step(actor, delta: float, distance: float, direction: Vector3, _sight: bool) -> Vector3:
	advance(delta)
	for key: String in cooldowns: cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
	touch(actor, 1000.0, 3.0, 1.0, 0.15)
	var result := Vector3.ZERO
	match state:
		"init", "idle_a", "idle_b":
			if elapsed >= duration: start_action(actor, "idle")
		"idle":
			if elapsed > (0.1 if enraged else 0.2): _decide(actor, distance)
		"chase":
			actor._face_planar_direction(direction)
			result = direction.normalized() * (11.5 if enraged else 9.0)
			if elapsed >= 2.0: start_action(actor, "idle")
		"stomp":
			if event("stomp", 0.25): actor.source_shockwave(15.0, 15.0, 10000.0, 10000.0, 0.04, 0.04)
			if elapsed >= duration:
				cooldowns.stomp = 15.0
				start_action(actor, "laser") # Source always chains stomp -> laser.
		"missile_a", "missile_b":
			for index in range(MISSILE_TIMES.size()):
				if event("missile_%d" % index, MISSILE_TIMES[index]): actor.source_machine_missiles()
			if elapsed >= duration:
				cooldowns.missile = 10.0
				start_action(actor, "idle")
		"laser":
			if event("laser", 0.42): actor.source_machine_laser(beam_direction)
			if elapsed >= duration:
				cooldowns.laser = 30.0
				start_action(actor, "idle")
		"gift", "ball":
			if event("bombs", 0.05): actor.source_machine_bombs(state == "ball", rng)
			if elapsed >= duration:
				if state == "ball": start_action(actor, "whirl_start")
				else:
					cooldowns.gift = 60.0
					start_action(actor, "idle")
		"rage":
			if elapsed >= duration: start_action(actor, "ball")
		"whirl_start":
			if elapsed >= duration: start_action(actor, "whirl")
		"whirl":
			actor._face_planar_direction(direction)
			result = direction.normalized() * 11.5
			var hit := strike(actor, 10000.0, 6.0, 180.0, 1.0, 0.3)
			if (hit and actor.source_damage_receivers().size() == 1) or elapsed >= 10.0: start_action(actor, "whirl_end")
		"whirl_end":
			if elapsed >= duration: start_action(actor, "rage_end" if rage_attacks >= 2 else "ball")
		"rage_end":
			if elapsed >= duration: start_action(actor, "idle")
	return result


func _decide(actor, distance: float) -> void:
	if attacked:
		attacked = false
		start_action(actor, "idle_a" if rng.randi_range(0, 99) < 50 else "idle_b")
		return
	var band := int(actor.health * 5.0 / actor.max_health)
	if band < 4 and not rage_bands.has(band):
		rage_bands[band] = true
		attacked = true
		start_action(actor, "rage")
	elif float(cooldowns.gift) <= 0.0:
		attacked = true
		start_action(actor, "gift")
	elif float(cooldowns.stomp) <= 0.0 and distance < 15.0:
		attacked = true
		start_action(actor, "stomp")
	else:
		var roll := rng.randi_range(0, 99)
		if roll < 25 and float(cooldowns.missile) <= 0.0:
			attacked = true
			start_action(actor, "missile_a" if rng.randi_range(0, 99) < 50 else "missile_b")
		elif roll < 50 and roll >= 25 and float(cooldowns.laser) <= 0.0 and distance < 20.0:
			attacked = true
			start_action(actor, "laser")
		else: start_action(actor, "chase")
