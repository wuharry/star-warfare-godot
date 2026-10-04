extends SceneTree

const BEFORE := "res://docs/art/armor_style_unification_v1/before/viper/delivery/viper.scn"
const CURRENT := "res://assets/armors/viper_v2/viper.scn"
const OUTPUT := "res://docs/art/viper_runtime_v2/revisions/style_unified_v9/mesh_invariants.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var before_path := BEFORE
	var current_path := CURRENT
	var output_path := OUTPUT
	var visual_id := 0
	var armor_name := "VIPER"
	if "--armor=fortune" in OS.get_cmdline_user_args():
		before_path = "res://docs/art/armor_style_unification_v1/before/fortune/delivery/fortune.scn"
		current_path = "res://assets/armors/fortune_v1/fortune.scn"
		output_path = "res://docs/art/armor_style_unification_v1/fortune_scene_invariants.json"
		visual_id = 1
		armor_name = "FORTUNE"
	var previous := (load(before_path) as PackedScene).instantiate()
	var current := (load(current_path) as PackedScene).instantiate()
	var failures: Array[String] = []
	var rows: Array[Dictionary] = []
	for prefix: String in ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]:
		var key := prefix + "%02d" % visual_id
		var old := previous.find_child(key, true, false) as MeshInstance3D
		var new := current.find_child(key, true, false) as MeshInstance3D
		assert(old != null and new != null)
		var exact := old.transform == new.transform and old.skeleton == new.skeleton
		exact = exact and old.mesh.get_surface_count() == new.mesh.get_surface_count()
		var surfaces: Array[Dictionary] = []
		for sid: int in old.mesh.get_surface_count():
			var left := old.mesh.surface_get_arrays(sid)
			var right := new.mesh.surface_get_arrays(sid)
			var arrays_exact := left == right
			var old_material := old.get_active_material(sid) as BaseMaterial3D
			var new_material := new.get_active_material(sid) as BaseMaterial3D
			var material_mode_exact := old_material.shading_mode == new_material.shading_mode and old_material.albedo_color == new_material.albedo_color and old_material.texture_filter == new_material.texture_filter and old_material.cull_mode == new_material.cull_mode
			exact = exact and arrays_exact and material_mode_exact
			surfaces.append({"surface": sid, "all_mesh_arrays_exact": arrays_exact, "material_mode_exact": material_mode_exact, "vertices": left[Mesh.ARRAY_VERTEX].size(), "triangles": left[Mesh.ARRAY_INDEX].size() / 3})
		var skin_exact := old.skin.get_bind_count() == new.skin.get_bind_count()
		for bind: int in old.skin.get_bind_count():
			skin_exact = skin_exact and old.skin.get_bind_name(bind) == new.skin.get_bind_name(bind) and old.skin.get_bind_bone(bind) == new.skin.get_bind_bone(bind) and old.skin.get_bind_pose(bind) == new.skin.get_bind_pose(bind)
		exact = exact and skin_exact
		if not exact: failures.append(key + " differs from the immutable prepass cage or material mode")
		rows.append({"part": key, "exact": exact, "skin_exact": skin_exact, "surfaces": surfaces})
	previous.free()
	current.free()
	var report := FileAccess.open(output_path, FileAccess.WRITE)
	report.store_string(JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "scope": "Exact prepass/current mesh arrays, transforms, skeleton paths, skin binds and material mode. Pixel painting changes are intentional and not measured as a similarity score.", "before_scene_sha256": FileAccess.get_sha256(before_path), "current_scene_sha256": FileAccess.get_sha256(current_path), "parts": rows, "failures": failures}, "\t"))
	print("%s_STYLE_INVARIANTS_%s parts=4 failures=%d" % [armor_name, "PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
