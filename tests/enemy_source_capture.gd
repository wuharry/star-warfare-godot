extends Node

const Catalog = preload("res://scripts/core/monster_catalog.gd")
const OUTPUT := "res://test_output/enemy_source"

class Target extends WarfarePlayer:
	func _ready() -> void:
		health = 100000000.0
		max_health = health
		set_physics_process(false)
	func take_damage(_amount: float, _at := Vector3.ZERO, _source: Node = null) -> void: pass

var manifest: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not GameState.save_path.begins_with("user://star_warfare_test_"):
		push_error("Capture requires -- --test-profile=<unique>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _sheet("normal", range(8), false, "idle")
	await _sheet("elite", Catalog.ELITE_IDS, true, "run")
	await _sheet("boss_idle", [8, 9, 10, 11, 12, 13, 14], false, "idle")
	await _sheet("boss_attack", [8, 9, 10, 11, 12, 13, 14], false, "attack")
	var report := FileAccess.open(OUTPUT + "/capture.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"viewport": [1280, 720], "renderer": RenderingServer.get_current_rendering_method(), "captures": manifest}, "\t"))
	report.close()
	await get_tree().create_timer(0.15).timeout
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.15).timeout
	print("ENEMY_SOURCE_CAPTURE_PASS sheets=4")
	get_tree().quit()


func _sheet(filename: String, ids: Array, elite: bool, pose: String) -> void:
	var layer := Control.new()
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color(0.035, 0.045, 0.06)
	background.size = Vector2(1280, 720)
	layer.add_child(background)
	var heading := Label.new()
	heading.text = "SOURCE ENEMIES / " + filename.to_upper() + "    |    source meshes + materials; metre heights below"
	heading.position = Vector2(20, 12)
	heading.add_theme_font_size_override("font_size", 20)
	layer.add_child(heading)
	var records: Array[Dictionary] = []
	for index in range(ids.size()):
		var id: int = ids[index]
		var origin := Vector2(16 + (index % 4) * 316, 48 + (index / 4) * 332)
		var container := SubViewportContainer.new()
		container.position = origin
		container.size = Vector2(304, 286)
		container.stretch = true
		layer.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(304, 286)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.09, 0.11, 0.14)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
		environment.environment.ambient_light_energy = 0.7
		viewport.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -35, 0)
		light.light_energy = 1.6
		viewport.add_child(light)
		var target := Target.new()
		viewport.add_child(target)
		target.position = Vector3(0, 0, -30)
		var enemy := WarfareEnemy.new()
		if not enemy.configure_original(target, id, 1.0, elite):
			push_error(enemy.configuration_error)
			get_tree().quit(1)
			return
		enemy.spawn_left = 0.0
		viewport.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.rotation.y = 0.0
		var clip := pose
		if id == 8 and pose == "attack": clip = "attack04"
		if id == 10 and pose == "attack": clip = "flame"
		if id == 14 and pose == "attack": clip = "attack_joky"
		enemy._play_recovered_animation(clip, 0.0, true)
		var animation := enemy.recovered_animation_player
		animation.advance(0.0)
		animation.seek(animation.get_animation(clip).length * (0.52 if pose == "attack" else 0.1), true)
		animation.pause()
		var bounds := EnemyHitGeometry.posed_bounds(enemy)
		var center := bounds.get_center()
		var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = extent * 1.3
		camera.position = center + Vector3(0.7, 0.45, -1.0).normalized() * extent * 2.0
		camera.look_at(center)
		camera.current = true
		var label := Label.new()
		label.position = origin + Vector2(0, 289)
		label.text = "%02d %s%s / %s\n%s  |  posed height %.2fm" % [id, Catalog.KINDS[id], " ELITE" if elite else "", clip, Catalog.MODELS[id], bounds.size.y]
		label.add_theme_font_size_override("font_size", 13)
		layer.add_child(label)
		records.append({"id": id, "elite": elite, "clip": clip, "bounds": [bounds.size.x, bounds.size.y, bounds.size.z]})
	for frame in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	var error := screenshot.save_png(OUTPUT + "/" + filename + ".png")
	if error != OK:
		push_error("Capture failed: " + error_string(error))
		get_tree().quit(1)
	manifest.append({"file": filename + ".png", "enemies": records})
	layer.free()
	await get_tree().process_frame
