extends Node3D

const Fixture := preload("res://tests/reload_catalog_fixture.gd")
const Suit := preload("res://scripts/art/cartoon_viper.gd")
const OUT := "res://test_output/cartoon_viper/"
var suit := Suit.new()
var fixture: Node3D
var world: WarfareGameWorld
var status: Label
var mode := 0
var modern := true
var capturing := false
var clock := 0.0
var orbit_target := Vector3(0, 1.01, 0)

class WalkWorld extends WarfareGameWorld:
	func _ready() -> void:
		level_data = GameState.get_level_data(GameState.selected_level)
		arena_size = float(level_data.arena_size)
		completed = true
		GameState.apply_viewport_quality()
		_load_stage_metadata()
		_build_environment()
		_build_arena()
		_build_player()

func _ready() -> void:
	capturing = "--capture" in OS.get_cmdline_user_args() or "--motion-capture" in OS.get_cmdline_user_args() or "--walk-capture" in OS.get_cmdline_user_args()
	GameState.save_path = "user://cartoon_viper_preview_profile.json"
	GameState.settings.show_touch_controls = false
	GameState.settings.quality = "high"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	get_window().size = Vector2i(1280, 800)
	get_window().content_scale_size = Vector2i(1280, 800)
	get_window().title = "Star Warfare — Viper 卡通裝甲"
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_build_controls()
	_studio()
	if "--walk-capture" in OS.get_cmdline_user_args():
		_capture_walk.call_deferred()
	elif capturing:
		_capture_all.call_deferred()

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var row := HBoxContainer.new()
	row.position = Vector2(20, 20)
	row.add_theme_constant_override("separation", 8)
	layer.add_child(row)
	for index in 5:
		var button := Button.new()
		button.text = ["1 造型", "2 跑步", "3 跑射", "4 換彈", "5 實機走動"][index]
		button.pressed.connect(func() -> void: if not capturing: _select(index))
		row.add_child(button)
	for entry: Array in [["6 手部", "hand"], ["7 鞋部", "boots"], ["8 甲紋", "chest"], ["9 頭盔", "head"]]:
		var detail := Button.new()
		detail.text = entry[0]
		var view: String = entry[1]
		detail.pressed.connect(func() -> void: if not capturing: _detail(view))
		row.add_child(detail)
	var compare := Button.new()
	compare.text = "空白鍵：前／後"
	compare.pressed.connect(func() -> void: if not capturing: _toggle())
	row.add_child(compare)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 19)
	row.add_child(status)
	var help := Label.new()
	help.position = Vector2(24, 758)
	help.text = "展示：A / D 旋轉視角    實機：WASD 移動、滑鼠轉向、點擊射擊、R 換彈    Esc 返回／離開"
	layer.add_child(help)

func _clear_subject() -> void:
	suit.restore()
	if is_instance_valid(fixture):
		fixture.cleanup()
		fixture.free()
		fixture = null
	if is_instance_valid(world):
		world.free()
		world = null
	AudioDirector.stop_all_sfx()

func _studio() -> void:
	_clear_subject()
	fixture = Fixture.new()
	add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://cartoon_viper_preview_profile.json"
	fixture.label.hide()
	fixture.player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fixture.fill.light_energy = .35
	for child in fixture.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 1.25
			child.rotation_degrees = Vector3(-28, 145, 0)
			child.shadow_enabled = true
		elif child is WorldEnvironment:
			child.environment.background_color = Color("e2c9a3")
			child.environment.ambient_light_color = Color("b7b4d5")
			child.environment.ambient_light_energy = .5
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b39d8b")
	material.roughness = 1.0
	plane.material = material
	floor.mesh = plane
	floor.position.y = -.005
	fixture.add_child(floor)
	fixture.view_camera.fov = 34
	_view("three_quarter")
	if modern:
		suit.apply(fixture.player)
	_set_pose(0)

func _select(index: int) -> void:
	if index == 4:
		_clear_subject()
		GameState.selected_level = 3
		world = WalkWorld.new()
		add_child(world)
		if modern:
			suit.apply(world.player)
		mode = 4
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if not is_instance_valid(fixture):
			_studio()
		_set_pose(index)
	_update_label()

func _set_pose(index: int) -> void:
	mode = index
	clock = 0
	var player: WarfarePlayer = fixture.player
	player._cancel_reload()
	for debris in get_tree().get_nodes_in_group("reload_debris"):
		debris.free()
	player.recovered_animation_tree.active = false
	player.recovered_skeleton.clear_bones_global_pose_override()
	player.gun_socket.visible = index > 0
	player.left_gun_socket.hide()
	if index == 3:
		fixture.begin("gun00", 0, true)
	elif index == 0:
		player.recovered_animation_player.stop()
		_relaxed_stance(player.recovered_skeleton)
	else:
		player._play_recovered_animation("run_rifle", .12, true)
		player.recovered_animation_player.advance(0)
	_update_label()

func _advance(delta: float) -> void:
	if not is_instance_valid(fixture):
		return
	clock += delta
	var player: WarfarePlayer = fixture.player
	if mode == 3:
		if player.reload_left <= 0:
			fixture.begin("gun00", 0, true)
		fixture.step(delta)
	elif mode == 2:
		player.shoot_pose_left = 1.0
		player._update_recovered_animation(1.0, Vector2(0, -1))
		player.recovered_animation_tree.advance(delta)
	elif mode == 1:
		player.recovered_animation_player.advance(delta)
	player.recovered_skeleton.force_update_all_bone_transforms()

func _relaxed_stance(skeleton: Skeleton3D) -> void:
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	# A slight elbow bend and arms closer to the torso make the equipment view
	# readable as a person wearing armor. Gameplay still uses its authored clips.
	for adjustment: Array in [
		["Bip01 L UpperArm", Vector3.FORWARD, -3.0],
		["Bip01 R UpperArm", Vector3.FORWARD, 3.0],
		["Bip01 L Forearm", Vector3.RIGHT, 12.0],
		["Bip01 R Forearm", Vector3.RIGHT, 8.0],
	]:
		var bone := skeleton.find_bone(adjustment[0])
		var parent := skeleton.get_bone_parent(bone)
		var pose := skeleton.get_bone_global_pose(bone)
		pose.basis = Basis(adjustment[1], deg_to_rad(adjustment[2])) * pose.basis
		var local := skeleton.get_bone_global_pose(parent).affine_inverse() * pose
		skeleton.set_bone_pose_rotation(bone, local.basis.orthonormalized().get_rotation_quaternion())
		skeleton.force_update_all_bone_transforms()

func _process(delta: float) -> void:
	if not capturing:
		_advance(delta)

func _view(view: String) -> void:
	var positions := {"front": Vector3(0, 1.3, -4.2), "three_quarter": Vector3(2.6, 1.65, -4.0),
		"side": Vector3(4.2, 1.3, 0), "rear": Vector3(2.4, 1.5, 4.0),
		"head": Vector3(.73, 1.7, -1.45), "chest": Vector3(.95, 1.4, -1.7), "boots": Vector3(.65, .40, -1.0),
		"boot_side": Vector3(1.1, .22, .05), "hand": Vector3(.9, .85, -.7)}
	var targets := {"head": Vector3(0, 1.60, -.12), "chest": Vector3(0, 1.15, -.05), "boots": Vector3(0, .16, -.08),
		"boot_side": Vector3(.23, .13, -.08), "hand": Vector3(.45, .68, 0)}
	orbit_target = targets.get(view, Vector3(0, 1.01, 0))
	fixture.view_camera.position = positions[view]
	fixture.view_camera.look_at(orbit_target)
	fixture.fill.position = Vector3(-2, 2.5, -3)

func _detail(view: String) -> void:
	if not is_instance_valid(fixture):
		_studio()
	_set_pose(0)
	_view(view)

func _toggle() -> void:
	modern = not modern
	if modern:
		suit.apply(fixture.player if is_instance_valid(fixture) else world.player)
	else:
		suit.restore()
	_update_label()

func _update_label() -> void:
	status.text = "  %s · %s" % ["新版模型＋貼圖" if modern else "原本模型＋貼圖", ["造型", "跑步", "跑射", "換彈", "實機走動"][mode]]

func _unhandled_key_input(event: InputEvent) -> void:
	if capturing or not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_ESCAPE:
		if is_instance_valid(world):
			_studio()
		else:
			_clear_subject()
			get_tree().quit()
	elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]:
		_select(event.keycode - KEY_1)
	elif event.keycode in [KEY_6, KEY_7, KEY_8, KEY_9]:
		_detail(["hand", "boots", "chest", "head"][event.keycode - KEY_6])
	elif event.keycode == KEY_SPACE:
		_toggle()
	elif event.keycode in [KEY_A, KEY_D] and is_instance_valid(fixture):
		var pivot := orbit_target
		fixture.view_camera.position = pivot + (fixture.view_camera.position - pivot).rotated(Vector3.UP, .22 if event.keycode == KEY_A else -.22)
		fixture.view_camera.look_at(pivot)

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for tick in 5:
		await get_tree().process_frame
	_advance(.1)
	for view in ["three_quarter", "front", "side", "rear", "head", "hand", "boots", "boot_side", "chest"]:
		_view(view)
		await _save("new_" + view)
	_view("three_quarter")
	_toggle()
	await _save("baseline_three_quarter")
	for view in ["head", "hand", "boots"]:
		_view(view)
		await _save("baseline_" + view)
	_view("three_quarter")
	_toggle()
	for action in [1, 2, 3]:
		_set_pose(action)
		for sample in 4:
			for step in 12:
				_advance(1.0 / 60.0)
			await _save("%s_%02d" % [["", "run", "run_shoot", "reload"][action], sample])
	if "--motion-capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "motion"))
		for frame in 360:
			if frame in [0, 60, 150, 240]:
				_set_pose([0, 1, 2, 3][[0, 60, 150, 240].find(frame)])
			_advance(1.0 / 60.0)
			await _save("motion/frame_%04d" % frame)
	_select(4)
	for tick in 20:
		await get_tree().process_frame
	await _save("gameplay")
	if "--motion-capture" in OS.get_cmdline_user_args():
		for frame in 300:
			if frame == 30:
				world.player.set_touch_move(Vector2(0, -1))
			elif frame == 90:
				world.player.set_touch_move(Vector2.RIGHT)
			elif frame == 135:
				world.player.set_touch_move(Vector2.ZERO)
			elif frame == 165:
				world.player.set_touch_move(Vector2(0, -1))
				world.player.set_touch_fire(true)
			elif frame == 210:
				world.player.set_touch_fire(false)
				world.player.request_touch_reload()
			elif frame == 270:
				world.player.set_touch_move(Vector2.ZERO)
			await _save("motion/frame_%04d" % (frame + 360))
	_clear_subject()
	await get_tree().process_frame
	print("CARTOON_VIPER_CAPTURE_PASS viewport=1280x800 renderer=%s" % RenderingServer.get_current_rendering_method())
	get_tree().quit()

func _save(stem: String) -> void:
	await get_tree().process_frame
	# Idle/occluded windows need an explicit draw during offline capture.
	RenderingServer.force_draw(false, 0.0)
	var error := get_viewport().get_texture().get_image().save_png(OUT + stem + ".png")
	if error != OK:
		push_error("Could not save " + stem)
		get_tree().quit(1)

func _capture_walk() -> void:
	_select(4)
	world.player.set_touch_move(Vector2(0, -1))
	world.player.set_touch_fire(true)
	for frame in 120:
		await get_tree().process_frame
		RenderingServer.force_draw(false, 0.0)
	world.player.set_touch_fire(false)
	world.player.request_touch_reload()
	await _save("gameplay_firing")
	for frame in 120:
		await get_tree().process_frame
		RenderingServer.force_draw(false, 0.0)
	_clear_subject()
	await get_tree().process_frame
	print("CARTOON_VIPER_WALK_CAPTURE_PASS")
	get_tree().quit()
