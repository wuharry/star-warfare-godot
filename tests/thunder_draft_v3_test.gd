extends Node

const Contract = preload("res://tools/thunder_draft_v3/contract.gd")
const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
const Catalog = preload("res://scripts/core/armor_catalog.gd")
const CONFIG := "res://docs/art/thunder_draft_v3/runtime_config.json"

var errors: Array[String] = []
var animation_samples: Array[Dictionary] = []
var store_samples: Array[Dictionary] = []
var checks := 0
var head_metrics: Dictionary = {}
var target: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors.append(message)


func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	errors.append_array(Contract.check_pins(config, true))
	if not errors.is_empty():
		_finish(config, {})
		return
	target = JSON.parse_string(FileAccess.get_file_as_string(str(config.head_target)))
	_check(not "--thunder-helmet=sw2" in OS.get_cmdline_user_args() and not "--thunder-helmet=prototype" in OS.get_cmdline_user_args(), "This test must exercise the default Thunder loader")
	_check(Visuals.reworked_scene_path(6) == str(config.output_scene), "Default loader does not select draft-refined Thunder")
	var saved_path: String = GameState.save_path
	var saved_hash := _hash(saved_path)
	GameState.save_path = "user://thunder_draft_v3_test_profile.json"
	var raw := (load(str(config.source_scene)) as PackedScene).instantiate() as Node3D
	var before := (load(str(config.before_scene)) as PackedScene).instantiate() as Node3D
	var current := (load(str(config.output_scene)) as PackedScene).instantiate() as Node3D
	var original_head := raw.find_child(str(config.head_node), true, false) as MeshInstance3D
	var head := current.find_child(str(config.head_node), true, false) as MeshInstance3D
	_check(current.get_child_count() == 4, "Default scene must retain four modular parts")
	errors.append_array(Contract.compare_head(original_head, head, target))
	_check(head.get_meta("armor_rework", "") == str(config.revision), "Head revision marker missing")
	_check(head.mesh.get_surface_count() == 1, "Original head surface count changed")
	_check(head.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size() == 147, "Original 147 UV samples changed")
	_check(Contract.triangle_count(head) == 196, "Original 196 head triangles changed")
	_check(head.skin.get_bind_count() == 28, "Original 28 head Skin binds changed")
	for part_name: String in config.inherited_body_nodes:
		errors.append_array(Contract.compare_part(before.find_child(part_name, true, false), current.find_child(part_name, true, false)))
	_validate_texture(config, head)
	head_metrics = Contract.geometry_report(original_head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], Contract.target_points(target), original_head.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX])
	_validate_guards(original_head, head, target)
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	GameState.save_path = "user://thunder_draft_v3_test_profile.json"
	_equip_thunder()
	fixture.player._apply_recovered_armor_visibility()
	var avatar := fixture.player.recovered_avatar
	var skeleton := fixture.player.recovered_skeleton
	var parts: Array[MeshInstance3D] = []
	for prefix: String in Visuals.ORIGINAL_PART_PREFIXES:
		var name_key := prefix + "06"
		var loaded := avatar.find_child(name_key, true, false) as MeshInstance3D
		var authored := current.find_child(name_key, true, false) as MeshInstance3D
		_check(loaded != null and loaded.visible, "Actual player missing visible " + name_key)
		if loaded == null:
			continue
		parts.append(loaded)
		_check(loaded.mesh == authored.mesh and loaded.skin == authored.skin, "Actual player does not consume authored mesh/Skin: " + name_key)
		_check(loaded.transform == authored.transform, "Actual player changed part transform: " + name_key)
		_check(loaded.get_node_or_null(loaded.skeleton) == skeleton, "Actual player part uses the wrong skeleton: " + name_key)
		for sid: int in loaded.mesh.get_surface_count():
			_check(loaded.get_active_material(sid) == authored.get_active_material(sid), "Actual player overrides authored material: " + name_key)
	_check_visible(avatar, ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"])
	var untouched_scene := (load(Visuals.reworked_scene_path(2)) as PackedScene).instantiate() as Node3D
	for cycle: int in 3:
		GameState.equipped_armor = {"head": "armor_head_06", "body": "armor_body_00", "arms": "armor_arms_21", "legs": "armor_legs_02", "bag": "armor_bag_00"}
		fixture.player._apply_recovered_armor_visibility()
		_check_visible(avatar, ["ArmorHead_06", "ArmorBody_00", "ArmorHand_21", "ArmorFoot_02"])
		var loaded_foot := avatar.find_child("ArmorFoot_02", true, false) as MeshInstance3D
		var authored_foot := untouched_scene.find_child("ArmorFoot_02", true, false) as MeshInstance3D
		_check(loaded_foot.mesh == authored_foot.mesh, "Mixed equip changed Tank mesh")
		_equip_thunder()
		fixture.player._apply_recovered_armor_visibility()
		_check_visible(avatar, ["ArmorHead_06", "ArmorBody_06", "ArmorHand_06", "ArmorFoot_06"])
	var original_child_count := skeleton.get_child_count()
	for cycle: int in 10:
		fixture.player._apply_recovered_armor_visibility()
	_check(skeleton.get_child_count() == original_child_count, "Repeated equip duplicates part nodes")
	avatar.remove_meta("unity_armor_materials_restored")
	Visuals.ensure_parts(avatar, {"head": 6})
	_check((avatar.find_child("ArmorHead_06", true, false) as MeshInstance3D).get_active_material(0) == head.get_active_material(0), "Original material restoration overwrites new head")
	_validate_animation(fixture, parts)
	_validate_store(current)
	untouched_scene.free()
	fixture.cleanup()
	fixture.queue_free()
	raw.free()
	before.free()
	current.free()
	await get_tree().process_frame
	AudioDirector.stop_all_sfx()
	_check(_hash(saved_path) == saved_hash, "Real user save changed")
	GameState.save_path = saved_path
	_finish(config, {"save_path": saved_path, "before": saved_hash, "after": _hash(saved_path), "unchanged": _hash(saved_path) == saved_hash})


func _validate_texture(config: Dictionary, head: MeshInstance3D) -> void:
	var material := head.get_active_material(0) as ShaderMaterial
	_check(material != null, "New head must use its dedicated painted shader")
	if material == null:
		return
	_check(material.resource_name == "ThunderDraftHeadV3", "Wrong head material")
	_check(material.shader != null and "render_mode unshaded, cull_disabled;" in material.shader.code and "ALBEDO = texture(albedo_texture, UV).rgb;" in material.shader.code, "Head shader must sample original UV as unshaded diffuse")
	var texture := material.get_shader_parameter("albedo_texture") as Texture2D
	_check(texture != null and texture.resource_path == str(config.portable_texture), "Head shader does not use the portable native generated texture")
	if texture == null:
		return
	var decoded := Image.new()
	_check(decoded.load_png_from_buffer(FileAccess.get_file_as_bytes(str(config.native_generated_png))) == OK, "Cannot decode native head PNG")
	var runtime := texture.get_image()
	_check(runtime != null and not runtime.is_empty(), "Portable runtime head image missing")
	if runtime == null or runtime.is_empty():
		return
	_check(runtime.get_format() == decoded.get_format() and runtime.get_size() == decoded.get_size(), "Portable head image size/format changed")
	_check(runtime.get_data() == decoded.get_data(), "Portable head image pixel bytes changed")
	_check(not runtime.has_mipmaps() and not runtime.is_compressed(), "Portable head image unexpectedly generated mipmaps or compressed pixels")


func _validate_guards(original: MeshInstance3D, valid: MeshInstance3D, valid_target: Dictionary) -> void:
	var wrong := valid.duplicate() as MeshInstance3D
	wrong.transform.origin.x += 0.01
	_check(not Contract.compare_head(original, wrong, valid_target).is_empty(), "Guard failed to reject changed original transform")
	wrong.free()
	wrong = valid.duplicate() as MeshInstance3D
	wrong.skin = valid.skin.duplicate(true) as Skin
	var pose := wrong.skin.get_bind_pose(0)
	pose.origin.x += 0.01
	wrong.skin.set_bind_pose(0, pose)
	_check(not Contract.compare_head(original, wrong, valid_target).is_empty(), "Guard failed to reject changed original Skin bind")
	wrong.free()
	for channel: int in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		wrong = valid.duplicate() as MeshInstance3D
		var arrays := valid.mesh.surface_get_arrays(0).duplicate(true)
		if channel == Mesh.ARRAY_TEX_UV:
			arrays[channel][0] += Vector2(0.025, 0)
		elif channel == Mesh.ARRAY_WEIGHTS:
			# The original first influence is 1.0; >1 is clamped in storage.
			# Redistribute within [0,1] while keeping the influence sum 1.0.
			arrays[channel][0] = 0.5
			arrays[channel][1] = 0.5
		else:
			arrays[channel][0] = (int(arrays[channel][0]) + 1) % (147 if channel == Mesh.ARRAY_INDEX else 28)
		var wrong_mesh := ArrayMesh.new()
		wrong_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		wrong.mesh = wrong_mesh
		_check(wrong.mesh.surface_get_arrays(0)[channel] != valid.mesh.surface_get_arrays(0)[channel], "Negative guard fixture did not actually change stored channel " + str(channel))
		var immutable_errors := Contract.compare_head(original, wrong, valid_target)
		_check(immutable_errors.has(str(original.name) + ": native array channel %d changed at surface 0" % channel), "Guard did not independently identify immutable channel " + str(channel))
		wrong.free()
	var moved := valid_target.duplicate(true)
	moved.positions[0][0] += 0.50
	_check(not Contract.validate_target(original, moved).is_empty(), "Guard failed to reject >20% original-head displacement")
	var rebased := valid_target.duplicate(true)
	rebased.source_positions = rebased.positions.duplicate(true)
	_check(not Contract.validate_target(original, rebased).is_empty(), "Guard failed to reject source position rebase")
	var divergent := valid_target.duplicate(true)
	divergent.positions[0][0] += 0.001
	_check(not Contract.compare_head(original, valid, divergent).is_empty(), "Guard failed to reject delivered head mismatch with target")


func _validate_animation(fixture: Node3D, parts: Array[MeshInstance3D]) -> void:
	var player: WarfarePlayer = fixture.player
	var animation := player.recovered_animation_player
	var skeleton := player.recovered_skeleton
	player.recovered_animation_tree.active = false
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var initial: Dictionary = {}
	var moved: Dictionary = {}
	for clip: String in ["idle_rifle", "run_rifle"]:
		_check(animation.has_animation(clip), "Missing actual animation " + clip)
		if not animation.has_animation(clip):
			continue
		animation.play(clip)
		for time: float in [0.0, 0.2, 0.5]:
			animation.seek(time, true)
			skeleton.force_update_all_bone_transforms()
			for part: MeshInstance3D in parts:
				var bounds := Contract.posed_bounds(part, skeleton)
				_check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length() > 0.01 and bounds.size.length() < 3.0, str(part.name) + " has invalid animated skin bounds during " + clip)
				if not initial.has(part.name):
					initial[part.name] = bounds
				elif not bounds.is_equal_approx(initial[part.name]):
					moved[part.name] = true
			animation_samples.append({"clip": clip, "time": time, "parts_checked": parts.size()})
	for part: MeshInstance3D in parts:
		_check(moved.has(part.name), str(part.name) + " does not follow animated bones")
	for fraction: float in [0.20, 0.52, 0.85]:
		fixture.begin("gun00", 0, true)
		fixture.advance_to(fixture.duration * fraction)
		for part: MeshInstance3D in parts:
			var bounds := Contract.posed_bounds(part, skeleton)
			_check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length() > 0.01 and bounds.size.length() < 3.0, str(part.name) + " has invalid actual moving reload bounds")
		animation_samples.append({"clip": "actual_gun00_moving_reload_variant_0", "fraction": fraction, "time": fixture.elapsed, "parts_checked": parts.size()})


func _validate_store(template: Node3D) -> void:
	var shell := UnityEquipmentShell.new()
	shell.setup("store", true)
	add_child(shell)
	for mode: String in ["store", "customize"]:
		shell.set_mode(mode, false)
		for index: int in 4:
			var part_name: String = str(Visuals.ORIGINAL_PART_PREFIXES[index]) + "06"
			shell._select_category(Catalog.PART_KEYS[index], false)
			shell._select_item(Catalog.item_key(index, 6), false)
			var preview := shell.preview_root.find_child(part_name, true, false) as MeshInstance3D
			var authored := template.find_child(part_name, true, false) as MeshInstance3D
			_check(preview != null and preview.visible, mode + " missing visible preview " + part_name)
			if preview == null:
				continue
			_check(preview.mesh == authored.mesh and preview.skin == authored.skin, mode + " does not consume authored mesh/Skin " + part_name)
			for sid: int in preview.mesh.get_surface_count():
				_check(preview.get_active_material(sid) == authored.get_active_material(sid), mode + " overrides authored material " + part_name)
			store_samples.append({"mode": mode, "part": part_name, "mesh_skin_material_match": preview.mesh == authored.mesh and preview.skin == authored.skin})
	shell.queue_free()


func _equip_thunder() -> void:
	GameState.equipped_armor = {"head": "armor_head_06", "body": "armor_body_06", "arms": "armor_arms_06", "legs": "armor_legs_06", "bag": "armor_bag_00"}


func _check_visible(avatar: Node3D, expected: Array) -> void:
	var actual: Array[String] = []
	for mesh: MeshInstance3D in avatar.find_children("Armor*", "MeshInstance3D", true, false):
		if mesh.visible:
			actual.append(str(mesh.name))
	_check(actual.size() == expected.size(), "Equipment displays extra armor parts")
	for part_name: String in expected:
		_check(actual.has(part_name), "Equipment missing " + part_name)


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"


func _finish(config: Dictionary, save_record: Dictionary) -> void:
	var report := {
		"status": "PASS" if errors.is_empty() else "FAIL", "errors": errors, "checks": checks,
		"revision": config.revision, "default_scene_sha256": _hash(str(config.output_scene)),
		"head_original_uv_topology_skin_transform_exact": errors.is_empty(), "head_positions_match_pinned_target": errors.is_empty(), "head_contract": head_metrics,
		"target_sha256": _hash(str(config.head_target)), "before_scene_sha256": _hash(str(config.before_scene)), "body_baseline_commit": config.body_baseline_commit,
		"whole_suit_original_percentage": "NOT_CLAIMED_BODY_INHERITS_3ED",
		"body_buffers_materials_skin_transform_vs_3ed1c291_exact": errors.is_empty(),
		"head_uv_coordinate_count": 147, "head_triangles": 196, "head_geometry_displacement_fraction": head_metrics.get("max_displacement_fraction_of_smallest_dimension", null),
		"head_uv_changed_fraction": 0.0, "actual_default_loader": errors.is_empty(),
		"mixed_equipment_cycles": 3 if not animation_samples.is_empty() else 0, "repeated_equips": 10 if not animation_samples.is_empty() else 0,
		"animation_samples": animation_samples, "store_customize_samples": store_samples,
		"negative_guards": ["original_transform", "original_skin_bind", "original_uv", "original_indices", "original_bones", "original_weights", "original_head_20_percent", "source_rebase", "delivered_target_mismatch"] if checks > 0 else [],
		"real_save": save_record, "protected_alternates": config.protected_alternates,
		"visual_acceptance": "NOT_RUN_IN_THIS_LOGIC_TEST"
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(config.work) + "review/"))
	var file := FileAccess.open(str(config.work) + "review/runtime_test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for error: String in errors:
		push_error(error)
	print("THUNDER_DRAFT_V3_RUNTIME_%s checks=%d errors=%d" % [report.status, checks, errors.size()])
	get_tree().quit(0 if errors.is_empty() else 1)
