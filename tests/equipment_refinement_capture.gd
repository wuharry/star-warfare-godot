extends Node3D

const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Refined = preload("res://scripts/core/equipment_refinement.gd")
const OUT := "res://test_output/equipment_refinement/preview/"
var fixture: Node3D
var records: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(800, 900)
	get_window().content_scale_size = Vector2i(800, 900)
	fixture = Fixture.new()
	add_child(fixture)
	fixture.setup()
	fixture.label.visible = false
	fixture.player.backpack_socket.visible = false
	fixture.player.gun_socket.visible = false
	fixture.player.left_gun_socket.visible = false
	fixture.view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.view_camera.size = 2.25
	fixture.fill.light_energy = .8
	for child in fixture.get_children():
		if child is DirectionalLight3D: child.light_energy = 1.0
	var original := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	Visuals._restore_original_materials(original)
	if OS.get_cmdline_user_args().has("--weapons-only"):
		for record: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(OUT + "captures.json")):
			if record.kind == "armor": records.append(record)
	for id in range(1, Catalog.SET_NAMES.size()):
		if OS.get_cmdline_user_args().has("--weapons-only"): continue
		var key := "armor_%02d" % id
		if OS.get_cmdline_user_args().has("--sample") and id not in [1, 2, 21, 28]: continue
		if OS.get_cmdline_user_args().has("--black-hole") and id != 18: continue
		var source: Node = original
		if id >= Catalog.CALLOFMINI_FIRST_ID:
			source = (load(Catalog.gameplay_scene_path(id)) as PackedScene).instantiate()
		Visuals.ensure_parts(fixture.player.recovered_avatar, {"head": id, "body": id, "hand": id, "foot": id})
		for part: MeshInstance3D in fixture.player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
			part.visible = str(part.name).ends_with("_%02d" % id)
		var refined := (load(Refined.ROOT + "armors/%s.scn" % key) as PackedScene).instantiate()
		for version in ["original", "refined"]:
			for prefix in Visuals.ORIGINAL_PART_PREFIXES:
				var name_key: String = prefix + "%02d" % id
				var part := fixture.player.recovered_avatar.find_child(name_key, true, false) as MeshInstance3D
				var template := (source if version == "original" else refined).find_child(name_key, true, false) as MeshInstance3D
				# Release overrides before replacing a mesh with a different surface count.
				for surface in part.get_surface_override_material_count(): part.set_surface_override_material(surface, null)
				part.mesh = template.mesh
				part.skin = template.skin
				part.transform = template.transform
				for surface in part.mesh.get_surface_count(): part.set_surface_override_material(surface, template.get_active_material(surface))
			fixture.player.recovered_animation_tree.active = false
			fixture.player._play_recovered_animation("idle_rifle", 0, true)
			fixture.player.recovered_animation_player.advance(0)
			fixture.player.recovered_skeleton.force_update_all_bone_transforms()
			for view in ["front", "side", "rear"]:
				fixture.set_view(view)
				fixture.view_camera.look_at(Vector3(0, 1.0, 0))
				await _save(key, version, view)
		refined.free()
		if source != original: source.free()
		records.append({"key": key, "kind": "armor", "name": Catalog.SET_NAMES[id]})
		print("CAPTURED ", key)
	original.free()
	fixture.player.visible = false
	fixture.view_camera.size = 2.5
	for key: String in GameState.WEAPONS:
		if OS.get_cmdline_user_args().has("--black-hole"): continue
		if OS.get_cmdline_user_args().has("--sample") and key not in ["gun00", "gun11", "gun22", "gun45"]: continue
		var weapon: Dictionary = GameState.WEAPONS[key]
		var source := load("res://assets/models/weapons/%s.obj" % weapon.model) as Mesh
		for version in ["original", "refined"]:
			var instance := MeshInstance3D.new()
			instance.mesh = source if version == "original" else Refined.weapon_mesh(weapon.model)
			fixture.player._repair_recovered_weapon_materials(instance, int(weapon.id))
			if version == "original": _restore_original_shader_textures(instance)
			var bounds := source.get_aabb()
			var scale_factor := 1.9 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			var longest_axis := bounds.size.max_axis_index()
			instance.rotation_degrees = Vector3(0, 90, 0) if longest_axis == 2 else (Vector3(0, 0, 90) if longest_axis == 1 else Vector3.ZERO)
			instance.scale = Vector3.ONE * scale_factor
			instance.position = -(instance.basis * bounds.get_center())
			add_child(instance)
			var angles := {"front": Vector3(1.7, 1.0, -3), "side": Vector3(3, .6, -.2), "rear": Vector3(-1.7, 1, 3)}
			for view: String in angles:
				fixture.view_camera.position = angles[view]
				fixture.view_camera.look_at(Vector3.ZERO)
				fixture.fill.position = fixture.view_camera.position
				await _save(key, version, view)
			instance.free()
		records.append({"key": key, "kind": "weapon", "name": weapon.name})
		print("CAPTURED ", key)
	var file := FileAccess.open(OUT + "captures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	fixture.cleanup()
	await get_tree().process_frame
	print("EQUIPMENT_CAPTURE_PASS entries=", records.size())
	get_tree().quit()

func _save(key: String, version: String, view: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "%s_%s_%s.png" % [key, version, view]))
	assert(error == OK)

func _restore_original_shader_textures(instance: MeshInstance3D) -> void:
	# The UFO runtime repair deliberately remaps its hardcoded atlas. Undo only
	# that texture mapping for the original side of this comparison.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Refined.ROOT + "manifest.json"))
	var originals := {}
	for job: Dictionary in manifest.textures:
		if job.status == "approved": originals[job.output] = job.source
	for surface in instance.mesh.get_surface_count():
		var active := instance.get_active_material(surface) as ShaderMaterial
		if active == null: continue
		var material := active.duplicate() as ShaderMaterial
		for parameter: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(parameter.name)
			if value is Texture2D and originals.has(value.resource_path):
				material.set_shader_parameter(parameter.name, load(originals[value.resource_path]))
		instance.set_surface_override_material(surface, material)
