extends Node

# Holding the trigger should feel different from gun to gun. The fire interval
# has always differed in the weapon table, but the firing animation ran at one
# fixed rate for every weapon, so a 0.17 s machinegun pumped the arms at the
# same speed as a 0.85 s rifle. This pins the playback rate to the interval and,
# just as importantly, proves the rates actually spread out instead of all
# landing on the same clamp edge -- a clamp that swallows every weapon would
# make the whole feature a no-op while still "passing" a naive assertion.

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WEAPON FIRE FEEDBACK TEST: " + message)

func _automatic_weapons() -> Array[String]:
	var ids: Array[String] = []
	for weapon_id: String in GameState.WEAPONS:
		if bool(GameState.WEAPONS[weapon_id].get("automatic", false)):
			ids.append(weapon_id)
	ids.sort()
	return ids

func _run() -> void:
	# equip_weapon persists the selection, and GameState autosaves. Never let a
	# test write to the real profile.
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_level = 1
	GameState.selected_weapon = "gun00"
	var world := (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	add_child(world)
	await get_tree().process_frame
	var player := world.player
	player.max_health = 100000.0
	player.health = player.max_health
	player.energy = player.max_energy

	# --- the interval helper must reproduce what _try_fire actually sets ------
	player.equip_weapon("gun00", false)
	player.armor_skills = {}
	var expected: float = float(player.current_weapon.cooldown)
	_check(is_equal_approx(player._current_shot_interval(), expected),
		"_current_shot_interval disagrees with the weapon cooldown with no armour bonus")
	player.armor_skills = {"attack_frequency": -0.5}
	_check(is_equal_approx(player._current_shot_interval(), expected * 0.5),
		"_current_shot_interval ignores the armour attack_frequency bonus")
	# The original clamp keeps a hostile bonus from inverting the fire rate.
	player.armor_skills = {"attack_frequency": -5.0}
	_check(is_equal_approx(player._current_shot_interval(), expected * 0.2),
		"_current_shot_interval lost the 0.2 floor on the armour bonus")
	player.armor_skills = {}

	# --- a single-shot weapon must never be rate-scaled -----------------------
	for weapon_id: String in GameState.WEAPONS:
		if bool(GameState.WEAPONS[weapon_id].get("automatic", false)):
			continue
		player.equip_weapon(weapon_id, false)
		_check(is_equal_approx(player._shoot_animation_rate("stand_shoot_rifle"), 1.0),
			"non-automatic %s was given a scaled firing animation" % weapon_id)
		break

	# --- automatic weapons must actually spread across distinct rates ---------
	var rates: Dictionary = {}
	var report: Array[String] = []
	var clip := player.recovered_animation_player.get_animation("stand_shoot_rifle")
	_check(clip != null and clip.length > 0.0, "stand_shoot_rifle clip is missing or zero length")
	for weapon_id in _automatic_weapons():
		player.equip_weapon(weapon_id, false)
		var interval: float = player._current_shot_interval()
		var rate: float = player._shoot_animation_rate("stand_shoot_rifle")
		rates[weapon_id] = rate
		report.append("  %-7s %-10s interval=%.3fs  rate=%.2fx" % [
			weapon_id, str(player.current_weapon.name), interval, rate])
		_check(rate > 0.0, "%s produced a non-positive animation rate" % weapon_id)
		# A faster gun must never animate slower than a slower gun.
		if interval > 0.0 and clip:
			var unclamped: float = clip.length / interval
			# The clamp is a guard, not a tuning knob. Every shipped automatic
			# weapon must resolve inside it, or its fire rate stops reaching the
			# player and this whole feature silently flattens out again.
			_check(
				unclamped >= WarfarePlayer.SHOOT_ANIMATION_RATE_MIN
				and unclamped <= WarfarePlayer.SHOOT_ANIMATION_RATE_MAX,
				"%s (%.3fs) needs rate %.2fx, outside the [%.2f, %.2f] guard -- widen it or the weapon animates like every other slow gun" % [
					weapon_id, interval, unclamped,
					WarfarePlayer.SHOOT_ANIMATION_RATE_MIN, WarfarePlayer.SHOOT_ANIMATION_RATE_MAX])
			_check(is_equal_approx(rate, unclamped),
				"%s is inside the guard but its rate was altered" % weapon_id)

	var distinct: Dictionary = {}
	for weapon_id: String in rates:
		distinct[snappedf(rates[weapon_id], 0.01)] = true
	# Distinct rates, not just "more than one": the fire intervals themselves
	# collapse onto a handful of values (0.20 s is shared by four weapons), so
	# this tracks the interval table rather than demanding 18 unique speeds.
	var distinct_intervals: Dictionary = {}
	for weapon_id in _automatic_weapons():
		player.equip_weapon(weapon_id, false)
		distinct_intervals[snappedf(player._current_shot_interval(), 0.001)] = true
	_check(distinct.size() == distinct_intervals.size(),
		"%d distinct animation rates for %d distinct fire intervals -- the guard is flattening real differences" % [
			distinct.size(), distinct_intervals.size()])

	# --- the rate must survive a weapon swap onto the same clip ---------------
	var ids := _automatic_weapons()
	if ids.size() >= 2:
		var slow := ids[0]
		var fast := ids[0]
		for weapon_id in ids:
			if rates[weapon_id] < rates[slow]:
				slow = weapon_id
			if rates[weapon_id] > rates[fast]:
				fast = weapon_id
		if not is_equal_approx(rates[slow], rates[fast]):
			player.equip_weapon(slow, false)
			player.shoot_pose_left = 0.4
			player._play_recovered_animation("stand_shoot_rifle", 0.08, false, rates[slow])
			_check(is_equal_approx(player.recovered_animation_speed, rates[slow]),
				"slow weapon did not apply its playback rate")
			player.equip_weapon(fast, false)
			player._play_recovered_animation("stand_shoot_rifle", 0.08, false, rates[fast])
			_check(is_equal_approx(player.recovered_animation_speed, rates[fast]),
				"swapping to a faster weapon kept the previous playback rate on the same clip")

	# --- the layered path scales only the arms, never the legs ---------------
	player.equip_weapon(ids[0] if not ids.is_empty() else "gun00", false)
	player._play_recovered_layered_animation("run_rifle", "run_shoot_rifle", false, 1.85)
	_check(is_equal_approx(float(player.recovered_animation_tree.get("parameters/upper_rate/scale")), 1.85),
		"layered firing animation ignored its playback rate")
	player._play_recovered_layered_animation("run_rifle", "run_shoot_rifle", false, 0.75)
	_check(is_equal_approx(float(player.recovered_animation_tree.get("parameters/upper_rate/scale")), 0.75),
		"layered rate did not update when the clip stayed the same")

	print("=== automatic weapon firing rates ===")
	for line in report:
		print(line)
	print("distinct rates: %d of %d automatic weapons" % [distinct.size(), rates.size()])

	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	if failures.is_empty():
		print("WEAPON_FIRE_FEEDBACK_TEST_PASS checks=%d" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)
