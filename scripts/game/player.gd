class_name WarfarePlayer
extends CharacterBody3D

signal health_changed(health: float, shield: float)
signal ammo_changed(current: int, reserve: int, reloading: bool)
signal weapon_changed(weapon_id: String, weapon_data: Dictionary)
signal dash_changed(ratio: float)
signal died

const ProjectileScript = preload("res://scripts/game/projectile.gd")

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

var camera_yaw := 0.0
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
var gun_socket: BoneAttachment3D
var backpack_socket: BoneAttachment3D
var backpack_visual: MeshInstance3D

var weapon_order: Array[String] = []
var current_weapon_id := "gun00"
var current_weapon: Dictionary = {}
var max_energy := 5000
var energy := 5000
var shot_cooldown := 0.0
var reload_left := 0.0
var weapon_audio_active := false
var shoot_pose_left := 0.0
var restart_shoot_animation_requested := false
var hurt_pose_left := 0.0
var footstep_clock := 0.0

var fire_audio: AudioStreamPlayer3D
var hurt_audio: AudioStreamPlayer3D

func _ready() -> void:
	name = "Player"
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1
	_build_collision()
	_build_visual()
	_build_camera()
	_build_audio()
	weapon_order.assign(GameState.battle_weapons)
	equip_weapon(GameState.selected_weapon, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("mobile") else Input.MOUSE_MODE_CAPTURED
	health_changed.emit(health, shield)

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
	gun_mount_rest_position = gun_mount.position
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
		if animation_name.begins_with("idle_") or (animation_name.begins_with("run_") and not animation_name.begins_with("run_shoot_")):
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
	var backpack_path := "res://assets/models/player/animated/bag.obj"
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
	backpack_visual.transform = Transform3D(
		fly_bag_rest.basis.inverse() * Basis.from_scale(Vector3.ONE * 0.8),
		Vector3.ZERO
	)
	backpack_socket.add_child(backpack_visual)

func _play_recovered_animation(animation_name: String, blend := 0.08, restart := false) -> void:
	if not recovered_animation_player or not recovered_animation_player.has_animation(animation_name):
		return
	if recovered_animation_tree and recovered_animation_tree.active:
		recovered_animation_tree.active = false
		recovered_layered_animation = false
	if not restart and recovered_animation_name == animation_name and recovered_animation_player.is_playing():
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
	for child in gun_mount.get_children():
		child.queue_free()
	var data: Dictionary = GameState.WEAPONS.get(current_weapon_id, GameState.WEAPONS.gun00)
	var weapon_color: Color = data.color
	var metal := _material(Color(0.06, 0.075, 0.09), 0.43, 0.73)
	var accent := _material(weapon_color.darkened(0.15), 0.28, 0.62, weapon_color * 0.5)
	var kind := str(data.kind)
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
			gun_mount.add_child(restored)
			added_restored_visual = true
	if not added_restored_visual:
		_add_box(gun_mount, size, Vector3.ZERO, metal, "WeaponBody")
		_add_box(gun_mount, Vector3(size.x * 1.25, 0.07, size.z * 0.72), Vector3(0, 0.14, -0.06), accent, "WeaponGlow")
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -size.z * 0.62)
	gun_mount.add_child(muzzle)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = weapon_color
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 3.6
	muzzle.add_child(muzzle_light)

func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	# Unity rotated the player first and then evaluated
	# target.TransformPoint(pivotPosition). Keep the yaw pivot on the player's
	# centerline so the authored +0.6 shoulder offset rotates with the view.
	camera_rig.position = Vector3(0.0, 1.683712, 0.0)
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
		velocity.y -= gravity * delta
		move_and_slide()
		return

	shot_cooldown = maxf(0.0, shot_cooldown - delta)
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
		velocity.x = move_toward(velocity.x, desired.x * move_speed, 34.0 * delta)
		velocity.z = move_toward(velocity.z, desired.z * move_speed, 34.0 * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	move_and_slide()

	model.rotation.y = camera_yaw
	# Resolve firing before choosing the pose. This keeps an automatic weapon's
	# shoot window alive on the exact frame its cooldown expires instead of
	# briefly falling back to run/idle between consecutive shots.
	_handle_weapon_input()
	_update_visual_animation(delta, desired.length())

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look_delta(event.relative)
	elif event is InputEventMouseButton and event.pressed and not OS.has_feature("mobile") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventScreenDrag and event.position.x > get_viewport().get_visible_rect().size.x * 0.36:
		_apply_look_delta(event.relative * 0.72)
	elif event.is_action_pressed("zoom_in"):
		camera_distance = maxf(1.9, camera_distance - 0.2)
	elif event.is_action_pressed("zoom_out"):
		camera_distance = minf(4.5, camera_distance + 0.2)

func _apply_look_delta(relative: Vector2) -> void:
	var sensitivity := float(GameState.settings.look_sensitivity) * 0.01
	camera_yaw -= relative.x * sensitivity
	var direction := -1.0 if bool(GameState.settings.invert_y) else 1.0
	camera_pitch -= relative.y * sensitivity * direction
	camera_pitch = clampf(camera_pitch, deg_to_rad(-62.0), deg_to_rad(38.0))
	camera_rig.rotation.y = camera_yaw
	pitch_node.rotation.x = camera_pitch

func _handle_weapon_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		_equip_loadout_slot(0)
	elif Input.is_action_just_pressed("weapon_2"):
		_equip_loadout_slot(1)
	elif Input.is_action_just_pressed("weapon_3"):
		_equip_loadout_slot(2)
	elif Input.is_action_just_pressed("weapon_4"):
		_equip_loadout_slot(3)
	if Input.is_action_just_pressed("reload") or touch_reload_requested:
		cycle_weapon(-1)
	touch_reload_requested = false
	var trigger := Input.is_action_pressed("fire") or touch_fire
	var just_triggered := Input.is_action_just_pressed("fire") or touch_fire_started
	touch_fire_started = false
	_update_continuous_weapon_audio(trigger, just_triggered)
	if (bool(current_weapon.automatic) and trigger) or (not bool(current_weapon.automatic) and just_triggered):
		_try_fire()

func _equip_loadout_slot(index: int) -> void:
	if index >= 0 and index < weapon_order.size():
		equip_weapon(weapon_order[index])

func equip_weapon(weapon_id: String, persist_selection := true) -> void:
	if not GameState.WEAPONS.has(weapon_id):
		return
	_stop_continuous_weapon_audio()
	current_weapon_id = weapon_id
	current_weapon = GameState.WEAPONS[weapon_id].duplicate(true)
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

func _try_fire() -> void:
	if shot_cooldown > 0.0 or reload_left > 0.0 or dead or current_weapon.is_empty():
		return
	# Imported weapon meshes and animation libraries can be regenerated by a
	# different Godot minor version. Never let a missing visual node turn a
	# valid weapon shot into a script crash.
	if not is_instance_valid(muzzle) or not is_instance_valid(muzzle_light) or not is_instance_valid(gun_mount):
		_build_gun_visual()
	if not is_instance_valid(muzzle) or not is_instance_valid(muzzle_light) or not is_instance_valid(gun_mount):
		return
	var energy_cost := int(current_weapon.energy)
	if energy_cost > energy:
		AudioDirector.play_3d(str(current_weapon.get("blank_sound", "blank/blank_shot01.wav")), global_position, -4.0)
		return
	energy -= energy_cost
	shot_cooldown = float(current_weapon.cooldown)
	shoot_pose_left = maxf(0.14, minf(0.55, shot_cooldown))
	# One-shot clips must restart on every successful trigger pull. Automatic
	# clips deliberately remain continuous while the button is held.
	restart_shoot_animation_requested = not bool(current_weapon.get("automatic", false))
	muzzle_light.light_energy = 5.0
	get_tree().create_timer(0.045).timeout.connect(func():
		if is_instance_valid(muzzle_light): muzzle_light.light_energy = 0.0
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
				collider.take_damage(float(current_weapon.damage), result.position, self)
		if get_parent().has_method("spawn_tracer"):
			get_parent().spawn_tracer(muzzle.global_position, hit_position, current_weapon.color, str(current_weapon.kind) == "pierce")
		if not result.is_empty() and get_parent().has_method("spawn_impact"):
			get_parent().spawn_impact(hit_position, result.normal, current_weapon.color)

func _fire_projectile(projectile_kind: String) -> void:
	var aim := get_aim_solution(float(current_weapon.get("range", 105.0)))
	# Unity first raycast from the shoulder camera and then converged the actual
	# muzzle toward that point.  This prevents close shots from travelling
	# parallel to (and visibly missing) the reticle.
	var direction: Vector3 = (Vector3(aim.target) - muzzle.global_position).normalized()
	if projectile_kind == "grenade":
		direction = (direction + Vector3.UP * 0.18).normalized()
	var projectile := ProjectileScript.new()
	projectile.configure(self, direction, float(current_weapon.speed), float(current_weapon.damage), maxf(float(current_weapon.splash), 0.65), current_weapon.color, false, projectile_kind, str(current_weapon.explosion_sound))
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
			target.take_damage(float(current_weapon.damage), center, self)
			made_contact = true
	var sound_path := str(current_weapon.get("sound", ""))
	if sound_path.is_empty():
		var choices: Array = current_weapon.get("hit_sounds", []) if made_contact else current_weapon.get("swing_sounds", [])
		if not choices.is_empty():
			sound_path = str(choices.pick_random())
	if not sound_path.is_empty():
		AudioDirector.play_3d(sound_path, global_position, -1.0, randf_range(0.97, 1.03))

func _start_reload() -> void:
	# The original game has no per-gun reload: every shot consumes the shared
	# energy reserve.  This method remains for old input bindings.
	return

func _update_reload(delta: float) -> void:
	reload_left = maxf(0.0, reload_left - delta)

func _emit_ammo() -> void:
	ammo_changed.emit(energy, max_energy, false)

func take_damage(amount: float, _hit_position := Vector3.ZERO, _source: Node = null) -> void:
	if dead:
		return
	var remaining := amount
	if shield > 0.0:
		var absorbed := minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	health = maxf(0.0, health - remaining)
	health_changed.emit(health, shield)
	if hurt_audio.stream and not hurt_audio.playing:
		hurt_audio.play()
	hurt_pose_left = 0.22
	recovered_animation_name = ""
	var tween := create_tween()
	tween.tween_property(model, "scale", Vector3(1.08, 0.94, 1.08), 0.055)
	tween.tween_property(model, "scale", Vector3.ONE, 0.1)
	if health <= 0.0:
		_die()

func restore(kind: String, amount: float) -> void:
	if kind == "energy":
		energy = mini(max_energy, energy + int(amount))
		_emit_ammo()
	elif kind == "shield":
		shield = minf(max_shield, shield + amount)
	elif kind == "health":
		health = minf(max_health, health + amount)
	elif kind == "ammo":
		energy = mini(max_energy, energy + int(amount))
		_emit_ammo()
	health_changed.emit(health, shield)

func _die() -> void:
	dead = true
	_stop_continuous_weapon_audio()
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

func _update_visual_animation(delta: float, movement: float) -> void:
	if recovered_animation_player:
		_update_recovered_animation(movement)
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
	if movement > 0.25 and is_on_floor():
		footstep_clock += delta * movement
		if footstep_clock >= 0.38:
			footstep_clock = 0.0
			AudioDirector.play_3d("walk_metal.wav", global_position, -13.0, randf_range(0.95, 1.05))
	else:
		footstep_clock = 0.3

func _update_recovered_animation(movement: float) -> void:
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
