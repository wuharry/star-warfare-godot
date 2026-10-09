@tool
extends SceneTree

# Godot owns .import/.godot writes. A transient importer callback uses the
# documented append_import_external_resource API to pass custom options.
# It is registered only in this editor process; project.godot is unchanged.
const REQUEST := "res://tools/armor_runtime_v1/head_lossless.titan_head_reimport"
const TARGETS: Array[String] = ["res://assets/armors/titan_v1/titan_titan_head_diffuse.png"]
var report_path := ""

class HeadImporter extends EditorImportPlugin:
	var imported_paths: Array[String] = []
	func _get_importer_name() -> String: return "titan.transient_head_lossless"
	func _get_visible_name() -> String: return "Titan GLB head import request"
	func _get_recognized_extensions() -> PackedStringArray: return PackedStringArray(["titan_head_reimport"])
	func _get_save_extension() -> String: return "tres"
	func _get_resource_type() -> String: return "Resource"
	func _get_import_options(_path: String, _preset: int) -> Array[Dictionary]: return []
	func _import(source_file: String, save_path: String, _options: Dictionary, _variants: Array[String], _files: Array[String]) -> Error:
		for path: String in FileAccess.get_file_as_string(source_file).strip_edges().split("\n"):
			var config := ConfigFile.new()
			if config.load(path + ".import") != OK: return ERR_CANT_OPEN
			var parameters: Dictionary = {}
			for key: String in config.get_section_keys("params"): parameters[key] = config.get_value("params", key)
			parameters["compress/mode"] = 0
			parameters["detect_3d/compress_to"] = 0
			parameters["mipmaps/generate"] = true
			var generator: Variant = config.get_value("remap", "generator_parameters") if config.has_section_key("remap", "generator_parameters") else null
			var result := append_import_external_resource(path, parameters, "texture", generator)
			if result != OK: return result
			imported_paths.append(path)
		return ResourceSaver.save(Resource.new(), save_path + ".tres")

var importer: HeadImporter
var registration: EditorPlugin
var hashes: Dictionary = {}

func _initialize() -> void: _begin.call_deferred()

func _begin() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.is_scanning():
		filesystem.filesystem_changed.connect(_run, CONNECT_ONE_SHOT)
	else:
		_run()

func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/titan_runtime_v1/runtime_config.json"))
	var revision := int(str(config.active_helmet_revision).trim_prefix("helmet_refinement_v"))
	assert(revision in [4, 5, 6])
	report_path = "res://docs/art/titan_runtime_v1/review/helmet_v%d_lossless_import.json" % revision
	for path: String in TARGETS: hashes[path] = FileAccess.get_sha256(path)
	importer = HeadImporter.new()
	registration = EditorPlugin.new()
	registration.add_import_plugin(importer)
	var request := FileAccess.open(REQUEST, FileAccess.WRITE)
	request.store_string("\n".join(TARGETS) + "\n")
	request.close()
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.filesystem_changed.connect(_import_request, CONNECT_ONE_SHOT)
	filesystem.scan()

func _import_request() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.reimport_files(PackedStringArray([REQUEST]))
	var errors: Array[String] = []
	for path: String in TARGETS:
		if path not in importer.imported_paths: errors.append("Importer callback did not import " + path)
	var records: Array[Dictionary] = []
	for path: String in TARGETS:
		var config := ConfigFile.new()
		if config.load(path + ".import") != OK: errors.append("Missing engine-generated import metadata " + path)
		if config.get_value("params", "compress/mode", -1) != 0: errors.append("Lossless import failed " + path)
		if FileAccess.get_sha256(path) != hashes[path]: errors.append("PNG bytes changed " + path)
		records.append({"path":path,"png_sha256":FileAccess.get_sha256(path),"import_metadata_sha256":FileAccess.get_sha256(path + ".import"),"compress_mode":config.get_value("params","compress/mode",-1),"mipmaps":config.get_value("params","mipmaps/generate",false)})
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"PASS" if errors.is_empty() else "FAIL","errors":errors,"method":"Temporary registered EditorImportPlugin callback + append_import_external_resource, no manual metadata editing","records":records,"gpu_memory_measurement":"NOT RUN; lossless import uses uncompressed GPU texels rather than BC texture blocks, exact additional runtime VRAM has not been measured","source":"https://docs.godotengine.org/en/4.7/classes/class_editorimportplugin.html#class-editorimportplugin-method-append-import-external-resource"},"\t"))
	registration.remove_import_plugin(importer)
	registration.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST))
	# This engine-created import belongs only to the transient request.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST + ".import"))
	print("TITAN_HEAD_LOSSLESS_%s errors=%d" % ["PASS" if errors.is_empty() else "FAIL", errors.size()])
	quit(0 if errors.is_empty() else 1)
