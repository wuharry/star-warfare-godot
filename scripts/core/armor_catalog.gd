class_name ArmorCatalog
extends RefCounted

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
	"X-Field", "Wrath"
]

const ARMOR_ROWS := [
	["Viper Head",0,350,0,0,0,0,0,0,0,0,"",0,0,3000,0],
	["Viper Chest",1,400,0,0,0,0,0,0,0,0,"",0,0,4700,0],
	["Viper Hands",2,200,0,0,0,0,0,0,0,0,"",0,0,3000,0],
	["Viper Legs",3,250,0,0,0,0,0,0,0,0,"",0,0,2400,0],
	["Fortune Head",0,450,0,0,5,0,0,0,0,1,"",0,0,20000,0],
	["Fortune Chest",1,900,0,0,0,0,0,0,0,1,"",0,0,27000,0],
	["Fortune Hands",2,300,5,0,0,0,0,0,0,1,"",0,0,24000,0],
	["Fortune Legs",3,450,0,0,0,0,0,0,0,1,"",0,0,16000,0],
	["Tank Head",0,1000,0,0,0,0,0,0,0,2,"",2,0,80000,0],
	["Tank Chest",1,2300,0,246,0,0,0,0,0,2,"",2,0,160000,0],
	["Tank Hands",2,900,15,246,0,0,0,0,0,2,"",2,0,85000,0],
	["Tank Legs",3,750,0,0,0,0,0,0,0,2,"",2,0,75000,0],
	["Hydra Head",0,650,0,0,10,0,0,0,0,3,"",2,0,95000,0],
	["Hydra Chest",1,1800,0,0,0,0,0,0,0,3,"",2,0,145000,0],
	["Hydra Hands",2,800,5,0,0,0,0,0,0,3,"",2,0,100000,0],
	["Hydra Legs",3,600,0,0,0,0,0,0,0,3,"",2,0,60000,0],
	["Strike Head",0,2000,0,0,0,0,0,0,0,4,"",4,0,200000,0],
	["Strike Chest",1,3300,5,0,0,0,0,0,0,4,"",4,0,340000,0],
	["Strike Hands",2,1600,10,0,0,0,0,0,0,4,"",4,0,230000,0],
	["Strike Legs",3,1900,0,10,0,0,0,0,0,4,"",4,0,250000,0],
	["Titan Head",0,2600,5,0,10,0,0,0,0,5,"",4,0,270000,0],
	["Titan Chest",1,5000,0,246,0,0,0,0,0,5,"",4,0,400000,0],
	["Titan Hands",2,2200,0,0,0,0,0,0,0,5,"",4,0,240000,0],
	["Titan Legs",3,2400,0,0,0,0,0,0,0,5,"",4,0,200000,0],
	["Thunder Head",0,4000,0,0,10,0,0,0,0,6,"",5,0,670000,0],
	["Thunder Chest",1,7500,0,0,0,0,0,0,0,6,"",5,0,980000,0],
	["Thunder Hands",2,4000,20,0,0,0,0,0,0,6,"",5,0,700000,0],
	["Thunder Legs",3,4500,0,10,0,0,0,0,0,6,"",5,0,550000,0],
	["Atom Head",0,7000,5,0,0,0,0,0,0,7,"",5,0,800000,0],
	["Atom Chest",1,11000,0,0,0,0,0,0,0,7,"",5,0,1200000,0],
	["Atom Hands",2,5000,10,0,0,0,0,0,0,7,"",5,0,650000,0],
	["Atom Legs",3,4000,0,10,0,0,0,0,0,7,"",5,0,450000,0],
	["Pegasus Head",0,10000,5,0,5,0,0,0,0,8,"",6,0,1500000,0],
	["Pegasus Chest",1,16000,10,0,0,0,0,0,0,8,"",6,0,2500000,140],
	["Pegasus Hands",2,8000,5,0,0,0,0,0,0,8,"",6,0,1300000,0],
	["Pegasus Legs",3,9000,5,0,0,0,0,0,0,8,"",6,0,1400000,0],
	["Draco Head",0,12000,0,0,0,0,0,0,0,9,"",6,0,1700000,0],
	["Draco Chest",1,13000,0,0,0,0,0,0,0,9,"",6,0,2300000,0],
	["Draco Hands",2,7500,10,0,0,0,0,0,0,9,"",6,0,1500000,0],
	["Draco Legs",0,6500,0,0,0,0,0,0,0,9,"",6,0,1200000,0],
	["Phoenix Head",0,13000,5,0,10,0,0,0,0,10,"",6,0,2200000,130],
	["Phoenix Chest",1,18000,5,0,0,0,0,0,0,10,"",6,0,3000000,0],
	["Phoenix Hands",2,9500,5,0,0,0,0,0,0,10,"",6,0,2000000,0],
	["Phoenix Legs",3,8500,0,10,0,0,0,0,0,10,"",6,0,2000000,120],
	["Cygni Head",0,14000,0,0,0,0,0,0,0,11,"",7,0,2000000,0],
	["Cygni Chest",1,15000,0,0,5,0,0,0,0,11,"",7,0,2500000,0],
	["Cygni Hands",2,10000,5,0,0,0,0,0,0,11,"",7,0,2200000,0],
	["Cygni Legs",3,11000,0,10,0,0,0,0,0,11,"",7,0,2500000,0],
	["Andromedae Head",0,13000,0,0,5,0,0,0,0,12,"",7,0,2100000,0],
	["Andromedae Chest",1,20000,5,0,0,0,0,0,0,12,"",7,0,3500000,180],
	["Andromedae Hands",2,11000,5,0,5,0,0,0,0,12,"",7,0,2400000,150],
	["Andromedae Legs",3,15000,5,246,10,0,0,0,0,12,"",7,0,2700000,0],
	["Perseus Head",0,12000,0,0,10,0,0,0,0,13,"",7,0,1800000,0],
	["Perseus Chest",1,18000,10,0,0,0,0,0,0,13,"",7,0,3000000,0],
	["Perseus Hands",2,14000,5,0,0,0,0,0,0,13,"",7,0,2000000,0],
	["Perseus Legs",3,12000,0,10,0,0,0,0,0,13,"",7,0,2200000,0],
	["Chaos Head",0,12000,0,0,5,0,0,0,0,14,"",8,0,2200000,0],
	["Chaos Chest",1,16000,0,0,10,0,0,0,0,14,"",8,0,3300000,200],
	["Chaos Hands",2,10000,5,0,0,0,0,0,0,14,"",8,0,1800000,0],
	["Chaos Legs",3,12000,0,10,5,0,0,0,0,14,"",8,0,2200000,0],
	["DEC.24 Head",0,14000,5,0,5,0,0,0,0,15,"",8,0,3300000,0],
	["DEC.24 Chest",1,15000,5,0,0,0,0,0,0,15,"",8,0,1800000,0],
	["DEC.24 Hands",2,10000,0,0,10,0,0,0,0,15,"",8,0,1900000,0],
	["DEC.24 Legs",3,11000,0,0,5,0,0,0,0,15,"",8,0,2800000,0],
	["Knight Head",0,19000,10,0,0,0,0,0,0,16,"",8,0,3300000,180],
	["Knight Chest",1,16000,5,0,0,0,0,0,0,16,"",8,0,1800000,0],
	["Knight Hands",2,15000,5,0,0,0,0,0,0,16,"",8,0,1900000,0],
	["Knight Legs",3,14000,0,10,0,0,0,0,0,16,"",8,0,2800000,0],
	["R.O.M.E Head",0,18000,10,0,0,0,0,0,0,17,"",8,0,3500000,0],
	["R.O.M.E Chest",1,15000,5,0,5,0,0,0,0,17,"",8,0,2000000,0],
	["R.O.M.E Hands",2,13000,10,0,10,0,0,0,0,17,"",8,0,3500000,220],
	["R.O.M.E Legs",3,14000,5,10,5,0,0,0,0,17,"",8,0,3000000,0],
	["Black Hole Head",0,15000,10,0,10,0,0,0,0,18,"",8,0,3500000,180],
	["Black Hole Chest",1,21000,5,0,5,0,0,0,0,18,"",8,0,2700000,50],
	["Black Hole Hands",2,11000,10,0,0,10,0,0,0,18,"",8,0,2000000,0],
	["Black Hole Legs",3,16000,5,10,5,0,0,0,0,18,"",8,0,2200000,0],
	["X-Field Head",0,15000,0,0,0,0,0,0,0,19,"",8,0,3600000,0],
	["X-Field Chest",1,21000,0,0,15,0,0,0,0,19,"",8,0,2200000,42],
	["X-Field Hands",2,11000,5,0,0,0,0,0,0,19,"",8,0,3000000,0],
	["X-Field Legs",3,16000,5,10,0,0,0,0,0,19,"",8,0,2800000,200],
	["Wrath Head",0,20000,15,5,0,0,0,0,0,20,"8",8,0,3600000,230],
	["Wrath Chest",1,16000,10,0,10,0,0,0,0,20,"8",8,0,4000000,168],
	["Wrath Hands",2,13000,5,0,10,0,0,0,0,20,"8",8,0,3300000,0],
	["Wrath Legs",3,10000,5,251,0,0,0,0,0,20,"8",8,0,2700000,0],
	["VB-03-II",4,200,0,0,0,0,0,0,0,0,"",0,3,3500,0],
	["VB-03-III",4,300,10,0,0,0,0,0,0,0,"",0,3,25000,0],
	["SP-04-IV",4,500,0,0,0,0,4,0,0,0,"",0,4,40000,0],
	["SP-11-V",4,300,10,10,0,0,0,0,0,0,"",1,3,80000,8],
	["KP-101-X",4,500,0,0,0,0,10,0,0,0,"",1,4,100000,10],
	["VP-22-VII",4,600,15,0,0,20,0,0,0,0,"",1,4,150000,0],
	["SPD-005-a",4,700,0,0,0,0,3,0,0,0,"",2,5,100000,0],
	["ECO-03-VI",4,500,0,10,10,0,6,0,0,0,"",2,3,200000,0],
	["TT-05-b",4,1000,0,0,0,0,7,0,0,0,"",3,5,280000,0],
	["SAM-005-I",4,800,20,10,25,25,0,0,0,0,"",3,5,600000,60],
	["STK-06-ZZ",4,900,30,20,0,0,8,0,0,0,"",4,6,700000,0],
	["HYD-00-IX",4,1500,15,0,0,0,9,13,0,0,"",4,5,480000,48],
	["H.F-V-03",4,1200,0,0,0,0,11,1,0,0,"",5,6,950000,95],
	["STK.F-VI-00",4,800,0,10,0,0,12,0,0,0,"",5,6,850000,85],
	["X02B-FREEDOM",4,2000,10,0,0,0,15,17,0,0,"",0,6,2000000,150],
	["F.L.O.A.T",4,1500,20,10,10,10,16,18,0,0,"",0,6,1500000,120],
	["Visnu",4,4000,0,0,0,10,22,0,0,0,"",5,6,1500000,120],
	["TRI-0-AVATAR",4,3500,15,10,0,0,24,0,0,0,"",5,6,1500000,120],
	["BLADE-MASTER",4,1000,0,10,0,0,16,23,0,0,"",3,4,1200000,0],
	["TOUCH AND GO",4,2000,0,10,0,0,28,0,0,0,"",4,5,1000000,0],
	["DRACULA",4,3000,5,10,0,0,29,0,0,0,"",4,6,1500000,110],
	["JIN.JINGLE",4,3600,30,20,35,30,31,32,33,0,"",4,6,1500000,140],
	["S.H.I.E.L.D",4,4000,25,10,0,30,36,0,0,0,"",4,6,1500000,200],
	["D-WINGS",4,4000,15,20,25,30,37,0,0,0,"",5,6,1500000,218],
	["Spectre",4,3000,5,10,10,25,41,42,0,0,"",6,6,1500000,188]
]

# HP, attack%, speed*10, cash%, exp%, and three advanced-skill row ids.
const SET_BONUS_ROWS := [
	[0,0,0,0,0,0,0,0],[400,0,0,5,0,0,0,0],[600,0,0,0,0,0,0,0],
	[400,0,10,0,0,0,0,0],[800,15,0,0,0,0,0,0],[1600,0,0,0,0,1,0,0],
	[0,0,0,0,0,14,2,0],[0,0,0,0,0,5,0,0],[5000,0,0,0,10,4,19,0],
	[0,10,0,0,10,20,0,0],[6000,0,0,0,0,4,21,0],[5000,5,10,0,0,25,0,0],
	[8000,0,0,0,20,26,0,0],[6000,5,0,5,10,27,0,0],[6000,5,0,0,0,30,0,0],
	[4000,5,10,5,10,34,0,0],[6000,10,0,10,0,35,0,0],[5000,10,10,0,0,38,0,0],
	[5000,0,0,0,0,39,0,0],[4000,20,10,0,0,40,0,0],[5500,15,5,0,0,43,0,0]
]

const SKILL_ROWS := [
	[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],[0,0,0,30,0,0,0,0,0,0,0,0,0,0,0,0],
	[241,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],[0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0],
	[236,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],[0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0],
	[246,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,236,0,0,0,0,0,0,0,0,0],
	[50,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],[0,60,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,40,0,0,0,0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,70,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,20,0,0,0,0,0,0,0],[0,0,0,0,0,20,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0],[0,40,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0],[0,0,0,0,0,15,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,246,0,0,0,0,0,0,0,0,0],[0,0,60,0,0,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,0,0,0,236,0,0,0],[0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0],[0,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,4,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0],
	[0,0,0,0,0,0,0,0,0,0,0,0,0,0,20,0],[0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0],[0,0,20,0,0,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,10,0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,10,0,0,0,0,0,0,0],
	[0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,241],
	[0,0,0,0,0,0,0,0,0,7,0,0,0,0,0,0],[0,50,0,0,0,0,0,0,0,0,0,1,0,0,10,0],
	[0,0,0,0,6,0,0,0,0,0,0,0,0,0,0,246],[0,0,0,0,7,0,0,0,0,8,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,9,0,0,0,0,0,0],[0,0,0,0,0,30,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,0,0,0,0,0,15,0],[0,0,0,0,0,0,0,0,0,10,0,0,0,0,0,0]
]

const WEAPON_BOOST_ROWS := [
	[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
	[246,30,246,246,246,246,246,246,246,246,246,246,246,246,246],
	[0,0,0,0,30,30,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,0,0,40,0,0,0],
	[0,0,20,0,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,30,0,0,0,0,0,0,0,0,0],
	[0,0,0,20,0,0,0,0,0,0,0,0,0,0,0],
	[0,0,0,0,0,0,0,0,0,0,0,0,15,0,0]
]
const DEFENCE_ROWS := [[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0,0,226,0,0,0]]

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
	return result

static func build_set_bonuses() -> Dictionary:
	var result := {}
	for set_id in range(SET_BONUS_ROWS.size()):
		var row: Array = SET_BONUS_ROWS[set_id]
		var skills := _base_skills(row, 0)
		for column in range(5, 8):
			_add_advanced_skills(skills, int(row[column]))
		result[set_id] = {"id": set_id, "name": SET_NAMES[set_id], "skills": skills}
	return result

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
