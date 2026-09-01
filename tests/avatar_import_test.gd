extends SceneTree

const AVATAR_PATH := "res://assets/models/player/animated/player.gltf"
const AVATAR_ROOT := "res://assets/models/player/animated"
const BAG_MANIFEST_PATH := AVATAR_ROOT + "/bags/manifest.json"
const ARMOR_PARTS := ["Head", "Body", "Hand", "Foot"]
const ARMOR_VARIANT_COUNT := 21
const BAG_VARIANT_COUNT := 25
const EXPECTED_TEXTURE_COUNT := 105

func _initialize() -> void:
	var packed := load(AVATAR_PATH) as PackedScene
	assert(packed != null, "Animated player glTF did not import")
	var avatar := packed.instantiate()
	root.add_child(avatar)
	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	var imported_meshes: Array[MeshInstance3D] = []
	_collect(avatar, skeletons, players, imported_meshes)
	assert(skeletons.size() == 1, "Expected exactly one imported skeleton")
	assert(players.size() == 1, "Expected exactly one imported AnimationPlayer")
	var skeleton := skeletons[0]
	var animation_player := players[0]
	assert(skeleton.get_bone_count() == 28, "Expected the canonical 28-bone legacy skeleton")
	assert(skeleton.find_bone("r hand gun") >= 0, "Weapon attachment bone is missing")
	assert(skeleton.find_bone("fly_bag") >= 0, "Backpack attachment bone is missing")
	assert(skeleton.find_bone("Bip01 Spine1") >= 0, "Upper-body attachment bone is missing")
	assert(imported_meshes.size() == ARMOR_PARTS.size() * ARMOR_VARIANT_COUNT, "Expected 84 armor meshes")
	assert(animation_player.get_animation_list().size() == 79, "Expected all 79 recovered animations")
	for fly_animation in [
		"fly_idle", "fly_front", "fly_back", "fly_left", "fly_right",
		"fly_idle_rifle", "fly_rifle", "fly_stand_shoot_rifle",
		"fly_stand_shoot_laser", "fly_runshoot_jian"
	]:
		assert(animation_player.has_animation(fly_animation), "Missing flying armor clip: %s" % fly_animation)
	assert(animation_player.has_animation("idle_rifle"), "Rifle idle animation is missing")
	assert(animation_player.has_animation("run_rifle"), "Rifle run animation is missing")
	assert(animation_player.has_animation("stand_shoot_rifle"), "Rifle firing animation is missing")
	assert(animation_player.has_animation("dead"), "Death animation is missing")

	var textured_surfaces := 0
	for part_name: String in ARMOR_PARTS:
		for armor_id in range(ARMOR_VARIANT_COUNT):
			var node_name := "Armor%s_%02d" % [part_name, armor_id]
			var armor_mesh := avatar.find_child(node_name, true, false) as MeshInstance3D
			assert(armor_mesh != null, "Missing named armor mesh: " + node_name)
			assert(armor_mesh.mesh != null, "Armor mesh has no geometry: " + node_name)
			assert(armor_mesh.mesh.get_surface_count() > 0, "Armor mesh has no surfaces: " + node_name)
			assert(armor_mesh.mesh.get_aabb().size.length_squared() > 0.0, "Armor mesh has empty bounds: " + node_name)
			assert(armor_mesh.visible == (armor_id == 0), "%s has the wrong default visibility" % node_name)
			assert(armor_mesh.get_node_or_null(armor_mesh.skeleton) == skeleton, "%s is not bound to the shared skeleton" % node_name)
			for surface_index in range(armor_mesh.mesh.get_surface_count()):
				var material := armor_mesh.mesh.surface_get_material(surface_index) as BaseMaterial3D
				assert(material != null, "%s surface %d has no material" % [node_name, surface_index])
				if material.albedo_texture != null:
					textured_surfaces += 1
	assert(textured_surfaces >= imported_meshes.size(), "Recovered armor surfaces lost their Unity textures")

	# Prove variants are runtime-switchable without duplicating the Skeleton3D
	# or animation library. Runtime equipment code only needs to toggle these
	# exact node names.
	var default_head := avatar.find_child("ArmorHead_00", true, false) as MeshInstance3D
	var alternate_head := avatar.find_child("ArmorHead_20", true, false) as MeshInstance3D
	default_head.visible = false
	alternate_head.visible = true
	assert(not default_head.visible and alternate_head.visible, "Armor visibility switching failed")
	default_head.visible = true
	alternate_head.visible = false

	_validate_gltf_manifest()
	_validate_bags()
	animation_player.play("idle_rifle")
	await process_frame
	print("AVATAR_REST pelvis=%s head=%s hand=%s gun=%s" % [
		skeleton.get_bone_global_rest(skeleton.find_bone("Bip01 Pelvis")).origin,
		skeleton.get_bone_global_rest(skeleton.find_bone("Bip01 Head")).origin,
		skeleton.get_bone_global_rest(skeleton.find_bone("Bip01 R Hand")).origin,
		skeleton.get_bone_global_rest(skeleton.find_bone("r hand gun")).origin,
	])
	print("AVATAR_IMPORT_TEST_PASS bones=%d animations=%d gun_bone=%d" % [
		skeleton.get_bone_count(), animation_player.get_animation_list().size(), skeleton.find_bone("r hand gun")
	])
	avatar.queue_free()
	await process_frame
	quit()

func _validate_gltf_manifest() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AVATAR_PATH))
	assert(parsed is Dictionary, "Animated player glTF JSON is invalid")
	var gltf := parsed as Dictionary
	assert((gltf.get("meshes", []) as Array).size() == 84, "glTF must contain 84 named armor meshes")
	assert((gltf.get("skins", []) as Array).size() == 84, "Every armor mesh must have a skin")
	assert((gltf.get("animations", []) as Array).size() == 79, "glTF animation manifest is incomplete")
	assert((gltf.get("extensionsRequired", []) as Array).has("KHR_node_visibility"), "glTF does not preserve armor visibility")
	var images := gltf.get("images", []) as Array
	assert(images.size() == EXPECTED_TEXTURE_COUNT, "Expected %d unique armor textures, found %d" % [EXPECTED_TEXTURE_COUNT, images.size()])
	var image_uris := {}
	for image_entry: Dictionary in images:
		var uri := str(image_entry.get("uri", ""))
		assert(uri.begins_with("armor_textures/"), "Armor texture escaped its namespace: " + uri)
		assert(not image_uris.has(uri), "Duplicate glTF texture URI: " + uri)
		image_uris[uri] = true
		var texture_path := AVATAR_ROOT.path_join(uri)
		_validate_texture_file(texture_path, "armor")

func _validate_bags() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BAG_MANIFEST_PATH))
	assert(parsed is Dictionary, "Bag manifest is invalid")
	var manifest := parsed as Dictionary
	var bags := manifest.get("bags", []) as Array
	assert(int(manifest.get("count", -1)) == BAG_VARIANT_COUNT, "Bag manifest count is wrong")
	assert(bags.size() == BAG_VARIANT_COUNT, "Expected all 25 Unity bags")
	var ids := {}
	for bag_entry: Dictionary in bags:
		var bag_id := int(bag_entry.get("id", -1))
		assert(bag_id >= 0 and bag_id < BAG_VARIANT_COUNT, "Invalid bag ID in manifest")
		assert(not ids.has(bag_id), "Duplicate bag ID in manifest: %d" % bag_id)
		ids[bag_id] = true
		assert(str(bag_entry.get("name", "")) == "ArmorBag_%02d" % bag_id, "Bag node naming drifted")
		assert(int(bag_entry.get("vertices", 0)) > 0, "Bag %d has no vertices" % bag_id)
		assert(int(bag_entry.get("faces", 0)) > 0, "Bag %d has no faces" % bag_id)
		var obj_path := (AVATAR_ROOT + "/bags").path_join(str(bag_entry.get("obj", "")))
		assert(FileAccess.file_exists(obj_path), "Missing bag OBJ: " + obj_path)
		var bag_mesh := load(obj_path) as Mesh
		assert(bag_mesh != null and bag_mesh.get_surface_count() > 0, "Godot could not import bag %d" % bag_id)
		for texture_name: String in bag_entry.get("textures", []) as Array:
			_validate_texture_file(obj_path.get_base_dir().path_join(texture_name), "bag %d" % bag_id)
		assert(bool(bag_entry.get("animated_in_unity", false)) == (bag_id == 15 or bag_id == 23), "Unity animated-bag metadata is wrong")
	assert(ids.size() == BAG_VARIANT_COUNT, "Bag manifest IDs are incomplete")

func _validate_texture_file(texture_path: String, label: String) -> void:
	assert(FileAccess.file_exists(texture_path), "Missing exported %s texture: %s" % [label, texture_path])
	assert(FileAccess.file_exists(texture_path + ".import"), "Missing Godot import sidecar: " + texture_path)
	assert(ResourceLoader.exists(texture_path), "Godot did not import texture: " + texture_path)
	var image := Image.new()
	assert(image.load(ProjectSettings.globalize_path(texture_path)) == OK, "Could not decode texture: " + texture_path)
	assert(image.get_format() == Image.FORMAT_RGBA8, "Texture is not RGBA8: " + texture_path)
	assert(maxi(image.get_width(), image.get_height()) <= 4096, "Texture exceeds 4096px: " + texture_path)

func _collect(
	node: Node,
	skeletons: Array[Skeleton3D],
	players: Array[AnimationPlayer],
	meshes: Array[MeshInstance3D],
) -> void:
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_collect(child, skeletons, players, meshes)
