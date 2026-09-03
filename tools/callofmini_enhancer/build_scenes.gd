extends SceneTree

const ENHANCED_ROOT := "res://assets/callOfMini/enhanced"
const ARMOR_MODELS := [
	["Assault Armor", "AssaultArmor.dae", "AssaultArmor.tscn"],
	["Combat Suit", "CombatSuit.dae", "CombatSuit.tscn"],
	["Drillmaster", "Drillmaster.dae", "Drillmaster.tscn"],
	["Heavy Battlesuit", "HeavyBattlesuit.dae", "HeavyBattlesuit.tscn"],
	["Mark-6 117R", "Mark6117R.dae", "Mark6117R.tscn"],
	["Recon Suit", "ReconSuit.dae", "ReconSuit.tscn"],
	["Sanguine Chaos", "Sanguine.dae", "Sanguine.tscn"],
	["Training Suit", "TrainingSuit.dae", "TrainingSuit.tscn"],
]


func _initialize() -> void:
	for armor_entry: Array in ARMOR_MODELS:
		_build_scene(String(armor_entry[0]), String(armor_entry[1]), String(armor_entry[2]))
	print("CALLOFMINI_SCENES_READY count=%d" % ARMOR_MODELS.size())
	quit(0)


func _build_scene(armor_folder: String, dae_name: String, scene_name: String) -> void:
	var armor_root := ENHANCED_ROOT.path_join(armor_folder)
	var dae_path := armor_root.path_join(dae_name)
	var output_path := armor_root.path_join(scene_name)
	var source_scene := load(dae_path) as PackedScene
	assert(source_scene != null, "Could not load Call of Mini DAE: " + dae_path)
	var model := source_scene.instantiate() as Node3D
	assert(model != null, "Call of Mini DAE root is not Node3D: " + dae_path)
	model.name = scene_name.get_basename()
	_prepare_materials(model)

	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(model)
	assert(pack_error == OK, "Could not pack enhanced armor scene: %s (%s)" % [output_path, error_string(pack_error)])
	var save_error: Error = ResourceSaver.save(packed, output_path)
	assert(save_error == OK, "Could not save enhanced armor scene: %s (%s)" % [output_path, error_string(save_error)])
	model.free()


func _prepare_materials(model: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var imported := mesh_instance.mesh.surface_get_material(surface_index) as BaseMaterial3D
			if imported == null:
				continue
			var material := imported.duplicate() as BaseMaterial3D
			material.resource_name = "%s_enhanced" % imported.resource_name
			material.albedo_color = Color.WHITE
			material.metallic = 0.08
			material.roughness = 0.62
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			# The legacy atlas already bakes bevel highlights and occlusion. Keeping
			# it unshaded avoids applying a second, incompatible lighting pass to the
			# old Collada normals and matches the readable mobile armor treatment.
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh_instance.set_surface_override_material(surface_index, material)


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, output)
