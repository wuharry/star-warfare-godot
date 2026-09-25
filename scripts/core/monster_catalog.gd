extends RefCounted

const Source = preload("res://scripts/core/recovered_game_data.gd")
# Match the recovered models, not the restoration's descriptive AI aliases.
# Unity GameWorld maps bug01..08 to EnemyType 0..7 and boss01 to Dragon (10).
const RUNTIME_IDS := {"crawler": 0, "spitter": 2, "brute": 3, "boss": 10}
const RUNTIME_MODELS := {"crawler": "bug01", "spitter": "bug03", "brute": "bug04", "boss": "boss01"}

# Concept prototypes replace the visual scene only. Source monster IDs, stats
# and behaviour still come from the recovered catalog above.
const CONCEPT_SCENES := {
	"crawler": "res://assets/models/enemies/concept/warrior/warrior.gltf",
}


static func visual_scene_path(kind: String, use_concept := true) -> String:
	var model_name: String = str(RUNTIME_MODELS.get(kind, "bug01"))
	var original := "res://assets/models/enemies/animated/%s/%s.gltf" % [model_name, model_name]
	var concept: String = str(CONCEPT_SCENES.get(kind, ""))
	return concept if use_concept and not concept.is_empty() and ResourceLoader.exists(concept) else original


static func get_monster(monster_id: int) -> Dictionary:
	if monster_id < 0 or monster_id >= Source.MONSTER_ROWS.size():
		return {}
	var row: Array = Source.MONSTER_ROWS[monster_id]
	var attacks: Array = Source.ATTACK_TABLES[int(row[3]) - 1]
	return {
		"id": monster_id, "name": str(row[0]), "hp": float(row[1]),
		"speed": float(row[2]), "experience": int(row[4]), "credits": int(row[5]),
		"attacks": attacks.duplicate(true),
	}


static func for_kind(kind: String) -> Dictionary:
	return get_monster(int(RUNTIME_IDS.get(kind, 0)))
