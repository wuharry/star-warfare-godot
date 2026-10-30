class_name MatchRules
extends RefCounted
## Pure, host-owned rules. No profile, SceneTree, RPC or wall-clock dependency.
## Source: GameMode.cs, Global.cs, PlayerVSStatistics.cs, CMIConfig.cs,
## CatchTheFlagResponse.cs, DropTheFlagResponse.cs, GetTheFlagScoreResponse.cs,
## SendPlayerVIPResponse.cs, SecureVIPPlayerResponse.cs, EnemySpawnScript.cs.
## Server matchmaking/limits were not shipped: LAN limits are configurable.

const MODES := ["Survival", "Boss", "VS_FFA", "VS_TDM", "CTF_FFA", "CTF_TDM", "VIP", "CMI"]
const TEAM_MODES := ["VS_TDM", "CTF_TDM", "VIP", "CMI"]
const FLAG_SECONDS := 40.0
const VIP_SECONDS := 50.0
const RESPAWN_SECONDS := 11.0
const DEATH_SECONDS := 4.0
const REVIVE_SECONDS := 5.0
const GIFT_HP := [5.0, 10.0, 20.0, 20.0, 20.0]
const GIFT_SCORE := [5, 10, 25, 50, 0]
const BOSS_TYPES := ["Dragon", "Mantis", "Beetle", "MainMantis", "Earthworm", "SantaMachine"]
const BOSS_SOURCE_IDS := [10, 9, 8, 11, 13, 14]

var config: Dictionary = {}
var players: Dictionary = {}
var team_scores := {0: 0, 1: 0}
var elapsed := 0.0
var ended := false
var result: Dictionary = {}
var flag_carrier := 0
var last_flag_team := -1
var flag_left := FLAG_SECONDS
var flag_position := Vector3.ZERO
var flag_home := Vector3.ZERO
var flag_respawn := 0.0
var vip_id := 0
var vip_left := VIP_SECONDS
var vip_cursor := -1
var wave := 0

static func is_coop(mode: String) -> bool:
	return mode in ["Survival", "Boss"]

static func is_team(mode: String) -> bool:
	return mode in TEAM_MODES

# VSMath.cs; applied after source equipment bonuses, before victim defence.
static func vs_health(hp: float) -> float:
	return float(int(pow(maxf(0.0, hp), 0.65) / 2.0 + 300.0))

static func vs_damage(damage: float, kind: String) -> float:
	var boost := float({"machinegun": 1.37, "arrow": 1.2, "grenade": 2.4, "sword": 2.0,
		"rocket": 1.3, "sniper": 4.0, "reflection": 4.0, "tracking": 1.3,
		"ricochet": 1.9, "fly_grenade": 0.6}.get(kind, 1.0))
	return pow(maxf(0.0, damage), 0.3) * 10.0 * boost

static func description(mode: String) -> String:
	match mode:
		"Survival": return TranslationServer.translate("Survive endless waves together. All players down ends the run; difficulty rises every 13 rounds.")
		"Boss": return TranslationServer.translate("Defeat the boss together. All players down means defeat.")
		"VS_FFA": return TranslationServer.translate("Free for all: +50 per kill. Four-second death animation, then an 11-second respawn timer.")
		"VS_TDM": return TranslationServer.translate("Team deathmatch: +40 per kill; friendly fire is disabled.")
		"CTF_FFA": return TranslationServer.translate("Hold the single flag for 40 seconds to score 100. A new carrier gets at least 10 seconds.")
		"CTF_TDM": return TranslationServer.translate("Team flag hold: allies continue the timer; opponents reset it to 40 seconds. Secure for +100.")
		"VIP": return TranslationServer.translate("Protect the VIP for 50 seconds: +100. Kill the enemy VIP: +150. The next VIP then rotates.")
		"CMI": return TranslationServer.translate("Shoot gifts: small/medium/large score +5/+10/+25; mystery gifts score +50 or 0.")
	return ""

static func normalized_config(raw: Dictionary) -> Dictionary:
	var mode := str(raw.get("mode", "VS_FFA"))
	if mode not in MODES:
		mode = "VS_FFA"
	var maps := range(1, 9) if is_coop(mode) else range(13, 22)
	var level := int(raw.get("level", maps[0]))
	if level not in maps:
		level = maps[0]
	return {
		"mode": mode, "level": level,
		"boss_index": clampi(int(raw.get("boss_index", 0)), 0, 5),
		# UIConstant.PLAYER_NUM_COOP exposes exactly 1/2/3 players.
		"max_players": clampi(int(raw.get("max_players", 3 if is_coop(mode) else 8)), 1 if is_coop(mode) else 2, 3 if is_coop(mode) else 8),
		"time_limit": clampi(int(raw.get("time_limit", 600)), 60, 3600),
		"score_limit": clampi(int(raw.get("score_limit", 1000)), 100, 10000),
		"room_name": str(raw.get("room_name", "LAN ROOM")).strip_edges().left(40),
	}

func begin(room_config: Dictionary, roster: Dictionary) -> void:
	config = normalized_config(room_config)
	players.clear()
	for id: int in roster:
		players[id] = {"team": int(roster[id].team), "name": str(roster[id].name),
			"score": 0, "kills": 0, "deaths": 0, "alive": true, "respawn": 0.0, "boost": 0.0,
			"revive_eligible": false, "revive_left": 0.0, "death_elapsed": 0.0}
	team_scores = {0: 0, 1: 0}
	elapsed = 0.0
	ended = false
	result = {}
	flag_carrier = 0
	last_flag_team = -1
	flag_left = FLAG_SECONDS
	flag_respawn = 0.0
	vip_cursor = -1
	vip_id = 0
	wave = 0
	if config.mode == "VIP":
		choose_vip()

func can_damage(attacker: int, victim: int) -> bool:
	if ended or attacker == victim or not players.has(attacker) or not players.has(victim):
		return false
	if not players[attacker].alive or not players[victim].alive or is_coop(config.mode):
		return false
	return not is_team(config.mode) or players[attacker].team != players[victim].team

func add_score(id: int, amount: int) -> void:
	if ended or not players.has(id) or amount <= 0:
		return
	players[id].score += amount
	if is_team(config.mode):
		team_scores[int(players[id].team)] += amount
	if not is_coop(config.mode):
		var current := int(team_scores[int(players[id].team)]) if is_team(config.mode) else int(players[id].score)
		if current >= int(config.score_limit):
			finish("score_limit")

func player_died(victim: int, killer: int, position: Vector3, revival_available := false) -> void:
	if ended or not players.has(victim) or not players[victim].alive:
		return
	# Validate the kill before setting alive=false (can_damage checks both).
	var valid_kill := can_damage(killer, victim)
	players[victim].alive = false
	players[victim].deaths += 1
	players[victim].death_elapsed = 0.0
	players[victim].revive_eligible = revival_available
	players[victim].revive_left = DEATH_SECONDS + REVIVE_SECONDS if revival_available else 0.0
	players[victim].respawn = 0.0 if is_coop(config.mode) else DEATH_SECONDS + RESPAWN_SECONDS + (REVIVE_SECONDS if revival_available else 0.0)
	if flag_carrier == victim:
		drop_flag(position)
	if valid_kill:
		players[killer].kills += 1
		match config.mode:
			"VS_FFA": add_score(killer, 50)
			"VS_TDM": add_score(killer, 40)
			"VIP":
				if victim == vip_id:
					add_score(killer, 150)
	if config.mode == "VIP" and victim == vip_id and not ended:
		choose_vip()

func can_revive(id: int) -> bool:
	if ended or not players.has(id): return false
	var row: Dictionary = players[id]
	return not bool(row.alive) and bool(row.get("revive_eligible", false)) and float(row.get("death_elapsed", 0.0)) >= DEATH_SECONDS and float(row.get("revive_left", 0.0)) > 0.0

func complete_revival(id: int) -> bool:
	if not can_revive(id): return false
	players[id].alive = true
	players[id].respawn = 0.0
	players[id].revive_eligible = false
	players[id].revive_left = 0.0
	players[id].death_elapsed = 0.0
	return true

func _check_coop_defeat() -> void:
	if not is_coop(config.mode) or ended: return
	for row: Dictionary in players.values():
		if bool(row.alive): return
		if float(row.get("death_elapsed", 0.0)) < DEATH_SECONDS: return
		if bool(row.get("revive_eligible", false)) and float(row.get("revive_left", 0.0)) > 0.0: return
	finish("squad_eliminated", false)

func pick_flag(id: int) -> bool:
	if ended or config.mode not in ["CTF_FFA", "CTF_TDM"] or flag_carrier != 0 or flag_respawn > 0.0:
		return false
	if not players.has(id) or not players[id].alive:
		return false
	if config.mode == "CTF_TDM":
		if last_flag_team != int(players[id].team):
			flag_left = FLAG_SECONDS
	else:
		flag_left = maxf(10.0, flag_left)
	flag_carrier = id
	last_flag_team = int(players[id].team)
	return true

func drop_flag(position: Vector3) -> void:
	flag_position = position
	flag_carrier = 0

func choose_vip() -> void:
	var ids: Array = players.keys()
	ids.sort()
	if ids.is_empty():
		vip_id = 0
		return
	# The original server chose the VIP; deterministic rotation is the LAN policy.
	vip_cursor = (vip_cursor + 1) % ids.size()
	vip_id = int(ids[vip_cursor])
	vip_left = VIP_SECONDS
	players[vip_id].alive = true
	players[vip_id].respawn = 0.0
	players[vip_id].revive_eligible = false
	players[vip_id].revive_left = 0.0

func tick(delta: float) -> Array[int]:
	var revived: Array[int] = []
	if ended:
		return revived
	elapsed += maxf(delta, 0.0)
	for id: int in players:
		players[id].boost = maxf(0.0, float(players[id].boost) - delta)
		if not players[id].alive:
			players[id].death_elapsed = float(players[id].get("death_elapsed", 0.0)) + delta
			players[id].revive_left = maxf(0.0, float(players[id].get("revive_left", 0.0)) - delta)
		if not players[id].alive and not is_coop(config.mode):
			players[id].respawn = maxf(0.0, float(players[id].respawn) - delta)
			if players[id].respawn <= 0.0:
				players[id].alive = true
				players[id].revive_eligible = false
				players[id].revive_left = 0.0
				revived.append(id)
	_check_coop_defeat()
	if ended: return revived
	flag_respawn = maxf(0.0, flag_respawn - delta)
	if flag_carrier != 0:
		flag_left = maxf(0.0, flag_left - delta)
		if flag_left <= 0.0:
			var carrier := flag_carrier
			add_score(carrier, 100)
			for id: int in players:
				if id == carrier or (config.mode == "CTF_TDM" and players[id].team == players[carrier].team):
					players[id].boost = 10.0
			flag_carrier = 0
			last_flag_team = -1
			flag_left = FLAG_SECONDS
			flag_position = flag_home
			flag_respawn = 3.0
	if config.mode == "VIP" and vip_id != 0:
		vip_left = maxf(0.0, vip_left - delta)
		if vip_left <= 0.0:
			add_score(vip_id, 100)
			if not ended:
				choose_vip()
	if not is_coop(config.mode) and elapsed >= float(config.time_limit):
		finish("time_limit")
	return revived

func damage_multiplier(id: int) -> float:
	if not players.has(id) or float(players[id].boost) <= 0.0:
		return 1.0
	return 1.5 if config.mode == "CTF_TDM" else 2.0

func enemy_killed(killer: int, boss: bool) -> void:
	if ended or not is_coop(config.mode):
		return
	if players.has(killer):
		players[killer].kills += 1
		add_score(killer, 100)
	if config.mode == "Boss" and boss:
		finish("boss_defeated", true)

func gift_destroyed(killer: int, kind: int) -> void:
	if config.mode == "CMI" and kind >= 0 and kind < GIFT_SCORE.size():
		add_score(killer, GIFT_SCORE[kind])

func remove_player(id: int, position: Vector3 = Vector3.ZERO) -> void:
	if not players.has(id):
		return
	if flag_carrier == id:
		drop_flag(position)
	players.erase(id)
	if ended:
		return
	if vip_id == id:
		choose_vip()
	if is_coop(config.mode):
		_check_coop_defeat()
	elif players.size() < 2:
		finish("opponent_left")
	elif is_team(config.mode):
		var teams := {}
		for row: Dictionary in players.values():
			teams[int(row.team)] = true
		if teams.size() < 2:
			finish("opponent_left")

func finish(reason: String, coop_win := false) -> void:
	if ended:
		return
	ended = true
	var winners: Array[int] = []
	var best := -1
	if is_coop(config.mode):
		if coop_win:
			winners.assign(players.keys())
	else:
		for id: int in players:
			var value := int(team_scores[int(players[id].team)]) if is_team(config.mode) else int(players[id].score)
			if reason == "opponent_left":
				value = 1
			if value > best:
				best = value
				winners.clear()
			if value == best:
				winners.append(id)
	var draw := false
	if not is_coop(config.mode) and reason != "opponent_left":
		draw = team_scores[0] == team_scores[1] if is_team(config.mode) else winners.size() > 1
	result = {"reason": reason, "winners": winners, "draw": draw, "coop_win": coop_win}

func snapshot() -> Dictionary:
	return {"players": players.duplicate(true), "team_scores": team_scores.duplicate(),
		"elapsed": elapsed, "ended": ended, "result": result.duplicate(true),
		"flag_carrier": flag_carrier, "flag_left": flag_left, "flag_position": flag_position,
		"flag_respawn": flag_respawn, "vip_id": vip_id, "vip_left": vip_left, "wave": wave}
