extends RefCounted

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const ORIGINAL_PART_PREFIXES := ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]
const REWORKED_SCENES := {0: "res://assets/armors/viper/viper.scn"}


static func ensure_parts(avatar: Node3D, visual_ids: Dictionary) -> void:
	_restore_original_materials(avatar)
	var skeletons := avatar.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	_ensure_reworked_parts(avatar, skeleton, visual_ids)
	for visual_id: int in visual_ids.values():
		var scene_path := Catalog.gameplay_scene_path(visual_id)
		if scene_path.is_empty() or skeleton.has_node("ArmorHead_%02d" % visual_id):
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var parts := packed.instantiate() as Node3D
		for child: Node in parts.get_children():
			var mesh_instance := child as MeshInstance3D
			if mesh_instance == null:
				continue
			mesh_instance.owner = null
			parts.remove_child(mesh_instance)
			skeleton.add_child(mesh_instance)
			mesh_instance.skeleton = NodePath("..")
			mesh_instance.visible = false
		parts.free()


static func _ensure_reworked_parts(avatar: Node3D, skeleton: Skeleton3D, visual_ids: Dictionary) -> void:
	for visual_id: int in visual_ids.values():
		if not REWORKED_SCENES.has(visual_id):
			continue
		var marker := "armor_rework_%02d" % visual_id
		if avatar.has_meta(marker):
			continue
		var packed := load(str(REWORKED_SCENES[visual_id])) as PackedScene
		if packed == null:
			continue
		var source := packed.instantiate() as Node3D
		for child: Node in source.get_children():
			var replacement := child as MeshInstance3D
			if replacement == null:
				continue
			var existing := avatar.find_child(str(replacement.name), true, false) as MeshInstance3D
			if existing != null:
				# Keep node paths stable for animation tracks and mixed equipment.
				existing.mesh = replacement.mesh
				existing.skin = replacement.skin
				existing.material_override = null
				for surface in existing.get_surface_override_material_count():
					existing.set_surface_override_material(surface, null)
				existing.transform = replacement.transform
				existing.extra_cull_margin = replacement.extra_cull_margin
				existing.set_meta("armor_rework", replacement.get_meta("armor_rework"))
			else:
				replacement.owner = null
				source.remove_child(replacement)
				skeleton.add_child(replacement)
				replacement.skeleton = NodePath("..")
				replacement.visible = false
		source.free()
		avatar.set_meta(marker, true)


static func _restore_original_materials(avatar: Node3D) -> void:
	if avatar.has_meta("unity_armor_materials_restored"):
		return
	# All 106 material slots in Unity Avatar/01..21 armor parts use
	# SolidTexture or SolidAndAlphaTexture(_Bright): their fixed-function
	# passes combine textures without Lighting On. The glTF export loses this
	# source behavior and defaults to PBR, making the player black indoors.
	# Only restore armor; weapons and backpacks own separate material rules.
	for instance: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if instance.has_meta("armor_rework"):
			continue
		var original_part := false
		for prefix: String in ORIGINAL_PART_PREFIXES:
			if instance.name.begins_with(prefix):
				var id_text := String(instance.name).trim_prefix(prefix)
				original_part = id_text.is_valid_int() and int(id_text) < Catalog.CALLOFMINI_FIRST_ID
				break
		if not original_part or instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var source := instance.get_active_material(surface) as BaseMaterial3D
			if source == null or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			var material := source.duplicate() as BaseMaterial3D
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			instance.set_surface_override_material(surface, material)
	avatar.set_meta("unity_armor_materials_restored", true)


static func restore_starter_backpack(instance: MeshInstance3D, visual_id: int) -> void:
	if visual_id != 0 or instance.mesh == null:
		return
	# Unity Avatar/01/Bag uses Material/01.mat -> SolidAndAlphaTexture_Bright.
	# That pass is unlit and uses white _TintColor; the serialized gray _Color
	# copied into OBJ's Kd is ignored by the source shader. Other bags have
	# separate animated/additive/built-in shaders and retain their own rules.
	var source := instance.get_active_material(0) as BaseMaterial3D
	if source == null:
		return
	var material := source.duplicate() as BaseMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	instance.material_override = material
