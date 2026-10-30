class_name CareerProgress
extends RefCounted
## Offline career data. The owner serializes this inside GameState's transaction.
## No file access, autoload lookup, platform achievement IDs or network submission.

signal changed
signal achievement_unlocked(achievement_id: String)

const SCHEMA_VERSION := 1
# Largest integer that survives JSON's double representation without rounding.
const MAX_COUNTER := 9007199254740991
const SOURCE_SUIT_COUNT := 21 # Global.TOTAL_ARMOR_NUM; excludes added CoM suits.
const SOURCE_WEAPON_COUNT := 47 # Global.TOTAL_WEAPON_NUM.
const SOURCE_MAX_WEAPON_LEVEL := 8 # Global.MAX_LEVEL_WEAPONW.
const DEFAULT_STATS := {
	"enemy_kills": 0, "team_kills": 0, "max_combo": 0, "credits_spent": 0,
	"full_upgrades": 0, "suits_collected": 0, "multiplayer_sessions": 0,
	"revivals": 0, "wins": 0, "losses": 0, "flawless_wins": 0,
	"high_score": 0, "high_kills": 0,
	"campaign_first": 0, "campaign_third": 0, "campaign_fifth": 0,
}
# AchievementState.cs indexes 0..22. Local IDs retain the source ordering only.
# >= intentionally repairs missed thresholds when loading/batching progress;
# the source's incremental == checks must not strand a migrated player.
const ACHIEVEMENTS := [
	{"id": "a1", "title": "First Enemy", "metric": "enemy_kills", "target": 1, "description": "Defeat your first alien."},
	{"id": "a2", "title": "Debugger", "metric": "enemy_kills", "target": 100, "description": "Defeat 100 aliens."},
	{"id": "a3", "title": "Boss Killer", "metric": "boss_category_max", "target": 1, "description": "Defeat a boss."},
	{"id": "a4", "title": "One Million Spent", "metric": "credits_spent", "target": 1000000, "description": "Spend 1,000,000 credits. Mithril does not count."},
	{"id": "a5", "title": "Ten Million Spent", "metric": "credits_spent", "target": 10000000, "description": "Spend 10,000,000 credits. Mithril does not count."},
	{"id": "a6", "title": "Blacksmith", "metric": "full_upgrades", "target": 1, "description": "Upgrade a Star Warfare weapon to level 8."},
	{"id": "a7", "title": "Weapon Specialist", "metric": "full_upgrades", "target": 5, "description": "Fully upgrade five different Star Warfare weapons."},
	{"id": "a8", "title": "One Suit", "metric": "suits_collected", "target": 1, "description": "Own all four armor pieces of one Star Warfare suit."},
	{"id": "a9", "title": "Suit Collector", "metric": "suits_collected", "target": 7, "description": "Own seven full Star Warfare suits. Backpacks are not required."},
	{"id": "a10", "title": "Once Co-op", "metric": "multiplayer_sessions", "target": 1, "description": "Start a multiplayer match, including VS."},
	{"id": "a11", "title": "Team Work", "metric": "team_kills", "target": 50, "description": "Receive credit for 50 alien kills in multiplayer."},
	{"id": "a12", "title": "Seal Team VI", "metric": "team_kills", "target": 500, "description": "Receive credit for 500 alien kills in multiplayer."},
	{"id": "a13", "title": "Combo", "metric": "max_combo", "target": 1, "description": "Start a kill chain with your first alien kill."},
	{"id": "a14", "title": "First Level", "metric": "campaign_first", "target": 1, "description": "Clear sector 1, mission 5."},
	{"id": "a15", "title": "Three Levels", "metric": "campaign_third", "target": 1, "description": "Clear sector 3, mission 5."},
	{"id": "a16", "title": "Five Levels", "metric": "campaign_fifth", "target": 1, "description": "Clear sector 5, mission 5."},
	{"id": "a17", "title": "Ghost", "metric": "flawless_wins", "target": 1, "description": "Win a PvE run without taking a hit."},
	{"id": "a18", "title": "Rebirth", "metric": "revivals", "target": 1, "description": "Successfully use a revival."},
	{"id": "a19", "title": "Phoenix", "metric": "revivals", "target": 100, "description": "Successfully use 100 revivals."},
	{"id": "a20", "title": "Monster Killer", "metric": "max_combo", "target": 10, "description": "Reach a chain of 10 alien kills."},
	{"id": "a21", "title": "Over Heated", "metric": "max_combo", "target": 50, "description": "Reach a chain of 50 alien kills."},
	{"id": "a22", "title": "Boss Hunter", "metric": "boss_category_max", "target": 10, "description": "Defeat 10 bosses in the same boss category."},
	{"id": "a23", "title": "Boss Veteran", "metric": "boss_category_max", "target": 100, "description": "Defeat 100 bosses in the same boss category."},
]

var _stats: Dictionary = DEFAULT_STATS.duplicate(true)
var _boss_kills: Array[int] = [0, 0, 0]
var _best_scores: Dictionary = {}
var _full_weapon_ids: Dictionary = {}
var _unlocked: Dictionary = {}


func serialize() -> Dictionary:
	var completed: Array[String] = []
	for definition: Dictionary in ACHIEVEMENTS:
		if is_unlocked(definition.id):
			completed.append(definition.id)
	return {"version": SCHEMA_VERSION, "stats": _stats.duplicate(true),
		"boss_kills": _boss_kills.duplicate(), "best_scores": _best_scores.duplicate(true),
		"full_weapon_ids": _full_weapon_ids.keys(), "unlocked": completed}


## Replaces all data, including on missing/corrupt input. Loading never emits unlocks.
func load_data(data: Variant) -> void:
	_stats = DEFAULT_STATS.duplicate(true)
	_boss_kills.assign([0, 0, 0])
	_best_scores.clear()
	_full_weapon_ids.clear()
	_unlocked.clear()
	if data is Dictionary:
		var stored_stats: Variant = data.get("stats", {})
		if stored_stats is Dictionary:
			for key: String in DEFAULT_STATS:
				_stats[key] = _counter(stored_stats.get(key, 0))
		var bosses: Variant = data.get("boss_kills", [])
		if bosses is Array:
			for index in range(mini(3, bosses.size())):
				_boss_kills[index] = _counter(bosses[index])
		_read_scores(data.get("best_scores", {}))
		var weapons: Variant = data.get("full_weapon_ids", [])
		if weapons is Array:
			for weapon_id: Variant in weapons:
				if _is_source_weapon(weapon_id):
					_full_weapon_ids[weapon_id] = true
		var completed: Variant = data.get("unlocked", [])
		if completed is Array:
			for definition: Dictionary in ACHIEVEMENTS:
				if completed.has(definition.id):
					_unlocked[definition.id] = true
	_stats.full_upgrades = maxi(int(_stats.full_upgrades), _full_weapon_ids.size())
	_evaluate(false)
	changed.emit()


## Pass the full parent save. Old saves only prove ownership/upgrades/best scores;
## credits, XP and unlocked_level cannot prove historic spending, kills or wins.
func load_save_section(save: Dictionary) -> void:
	load_data(save.get("career_progress", {}))
	if not save.get("career_progress") is Dictionary or save.career_progress.is_empty():
		initialize_from_legacy_save(save)


func initialize_from_legacy_save(save: Dictionary) -> void:
	_read_scores(save.get("best_scores", {}))
	var armor: Variant = save.get("owned_armor", [])
	var levels: Variant = save.get("weapon_levels", {})
	# GameState normalizes older per-part armor saves before this call.
	sync_inventory(armor if armor is Array else [], levels if levels is Dictionary else {}, false)


## Call after GameState normalizes ownership and after a successful armor purchase.
## Only the four SW1 pieces count, matching UserState.OwnedSuitCount().
func sync_inventory(owned_armor: Array, weapon_levels: Dictionary, notify_unlocks := true) -> void:
	var suits := 0
	for set_id in range(SOURCE_SUIT_COUNT):
		var complete := true
		for part: String in ["head", "body", "arms", "legs"]:
			if not owned_armor.has("armor_%s_%02d" % [part, set_id]):
				complete = false
				break
		if complete:
			suits += 1
	_stats.suits_collected = suits
	for weapon_id: Variant in weapon_levels:
		if _is_source_weapon(weapon_id) and _counter(weapon_levels[weapon_id]) >= SOURCE_MAX_WEAPON_LEVEL:
			_full_weapon_ids[weapon_id] = true
	_stats.full_upgrades = maxi(int(_stats.full_upgrades), _full_weapon_ids.size())
	_evaluate(notify_unlocks)
	changed.emit()


## One credited alien kill, not a teammate's duplicate broadcast or a VS player kill.
func record_enemy_kill(multiplayer := false) -> void:
	_increment("enemy_kills")
	if multiplayer:
		_increment("team_kills")
	_commit()


## Mantis=0; Spider/Beetle, Earthworm, SatanMachine=1; Dragon=2.
## Source CoopMantis/MainMantis/AssistMantis have no KillBoss call: do not guess.
func record_boss_kill(source_category: int) -> bool:
	if source_category < 0 or source_category >= _boss_kills.size():
		return false
	_boss_kills[source_category] = mini(MAX_COUNTER, _boss_kills[source_category] + 1)
	_commit()
	return true


func record_max_combo(value: int) -> void:
	if value <= int(_stats.max_combo):
		return
	_stats.max_combo = mini(value, MAX_COUNTER)
	_commit()


## Actual credit debit only. UserState.BuyWithMithril never called WasteMoney.
## Record before the parent's atomic save; restore serialize() snapshot on failure.
func record_spend(credits_paid: int) -> bool:
	if credits_paid <= 0:
		return false
	_increment("credits_spent", credits_paid)
	_commit()
	return true


## Notify only when a source weapon reaches LV8. Repeated notices are idempotent.
func record_full_upgrade(weapon_id: String) -> bool:
	if not _is_source_weapon(weapon_id) or _full_weapon_ids.has(weapon_id):
		return false
	_full_weapon_ids[weapon_id] = true
	_increment("full_upgrades")
	_commit()
	return true


func record_revival() -> void:
	_increment("revivals")
	_commit()


## GameWorld.cs:330 calls OnceCoop for IsMultiPlayer, including VS.
func record_multiplayer_start() -> void:
	_increment("multiplayer_sessions")
	_commit()


## One finished run; BattleProgress.finish guards duplicate result callbacks.
## Required: won:bool. Optional: score, kills, max_combo, level_key, never_hit,
## pve (defaults false), multiplayer, source_stage/source_substage (zero based).
## Kill totals are recorded live and MUST NOT be added again at settlement.
func record_run(result: Dictionary) -> bool:
	if not result.get("won") is bool:
		return false
	var score := _counter(result.get("score", 0))
	_stats.high_score = maxi(int(_stats.high_score), score)
	_stats.high_kills = maxi(int(_stats.high_kills), _counter(result.get("kills", 0)))
	_stats.max_combo = maxi(int(_stats.max_combo), _counter(result.get("max_combo", 0)))
	var key: Variant = result.get("level_key", "")
	if key is String and not key.is_empty():
		_best_scores[key] = maxi(int(_best_scores.get(key, 0)), score)
	if result.won:
		_increment("wins")
		if result.get("pve") == true and result.get("never_hit") == true:
			_increment("flawless_wins")
		# StatisticsUI.Exit increments subStage then compares with 6 - 1:
		# only the just-cleared source substage 4 at stage 0/2/4 grants these.
		if result.get("pve") == true and result.get("multiplayer", false) == false:
			var stage: Variant = result.get("source_stage", -1)
			var substage: Variant = result.get("source_substage", -1)
			if _is_nonnegative_integer(stage) and _is_nonnegative_integer(substage) and int(substage) == 4:
				var milestones := {0: "campaign_first", 2: "campaign_third", 4: "campaign_fifth"}
				if milestones.has(int(stage)):
					_stats[milestones[int(stage)]] = 1
	else:
		_increment("losses")
	_commit()
	return true


func get_statistics() -> Dictionary:
	var result := _stats.duplicate(true)
	result.boss_kills = _boss_kills.duplicate()
	result.best_scores = _best_scores.duplicate(true)
	result.achievements_completed = _unlocked.size()
	result.achievements_total = ACHIEVEMENTS.size()
	return result


func get_achievements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in ACHIEVEMENTS:
		var row := definition.duplicate(true)
		row.current = _metric(row.metric)
		row.complete = is_unlocked(row.id)
		row.progress = 1.0 if row.complete else minf(1.0, float(row.current) / float(row.target))
		result.append(row)
	return result


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)


func _commit() -> void:
	_evaluate(true)
	changed.emit()


func _evaluate(notify_unlocks: bool) -> void:
	for definition: Dictionary in ACHIEVEMENTS:
		if not _unlocked.has(definition.id) and _metric(definition.metric) >= int(definition.target):
			_unlocked[definition.id] = true
			if notify_unlocks:
				achievement_unlocked.emit(definition.id)


func _metric(key: String) -> int:
	if key == "boss_category_max":
		return maxi(_boss_kills[0], maxi(_boss_kills[1], _boss_kills[2]))
	return int(_stats.get(key, 0))


func _increment(key: String, amount := 1) -> void:
	_stats[key] = int(_stats[key]) + mini(amount, MAX_COUNTER - int(_stats[key]))


func _read_scores(scores: Variant) -> void:
	if not scores is Dictionary:
		return
	for key: Variant in scores:
		if key is String and not key.is_empty() and _is_nonnegative_integer(scores[key]):
			var value := _counter(scores[key])
			_best_scores[key] = maxi(int(_best_scores.get(key, 0)), value)
			_stats.high_score = maxi(int(_stats.high_score), value)


static func _is_source_weapon(value: Variant) -> bool:
	if not value is String:
		return false
	for index in range(SOURCE_WEAPON_COUNT):
		if value == "gun%02d" % index:
			return true
	return false


static func _is_nonnegative_integer(value: Variant) -> bool:
	return (value is int and value >= 0) or (value is float and is_finite(value) and value >= 0.0 and value == floor(value))


static func _counter(value: Variant) -> int:
	if not _is_nonnegative_integer(value):
		return 0
	return int(min(value, MAX_COUNTER))
