extends SceneTree

const SOURCE := "res://assets/models/player/animated/player.gltf"
const OUT := "res://assets/armors/concept_runtime/"
const INPUT := "res://test_output/armor_concept_runtime/"
const IDS := [0, 1, 2, 3, 4, 5, 7, 8, 9, 11]
const REVISION := "concept_armor_chibi_v1"
const PREFIXES := ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var selected: Array[int] = []
	selected.assign(IDS)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="):
			selected.clear()
			for value: String in arg.trim_prefix("--ids=").split(","):
				if not value.is_valid_int() or int(value) not in IDS:
					_fail("Unauthorized armor id: " + value)
					return
				selected.append(int(value))
	var original := (load(SOURCE) as PackedScene).instantiate()
	root.add_child(original)
	var skeleton := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skin := Skin.new()
	var bones := {}
	for index: int in skeleton.get_bone_count():
		var name_key := skeleton.get_bone_name(index)
		bones[name_key] = index
		skin.add_named_bind(name_key, skeleton.get_bone_global_rest(index).affine_inverse())
	var material := ShaderMaterial.new()
	material.shader = load(OUT + "armor_surface.gdshader") as Shader
	material.resource_name = "ConceptArmorPalette"
	var records: Array[Dictionary] = []
	for id: int in selected:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUT + "armor_%02d.json" % id))
		if not data is Dictionary or data.get("id", -1) != id or data.get("revision", "") != REVISION:
			original.free()
			_fail("Missing or stale Blender export %02d" % id)
			return
		var source: Array = data.get("parts", [])
		var error := _validate(source, id, bones)
		if not error.is_empty():
			original.free()
			_fail(error)
			return
		var container := Node3D.new()
		container.name = "ConceptArmor%02d" % id
		var triangles := 0
		var vertices_count := 0
		for part: Dictionary in source:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var positions := PackedVector3Array()
			var normals := PackedVector3Array()
			var uvs := PackedVector2Array()
			var colors := PackedColorArray()
			var indices := PackedInt32Array()
			var weights := PackedFloat32Array()
			var corners: int = part.positions.size() / 3
			triangles += corners / 3
			vertices_count += corners
			for triangle: int in corners / 3:
				# Blender uses CCW; Godot expects clockwise. Both use the original
				# game's Y-up coordinates here, so no additional axis conversion.
				for corner: int in [2, 1, 0]:
					var i := triangle * 3 + corner
					positions.append(Vector3(part.positions[i*3], part.positions[i*3+1], part.positions[i*3+2]))
					normals.append(Vector3(part.normals[i*3], part.normals[i*3+1], part.normals[i*3+2]))
					uvs.append(Vector2(part.uv[i*2], 1.0 - float(part.uv[i*2+1])))
					colors.append(Color(part.colors[i*4], part.colors[i*4+1], part.colors[i*4+2], part.colors[i*4+3]))
					for influence: int in 4:
						indices.append(int(bones[part.bones[i][influence]]) if influence < part.bones[i].size() else 0)
						weights.append(float(part.weights[i][influence]) if influence < part.weights[i].size() else 0.0)
			arrays[Mesh.ARRAY_VERTEX] = positions
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_BONES] = indices
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
			var instance := MeshInstance3D.new()
			instance.name = str(part.name)
			instance.mesh = mesh
			instance.skin = skin
			instance.skeleton = NodePath("..")
			instance.extra_cull_margin = 1.0
			instance.set_meta("armor_rework", REVISION)
			container.add_child(instance)
			instance.owner = container
		var scene := PackedScene.new()
		var saved := scene.pack(container)
		if saved == OK:
			saved = ResourceSaver.save(scene, OUT + "armor_%02d.scn" % id)
		container.free()
		if saved != OK:
			original.free()
			_fail("Scene save failed for %02d: %s" % [id, error_string(saved)])
			return
		records.append({"id": id, "triangles": triangles, "vertices": vertices_count, "surfaces": 4})
		print("CONCEPT_ARMOR_COMPILE_PASS id=%02d triangles=%d" % [id, triangles])
	original.free()
	var report := FileAccess.open(INPUT + "compile.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"revision": REVISION, "sets": records}, "\t"))
	quit()


static func _validate(parts: Array, id: int, bones: Dictionary) -> String:
	if parts.size() != 4:
		return "Need four modular armor parts"
	var seen := {}
	for value: Variant in parts:
		if not value is Dictionary:
			return "Part must be a dictionary"
		var part: Dictionary = value
		var expected: Array[String] = []
		for prefix: String in PREFIXES:
			expected.append(prefix + "%02d" % id)
		var name_key := str(part.get("name", ""))
		if name_key not in expected or seen.has(name_key):
			return "Unknown/duplicate part: " + name_key
		seen[name_key] = true
		for key: String in ["positions", "normals", "colors", "uv", "bones", "weights"]:
			if not part.get(key) is Array:
				return name_key + " missing " + key
		var n: int = part.positions.size() / 3
		if n == 0 or part.positions.size() % 9 != 0 or part.normals.size() != n*3 or part.colors.size() != n*4 or part.uv.size() != n*2 or part.bones.size() != n or part.weights.size() != n:
			return name_key + " inconsistent geometry"
		for key: String in ["positions", "normals", "colors", "uv"]:
			for component: Variant in part[key]:
				if not (component is float or component is int) or not is_finite(float(component)):
					return name_key + " has non-finite " + key
		for i: int in n:
			if not part.bones[i] is Array or not part.weights[i] is Array:
				return name_key + " missing skin arrays"
			if part.bones[i].is_empty() or part.bones[i].size() > 4 or part.bones[i].size() != part.weights[i].size():
				return name_key + " needs one to four skin weights"
			var total := 0.0
			for j: int in part.bones[i].size():
				if not bones.has(part.bones[i][j]):
					return name_key + " unknown bone"
				var weight: Variant = part.weights[i][j]
				if not (weight is float or weight is int) or not is_finite(float(weight)) or float(weight) < 0:
					return name_key + " invalid weight"
				total += float(weight)
			if absf(total - 1.0) > 0.001:
				return name_key + " weights not normalized"
	return ""


func _fail(message: String) -> void:
	push_error("CONCEPT_ARMOR_COMPILE: " + message)
	quit(1)
