extends Node

const OUTPUT := "res://test_output/scope_aim/"
var viewport: SubViewport
var world: WarfareGameWorld
var captures: Array[Dictionary] = []
var failed := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Scope capture requires a real renderer")
		get_tree().quit(1)
		return
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_level = 1
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	GameState.settings.quality = "high"
	GameState.settings.show_touch_controls = true
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", "--mobile" in OS.get_cmdline_user_args())
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = (load("res://scenes/game.tscn") as PackedScene).instantiate() as WarfareGameWorld
	viewport.add_child(world)
	await get_tree().physics_frame
	await get_tree().process_frame
	world.completed = true
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	world.hud.announcement.text = ""
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var mode := "mobile" if is_instance_valid(world.hud.touch_root) else "desktop"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).close()
	for key: String in ["gun00", "gun14", "gun34", "gun35", "gun40", "gun01", "gun43"]:
		world.player.equip_weapon(key, false)
		await _capture(mode + "_" + key + "_hip")
		world.player.toggle_touch_aim()
		var steps := maxi(1, world.player.get_scope_magnifications().size())
		for index in steps:
			await _capture(mode + "_" + key + "_aim_" + str(index))
			world.player.cycle_scope_magnification()
	if mode == "mobile":
		world.player.equip_weapon("gun00", false)
		world.player.toggle_touch_aim()
		for dimensions: Vector2i in [Vector2i(1560, 720), Vector2i(960, 640)]:
			viewport.size = dimensions
			await _capture("mobile_gun00_" + str(dimensions.x))
	var manifest := FileAccess.open(OUTPUT + mode + "_captures.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "captures": captures}, "\t"))
	manifest.close()
	_write_preview(mode)
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	print("SCOPE_AIM_CAPTURE_PASS " + mode if not failed else "SCOPE_AIM_CAPTURE_FAIL")
	get_tree().quit(1 if failed else 0)

func _capture(stem: String) -> void:
	for frame in 120:
		world.player._update_camera_controller(1.0 / 60.0)
	world.hud._layout_original_hud()
	world.hud._update_aim_hud()
	world.hud._update_fire_reticle_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	# macOS can occlude the root window; explicitly render our own viewport.
	RenderingServer.force_draw(false)
	var capture := viewport.get_texture().get_image()
	if capture.is_empty() or capture.get_size() != viewport.size or capture.save_png(OUTPUT + stem + ".png") != OK:
		failed = true
		push_error("Failed scope capture: " + stem)
		return
	captures.append({"path": stem + ".png", "viewport": [viewport.size.x, viewport.size.y], "weapon": world.player.current_weapon_id, "scoped": world.player.is_scope_active(), "magnification": world.player.get_scope_magnification(), "fov": world.player.camera.fov})

func _write_preview(mode: String) -> void:
	var html := """<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>瞄準鏡與準星對照</title>
<style>body{margin:0;padding:32px;background:#10161d;color:#e7edf2;font:16px/1.6 system-ui}main{max-width:1600px;margin:auto}h1{margin:0}p{color:#a9bbc9}section{margin:32px 0;border-top:1px solid #33424f;padding-top:16px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}figure{margin:0}img{width:100%;background:#06090c;border:1px solid #33424f}figcaption{color:#a9bbc9}a{color:#8ed8e8}</style><main><h1>第三人稱與鏡內準星</h1><p>Godot Compatibility 實際擷取。未開鏡沿用原準星；鏡內準星、鏡框和倍率由各槍的瞄準鏡設定決定。模型圖使用中性無光照材質檢查；鏡內設計與倍率為本專案新增設定。點圖可看原尺寸。</p>"""
	html += "<p>本版改為細圓框、可透視場景的外圍暗角，以及金色圓環＋分段弧線＋十字導線。各槍保留自己的環大小、短刻線、淡鏡片色調與倍率；鏡外也使用同一個放大相機。<a href='https://www.youtube.com/watch?v=3j1gM6l4d5w&amp;t=54s'>Call of Mini 參考影片（約 0:54）</a>。</p>"
	var before_stem := mode + "_gun00_aim_0.png" if mode == "mobile" else mode + "_gun40_aim_0.png"
	if FileAccess.file_exists(OUTPUT + "before_com_style/" + before_stem):
		html += "<section><h2>這次修改 · 相同武器與倍率</h2><div class='grid'>"
		html += _figure("before_com_style/" + before_stem, "修改前：厚實鏡框與不透明周圍")
		html += _figure(before_stem, "修改後：透視暗角、金色環形準星")
		html += "</div></section>"
	for key: String in ["gun00", "gun14", "gun34", "gun35", "gun40", "gun01", "gun43"]:
		html += "<section><h2>" + str(GameState.WEAPONS[key].name).xml_escape() + " · " + key + "</h2><div class='grid'>"
		var model_path := "models/" + key + "_rear.png"
		if FileAccess.file_exists(OUTPUT + model_path):
			html += _figure(model_path, "模型後方：確認鏡具／瞄準裝置")
		for capture in captures:
			if str(capture.weapon) != key or int(capture.viewport[0]) != 1280:
				continue
			var caption := "第三人稱／腰射"
			if "_aim_" in str(capture.path):
				caption = str(capture.magnification).trim_suffix(".0") + "× · 鏡內專屬準星" if bool(capture.scoped) else "無瞄準鏡：原本的視野放大"
			html += _figure(str(capture.path), caption)
		html += "</div></section>"
	for capture in captures:
		if int(capture.viewport[0]) != 1280:
			html += "<section><h2>手機比例 · " + str(capture.viewport) + "</h2>" + _figure(str(capture.path), "移動、射擊、開鏡、換彈與倍率分區") + "</section>"
	html += "</main></html>"
	var file := FileAccess.open(OUTPUT + mode + ".html", FileAccess.WRITE)
	file.store_string(html)
	file.close()

func _figure(path: String, caption: String) -> String:
	return "<figure><a href='" + path + "'><img loading='lazy' src='" + path + "' alt='" + caption + "'></a><figcaption>" + caption + "</figcaption></figure>"
