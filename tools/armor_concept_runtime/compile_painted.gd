extends "res://tools/armor_facets/compile.gd"

const PAINTED_OUT := "res://assets/armors/concept_runtime/painted/"
const PAINTED_WORK := "res://test_output/armor_concept_runtime/"
const PAINTED_REVISION := "concept_painted_cygni_trial_v2"
var current_part := ""
var new_helmet := false
var repaired_head := false
var neutral_tint := Color.WHITE


func _run() -> void:
	new_helmet = "--new-cygni-helmet" in OS.get_cmdline_user_args()
	repaired_head = "--repaired-head" in OS.get_cmdline_user_args()
	var report_name := "repaired_build.json" if repaired_head else "painted_build.json"
	var mesh_name := "repaired_armor_arrays.json" if repaired_head else "painted_meshes.json"
	var revision := "concept_cygni_connected_shell_v4" if repaired_head else ("concept_new_cygni_helmet_v3" if new_helmet else PAINTED_REVISION)
	var report_revision := "concept_cygni_connected_shell_v4" if repaired_head else PAINTED_REVISION
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAINTED_WORK + report_name))
	var geometry: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAINTED_WORK + mesh_name))
	if not report is Dictionary or report.get("revision", "") != report_revision or not geometry is Dictionary:
		_abort("Missing/stale Cygni painted trial build")
		return
	for path: String in report.source_fingerprints:
		if FileAccess.get_sha256("res://" + path) != report.source_fingerprints[path]:
			_abort("Cygni input changed: " + path)
			return
	meshes = geometry
	if new_helmet and not repaired_head:
		var head_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAINTED_WORK + "new_helmet_arrays.json"))
		if not head_data is Dictionary:
			_abort("Build the new concept helmet before compiling")
			return
		meshes["ArmorHead_11"] = [head_data]
	var source := (load("res://assets/equipment_refined/armors/armor_11.scn") as PackedScene).instantiate()
	neutral_tint = source.find_child("ArmorBody_11", true, false).get_active_material(0).get_shader_parameter("albedo_tint")
	# Preflight every part before saving. Preserve original transform and skin;
	# the shared facet exporter converted each vertex back to its source axes.
	for prefix: String in PREFIXES:
		var key := prefix + "11"
		var original := source.find_child(key, true, false) as MeshInstance3D
		if original == null or original.skin == null or not meshes.has(key) or meshes[key].size() != original.mesh.get_surface_count():
			source.free()
			_abort("Missing painted armor part: " + key)
			return
		for sid: int in original.mesh.get_surface_count():
			if not _valid_surface(meshes[key][sid], original.skin.get_bind_count(), key):
				source.free()
				quit(1)
				return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PAINTED_OUT)) != OK:
		source.free()
		_abort("Cannot create painted armor output")
		return
	var container := Node3D.new()
	container.name = "PaintedCygniTrial"
	var triangles := 0
	for prefix: String in PREFIXES:
		current_part = prefix + "11"
		var original := source.find_child(current_part, true, false) as MeshInstance3D
		var replacement := MeshInstance3D.new()
		replacement.name = current_part
		replacement.transform = original.transform
		replacement.skin = original.skin
		replacement.skeleton = NodePath("..")
		replacement.extra_cull_margin = 1.0
		replacement.mesh = _compile(original)
		replacement.set_meta("armor_rework", revision)
		container.add_child(replacement)
		replacement.owner = container
		for sid: int in replacement.mesh.get_surface_count():
			triangles += replacement.mesh.surface_get_array_index_len(sid) / 3
	var packed := PackedScene.new()
	var error := packed.pack(container)
	if error == OK:
		var filename := "repaired_cygni_helmet.scn" if repaired_head else ("new_cygni_helmet.scn" if new_helmet else "armor_11.scn")
		error = ResourceSaver.save(packed, PAINTED_OUT + filename)
	container.free()
	source.free()
	if error != OK:
		_abort("Cannot save Cygni trial: " + error_string(error))
		return
	print("CYGNI_PAINTED_COMPILE_PASS triangles=%d surfaces=5 revision=%s" % [triangles, revision])
	quit()


func _material(source: Material) -> Material:
	if repaired_head:
		if current_part == "ArmorHead_11":
			var clay := StandardMaterial3D.new()
			clay.vertex_color_use_as_albedo = true
			clay.roughness = 0.82
			return clay
		return source.duplicate()
	var material := source.duplicate() as ShaderMaterial
	if material == null:
		return source
	material.shader = load(PAINTED_OUT + "painted_armor.gdshader") as Shader
	if current_part == "ArmorHead_11":
		var texture_path := "res://assets/armors/concept_runtime/textures/new_cygni_helmet.png" if new_helmet else "res://assets/armors/concept_runtime/textures/cygni_head.png"
		if new_helmet and not ResourceLoader.exists(texture_path):
			var clay := StandardMaterial3D.new()
			clay.vertex_color_use_as_albedo = true
			clay.roughness = 0.8
			return clay
		material.set_shader_parameter("albedo_texture", load(texture_path))
		material.set_shader_parameter("albedo_tint", neutral_tint if new_helmet else Color.WHITE)
		material.set_shader_parameter("use_vertex_color", not new_helmet)
	return material
