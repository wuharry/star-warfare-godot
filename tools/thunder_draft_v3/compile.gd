extends SceneTree

const Contract = preload("res://tools/thunder_draft_v3/contract.gd")
const CONFIG := "res://docs/art/thunder_draft_v3/runtime_config.json"
const PAINT_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
void fragment() {
    ALBEDO = texture(albedo_texture, UV).rgb;
}
"""

var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	errors.append_array(Contract.check_pins(config))
	if not errors.is_empty():
		_finish("PIN_CHECK")
		return
	var original := (load(str(config.source_scene)) as PackedScene).instantiate() as Node3D
	root.add_child(original)
	var head := original.find_child(str(config.head_node), true, false) as MeshInstance3D
	var skeleton := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var work := str(config.work)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work + "guides/"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work + "build/"))
	_export_original(config, head, skeleton)
	if "--inspect-only" in OS.get_cmdline_user_args():
		original.free()
		_finish("SOURCE")
		return
	if not errors.is_empty():
		original.free()
		_finish("SOURCE")
		return
	errors.append_array(Contract.check_pins(config, true))
	var target_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(config.head_target)))
	if not target_value is Dictionary:
		errors.append("Missing or invalid pinned head target JSON")
	if not errors.is_empty():
		original.free()
		_finish("TARGET")
		return
	var target: Dictionary = target_value
	errors.append_array(Contract.validate_target(head, target))
	if not errors.is_empty():
		original.free()
		_finish("TARGET")
		return
	if not FileAccess.file_exists(str(config.native_generated_png)):
		errors.append("Missing native generated helmet PNG")
		original.free()
		_finish("COMPILE")
		return
	var image := Image.new()
	var image_error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(str(config.native_generated_png)))
	if image_error != OK or image.is_empty():
		errors.append("Cannot decode native generated helmet PNG")
		original.free()
		_finish("COMPILE")
		return
	var texture := ImageTexture.create_from_image(image)
	if ResourceSaver.save(texture, str(config.portable_texture), ResourceSaver.FLAG_COMPRESS) != OK:
		errors.append("Cannot write lossless portable head ImageTexture")
		original.free()
		_finish("COMPILE")
		return
	texture = load(str(config.portable_texture)) as ImageTexture
	if texture.get_image().get_data() != image.get_data() or texture.get_image().get_format() != image.get_format() or texture.get_size() != Vector2(image.get_size()):
		errors.append("Portable head image changed the native PNG pixels")
	var shader := Shader.new()
	shader.code = PAINT_SHADER
	var material := ShaderMaterial.new()
	material.resource_name = "ThunderDraftHeadV3"
	material.shader = shader
	material.set_shader_parameter("albedo_texture", texture)
	var restored := (load(str(config.before_scene)) as PackedScene).instantiate() as Node3D
	var previous_head := restored.find_child(str(config.head_node), true, false) as MeshInstance3D
	previous_head.mesh = _bounded_head_mesh(head, target)
	if previous_head.mesh == null:
		restored.free()
		original.free()
		_finish("GEOMETRY")
		return
	for sid: int in previous_head.mesh.get_surface_count():
		previous_head.mesh.surface_set_material(sid, material)
	previous_head.skin = head.skin.duplicate(true) as Skin
	previous_head.transform = head.transform
	previous_head.skeleton = NodePath("..")
	previous_head.material_override = null
	for sid: int in previous_head.get_surface_override_material_count():
		previous_head.set_surface_override_material(sid, null)
	previous_head.set_meta("armor_rework", str(config.revision))
	previous_head.set_meta("original_head_source", str(config.source_scene))
	previous_head.set_meta("original_uv_preserved", true)
	errors.append_array(Contract.compare_head(head, previous_head, target))
	var packed := PackedScene.new()
	if packed.pack(restored) != OK:
		errors.append("Cannot pack head-only Thunder scene")
	elif errors.is_empty() and ResourceSaver.save(packed, str(config.output_scene)) != OK:
		errors.append("Cannot save default Thunder scene")
	var frozen := (load(str(config.before_scene)) as PackedScene).instantiate() as Node3D
	var output: Node3D
	if errors.is_empty():
		output = (load(str(config.output_scene)) as PackedScene).instantiate() as Node3D
		var before_triangles := 0
		var current_triangles := 0
		for child: Node in frozen.get_children():
			if child is MeshInstance3D:
				before_triangles += Contract.triangle_count(child)
		for child: Node in output.get_children():
			if child is MeshInstance3D:
				current_triangles += Contract.triangle_count(child)
		for part_name: String in config.inherited_body_nodes:
			errors.append_array(Contract.compare_part(frozen.find_child(part_name, true, false), output.find_child(part_name, true, false)))
		errors.append_array(Contract.compare_head(head, output.find_child(str(config.head_node), true, false), target))
		errors.append_array(Contract.check_pins(config, true))
		var head_contract := Contract.geometry_report(head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], Contract.target_points(target), head.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX])
		var report := {
			"status": "PASS" if errors.is_empty() else "FAIL", "errors": errors,
			"revision": config.revision, "scene_sha256": FileAccess.get_sha256(str(config.output_scene)),
			"runtime_triangle_counts": {"restored_before_whole_suit": before_triangles, "current_whole_suit": current_triangles, "restored_before_head": Contract.triangle_count(frozen.find_child(str(config.head_node), true, false)), "current_original_topology_head": Contract.triangle_count(head)},
			"true_original_head": {"uv_coordinates": head.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size(), "triangles": Contract.triangle_count(head), "max_rest_displacement": head_contract.max_rest_displacement, "max_displacement_fraction_of_smallest_dimension": head_contract.max_displacement_fraction_of_smallest_dimension, "max_dimension_change_fraction": head_contract.max_dimension_change_fraction, "dimension_change_fractions": head_contract.dimension_change_fractions, "normalizer_original_smallest_dimension_m": head_contract.normalizer_original_smallest_dimension_m, "uv_changed_fraction": 0.0, "immutable_native_channels_and_serialized_buffers_exact": errors.is_empty(), "skin_binds": head.skin.get_bind_count()},
			"head_contract": head_contract, "head_original_uv_topology_skin_transform_exact": errors.is_empty(), "delivered_head_matches_target": errors.is_empty(), "target_sha256": FileAccess.get_sha256(str(config.head_target)),
			"whole_suit_original_percentage": "NOT_CLAIMED_BODY_INHERITS_3ED",
			"body_baseline": {"commit": config.body_baseline_commit, "scene_sha256": config.before_scene_sha256, "three_parts_native_buffers_materials_skin_transform_unchanged": errors.is_empty()},
			"native_png_sha256": FileAccess.get_sha256(str(config.native_generated_png)),
			"portable_texture_sha256": FileAccess.get_sha256(str(config.portable_texture)),
			"pixel_bytes_preserved": texture.get_image().get_data() == image.get_data(),
			"native_size": [image.get_width(), image.get_height()], "shader_code": PAINT_SHADER,
			"protected_alternates": config.protected_alternates,
			"scope": config.constraint
		}
		_write_json(work + "build/compile_report.json", report)
		output.free()
	frozen.free()
	restored.free()
	original.free()
	_finish("COMPILE")


# Preserve real serialized UV/index/skin/attribute bytes. A regenerated mesh is
# used only for target positions, four-byte encoded normals and bounds.
func _bounded_head_mesh(head: MeshInstance3D, target: Dictionary) -> ArrayMesh:
	var arrays := head.mesh.surface_get_arrays(0).duplicate(true)
	var points := Contract.target_points(target)
	arrays[Mesh.ARRAY_VERTEX] = points
	var old_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var sums := PackedVector3Array()
	sums.resize(points.size())
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for tri: int in indices.size() / 3:
		var a: int = indices[tri * 3]
		var b: int = indices[tri * 3 + 1]
		var c: int = indices[tri * 3 + 2]
		var normal := (points[b] - points[a]).cross(points[c] - points[a])
		if normal.dot(old_normals[a] + old_normals[b] + old_normals[c]) < 0.0:
			normal = -normal
		for vertex: int in [a, b, c]:
			sums[vertex] += normal
	for vertex: int in points.size():
		if sums[vertex].length_squared() > 0.000000000001:
			arrays[Mesh.ARRAY_NORMAL][vertex] = sums[vertex].normalized()
	var generated_mesh := ArrayMesh.new()
	generated_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var raw: Dictionary = (head.mesh.get("_surfaces") as Array)[0].duplicate(true)
	var generated := RenderingServer.mesh_get_surface(generated_mesh.get_rid(), 0)
	if raw.format != generated.format or raw.vertex_count != generated.vertex_count:
		errors.append("Regenerated head changed original serialized format/count")
		return null
	var count: int = raw.vertex_count
	var stride := RenderingServer.mesh_surface_get_format_vertex_stride(raw.format, count)
	var normal_offset := RenderingServer.mesh_surface_get_format_offset(raw.format, count, Mesh.ARRAY_NORMAL)
	var normal_stride := 8 if arrays[Mesh.ARRAY_TANGENT] != null and arrays[Mesh.ARRAY_TANGENT].size() > 0 else 4
	var original_bytes: PackedByteArray = raw.vertex_data.duplicate()
	var edited_bytes: PackedByteArray = generated.vertex_data
	if stride != 12 or original_bytes.size() != edited_bytes.size() or normal_offset + (count - 1) * normal_stride + 4 > original_bytes.size():
		errors.append("Unsupported original head serialized vertex/normal layout")
		return null
	for byte: int in count * stride:
		original_bytes[byte] = edited_bytes[byte]
	for vertex: int in count:
		for byte: int in 4:
			original_bytes[normal_offset + vertex * normal_stride + byte] = edited_bytes[normal_offset + vertex * normal_stride + byte]
	raw.vertex_data = original_bytes
	raw.aabb = generated.aabb
	raw.bone_aabbs = generated.get("bone_aabbs", raw.get("bone_aabbs", []))
	var mesh := ArrayMesh.new()
	mesh.set("_surfaces", [raw])
	return mesh


func _export_original(config: Dictionary, head: MeshInstance3D, skeleton: Skeleton3D) -> void:
	var arrays := head.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if points.size() != int(config.original_head_uv_count) or uv.size() != points.size() or indices.size() / 3 != int(config.original_head_triangles) or head.skin.get_bind_count() != int(config.original_head_skin_bind_count):
		errors.append("True original head counts changed")
	var data := {"source_scene": config.source_scene, "source_scene_sha256": config.source_scene_sha256, "source_buffer_sha256": config.source_buffer_sha256, "original_texture": config.original_head_texture, "original_texture_sha256": config.original_head_texture_sha256, "node": str(head.name), "positions": [], "uv": [], "indices": [], "bone_indices": [], "weights": [], "binds": [], "rest_bounds": {}}
	for p: Vector3 in points:
		data.positions.append([p.x, p.y, p.z])
	for t: Vector2 in uv:
		data.uv.append([t.x, t.y])
	for index: int in indices:
		data.indices.append(index)
	for index: int in arrays[Mesh.ARRAY_BONES]:
		data.bone_indices.append(index)
	for weight: float in arrays[Mesh.ARRAY_WEIGHTS]:
		data.weights.append(weight)
	for bind: int in head.skin.get_bind_count():
		data.binds.append({"name": head.skin.get_bind_name(bind), "bone": head.skin.get_bind_bone(bind), "pose": var_to_str(head.skin.get_bind_pose(bind))})
	var bounds := Contract.posed_bounds(head, skeleton, true)
	data.rest_bounds = {"min": [bounds.position.x, bounds.position.y, bounds.position.z], "max": [bounds.end.x, bounds.end.y, bounds.end.z], "size": [bounds.size.x, bounds.size.y, bounds.size.z]}
	_write_json(str(config.work) + "head_source.json", data)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#17222d"/>'
	for tri: int in indices.size() / 3:
		var corners: Array[String] = []
		for corner: int in 3:
			var t: Vector2 = uv[indices[tri * 3 + corner]]
			corners.append("%.3f,%.3f" % [t.x * 1024, t.y * 1024])
		svg += '<polygon points="%s" fill="none" stroke="#9ad9e8" stroke-width="1"/>' % " ".join(corners)
	svg += '</svg>'
	var file := FileAccess.open(str(config.work) + "guides/head_original_uv.svg", FileAccess.WRITE)
	file.store_string(svg)
	file.close()
	var guide := Image.new()
	if guide.load_svg_from_string(svg) != OK or guide.save_png(str(config.work) + "guides/head_original_uv.png") != OK:
		errors.append("Cannot rasterize true original UV guide through Godot")


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("Cannot write " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _finish(stage: String) -> void:
	for error: String in errors:
		push_error(error)
	print("THUNDER_DRAFT_V3_%s_%s errors=%d" % [stage, "PASS" if errors.is_empty() else "FAIL", errors.size()])
	quit(0 if errors.is_empty() else 1)
