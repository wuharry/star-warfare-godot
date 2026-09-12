extends Node3D

var player: WarfarePlayer
var view_camera: Camera3D
var fill: OmniLight3D
var label: Label
var elapsed := 0.0
var duration := 0.0
var moving := false
const VIEWS := {"front": Vector3(2.5, 1.8, -2.8), "side": Vector3(-3.1, 1.8, -0.7), "rear": Vector3(2.7, 1.8, 2.7)}

func setup() -> void:
	GameState.save_path = "user://reload_catalog_test_profile.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_weapon = "gun00"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.045, 0.055, 0.07)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.5
	add_child(light)
	fill = OmniLight3D.new()
	fill.light_energy = 2.0
	fill.omni_range = 8
	add_child(fill)
	player = WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	view_camera = Camera3D.new()
	view_camera.fov = 40
	add_child(view_camera)
	view_camera.current = true
	set_view("front")
	label = Label.new()
	label.position = Vector2(18, 14)
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)

func begin(key: String, variant: int, walk := false, shells := 3) -> void:
	player._cancel_reload()
	for debris in get_tree().get_nodes_in_group("reload_debris"):
		debris.free()
	player.equip_weapon(key, false)
	player.reload_variant_override = variant
	player.rocket_reload_variant = -1
	player.shoot_pose_left = 0
	player.hurt_pose_left = 0
	player.velocity = Vector3.ZERO
	player.body_yaw = 0
	player.model.rotation.y = 0
	player.camera_yaw = 0
	player.recovered_animation_tree.active = false
	player._play_recovered_animation(player._reload_idle_animation(), 0, true)
	player.recovered_animation_player.advance(0)
	player.recovered_skeleton.clear_bones_global_pose_override()
	player.recovered_skeleton.force_update_all_bone_transforms()
	player.gun_socket.transform = player.recovered_skeleton.get_bone_global_pose(player.recovered_skeleton.find_bone(player.gun_socket.bone_name))
	var is_shell := str(player.current_weapon.reload_style) == "shotgun_shell"
	player._set_magazine_rounds(maxi(0, int(player.current_weapon.magazine_size) - shells) if is_shell else 0)
	player._start_reload()
	duration = player.reload_total * (shells if is_shell else 1)
	elapsed = 0
	moving = walk
	step(0)

func step(delta: float) -> void:
	player._update_reload(delta)
	player._update_body_facing(delta, Vector3.ZERO)
	player._update_combat_aim_pose(delta)
	player._update_recovered_animation(1 if moving else 0, Vector2(0, -1) if moving else Vector2.ZERO)
	if player.recovered_animation_tree.active:
		player.recovered_animation_tree.advance(delta)
	else:
		player.recovered_animation_player.advance(delta)
	player.recovered_skeleton.force_update_all_bone_transforms()
	player._update_reload_pose()
	elapsed += delta
	label.text = "%s / %s / %s / %.2f s" % [player.current_weapon_id, player.current_weapon.name, char(65 + player.active_reload_variant), elapsed]

func advance_to(time: float) -> void:
	while elapsed < time - 0.000001:
		var delta := minf(1.0 / 60, time - elapsed)
		if player.reload_left > 0:
			delta = minf(delta, player.reload_left)
		step(delta)

func set_view(view: String) -> void:
	view_camera.position = VIEWS[view]
	view_camera.look_at(Vector3(0, 1.13, -0.10))
	fill.position = view_camera.position

func cleanup() -> void:
	player._cancel_reload()
	player.queue_free()
	AudioDirector.stop_all_sfx()
