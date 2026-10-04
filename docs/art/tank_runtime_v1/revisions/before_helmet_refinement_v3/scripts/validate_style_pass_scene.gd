extends SceneTree

const WORK := "res://docs/art/tank_runtime_v1/"
const BEFORE := WORK + "revisions/before_style_unification_v2/delivery/"
const CURRENT := "res://assets/armors/tank_v1/tank.scn"
const NAMES: Array[String] = ["ArmorHead_02", "ArmorBody_02", "ArmorHand_02", "ArmorFoot_02"]
var errors: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func _run() -> void:
	var before := (load(BEFORE + "tank.scn") as PackedScene).instantiate()
	var current := (load(CURRENT) as PackedScene).instantiate()
	var records: Array[Dictionary] = []
	_check(before.get_child_count() == 4 and current.get_child_count() == 4, "Four original modular parts required")
	for name_key: String in NAMES:
		var old := before.find_child(name_key, true, false) as MeshInstance3D
		var new := current.find_child(name_key, true, false) as MeshInstance3D
		var prior_errors := errors.size()
		_check(old != null and new != null, "Missing part " + name_key)
		if old == null or new == null: continue
		_check(old.transform == new.transform and old.skeleton == new.skeleton, "Changed transform/skeleton path " + name_key)
		_check(old.skin.get_bind_count() == new.skin.get_bind_count(), "Changed Skin count " + name_key)
		for i: int in old.skin.get_bind_count():
			_check(old.skin.get_bind_name(i) == new.skin.get_bind_name(i) and old.skin.get_bind_bone(i) == new.skin.get_bind_bone(i) and old.skin.get_bind_pose(i) == new.skin.get_bind_pose(i), "Changed Skin bind " + name_key)
		_check(old.mesh.get_surface_count() == new.mesh.get_surface_count(), "Changed surface count " + name_key)
		for sid: int in old.mesh.get_surface_count():
			var a: Array = old.mesh.surface_get_arrays(sid)
			var b: Array = new.mesh.surface_get_arrays(sid)
			for channel: int in Mesh.ARRAY_MAX:
				_check(a[channel] == b[channel], "Changed actual SCN array %s/%d/channel%d" % [name_key,sid,channel])
			var old_material := old.get_active_material(sid) as BaseMaterial3D
			var new_material := new.get_active_material(sid) as BaseMaterial3D
			_check(old_material != null and new_material != null, "Missing painted material " + name_key)
			if old_material == null or new_material == null: continue
			for property: Dictionary in old_material.get_property_list():
				if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
				var key: String = property.name
				var original: Variant = old_material.get(key)
				var candidate: Variant = new_material.get(key)
				if original is Resource:
					_check(candidate is Resource and original.resource_path == candidate.resource_path, "Changed material resource path %s/%d/%s" % [name_key,sid,key])
				else:
					_check(original == candidate, "Changed material parameter %s/%d/%s" % [name_key,sid,key])
		records.append({"part":name_key,"surfaces":old.mesh.get_surface_count(),"all_mesh_arrays_transform_skeleton_skin_material_parameters_exact":errors.size() == prior_errors})
	for filename: String in ["source.json","target.json","geometry.json"]:
		_check(FileAccess.get_file_as_bytes(BEFORE + filename) == FileAccess.get_file_as_bytes(WORK + "build/" + filename), "Changed authored " + filename)
	var report := {"status":"PASS" if errors.is_empty() else "FAIL","errors":errors,
		"scope":"Paint-only pass: every actual SCN mesh array, transform, skeleton path, Skin bind and stored material parameter/resource path exact against frozen baseline; source/target/geometry JSON bytes exact. Albedo PNG pixel contents intentionally change.",
		"before_scene_sha256":FileAccess.get_sha256(BEFORE + "tank.scn"),"current_scene_sha256":FileAccess.get_sha256(CURRENT),
		"source_sha256":FileAccess.get_sha256(WORK + "build/source.json"),"target_sha256":FileAccess.get_sha256(WORK + "build/target.json"),"geometry_sha256":FileAccess.get_sha256(WORK + "build/geometry.json"),
		"additional_vertex_position_changes":0 if errors.is_empty() else null,"additional_uv_changes":0 if errors.is_empty() else null,
		"material_parameters_preserved":errors.is_empty(),"records":records}
	var file := FileAccess.open(WORK + "review/style_pass_scene_invariants.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	before.free();current.free()
	print("TANK_STYLE_SCENE_%s errors=%d" % [report.status,errors.size()])
	quit(0 if errors.is_empty() else 1)
