extends RefCounted

# Offline normal-enemy rules from Drone/Zergling/Scorpion/Boomer/Tank/Reaver/
# Mutalisk/Worm.cs. No guessed attacks from otherwise unused table rows:
# Tank never calls the table's "spit" or "lift" attacks, for example.
var state := "chase"
var elapsed := 0.0
var cooldown := 0.0
var special_cooldown := 0.0
var stagger_cooldown := 0.0
var look_cooldown := 0.0
var fired := false
var locked_direction := Vector3.ZERO
var jump_speed := 0.0
var id := -1
var config: Dictionary
var rng := RandomNumberGenerator.new()


func configure(spec: Dictionary) -> void:
	config = spec.duplicate(true)
	id = int(spec.id)
	rng.randomize()
	# Source Init seeds lastGotHitStateTime for these two armored enemies.
	stagger_cooldown = 10.0 if id == 4 else (11.0 if id == 5 else 0.0)
	state = "chase"


func damage_received(amount: float, spawning: bool) -> float:
	if spawning:
		return 0.0
	# Worm's rolled chase state divides integer damage by ten. It is vulnerable
	# while attacking; this is NOT a permanent armor percentage.
	return float(int(amount) / 10) if id == 7 and state == "chase" else maxf(0.0, amount)


func stagger(duration: float) -> bool:
	if id == 7 and state == "chase":
		return false
	if id in [4, 5] and (stagger_cooldown > 0.0 or state in ["rush_windup", "rush"]):
		return false
	stagger_cooldown = 10.0 if id == 4 else (11.0 if id == 5 else 0.0)
	state = "stagger"
	elapsed = -duration
	return true


func animation_name() -> String:
	match state:
		"attack": return "attack"
		"jump": return "jump"
		"rush_windup": return "idle01"
		"rush": return "chong"
		"stagger": return "attacked"
		"look": return "idle"
	return "run"


func step(actor: Node3D, delta: float, distance: float, planar: Vector3, sight: bool) -> Vector3:
	elapsed += delta
	cooldown = maxf(0.0, cooldown - delta)
	special_cooldown = maxf(0.0, special_cooldown - delta)
	stagger_cooldown = maxf(0.0, stagger_cooldown - delta)
	look_cooldown = maxf(0.0, look_cooldown - delta)
	var duration: float = actor.source_clip_length(animation_name(), 1.0)
	if state == "stagger":
		if elapsed >= 0.0: _enter("chase")
		return Vector3.ZERO
	if state == "look":
		if elapsed >= 1.0: _enter("chase")
		return Vector3.ZERO
	if state == "rush_windup":
		if distance > 8.0:
			locked_direction = actor.source_target_direction()
		if elapsed >= duration / 1.6: _enter("rush")
		return Vector3.ZERO
	if state == "rush":
		if not fired and distance < 2.0:
			actor.source_damage_target(float(config.attack_profiles[0].damage))
			fired = true
		if elapsed >= 5.0 - actor.source_clip_length("idle01", 1.0) / 1.6 or actor.is_on_wall() or distance < 1.0:
			_enter("chase")
			return Vector3.ZERO
		return locked_direction * float(config.attack_profiles[0].speed)
	if state == "jump":
		var progress := elapsed / duration
		if not fired and progress >= 0.2 and progress <= 0.66 and distance < 2.0:
			actor.source_damage_target(float(config.attack_profiles[1].damage))
			fired = true
		if progress >= 1.0: _enter("chase")
		return locked_direction * jump_speed if progress >= 0.2 and progress < 0.66 else Vector3.ZERO
	if state == "attack":
		actor._face_planar_direction(actor.source_target_direction())
		var hit_fraction := 0.6 if id in [2, 5, 6] else (0.5 if id == 7 else 0.4)
		if not fired and elapsed >= duration * hit_fraction:
			fired = true
			if id in [2, 5, 6]:
				actor.source_normal_shot(config.attack_profiles[0], id)
			else:
				var reach := 6.0 if id == 4 else (5.0 if id == 7 else 3.0)
				if actor.source_target_in_cone(reach, 30.0):
					actor.source_damage_target(float(config.damage))
		if elapsed >= duration: _enter("chase")
		return Vector3.ZERO
	if id == 1 and special_cooldown <= 0.0 and look_cooldown <= 0.0:
		if rng.randi_range(0, 99) < 10:
			look_cooldown = 4.0
			_enter("look")
			return Vector3.ZERO
		if sight and distance > 5.0 and distance < 15.0:
			special_cooldown = 3.5
			locked_direction = actor.source_target_direction()
			jump_speed = distance / (actor.source_clip_length("jump", 1.0) * 0.5)
			_enter("jump")
			return Vector3.ZERO
	if id == 4 and special_cooldown <= 0.0 and sight and actor.source_has_rush_clearance():
		special_cooldown = 10.0
		locked_direction = actor.source_target_direction()
		_enter("rush_windup")
		return Vector3.ZERO
	if distance < float(config.attack_range) and sight:
		if cooldown <= 0.0:
			cooldown = float(config.attack_interval)
			if id == 3:
				# Boomer.OnAttack kills itself; CheckHit is a single radius check.
				actor.source_explode(float(config.damage), float(config.attack_profiles[0].bomb_radius))
			else:
				_enter("attack")
		return Vector3.ZERO
	actor._face_planar_direction(planar)
	return planar.normalized() * float(config.speed)


func _enter(next: String) -> void:
	state = next
	elapsed = 0.0
	fired = false
