class_name PropsCatalogData
extends RefCounted

const Source = preload("res://scripts/core/recovered_game_data.gd")

# Recovered from resDataSets.bytes table 16 and the ItemID/Global category
# tables. Values preserve the original price, duration and effect fields.
const CATEGORY_KEYS := ["health", "aid", "assist"]
const CATEGORY_LABELS := {"health": "HEALTH", "aid": "AID-KIT", "assist": "ASSIST"}
const CATEGORY_ITEMS := {
	"health": [0, 1, 2, 3, 10, 4],
	"aid": [5, 6],
	"assist": [7, 8, 9],
}

# Display copy remains local; numeric effects/prices come from Source.PROP_ROWS.
const ITEM_ROWS := [
	[0, 81, "MINOR HEALTH", "health", "Restore 800 HP."],
	[1, 82, "SMALL HEALTH", "health", "Restore 1,500 HP."],
	[2, 83, "MEDIUM HEALTH", "health", "Restore 3,500 HP."],
	[3, 84, "GREAT HEALTH", "health", "Restore 8,000 HP."],
	[4, 85, "FULL HEALTH", "health", "Completely restore HP."],
	[5, 86, "SMALL FIRST-AID KIT", "aid", "Revive with 30% maximum HP."],
	[6, 87, "BIG FIRST-AID KIT", "aid", "Revive with full HP."],
	[7, 88, "BOOSTER", "assist", "Increase movement speed for 30 seconds."],
	[8, 89, "FORCE SHIELD", "assist", "Reduce incoming damage by 50% for 30 seconds."],
	[9, 90, "HYPER CLIP", "assist", "Increase weapon damage by 100% for 30 seconds."],
	[10, 91, "GIANT HEALTH", "health", "Restore 25,000 HP."],
]


static func build_items() -> Dictionary:
	var result := {}
	for row: Array in ITEM_ROWS:
		var key := "prop%02d" % int(row[0])
		var source: Array = Source.PROP_ROWS[int(row[0])]
		var effects := {}
		if int(source[4]) > 0:
			effects.heal = float(source[4])
		if int(source[5]) > 0:
			effects.revive_ratio = float(source[9]) / 100.0
		if int(source[3]) != 0:
			effects.speed_boost = float(_signed_byte(int(source[3])))
		if int(source[2]) != 0:
			effects.attack_boost = float(_signed_byte(int(source[2]))) / 100.0
		if int(source[10]) != 0:
			effects.damage_reduction = -float(_signed_byte(int(source[10]))) / 100.0
		result[key] = {
			"key": key,
			"index": int(row[0]),
			"item_id": int(row[1]),
			"name": str(row[2]),
			"category": str(row[3]),
			"price": int(source[11]),
			"mithril": int(source[12]),
			"duration": int(source[8]),
			"effects": effects,
			"description": str(row[4]),
		}
	return result


static func _signed_byte(value: int) -> int:
	return value - 256 if value > 127 else value


static func get_ids(category_key: String) -> Array[String]:
	var result: Array[String] = []
	for item_index: int in CATEGORY_ITEMS.get(category_key, []):
		result.append("prop%02d" % item_index)
	return result
