extends SceneTree

const AVATAR_PATH := "res://assets/models/player/animated/player.gltf"

func _initialize() -> void:
	var packed := load(AVATAR_PATH) as PackedScene
	assert(packed != null, "Animated player glTF did not import")
	var avatar := packed.instantiate()
	root.add_child(avatar)
	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	_collect(avatar, skeletons, players)
	assert(skeletons.size() == 1, "Expected exactly one imported skeleton")
	assert(players.size() == 1, "Expected exactly one imported AnimationPlayer")
	var skeleton := skeletons[0]
	var animation_player := players[0]
	assert(skeleton.get_bone_count() >= 20, "Legacy skeleton is incomplete")
	assert(skeleton.find_bone("r hand gun") >= 0, "Weapon attachment bone is missing")
	assert(skeleton.find_bone("fly_bag") >= 0, "Backpack attachment bone is missing")
	assert(animation_player.has_animation("idle_rifle"), "Rifle idle animation is missing")
	assert(animation_player.has_animation("run_rifle"), "Rifle run animation is missing")
	assert(animation_player.has_animation("stand_shoot_rifle"), "Rifle firing animation is missing")
	assert(animation_player.has_animation("dead"), "Death animation is missing")
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

func _collect(node: Node, skeletons: Array[Skeleton3D], players: Array[AnimationPlayer]) -> void:
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	for child in node.get_children():
		_collect(child, skeletons, players)
