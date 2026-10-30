extends RefCounted

# Shared clocks only. Each boss below keeps its own source decisions, clip
# events and damage rules; a large delta cannot fire a one-shot twice.
var spec: Dictionary
var monster_id := -1
var state := "init"
var elapsed := 0.0
var state_time := 0.0
var previous_elapsed := 0.0
var duration := 1.0
var animation_speed := 1.0
var vertical_control := false
var enraged := false
var rage_pending := false
var hit_threshold := 1
var fire_left := 2.0
var touch_left := 2.0
var events: Dictionary = {}
var rng := RandomNumberGenerator.new()
var clips: Dictionary = {}


func configure(data: Dictionary) -> void:
	spec = data.duplicate(true)
	monster_id = int(data.id)
	rng.randomize()


func animation_name() -> String:
	return str(clips.get(state, "idle"))


func start_action(actor, action: String) -> void:
	state = action
	elapsed = 0.0
	state_time = 0.0
	previous_elapsed = 0.0
	events.clear()
	animation_speed = 1.0
	duration = actor.source_clip_length(animation_name(), 1.0)
	actor.source_set_beam(false)
	actor._play_recovered_animation(animation_name(), 0.08, true)
	actor.source_boss_sound(action)


func advance(delta: float) -> void:
	previous_elapsed = elapsed
	state_time += delta
	elapsed += delta * animation_speed
	fire_left = maxf(0.0, fire_left - delta)
	touch_left = maxf(0.0, touch_left - delta)


func fraction() -> float:
	return elapsed / maxf(duration, 0.001)


func event(key: String, at_fraction: float) -> bool:
	if not events.has(key) and fraction() >= at_fraction:
		events[key] = true
		return true
	return false


func window(begin: float, end: float) -> bool:
	return fraction() >= begin and previous_elapsed / maxf(duration, 0.001) < end


func strike(actor, damage: float, reach: float, half_angle := 65.0, interval := 2.0, knock_step := 0.0) -> bool:
	if fire_left <= 0.0 and actor.source_target_in_cone(reach, half_angle):
		actor.source_damage_target(damage, knock_step)
		fire_left = interval
		return true
	return false


func touch(actor, damage: float, radius: float, interval := 2.0, knock_step := 0.08) -> void:
	if touch_left <= 0.0 and actor.source_planar_distance() < radius and absf(actor.target.global_position.y - actor.global_position.y) < 2.5:
		actor.source_damage_target(damage, knock_step)
		touch_left = interval


func hover(actor, height: float, delta: float, rate := 10.0) -> float:
	return clampf((actor.source_floor_height() + height - actor.global_position.y) / maxf(delta, 0.001), -rate, rate)


func damage_received(amount: float, _spawning := false) -> float:
	return amount


func on_damage(actor) -> void:
	if actor.health <= 0.0: return
	var loss: float = 1.0 - actor.health / actor.max_health
	if not enraged and loss > float(spec.rage_loss): rage_pending = true
	if loss > hit_threshold * 0.15:
		hit_threshold += 1
		start_action(actor, "stagger")


func on_death(_actor) -> void:
	pass


func death_animation() -> String:
	return "dead"
