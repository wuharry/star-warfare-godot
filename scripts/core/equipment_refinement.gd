extends RefCounted

const ROOT := "res://assets/equipment_refined/"
static var _textures: Dictionary = {}
static var _loaded := false

static func authored_bounds(mesh: Mesh) -> AABB:
	if mesh is ArrayMesh and mesh.resource_path.begins_with(ROOT):
		return mesh.custom_aabb
	return mesh.get_aabb()

static func weapon_mesh(model: String) -> Mesh:
	var path := ROOT + "weapons/%s.res" % model
	if not ResourceLoader.exists(path):
		path = "res://assets/models/weapons/%s.obj" % model
	return load(path) as Mesh if ResourceLoader.exists(path) else null

static func texture_path(source: String) -> String:
	if not _loaded:
		_loaded = true
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
		if manifest is Dictionary:
			for job: Dictionary in manifest.get("textures", []):
				if job.status == "approved":
					_textures[job.source] = job.output
	return str(_textures.get(source, source))
