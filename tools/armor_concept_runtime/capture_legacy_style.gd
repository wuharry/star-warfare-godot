extends SceneTree

## Raw original references: no gameplay replacement, AI texture or animation.
const SOURCE := "res://assets/models/player/animated/player.gltf"
const OUT := "res://test_output/armor_style_base/"
const IDS := [0, 2, 3, 4, 7, 9, 10, 11, 12]
const VIEWS := {
	"quarter": Vector3(3.3, 1.8, -5),
	"front": Vector3(0, 1.04, -6),
	"side": Vector3(6, 1.04, 0),
	"rear": Vector3(0, 1.04, 6),
}
const PREFIXES := ["ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 720)
	root.title = "原版裝甲風格基準 — 原始模型／貼圖／rest pose"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0c1013")
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.35
	stage.add_child(camera)
	camera.current = true
	var avatar := (load(SOURCE) as PackedScene).instantiate() as Node3D
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
			assert(material != null, "Original material missing")
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.set_surface_override_material(surface, material)
	var files: Array[Dictionary] = []
	for id: int in IDS:
		var names: Array[String] = []
		for prefix: String in PREFIXES:
			names.append(prefix + "%02d" % id)
		for mesh: MeshInstance3D in meshes:
			mesh.visible = String(mesh.name) in names
		for view: String in VIEWS:
			camera.position = VIEWS[view]
			camera.look_at(Vector3(0, 1.04, 0))
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path := OUT + "original_%02d_%s.png" % [id, view]
			assert(viewport.get_texture().get_image().save_png(path) == OK, "Reference capture failed")
			files.append({"id": id, "view": view, "path": path})
	var report := {
		"source": SOURCE,
		"viewport": viewport.size,
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"pose": "original imported skeleton rest pose; no animation",
		"materials": "raw imported textures and tint; UNSHADED as original armor shader behavior",
		"files": files,
	}
	var file := FileAccess.open(OUT + "capture.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("LEGACY_STYLE_CAPTURE_PASS images=%d" % files.size())
	quit()
