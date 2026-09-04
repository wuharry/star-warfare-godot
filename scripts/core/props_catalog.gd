class_name PropsCatalogData
extends RefCounted

# Recovered from resDataSets.bytes table 16 and the ItemID/Global category
# tables. Values preserve the original price, duration and effect fields.
const CATEGORY_KEYS := ["health", "aid", "assist"]
const CATEGORY_LABELS := {"health": "HEALTH", "aid": "AID-KIT", "assist": "ASSIST"}
const CATEGORY_ITEMS := {
	"health": [0, 1, 2, 3, 10, 4],
	"aid": [5, 6],
	"assist": [7, 8, 9],
}

const ITEM_ROWS := [
	[0, 81, "MINOR HEALTH", "health", 1000, 0, 0, {"heal": 800.0}, "Restore 800 HP."],
	[1, 82, "SMALL HEALTH", "health", 2500, 0, 0, {"heal": 1500.0}, "Restore 1,500 HP."],
	[2, 83, "MEDIUM HEALTH", "health", 7000, 0, 0, {"heal": 3500.0}, "Restore 3,500 HP."],
	[3, 84, "GREAT HEALTH", "health", 20000, 0, 0, {"heal": 8000.0}, "Restore 8,000 HP."],
	[4, 85, "FULL HEALTH", "health", 0, 1, 0, {"heal": 999999.0}, "Completely restore HP."],
	[5, 86, "SMALL FIRST-AID KIT", "aid", 0, 1, 0, {"revive_ratio": 0.30}, "Revive with 30% maximum HP."],
	[6, 87, "BIG FIRST-AID KIT", "aid", 0, 2, 0, {"revive_ratio": 1.0}, "Revive with full HP."],
	[7, 88, "BOOSTER", "assist", 2000, 0, 30, {"speed_boost": 2.0}, "Increase movement speed for 30 seconds."],
	[8, 89, "FORCE SHIELD", "assist", 2000, 0, 30, {"damage_reduction": 0.50}, "Reduce incoming damage by 50% for 30 seconds."],
	[9, 90, "HYPER CLIP", "assist", 2000, 0, 30, {"attack_boost": 1.0}, "Increase weapon damage by 100% for 30 seconds."],
	[10, 91, "GIANT HEALTH", "health", 40000, 0, 0, {"heal": 25000.0}, "Restore 25,000 HP."],
]


static func build_items() -> Dictionary:
	var result := {}
	for row: Array in ITEM_ROWS:
		var key := "prop%02d" % int(row[0])
		result[key] = {
			"key": key,
			"index": int(row[0]),
			"item_id": int(row[1]),
			"name": str(row[2]),
			"category": str(row[3]),
			"price": int(row[4]),
			"mithril": int(row[5]),
			"duration": int(row[6]),
			"effects": (row[7] as Dictionary).duplicate(true),
			"description": str(row[8]),
		}
	return result


static func get_ids(category_key: String) -> Array[String]:
	var result: Array[String] = []
	for item_index: int in CATEGORY_ITEMS.get(category_key, []):
		result.append("prop%02d" % item_index)
	return result
