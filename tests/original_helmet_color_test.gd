extends Node3D

const Visuals = preload("res://scripts/game/armor_visuals.gd")
const Fixture = preload("res://tests/reload_catalog_fixture.gd")
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("ORIGINAL_HELMET_COLOR: " + message)

func _tint(material: Material) -> Color:
	if material is BaseMaterial3D:
		return material.albedo_color
	return material.get_shader_parameter("albedo_tint") if material is ShaderMaterial else Color.MAGENTA

func _run() -> void:
	var raw := (load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	add_child(raw)
	var original_materials: Dictionary = {}
	for id: int in [8, 11]:
		var head := raw.find_child("ArmorHead_%02d" % id, true, false) as MeshInstance3D
		original_materials[id] = head.get_active_material(0)
	Visuals._restore_original_helmet_colors(raw)
	for id: int in [8, 11]:
		var head := raw.find_child("ArmorHead_%02d" % id, true, false) as MeshInstance3D
		var body := raw.find_child("ArmorBody_%02d" % id, true, false) as MeshInstance3D
		_check(_tint(head.get_active_material(0)).is_equal_approx(_tint(body.get_active_material(0))), "Original helmet tint differs from body")
		_check(head.mesh.surface_get_material(0) == original_materials[id], "Shared source material was overwritten")
		_check((head.get_active_material(0) as BaseMaterial3D).albedo_texture == (original_materials[id] as BaseMaterial3D).albedo_texture, "Original texture changed")
	raw.free()
	var real_save := GameState.save_path
	var before := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "absent"
	GameState.save_path = "user://original_helmet_color_test_profile.json"
	var fixture := Fixture.new()
	add_child(fixture)
	fixture.setup()
	for id: int in [8, 11]:
		for part: int in 4:
			GameState.equipped_armor[ArmorCatalog.PART_KEYS[part]] = ArmorCatalog.item_key(part, id)
		fixture.player._apply_recovered_armor_visibility()
		var avatar: Node3D = fixture.player.recovered_avatar
		var head := avatar.find_child("ArmorHead_%02d" % id, true, false) as MeshInstance3D
		var body := avatar.find_child("ArmorBody_%02d" % id, true, false) as MeshInstance3D
		if str(head.get_meta("armor_rework", "")).begins_with("original_refined_"):
			_check(_tint(head.get_active_material(0)).is_equal_approx(_tint(body.get_active_material(0))), "Runtime original helmet tint differs from body")
		var shader := head.get_active_material(0)
		Visuals._restore_original_helmet_colors(avatar)
		_check(head.get_active_material(0) == shader, "Repeated restoration needlessly replaces material")
	fixture.cleanup()
	fixture.queue_free()
	await get_tree().process_frame
	GameState.save_path = real_save
	var after := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "absent"
	_check(before == after, "Real save changed")
	print("ORIGINAL_HELMET_COLOR_%s originals=2 runtime=2 source_preserved=true save_unchanged=%s" % ["PASS" if failures.is_empty() else "FAIL", str(before == after)])
	get_tree().quit(0 if failures.is_empty() else 1)
