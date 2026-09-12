extends Node3D

const OUTPUT := "res://test_output/rocket_reload"
const FPS := 30
const VIEWS := {
	"front": Vector3(-2.7, 1.8, -3.0),
	"right_front": Vector3(2.7, 1.8, -3.0),
	"side": Vector3(-3.3, 1.7, 0.0),
	"rear": Vector3(2.6, 1.9, 2.8),
}
const STAGES := {"start": 0.0, "raise": 0.22, "take": 0.32, "carry": 0.48, "align": 0.65, "insert": 0.79, "seated": 0.83, "return": 0.94, "end": 1.0}

var player: WarfarePlayer
var view_camera: Camera3D
var fill: OmniLight3D
var caption: Label
var elapsed := 0.0
var moving := false
var capturing := false
var playback_speed := 1.0
var restart_wait := 0.0

func _ready() -> void:
	capturing = "--capture" in OS.get_cmdline_user_args()
	moving = "--moving" in OS.get_cmdline_user_args()
	GameState.save_path = "user://rocket_reload_preview.json"
	GameState.equipped_armor = GameState._default_armor_equipment()
	GameState.selected_weapon = "gun11"
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.background_color = Color(0.045, 0.055, 0.07)
	world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.environment.ambient_light_color = Color.WHITE
	world_environment.environment.ambient_light_energy = 0.9
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.5
	add_child(light)
	fill = OmniLight3D.new()
	fill.light_energy = 2.0
	fill.omni_range = 7.0
	add_child(fill)
	player = WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	player.recovered_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.recovered_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	view_camera = Camera3D.new()
	view_camera.fov = 42
	add_child(view_camera)
	view_camera.current = true
	_set_view("front")
	var overlay := CanvasLayer.new()
	add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(24, 18)
	caption.add_theme_font_size_override("font_size", 22)
	overlay.add_child(caption)
	if not capturing:
		_build_controls(overlay)
	await get_tree().process_frame
	_restart(0)
	if capturing:
		set_process(false)
		await _capture()

func _build_controls(overlay: CanvasLayer) -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(24, 60)
	row.add_theme_constant_override("separation", 10)
	overlay.add_child(row)
	for variant in range(2):
		var button := Button.new()
		button.text = "A / 胸前側收" if variant == 0 else "B / 立筒裝填"
		button.pressed.connect(_restart.bind(variant))
		row.add_child(button)
	for view: String in VIEWS:
		var button := Button.new()
		button.text = view
		button.pressed.connect(_set_view.bind(view))
		row.add_child(button)
	var slow := Button.new()
	slow.text = "1x / 0.25x"
	slow.pressed.connect(func(): playback_speed = 0.25 if playback_speed == 1.0 else 1.0)
	row.add_child(slow)

func _restart(variant: int) -> void:
	player._cancel_reload()
	player.rocket_reload_variant = variant
	player.recovered_animation_tree.active = false
	player._play_recovered_animation("idle_bazinga", 0.0, true)
	player.recovered_animation_player.advance(0.0)
	player.recovered_skeleton.clear_bones_global_pose_override()
	player.recovered_skeleton.force_update_all_bone_transforms()
	player.gun_socket.transform = player.recovered_skeleton.get_bone_global_pose(player.recovered_skeleton.find_bone(player.gun_socket.bone_name))
	player._set_magazine_rounds(0)
	player._start_reload()
	elapsed = 0.0
	restart_wait = 0.0
	_advance(0.0)

func _advance(delta: float) -> void:
	player._update_reload(delta)
	player._update_body_facing(delta, Vector3.ZERO)
	player._update_combat_aim_pose(delta)
	player._update_recovered_animation(1.0 if moving else 0.0, Vector2(0, -1) if moving else Vector2.ZERO)
	if player.recovered_animation_tree.active:
		player.recovered_animation_tree.advance(delta)
	else:
		player.recovered_animation_player.advance(delta)
	player.recovered_skeleton.force_update_all_bone_transforms()
	player._update_reload_pose()
	elapsed += delta
	caption.text = "RPG-21 / %s / %.2f s / %s" % ["A - 胸前側收" if player.active_rocket_reload_variant == 0 else "B - 立筒裝填", elapsed, "移動" if moving else "站立"]

func _process(delta: float) -> void:
	if not is_instance_valid(player) or capturing or player.reload_total <= 0:
		return
	if player.reload_left > 0.0:
		_advance(minf(delta * playback_speed, player.reload_left))
	else:
		restart_wait += delta
		if restart_wait > 0.7:
			_restart(player.rocket_reload_variant)

func _set_view(view: String) -> void:
	view_camera.position = VIEWS[view]
	view_camera.look_at(Vector3(0, 1.12, -0.06), Vector3.UP)
	fill.position = view_camera.position

func _capture() -> void:
	var directory := OUTPUT + ("/moving" if moving else "/stationary")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("Rocket capture directory: " + error_string(error))
		get_tree().quit(1)
		return
	var manifest := {"weapon": "gun11", "fps": FPS, "moving": moving, "renderer": RenderingServer.get_current_rendering_method(), "viewport": [get_viewport().size.x, get_viewport().size.y], "captures": []}
	for variant in range(2):
		_restart(variant)
		var duration := player.reload_total
		manifest["duration"] = duration
		var samples: Array[Dictionary] = []
		for key: String in STAGES:
			samples.append({"time": duration * float(STAGES[key]), "name": key})
		if "--sequence" in OS.get_cmdline_user_args():
			for frame in range(ceili(duration * FPS) + 1):
				samples.append({"time": minf(float(frame) / FPS, duration), "name": "%03d" % frame, "frame": frame})
		samples.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.time) < float(b.time))
		for sample: Dictionary in samples:
			while elapsed < float(sample.time) - 0.000001:
				_advance(minf(1.0 / 60.0, float(sample.time) - elapsed))
			if float(sample.time) >= duration and player.reload_left > 0:
				_advance(player.reload_left)
			for view: String in VIEWS:
				_set_view(view)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var filename := "%s_%s_%s.png" % ["a" if variant == 0 else "b", view, sample.name]
				error = get_viewport().get_texture().get_image().save_png(directory + "/" + filename)
				if error != OK:
					push_error("Rocket image save failed: " + filename)
					get_tree().quit(1)
					return
				var record := {"variant": variant, "view": view, "time": sample.time, "path": filename}
				if sample.has("frame"):
					record["frame"] = sample.frame
				manifest.captures.append(record)
		print("ROCKET_CAPTURE_VARIANT_COMPLETE ", variant)
	var file := FileAccess.open(directory + "/manifest.json", FileAccess.WRITE)
	if file == null:
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	player._cancel_reload()
	player.queue_free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	print("ROCKET_RELOAD_CAPTURE_PASS ", directory)
	get_tree().quit(0)
