extends Node3D

# Thunder wearing the original SW1 helmet mesh with Viper's fitted panels.
# Run with --thunder-helmet=original; the default Thunder scene is untouched,
# so thunder_armor_test still covers the hand-modelled v5 helmet.
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const SCENE := "res://assets/armors/thunder/thunder_original.scn"
const BASE := "res://assets/armors/thunder/thunder.scn"
const SOURCE := "res://assets/models/player/animated/player.gltf"
const SHADER := "res://assets/armors/angular/armor_surface.gdshader"
const REVISION := "thunder_original_helmet_v1"
const BASE_REVISION := "thunder_helmet_v5_sw2"
# A fitted panel is lifted off the source surface by at most this much, so the
# rebuilt helmet must stay inside the original silhouette grown by that margin.
const MAX_LIFT := 0.042
var failures: Array[String] = []
var head_triangles := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
		push_error("THUNDER_ORIGINAL: " + message)


func _run() -> void:
	var real_save := GameState.save_path
	var save_hash := _hash(real_save)
	GameState.save_path = "user://thunder_original_helmet_test_profile.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_weapon = "gun00"
	_check("--thunder-helmet=original" in OS.get_cmdline_user_args(), "Run this regression with --thunder-helmet=original")
	_check(Visuals.reworked_scene_path(6) == SCENE, "the flag does not select the original helmet scene")
	_check(Visuals.REWORKED_SCENES.get(6, "") == BASE, "the default Thunder mapping changed")
	for id: int in Catalog.SET_NAMES.size():
		if id != 6:
			_check(Visuals.reworked_scene_path(id) != SCENE, "the original helmet leaked into set %02d" % id)
	if not ResourceLoader.exists(SCENE):
		_check(false, "the original helmet scene has not been compiled")
		_finish(0)
		return

	var template := (load(SCENE) as PackedScene).instantiate() as Node3D
	var base := (load(BASE) as PackedScene).instantiate() as Node3D
	var gltf := (load(SOURCE) as PackedScene).instantiate() as Node3D
	var source_head := gltf.find_child("ArmorHead_06", true, false) as MeshInstance3D
	var head := template.find_child("ArmorHead_06", true, false) as MeshInstance3D
	_check(template.get_child_count() == 4, "the mixed set must ship four parts")
	_check(head != null and source_head != null, "missing ArmorHead_06 in the scene or the glTF source")
	if head != null and source_head != null:
		_validate_head(head, source_head)
	_validate_reused_parts(template, base)

	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	var avatar := player.recovered_avatar
	var skeleton := player.recovered_skeleton
	for part: int in 4:
		GameState.equipped_armor[Catalog.PART_KEYS[part]] = Catalog.item_key(part, 6)
	player._apply_recovered_armor_visibility()
	for child: Node in template.get_children():
		var authored := child as MeshInstance3D
		var equipped := avatar.find_child(str(authored.name), true, false) as MeshInstance3D
		_check(equipped != null and equipped.visible, "equipping Thunder does not show " + str(authored.name))
		if equipped == null:
			continue
		_check(equipped.mesh == authored.mesh, str(authored.name) + " does not use the compiled mesh")
		_check(equipped.get_node_or_null(equipped.skeleton) == skeleton, str(authored.name) + " uses another skeleton")
		_check(equipped.get_meta("armor_rework", "") == authored.get_meta("armor_rework", ""),
			str(authored.name) + " lost its rework revision when equipped")
	if head != null and source_head != null:
		_validate_named_binds(head, source_head, skeleton)

	gltf.free()
	base.free()
	template.free()
	player.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	_check(_hash(real_save) == save_hash, "Real player save changed")
	_finish(head_triangles)


func _validate_head(head: MeshInstance3D, source_head: MeshInstance3D) -> void:
	_check(head.get_meta("armor_rework", "") == REVISION, "the helmet does not carry the original-helmet revision")
	head_triangles = _triangles(head.mesh)
	var source_triangles := _triangles(source_head.mesh)
	# Panels are added to the original mesh, not modelled over it: the result
	# must grow past the source and stay far below the v5 helmet's 6284.
	_check(source_triangles == 196, "the original glTF helmet is no longer 196 triangles")
	_check(head_triangles > source_triangles and head_triangles < 2000,
		"the rebuilt helmet has an implausible triangle count: %d" % head_triangles)
	_check(head.mesh.get_surface_count() == 1, "the original helmet is a single textured surface")
	_check(head.skin != null and head.skin.get_bind_count() == source_head.skin.get_bind_count(),
		"the helmet skin no longer matches the original bind list")
	_check(head.transform.is_equal_approx(source_head.transform), "the helmet transform moved off the original")
	var bounds := source_head.mesh.get_aabb().grow(MAX_LIFT)
	_check(bounds.encloses(head.mesh.get_aabb()), "the fitted panels push the helmet outside the original silhouette")
	var finish := head.get_active_material(0) as ShaderMaterial
	_check(finish != null and finish.shader != null and finish.shader.resource_path == SHADER,
		"the helmet does not use Viper's fitted-panel shader")
	if finish == null:
		return
	var paint := finish.get_shader_parameter("albedo_texture") as Texture2D
	var original_paint := source_head.get_active_material(0) as BaseMaterial3D
	_check(paint != null and original_paint != null and paint == original_paint.albedo_texture,
		"the helmet no longer paints with the original texture")
	_check(finish.get_shader_parameter("albedo_tint") == original_paint.albedo_color,
		"the helmet tint drifted from every other original armor part")


func _validate_reused_parts(template: Node3D, base: Node3D) -> void:
	# Only the helmet changes; the hand-modelled body, hands and feet are the
	# same resources as the accepted v5 scene and keep their own revision.
	for prefix: String in ["ArmorBody_", "ArmorHand_", "ArmorFoot_"]:
		var part := template.find_child(prefix + "06", true, false) as MeshInstance3D
		var accepted := base.find_child(prefix + "06", true, false) as MeshInstance3D
		_check(part != null and accepted != null, "missing reused part " + prefix + "06")
		if part == null or accepted == null:
			continue
		# Packing writes fresh copies of built-in sub-resources, so identity
		# cannot be compared; the vertex data and materials must still match.
		_check(part.get_meta("armor_rework", "") == BASE_REVISION, prefix + "06 lost the accepted v5 revision")
		_check(part.mesh.get_surface_count() == accepted.mesh.get_surface_count(), prefix + "06 changed its surface count")
		if part.mesh.get_surface_count() != accepted.mesh.get_surface_count():
			continue
		for surface: int in part.mesh.get_surface_count():
			_check(part.mesh.surface_get_arrays(surface).hash() == accepted.mesh.surface_get_arrays(surface).hash(),
				prefix + "06 is no longer the accepted v5 geometry")
			_check(_paint(part.get_active_material(surface)) == _paint(accepted.get_active_material(surface)),
				prefix + "06 changed an accepted v5 material")
		_check(_binds(part.skin) == _binds(accepted.skin), prefix + "06 is no longer the accepted v5 skin")


func _validate_named_binds(head: MeshInstance3D, source_head: MeshInstance3D, skeleton: Skeleton3D) -> void:
	# Every original SW1 set keeps the glTF's rotated bind poses, and its mesh
	# is stored in the matching rotated space. Reusing the source skin verbatim
	# is what keeps that pair consistent; only the reworked sets are aligned to
	# the skeleton rest, so an identity product is the wrong thing to require.
	_check(_binds(head.skin) == _binds(source_head.skin), "the helmet no longer uses the original glTF skin")
	for bind: int in head.skin.get_bind_count():
		_check(skeleton.find_bone(head.skin.get_bind_name(bind)) >= 0, "the helmet has an unknown named bind")


func _binds(skin: Skin) -> Array:
	var result: Array = []
	for bind: int in skin.get_bind_count():
		result.append([str(skin.get_bind_name(bind)), skin.get_bind_pose(bind)])
	return result


func _paint(material: Material) -> Array:
	if material is ShaderMaterial:
		var texture: Variant = material.get_shader_parameter("albedo_texture")
		return [material.shader.resource_path if material.shader else "",
			texture.resource_path if texture is Texture2D else "",
			material.get_shader_parameter("albedo_tint")]
	if material is BaseMaterial3D:
		return ["", material.albedo_texture.resource_path if material.albedo_texture else "", material.albedo_color]
	return []


func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		total += count / 3
	return total


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"


func _finish(triangles: int) -> void:
	print("THUNDER_ORIGINAL_HELMET_%s head_triangles=%d reused_v5_parts=3 named_binds=true original_texture=true" %
		["PASS" if failures.is_empty() else "FAIL", triangles])
	get_tree().quit(0 if failures.is_empty() else 1)
