extends RefCounted
## Reversible mesh replacement used by the art showroom; gameplay uses --armor-style=cartoon.

const ASSETS := "res://assets/armors/cartoon_viper/"
var originals: Array[Dictionary] = []

func apply(player: WarfarePlayer) -> void:
	if not originals.is_empty():
		return
	var suit := (load(ASSETS + "viper.scn") as PackedScene).instantiate()
	for source: MeshInstance3D in suit.get_children():
		var target := player.recovered_avatar.find_child(source.name, true, false) as MeshInstance3D
		assert(target != null, "Starter suit part is missing")
		_remember(target)
		target.material_override = null
		for surface in target.get_surface_override_material_count():
			target.set_surface_override_material(surface, null)
		target.mesh = source.mesh
		target.skin = source.skin
		target.transform = source.transform
		target.extra_cull_margin = 1.0
	suit.free()
	_remember(player.backpack_visual)
	player.backpack_visual.mesh = load(ASSETS + "backpack.res")
	player.backpack_visual.material_override = null
	var bone := player.recovered_skeleton.find_bone("fly_bag")
	player.backpack_visual.transform = player.recovered_skeleton.get_bone_global_rest(bone).affine_inverse()

func _remember(target: MeshInstance3D) -> void:
	var overrides: Array[Material] = []
	for surface in target.get_surface_override_material_count():
		overrides.append(target.get_surface_override_material(surface))
	originals.append({"node": target, "mesh": target.mesh, "skin": target.skin, "transform": target.transform,
		"material": target.material_override, "overrides": overrides, "margin": target.extra_cull_margin})

func restore() -> void:
	for entry in originals:
		if not is_instance_valid(entry.node):
			continue
		entry.node.mesh = entry.mesh
		entry.node.skin = entry.skin
		entry.node.transform = entry.transform
		entry.node.material_override = entry.material
		entry.node.extra_cull_margin = entry.margin
		for surface in entry.overrides.size():
			entry.node.set_surface_override_material(surface, entry.overrides[surface])
	originals.clear()
