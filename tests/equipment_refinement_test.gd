extends Node3D

const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Refined = preload("res://scripts/core/equipment_refinement.gd")
var failures: Array[String] = []
var checked_armor_textures: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var fixture := preload("res://tests/reload_catalog_fixture.gd").new()
	add_child(fixture)
	fixture.setup()
	var avatar: Node3D = fixture.player.recovered_avatar
	var skeleton := avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var animation := avatar.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var original_avatar := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	var checked_armor_sets := 0
	for id in range(1, Catalog.SET_NAMES.size()):
		if id == 6:
			# Thunder now has deliberately redesigned helmet / plate geometry and
			# materials. Old-atlas and < .025 silhouette parity are not its contract.
			# tests/thunder_armor_test.tscn owns skinning, animation and mixed equips;
			# all other refinement-only sets keep the original strict assertions.
			_check(Visuals.REWORKED_SCENES.get(6, "") == "res://assets/armors/thunder/thunder.scn", "Thunder redesign lost its dedicated runtime mapping")
			continue
		checked_armor_sets += 1
		var original: Node = original_avatar
		if id >= Catalog.CALLOFMINI_FIRST_ID:
			original = (load(Catalog.gameplay_scene_path(id)) as PackedScene).instantiate()
		var ids := {"head": id, "body": id, "hand": id, "foot": id}
		Visuals.ensure_parts(avatar, ids)
		for prefix in Visuals.ORIGINAL_PART_PREFIXES:
			var part := avatar.find_child(prefix + "%02d" % id, true, false) as MeshInstance3D
			_check(part != null and part.has_meta("armor_rework"), "missing refined armor %s%d" % [prefix, id])
			if part == null: continue
			_check(part.skin != null, "missing original skin " + str(part.name))
			_validate_mesh(part.mesh, str(part.name), skeleton.get_bone_count())
			var source_part := original.find_child(str(part.name), true, false) as MeshInstance3D
			for surface in source_part.mesh.get_surface_count():
				_validate_material(source_part.get_active_material(surface), part.get_active_material(surface), str(part.name))
		var count := skeleton.get_child_count()
		Visuals.ensure_parts(avatar, ids)
		_check(count == skeleton.get_child_count(), "repeated equip duplicated armor")
		fixture.player._cancel_reload()
		for pose in ["idle_rifle", "run_rifle"]:
			if not animation.has_animation(pose):
				_check(false, "missing validation animation " + pose)
				continue
			animation.play(pose)
			for time in [0.0, 0.2, 0.5]:
				animation.seek(time, true)
				skeleton.force_update_all_bone_transforms()
				for prefix in Visuals.ORIGINAL_PART_PREFIXES:
					var name_key: String = prefix + "%02d" % id
					var source := original.find_child(name_key, true, false) as MeshInstance3D
					var refined := avatar.find_child(name_key, true, false) as MeshInstance3D
					var before := _posed_bounds(source, skeleton)
					var after := _posed_bounds(refined, skeleton)
					_check(before.position.distance_to(after.position) < .025 and before.end.distance_to(after.end) < .025, "posed silhouette changed %s %s %.2f" % [name_key, pose, time])
		fixture.begin("gun00", 0)
		for fraction in [0.15, 0.35, 0.35]:
			fixture.step(fixture.duration * fraction)
			for prefix in Visuals.ORIGINAL_PART_PREFIXES:
				var name_key: String = prefix + "%02d" % id
				var before := _posed_bounds(original.find_child(name_key, true, false), skeleton)
				var after := _posed_bounds(avatar.find_child(name_key, true, false), skeleton)
				_check(before.position.distance_to(after.position) < .025 and before.end.distance_to(after.end) < .025, "reload silhouette changed " + name_key)
		if original != original_avatar: original.free()
	original_avatar.free()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Refined.ROOT + "manifest.json"))
	var checked_models := {}
	for entry: Dictionary in manifest.entries:
		if entry.kind != "weapon": continue
		for model: Dictionary in entry.models:
			if checked_models.has(model.model): continue
			checked_models[model.model] = true
			var source := load("res://assets/models/weapons/%s.obj" % model.model) as Mesh
			var refined := Refined.weapon_mesh(model.model)
			_check(refined.resource_path.begins_with(Refined.ROOT), "weapon uses old mesh " + str(model.model))
			_check(source.get_aabb().is_equal_approx(Refined.authored_bounds(refined)), "weapon scale or pivot bounds changed " + str(model.model))
			var tolerance := source.get_aabb().size.length() * .003
			_check(source.get_aabb().position.distance_to(refined.get_aabb().position) < tolerance and source.get_aabb().end.distance_to(refined.get_aabb().end) < tolerance, "weapon silhouette changed " + str(model.model))
			_check(source.get_surface_count() == refined.get_surface_count(), "weapon lost material surfaces " + str(model.model))
			_validate_mesh(refined, str(model.model), 0)
			for surface in source.get_surface_count():
				_validate_material(source.surface_get_material(surface), refined.surface_get_material(surface), str(model.model))
	for id in [36, 45, 46]:
		fixture.player.equip_weapon("gun%02d" % id, false)
		var overlays := 0
		for instance: MeshInstance3D in fixture.player.gun_mount.find_children("*", "MeshInstance3D", true, false):
			for surface in instance.mesh.get_surface_count():
				var active := instance.get_active_material(surface) as ShaderMaterial
				if active == null or active.shader != UnityMaterialRestorer.SOLID_OVERLAY_SHADER: continue
				overlays += 1
				var base: Texture2D = active.get_shader_parameter("base_texture")
				var overlay: Texture2D = active.get_shader_parameter("overlay_texture")
				_check(base != null and overlay != null, "missing two-texture weapon material %d" % id)
				if id == 46:
					_check(base.resource_path == Refined.texture_path("res://assets/models/weapons/33_EartherBreaker_D.png"), "Spreader lost refined atlas")
		_check(overlays > 0, "missing restored weapon overlay %d" % id)
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	print("EQUIPMENT_REFINEMENT_TEST_PASS armor_sets=%d weapon_meshes=%d armor_textures=%d thunder=dedicated_test" % [checked_armor_sets, checked_models.size(), checked_armor_textures.size()] if failures.is_empty() else "EQUIPMENT_REFINEMENT_TEST_FAIL count=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _posed_bounds(instance: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var transforms: Array[Transform3D] = []
	for bind in instance.skin.get_bind_count():
		var bone := skeleton.find_bone(instance.skin.get_bind_name(bind))
		if bone < 0: bone = instance.skin.get_bind_bone(bind)
		transforms.append(skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
	var bounds := AABB()
	var started := false
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for k in 4:
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][i * 4 + k]
				if weight > 0:
					point += (transforms[arrays[Mesh.ARRAY_BONES][i * 4 + k]] * arrays[Mesh.ARRAY_VERTEX][i]) * weight
			bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return bounds

func _validate_mesh(mesh: Mesh, label: String, bone_count: int) -> void:
	for surface in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		_check(vertices.size() == normals.size() and vertices.size() == uv.size(), "incomplete attributes " + label)
		for i in vertices.size():
			_check(vertices[i].is_finite() and normals[i].is_finite() and uv[i].is_finite(), "invalid vertex " + label)
			_check(absf(normals[i].length() - 1.0) < .03, "invalid normal " + label)
			if bone_count == 0: continue
			var total := 0.0
			for k in 4:
				var bone := int(a[Mesh.ARRAY_BONES][i*4+k])
				var weight := float(a[Mesh.ARRAY_WEIGHTS][i*4+k])
				_check(bone >= 0 and bone < bone_count and weight >= 0 and is_finite(weight), "invalid skin influence " + label)
				total += weight
			_check(absf(total-1.0) < .003, "unnormalized skin " + label)

func _validate_material(source: Material, refined: Material, label: String) -> void:
	if source == null:
		return
	_check(refined != null, "missing material " + label)
	if source is BaseMaterial3D:
		var actual: Texture2D
		if refined is BaseMaterial3D:
			actual = refined.albedo_texture
			_check(source.albedo_color.is_equal_approx(refined.albedo_color), "material tint changed " + label)
			_check(source.texture_repeat == refined.texture_repeat and source.cull_mode == refined.cull_mode, "material UV wrapping or culling changed " + label)
		elif refined is ShaderMaterial:
			actual = refined.get_shader_parameter("albedo_texture")
			var tint: Color = refined.get_shader_parameter("albedo_tint")
			_check(source.albedo_color.is_equal_approx(tint), "painted material lost original tint " + label)
		if source.albedo_texture != null:
			_check(actual != null and actual.resource_path == Refined.texture_path(source.albedo_texture.resource_path), "incorrect refined atlas " + label)
			if actual != null and label.begins_with("Armor"):
				_validate_armor_texture(actual)


func _validate_armor_texture(texture: Texture2D) -> void:
	var path := texture.resource_path
	if checked_armor_textures.has(path):
		return
	checked_armor_textures[path] = true
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK:
		_check(false, "missing armor texture import settings " + path)
		return
	_check(config.get_value("params", "compress/mode", -1) == 0, "armor texture must remain lossless " + path)
	_check(not config.get_value("params", "mipmaps/generate", true), "armor texture unexpectedly has mipmaps " + path)
	_check(config.get_value("params", "detect_3d/compress_to", -1) == 0, "armor texture enables automatic 3D compression " + path)
	var source := Image.load_from_file(ProjectSettings.globalize_path(path))
	var runtime := texture.get_image()
	if source == null or source.is_empty() or runtime == null or runtime.is_empty():
		_check(false, "cannot inspect actual imported armor pixels " + path)
		return
	_check(source.get_width() >= 1254 and source.get_height() >= 1254, "armor atlas below accepted native detail size " + path)
	_check(source.get_size() == runtime.get_size(), "runtime armor texture size differs from PNG " + path)
	_check(not runtime.has_mipmaps(), "runtime armor texture contains mip chain " + path)
	# Godot's alpha-border repair can replace RGB under fully transparent pixels.
	# Composite both images onto black in memory so that unused transparent atlas
	# padding does not cause false positives; visible imported paint must still
	# match the native PNG byte for byte. This catches an outdated .ctex cache.
	_check(_visible_pixels(source) == _visible_pixels(runtime), "runtime armor texture cache differs from native PNG " + path)


func _visible_pixels(image: Image) -> PackedByteArray:
	var decoded := image.duplicate() as Image
	if decoded.is_compressed():
		decoded.decompress()
	decoded.convert(Image.FORMAT_RGBA8)
	var data := decoded.get_data()
	for i in range(3, data.size(), 4):
		if data[i] < 26:
			data[i - 3] = 0
			data[i - 2] = 0
			data[i - 1] = 0
			data[i] = 0
	var cleaned := Image.create_from_data(decoded.get_width(), decoded.get_height(), false, Image.FORMAT_RGBA8, data)
	var canvas := Image.create(decoded.get_width(), decoded.get_height(), false, Image.FORMAT_RGBA8)
	canvas.fill(Color.BLACK)
	canvas.blend_rect(cleaned, Rect2i(Vector2i.ZERO, decoded.get_size()), Vector2i.ZERO)
	return canvas.get_data()
