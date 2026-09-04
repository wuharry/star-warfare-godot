extends SceneTree

# Generates catalog thumbnails from the exact meshes used by the playable
# character. Run with:
# godot --headless --path . --script res://tools/render_armor_thumbnails.gd

const ArmorCatalogData = preload("res://scripts/core/armor_catalog.gd")
const AVATAR_PATH := "res://assets/models/player/animated/player.gltf"
const BAG_DIR := "res://assets/models/player/animated/bags/"
const OUTPUT_DIR := "res://assets/ui/armor_thumbnails/"
const SIZE := Vector2i(256, 256)
const PART_PREFIXES := {
	"head": "armorhead_",
	"body": "armorbody_",
	"arms": "armorhand_",
	"legs": "armorfoot_",
}

var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D


func _initialize() -> void:
	call_deferred("_render_all")


func _render_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build_stage()
	var avatar_scene := load(AVATAR_PATH) as PackedScene
	if avatar_scene == null:
		push_error("Could not load armor avatar: " + AVATAR_PATH)
		quit(1)
		return
	var avatar := avatar_scene.instantiate() as Node3D
	avatar.rotation_degrees.y = -90.0
	stage.add_child(avatar)
	_pose_avatar(avatar)
	var catalog := ArmorCatalogData.build_items()
	var meshes: Array[MeshInstance3D] = []
	for candidate in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		mesh_instance.visible = false
		meshes.append(mesh_instance)

	for part_key: String in PART_PREFIXES:
		for item_key: String in _item_ids(catalog, part_key):
			var item: Dictionary = catalog[item_key]
			var visual_id := int(item.visual_id)
			var visible_meshes := _show_part(meshes, str(PART_PREFIXES[part_key]), visual_id)
			if visible_meshes.is_empty():
				push_warning("No mesh for %s" % item_key)
				continue
			_frame_avatar_part(avatar, part_key)
			await _save_frame("armor_%s_%02d.png" % [part_key, visual_id])

	avatar.queue_free()
	await process_frame
	for item_key: String in _item_ids(catalog, "bag"):
		var item: Dictionary = catalog[item_key]
		var visual_id := int(item.visual_id)
		var bag_name := "ArmorBag_%02d" % visual_id
		var mesh_path := "%s%s/%s.obj" % [BAG_DIR, bag_name, bag_name]
		var mesh := load(mesh_path) as Mesh if ResourceLoader.exists(mesh_path) else null
		if mesh == null:
			push_warning("No mesh for %s" % item_key)
			continue
		var instance := MeshInstance3D.new()
		instance.name = bag_name
		instance.mesh = mesh
		stage.add_child(instance)
		_frame_nodes([instance], "bag")
		await _save_frame("armor_bag_%02d.png" % visual_id)
		instance.queue_free()
		await process_frame

	print("ARMOR_THUMBNAILS_RENDERED")
	quit(0)


func _item_ids(catalog: Dictionary, part_key: String) -> Array[String]:
	var ids: Array[String] = []
	for item_key_value in catalog:
		var item_key := str(item_key_value)
		if str(catalog[item_key].part_key) == part_key:
			ids.append(item_key)
	ids.sort_custom(func(a: String, b: String): return int(catalog[a].id) < int(catalog[b].id))
	return ids


func _build_stage() -> void:
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.012, 0.018, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.38, 0.46)
	env.ambient_light_energy = 1.4
	environment.environment = env
	stage.add_child(environment)
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.current = true
	stage.add_child(camera)
	key_light = DirectionalLight3D.new()
	key_light.light_color = Color(0.55, 0.9, 1.0)
	key_light.light_energy = 2.4
	key_light.rotation_degrees = Vector3(-35, -35, 0)
	stage.add_child(key_light)
	fill_light = DirectionalLight3D.new()
	fill_light.light_color = Color(1.0, 0.48, 0.2)
	fill_light.light_energy = 1.1
	fill_light.rotation_degrees = Vector3(25, 145, 0)
	stage.add_child(fill_light)


func _show_part(meshes: Array[MeshInstance3D], prefix: String, visual_id: int) -> Array[Node3D]:
	var visible_nodes: Array[Node3D] = []
	for mesh_instance: MeshInstance3D in meshes:
		var lower_name := mesh_instance.name.to_lower()
		var matches := false
		if lower_name.begins_with(prefix):
			var id_text := lower_name.trim_prefix(prefix)
			matches = id_text.is_valid_int() and int(id_text) == visual_id
		mesh_instance.visible = matches
		if matches:
			visible_nodes.append(mesh_instance)
	return visible_nodes


func _pose_avatar(avatar: Node3D) -> void:
	for candidate in avatar.find_children("*", "AnimationPlayer", true, false):
		var animation_player := candidate as AnimationPlayer
		if animation_player.has_animation("idle_rifle"):
			animation_player.play("idle_rifle")
			animation_player.seek(0.0, true)
			return


func _frame_avatar_part(avatar: Node3D, part_key: String) -> void:
	var skeleton: Skeleton3D = null
	for candidate in avatar.find_children("*", "Skeleton3D", true, false):
		skeleton = candidate as Skeleton3D
		break
	if skeleton == null:
		return
	var wanted: Array[String] = []
	match part_key:
		"head":
			wanted = ["Bip01 Neck", "Bip01 Head"]
		"body":
			wanted = ["Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1", "Bip01 Neck"]
		"arms":
			wanted = ["Bip01 L UpperArm", "Bip01 L Forearm", "Bip01 L Hand", "Bip01 R UpperArm", "Bip01 R Forearm", "Bip01 R Hand"]
		"legs":
			wanted = ["Bip01 L Thigh", "Bip01 L Calf", "Bip01 L Foot", "Bip01 R Thigh", "Bip01 R Calf", "Bip01 R Foot"]
	var bounds := AABB()
	var has_bounds := false
	for bone_name: String in wanted:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var point := (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin
		var point_bounds := AABB(point, Vector3(0.001, 0.001, 0.001))
		bounds = bounds.merge(point_bounds) if has_bounds else point_bounds
		has_bounds = true
	if not has_bounds:
		return
	var margin := 0.38 if part_key == "head" else 0.28
	bounds = bounds.grow(margin)
	_frame_bounds(bounds, part_key)


func _frame_nodes(nodes: Array, part_key: String) -> void:
	var bounds := AABB()
	var has_bounds := false
	for node_value in nodes:
		var node := node_value as MeshInstance3D
		if node == null or node.mesh == null:
			continue
		var node_bounds: AABB = node.global_transform * node.get_aabb()
		bounds = bounds.merge(node_bounds) if has_bounds else node_bounds
		has_bounds = true
	if not has_bounds:
		return
	_frame_bounds(bounds, part_key)


func _frame_bounds(bounds: AABB, part_key: String) -> void:
	var center := bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var distance_factor := 2.25
	if part_key == "arms":
		distance_factor = 1.78
	elif part_key == "legs":
		distance_factor = 1.9
	var distance := maxf(0.75, extent * distance_factor)
	var direction := Vector3(0.62, 0.22, 1.0).normalized()
	if part_key == "arms":
		direction = Vector3(0.72, 0.08, 1.0).normalized()
	elif part_key == "legs":
		direction = Vector3(0.6, 0.12, 1.0).normalized()
	camera.position = center + direction * distance
	camera.look_at(center, Vector3.UP)


func _save_frame(file_name: String) -> void:
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + file_name))
	if error != OK:
		push_error("Failed to save %s: %s" % [file_name, error_string(error)])
