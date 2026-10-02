extends SceneTree

## Research only: raw SW imports and byte-identical CoM DAE with original PNGs.
const OUT := "res://test_output/armor_original_corpus/"
const COM := [
	["Assault Armor", "AssaultArmor"], ["Combat Suit", "CombatSuit"],
	["Drillmaster", "Drillmaster"], ["Heavy Battlesuit", "HeavyBattlesuit"],
	["Mark-6 117R", "Mark6117R"], ["Recon Suit", "ReconSuit"],
	["Sanguine Chaos", "Sanguine"], ["Training Suit", "TrainingSuit"],
]
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 720)
	root.title = "Original armor corpus — source assets only"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	viewport = SubViewport.new()
	viewport.size = root.size
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("0c1013")
	stage.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	stage.add_child(camera)
	var avatar := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	stage.add_child(avatar)
	for animation: AnimationPlayer in avatar.find_children("*", "AnimationPlayer", true, false):
		animation.stop()
	for skeleton: Skeleton3D in avatar.find_children("*", "Skeleton3D", true, false):
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
	var meshes := avatar.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface).duplicate() as BaseMaterial3D
			assert(material != null)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.set_surface_override_material(surface, material)
	for id: int in range(21):
		for mesh: MeshInstance3D in meshes:
			mesh.visible = String(mesh.name) in ["ArmorHead_%02d" % id, "ArmorBody_%02d" % id, "ArmorHand_%02d" % id, "ArmorFoot_%02d" % id]
		await _capture(id, Vector3(0, 1.04, 0), 2.35)
	avatar.queue_free()
	await process_frame
	for i: int in COM.size():
		var directory := "res://assets/callOfMini/enhanced/%s/" % COM[i][0]
		var model := (load(directory + COM[i][1] + ".dae") as PackedScene).instantiate() as Node3D
		# Raw CoM faces +Z; raw SW faces -Z. Rotate the display root only.
		model.rotate_y(PI)
		stage.add_child(model)
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for surface: int in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as BaseMaterial3D
				assert(source != null and source.albedo_texture != null)
				var filename := source.albedo_texture.resource_path.get_file()
				var raw := Image.load_from_file(directory + "source/" + filename)
				assert(raw != null, "Missing original texture: " + filename)
				var material := source.duplicate() as BaseMaterial3D
				material.albedo_texture = ImageTexture.create_from_image(raw)
				material.albedo_color = Color.WHITE
				# Neutral diffuse inspection, not a claim about the original CoM renderer.
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh.set_surface_override_material(surface, material)
		await _capture(21 + i, bounds.get_center(), bounds.size.y * 1.18)
		model.queue_free()
		await process_frame
	var report := {"viewport": [640, 720], "renderer": "gl_compatibility", "sw": "raw player.gltf rest pose; original tint; UNSHADED", "com": "ZIP-identical DAE and source PNG; unlit inspection with white tint; display root rotated 180 degrees Y from source +Z forward to SW -Z forward; each model framed to height independently, not retargeted; UV unchanged", "files": records}
	var file := FileAccess.open(OUT + "capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ORIGINAL_CORPUS_CAPTURE_PASS images=%d" % records.size())
	quit()


func _capture(id: int, center: Vector3, size: float) -> void:
	camera.size = size
	var directions := {"front": Vector3(0, 0, -1), "quarter": Vector3(0.55, 0.15, -1), "side": Vector3(1, 0, 0), "rear": Vector3(0, 0, 1)}
	for view: String in directions:
		camera.position = center + directions[view].normalized() * maxf(size * 3, 6.0)
		camera.look_at(center)
		await process_frame
		await process_frame
		# Explicit draw also works when macOS stops drawing an occluded window.
		RenderingServer.force_draw(false)
		var path := OUT + "original_%02d_%s.png" % [id, view]
		assert(viewport.get_texture().get_image().save_png(path) == OK)
		records.append({"id": id, "view": view, "path": path, "ortho_size": size, "center": [center.x, center.y, center.z]})
