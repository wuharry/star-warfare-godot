extends Node3D

# Frozen pre-redesign Thunder (armor_06), independent of the current runtime map.
# Camera / neutral studio setup follows tests/equipment_refinement_capture.gd.
# No WarfarePlayer is needed: unrelated weapon class imports cannot block art review.
# No runtime resources or saves are written. Run with a windowed renderer:
# godot --path . --rendering-method gl_compatibility docs/art/thunder_mk_comparison_v1/render_mk1.tscn
const BASELINE := "res://assets/equipment_refined/armors/armor_06.scn"
const OUT := "res://docs/art/thunder_mk_comparison_v1/references/"
var source_textures: Array[ImageTexture] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := get_window()
	root.size = Vector2i(400, 480)
	root.content_scale_size = Vector2i(400, 480)
	root.title = "Thunder mk1 reference capture"
	# Render resolution must not depend on the desktop's maximum window size.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 1200)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	# This checkout lacks imported copies of the refined atlases. Populate only
	# the in-memory resource cache from the exact PNGs; do not regenerate imports.
	for stem: String in ["f8d96c60d30f", "dce7a1446714", "d6da6925f6b4", "df2d0a0b46da", "14ceb45bf36d"]:
		var source_path := "res://assets/equipment_refined/textures/" + stem + ".png"
		var source_image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		if source_image == null or source_image.is_empty():
			push_error("Cannot read Thunder texture " + source_path)
			get_tree().quit(1)
			return
		source_image.generate_mipmaps()
		var source_texture := ImageTexture.create_from_image(source_image)
		source_texture.take_over_path(source_path)
		source_textures.append(source_texture)
	var avatar := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate() as Node3D
	viewport.add_child(avatar)
	if not _apply_baseline_parts(avatar):
		get_tree().quit(1)
		return
	var visible_count := 0
	for part: MeshInstance3D in avatar.find_children("*", "MeshInstance3D", true, false):
		part.visible = part.name in ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"]
		if part.visible:
			if not part.has_meta("armor_rework"):
				push_error("Expected current refined armor part: " + str(part.name))
				get_tree().quit(1)
				return
			visible_count += 1
	if visible_count != 4:
		push_error("Expected exactly four Thunder armor parts")
		get_tree().quit(1)
		return
	for candidate in avatar.find_children("*", "AnimationPlayer", true, false):
		var animator := candidate as AnimationPlayer
		animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if animator.has_animation("idle_rifle"):
			animator.play("idle_rifle")
			animator.seek(0.0, true)
	for skeleton: Skeleton3D in avatar.find_children("*", "Skeleton3D", true, false):
		skeleton.force_update_all_bone_transforms()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.055, 0.055, 0.06)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	viewport.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color.WHITE
	key.light_energy = 1.0
	viewport.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color.WHITE
	fill.light_energy = 0.65
	fill.omni_range = 8
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.30
	camera.current = true
	viewport.add_child(camera)
	var output_dir := ProjectSettings.globalize_path(OUT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK:
		push_error("Cannot create reference output directory: " + error_string(directory_error))
		get_tree().quit(1)
		return
	for view: String in ["front", "rear"]:
		camera.position = Vector3(2.5, 1.8, -2.8) if view == "front" else Vector3(-2.5, 1.8, 2.8)
		camera.look_at(Vector3(0, 1.0, 0))
		fill.position = camera.position
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var output_path := OUT + "mk1_current_" + view + ".png"
		var error := viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_path))
		if error != OK:
			push_error("Cannot save " + output_path + ": " + error_string(error))
			get_tree().quit(1)
			return
		print("THUNDER_MK1_CAPTURE ", output_path)
	avatar.queue_free()
	await get_tree().process_frame
	print("THUNDER_MK1_CAPTURE_PASS viewport=1000x1200 renderer=gl_compatibility set=06 frames=2")
	get_tree().quit(0)


func _apply_baseline_parts(avatar: Node3D) -> bool:
	# Never call ensure_parts here: set 06 now resolves to the redesigned scene.
	# This archive must continue reproducing the original before screenshots.
	var packed := load(BASELINE) as PackedScene
	if packed == null:
		push_error("Cannot load original Thunder baseline: " + BASELINE)
		return false
	var baseline := packed.instantiate() as Node3D
	var replaced := 0
	for child: Node in baseline.get_children():
		var replacement := child as MeshInstance3D
		if replacement == null:
			continue
		var existing := avatar.find_child(str(replacement.name), true, false) as MeshInstance3D
		if existing == null:
			push_error("Missing original Thunder node: " + str(replacement.name))
			baseline.free()
			return false
		existing.material_override = null
		for surface in existing.get_surface_override_material_count():
			existing.set_surface_override_material(surface, null)
		existing.mesh = replacement.mesh
		existing.skin = replacement.skin
		existing.transform = replacement.transform
		existing.extra_cull_margin = replacement.extra_cull_margin
		existing.set_meta("armor_rework", replacement.get_meta("armor_rework"))
		replaced += 1
	baseline.free()
	if replaced != 4:
		push_error("Original Thunder baseline must supply exactly four parts")
		return false
	return true
