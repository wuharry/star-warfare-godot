extends Node3D
## Real gameplay loader, original skeleton and real reload evaluator.
## A failed neck contract still captures BEFORE evidence; it never becomes PASS
## merely because all equipment IDs load or the images have been written.

const Contract = preload("res://tools/armor_runtime_v1/neck_contract.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const LOW_COLLARS := [0, 1, 4, 5, 10, 11, 21, 28]
const CAPTURE_SIZE := Vector2i(720, 720)
const HEAD_ID := 5

var output := "res://docs/art/titan_neck_mix_v1/review/after/"
var label := "after"
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var poses: Array[Dictionary] = []
var mixes: Array[Dictionary] = []
var negatives: Array[Dictionary] = []
var shared_gate_checks: Array[Dictionary] = []
var resource_hashes: Dictionary = {}
var viewport: SubViewport
var fixture: Fixture
var source: Node3D
var original_head: MeshInstance3D
var source_component: Dictionary = {}
var state_snapshot: Dictionary = {}
var real_save := ""
var save_hash := ""
var input_mode: int
var head_report: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _wants_images() -> bool:
	return true

func _run_negative_checks(_head: MeshInstance3D) -> void:
	pass

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=").trim_suffix("/") + "/"
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	if not output.begins_with("res://") or not label.is_valid_filename():
		push_error("Neck review requires --out=res://... and a valid --label")
		get_tree().quit(2)
		return
	if FileAccess.file_exists(output + "capture.json"):
		push_error("Immutable neck evidence already exists; choose a new --out directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	state_snapshot = Contract.snapshot_state(GameState)
	real_save = GameState.save_path
	save_hash = _hash(real_save)
	input_mode = Input.mouse_mode
	GameState.save_path = "user://titan_neck_mix_%s_profile.json" % label
	viewport = SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _wants_images() else SubViewport.UPDATE_DISABLED
	add_child(viewport)
	fixture = Fixture.new()
	viewport.add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://titan_neck_mix_%s_profile.json" % label
	fixture.label.hide()
	fixture.player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	source = (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate() as Node3D
	original_head = source.find_child("ArmorHead_05", true, false) as MeshInstance3D
	source_component = Contract.identify(original_head)
	for message: String in source_component.errors: _fail(message)
	_pin("res://assets/models/player/animated/player.gltf")
	_pin("res://assets/models/player/animated/player.bin")
	_pin(Visuals.reworked_scene_path(HEAD_ID))
	if source_component.errors.is_empty():
		_equip(0)
		var head: MeshInstance3D = fixture.player.recovered_avatar.find_child("ArmorHead_05", true, false)
		head_report = Contract.verify(original_head, head)
		for message: String in head_report.errors: _fail(message)
		_run_negative_checks(head)
		for body_id: int in range(Catalog.SET_NAMES.size()):
			_equip(body_id)
			var body: MeshInstance3D = fixture.player.recovered_avatar.find_child("ArmorBody_%02d" % body_id, true, false)
			var body_path: String = Visuals.reworked_scene_path(body_id)
			if not ResourceLoader.exists(body_path): body_path = Catalog.gameplay_scene_path(body_id)
			_pin(body_path)
			var visible_names: Array[String] = _visible_names()
			var expected: Array[String] = ["ArmorHead_05", "ArmorBody_%02d" % body_id, "ArmorHand_00", "ArmorFoot_00"]
			_check(visible_names.size() == 4, "MIX_VISIBLE: body %d has duplicate/missing visible pieces" % body_id)
			for name_key: String in expected: _check(name_key in visible_names, "MIX_VISIBLE: missing " + name_key)
			_check(body != null and body.visible and body.mesh != null and body.skin != null, "MIX_BODY: cannot load body %d" % body_id)
			mixes.append({"body_id": body_id, "body_name": Catalog.SET_NAMES[body_id], "body_scene": body_path,
				"head_scene": Visuals.reworked_scene_path(HEAD_ID), "visible_parts": visible_names,
				"body_loaded": body != null and body.mesh != null, "pose_samples": 9})
			for clip: String in ["idle_rifle", "run_rifle"]:
				for time: float in [0.0, 0.30, 0.65]:
					_pose(clip, time)
					_check_pose(body_id, clip, time)
			fixture.begin("gun00", 0)
			for fraction: float in [0.15, 0.50, 0.85]:
				fixture.advance_to(fixture.duration * fraction)
				_check_pose(body_id, "reload", fraction)
			if _wants_images() and body_id in LOW_COLLARS:
				_pose("rest", 0)
				for view: String in ["front", "quarter", "side", "rear"]:
					_camera(view)
					await _capture(body_id, "rest", view)
		if _wants_images():
			_equip(0)
			_camera("quarter")
			for clip: String in ["idle_rifle", "run_rifle", "reload"]:
				_pose(clip, 0.50 if clip == "reload" else 0.30)
				await _capture(0, clip, "quarter")
	await _finish()

func _equip(body_id: int) -> void:
	GameState.equipped_armor = {"head": "armor_head_05", "body": "armor_body_%02d" % body_id,
		"arms": "armor_arms_00", "legs": "armor_legs_00", "bag": "armor_bag_00"}
	fixture.player._apply_recovered_armor_visibility()
	fixture.player.recovered_animation_tree.active = false
	if _wants_images():
		for mesh: MeshInstance3D in fixture.player.recovered_avatar.find_children("*", "MeshInstance3D", true, false):
			if not str(mesh.name).begins_with("Armor"): mesh.hide()
		if is_instance_valid(fixture.player.backpack_socket): fixture.player.backpack_socket.hide()

func _pose(clip: String, time: float) -> void:
	fixture.player._cancel_reload()
	fixture.player.recovered_animation_tree.active = false
	fixture.player.recovered_animation_player.stop()
	fixture.player.recovered_skeleton.clear_bones_global_pose_override()
	fixture.player.recovered_skeleton.reset_bone_poses()
	if clip == "reload":
		fixture.begin("gun00", 0)
		fixture.advance_to(fixture.duration * time)
	elif clip != "rest":
		fixture.player._play_recovered_animation(clip, 0, true)
		fixture.player.recovered_animation_player.seek(time, true)
	fixture.player.recovered_skeleton.force_update_all_bone_transforms()

func _check_pose(body_id: int, clip: String, time: float) -> void:
	var head: MeshInstance3D = fixture.player.recovered_avatar.find_child("ArmorHead_05", true, false)
	var skeleton: Skeleton3D = fixture.player.recovered_skeleton
	var expected: PackedVector3Array = Contract.posed_vertices(original_head, skeleton, source_component.vertex_ids)
	var actual: PackedVector3Array = Contract.posed_vertices(head, skeleton, source_component.vertex_ids)
	var maximum := 0.0
	for index: int in expected.size():
		_check(actual[index].is_finite(), "MIX_POSE: non-finite neck vertex")
		maximum = maxf(maximum, actual[index].distance_to(expected[index]))
	_check(maximum <= Contract.POSITION_EPSILON, "MIX_POSE: original neck tube moved in body %d/%s/%.2f" % [body_id, clip, time])
	poses.append({"body_id": body_id, "clip": clip, "time": time,
		"original_neck_maximum_error_m": maximum, "neck_vertex_samples": actual.size()})

func _camera(view: String) -> void:
	var directions := {"front": Vector3(0, 0, -1), "quarter": Vector3(0.8, 0.12, -1),
		"side": Vector3(1, 0.08, 0), "rear": Vector3(0, 0.08, 1)}
	var center := Vector3(0, 1.47, 0.015)
	var camera: Camera3D = fixture.view_camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 1.35
	camera.global_position = center + (directions[view] as Vector3).normalized() * 5
	camera.look_at(center)
	fixture.fill.global_position = camera.global_position

func _capture(body_id: int, pose: String, view: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image: Image = viewport.get_texture().get_image()
	var file_name := "%s_body_%02d_%s_%s.png" % [label, body_id, pose, view]
	var path: String = output + file_name
	if image == null or image.is_empty() or image.save_png(path) != OK:
		_fail("CAPTURE: cannot save " + file_name)
		return
	frames.append({"file": file_name, "sha256": _hash(path), "body_id": body_id,
		"pose": pose, "view": view, "width": image.get_width(), "height": image.get_height()})
	_check(_hash(real_save) == save_hash, "SAVE: real profile changed while capturing " + file_name)

func _visible_names() -> Array[String]:
	var result: Array[String] = []
	for mesh: MeshInstance3D in fixture.player.recovered_avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if mesh.visible: result.append(str(mesh.name))
	result.sort()
	return result

func _pin(path: String) -> void:
	if path.is_empty(): return
	resource_hashes[path] = _hash(path)

func _check(ok: bool, message: String) -> void:
	if not ok: _fail(message)

func _fail(message: String) -> void:
	if message not in failures: failures.append(message)

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"

func _finish() -> void:
	if mixes.size() != 29 or poses.size() != 261: _fail("MIX_MATRIX: expected 29 bodies and 261 actual pose samples")
	if _wants_images() and frames.size() != 35: _fail("CAPTURE: expected 35 actual neck close-ups")
	for path: String in resource_hashes:
		_check(_hash(path) == resource_hashes[path], "RESOURCE: source/runtime changed during review " + path)
	_check(_hash(real_save) == save_hash, "SAVE: real profile changed")
	var isolated_path: String = GameState.save_path
	if source != null: source.free()
	if fixture != null:
		fixture.cleanup()
		fixture.free()
	await get_tree().process_frame
	Contract.restore_state(GameState, state_snapshot)
	Input.mouse_mode = input_mode
	_check(GameState.save_path == real_save and _hash(real_save) == save_hash, "SAVE: real profile state not restored")
	_check(Contract.snapshot_state(GameState) == state_snapshot, "STATE: GameState script properties not restored")
	var report := {"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures,
		"label": label, "neck_contract": head_report, "mixes": mixes, "poses": poses,
		"negative_fixtures": negatives, "shared_gate_checks": shared_gate_checks,
		"frames": frames, "resource_sha256": resource_hashes,
		"renderer": RenderingServer.get_current_rendering_method(), "engine_arguments": OS.get_cmdline_args(),
		"real_save_path": real_save, "real_save_sha256_at_start": save_hash, "real_save_sha256_at_end": _hash(real_save),
		"isolated_save_path": isolated_path, "save_unchanged": _hash(real_save) == save_hash,
		"gamestate_restored": Contract.snapshot_state(GameState) == state_snapshot,
		"scope": "Actual gameplay-loader Titan head with every 0-28 body, original-neck invariants at nine idle/run/reload poses. 35 normal-resource close-ups require visual inspection; finite vertices and exact interfaces alone do not prove artistic neck coverage."}
	var file := FileAccess.open(output + "capture.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write neck review report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("ARMOR_NECK_MIX_%s bodies=%d poses=%d images=%d negative_fixtures=%d save_unchanged=%s" % [
		"PASS" if failures.is_empty() else "FAIL", mixes.size(), poses.size(), frames.size(), negatives.size(), str(_hash(real_save) == save_hash)])
	for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
