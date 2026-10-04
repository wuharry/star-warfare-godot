extends SceneTree

const WORK := "res://docs/art/fortune_runtime_v1/"
const BEFORE := "res://docs/art/armor_style_unification_v1/revisions/fortune_head_v7_before_refinement/delivery/"
const CURRENT_SCENE := "res://assets/armors/fortune_v1/fortune.scn"
const NAMES: Array[String] = ["ArmorHead_01", "ArmorBody_01", "ArmorHand_01", "ArmorFoot_01"]
var errors: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func _skin_equal(a: Skin, b: Skin) -> bool:
	if a == null or b == null or a.get_bind_count() != b.get_bind_count(): return false
	for i: int in a.get_bind_count():
		if a.get_bind_name(i) != b.get_bind_name(i) or a.get_bind_bone(i) != b.get_bind_bone(i) or a.get_bind_pose(i) != b.get_bind_pose(i): return false
	return true

func _run() -> void:
	var before := (load(BEFORE + "fortune.scn") as PackedScene).instantiate()
	var current := (load(CURRENT_SCENE) as PackedScene).instantiate()
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK + "build/source.json"))
	var old_target: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BEFORE + "target.json"))
	var target: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK + "build/target.json"))
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORK + "build/geometry.json"))
	var before_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BEFORE + "manifest.json"))
	_check(before.get_child_count() == 4 and current.get_child_count() == 4, "Expected four modular parts in each actual SCN")
	_check(FileAccess.get_sha256(WORK + "build/source.json") == before_manifest.asset_sha256["docs/art/fortune_runtime_v1/build/source.json"], "Original source snapshot changed")
	var records: Array[Dictionary] = []
	var positions_changed: Array[String] = []
	var incremental: Array[Dictionary] = []
	for name_key: String in NAMES:
		var errors_before := errors.size()
		var a := before.find_child(name_key, true, false) as MeshInstance3D
		var b := current.find_child(name_key, true, false) as MeshInstance3D
		_check(a != null and b != null, "Missing SCN part " + name_key)
		if a == null or b == null: continue
		_check(a.transform == b.transform and a.skeleton == b.skeleton, "Changed part transform/skeleton path " + name_key)
		_check(_skin_equal(a.skin, b.skin), "Changed original skin binds " + name_key)
		_check(a.mesh.get_surface_count() == b.mesh.get_surface_count(), "Changed surface count " + name_key)
		var changed := 0
		var maximum := 0.0
		for sid: int in a.mesh.get_surface_count():
			var old_arrays: Array = a.mesh.surface_get_arrays(sid)
			var new_arrays: Array = b.mesh.surface_get_arrays(sid)
			for channel: int in Mesh.ARRAY_MAX:
				if name_key == "ArmorHead_01" and channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]: continue
				_check(old_arrays[channel] == new_arrays[channel], "Changed SCN array %s/%d/channel%d" % [name_key, sid, channel])
			var old_vertices: PackedVector3Array = old_arrays[Mesh.ARRAY_VERTEX]
			var new_vertices: PackedVector3Array = new_arrays[Mesh.ARRAY_VERTEX]
			_check(old_vertices.size() == new_vertices.size(), "Changed vertex count " + name_key)
			for i: int in old_vertices.size(): changed += int(old_vertices[i] != new_vertices[i])
			var row: Dictionary = target.parts[name_key].surfaces[sid]
			var old_row: Dictionary = old_target.parts[name_key].surfaces[sid]
			var source_row: Dictionary = original.parts[name_key].surfaces[sid]
			_check(row.uv == old_row.uv, "Changed authored UV coordinates " + name_key)
			var rest_changes := 0
			for i: int in row.positions.size():
				var p := Vector3(row.positions[i][0], row.positions[i][1], row.positions[i][2])
				var old := Vector3(old_row.positions[i][0], old_row.positions[i][1], old_row.positions[i][2])
				maximum = maxf(maximum, p.distance_to(old))
				rest_changes += int(p != old)
				var source_p := Vector3(source_row.positions[i][0], source_row.positions[i][1], source_row.positions[i][2])
				var dims := Vector3(geometry.parts[name_key].original_bounds.max[0] - geometry.parts[name_key].original_bounds.min[0], geometry.parts[name_key].original_bounds.max[1] - geometry.parts[name_key].original_bounds.min[1], geometry.parts[name_key].original_bounds.max[2] - geometry.parts[name_key].original_bounds.min[2])
				_check(p.distance_to(source_p) / minf(dims.x, minf(dims.y, dims.z)) <= .150001, "Original total displacement budget exceeded " + name_key)
			incremental.append({"part":name_key,"surface":sid,"changed_rest_vertices":rest_changes})
			var material := b.get_active_material(sid) as BaseMaterial3D
			_check(material != null and material.albedo_texture != null and material.albedo_texture.resource_path.begins_with("res://assets/armors/fortune_v1/"), "Current SCN is a temporary geometry preview, not final canonical " + name_key)
			var part_geometry: Dictionary = geometry.parts[name_key]
			for fraction: float in part_geometry.dimension_delta_fraction: _check(fraction <= .15, "Original dimensions budget exceeded " + name_key)
		if changed > 0: positions_changed.append(name_key)
		records.append({"part":name_key,"changed_actual_scn_vertices":changed,"max_incremental_rest_displacement_m":maximum,"uv_indices_weights_bone_arrays_and_skin_exact":errors.size() == errors_before})
	_check(positions_changed == ["ArmorHead_01"], "Only head positions may change")
	var head_quality: Dictionary = geometry.parts.ArmorHead_01.shape_quality
	_check(head_quality.reversed_triangles == 0 and head_quality.zero_area_triangles == 0 and head_quality.coincident_seam_max_rest_gap == 0, "Invalid authored head triangles or seam")
	var report := {"status":"PASS" if errors.is_empty() else "FAIL", "errors":errors,
		"scope":"Actual final SCN arrays against immutable v7 SCN: only head vertex positions/normals may change; all UV/index/weights/bones/skin and all body/limb arrays exact. Original total 15% displacement/dimensions checked, not an incremental allowance.",
		"before_scene_sha256":FileAccess.get_sha256(BEFORE + "fortune.scn"), "current_scene_sha256":FileAccess.get_sha256(CURRENT_SCENE),
		"target_sha256":FileAccess.get_sha256(WORK + "build/target.json"), "master_sha256":FileAccess.get_sha256(WORK + "build/fortune_master.blend"), "source_sha256":FileAccess.get_sha256(WORK + "build/source.json"),
		"positions_changed":positions_changed,"head_normals_change_allowed":true,"additional_uv_changes":0,"records":records,"incremental":incremental,"geometry":geometry.parts.ArmorHead_01,
		"limitation":"Engineering invariants only; neither approved art similarity nor full-frame animation verification."}
	var file := FileAccess.open(WORK + "review/helmet_refinement_invariants.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	before.free(); current.free()
	print("FORTUNE_HELMET_REFINEMENT_%s errors=%d" % [report.status, errors.size()])
	quit(0 if errors.is_empty() else 1)
