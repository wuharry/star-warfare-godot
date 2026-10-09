extends Node3D
## Geometry-only render diagnostics. Red means ORIGINAL neck-interface faces;
## black means opaque equipped geometry. Native artwork is never edited.

const Contract = preload("res://tools/armor_runtime_v1/neck_contract.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const SCHEMA := "armor_neck_exposure_v1"
const SIZE := Vector2i(384, 384)
const NORMAL_SIZE := Vector2i(720, 720)
const VIEWS := ["front", "quarter", "side", "rear"]
const POSES := ["idle", "run", "reload"]
const BODIES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
	15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28]
const REFERENCE_IDS := [0, 1, 2, 3, 4]
const CANDIDATE_ID := 5
const PIXEL_MARGIN := 2.0
const DIAGNOSTIC_LAYER := 1 << 19
const OPAQUE_SHADER_AUDIT := {
	"res://assets/equipment_refined/painted_equipment.gdshader": {
		"sha256": "c6a6500f4e22d91f0837c0be2437c6a8d7c950511cddf0f95a42d6cbeb27ebc5", "cull": BaseMaterial3D.CULL_DISABLED},
	"res://assets/armors/thunder/painted_armor.gdshader": {
		"sha256": "d06e63dbd06da0a3731968f6e655b348e7e1e4853d1544883e0d443ffc3c0bc6", "cull": BaseMaterial3D.CULL_BACK},
	"res://assets/armors/thunder/hard_surface.gdshader": {
		"sha256": "c350d4479c31205743a17b2e5d2fe4c0e629e4f5307786c6f52ae82042093ddc", "cull": BaseMaterial3D.CULL_BACK},
}

var output := "res://docs/art/titan_neck_exposure_v1/review/calibration/"
var label := "calibration"
var mode := "calibrate"
var baseline_path := ""
var plan_only := false
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var regressions: Array[Dictionary] = []
var resources: Dictionary = {}
var reference_resources: Dictionary = {}
var thresholds: Dictionary = {}
var baseline: Dictionary = {}
var style_failures: Array[String] = []
var state: Dictionary = {}
var real_save := ""
var real_save_hash := ""
var input_mode: int
var viewport: SubViewport
var fixture: Fixture
var source: Node3D
var runtime_heads: Dictionary = {}
var diagnostic: Array[MeshInstance3D] = []
var hidden: Array[MeshInstance3D] = []
var current_head: MeshInstance3D
var current_descriptor: Array[Dictionary] = []
var reference_rows: Array[Dictionary] = []
var candidate_rows: Array[Dictionary] = []
var material_policies: Dictionary = {}
var alpha_textures: Dictionary = {}
var current_camera_size := 1.35
var current_camera_center := Vector3(0, 1.47, 0.015)
var diagnostic_build: Dictionary = {}
var diagnostic_camera_mask := -1

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=").trim_suffix("/") + "/"
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		if argument.begins_with("--baseline="): baseline_path = argument.trim_prefix("--baseline=")
		if argument == "--plan-only": plan_only = true
	if not output.begins_with("res://") or not label.is_valid_filename() or mode not in ["calibrate", "verify"]:
		push_error("Use --out=res://NEW_DIRECTORY --label=NAME --mode=calibrate|verify [--baseline=res://capture.json] [--plan-only]")
		get_tree().quit(2)
		return
	if FileAccess.file_exists(output + "capture.json") or FileAccess.file_exists(output + "plan.json"):
		push_error("Exposure evidence is immutable; choose a fresh --out directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if plan_only:
		_write(output + "plan.json", _plan())
		print("ARMOR_NECK_EXPOSURE_PLAN_ONLY no measurements or visual acceptance claimed")
		get_tree().quit()
		return
	if mode == "verify":
		if not FileAccess.file_exists(baseline_path):
			push_error("Verification requires a frozen calibration --baseline=res://.../capture.json")
			get_tree().quit(2)
			return
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
		var baseline_errors: Array[String] = baseline_validation_errors(decoded)
		if not baseline_errors.is_empty():
			for message: String in baseline_errors: push_error(message)
			get_tree().quit(2)
			return
		baseline = decoded
		# JSON stores numbers as floats. Only exact integral numeric IDs were
		# accepted above; normalize the in-memory list without editing evidence.
		baseline.reference_ids = REFERENCE_IDS.duplicate()
		thresholds = baseline.get("thresholds", {}).duplicate(true)
	state = Contract.snapshot_state(GameState)
	real_save = GameState.save_path
	real_save_hash = _hash(real_save)
	input_mode = Input.mouse_mode
	GameState.save_path = "user://neck_exposure_%s_profile.json" % label
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	fixture = Fixture.new()
	viewport.add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://neck_exposure_%s_profile.json" % label
	fixture.label.hide()
	fixture.player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for world: WorldEnvironment in fixture.find_children("*", "WorldEnvironment", true, false):
		world.environment.background_color = Color.BLACK
		world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	source = (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate() as Node3D
	_pin("res://assets/models/player/animated/player.gltf", true)
	_pin("res://assets/models/player/animated/player.bin", true)
	_pin("res://tools/armor_runtime_v1/neck_exposure_capture.gd")
	_pin(get_script().resource_path)
	# Every original helmet is measured on the SAME current low-collar body.
	for head_id: int in range(21):
		await _series("legacy", head_id)
	for head_id: int in range(6):
		if ResourceLoader.exists(Visuals.reworked_scene_path(head_id)):
			await _series("current", head_id)
		else:
			failures.append("EXPOSURE_RESOURCE: requested current head %d is missing" % head_id)
	if mode == "calibrate": _calibrate()
	else:
		for path: String in baseline.get("reference_resource_sha256", {}):
			_check(_hash(path) == baseline.reference_resource_sha256[path], "EXPOSURE_BASELINE: reference changed since calibration " + path)
	for body_id: int in BODIES:
		_equip("current", CANDIDATE_ID, body_id)
		for pose: String in POSES:
			_pose(pose)
			for view: String in VIEWS:
				_camera(view)
				var row: Dictionary = await _measure("candidate", CANDIDATE_ID, body_id, pose, view)
				candidate_rows.append(row)
				_accept(row)
	# Normal native resources, actual gameplay loader and actual idle skeleton.
	# These are fixture camera reproductions, not screenshots of the room UI.
	_equip("current", CANDIDATE_ID, 0)
	_pose("idle")
	_camera("quarter")
	await _normal_capture("gameplay_loader_quarter_idle")
	_camera("front")
	await _normal_capture("room_preview_front_idle_reproduction")
	await _regression_checks()
	await _finish()

func _plan() -> Dictionary:
	return {"schema": SCHEMA, "label": label, "mode": mode, "status": "NOT_RUN",
		"measurement": "depth-tested original neck red pixels / standalone complete actual head red projected pixels (includes neck)",
		"camera": {"projection": "orthographic", "size": 1.35, "center": [0, 1.47, 0.015], "diagnostic_viewport": [384, 384], "normal_viewport": [720, 720], "views": VIEWS},
		"legacy_calibration_heads": range(21), "current_comparison_heads": range(6),
		"comparison_body": 0, "comparison_pose": "idle", "reference_ids": REFERENCE_IDS,
		"candidate_head": CANDIDATE_ID, "candidate_bodies": BODIES, "candidate_poses": POSES,
		"candidate_sample_count": BODIES.size() * POSES.size() * VIEWS.size(),
		"threshold_policy": "For each view, maximum measured CURRENT approved heads 0..4 on body0 idle plus TWO pixels divided by that reference head area. Candidate Titan is excluded; verification reads frozen thresholds without recalibration.",
		"normal_images": ["gameplay_loader_quarter_idle", "room_preview_front_idle_reproduction"],
		"occluder_policy": "Only the four selected armor pieces. Weapons, backpack and reload debris are hidden after EVERY pose; diagnostic camera sees only temporary armor partitions on a dedicated render layer. Normal camera reproductions also hide weapons/backpack.",
		"legacy_display_camera_exceptions": {"14": {"size": 2.25, "center": [0, 1.70, 0.015]}, "20": {"size": 2.25, "center": [0, 1.70, 0.015]}},
		"scope": "Diagnostic render changes only temporary materials/face partitions. Native PNG/SCN/GLB remain untouched. Camera reproductions use the actual player loader, not the actual room scene/UI."}

static func _exact_numeric_id(value: Variant, expected: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == float(expected)

static func baseline_validation_errors(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary: return ["EXPOSURE_BASELINE: calibration root must be a Dictionary"]
	var document: Dictionary = value
	if document.get("schema", "") != SCHEMA or document.get("measurement_integrity", "") != "PASS":
		errors.append("EXPOSURE_BASELINE: invalid schema or measurement integrity")
	var ids: Variant = document.get("reference_ids")
	if not ids is Array or ids.size() != REFERENCE_IDS.size():
		errors.append("EXPOSURE_BASELINE: exactly five approved numeric reference IDs required")
	else:
		for index: int in REFERENCE_IDS.size():
			if not _exact_numeric_id(ids[index], REFERENCE_IDS[index]): errors.append("EXPOSURE_BASELINE: reference IDs must be exactly ordered integer values 0..4")
	var rows: Variant = document.get("reference_measurements")
	var pins: Variant = document.get("reference_resource_sha256")
	var limits: Variant = document.get("thresholds")
	if not rows is Array or rows.size() != REFERENCE_IDS.size() * VIEWS.size(): errors.append("EXPOSURE_BASELINE: all 20 approved reference renders required")
	if not pins is Dictionary: errors.append("EXPOSURE_BASELINE: original/peer SHA256 dictionary required")
	if not limits is Dictionary or limits.size() != VIEWS.size(): errors.append("EXPOSURE_BASELINE: four measured view thresholds required")
	if not errors.is_empty(): return errors
	var expected_resources: Array[String] = ["res://assets/models/player/animated/player.gltf", "res://assets/models/player/animated/player.bin"]
	for head_id: int in REFERENCE_IDS: expected_resources.append(Visuals.reworked_scene_path(head_id))
	for path: String in expected_resources:
		var checksum: Variant = pins.get(path)
		if not checksum is String or checksum.length() != 64 or not checksum.is_valid_hex_number(): errors.append("EXPOSURE_BASELINE: missing valid required resource SHA256 " + path)
	if pins.has(Visuals.reworked_scene_path(CANDIDATE_ID)): errors.append("EXPOSURE_BASELINE: candidate cannot be a calibration resource")
	for item: Variant in rows:
		if not item is Dictionary:
			errors.append("EXPOSURE_BASELINE: every reference render must be a Dictionary")
			continue
		var row: Dictionary = item
		var pixels: Variant = row.get("complete_head_pixels")
		var visible: Variant = row.get("visible_neck_pixels")
		var fraction: Variant = row.get("visible_neck_fraction")
		if typeof(pixels) not in [TYPE_INT, TYPE_FLOAT] or typeof(visible) not in [TYPE_INT, TYPE_FLOAT] or typeof(fraction) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("EXPOSURE_BASELINE: reference pixel counts/fraction must be numeric")
			continue
		if not is_finite(float(pixels)) or not is_finite(float(visible)) or not is_finite(float(fraction)) or float(pixels) <= 100 or float(visible) < 0 or float(visible) > float(pixels) or floorf(float(pixels)) != float(pixels) or floorf(float(visible)) != float(visible):
			errors.append("EXPOSURE_BASELINE: malformed actual reference pixel counts/fraction")
			continue
		if absf(float(fraction) - float(visible) / float(pixels)) > 0.000000000001 or row.get("complete_head_unclipped", false) != true or row.get("same_camera_as_approved_peers", false) != true:
			errors.append("EXPOSURE_BASELINE: reference must use unclipped actual pixel ratio and approved camera")
	if not errors.is_empty(): return errors
	for view: String in VIEWS:
		var measured_maximum := -1.0
		for head_id: int in REFERENCE_IDS:
			var matches := 0
			for row: Dictionary in rows:
				if _exact_numeric_id(row.get("head_id"), head_id) and row.get("view", "") == view and row.get("version", "") == "current" and _exact_numeric_id(row.get("body_id"), 0) and row.get("pose", "") == "idle":
					matches += 1
					measured_maximum = maxf(measured_maximum, float(row.visible_neck_fraction) + PIXEL_MARGIN / float(row.complete_head_pixels))
			if matches != 1: errors.append("EXPOSURE_BASELINE: each approved head/body0/idle/view must appear exactly once")
		var specification: Variant = limits.get(view)
		if not specification is Dictionary:
			errors.append("EXPOSURE_BASELINE: each view threshold must be a Dictionary")
			continue
		var limit: Variant = specification.get("maximum_fraction")
		if typeof(limit) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(limit)) or float(limit) < 0 or float(limit) >= 1:
			errors.append("EXPOSURE_BASELINE: view threshold must be finite numeric fraction in [0,1)")
			continue
		# Validate the saved peer-only formula, NEVER derive from a candidate.
		if absf(float(limit) - measured_maximum) > 0.000000000001 or not _exact_numeric_id(specification.get("pixel_margin"), int(PIXEL_MARGIN)) or not _exact_numeric_id(specification.get("reference_count"), REFERENCE_IDS.size()):
			errors.append("EXPOSURE_BASELINE: saved threshold differs from frozen max(peers0..4)+2pixels policy")
	return errors

func _series(version: String, head_id: int) -> void:
	_equip(version, head_id, 0)
	_pose("idle")
	for view: String in VIEWS:
		_camera(view)
		var row: Dictionary = await _measure(version, head_id, 0, "idle", view)
		if version == "current" and head_id in REFERENCE_IDS: reference_rows.append(row)

func _equip(version: String, head_id: int, body_id: int) -> void:
	_restore_diagnostic()
	current_camera_size = 2.25 if version == "legacy" and head_id in [14, 20] else 1.35
	current_camera_center = Vector3(0, 1.70, 0.015) if version == "legacy" and head_id in [14, 20] else Vector3(0, 1.47, 0.015)
	# Restore every earlier source substitution before the real loader runs.
	for id: int in runtime_heads:
		var part: MeshInstance3D = fixture.player.recovered_avatar.find_child("ArmorHead_%02d" % id, true, false)
		if part != null:
			part.mesh = runtime_heads[id].mesh
			part.skin = runtime_heads[id].skin
			part.transform = runtime_heads[id].transform
			for surface: int in part.get_surface_override_material_count(): part.set_surface_override_material(surface, null)
	GameState.equipped_armor = {"head": "armor_head_%02d" % head_id, "body": "armor_body_%02d" % body_id,
		"arms": "armor_arms_00", "legs": "armor_legs_00", "bag": "armor_bag_00"}
	fixture.player._apply_recovered_armor_visibility()
	fixture.player.recovered_animation_tree.active = false
	current_head = fixture.player.recovered_avatar.find_child("ArmorHead_%02d" % head_id, true, false)
	if not runtime_heads.has(head_id):
		runtime_heads[head_id] = {"mesh": current_head.mesh, "skin": current_head.skin, "transform": current_head.transform}
	var original: MeshInstance3D = source.find_child("ArmorHead_%02d" % head_id, true, false)
	current_descriptor.clear()
	for surface: int in original.mesh.get_surface_count():
		var component: Dictionary = Contract.identify(original, surface)
		if int(component.get("candidate_count", -1)) == 0: continue
		for message: String in component.errors: _check(false, message)
		if component.errors.is_empty():
			var source_arrays: Array = original.mesh.surface_get_arrays(surface)
			var source_indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
			var face_keys: Dictionary = {}
			for triangle: int in component.triangle_ids:
				var offset: int = triangle * 3
				face_keys[_face_key(source_indices[offset], source_indices[offset + 1], source_indices[offset + 2])] = true
			component.original_face_keys = face_keys
			current_descriptor.append(component)
	_check(not current_descriptor.is_empty(), "EXPOSURE_SOURCE: no original neck faces for head %d" % head_id)
	if version == "legacy":
		current_head.mesh = original.mesh
		current_head.skin = original.skin
		current_head.transform = original.transform
		for surface: int in current_head.get_surface_override_material_count(): current_head.set_surface_override_material(surface, null)
	_hide_non_armor()
	_pin(Visuals.reworked_scene_path(body_id), body_id == 0)
	if version == "current": _pin(Visuals.reworked_scene_path(head_id), head_id in REFERENCE_IDS)

func _pose(pose: String) -> void:
	fixture.player._cancel_reload()
	fixture.player.recovered_animation_tree.active = false
	fixture.player.recovered_animation_player.stop()
	fixture.player.recovered_skeleton.clear_bones_global_pose_override()
	fixture.player.recovered_skeleton.reset_bone_poses()
	if pose == "reload":
		fixture.begin("gun00", 0)
		fixture.advance_to(fixture.duration * 0.50)
	else:
		fixture.player._play_recovered_animation("idle_rifle" if pose == "idle" else "run_rifle", 0, true)
		fixture.player.recovered_animation_player.seek(0.30, true)
	fixture.player.recovered_skeleton.force_update_all_bone_transforms()
	# Reload can recreate/show gun meshes after _equip. Apply the same armor-only
	# policy AFTER animation/reload evaluation for idle, run and reload alike.
	_hide_non_armor()
	var visible_parts: Array[String] = []
	for mesh: MeshInstance3D in fixture.player.recovered_avatar.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree(): visible_parts.append(str(mesh.name))
	var body_id: int = int(str(GameState.equipped_armor.body).get_slice("_", 2))
	var expected: Array[String] = [str(current_head.name), "ArmorBody_%02d" % body_id, "ArmorHand_00", "ArmorFoot_00"]
	_check(visible_parts.size() == 4, "EXPOSURE_PARTS: every pose must contain exactly four visible armor pieces")
	for part: String in expected: _check(part in visible_parts, "EXPOSURE_PARTS: missing selected part " + part)

func _hide_non_armor() -> void:
	for mesh: MeshInstance3D in fixture.player.recovered_avatar.find_children("*", "MeshInstance3D", true, false):
		if not str(mesh.name).begins_with("Armor"): mesh.hide()
	if is_instance_valid(fixture.player.backpack_socket): fixture.player.backpack_socket.hide()
	for debris: Node in get_tree().get_nodes_in_group("reload_debris"):
		if debris is Node3D: (debris as Node3D).hide()

func _camera(view: String) -> void:
	var directions := {"front": Vector3(0, 0, -1), "quarter": Vector3(0.8, 0.12, -1),
		"side": Vector3(1, 0.08, 0), "rear": Vector3(0, 0.08, 1)}
	var center: Vector3 = current_camera_center
	var camera: Camera3D = fixture.view_camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = current_camera_size
	camera.global_position = center + (directions[view] as Vector3).normalized() * 5
	camera.look_at(center)
	fixture.fill.global_position = camera.global_position

func _measure(version: String, head_id: int, body_id: int, pose: String, view: String) -> Dictionary:
	var key := "%s_head_%02d_body_%02d_%s_%s" % [version, head_id, body_id, pose, view]
	_build_diagnostic(false)
	var exposed_build: Dictionary = diagnostic_build.duplicate(true)
	_check(bool(exposed_build.get("completed", false)), "EXPOSURE_SURFACES: incomplete equipped geometry diagnostic " + key)
	var exposed: Image = await _image()
	var exposed_count: int = _red_pixels(exposed)
	_save_image(exposed, key + "_exposed.png", "depth_tested_red_neck")
	_restore_diagnostic()
	_build_diagnostic(true)
	var mask_build: Dictionary = diagnostic_build.duplicate(true)
	_check(bool(mask_build.get("completed", false)), "EXPOSURE_SURFACES: incomplete complete-head diagnostic " + key)
	var head_mask: Image = await _image()
	var head_count: int = _red_pixels(head_mask)
	var head_bounds: Rect2i = _red_bounds(head_mask)
	_save_image(head_mask, key + "_head_mask.png", "standalone_complete_head_including_neck")
	_restore_diagnostic()
	_check(head_count > 100, "EXPOSURE_MASK: empty/tiny full head projected mask " + key)
	_check(exposed_count <= head_count, "EXPOSURE_MASK: neck visible area exceeds complete head " + key)
	_check(head_bounds.position.x > 1 and head_bounds.position.y > 1 and head_bounds.end.x < SIZE.x - 1 and head_bounds.end.y < SIZE.y - 1,
		"EXPOSURE_MASK: complete head silhouette touches viewport border; denominator is clipped " + key)
	var ratio: float = float(exposed_count) / maxf(1, head_count)
	var row := {"version": version, "head_id": head_id, "head_name": Catalog.SET_NAMES[head_id],
		"body_id": body_id, "body_name": Catalog.SET_NAMES[body_id], "pose": pose, "view": view,
		"visible_neck_pixels": exposed_count, "complete_head_pixels": head_count,
		"visible_neck_fraction": ratio, "visible_neck_percent": ratio * 100,
		"camera_size": current_camera_size, "camera_center": [current_camera_center.x, current_camera_center.y, current_camera_center.z],
		"same_camera_as_approved_peers": current_camera_size == 1.35 and current_camera_center == Vector3(0, 1.47, 0.015),
		"complete_head_bounds_px": [head_bounds.position.x, head_bounds.position.y, head_bounds.size.x, head_bounds.size.y],
		"complete_head_unclipped": head_bounds.position.x > 1 and head_bounds.position.y > 1 and head_bounds.end.x < SIZE.x - 1 and head_bounds.end.y < SIZE.y - 1,
		"measurement_integrity": "PASS" if bool(exposed_build.get("completed", false)) and bool(mask_build.get("completed", false)) else "FAIL",
		"diagnostic_surface_coverage": {"equipped_geometry": exposed_build, "complete_head": mask_build},
		"neck_mesh_source": "source-connected-component ORIGINAL face indices with ACTUAL delivered positions/weights",
		"source_neck_components": current_descriptor.duplicate(true),
		"diagnostic_exposed": key + "_exposed.png", "diagnostic_head_mask": key + "_head_mask.png"}
	measurements.append(row)
	return row

func _build_diagnostic(head_only: bool) -> void:
	# This stays false if an unexpected script error aborts the function. The
	# caller must reject that row rather than approve an incomplete render.
	diagnostic_build = {"completed": false, "expected_surfaces": 0, "rendered_surfaces": 0, "surfaces": []}
	diagnostic_camera_mask = fixture.view_camera.cull_mask
	fixture.view_camera.cull_mask = DIAGNOSTIC_LAYER
	for actual: MeshInstance3D in fixture.player.recovered_avatar.find_children("*", "MeshInstance3D", true, false):
		if not actual.is_visible_in_tree() or actual.mesh == null: continue
		hidden.append(actual)
		actual.hide()
		if head_only and actual != current_head: continue
		for surface: int in actual.mesh.get_surface_count():
			diagnostic_build.expected_surfaces += 1
			var arrays: Array = actual.mesh.surface_get_arrays(surface).duplicate(true)
			var topology: Dictionary = diagnostic_triangle_indices(arrays, actual.mesh.surface_get_primitive_type(surface))
			for message: String in topology.errors: _check(false, message + " " + str(actual.name) + " surface%d" % surface)
			if not topology.errors.is_empty(): continue
			var indices: PackedInt32Array = topology.indices
			var neck := PackedInt32Array()
			var other := PackedInt32Array()
			var tube_faces: Dictionary = {}
			if actual == current_head:
				for descriptor: Dictionary in current_descriptor:
					if int(descriptor.surface) == surface: tube_faces = descriptor.original_face_keys
			for offset: int in range(0, indices.size(), 3):
				var is_neck: bool = tube_faces.has(_face_key(indices[offset], indices[offset + 1], indices[offset + 2]))
				# Packed arrays are value types: append to the selected buffer directly.
				if is_neck: neck.append_array(PackedInt32Array([indices[offset], indices[offset + 1], indices[offset + 2]]))
				else: other.append_array(PackedInt32Array([indices[offset], indices[offset + 1], indices[offset + 2]]))
			var original_material: Material = actual.get_active_material(surface)
			var rendered_indices := 0
			if head_only:
				rendered_indices = _add_partition(actual, arrays, indices, Color.RED, original_material)
			else:
				rendered_indices = _add_partition(actual, arrays, other, Color.BLACK, original_material)
				rendered_indices += _add_partition(actual, arrays, neck, Color.RED, original_material)
			var covered: bool = rendered_indices == indices.size()
			_check(covered, "EXPOSURE_SURFACES: omitted/failed source triangles " + str(actual.name) + " surface%d" % surface)
			if covered: diagnostic_build.rendered_surfaces += 1
			diagnostic_build.surfaces.append({"part": str(actual.name), "surface": surface, "indices_mode": topology.indices_mode,
				"source_triangle_indices": indices.size(), "rendered_triangle_indices": rendered_indices, "complete": covered})
	diagnostic_build.completed = diagnostic_build.expected_surfaces > 0 and diagnostic_build.expected_surfaces == diagnostic_build.rendered_surfaces

static func diagnostic_triangle_indices(arrays: Array, primitive: int) -> Dictionary:
	var errors: Array[String] = []
	var indices := PackedInt32Array()
	var index_mode := "source_indexed"
	if primitive != Mesh.PRIMITIVE_TRIANGLES: errors.append("EXPOSURE_TOPOLOGY: actual surface primitive is not TRIANGLES")
	if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		errors.append("EXPOSURE_TOPOLOGY: actual surface has no valid vertex buffer")
		return {"errors": errors, "indices": indices, "indices_mode": "invalid"}
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for point: Vector3 in positions:
		if not point.is_finite():
			errors.append("EXPOSURE_TOPOLOGY: actual position is non-finite")
			break
	var value: Variant = arrays[Mesh.ARRAY_INDEX]
	if value == null or (value is PackedInt32Array and value.is_empty()):
		index_mode = "explicit_sequence_for_actual_nonindexed_triangles"
		if positions.is_empty() or positions.size() % 3 != 0: errors.append("EXPOSURE_TOPOLOGY: nonindexed TRIANGLES vertex count must be a nonempty multiple of three")
		else:
			indices.resize(positions.size())
			for index: int in positions.size(): indices[index] = index
	elif value is PackedInt32Array: indices = value.duplicate()
	else: errors.append("EXPOSURE_TOPOLOGY: unsupported actual index channel type")
	if indices.is_empty() or indices.size() % 3 != 0: errors.append("EXPOSURE_TOPOLOGY: incomplete or empty triangle index buffer")
	for index: int in indices:
		if index < 0 or index >= positions.size():
			errors.append("EXPOSURE_TOPOLOGY: triangle index is outside actual vertex buffer")
			break
	return {"errors": errors, "indices": indices, "indices_mode": index_mode}

func _face_key(a: int, b: int, c: int) -> String:
	if a <= b and a <= c: return "%d/%d/%d" % [a, b, c]
	if b <= a and b <= c: return "%d/%d/%d" % [b, c, a]
	return "%d/%d/%d" % [c, a, b]

func _add_partition(actual: MeshInstance3D, arrays: Array, indices: PackedInt32Array, color: Color, original_material: Material) -> int:
	if indices.is_empty(): return 0
	var partition: Array = arrays.duplicate(true)
	partition[Mesh.ARRAY_INDEX] = indices
	var material: BaseMaterial3D = _diagnostic_material(original_material, color)
	if material == null: return 0
	# Alpha vertices must retain their actual coverage while RGB becomes a mask.
	if material.vertex_color_use_as_albedo and partition[Mesh.ARRAY_COLOR] != null:
		var colors: PackedColorArray = partition[Mesh.ARRAY_COLOR].duplicate()
		for index: int in colors.size(): colors[index] = Color(1, 1, 1, colors[index].a)
		partition[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, partition)
	if mesh.get_surface_count() != 1:
		_check(false, "EXPOSURE_SURFACES: diagnostic mesh upload failed")
		return 0
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.skin = actual.skin
	instance.skeleton = actual.skeleton
	instance.transform = actual.transform
	instance.extra_cull_margin = actual.extra_cull_margin
	instance.layers = DIAGNOSTIC_LAYER
	actual.get_parent().add_child(instance)
	diagnostic.append(instance)
	return indices.size()

func _diagnostic_material(original: Material, color: Color) -> BaseMaterial3D:
	var material: BaseMaterial3D
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		material = base.duplicate() as BaseMaterial3D
		material.albedo_color = Color(color.r, color.g, color.b, base.albedo_color.a)
		material.albedo_texture = null
		material.emission_enabled = false
		material.normal_enabled = false
		material.detail_enabled = false
		material.next_pass = null
		if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and base.albedo_texture != null:
			var cache_key: int = base.albedo_texture.get_instance_id()
			if not alpha_textures.has(cache_key):
				var pixels: Image = base.albedo_texture.get_image()
				if pixels == null or pixels.is_empty() or (pixels.is_compressed() and pixels.decompress() != OK):
					_check(false, "EXPOSURE_ALPHA: cannot decode actual alpha texture")
					return null
				for y: int in pixels.get_height():
					for x: int in pixels.get_width(): pixels.set_pixel(x, y, Color(1, 1, 1, pixels.get_pixel(x, y).a))
				alpha_textures[cache_key] = ImageTexture.create_from_image(pixels)
			material.albedo_texture = alpha_textures[cache_key]
		elif base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			material.vertex_color_use_as_albedo = false
		material_policies[original.resource_name] = {"type": "BaseMaterial3D", "transparency": base.transparency,
			"blend_mode": base.blend_mode, "depth_draw_mode": base.depth_draw_mode, "cull_mode": base.cull_mode,
			"policy": "Original alpha/blend/depth/cull retained; temporary alpha-only RGB mask for transparent texture"}
	elif original is ShaderMaterial and (original as ShaderMaterial).shader != null and OPAQUE_SHADER_AUDIT.has((original as ShaderMaterial).shader.resource_path):
		# The exact audited shader files have no alpha/discard, vertex displacement
		# or depth override. Each retains its own culling; never guess by path alone.
		var shader := (original as ShaderMaterial).shader
		var shader_path: String = shader.resource_path
		var audit: Dictionary = OPAQUE_SHADER_AUDIT[shader_path]
		var checksum: String = _hash(shader_path)
		if checksum != audit.sha256:
			_check(false, "EXPOSURE_SHADER: audited opaque shader code SHA256 changed; re-audit coverage " + shader_path)
			return null
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.cull_mode = int(audit.cull)
		_pin(shader_path, true)
		material_policies[original.resource_name] = {"type": "known_opaque_project_shader", "shader": shader_path,
			"sha256": checksum, "expected_audited_sha256": audit.sha256, "cull_mode": audit.cull,
			"policy": "Exact audited code SHA has no ALPHA/discard/vertex/depth override; original opaque depth and each shader's actual culling retained"}
	else:
		_check(false, "EXPOSURE_SHADER: unsupported actual material; cannot invent opaque coverage " + str(original))
		return null
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	return material

func _restore_diagnostic() -> void:
	for instance: MeshInstance3D in diagnostic: instance.free()
	diagnostic.clear()
	for actual: MeshInstance3D in hidden: actual.show()
	hidden.clear()
	if diagnostic_camera_mask >= 0 and fixture != null:
		fixture.view_camera.cull_mask = diagnostic_camera_mask
	diagnostic_camera_mask = -1

func _calibrate() -> void:
	for view: String in VIEWS:
		var maximum := -1.0
		var selected: Dictionary = {}
		var count := 0
		for row: Dictionary in reference_rows:
			if row.view != view: continue
			count += 1
			var limit: float = float(row.visible_neck_fraction) + PIXEL_MARGIN / maxf(1, row.complete_head_pixels)
			if limit > maximum:
				maximum = limit
				selected = row
		_check(count == REFERENCE_IDS.size(), "EXPOSURE_BASELINE: every approved reference must be measured in " + view)
		thresholds[view] = {"maximum_fraction": maximum, "maximum_percent": maximum * 100,
			"reference_count": count, "selected_reference_head": selected.get("head_id", -1), "pixel_margin": PIXEL_MARGIN}

func _accept(row: Dictionary) -> void:
	if row.get("measurement_integrity", "PASS") != "PASS":
		row.style_coverage = "NOT_EVALUATED"
		_check(false, "EXPOSURE_SURFACES: incomplete render cannot pass style coverage")
		return
	if not thresholds.has(row.view):
		_check(false, "EXPOSURE_BASELINE: missing view threshold " + str(row.view))
		return
	var limit: float = float(thresholds[row.view].maximum_fraction)
	row.maximum_fraction = limit
	row.style_coverage = "PASS" if float(row.visible_neck_fraction) <= limit else "FAIL"
	if row.style_coverage == "FAIL":
		style_failures.append("STYLE_NECK_COVERAGE: body%d %s/%s exposes %.3f%% above frozen peers %.3f%%" % [row.body_id, row.pose, row.view, row.visible_neck_percent, limit * 100])

func _image() -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()

func _red_pixels(image: Image) -> int:
	if image == null or image.is_empty():
		_check(false, "EXPOSURE_RENDER: viewport returned no pixels; a real renderer is required")
		return 0
	var count := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r >= 0.80 and pixel.g <= 0.10 and pixel.b <= 0.10 and pixel.a >= 0.99: count += 1
	return count

func _save_image(image: Image, file_name: String, kind: String) -> void:
	if image == null or image.is_empty() or image.save_png(output + file_name) != OK:
		_check(false, "EXPOSURE_RENDER: cannot save " + file_name)
		return
	frames.append({"file": file_name, "kind": kind, "sha256": _hash(output + file_name), "width": image.get_width(), "height": image.get_height()})

func _red_bounds(image: Image) -> Rect2i:
	if image == null or image.is_empty(): return Rect2i()
	var lower := Vector2i(image.get_width(), image.get_height())
	var upper := Vector2i(-1, -1)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r < 0.80 or pixel.g > 0.10 or pixel.b > 0.10 or pixel.a < 0.99: continue
			lower.x = mini(lower.x, x)
			lower.y = mini(lower.y, y)
			upper.x = maxi(upper.x, x)
			upper.y = maxi(upper.y, y)
	return Rect2i(lower, upper - lower + Vector2i.ONE) if upper.x >= 0 else Rect2i()

func _normal_capture(file_name: String) -> void:
	viewport.size = NORMAL_SIZE
	var image: Image = await _image()
	_save_image(image, file_name + ".png", "native_resources_camera_reproduction")
	viewport.size = SIZE

func _regression_checks() -> void:
	pass

func _pin(path: String, reference: bool = false) -> void:
	resources[path] = _hash(path)
	if reference: reference_resources[path] = resources[path]

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"

func _check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "\t") + "\n")
	else: push_error("Cannot write " + path)

func _finish() -> void:
	_restore_diagnostic()
	var expected_candidates: int = BODIES.size() * POSES.size() * VIEWS.size()
	_check(candidate_rows.size() == expected_candidates, "EXPOSURE_MATRIX: expected %d bodies x %d poses x %d views = %d samples" % [BODIES.size(), POSES.size(), VIEWS.size(), expected_candidates])
	for path: String in resources: _check(_hash(path) == resources[path], "EXPOSURE_RESOURCE: changed while measuring " + path)
	_check(_hash(real_save) == real_save_hash, "EXPOSURE_SAVE: real player profile changed")
	var isolated: String = GameState.save_path
	source.free()
	fixture.cleanup()
	fixture.free()
	await get_tree().process_frame
	Contract.restore_state(GameState, state)
	Input.mouse_mode = input_mode
	_check(Contract.snapshot_state(GameState) == state, "EXPOSURE_STATE: GameState not restored")
	_check(_hash(real_save) == real_save_hash, "EXPOSURE_SAVE: real player profile not restored")
	var report: Dictionary = _plan()
	report.status = "PASS" if failures.is_empty() and style_failures.is_empty() else "FAIL"
	report.style_coverage = "FAIL" if not style_failures.is_empty() else ("PASS" if failures.is_empty() else "NOT_EVALUATED")
	report.measurement_integrity = "PASS" if failures.is_empty() else "FAIL"
	report.failures = failures
	report.style_failures = style_failures
	report.thresholds = thresholds
	report.thresholds_frozen_before_candidate_measurements = true
	report.baseline_path = baseline_path
	report.baseline_sha256 = _hash(baseline_path) if not baseline_path.is_empty() else "calibration_created_from_approved_peers_only"
	report.measurements = measurements
	report.candidate_measurements = candidate_rows
	report.reference_measurements = reference_rows
	report.reference_resource_sha256 = reference_resources
	report.resource_sha256 = resources
	report.material_policies = material_policies
	report.frames = frames
	report.regression_checks = regressions
	report.renderer = RenderingServer.get_current_rendering_method()
	report.engine_arguments = OS.get_cmdline_args()
	report.save_unchanged = _hash(real_save) == real_save_hash
	report.gamestate_restored = Contract.snapshot_state(GameState) == state
	report.real_save_path = real_save
	report.real_save_sha256_at_start = real_save_hash
	report.real_save_sha256_at_end = _hash(real_save)
	report.isolated_save_path = isolated
	_write(output + "capture.json", report)
	print("ARMOR_NECK_EXPOSURE_%s integrity=%s style=%s candidate_samples=%d references=%d" % [report.status, report.measurement_integrity, report.style_coverage, candidate_rows.size(), reference_rows.size()])
	for message: String in failures: push_error(message)
	for message: String in style_failures: push_error(message)
	get_tree().quit(0 if report.status == "PASS" else 1)
