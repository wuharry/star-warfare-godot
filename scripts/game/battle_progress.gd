class_name BattleProgress
extends RefCounted
## One run's transient state. Feed gameplay delta (pause stops the clock), never
## wall-clock time. This helper neither awards currency nor writes a save.

signal combo_changed(combo: int, maximum: int)

const CareerData = preload("res://scripts/core/career_progress.gd")
const COMBO_WINDOW_SECONDS := 3.0 # Player.cs:630; Timer.Ready uses >, not >=.

var combo := 0
var max_combo := 0
var kills := 0
var never_hit := true
var active := false
var elapsed := 0.0
var _last_kill_at := -INF
var _career: CareerData
var _context: Dictionary = {}
var _result: Dictionary = {}


## Context: level_key:String, multiplayer:bool, pve:bool (default true), and
## optional source_stage/source_substage. Do not infer chapter flags from waves.
func start(progress: CareerData, context: Dictionary = {}) -> void:
	_career = progress
	_context = context.duplicate(true)
	_result.clear()
	combo = 0
	max_combo = 0
	kills = 0
	never_hit = true
	elapsed = 0.0
	_last_kill_at = -INF
	active = true
	if _career != null and _context.get("multiplayer", false) == true:
		_career.record_multiplayer_start()
	combo_changed.emit(combo, max_combo)


func advance(delta: float) -> void:
	if not active or not is_finite(delta) or delta <= 0.0:
		return
	elapsed += delta
	if combo > 0 and elapsed - _last_kill_at > COMBO_WINDOW_SECONDS:
		combo = 0
		combo_changed.emit(combo, max_combo)


## Call once when the local player receives an alien kill. VS player kills use
## their own multiplayer statistics, as they do in the source PlayerVSStatistics.
func record_enemy_kill(source_boss_category := -1) -> int:
	if not active:
		return combo
	combo += 1
	kills += 1
	max_combo = maxi(max_combo, combo)
	_last_kill_at = elapsed
	if _career != null:
		_career.record_enemy_kill(_context.get("multiplayer", false) == true)
		_career.record_max_combo(max_combo)
		if source_boss_category >= 0:
			_career.record_boss_kill(source_boss_category)
	combo_changed.emit(combo, max_combo)
	return combo


## Wire WarfarePlayer.damaged(actual_damage); shield damage counts too.
func record_damage(actual_damage: float) -> void:
	if is_finite(actual_damage) and actual_damage > 0.0:
		record_hit()


## For a source-style accepted hit even with no HP loss. Blocked/missed attacks
## must not call this. Healing does not restore eligibility for Ghost.
func record_hit() -> void:
	if active:
		never_hit = false


## Wire only a confirmed local revived signal, not an attempted use or VS respawn.
func record_revival() -> void:
	if not active:
		return
	never_hit = false
	if _career != null:
		_career.record_revival()


## Enemy.AddCashAndExpToPlayer: combo bonuses are added to base loot/XP.
## Caller applies int(base_cash * rate), and int(base_exp * (1 + skill + rate)).
func get_combo_bonus_rate() -> float:
	if combo >= 10:
		return 1.0
	if combo >= 8:
		return 0.5
	if combo >= 5:
		return 0.2
	if combo >= 3:
		return 0.1
	return 0.0


## Settlement is idempotent for this run, even if win/death callbacks race.
## Finish before GameState's existing complete_level/_save transaction.
func finish(won: bool, score := 0) -> Dictionary:
	if not active:
		return _result.duplicate(true)
	active = false
	_result = _context.duplicate(true)
	_result.merge({"won": won, "score": maxi(0, score), "kills": kills,
		"max_combo": max_combo, "never_hit": never_hit, "time": elapsed,
		"pve": _context.get("pve", true) == true}, true)
	if _career != null:
		_career.record_run(_result)
	return _result.duplicate(true)


## Leaving an unfinished run retains live kill statistics but awards no victory.
func stop() -> void:
	active = false
	combo = 0
	combo_changed.emit(combo, max_combo)
