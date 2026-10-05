extends SceneTree
const Contract = preload("res://tools/armor_runtime_v1/refined_head_contract.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var work := "res://docs/art/titan_runtime_v1/"
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(work+"runtime_config.json"))
	var target: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(work+"build/target.json"))
	var authored: Dictionary = target.parts.ArmorHead_05.surfaces[0]
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	var current := (load("res://assets/armors/titan_v1/titan.scn") as PackedScene).instantiate()
	var baseline: Array = (original.find_child("ArmorHead_05",true,false) as MeshInstance3D).mesh.surface_get_arrays(0)
	var actual: Array = (current.find_child("ArmorHead_05",true,false) as MeshInstance3D).mesh.surface_get_arrays(0)
	assert(Contract.verify(actual,baseline,authored,config.head_refinement).is_empty())
	var bad_weights: Array = actual.duplicate(true)
	bad_weights[Mesh.ARRAY_WEIGHTS][4] = .5
	assert("Original head bind/weight prefix changed" in Contract.verify(bad_weights,baseline,authored,config.head_refinement))
	# Corrupt both mesh AND metadata: equality to target must not hide a lost face.
	var bad_faces: Array = actual.duplicate(true)
	var bad_target: Dictionary = authored.duplicate(true)
	var count: int = bad_faces[Mesh.ARRAY_INDEX].size()
	for corner: int in 3:
		bad_faces[Mesh.ARRAY_INDEX][count-3+corner] = bad_faces[Mesh.ARRAY_INDEX][corner]
	bad_target.indices = Array(bad_faces[Mesh.ARRAY_INDEX])
	bad_target.triangle_parents[-1] = bad_target.triangle_parents[0]
	var errors := Contract.verify(bad_faces,baseline,bad_target,config.head_refinement)
	assert("Subdivision duplicated a triangle" in errors and "Subdivision does not cover its original triangle" in errors)
	original.free()
	current.free()
	print("ARMOR_HEAD_REFINEMENT_CONTRACT_PASS valid_asset / changed_weights_rejected / duplicate_and_lost_faces_rejected")
	quit()
