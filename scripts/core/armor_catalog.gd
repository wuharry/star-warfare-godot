class_name ArmorCatalog
extends RefCounted

const Source = preload("res://scripts/core/recovered_game_data.gd")

# Recovered from Unity Resources/UI/resDataSets.bytes tables 14, 15 and 73-75.
# Armor rows: name, authored type, HP, attack%, speed*10, cash%, exp%,
# three advanced-skill row ids, set id, description token, unlock rank,
# bag slots, cash price, mithril price.
const PART_KEYS := ["head", "body", "arms", "legs", "bag"]
const PART_LABELS := ["HELMET", "BODY", "ARMS", "LEGS", "PACK"]
const SET_NAMES := [
	"Viper", "Fortune", "Tank", "Hydra", "Strike", "Titan", "Thunder",
	"Atom", "Pegasus", "Draco", "Phoenix", "Cygni", "Andromedae",
	"Perseus", "Chaos", "DEC.24", "Knight", "R.O.M.E", "Black Hole",
	"X-Field", "Wrath", "Assault Armor", "Combat Suit", "Drillmaster",
	"Heavy Battlesuit", "Mark-6 117R", "Recon Suit", "Sanguine Chaos", "Training Suit"
]

# Additional appearance sets retain Viper prices/stats; Unity IDs remain stable.
const CALLOFMINI_FIRST_ID := 21
const CALLOFMINI_MODELS := [
	"AssaultArmor", "CombatSuit", "Drillmaster", "HeavyBattlesuit",
	"Mark6117R", "ReconSuit", "Sanguine", "TrainingSuit"
]
const CALLOFMINI_GAMEPLAY_DIR := "res://assets/callOfMini/gameplay/"

const ARMOR_ROWS = Source.ARMOR_ROWS

# HP, attack%, speed*10, cash%, exp%, and three advanced-skill row ids.
const SET_BONUS_ROWS = Source.SET_BONUS_ROWS

const SKILL_ROWS = Source.SKILL_ROWS

const WEAPON_BOOST_ROWS = Source.WEAPON_BOOST_ROWS
const DEFENCE_ROWS = Source.DEFENCE_ROWS

const WEAPON_SKILL_KEYS := [
	"assault_boost", "shotgun_boost", "rpg_boost", "grenade_boost",
	"laser_boost", "laser_cannon_boost", "plasma_boost", "machine_boost",
	"bow_boost", "impulse_boost", "glove_boost", "sword_boost",
	"sniper_boost", "tracking_boost", "pingpong_boost"
]
const DEFENCE_SKILL_KEYS := [
	"assault_defence", "shotgun_defence", "rpg_defence", "grenade_defence",
	"laser_defence", "laser_cannon_defence", "plasma_defence", "machine_defence",
	"bow_defence", "impulse_defence", "glove_defence", "sword_defence",
	"sniper_defence", "tracking_defence", "pingpong_defence"
]
const POWER_SKILL_KEYS := [
	"", "power_up", "speed_up", "defence_up", "andromeda_up", "health_steal",
	"attack_shield", "impact_wave", "track_wave", "hurt_health", "gravity_force"
]

static func item_key(part: int, item_id: int) -> String:
	return "armor_%s_%02d" % [PART_KEYS[part], item_id]

static func build_items() -> Dictionary:
	var result := {}
	for row_index in range(ARMOR_ROWS.size()):
		var row: Array = ARMOR_ROWS[row_index]
		var part := 4 if row_index >= 84 else row_index % 4
		var item_id := row_index - 84 if part == 4 else int(row_index / 4)
		var skills := _base_skills(row, 2)
		var special_skill_ids: Array[int] = []
		for column in range(7, 10):
			var special_id := int(row[column])
			if special_id > 0:
				special_skill_ids.append(special_id)
			_add_advanced_skills(skills, special_id)
		var key := item_key(part, item_id)
		result[key] = {
			"key": key, "id": item_id, "part": part, "part_key": PART_KEYS[part],
			"source_row": row_index, "authored_type": int(row[1]),
			"name": str(row[0]), "set_id": int(row[10]),
			"unlock": int(row[12]), "bag_slots": int(row[13]),
			"price": int(row[14]), "mithril": int(row[15]), "skills": skills,
			"currency": "mithril" if int(row[15]) > 0 else "credits",
			"price_amount": int(row[15]) if int(row[15]) > 0 else int(row[14]),
			"special_skill_ids": special_skill_ids, "description_token": str(row[11]),
			"visual_id": item_id, "default_owned": item_id == 0
		}
	for index in range(CALLOFMINI_MODELS.size()):
		var set_id := CALLOFMINI_FIRST_ID + index
		for part in range(4):
			var key := item_key(part, set_id)
			var item: Dictionary = result[item_key(part, 0)].duplicate(true)
			item.merge({
				"key": key, "id": set_id, "visual_id": set_id, "set_id": set_id,
				"source_row": -1, "default_owned": false,
				"name": "%s %s" % [SET_NAMES[set_id], ["Head", "Chest", "Hands", "Legs"][part]],
				"appearance_source": "callofmini"
			}, true)
			result[key] = item
	return result

static func build_set_bonuses() -> Dictionary:
	var result := {}
	for set_id in range(SET_BONUS_ROWS.size()):
		var row: Array = SET_BONUS_ROWS[set_id]
		var skills := _base_skills(row, 0)
		for column in range(5, 8):
			_add_advanced_skills(skills, int(row[column]))
		result[set_id] = {"id": set_id, "name": SET_NAMES[set_id], "skills": skills}
	for set_id in range(CALLOFMINI_FIRST_ID, SET_NAMES.size()):
		result[set_id] = {"id": set_id, "name": SET_NAMES[set_id], "skills": empty_skills()}
	return result

static func gameplay_scene_path(visual_id: int) -> String:
	var index := visual_id - CALLOFMINI_FIRST_ID
	if index < 0 or index >= CALLOFMINI_MODELS.size():
		return ""
	return CALLOFMINI_GAMEPLAY_DIR + CALLOFMINI_MODELS[index] + ".scn"

static func empty_skills() -> Dictionary:
	var skills := {
		"hp": 0.0, "attack_boost": 0.0, "speed_boost": 0.0,
		"money_boost": 0.0, "exp_boost": 0.0, "save_energy": 0.0,
		"recovery_boost": 0.0, "hp_auto_recovery": 0.0,
		"hp_on_kill": 0.0, "damage_reduce": 0.0, "block_rate": 0.0,
		"team_hp_recovery": 0.0, "team_attack_boost": 0.0,
		"team_damage_reduce": 0.0, "unlimited_energy": 0.0, "fly": 0.0,
		"speed_on_hit": 0.0, "attack_frequency": 0.0
	}
	for key in WEAPON_SKILL_KEYS:
		skills[key] = 0.0
	for key in DEFENCE_SKILL_KEYS:
		skills[key] = 0.0
	for key in POWER_SKILL_KEYS:
		if not key.is_empty():
			skills[key] = 0.0
	return skills

static func merge_skills(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		target[key] = float(target.get(key, 0.0)) + float(source[key])

static func _base_skills(row: Array, start: int) -> Dictionary:
	var skills := empty_skills()
	skills.hp = float(row[start])
	skills.attack_boost = float(_signed_byte(int(row[start + 1]))) / 100.0
	skills.speed_boost = float(_signed_byte(int(row[start + 2]))) / 10.0
	skills.money_boost = float(_signed_byte(int(row[start + 3]))) / 100.0
	skills.exp_boost = float(_signed_byte(int(row[start + 4]))) / 100.0
	return skills

static func _add_advanced_skills(skills: Dictionary, skill_id: int) -> void:
	if skill_id <= 0 or skill_id >= SKILL_ROWS.size():
		return
	var row: Array = SKILL_ROWS[skill_id]
	_add(skills, "save_energy", float(_signed_byte(int(row[0]))) / 100.0)
	_add(skills, "hp_auto_recovery", float(_signed_byte(int(row[1]))))
	_add(skills, "hp_on_kill", float(_signed_byte(int(row[2]))))
	_add(skills, "recovery_boost", float(_signed_byte(int(row[3]))) / 100.0)
	var weapon_row := int(row[4])
	if weapon_row > 0 and weapon_row < WEAPON_BOOST_ROWS.size():
		for index in range(WEAPON_SKILL_KEYS.size()):
			_add(skills, WEAPON_SKILL_KEYS[index], float(_signed_byte(int(WEAPON_BOOST_ROWS[weapon_row][index]))) / 100.0)
	_add(skills, "block_rate", float(_signed_byte(int(row[5]))) / 100.0)
	_add(skills, "damage_reduce", float(_signed_byte(int(row[6]))) / 100.0)
	_add(skills, "team_hp_recovery", float(_signed_byte(int(row[7]))))
	_add(skills, "team_attack_boost", float(_signed_byte(int(row[8]))) / 100.0)
	var power_id := int(row[9])
	if power_id > 0 and power_id < POWER_SKILL_KEYS.size():
		_add(skills, POWER_SKILL_KEYS[power_id], 1.0)
	_add(skills, "unlimited_energy", float(int(row[10])))
	_add(skills, "fly", float(int(row[11])))
	_add(skills, "team_damage_reduce", float(_signed_byte(int(row[12]))) / 100.0)
	var defence_row := _signed_byte(int(row[13]))
	if defence_row > 0 and defence_row < DEFENCE_ROWS.size():
		for index in range(DEFENCE_SKILL_KEYS.size()):
			_add(skills, DEFENCE_SKILL_KEYS[index], float(_signed_byte(int(DEFENCE_ROWS[defence_row][index]))) / 100.0)
	_add(skills, "speed_on_hit", float(_signed_byte(int(row[14]))) / 10.0)
	_add(skills, "attack_frequency", float(_signed_byte(int(row[15]))) / 100.0)

static func _add(skills: Dictionary, key: String, value: float) -> void:
	if not is_zero_approx(value):
		skills[key] = float(skills.get(key, 0.0)) + value

static func _signed_byte(value: int) -> int:
	return value - 256 if value > 127 else value
