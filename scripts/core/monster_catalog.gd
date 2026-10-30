extends RefCounted

const Source = preload("res://scripts/core/recovered_game_data.gd")
# Preserve the restoration's four legacy aliases for existing saves/tests.
# Numeric spawns use GameWorld.GetEnemyTypeID's separate prefab pool mapping.
const RUNTIME_IDS := {"crawler": 0, "spitter": 2, "brute": 3, "boss": 10}
const RUNTIME_MODELS := {"crawler": "bug01", "spitter": "bug03", "brute": "bug04", "boss": "boss01"}

# Identity/model bindings come from GameWorld.SpawnEnemy/CreateBoss, not enum
# names (Beetle is implemented by Spider; SantaMachine by SatanMachine).
const KINDS := ["drone", "zergling", "scorpion", "boomer", "tank", "reaver", "mutalisk", "worm", "beetle", "mantis", "dragon", "main_mantis", "assist_mantis", "earthworm", "santa_machine"]
const MODELS := ["bug01", "bug02", "bug03", "bug07", "bug08", "bug05", "bug04", "bug06", "boss03", "boss02", "boss01", "boss02", "boss02-1", "boss05", "boss06"]
const PREFAB_POOL_INDICES := [0, 1, 2, 6, 7, 4, 3, 5]
const ELITE_IDS := [0, 1, 2, 5, 6, 7]
const IMPLEMENTATIONS := ["Drone.cs", "Zergling.cs", "Scorpion.cs", "Boomer.cs", "Tank.cs", "Reaver.cs", "Mutalisk.cs", "Worm.cs", "Spider.cs", "Mantis.cs", "Dragon.cs", "MainMantis.cs", "AssistMantis.cs", "Earthworm.cs", "SatanMachine.cs"]
const NORMAL_REACH := [2.5, 2.8, 18.0, 2.5, 5.0, 20.0, 25.0, 4.5]
const VOICES := ["gongchong", "gaosuchong", "xeiweichong", "zibaochong", "daxingjiachong", "jinjiachong", "feixingchong", "luntaichong_juansuo"]
const BOSS_VOICES := {8: "spider/juxingjiachong", 9: "mantis/feixingtanglang_gongjiqian", 10: "dragon/long_housheng_2", 11: "mantis/feixingtanglang_gongjiqian", 12: "mantis/feixingtanglang_gongjiqian", 13: "earthworm/rage", 14: "satanmachine/xiaochouxiaosheng"}
# OnDead(): Mantis=0 (also both CoopMantis subclasses), Spider/Earthworm/
# SatanMachine=1, Dragon=2. AchievementState has three counters, not six.
const ACHIEVEMENT_BOSS_CATEGORIES := {8: 1, 9: 0, 10: 2, 11: 0, 12: 0, 13: 1, 14: 1}
# loadParameters() overrides the table's HP for every boss. Keep get_monster()
# as the raw table API so existing four-kind fixtures retain their contract.
const BOSS_PARAMETERS := {
	8: {"hp": 108000.0, "speed": 12.0, "attack_range": 6.0, "damage": 2200.0, "rage_loss": 0.60, "actions": ["double_attack", "spit", "continuous_spit", "poison_trail", "rush", "jump"]},
	9: {"hp": 36000.0, "speed": 12.0, "attack_range": 8.0, "damage": 1000.0, "rage_loss": 0.60, "actions": ["ground_slash", "fly_slash", "dive", "laser", "boomerang", "shot"]},
	10: {"hp": 360000.0, "speed": 12.0, "attack_range": 10.0, "damage": 3500.0, "rage_loss": 0.60, "actions": ["bite", "pounce", "ground_shot", "flame", "takeoff", "fly_shot", "fly_flame", "dive", "rush", "landing", "rage"]},
	11: {"hp": 180000.0, "speed": 12.0, "attack_range": 8.0, "damage": 2000.0, "rage_loss": 0.40, "actions": ["paired_dive", "paired_laser", "defend", "partner_death_rage"]},
	12: {"hp": 80000.0, "speed": 12.0, "attack_range": 8.0, "damage": 2000.0, "rage_loss": 0.60, "actions": ["assist_shot", "assist_boomerang", "assist_laser", "partner_death_rage"]},
	13: {"hp": 440000.0, "speed": 16.0, "attack_range": 14.0, "damage": 6400.0, "rage_loss": 0.45, "actions": ["tail_slash", "spit", "slowing_slime", "rush", "drill_in", "drill_out", "super_rush"]},
	14: {"hp": 1200000.0, "speed": 9.0, "attack_range": 15.0, "damage": 10000.0, "rage_loss": [0.2, 0.4, 0.6, 0.8], "actions": ["stomp", "whirl", "missiles", "laser", "gift_bombs", "throw_ball"]},
}
const ENCOUNTERS := [
	{"key": "dragon", "monster_ids": [10], "source_boss_index": 0, "arena_source": "level/Boss1"},
	{"key": "mantis", "monster_ids": [9], "source_boss_index": 1, "arena_source": "level/Boss2"},
	{"key": "beetle", "monster_ids": [8], "source_boss_index": 2, "arena_source": "level/Boss3"},
	{"key": "twin_mantis", "monster_ids": [11, 12], "source_boss_index": 3, "arena_source": "level/Boss4"},
	{"key": "earthworm", "monster_ids": [13], "source_boss_index": 4, "arena_source": "level/Boss5"},
	{"key": "santa_machine", "monster_ids": [14], "source_boss_index": 5, "arena_source": "level/Boss6"},
]


static func get_monster(monster_id: int) -> Dictionary:
	if monster_id < 0 or monster_id >= Source.MONSTER_ROWS.size():
		return {}
	var row: Array = Source.MONSTER_ROWS[monster_id]
	var attacks: Array = Source.ATTACK_TABLES[int(row[3]) - 1]
	return {
		"id": monster_id, "name": str(row[0]), "hp": float(row[1]),
		"source_enemy_type": monster_id, "table_row_id": monster_id,
		"source_prefab_pool_index": PREFAB_POOL_INDICES[monster_id] if monster_id < 8 else -1,
		"achievement_boss_category": int(ACHIEVEMENT_BOSS_CATEGORIES.get(monster_id, -1)),
		"speed": float(row[2]), "experience": int(row[4]), "credits": int(row[5]),
		"attacks": attacks.duplicate(true),
	}


static func for_kind(kind: String) -> Dictionary:
	return get_monster(id_for_kind(kind))


static func id_for_kind(kind: String) -> int:
	return int(RUNTIME_IDS[kind]) if RUNTIME_IDS.has(kind) else KINDS.find(kind)


static func model_path(monster_id: int) -> String:
	if monster_id < 0 or monster_id >= MODELS.size():
		return ""
	return "res://assets/models/enemies/animated/%s/%s.gltf" % [MODELS[monster_id], MODELS[monster_id]]


static func attack_data(row: Array) -> Dictionary:
	return {"name": str(row[0]), "damage": float(row[1]), "interval": float(row[2]),
		"range": float(row[3]), "bomb_radius": float(row[4]), "splash_damage": float(row[5]),
		"splash_duration": float(row[6]) / 10.0, "splash_radius": float(row[7]), "speed": float(row[8])}


## Offline source rules. difficulty_level is Unity's wave/level index, NOT the
## restoration's recruit/veteran/elite setting. Extra health_scale is applied by
## the caller; do not also multiply by these source coefficients in GameWorld.
static func runtime_spec(monster_id: int, difficulty_level := 0, is_elite := false) -> Dictionary:
	var data := get_monster(monster_id)
	if data.is_empty():
		return {}
	data["kind"] = KINDS[monster_id]
	data["model"] = MODELS[monster_id]
	data["model_path"] = model_path(monster_id)
	data["source"] = IMPLEMENTATIONS[monster_id]
	data["is_boss"] = BOSS_PARAMETERS.has(monster_id)
	data["elite_requested"] = is_elite
	data["elite"] = is_elite and monster_id in ELITE_IDS
	data["elite_available"] = monster_id in ELITE_IDS
	data["behavior_available"] = true
	data["visual_available"] = ResourceLoader.exists(data.model_path)
	# Source spawning excludes Boomer/Tank from elites. Actual elite prefabs use
	# their original materials; no recolouring or unrelated mesh substitution.
	if data.elite:
		data.model_path = "res://assets/models/enemies/animated/%s_elite/%s_elite.gltf" % [MODELS[monster_id], MODELS[monster_id]]
		data.visual_available = ResourceLoader.exists(data.model_path)
	data["spawnable"] = data.visual_available and data.behavior_available
	data["blockers"] = []
	if not data.visual_available:
		data.blockers.append("missing_model:" + data.model_path)
	if not data.behavior_available:
		data.blockers.append("boss_state_machine_not_ported:" + data.source)
	data["presentation_gaps"] = ["procedural_projectile_and_attack_effects", "analytical_attack_geometry_in_place_of_unity_bone_colliders"]
	if monster_id == 6 and data.elite:
		data.presentation_gaps.append("source_elite_missing_clip_targets:Bone_tail_07,Bone_R_Down03;removed_tail_06_frame_baked_into_children")
	data["elite_exclusion_reason"] = "GameWorld.SpawnEnemy excludes Boomer/Tank" if is_elite and monster_id in [3, 4] else ""
	data["attack_profiles"] = []
	for row: Array in data.attacks:
		data.attack_profiles.append(attack_data(row))
	if data.is_boss:
		data.merge(BOSS_PARAMETERS[monster_id].duplicate(true), true)
		data["voice"] = "res://assets/original/audio/enemy/%s.wav" % BOSS_VOICES[monster_id]
		data.credits = int(float(data.credits) * 0.75) # Enemy.LoadConfig single-player reward.
		return data
	var hp_factor := 1.0
	var damage_factor := 1.0
	var cash := float(data.credits)
	var xp := float(data.experience)
	for index in range(maxi(0, difficulty_level)):
		hp_factor = minf(80.0, hp_factor * maxf(1.1, 1.25 - index * 0.01))
		damage_factor = minf(70.0, damage_factor * minf(1.25, 1.1 + index * 0.01))
		cash *= 1.07
		xp *= 1.1
	data.hp = int(float(data.hp) * hp_factor) * (3 if data.elite else 1)
	data.speed = float(data.speed) + (2.0 if data.elite else 0.0)
	data.credits = int(cash * (3.0 if data.elite else 1.0))
	data.experience = int(xp * (3.0 if data.elite else 1.0))
	for index in range(data.attack_profiles.size()):
		# Tank.Init doubles its normal attack, but deliberately NOT rushDamage.
		var elite_multiplier := 2 if data.elite and (monster_id != 4 or index == 2) else 1
		data.attack_profiles[index].damage = int(float(data.attack_profiles[index].damage) * damage_factor) * elite_multiplier
	var main_attack: Dictionary = data.attack_profiles[2 if monster_id == 4 else 0]
	data["damage"] = main_attack.damage
	data["attack_range"] = NORMAL_REACH[monster_id]
	data["attack_interval"] = main_attack.interval
	data["voice"] = "res://assets/original/audio/enemy/%s.wav" % VOICES[monster_id]
	return data


## Catalog only, not invented wave weights. Pass actual source spawn IDs from
## the level/survival spawner; missing entries remain visible with blockers.
static func normal_entries(only_spawnable := false) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for monster_id in range(8):
		var entry := runtime_spec(monster_id)
		if not only_spawnable or entry.spawnable:
			entries.append(entry)
	return entries


static func boss_encounters() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for definition: Dictionary in ENCOUNTERS:
		var entry := definition.duplicate(true)
		entry["members"] = []
		entry["blockers"] = []
		for monster_id: int in entry.monster_ids:
			var member := runtime_spec(monster_id)
			entry.members.append(member)
			entry.blockers.append_array(member.blockers)
		entry["arena_directory"] = "res://assets/models/boss_arenas/boss_%02d" % (int(entry.source_boss_index) + 1)
		entry["arena_path"] = str(entry.arena_directory) + "/level.json"
		entry["arena_available"] = FileAccess.file_exists(entry.arena_path)
		if not entry.arena_available: entry.blockers.append("missing_arena:" + str(entry.arena_path))
		entry["spawnable"] = entry.blockers.is_empty()
		entry["requires_all_members_dead"] = true
		entries.append(entry)
	return entries


## Source BossType index: Dragon=0, Mantis=1, Beetle=2, Twins=3, Worm=4, Santa=5.
static func boss_encounter(source_boss_index: int) -> Dictionary:
	if source_boss_index < 0 or source_boss_index >= ENCOUNTERS.size(): return {}
	return boss_encounters()[source_boss_index]
