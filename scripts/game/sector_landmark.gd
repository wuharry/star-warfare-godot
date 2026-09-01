class_name WarfareSectorLandmark
extends Node3D

const UnityColliderBuilderScript = preload("res://scripts/core/unity_collider_builder.gd")
const UnityMaterialRestorerScript = preload("res://scripts/core/unity_material_restorer.gd")

# One recovered Unity sector, planted into THE EXPANSE as a landmark.
#
# The campaign loads these stages whole, decorative horizon and all: a single
# sector can carry a 2000-unit mountain shell around a 100-unit arena, which is
# fine when it is the only thing in the world and useless when seventeen of
# them share one map. So the mesh is clipped to its playable core here — every
# triangle whose corners all sit inside the footprint survives, everything
# reaching past it (the horizon shells, the sky domes, the ground planes that
# run to the old skybox) is dropped, and the procedural terrain is flattened
# underneath to take over exactly where the original ground stops.

# A little slack past the footprint so the cut lands outside the props rather
# than through them.
const KEEP_MARGIN := 1.14
# Anything this far up is horizon dressing, not level geometry.
const MAX_LOCAL_HEIGHT := 92.0
# Lifts the recovered ground a hair above the plateau it sits on so the two
# never z-fight where they overlap.
const GROUND_LIFT := 0.06

var level_number := 1
var footprint_radius := 70.0
var display_name := ""
var source_triangles := 0
var kept_triangles := 0
var collider_count := 0

func configure(number: int, radius: float) -> bool:
	level_number = number
	footprint_radius = radius
	var level_root := "res://assets/models/levels/level_%02d" % number
	var mesh_path := "%s/stage.obj" % level_root
	if not ResourceLoader.exists(mesh_path):
		push_warning("Landmark art is missing: %s" % mesh_path)
		return false
	var source := load(mesh_path) as Mesh
	if source == null:
		push_warning("Landmark art failed to load: %s" % mesh_path)
		return false

	var clipped := clip_mesh(source, radius * KEEP_MARGIN, MAX_LOCAL_HEIGHT)
	source_triangles = int(clipped.source_triangles)
	kept_triangles = int(clipped.kept_triangles)
	var mesh: ArrayMesh = clipped.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		push_warning("Landmark %d clipped away to nothing" % number)
		return false

	var visual := MeshInstance3D.new()
	visual.name = "Sector%02dArt" % number
	visual.mesh = mesh
	visual.position = Vector3(0.0, GROUND_LIFT, 0.0)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var metadata_path := "%s/level.json" % level_root
	if FileAccess.file_exists(metadata_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		if parsed is Dictionary:
			UnityMaterialRestorerScript.apply_to_mesh(visual, parsed.get("material_render_modes", {}))
	add_child(visual)

	_build_colliders(level_root, radius * KEEP_MARGIN)
	display_name = str(GameState.get_level_data(number).get("name", ""))
	return true

static func clip_mesh(source: Mesh, keep_radius: float, max_height: float) -> Dictionary:
	# Rebuilds every surface from the triangles that survive the footprint test,
	# keeping each surface's original recovered material.
	var result := ArrayMesh.new()
	var total := 0
	var kept := 0
	var radius_squared := keep_radius * keep_radius
	for surface_index in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			# An unindexed surface lists its triangles vertex by vertex.
			indices = PackedInt32Array()
			indices.resize(vertices.size())
			for i in range(vertices.size()):
				indices[i] = i

		var out_vertices := PackedVector3Array()
		var out_normals := PackedVector3Array()
		var out_uvs := PackedVector2Array()
		var out_indices := PackedInt32Array()
		var remap: Dictionary = {}

		var triangle_count := indices.size() / 3
		total += triangle_count
		for triangle in range(triangle_count):
			var a := indices[triangle * 3]
			var b := indices[triangle * 3 + 1]
			var c := indices[triangle * 3 + 2]
			if not _inside(vertices[a], radius_squared, max_height):
				continue
			if not _inside(vertices[b], radius_squared, max_height):
				continue
			if not _inside(vertices[c], radius_squared, max_height):
				continue
			kept += 1
			for original in [a, b, c]:
				if not remap.has(original):
					remap[original] = out_vertices.size()
					out_vertices.append(vertices[original])
					if not normals.is_empty():
						out_normals.append(normals[original])
					if not uvs.is_empty():
						out_uvs.append(uvs[original])
				out_indices.append(int(remap[original]))

		if out_indices.is_empty():
			continue
		var out_arrays := []
		out_arrays.resize(Mesh.ARRAY_MAX)
		out_arrays[Mesh.ARRAY_VERTEX] = out_vertices
		if not out_normals.is_empty():
			out_arrays[Mesh.ARRAY_NORMAL] = out_normals
		if not out_uvs.is_empty():
			out_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
		out_arrays[Mesh.ARRAY_INDEX] = out_indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		var material := source.surface_get_material(surface_index)
		if material:
			result.surface_set_material(result.get_surface_count() - 1, material)

	return {
		"mesh": result if result.get_surface_count() > 0 else null,
		"source_triangles": total,
		"kept_triangles": kept,
	}

static func _inside(vertex: Vector3, radius_squared: float, max_height: float) -> bool:
	if vertex.y > max_height:
		return false
	return vertex.x * vertex.x + vertex.z * vertex.z <= radius_squared

func _build_colliders(level_root: String, keep_radius: float) -> void:
	var metadata_path := "%s/level.json" % level_root
	if not FileAccess.file_exists(metadata_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary:
		return
	var metadata: Dictionary = parsed
	var body := StaticBody3D.new()
	body.name = "Sector%02dColliders" % level_number
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(0.0, GROUND_LIFT, 0.0)
	add_child(body)

	var radius_squared := keep_radius * keep_radius
	for record in metadata.get("primitive_colliders", []):
		if not record is Dictionary:
			continue
		var origin := UnityColliderBuilderScript.collider_origin(record)
		if origin == Vector3.INF:
			continue
		if origin.x * origin.x + origin.z * origin.z > radius_squared:
			continue
		if origin.y > MAX_LOCAL_HEIGHT:
			continue
		if UnityColliderBuilderScript.add_primitive(body, record):
			collider_count += 1

	var collision_file := str(metadata.get("collision_mesh", ""))
	if collision_file.is_empty():
		return
	var collision_path := "%s/%s" % [level_root, collision_file]
	if not ResourceLoader.exists(collision_path):
		return
	var collision_mesh := load(collision_path) as Mesh
	if collision_mesh == null:
		return
	var clipped := clip_mesh(collision_mesh, keep_radius, MAX_LOCAL_HEIGHT)
	var clipped_mesh: ArrayMesh = clipped.mesh
	if clipped_mesh == null:
		return
	var shape := clipped_mesh.create_trimesh_shape()
	if shape == null:
		return
	var collision := CollisionShape3D.new()
	collision.name = "Sector%02dMeshColliders" % level_number
	collision.shape = shape
	body.add_child(collision)
	collider_count += 1
