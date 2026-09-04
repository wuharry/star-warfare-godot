class_name WarfarePlayer
extends CharacterBody3D

signal health_changed(health: float, shield: float)
signal ammo_changed(current: int, reserve: int, reloading: bool)
signal weapon_changed(weapon_id: String, weapon_data: Dictionary)
signal dash_changed(ratio: float)
signal hit_confirmed(actual_damage: float)
signal kill_confirmed
signal shot_fired(weapon_data: Dictionary)
signal died

const ProjectileScript = preload("res://scripts/game/projectile.gd")
const ARMOR_HP_SCALE := 0.01
const CAMERA_BASE_HEIGHT := 1.683712
const FLY_CAMERA_OFFSET := 0.25
const UPPER_BODY_AIM_LIMIT := deg_to_rad(75.0)

var max_health := 100.0
var max_shield := 100.0
var health := 100.0
var shield := 100.0
var move_speed := 8.2
var gravity := 24.0
var dash_speed := 19.0
var dash_duration := 0.18
var dash_cooldown := 1.65
var dash_time := 0.0
var dash_cooldown_left := 0.0
var dash_direction := Vector3.ZERO
var dead := false
var armor_skills: Dictionary = {}
var speed_on_hit_left := 0.0
var float_audio_state := ""
var armor_power_controller: Node

var camera_yaw := 0.0
var body_yaw := 0.0
# ThirdPersonStandardCameraScript left angelV at its C# default of zero.  Start
# level with the same horizontal sight line as the original game.
var camera_pitch := 0.0
# Recovered from every original Unity level's
# ThirdPersonStandardCameraScript component.
var camera_distance := 2.2
var touch_move := Vector2.ZERO
var touch_fire := false
var touch_fire_started := false
var touch_dash_requested := false
var touch_reload_requested := false

var camera_rig: Node3D
var pitch_node: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var model: Node3D
var gun_mount: Node3D
var gun_mount_rest_position := Vector3.ZERO
var gun_mount_rest_rotation := Quaternion.IDENTITY
var gun_recoil_offset := Vector3(0.0, 0.0, 0.1)
var muzzle: Marker3D
var muzzle_light: OmniLight3D
var animation_clock := 0.0
var recovered_avatar: Node3D
var recovered_skeleton: Skeleton3D
var recovered_animation_player: AnimationPlayer
var recovered_animation_tree: AnimationTree
var recovered_animation_blend_tree: AnimationNodeBlendTree
var recovered_locomotion_node: AnimationNodeAnimation
var recovered_upper_body_node: AnimationNodeAnimation
var recovered_upper_body_seek: AnimationNodeTimeSeek
var recovered_upper_body_blend: AnimationNodeBlend2
var recovered_animation_name := ""
var recovered_locomotion_name := ""
var recovered_upper_body_name := ""
var recovered_layered_animation := false
var upper_body_aim_override_active := false
var gun_socket: BoneAttachment3D
var left_gun_socket: BoneAttachment3D
var backpack_socket: BoneAttachment3D
var backpack_visual: MeshInstance3D

var weapon_order: Array[String] = []
var current_weapon_id := "gun00"
var current_weapon: Dictionary = {}
var max_energy := 9999999
var energy := 9999999
var weapon_magazines: Dictionary = {}
var shot_cooldown := 0.0
var auto_reload_left := -1.0
var reload_left := 0.0
var reload_elapsed := 0.0
var reload_total := 0.0
var reload_start_rounds := 0
var reload_event_mask := 0
var reload_hand_start_local := Vector3.ZERO
var reload_part_socket: Marker3D
var attached_reload_part: Node3D
var reload_hand_prop: Node3D
var weapon_audio_active := false
var shoot_pose_left := 0.0
var restart_shoot_animation_requested := false
var hurt_pose_left := 0.0
var footstep_clock := 0.0
var tracer_shot_counts: Dictionary = {}

var fire_audio: AudioStreamPlayer3D
var hurt_audio: AudioStreamPlayer3D

func _ready() -> void:
	name = "Player"
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1
	_apply_armor_stats(true)
	_build_collision()
	_build_visual()
	_build_camera()
	_build_audio()
	_refresh_weapon_order_for_bag()
	var starting_weapon := GameState.selected_weapon if weapon_order.has(GameState.selected_weapon) else weapon_order[0]
	equip_weapon(starting_weapon, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("mobile") else Input.MOUSE_MODE_CAPTURED
	health_changed.emit(health, shield)
	if not GameState.armor_changed.is_connected(_on_armor_changed):
		GameState.armor_changed.connect(_on_armor_changed)

func _apply_armor_stats(restore_full := false) -> void:
	var previous_max := max_health
	armor_skills = GameState.get_armor_skills()
	max_health = 100.0 + float(armor_skills.get("hp", 0.0)) * ARMOR_HP_SCALE
	move_speed = maxf(3.5, 8.2 + float(armor_skills.get("speed_boost", 0.0)))
	if restore_full:
		health = max_health
	else:
		health = clampf(health + maxf(0.0, max_health - previous_max), 0.0, max_health)
	if is_inside_tree():
		health_changed.emit(health, shield)

func _on_armor_changed(_part_key: String, _armor_key: String) -> void:
	_apply_armor_stats()
	if is_instance_valid(armor_power_controller) and armor_power_controller.has_method("refresh_available_skills"):
		armor_power_controller.refresh_available_skills()
	_apply_recovered_armor_visibility()
	if _part_key in ["bag", "body"]:
		_refresh_recovered_backpack()
	if _part_key == "bag":
		_refresh_weapon_order_for_bag()
		if not weapon_order.has(current_weapon_id):
			equip_weapon(weapon_order[0], false)
	if float(armor_skills.get("fly", 0.0)) <= 0.0:
		_stop_flying_audio()

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.46
	capsule.height = 1.82
	collision.shape = capsule
	collision.position.y = 0.92
	add_child(collision)

func _build_visual() -> void:
	model = Node3D.new()
	model.name = "ArmorModel"
	add_child(model)

	var cyan := _material(Color(0.08, 0.48, 0.62), 0.32, 0.68)
	var dark := _material(Color(0.045, 0.075, 0.09), 0.72, 0.25)
	var glow := _material(Color(0.04, 0.75, 1.0), 0.24, 0.35, Color(0.02, 0.52, 0.9))

	var animated_path := "res://assets/models/player/animated/player.gltf"
	var restored_path := "res://assets/models/player/player.obj"
	if ResourceLoader.exists(animated_path):
		var animated_scene := load(animated_path) as PackedScene
		if animated_scene:
			recovered_avatar = animated_scene.instantiate() as Node3D
			if recovered_avatar:
				recovered_avatar.name = "RecoveredAnimatedAvatar"
				model.add_child(recovered_avatar)
				recovered_skeleton = _find_skeleton(recovered_avatar)
				recovered_animation_player = _find_animation_player(recovered_avatar)
				_prepare_recovered_animations()
				_add_recovered_backpack()
				_apply_recovered_armor_visibility()
	if not recovered_avatar and ResourceLoader.exists(restored_path):
		var restored := MeshInstance3D.new()
		restored.mesh = load(restored_path)
		_normalize_mesh(restored, 2.05)
		model.add_child(restored)
	elif not recovered_avatar:
		_add_box(model, Vector3(0.72, 0.82, 0.42), Vector3(0, 1.23, 0), cyan, "Torso")
		_add_box(model, Vector3(0.84, 0.18, 0.52), Vector3(0, 1.62, 0), dark, "Shoulders")
		_add_sphere(model, Vector3(0.27, 0.31, 0.27), Vector3(0, 1.91, -0.01), dark, "Helmet")
		_add_box(model, Vector3(0.31, 0.09, 0.29), Vector3(0, 1.91, -0.25), glow, "Visor")
		for side in [-1.0, 1.0]:
			var arm := _add_capsule(model, 0.16, 0.72, Vector3(side * 0.54, 1.27, 0), cyan, "Arm")
			arm.name = "ArmL" if side < 0 else "ArmR"
			var leg := _add_capsule(model, 0.19, 0.82, Vector3(side * 0.23, 0.48, 0), dark, "Leg")
			leg.name = "LegL" if side < 0 else "LegR"
			_add_box(model, Vector3(0.28, 0.18, 0.48), Vector3(side * 0.23, 0.12, -0.07), cyan, "Boot")
		_add_box(model, Vector3(0.58, 0.7, 0.2), Vector3(0, 1.27, 0.31), dark, "Backpack")
		for side in [-1.0, 1.0]:
			_add_box(model, Vector3(0.12, 0.4, 0.1), Vector3(side * 0.23, 1.28, 0.45), glow, "PowerCell")

	if recovered_skeleton and recovered_skeleton.find_bone("r hand gun") >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.name = "RecoveredWeaponSocket"
		attachment.bone_name = "r hand gun"
		recovered_skeleton.add_child(attachment)
		gun_socket = attachment
		# Keep recoil on a child pivot. BoneAttachment3D is rewritten by the
		# AnimationPlayer each frame, so moving it directly cancels the recoil.
		gun_mount = Node3D.new()
		gun_mount.name = "GunMount"
		# Unity's weapon helper aims along local -Y. The recovered OBJ exporter
		# stores barrel length along Godot -Z, so bridge those authored axes.
		gun_mount.rotation_degrees.x = -90.0
		gun_recoil_offset = Vector3(0.0, 0.1, 0.0)
		gun_socket.add_child(gun_mount)
	elif recovered_skeleton and recovered_skeleton.find_bone("Bip01 R Hand") >= 0:
		# Compatibility fallback for an older avatar export without the helper
		# bone. This is the converted idle_rifle socket transform from Unity.
		var attachment := BoneAttachment3D.new()
		attachment.name = "RecoveredHandSocket"
		attachment.bone_name = "Bip01 R Hand"
		recovered_skeleton.add_child(attachment)
		gun_socket = attachment
		gun_mount = Node3D.new()
		gun_mount.name = "GunMount"
		gun_mount.position = Vector3(-0.11418992, 0.079515845, 0.03771901)
		gun_mount.quaternion = Quaternion(0.051140323, -0.025414221, -0.63381046, 0.7713774).normalized()
		gun_socket.add_child(gun_mount)
	else:
		gun_mount = Node3D.new()
		gun_mount.name = "GunMount"
		gun_mount.position = Vector3(0.42, 1.24, -0.48)
		model.add_child(gun_mount)
	if recovered_skeleton and recovered_skeleton.find_bone("l hand gun") >= 0:
		left_gun_socket = BoneAttachment3D.new()
		left_gun_socket.name = "RecoveredLeftWeaponSocket"
		left_gun_socket.bone_name = "l hand gun"
		recovered_skeleton.add_child(left_gun_socket)
	gun_mount_rest_position = gun_mount.position
	gun_mount_rest_rotation = gun_mount.quaternion
	_build_gun_visual()

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _prepare_recovered_animations() -> void:
	if not recovered_animation_player:
		return
	for animation_name in recovered_animation_player.get_animation_list():
		var animation := recovered_animation_player.get_animation(animation_name)
		var flying_locomotion := animation_name in [
			"fly_idle", "fly_front", "fly_back", "fly_left", "fly_right",
			"fly_rifle", "fly_shotgun", "fly_bazinga", "fly_jian",
			"fly_bow", "fly_fist", "fly_machinegun", "fly_Sniper",
			"fly_stand_shoot_jian_lower"
		]
		if (
			animation_name.begins_with("idle_")
			or animation_name.begins_with("fly_idle_")
			or (animation_name.begins_with("run_") and not animation_name.begins_with("run_shoot_"))
			or flying_locomotion
		):
			animation.loop_mode = Animation.LOOP_LINEAR
	_build_recovered_animation_layers()
	_play_recovered_animation("idle_rifle", 0.0)

func _build_recovered_animation_layers() -> void:
	if not recovered_animation_player or not recovered_skeleton or not recovered_avatar:
		return
	recovered_animation_blend_tree = AnimationNodeBlendTree.new()
	recovered_locomotion_node = AnimationNodeAnimation.new()
	recovered_locomotion_node.animation = &"run_rifle"
	recovered_upper_body_node = AnimationNodeAnimation.new()
	recovered_upper_body_node.animation = &"run_shoot_rifle"
	recovered_upper_body_seek = AnimationNodeTimeSeek.new()
	recovered_upper_body_blend = AnimationNodeBlend2.new()
	recovered_upper_body_blend.sync = true
	recovered_upper_body_blend.filter_enabled = true
	recovered_animation_blend_tree.add_node("locomotion", recovered_locomotion_node, Vector2(0.0, 80.0))
	recovered_animation_blend_tree.add_node("upper_body", recovered_upper_body_node, Vector2(0.0, 240.0))
	recovered_animation_blend_tree.add_node("upper_seek", recovered_upper_body_seek, Vector2(180.0, 240.0))
	recovered_animation_blend_tree.add_node("layer", recovered_upper_body_blend, Vector2(260.0, 140.0))
	recovered_animation_blend_tree.connect_node("upper_seek", 0, "upper_body")
	recovered_animation_blend_tree.connect_node("layer", 0, "locomotion")
	recovered_animation_blend_tree.connect_node("layer", 1, "upper_seek")
	recovered_animation_blend_tree.connect_node("output", 0, "layer")

	# Unity's Player.AddMixingTransformAnimation applies run_shoot clips only
	# from Bip01 Spine1 downward through the hierarchy. Recreate that mask so
	# the locomotion clip keeps driving the pelvis and legs during held fire.
	for animation_name in recovered_animation_player.get_animation_list():
		if not animation_name.begins_with("run_shoot_"):
			continue
		var animation := recovered_animation_player.get_animation(animation_name)
		for track_index in range(animation.get_track_count()):
			var track_path := animation.track_get_path(track_index)
			if _is_upper_body_animation_track(track_path):
				recovered_upper_body_blend.set_filter_path(track_path, true)

	recovered_animation_tree = AnimationTree.new()
	recovered_animation_tree.name = "RecoveredAnimationLayers"
	recovered_avatar.add_child(recovered_animation_tree)
	recovered_animation_tree.anim_player = recovered_animation_tree.get_path_to(recovered_animation_player)
	recovered_animation_tree.tree_root = recovered_animation_blend_tree
	recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	recovered_animation_tree.set("parameters/layer/blend_amount", 1.0)
	recovered_animation_tree.active = false

func _is_upper_body_animation_track(track_path: NodePath) -> bool:
	if track_path.get_subname_count() < 1:
		return false
	var bone_index := recovered_skeleton.find_bone(String(track_path.get_subname(0)))
	var upper_body_index := recovered_skeleton.find_bone("Bip01 Spine1")
	while bone_index >= 0:
		if bone_index == upper_body_index:
			return true
		bone_index = recovered_skeleton.get_bone_parent(bone_index)
	return false

func _add_recovered_backpack() -> void:
	var bag_key := GameState.get_equipped_armor_key("bag")
	var bag_id := int(GameState.get_armor_item(bag_key).get("visual_id", 0))
	var backpack_path := "res://assets/models/player/animated/bags/ArmorBag_%02d/ArmorBag_%02d.obj" % [bag_id, bag_id]
	if not ResourceLoader.exists(backpack_path):
		backpack_path = "res://assets/models/player/animated/bag_%02d.obj" % bag_id
	if not ResourceLoader.exists(backpack_path):
		backpack_path = "res://assets/models/player/animated/bag.obj"
	if not ResourceLoader.exists(backpack_path) or not recovered_skeleton:
		return
	var fly_bag_bone := recovered_skeleton.find_bone("fly_bag")
	if fly_bag_bone < 0:
		return
	backpack_socket = BoneAttachment3D.new()
	backpack_socket.name = "RecoveredBackpackSocket"
	backpack_socket.bone_name = "fly_bag"
	recovered_skeleton.add_child(backpack_socket)

	backpack_visual = MeshInstance3D.new()
	backpack_visual.name = "RecoveredBackpack"
	backpack_visual.mesh = load(backpack_path)
	# AvatarBuilder placed the independent Bag prefab at fly_bag in world space
	# before parenting it. Its prefab root rotation is already baked into the
	# recovered OBJ, so cancel the socket's rest basis instead of applying the
	# unrelated embedded Player.prefab Bag rotation a second time.
	var fly_bag_rest := recovered_skeleton.get_bone_global_rest(fly_bag_bone)
	var body_key := GameState.get_equipped_armor_key("body")
	var body_id := int(GameState.get_armor_item(body_key).get("visual_id", 0))
	var unity_scale := float({14: 1.2, 15: 1.2, 16: 1.2, 17: 1.2, 18: 1.1, 19: 1.2, 20: 1.2}.get(bag_id, 1.0))
	var authored_scale := unity_scale if body_id == 5 else unity_scale * 0.8
	backpack_visual.transform = Transform3D(
		fly_bag_rest.basis.inverse() * Basis.from_scale(Vector3.ONE * authored_scale),
		Vector3.ZERO
	)
	backpack_socket.add_child(backpack_visual)

func _refresh_recovered_backpack() -> void:
	if is_instance_valid(backpack_socket):
		backpack_socket.get_parent().remove_child(backpack_socket)
		backpack_socket.queue_free()
	backpack_socket = null
	backpack_visual = null
	_add_recovered_backpack()

func _apply_recovered_armor_visibility() -> void:
	if not is_instance_valid(recovered_avatar):
		return
	var equipped_ids := {
		"head": int(GameState.get_armor_item(GameState.get_equipped_armor_key("head")).get("visual_id", 0)),
		"body": int(GameState.get_armor_item(GameState.get_equipped_armor_key("body")).get("visual_id", 0)),
		"hand": int(GameState.get_armor_item(GameState.get_equipped_armor_key("arms")).get("visual_id", 0)),
		"foot": int(GameState.get_armor_item(GameState.get_equipped_armor_key("legs")).get("visual_id", 0))
	}
	for candidate in recovered_avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		var lower_name := mesh_instance.name.to_lower()
		var part_name := ""
		for possible_part in equipped_ids:
			if (
				lower_name.begins_with("armor%s_" % possible_part)
				or lower_name.ends_with("_%s" % possible_part)
				or lower_name.begins_with("%s_" % possible_part)
			):
				part_name = possible_part
				break
		if part_name.is_empty():
			continue
		var visual_id := _armor_visual_id_from_name(lower_name)
		if visual_id >= 0:
			mesh_instance.visible = visual_id == int(equipped_ids[part_name])

func _armor_visual_id_from_name(node_name: String) -> int:
	# Exported parts use Armor00_Head; accept Head_00 as well so regenerated
	# assets from the Unity project remain backward compatible.
	if node_name.begins_with("armor") and node_name.length() >= 7:
		var id_text := node_name.substr(5, 2)
		if id_text.is_valid_int():
			return int(id_text)
	var suffix := node_name.get_slice("_", node_name.get_slice_count("_") - 1)
	return int(suffix) if suffix.is_valid_int() else -1

func _play_recovered_animation(animation_name: String, blend := 0.08, restart := false) -> void:
	if not recovered_animation_player or not recovered_animation_player.has_animation(animation_name):
		return
	var was_layered := recovered_animation_tree != null and recovered_animation_tree.active
	if recovered_animation_tree and recovered_animation_tree.active:
		recovered_animation_tree.active = false
		recovered_layered_animation = false
	# A non-looping clip reports `is_playing() == false` on its last frame. The
	# state timer may intentionally keep that pose a little longer; replaying it
	# from zero every physics frame caused the visible freeze/stutter regression.
	if not restart and recovered_animation_name == animation_name and not was_layered:
		return
	recovered_animation_name = animation_name
	recovered_animation_player.play(animation_name, blend)
	if restart:
		recovered_animation_player.seek(0.0, true)

func _play_recovered_layered_animation(locomotion_name: String, upper_body_name: String, restart_upper_body := false) -> void:
	if (
		not recovered_animation_player
		or not recovered_animation_tree
		or not recovered_animation_player.has_animation(locomotion_name)
		or not recovered_animation_player.has_animation(upper_body_name)
	):
		_play_recovered_animation(upper_body_name, 0.08, restart_upper_body)
		return
	var same_layer := (
		recovered_layered_animation
		and recovered_animation_tree.active
		and recovered_locomotion_name == locomotion_name
		and recovered_upper_body_name == upper_body_name
	)
	recovered_animation_name = upper_body_name
	if same_layer:
		if restart_upper_body:
			recovered_animation_tree.set("parameters/upper_seek/seek_request", 0.0)
		return
	recovered_locomotion_name = locomotion_name
	recovered_upper_body_name = upper_body_name
	recovered_locomotion_node.animation = StringName(locomotion_name)
	recovered_upper_body_node.animation = StringName(upper_body_name)
	recovered_animation_player.stop()
	recovered_animation_tree.active = true
	# AnimationNodeAnimation retains time when its clip changes or the tree is
	# reactivated. Seek only on a new firing state; held automatic fire keeps
	# advancing instead of being reset by every bullet.
	recovered_animation_tree.set("parameters/upper_seek/seek_request", 0.0)
	recovered_layered_animation = true

func _build_gun_visual() -> void:
	if not is_instance_valid(gun_mount):
		return
	reload_part_socket = null
	attached_reload_part = null
	for child in gun_mount.get_children():
		# Detach immediately so rapidly switching weapons can reuse stable node
		# names (WeaponVisual/Muzzle) before queued deletion runs next frame.
		gun_mount.remove_child(child)
		child.queue_free()
	var data: Dictionary = GameState.WEAPONS.get(current_weapon_id, GameState.WEAPONS.gun00)
	_prepare_weapon_mount(int(data.id))
	var weapon_color: Color = data.color
	var metal := _material(Color(0.06, 0.075, 0.09), 0.43, 0.73)
	var accent := _material(weapon_color.darkened(0.15), 0.28, 0.62, weapon_color * 0.5)
	var kind := str(data.kind)
	var visual_root := Node3D.new()
	visual_root.name = "WeaponVisual"
	if is_instance_valid(gun_socket):
		var authored_radians := _weapon_authored_rotation(int(data.id)) * (PI / 180.0)
		visual_root.basis = gun_mount.basis.inverse() * Basis.from_euler(authored_radians)
	gun_mount.add_child(visual_root)
	var size := Vector3(0.2, 0.22, 1.25)
	if kind in ["shotgun", "shockwave"]:
		size = Vector3(0.28, 0.25, 1.3)
	elif kind in ["rocket", "grenade", "fly_grenade"]:
		size = Vector3(0.4, 0.36, 1.42)
	elif kind in ["sniper", "reflection"]:
		size = Vector3(0.22, 0.24, 1.62)
	elif kind == "sword":
		size = Vector3(0.16, 0.16, 1.55)
	var restored_weapon_path := "res://assets/models/weapons/%s.obj" % str(data.model)
	var added_restored_visual := false
	if ResourceLoader.exists(restored_weapon_path):
		var restored_mesh := load(restored_weapon_path) as Mesh
		if restored_mesh:
			var restored := MeshInstance3D.new()
			restored.name = "Recovered_%s" % str(data.model)
			restored.mesh = restored_mesh
			var bounds := restored_mesh.get_aabb()
			var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			var factor := size.z / longest if longest > 0.001 else 1.0
			restored.scale = Vector3.ONE * factor
			# The prefab converter already preserves the old model's grip origin.
			# Centering here made every recovered gun float away from the hand.
			restored.position = Vector3.ZERO
			_repair_recovered_weapon_materials(restored, int(data.id))
			visual_root.add_child(restored)
			added_restored_visual = true
	if not added_restored_visual:
		_add_box(visual_root, size, Vector3.ZERO, metal, "WeaponBody")
		_add_box(visual_root, Vector3(size.x * 1.25, 0.07, size.z * 0.72), Vector3(0, 0.14, -0.06), accent, "WeaponGlow")
	_build_reload_attachment(visual_root, data)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -size.z * 0.62)
	gun_mount.add_child(muzzle)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = weapon_color
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 3.6
	muzzle.add_child(muzzle_light)

func _prepare_weapon_mount(weapon_id: int) -> void:
	var use_left_hand := weapon_id in [22, 29, 44]
	var target_socket: Node = left_gun_socket if use_left_hand and is_instance_valid(left_gun_socket) else gun_socket
	if is_instance_valid(target_socket) and gun_mount.get_parent() != target_socket:
		gun_mount.get_parent().remove_child(gun_mount)
		target_socket.add_child(gun_mount)
	if is_instance_valid(target_socket):
		gun_mount.position = Vector3.ZERO
		# Keep a stable aiming/recoil basis. Per-weapon Unity rotations are
		# applied below this pivot to the mesh only, so special weapons do not
		# turn the projectile direction sideways.
		gun_mount.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		gun_recoil_offset = Vector3(0.0, 0.1, 0.0)
	gun_mount_rest_position = gun_mount.position
	gun_mount_rest_rotation = gun_mount.quaternion

func _weapon_authored_rotation(weapon_id: int) -> Vector3:
	# Exact combat cases from Unity WeaponResourceConfig.RotateGun. Most legacy
	# rifles need the authored -90° X bridge; bows, fists and several special
	# weapons were already authored in hand-space and must not receive it.
	if weapon_id in [22, 23, 24, 25, 28, 31, 32, 39, 41, 45, 46]:
		return Vector3.ZERO
	if weapon_id == 36:
		return Vector3(0.0, 90.0, -90.0)
	if weapon_id == 44:
		return Vector3(90.0, 0.0, 0.0)
	return Vector3(-90.0, 0.0, 0.0)

func _repair_recovered_weapon_materials(instance: MeshInstance3D, weapon_id: int) -> void:
	# Unity's additive/glow shaders were reduced to OBJ/MTL. Godot's OBJ
	# importer otherwise treats them as ordinary opaque materials. Do not infer
	# the shader from PNG alpha alone: several solid Unity weapon atlases contain
	# semi-transparent pixels even though their shader deliberately ignored
	# alpha. Restore only the material names whose source shader was actually
	# AlphaBlend/Additive.
	if instance.mesh == null:
		return
	var alpha_effect_names := [
		"gong_1", "gun1112", "passer-standard_1", "sniper_effect",
		"orig_standard_7"
	]
	var additive_effect_names := [
		"fist_eff_001", "fist_eff_001_2", "rpg_mat_031",
		"rpg_mat_031_2", "gunchristmas_02", "hotwing_qiangkou"
	]
	for surface_index in range(instance.mesh.get_surface_count()):
		var source := instance.mesh.surface_get_material(surface_index) as StandardMaterial3D
		if source == null or source.albedo_texture == null:
			continue
		var material_name := source.resource_name.to_lower()
		var alpha_effect := material_name in alpha_effect_names
		var additive_effect := material_name in additive_effect_names
		# Keep exact surface fallbacks for regenerated OBJ imports that omit a
		# material resource name.
		if material_name.is_empty():
			alpha_effect = weapon_id == 22 and surface_index in [1, 2]
			additive_effect = (
				(weapon_id == 23 and surface_index in [0, 1])
				or (weapon_id == 37 and surface_index in [1, 2])
			)
		var forced_solid := (
			(weapon_id == 22 and surface_index == 0)
			or (weapon_id == 23 and surface_index == 2)
			or (weapon_id == 37 and surface_index == 0)
		)
		var almost_black_tint := source.albedo_color.r + source.albedo_color.g + source.albedo_color.b < 0.15
		if not alpha_effect and not additive_effect and not forced_solid and not almost_black_tint:
			continue
		var repaired := source.duplicate(true) as StandardMaterial3D
		if forced_solid or almost_black_tint or alpha_effect or additive_effect:
			# Unity's SolidTexture shader ignored the serialized black `_Color` on
			# Light Bow, MCP76 and TheArrow. OBJ/MTL multiplied by that unused
			# property and produced black weapons.
			repaired.albedo_color = Color(1.0, 1.0, 1.0, source.albedo_color.a)
		if forced_solid:
			repaired.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		elif alpha_effect or additive_effect:
			repaired.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			repaired.cull_mode = BaseMaterial3D.CULL_DISABLED
			repaired.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			repaired.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			repaired.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive_effect else BaseMaterial3D.BLEND_MODE_MIX
			if material_name == "gong_1":
				repaired.albedo_color.a = 0.58
		instance.set_surface_override_material(surface_index, repaired)

func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	# Unity rotated the player first and then evaluated
	# target.TransformPoint(pivotPosition). Keep the yaw pivot on the player's
	# centerline so the authored +0.6 shoulder offset rotates with the view.
	camera_rig.position = Vector3(0.0, CAMERA_BASE_HEIGHT, 0.0)
	add_child(camera_rig)
	pitch_node = Node3D.new()
	pitch_node.name = "Pitch"
	pitch_node.position = Vector3(0.6, 0.0, 0.0)
	camera_rig.add_child(pitch_node)
	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = camera_distance
	spring_arm.margin = 0.2
	spring_arm.collision_mask = 1
	pitch_node.add_child(spring_arm)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 60.0
	camera.current = true
	camera.position = Vector3.ZERO
	spring_arm.add_child(camera)
	camera_rig.rotation.y = camera_yaw
	pitch_node.rotation.x = camera_pitch

func _build_audio() -> void:
	fire_audio = AudioStreamPlayer3D.new()
	fire_audio.bus = &"SFX"
	fire_audio.max_distance = 45.0
	fire_audio.unit_size = 3.0
	add_child(fire_audio)
	hurt_audio = AudioStreamPlayer3D.new()
	hurt_audio.bus = &"SFX"
	var hurt_path := "res://assets/audio/player/hurt.wav"
	var recovered_hurt := "res://assets/original/audio/playerGotHit.wav"
	if ResourceLoader.exists(recovered_hurt):
		hurt_audio.stream = load(recovered_hurt)
	elif ResourceLoader.exists(hurt_path):
		hurt_audio.stream = load(hurt_path)
	add_child(hurt_audio)

func _physics_process(delta: float) -> void:
	if dead:
		_stop_flying_audio()
		velocity.y -= gravity * delta
		move_and_slide()
		return

	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	if auto_reload_left >= 0.0:
		auto_reload_left -= delta
		if auto_reload_left <= 0.0:
			auto_reload_left = -1.0
			_start_reload()
	_update_reload(delta)
	_update_armor_effects(delta)
	shoot_pose_left = maxf(0.0, shoot_pose_left - delta)
	hurt_pose_left = maxf(0.0, hurt_pose_left - delta)
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	dash_changed.emit(1.0 - dash_cooldown_left / dash_cooldown)
	_update_camera_controller(delta)

	var keyboard_move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_input := keyboard_move
	if touch_move.length_squared() > move_input.length_squared():
		move_input = touch_move
	var forward := -camera_rig.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_rig.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var desired := (right * move_input.x + forward * -move_input.y)
	if desired.length_squared() > 1.0:
		desired = desired.normalized()

	if (Input.is_action_just_pressed("dash") or touch_dash_requested) and dash_cooldown_left <= 0.0:
		touch_dash_requested = false
		dash_direction = desired.normalized() if desired.length_squared() > 0.01 else forward
		dash_time = dash_duration
		dash_cooldown_left = dash_cooldown
	if dash_time > 0.0:
		dash_time -= delta
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
	else:
		var power_speed_bonus := float(armor_power_controller.get_speed_bonus()) if is_instance_valid(armor_power_controller) and armor_power_controller.has_method("get_speed_bonus") else 0.0
		var active_move_speed := move_speed + power_speed_bonus + (float(armor_skills.get("speed_on_hit", 0.0)) if speed_on_hit_left > 0.0 else 0.0)
		velocity.x = move_toward(velocity.x, desired.x * active_move_speed, 34.0 * delta)
		velocity.z = move_toward(velocity.z, desired.z * active_move_speed, 34.0 * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	move_and_slide()

	_update_body_facing(delta, desired)
	_update_combat_aim_pose(delta)
	# Resolve firing before choosing the pose. This keeps an automatic weapon's
	# shoot window alive on the exact frame its cooldown expires instead of
	# briefly falling back to run/idle between consecutive shots.
	_handle_weapon_input()
	_update_visual_animation(delta, desired.length(), move_input)
	_update_reload_pose()

func _update_camera_controller(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() > 0.0001:
		_apply_look_delta(look * 165.0 * delta)
	var focused := Input.is_action_pressed("aim")
	var weapon_kind := str(current_weapon.get("kind", "hitscan"))
	var target_fov := (13.2 if weapon_kind in ["sniper", "reflection"] else 22.0) if focused else (80.0 if weapon_kind == "rocket" else 60.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-10.0 * delta))
	var target_length := 1.8 if focused else camera_distance
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target_length, 1.0 - exp(-11.0 * delta))
	var target_height := CAMERA_BASE_HEIGHT + (FLY_CAMERA_OFFSET if float(armor_skills.get("fly", 0.0)) > 0.0 else 0.0)
	camera_rig.position.y = lerpf(camera_rig.position.y, target_height, 1.0 - exp(-10.0 * delta))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weapon_previous"):
		cycle_weapon(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("weapon_next"):
		cycle_weapon(1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look_delta(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and not OS.has_feature("mobile") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventScreenDrag and event.position.x > get_viewport().get_visible_rect().size.x * 0.36:
		_apply_look_delta(event.relative * 0.72)

func _apply_look_delta(relative: Vector2) -> void:
	var sensitivity := float(GameState.settings.look_sensitivity) * 0.01
	camera_yaw = wrapf(camera_yaw - relative.x * sensitivity, -PI, PI)
	var direction := -1.0 if bool(GameState.settings.invert_y) else 1.0
	camera_pitch -= relative.y * sensitivity * direction
	camera_pitch = clampf(camera_pitch, deg_to_rad(-62.0), deg_to_rad(38.0))
	camera_rig.rotation.y = camera_yaw
	pitch_node.rotation.x = camera_pitch

func _update_body_facing(delta: float, desired_movement: Vector3) -> void:
	# Camera yaw is deliberately independent from avatar yaw. This allows the
	# player to orbit all the way around the suit (including a front view)
	# without making the avatar spin in place.
	var target_yaw := body_yaw
	var turn_response := 0.0
	var combat_facing := is_combat_aim_active()
	if combat_facing:
		# A high exponential response gives a short, readable turn instead of a
		# one-frame 180-degree snap when firing from a front-facing camera.
		target_yaw = camera_yaw
		turn_response = 18.0
	else:
		var travel := desired_movement
		if travel.length_squared() <= 0.0004:
			travel = Vector3(velocity.x, 0.0, velocity.z)
		if travel.length_squared() > 0.04:
			target_yaw = atan2(-travel.x, -travel.z)
			turn_response = 12.0
	if turn_response <= 0.0:
		return
	body_yaw = lerp_angle(body_yaw, target_yaw, 1.0 - exp(-turn_response * delta))
	if is_instance_valid(model):
		model.rotation.y = body_yaw

func is_combat_aim_active() -> bool:
	return (
		Input.is_action_pressed("aim")
		or Input.is_action_pressed("fire")
		or touch_fire
		or shoot_pose_left > 0.0
		or reload_left > 0.0
	)

func is_fire_input_active() -> bool:
	return Input.is_action_pressed("fire") or touch_fire

func _update_combat_aim_pose(delta: float) -> void:
	if not is_instance_valid(gun_mount):
		return
	if not is_combat_aim_active():
		if upper_body_aim_override_active and is_instance_valid(recovered_skeleton):
			recovered_skeleton.clear_bones_global_pose_override()
			upper_body_aim_override_active = false
		gun_mount.quaternion = gun_mount.quaternion.slerp(
			gun_mount_rest_rotation,
			1.0 - exp(-22.0 * delta)
		)
		return

	# Keep the lower body on the readable short turn used by free orbit, while
	# the chest supplies a bounded twist during those first frames. The weapon
	# pivot resolves the remainder so its muzzle and the camera ray agree even
	# when firing immediately from a full front view.
	if is_instance_valid(recovered_skeleton):
		var spine_index := recovered_skeleton.find_bone("Bip01 Spine1")
		if spine_index >= 0:
			var base_pose := recovered_skeleton.get_bone_global_pose_no_override(spine_index)
			var local_up := recovered_skeleton.global_transform.basis.inverse() * Vector3.UP
			var upper_yaw := clampf(
				angle_difference(body_yaw, camera_yaw),
				-UPPER_BODY_AIM_LIMIT,
				UPPER_BODY_AIM_LIMIT
			)
			base_pose.basis = Basis(local_up.normalized(), upper_yaw) * base_pose.basis
			recovered_skeleton.set_bone_global_pose_override(spine_index, base_pose, 1.0, true)
			recovered_skeleton.force_update_bone_child_transform(spine_index)
			upper_body_aim_override_active = true

	var aim := get_aim_solution(float(current_weapon.get("range", 105.0)))
	var target := Vector3(aim.target)
	if gun_mount.global_position.distance_squared_to(target) > 0.0001:
		gun_mount.look_at(target, Vector3.UP)

func _handle_weapon_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		_equip_loadout_slot(0)
	elif Input.is_action_just_pressed("weapon_2"):
		_equip_loadout_slot(1)
	elif Input.is_action_just_pressed("weapon_3"):
		_equip_loadout_slot(2)
	elif Input.is_action_just_pressed("weapon_4"):
		_equip_loadout_slot(3)
	var trigger := Input.is_action_pressed("fire") or touch_fire
	var just_triggered := Input.is_action_just_pressed("fire") or touch_fire_started
	if Input.is_action_just_pressed("reload") or touch_reload_requested:
		_start_reload()
	touch_reload_requested = false
	touch_fire_started = false
	if reload_left > 0.0 and str(current_weapon.get("reload_style", "")) == "shotgun_shell" and just_triggered and _magazine_rounds() > 0:
		_cancel_reload()
	_update_continuous_weapon_audio(trigger, just_triggered)
	if (bool(current_weapon.automatic) and trigger) or (not bool(current_weapon.automatic) and just_triggered):
		_try_fire()

func _equip_loadout_slot(index: int) -> void:
	if index >= 0 and index < weapon_order.size():
		equip_weapon(weapon_order[index])

func equip_weapon(weapon_id: String, persist_selection := true) -> void:
	if not GameState.WEAPONS.has(weapon_id):
		return
	_cancel_reload(false)
	_stop_continuous_weapon_audio()
	current_weapon_id = weapon_id
	current_weapon = GameState.WEAPONS[weapon_id].duplicate(true)
	auto_reload_left = -1.0
	_ensure_magazine_state()
	restart_shoot_animation_requested = false
	_build_gun_visual()
	recovered_animation_name = ""
	if persist_selection:
		GameState.set_weapon(weapon_id)
		AudioDirector.play_ui("mount_weapon", -2.0)
	weapon_changed.emit(weapon_id, current_weapon)
	_emit_ammo()

func cycle_weapon(direction: int) -> void:
	if weapon_order.is_empty():
		return
	var index := weapon_order.find(current_weapon_id)
	if index < 0:
		index = 0 if direction >= 0 else weapon_order.size() - 1
	else:
		index = posmod(index + direction, weapon_order.size())
	equip_weapon(weapon_order[index])

func _refresh_weapon_order_for_bag() -> void:
	# Keep the complete loadout in GameState so swapping back to a larger pack is
	# non-destructive, but expose only the slots provided by the equipped bag in
	# combat (matching Unity's BagNum behavior).
	weapon_order.clear()
	var capacity := maxi(1, GameState.get_bag_capacity())
	for weapon_id_value in GameState.battle_weapons:
		var weapon_id := str(weapon_id_value)
		if weapon_order.size() >= capacity:
			break
		if GameState.WEAPONS.has(weapon_id) and not weapon_order.has(weapon_id):
			weapon_order.append(weapon_id)
	if weapon_order.is_empty():
		weapon_order.append("gun00")

func _try_fire() -> void:
	if shot_cooldown > 0.0 or reload_left > 0.0 or dead or current_weapon.is_empty():
		return
	if _uses_magazine() and _magazine_rounds() <= 0:
		AudioDirector.play_3d(str(current_weapon.get("blank_sound", "blank/blank_shot01.wav")), global_position, -4.0)
		_start_reload()
		return
	# Imported weapon meshes and animation libraries can be regenerated by a
	# different Godot minor version. Never let a missing visual node turn a
	# valid weapon shot into a script crash.
	if not is_instance_valid(muzzle) or not is_instance_valid(muzzle_light) or not is_instance_valid(gun_mount):
		_build_gun_visual()
	if not is_instance_valid(muzzle) or not is_instance_valid(muzzle_light) or not is_instance_valid(gun_mount):
		return
	var energy_cost := 0 if float(armor_skills.get("unlimited_energy", 0.0)) > 0.0 else maxi(0, roundi(float(current_weapon.energy) * maxf(0.0, 1.0 + float(armor_skills.get("save_energy", 0.0)))))
	if energy_cost > energy:
		AudioDirector.play_3d(str(current_weapon.get("blank_sound", "blank/blank_shot01.wav")), global_position, -4.0)
		return
	energy -= energy_cost
	if _uses_magazine():
		_set_magazine_rounds(_magazine_rounds() - 1)
		if _magazine_rounds() <= 0:
			auto_reload_left = maxf(float(current_weapon.get("cooldown", 0.1)), 0.12)
	shot_cooldown = float(current_weapon.cooldown) * maxf(0.2, 1.0 + float(armor_skills.get("attack_frequency", 0.0)))
	shoot_pose_left = maxf(0.14, minf(0.55, shot_cooldown))
	shot_fired.emit(current_weapon)
	# One-shot clips must restart on every successful trigger pull. Automatic
	# clips deliberately remain continuous while the button is held.
	restart_shoot_animation_requested = not bool(current_weapon.get("automatic", false))
	muzzle_light.light_energy = 5.0
	var fired_muzzle_light_id: int = muzzle_light.get_instance_id()
	get_tree().create_timer(0.045).timeout.connect(func():
		var light: OmniLight3D = instance_from_id(fired_muzzle_light_id) as OmniLight3D
		if is_instance_valid(light):
			light.light_energy = 0.0
	)
	if str(current_weapon.kind) != "sword" and not weapon_audio_active:
		_play_weapon_fire_sound()
	gun_mount.position = gun_mount_rest_position + gun_recoil_offset
	var recoil_tween := create_tween()
	recoil_tween.tween_property(gun_mount, "position", gun_mount_rest_position, 0.09).set_trans(Tween.TRANS_QUAD)

	var kind := str(current_weapon.kind)
	if kind == "sword":
		_fire_melee()
	elif kind in ["rocket", "grenade", "fly_grenade", "plasma", "arrow", "energy_fist", "tracking", "ricochet", "spring"]:
		_fire_projectile(kind)
	else:
		_fire_hitscan()
	_emit_ammo()

func _fire_hitscan() -> void:
	var aim := get_aim_solution(float(current_weapon.range))
	var origin: Vector3 = aim.origin
	var base_direction: Vector3 = aim.direction
	var space := get_world_3d().direct_space_state
	var tracer_style := str(current_weapon.get("tracer_style", "legacy"))
	var show_tracer := _consume_tracer_slot(tracer_style, int(current_weapon.get("tracer_every", 1)))
	if get_parent().has_method("spawn_muzzle_effect"):
		get_parent().spawn_muzzle_effect(muzzle.global_position, base_direction, tracer_style)
	if tracer_style == "machinegun" and get_parent().has_method("spawn_machinegun_muzzle_fx"):
		get_parent().spawn_machinegun_muzzle_fx(muzzle.global_position, base_direction)
	for pellet_index in range(int(current_weapon.pellets)):
		var spread := float(current_weapon.spread)
		var direction := (base_direction + camera.global_transform.basis.x * randf_range(-spread, spread) + camera.global_transform.basis.y * randf_range(-spread, spread)).normalized()
		var end := origin + direction * float(current_weapon.range)
		var query := PhysicsRayQueryParameters3D.create(origin, end, 3)
		query.exclude = [get_rid()]
		var result := space.intersect_ray(query)
		var hit_position := end
		if not result.is_empty():
			hit_position = result.position
			var collider = result.collider
			if is_instance_valid(collider) and collider.has_method("take_damage"):
				collider.take_damage(_current_weapon_damage(), result.position, self)
		if show_tracer and get_parent().has_method("spawn_tracer"):
			get_parent().spawn_tracer(muzzle.global_position, hit_position, current_weapon.color, tracer_style)
		if not result.is_empty() and get_parent().has_method("spawn_impact"):
			get_parent().spawn_impact(hit_position, result.normal, current_weapon.color, tracer_style)

func _consume_tracer_slot(tracer_style: String, every: int) -> bool:
	if tracer_style not in ["rifle", "machinegun"]:
		return true
	var shot_count := int(tracer_shot_counts.get(current_weapon_id, 0))
	tracer_shot_counts[current_weapon_id] = shot_count + 1
	return shot_count % maxi(1, every) == 0

func _fire_projectile(projectile_kind: String) -> void:
	var aim := get_aim_solution(float(current_weapon.get("range", 105.0)))
	# Unity first raycast from the shoulder camera and then converged the actual
	# muzzle toward that point.  This prevents close shots from travelling
	# parallel to (and visibly missing) the reticle.
	var direction: Vector3 = (Vector3(aim.target) - muzzle.global_position).normalized()
	if projectile_kind == "grenade":
		direction = (direction + Vector3.UP * 0.18).normalized()
	var projectile := ProjectileScript.new()
	projectile.configure(self, direction, float(current_weapon.speed), _current_weapon_damage(), maxf(float(current_weapon.splash), 0.65), current_weapon.color, false, projectile_kind, str(current_weapon.explosion_sound), current_weapon_id)
	get_parent().add_child(projectile)
	projectile.global_position = muzzle.global_position

func get_aim_solution(maximum_range := 180.0) -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_point := viewport_size * 0.5
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var endpoint := origin + direction * maximum_range
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 3)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return {
		"origin": origin,
		"direction": direction,
		"target": Vector3(hit.position) if not hit.is_empty() else endpoint,
		"collider": hit.get("collider") if not hit.is_empty() else null
	}

func is_reticle_on_enemy() -> bool:
	var aim := get_aim_solution(float(current_weapon.get("range", 105.0)))
	var collider = aim.collider
	return is_instance_valid(collider) and (collider as Node).is_in_group("enemies")

func apply_touch_look(value: Vector2) -> void:
	_apply_look_delta(value)

func _fire_melee() -> void:
	var forward := -camera.global_transform.basis.z
	var center := global_position + Vector3.UP + Vector3(forward.x, 0.0, forward.z).normalized() * 1.55
	var shape := SphereShape3D.new()
	shape.radius = 1.55
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = 2
	var made_contact := false
	for hit in get_world_3d().direct_space_state.intersect_shape(params, 12):
		var target := hit.collider as Node
		if is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(_current_weapon_damage(), center, self)
			made_contact = true
	var sound_path := str(current_weapon.get("sound", ""))
	if sound_path.is_empty():
		var choices: Array = current_weapon.get("hit_sounds", []) if made_contact else current_weapon.get("swing_sounds", [])
		if not choices.is_empty():
			sound_path = str(choices.pick_random())
	if not sound_path.is_empty():
		AudioDirector.play_3d(sound_path, global_position, -1.0, randf_range(0.97, 1.03))

func _uses_magazine() -> bool:
	return str(current_weapon.get("resource_model", "energy")) == "magazine"

func _ensure_magazine_state() -> void:
	if not _uses_magazine():
		return
	var capacity := maxi(1, int(current_weapon.get("magazine_size", 1)))
	if not weapon_magazines.has(current_weapon_id):
		weapon_magazines[current_weapon_id] = capacity
	else:
		weapon_magazines[current_weapon_id] = clampi(int(weapon_magazines[current_weapon_id]), 0, capacity)

func _magazine_rounds() -> int:
	if not _uses_magazine():
		return 0
	_ensure_magazine_state()
	return int(weapon_magazines.get(current_weapon_id, 0))

func _set_magazine_rounds(rounds: int) -> void:
	if _uses_magazine():
		weapon_magazines[current_weapon_id] = clampi(rounds, 0, int(current_weapon.get("magazine_size", 1)))

func _start_reload() -> void:
	if dead or reload_left > 0.0 or not _uses_magazine():
		return
	var capacity := int(current_weapon.get("magazine_size", 1))
	if _magazine_rounds() >= capacity:
		return
	auto_reload_left = -1.0
	_stop_continuous_weapon_audio()
	shoot_pose_left = 0.0
	_begin_reload_cycle()

func _begin_reload_cycle() -> void:
	reload_start_rounds = _magazine_rounds()
	reload_total = maxf(0.12, float(current_weapon.get("reload_time", 1.5)))
	if reload_start_rounds == 0 and str(current_weapon.get("reload_style", "")) not in ["shotgun_shell", "rocket"]:
		reload_total += maxf(0.0, float(current_weapon.get("empty_reload_bonus", 0.0)))
	reload_left = reload_total
	reload_elapsed = 0.0
	reload_event_mask = 0
	if is_instance_valid(recovered_skeleton):
		var hand_index := recovered_skeleton.find_bone("Bip01 L Hand")
		if hand_index >= 0:
			reload_hand_start_local = recovered_skeleton.get_bone_global_pose_no_override(hand_index).origin
	_cleanup_reload_hand_prop()
	AudioDirector.play_3d("menu/mount_gears.wav", global_position, -8.0, 0.92)
	_emit_ammo()

func _update_reload(delta: float) -> void:
	if reload_left <= 0.0:
		return
	reload_elapsed = minf(reload_total, reload_elapsed + delta)
	reload_left = maxf(0.0, reload_total - reload_elapsed)
	_update_reload_visual_events(reload_elapsed / maxf(reload_total, 0.001))
	if reload_left <= 0.0:
		_finish_reload_cycle()

func _update_reload_visual_events(progress: float) -> void:
	var drop_fraction := float(current_weapon.get("drop_fraction", -1.0))
	var hand_fraction := float(current_weapon.get("hand_fraction", 0.35))
	var insert_fraction := float(current_weapon.get("insert_fraction", 0.75))
	if drop_fraction >= 0.0 and progress >= drop_fraction and reload_event_mask & 1 == 0:
		reload_event_mask |= 1
		_drop_reload_part()
	if progress >= hand_fraction and reload_event_mask & 2 == 0:
		reload_event_mask |= 2
		_create_reload_hand_prop()
	if progress >= insert_fraction and reload_event_mask & 4 == 0:
		reload_event_mask |= 4
		if is_instance_valid(attached_reload_part):
			attached_reload_part.visible = str(current_weapon.get("reload_style", "")) != "shotgun_shell"
		_cleanup_reload_hand_prop()
		var insert_sound := "shotgun/ShotgunCock02.wav" if str(current_weapon.get("reload_style", "")) == "shotgun_shell" else "menu/mount_weapon.wav"
		AudioDirector.play_3d(insert_sound, global_position, -5.0, randf_range(0.96, 1.04))

func _build_reload_attachment(visual_root: Node3D, data: Dictionary) -> void:
	if str(data.get("resource_model", "energy")) != "magazine":
		return
	reload_part_socket = Marker3D.new()
	reload_part_socket.name = "ReloadPartSocket"
	reload_part_socket.position = Vector3(data.get("prop_position", Vector3.ZERO))
	reload_part_socket.rotation_degrees = Vector3(data.get("prop_rotation", Vector3.ZERO))
	visual_root.add_child(reload_part_socket)
	if str(data.get("reload_style", "")) == "shotgun_shell":
		return
	attached_reload_part = _create_reload_prop(data, "AttachedReloadPart")
	reload_part_socket.add_child(attached_reload_part)

func _create_reload_prop(data: Dictionary, node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var shape_name := str(data.get("prop_shape", "box"))
	var size := Vector3(data.get("prop_size", Vector3(0.12, 0.24, 0.16)))
	var dark_metal := _material(Color(0.035, 0.045, 0.055), 0.31, 0.82)
	var edge_metal := _material(Color(0.18, 0.22, 0.24), 0.26, 0.9)
	var brass := _material(Color(0.72, 0.38, 0.08), 0.25, 0.72)
	var shell_red := _material(Color(0.48, 0.035, 0.025), 0.42, 0.45)
	match shape_name:
		"shell":
			_add_cylinder(root, size.x, size.y, Vector3.ZERO, shell_red, "ShellBody")
			_add_cylinder(root, size.x * 1.08, size.y * 0.12, Vector3(0.0, size.y * 0.48, 0.0), brass, "ShellCap")
		"drum":
			_add_cylinder(root, size.x * 0.5, size.y, Vector3.ZERO, dark_metal, "GrenadeDrum")
			_add_cylinder(root, size.x * 0.54, size.y * 0.18, Vector3(0.0, size.y * 0.35, 0.0), edge_metal, "DrumRing")
		"rocket":
			if not _add_original_reload_rocket(root, size):
				_add_cylinder(root, size.x * 0.5, size.y * 0.78, Vector3(0.0, size.y * 0.05, 0.0), dark_metal, "RocketBody")
				_add_cone(root, size.x * 0.52, size.y * 0.22, Vector3(0.0, -size.y * 0.45, 0.0), brass, "RocketNose")
				_add_box(root, Vector3(size.x * 1.6, size.y * 0.12, size.z * 0.18), Vector3(0.0, size.y * 0.43, 0.0), edge_metal, "RocketFin")
		_:
			_add_box(root, size, Vector3.ZERO, dark_metal, "MagazineBody")
			_add_box(root, Vector3(size.x * 1.08, size.y * 0.10, size.z * 1.08), Vector3(0.0, -size.y * 0.42, 0.0), edge_metal, "MagazineBase")
	return root

func _add_original_reload_rocket(parent: Node3D, target_size: Vector3) -> bool:
	var source_path := "res://assets/models/projectiles/original_rocket.obj"
	if not ResourceLoader.exists(source_path):
		return false
	var source := load(source_path) as Mesh
	if source == null:
		return false
	var body_mesh := ArrayMesh.new()
	for surface_index in range(source.get_surface_count()):
		var source_material := source.surface_get_material(surface_index) as StandardMaterial3D
		if source_material == null or not source_material.resource_name.begins_with("RPG_"):
			continue
		body_mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface_index), source.surface_get_arrays(surface_index))
		var restored_material := source_material.duplicate(true) as StandardMaterial3D
		var hd_texture_path := "res://assets/models/projectiles/gun0910_hd.png"
		if ResourceLoader.exists(hd_texture_path):
			restored_material.albedo_texture = load(hd_texture_path) as Texture2D
		body_mesh.surface_set_material(body_mesh.get_surface_count() - 1, restored_material)
	if body_mesh.get_surface_count() == 0:
		return false
	var instance := MeshInstance3D.new()
	instance.name = "OriginalUnityReloadRocket"
	instance.mesh = body_mesh
	var bounds := body_mesh.get_aabb()
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var scale_factor := target_size.y / longest if longest > 0.001 else 1.0
	instance.scale = Vector3.ONE * scale_factor
	instance.position = -bounds.get_center() * scale_factor
	parent.add_child(instance)
	return true

func _drop_reload_part() -> void:
	if not is_instance_valid(reload_part_socket):
		return
	var source_transform := reload_part_socket.global_transform
	if is_instance_valid(attached_reload_part):
		source_transform = attached_reload_part.global_transform
		attached_reload_part.visible = false
	var debris := RigidBody3D.new()
	debris.name = "Dropped_%s_%s" % [current_weapon_id, str(current_weapon.get("reload_style", "magazine"))]
	debris.add_to_group("reload_debris")
	debris.collision_layer = 0
	debris.collision_mask = 1
	debris.mass = 0.18
	debris.continuous_cd = true
	debris.add_child(_create_reload_prop(current_weapon, "ReloadDebrisVisual"))
	var collision := CollisionShape3D.new()
	var size := Vector3(current_weapon.get("prop_size", Vector3(0.12, 0.24, 0.16)))
	if str(current_weapon.get("prop_shape", "box")) in ["shell", "drum", "rocket"]:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = maxf(size.x, size.z) * 0.52
		cylinder.height = size.y
		collision.shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
	debris.add_child(collision)
	get_parent().add_child(debris)
	debris.global_transform = source_transform
	debris.linear_velocity = -global_transform.basis.x * randf_range(0.65, 1.15) + Vector3.UP * randf_range(0.25, 0.65) + velocity * 0.15
	debris.angular_velocity = Vector3(randf_range(-7.0, 7.0), randf_range(-9.0, 9.0), randf_range(-7.0, 7.0))
	AudioDirector.play_3d("walk_metal.wav", source_transform.origin, -13.0, randf_range(1.08, 1.28))
	var debris_nodes := get_tree().get_nodes_in_group("reload_debris")
	if debris_nodes.size() > 24 and is_instance_valid(debris_nodes[0]):
		debris_nodes[0].queue_free()
	get_tree().create_timer(7.0).timeout.connect(func():
		if is_instance_valid(debris):
			debris.queue_free()
	)

func _create_reload_hand_prop() -> void:
	_cleanup_reload_hand_prop()
	reload_hand_prop = _create_reload_prop(current_weapon, "ReloadHandProp")
	get_parent().add_child(reload_hand_prop)
	_update_reload_hand_prop()

func _cleanup_reload_hand_prop() -> void:
	if not is_instance_valid(reload_hand_prop):
		reload_hand_prop = null
		return
	reload_hand_prop.get_parent().remove_child(reload_hand_prop)
	reload_hand_prop.queue_free()
	reload_hand_prop = null

func _update_reload_hand_prop() -> void:
	if not is_instance_valid(reload_hand_prop) or not is_instance_valid(reload_part_socket):
		return
	var progress := reload_elapsed / maxf(reload_total, 0.001)
	if is_instance_valid(recovered_skeleton):
		reload_hand_prop.global_position = recovered_skeleton.to_global(_reload_left_hand_target(progress))
	else:
		reload_hand_prop.global_position = reload_part_socket.global_position
	reload_hand_prop.global_basis = reload_part_socket.global_basis

func _finish_reload_cycle() -> void:
	var style := str(current_weapon.get("reload_style", ""))
	var capacity := int(current_weapon.get("magazine_size", 1))
	if style == "shotgun_shell":
		_set_magazine_rounds(_magazine_rounds() + 1)
	else:
		_set_magazine_rounds(capacity)
	if is_instance_valid(attached_reload_part):
		attached_reload_part.visible = style != "shotgun_shell"
	_cleanup_reload_hand_prop()
	reload_left = 0.0
	reload_elapsed = 0.0
	_emit_ammo()
	if style == "shotgun_shell" and _magazine_rounds() < capacity:
		_begin_reload_cycle()
	else:
		_end_reload_pose()

func _cancel_reload(restore_attachment := true) -> void:
	if reload_left <= 0.0 and not is_instance_valid(reload_hand_prop):
		return
	reload_left = 0.0
	reload_elapsed = 0.0
	reload_total = 0.0
	reload_event_mask = 0
	_cleanup_reload_hand_prop()
	if restore_attachment and is_instance_valid(attached_reload_part):
		attached_reload_part.visible = str(current_weapon.get("reload_style", "")) != "shotgun_shell"
	_end_reload_pose()
	_emit_ammo()

func _end_reload_pose() -> void:
	if is_instance_valid(gun_mount):
		gun_mount.position = gun_mount_rest_position
	if is_instance_valid(recovered_skeleton):
		recovered_skeleton.clear_bones_global_pose_override()
		upper_body_aim_override_active = false

func _update_reload_pose() -> void:
	if reload_left <= 0.0:
		return
	var progress := clampf(reload_elapsed / maxf(reload_total, 0.001), 0.0, 1.0)
	var pulse := sin(progress * PI)
	var style := str(current_weapon.get("reload_style", "rifle"))
	var left_upper := Vector3.ZERO
	var left_forearm := Vector3.ZERO
	var right_upper := Vector3.ZERO
	var gun_tilt := Vector3.ZERO
	var gun_offset := Vector3.ZERO
	match style:
		"rifle":
			left_upper = Vector3(-28.0, -18.0, 42.0)
			left_forearm = Vector3(-48.0, 12.0, -8.0)
			right_upper = Vector3(4.0, 0.0, -8.0)
			gun_tilt = Vector3(-16.0, 5.0, 13.0)
			gun_offset = Vector3(-0.05, -0.05, 0.05)
		"sniper":
			left_upper = Vector3(-38.0, -8.0, 52.0)
			left_forearm = Vector3(-58.0, 18.0, -14.0)
			right_upper = Vector3(7.0, 3.0, -13.0)
			gun_tilt = Vector3(-10.0, -12.0, 22.0)
			gun_offset = Vector3(-0.08, -0.08, 0.10)
		"shotgun_shell":
			left_upper = Vector3(-44.0, -22.0, 32.0)
			left_forearm = Vector3(-62.0, 24.0, 5.0)
			right_upper = Vector3(10.0, 0.0, -10.0)
			gun_tilt = Vector3(9.0, 0.0, 18.0)
			gun_offset = Vector3(-0.04, -0.10, 0.04)
		"rocket":
			left_upper = Vector3(-62.0, 8.0, 58.0)
			left_forearm = Vector3(-36.0, -22.0, -18.0)
			right_upper = Vector3(18.0, 0.0, -18.0)
			gun_tilt = Vector3(-28.0, 5.0, 34.0)
			gun_offset = Vector3(-0.12, -0.14, 0.08)
		"grenade_drum":
			left_upper = Vector3(-34.0, -28.0, 50.0)
			left_forearm = Vector3(-52.0, 28.0, -12.0)
			right_upper = Vector3(12.0, 5.0, -14.0)
			gun_tilt = Vector3(14.0, -8.0, 25.0)
			gun_offset = Vector3(-0.08, -0.10, 0.06)
	# Keep the category-specific rotations as a small stylistic offset, then use
	# a two-bone solve so the hand and the physical shell/magazine actually meet.
	# Floating props look worse than a simpler pose, especially from the wider
	# desktop camera requested for this restoration.
	_solve_reload_left_arm(_reload_left_hand_target(progress), left_upper, left_forearm)
	_apply_reload_bone_rotation("Bip01 R UpperArm", right_upper * pulse)
	if is_instance_valid(gun_mount):
		gun_mount.position = gun_mount_rest_position + gun_offset * pulse
		gun_mount.quaternion = gun_mount.quaternion * Basis.from_euler(gun_tilt * (PI / 180.0) * pulse).get_rotation_quaternion()
	_update_reload_hand_prop()

func _reload_left_hand_target(progress: float) -> Vector3:
	if not is_instance_valid(recovered_skeleton) or not is_instance_valid(reload_part_socket):
		return reload_hand_start_local
	var socket_local := recovered_skeleton.to_local(reload_part_socket.global_position)
	var hip_world := global_position + Vector3.UP * 0.92 - global_transform.basis.x * 0.34 + global_transform.basis.z * 0.10
	var hip_local := recovered_skeleton.to_local(hip_world)
	var drop_fraction := maxf(0.0, float(current_weapon.get("drop_fraction", -1.0)))
	var hand_fraction := float(current_weapon.get("hand_fraction", 0.35))
	var insert_fraction := float(current_weapon.get("insert_fraction", 0.75))
	var result := reload_hand_start_local
	if float(current_weapon.get("drop_fraction", -1.0)) >= 0.0 and progress < drop_fraction:
		result = reload_hand_start_local.lerp(socket_local, smoothstep(0.0, 1.0, inverse_lerp(0.0, drop_fraction, progress)))
	elif progress < hand_fraction:
		var previous := socket_local if float(current_weapon.get("drop_fraction", -1.0)) >= 0.0 else reload_hand_start_local
		var segment_start := drop_fraction if float(current_weapon.get("drop_fraction", -1.0)) >= 0.0 else 0.0
		result = previous.lerp(hip_local, smoothstep(0.0, 1.0, inverse_lerp(segment_start, hand_fraction, progress)))
	elif progress < insert_fraction:
		var travel := smoothstep(0.0, 1.0, inverse_lerp(hand_fraction, insert_fraction, progress))
		result = hip_local.lerp(socket_local, travel)
		result += Vector3.UP * sin(travel * PI) * (0.14 if str(current_weapon.get("reload_style", "")) == "rocket" else 0.07)
	else:
		result = socket_local.lerp(reload_hand_start_local, smoothstep(0.0, 1.0, inverse_lerp(insert_fraction, 1.0, progress)))
	return result

func _solve_reload_left_arm(target: Vector3, upper_style_degrees: Vector3, forearm_style_degrees: Vector3) -> void:
	if not is_instance_valid(recovered_skeleton):
		return
	var upper_index := recovered_skeleton.find_bone("Bip01 L UpperArm")
	var forearm_index := recovered_skeleton.find_bone("Bip01 L Forearm")
	var hand_index := recovered_skeleton.find_bone("Bip01 L Hand")
	if upper_index < 0 or forearm_index < 0 or hand_index < 0:
		return
	var upper_pose := recovered_skeleton.get_bone_global_pose_no_override(upper_index)
	var forearm_pose := recovered_skeleton.get_bone_global_pose_no_override(forearm_index)
	var hand_pose := recovered_skeleton.get_bone_global_pose_no_override(hand_index)
	var shoulder := upper_pose.origin
	var elbow := forearm_pose.origin
	var wrist := hand_pose.origin
	var upper_length := maxf(0.001, shoulder.distance_to(elbow))
	var forearm_length := maxf(0.001, elbow.distance_to(wrist))
	var to_target := target - shoulder
	var distance := clampf(to_target.length(), 0.01, upper_length + forearm_length - 0.002)
	var direction := to_target.normalized()
	var along := (upper_length * upper_length - forearm_length * forearm_length + distance * distance) / (2.0 * distance)
	var bend_height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var current_bend := elbow - shoulder - direction * (elbow - shoulder).dot(direction)
	var pole := current_bend.normalized() if current_bend.length_squared() > 0.00001 else Vector3.UP.cross(direction).normalized()
	var desired_elbow := shoulder + direction * along + pole * bend_height
	var upper_from := (elbow - shoulder).normalized()
	var upper_to := (desired_elbow - shoulder).normalized()
	upper_pose.basis = Basis(Quaternion(upper_from, upper_to)) * upper_pose.basis
	upper_pose.basis = upper_pose.basis * Basis.from_euler(upper_style_degrees * (PI / 180.0) * 0.08)
	recovered_skeleton.set_bone_global_pose_override(upper_index, upper_pose, 1.0, true)
	var forearm_from := (wrist - elbow).normalized()
	var forearm_to := (target - desired_elbow).normalized()
	forearm_pose.origin = desired_elbow
	forearm_pose.basis = Basis(Quaternion(forearm_from, forearm_to)) * forearm_pose.basis
	forearm_pose.basis = forearm_pose.basis * Basis.from_euler(forearm_style_degrees * (PI / 180.0) * 0.05)
	recovered_skeleton.set_bone_global_pose_override(forearm_index, forearm_pose, 1.0, true)
	hand_pose.origin = target
	recovered_skeleton.set_bone_global_pose_override(hand_index, hand_pose, 1.0, true)
	recovered_skeleton.force_update_bone_child_transform(upper_index)

func _apply_reload_bone_rotation(bone_name: String, degrees: Vector3) -> void:
	if not is_instance_valid(recovered_skeleton):
		return
	var bone_index := recovered_skeleton.find_bone(bone_name)
	if bone_index < 0:
		return
	var pose := recovered_skeleton.get_bone_global_pose_no_override(bone_index)
	pose.basis = pose.basis * Basis.from_euler(degrees * (PI / 180.0))
	recovered_skeleton.set_bone_global_pose_override(bone_index, pose, 0.92, true)
	recovered_skeleton.force_update_bone_child_transform(bone_index)

func _emit_ammo() -> void:
	if _uses_magazine():
		ammo_changed.emit(_magazine_rounds(), -1, reload_left > 0.0)
	else:
		ammo_changed.emit(energy, max_energy, false)

func take_damage(amount: float, _hit_position := Vector3.ZERO, _source: Node = null) -> void:
	if dead:
		return
	if randf() < clampf(float(armor_skills.get("block_rate", 0.0)), 0.0, 0.9):
		AudioDirector.play_3d("force_shield01.wav", global_position, -6.0)
		return
	var health_before := health
	var shield_before := shield
	# Unity multiplies personal reduction, the team aura and the optional
	# weapon-category defence. Category defence matters in VS/co-op damage and is
	# harmless for ordinary enemies, which do not expose a weapon category.
	var damage_multiplier := maxf(0.0, 1.0 + float(armor_skills.get("damage_reduce", 0.0)))
	damage_multiplier *= maxf(0.0, 1.0 + float(armor_skills.get("team_damage_reduce", 0.0)))
	if is_instance_valid(_source) and _source.has_method("get_damage_category"):
		var defence_key := str(_source.get_damage_category())
		if not defence_key.is_empty():
			damage_multiplier *= maxf(0.0, 1.0 + float(armor_skills.get(defence_key, 0.0)))
	var remaining := amount * damage_multiplier
	if is_instance_valid(armor_power_controller) and armor_power_controller.has_method("modify_incoming_damage"):
		remaining = float(armor_power_controller.modify_incoming_damage(remaining))
	if remaining < 0.0:
		# HURT HEALTH turns the final mitigated hit into healing. Unity applies it
		# directly to HP, so it intentionally bypasses the restoration's shield.
		health = minf(max_health, health - remaining)
		remaining = 0.0
	elif shield > 0.0:
		var absorbed := minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	health = maxf(0.0, health - remaining)
	var actual_damage := maxf(0.0, health_before + shield_before - health - shield)
	# Keep PvP on the same authoritative confirmation path as enemy damage.
	# Blocks, mitigation, overkill and negative/healing damage therefore cannot
	# produce a false hitmarker on the attacking player's HUD.
	if actual_damage > 0.0 and is_instance_valid(_source) and _source != self and _source.has_method("on_damage_dealt"):
		_source.on_damage_dealt(actual_damage)
	if remaining > 0.0 and float(armor_skills.get("speed_on_hit", 0.0)) > 0.0:
		speed_on_hit_left = 2.5
	health_changed.emit(health, shield)
	if hurt_audio.stream and not hurt_audio.playing:
		hurt_audio.play()
	hurt_pose_left = 0.22
	recovered_animation_name = ""
	var tween := create_tween()
	tween.tween_property(model, "scale", Vector3(1.08, 0.94, 1.08), 0.055)
	tween.tween_property(model, "scale", Vector3.ONE, 0.1)
	if health <= 0.0:
		_die(_source)

func restore(kind: String, amount: float) -> void:
	if kind == "energy":
		energy = mini(max_energy, energy + int(amount))
		_emit_ammo()
	elif kind == "shield":
		shield = minf(max_shield, shield + amount)
	elif kind == "health":
		health = minf(max_health, health + amount * maxf(0.0, 1.0 + float(armor_skills.get("recovery_boost", 0.0))))
	elif kind == "ammo":
		energy = mini(max_energy, energy + int(amount))
		_emit_ammo()
	health_changed.emit(health, shield)

func set_armor_power_controller(controller: Node) -> void:
	armor_power_controller = controller

func heal_from_armor_power(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var before := health
	health = minf(max_health, health + amount)
	if health > before:
		health_changed.emit(health, shield)
	return health - before

func on_damage_dealt(actual_damage: float) -> void:
	if is_instance_valid(armor_power_controller) and armor_power_controller.has_method("on_damage_dealt"):
		armor_power_controller.on_damage_dealt(actual_damage)
	if actual_damage > 0.0:
		hit_confirmed.emit(actual_damage)

func on_enemy_defeated() -> void:
	kill_confirmed.emit()
	var recovery := float(armor_skills.get("hp_on_kill", 0.0)) * ARMOR_HP_SCALE
	if recovery <= 0.0 or dead:
		return
	health = minf(max_health, health + recovery)
	health_changed.emit(health, shield)

func _update_armor_effects(delta: float) -> void:
	speed_on_hit_left = maxf(0.0, speed_on_hit_left - delta)
	# GameWorld.TeamSkills contains at least the local player's aura even in the
	# original single-player mode. With no remote peer model in this restoration,
	# applying the equipped local aura reproduces that baseline exactly.
	var recovery_per_second := (
		float(armor_skills.get("hp_auto_recovery", 0.0))
		+ float(armor_skills.get("team_hp_recovery", 0.0))
	) * ARMOR_HP_SCALE
	if recovery_per_second > 0.0 and health > 0.0 and health < max_health:
		health = minf(max_health, health + recovery_per_second * delta)
		health_changed.emit(health, shield)

func _current_weapon_damage() -> float:
	var base_damage := float(current_weapon.get("damage", 0.0))
	var global_multiplier := maxf(
		0.0,
		1.0
		+ float(armor_skills.get("attack_boost", 0.0))
		+ float(armor_skills.get("team_attack_boost", 0.0))
	)
	var category_multiplier := maxf(0.0, 1.0 + float(armor_skills.get(_weapon_skill_key(), 0.0)))
	var result := base_damage * global_multiplier * category_multiplier
	if is_instance_valid(armor_power_controller) and armor_power_controller.has_method("modify_outgoing_damage"):
		result = float(armor_power_controller.modify_outgoing_damage(result))
	return result

func _weapon_skill_key() -> String:
	return _weapon_skill_key_for_kind(str(current_weapon.get("kind", "hitscan")))

func _weapon_skill_key_for_kind(kind: String) -> String:
	match kind:
		"shotgun": return "shotgun_boost"
		"shockwave": return "impulse_boost"
		"rocket": return "rpg_boost"
		"grenade", "fly_grenade": return "grenade_boost"
		"laser": return "laser_boost"
		"beam", "snow": return "laser_cannon_boost"
		"plasma": return "plasma_boost"
		"machinegun": return "machine_boost"
		"arrow": return "bow_boost"
		"energy_fist", "spring": return "glove_boost"
		"sword": return "sword_boost"
		"sniper", "reflection": return "sniper_boost"
		"tracking": return "tracking_boost"
		"ricochet": return "pingpong_boost"
		_: return "assault_boost"

func get_damage_category() -> String:
	match str(current_weapon.get("kind", "hitscan")):
		"shotgun": return "shotgun_defence"
		"shockwave": return "impulse_defence"
		"rocket": return "rpg_defence"
		"grenade", "fly_grenade": return "grenade_defence"
		"laser": return "laser_defence"
		"beam", "snow": return "laser_cannon_defence"
		"plasma": return "plasma_defence"
		"machinegun": return "machine_defence"
		"arrow": return "bow_defence"
		"energy_fist", "spring": return "glove_defence"
		"sword": return "sword_defence"
		"sniper", "reflection": return "sniper_defence"
		"tracking": return "tracking_defence"
		"ricochet": return "pingpong_defence"
		_: return "assault_defence"

func _die(killer: Node = null) -> void:
	dead = true
	if is_instance_valid(killer) and killer != self and killer.has_method("on_enemy_defeated"):
		killer.on_enemy_defeated()
	if is_instance_valid(armor_power_controller) and armor_power_controller.has_method("cancel_all_active"):
		armor_power_controller.cancel_all_active(false)
	_stop_continuous_weapon_audio()
	_stop_flying_audio()
	AudioDirector.play_3d("player_killed_1.wav", global_position)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if recovered_animation_player and recovered_animation_player.has_animation("dead"):
		recovered_animation_name = ""
		_play_recovered_animation("dead", 0.08)
	else:
		var tween := create_tween()
		tween.tween_property(model, "rotation:z", deg_to_rad(82.0), 0.42).set_trans(Tween.TRANS_QUAD)
	died.emit()

func set_touch_move(value: Vector2) -> void:
	touch_move = value

func set_touch_fire(pressed: bool) -> void:
	if pressed and not touch_fire:
		touch_fire_started = true
	touch_fire = pressed

func request_touch_dash() -> void:
	touch_dash_requested = true

func request_touch_reload() -> void:
	touch_reload_requested = true

func _update_visual_animation(delta: float, movement: float, movement_input := Vector2.ZERO) -> void:
	if recovered_animation_player:
		_update_recovered_animation(movement, movement_input)
	else:
		animation_clock += delta * (8.5 if movement > 0.1 else 2.1)
		if model.has_node("ArmL"):
			var swing := sin(animation_clock) * 0.42 * movement
			model.get_node("ArmL").rotation.x = swing
			model.get_node("ArmR").rotation.x = -swing
			model.get_node("LegL").rotation.x = -swing
			model.get_node("LegR").rotation.x = swing
		model.position.y = sin(animation_clock * 0.5) * (0.025 + movement * 0.018)
		var aim_weight := 1.0 if shoot_pose_left > 0.0 else 0.0
		gun_mount.rotation.x = lerpf(gun_mount.rotation.x, -0.08 - aim_weight * 0.09, 1.0 - exp(-16.0 * delta))
		model.rotation.z = lerpf(model.rotation.z, (0.12 if hurt_pose_left > 0.0 else 0.0), 1.0 - exp(-14.0 * delta))
	var flying := float(armor_skills.get("fly", 0.0)) > 0.0
	_update_flying_audio(flying, movement > 0.1)
	if movement > 0.25 and is_on_floor() and not flying:
		footstep_clock += delta * movement
		if footstep_clock >= 0.38:
			footstep_clock = 0.0
			AudioDirector.play_3d("walk_metal.wav", global_position, -13.0, randf_range(0.95, 1.05))
	else:
		footstep_clock = 0.3

func _update_recovered_animation(movement: float, movement_input := Vector2.ZERO) -> void:
	if not is_instance_valid(recovered_animation_player):
		return
	var restart_shoot_animation := restart_shoot_animation_requested
	restart_shoot_animation_requested = false
	if hurt_pose_left > 0.0 and recovered_animation_player.has_animation("attacked"):
		_play_recovered_animation("attacked", 0.04)
		return
	var moving := movement > 0.1
	var weapon_pose := str(current_weapon.get("animation", "rifle"))
	var locomotion_pose := weapon_pose
	if locomotion_pose == "grenade_launcher":
		locomotion_pose = "shotgun"
	elif locomotion_pose == "laser":
		locomotion_pose = "rifle"
	elif locomotion_pose == "BLACKSTARS":
		locomotion_pose = "bazinga"
	if float(armor_skills.get("fly", 0.0)) > 0.0:
		_update_recovered_flying_animation(moving, movement_input, weapon_pose, locomotion_pose, restart_shoot_animation)
		return
	var requested_candidate := ""
	if shoot_pose_left > 0.0:
		requested_candidate = ("run_shoot_" if moving else "stand_shoot_") + weapon_pose
	else:
		requested_candidate = ("run_" if moving else "idle_") + locomotion_pose
	var rifle_fallback := ""
	if shoot_pose_left > 0.0:
		rifle_fallback = "run_shoot_rifle" if moving else "stand_shoot_rifle"
	else:
		rifle_fallback = "run_rifle" if moving else "idle_rifle"
	var safe_pose_fallback := "run_rifle" if moving else "idle_rifle"
	var candidate := _first_available_recovered_animation([
		requested_candidate,
		rifle_fallback,
		safe_pose_fallback,
	])
	# Godot 4.5 and 4.7 can assign different names while importing the same
	# legacy glTF animation library. The old code assumed its rifle fallback
	# always existed and assigned loop_mode on null, which is the crash reported
	# for the laser/sniper weapons (and could affect every other gun as well).
	if candidate.is_empty():
		return
	if shoot_pose_left > 0.0:
		# The original AttackState used WrapMode.Loop for automatic weapons and
		# kept the same run-shoot state alive between bullets. Reconfigure the
		# shared imported clip for the equipped weapon instead of restarting it
		# from frame zero on every successful shot.
		var shoot_animation := recovered_animation_player.get_animation(candidate)
		if shoot_animation:
			shoot_animation.loop_mode = Animation.LOOP_LINEAR if bool(current_weapon.get("automatic", false)) else Animation.LOOP_NONE
		if moving and weapon_pose not in ["machinegun", "jian"]:
			var locomotion_candidate := _first_available_recovered_animation(["run_" + locomotion_pose, "run_rifle"])
			if not locomotion_candidate.is_empty() and candidate.begins_with("run_shoot_"):
				_play_recovered_layered_animation(locomotion_candidate, candidate, restart_shoot_animation)
				return
	_play_recovered_animation(candidate, 0.08, restart_shoot_animation and shoot_pose_left > 0.0)

func _update_recovered_flying_animation(
	moving: bool,
	movement_input: Vector2,
	weapon_pose: String,
	locomotion_pose: String,
	restart_shoot_animation: bool
) -> void:
	var base_candidate := _fly_direction_animation(movement_input) if moving else "fly_idle"
	base_candidate = _first_available_recovered_animation([
		base_candidate,
		"fly_front" if moving else "fly_idle",
		"run_rifle" if moving else "idle_rifle",
	])
	if base_candidate.is_empty():
		return

	if shoot_pose_left > 0.0:
		var flying_shoot := ""
		if moving and weapon_pose in ["machinegun", "jian"]:
			flying_shoot = "fly_runshoot_" + weapon_pose
		else:
			flying_shoot = ("run_shoot_" if moving else "fly_stand_shoot_") + weapon_pose
		var shoot_candidate := _first_available_recovered_animation([
			flying_shoot,
			("run_shoot_rifle" if moving else "fly_stand_shoot_rifle"),
			("run_shoot_rifle" if moving else "stand_shoot_rifle"),
		])
		if shoot_candidate.is_empty():
			_play_recovered_animation(base_candidate, 0.08)
			return
		var shoot_animation := recovered_animation_player.get_animation(shoot_candidate)
		if shoot_animation:
			shoot_animation.loop_mode = Animation.LOOP_LINEAR if bool(current_weapon.get("automatic", false)) else Animation.LOOP_NONE
		# Unity supplies a looping lower-body sword hover while its upper-body
		# strike plays. Preserve that authored exception when standing still.
		if not moving and weapon_pose == "jian":
			base_candidate = _first_available_recovered_animation([
				"fly_stand_shoot_jian_lower", base_candidate
			])
		_play_recovered_layered_animation(base_candidate, shoot_candidate, restart_shoot_animation)
		return

	var upper_candidate := _first_available_recovered_animation([
		("fly_" if moving else "fly_idle_") + locomotion_pose,
		("fly_rifle" if moving else "fly_idle_rifle"),
	])
	if upper_candidate.is_empty():
		_play_recovered_animation(base_candidate, 0.08)
	else:
		_play_recovered_layered_animation(base_candidate, upper_candidate)

func _fly_direction_animation(movement_input: Vector2) -> String:
	if absf(movement_input.x) > absf(movement_input.y):
		return "fly_right" if movement_input.x > 0.0 else "fly_left"
	return "fly_back" if movement_input.y > 0.0 else "fly_front"

func _update_flying_audio(flying: bool, moving: bool) -> void:
	if not flying:
		_stop_flying_audio()
		return
	var requested := "move" if moving else "idle"
	if requested == float_audio_state:
		return
	AudioDirector.stop("player_float")
	float_audio_state = requested
	AudioDirector.play_loop_3d(
		"float_move.wav" if moving else "float_idle.wav",
		global_position,
		"player_float",
		-10.0
	)

func _stop_flying_audio() -> void:
	if float_audio_state.is_empty():
		return
	float_audio_state = ""
	AudioDirector.stop("player_float")

func _first_available_recovered_animation(candidates: Array) -> String:
	if not is_instance_valid(recovered_animation_player):
		return ""
	for candidate_value in candidates:
		var candidate := str(candidate_value)
		if not candidate.is_empty() and recovered_animation_player.has_animation(candidate):
			return candidate
	return ""

func _set_fire_sound(sound_id: String) -> void:
	# Kept as an API-compatible no-op; AudioDirector now owns overlapping and
	# looped weapon voices.
	pass

func _play_weapon_fire_sound() -> void:
	var sound_path := str(current_weapon.get("sound", ""))
	var variants: Array = current_weapon.get("sound_variants", [])
	if not variants.is_empty():
		sound_path = str(variants.pick_random())
	if not sound_path.is_empty():
		AudioDirector.play_3d(sound_path, global_position, -1.0, randf_range(0.97, 1.03))

func _update_continuous_weapon_audio(trigger: bool, just_triggered: bool) -> void:
	var loop_path := str(current_weapon.get("loop_sound", ""))
	if loop_path.is_empty():
		return
	var key := "player_weapon_loop"
	if trigger:
		if just_triggered:
			weapon_audio_active = true
			var intro_path := str(current_weapon.get("sound", ""))
			if intro_path.is_empty():
				AudioDirector.play_loop_3d(loop_path, global_position, key, -2.0)
			else:
				var intro := AudioDirector.play_3d(intro_path, global_position, -1.0, 1.0, "player_weapon_intro")
				if intro:
					intro.finished.connect(_begin_continuous_weapon_loop.bind(loop_path))
				else:
					AudioDirector.play_loop_3d(loop_path, global_position, key, -2.0)
		elif weapon_audio_active and not AudioDirector.is_playing("player_weapon_intro"):
			AudioDirector.play_loop_3d(loop_path, global_position, key, -2.0)
	elif weapon_audio_active:
		_stop_continuous_weapon_audio()

func _begin_continuous_weapon_loop(loop_path: String) -> void:
	if weapon_audio_active and not loop_path.is_empty():
		AudioDirector.play_loop_3d(loop_path, global_position, "player_weapon_loop", -2.0)

func _stop_continuous_weapon_audio() -> void:
	if not weapon_audio_active:
		return
	AudioDirector.stop("player_weapon_intro")
	AudioDirector.stop("player_weapon_loop")
	var stop_path := str(current_weapon.get("stop_sound", ""))
	if not stop_path.is_empty():
		AudioDirector.play_3d(stop_path, global_position, -2.0)
	weapon_audio_active = false

func _normalize_mesh(instance: MeshInstance3D, target_height: float) -> void:
	var bounds := instance.mesh.get_aabb()
	if bounds.size.y > 0.001:
		var factor := target_height / bounds.size.y
		instance.scale = Vector3.ONE * factor
		instance.position.y = -bounds.position.y * factor

func _material(color: Color, roughness: float, metallic: float, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 2.0
	return material

func _add_box(parent: Node, size: Vector3, position_value: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position_value
	parent.add_child(instance)
	return instance

func _add_cylinder(parent: Node, radius: float, height: float, position_value: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.material = material
	instance.mesh = mesh
	instance.position = position_value
	parent.add_child(instance)
	return instance

func _add_cone(parent: Node, radius: float, height: float, position_value: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.material = material
	instance.mesh = mesh
	instance.position = position_value
	parent.add_child(instance)
	return instance

func _add_sphere(parent: Node, scale_value: Vector3, position_value: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = material
	instance.mesh = mesh
	instance.scale = scale_value * 2.0
	instance.position = position_value
	parent.add_child(instance)
	return instance

func _add_capsule(parent: Node, radius: float, height: float, position_value: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh.material = material
	instance.mesh = mesh
	instance.position = position_value
	parent.add_child(instance)
	return instance
