extends Node

# Photograph the real HUD reticle at each stage of the hip-fire bloom.
# The spread is accumulated by calling the same _try_fire() branch the game
# uses, not by writing the value in; a mocked reticle would prove nothing.
# godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/hip_fire_spread_capture.tscn

const OUTPUT := "res://test_output/hip_fire_spread/"
const DETAIL := Vector2i(320, 320)
const WEAPONS := ["gun00", "gun17", "gun06", "gun40"]
const STAGES := [
	{"key": "precise", "ratio": 0.0, "label": "起始：最小散布"},
	{"key": "half", "ratio": 0.5, "label": "連射中：約半滿"},
	{"key": "capped", "ratio": 1.0, "label": "持續連射：到達上限"},
]
var viewport: SubViewport
var world: WarfareGameWorld
var captures: Array[Dictionary] = []
var failed := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Hip-fire capture requires a real renderer")
		get_tree().quit(1)
		return
	_run()


func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	GameState.selected_level = 1
	GameState.selected_game_mode = "singleplayer"
	GameState.selected_weapon = "gun00"
	GameState.battle_weapons.assign(["gun00"])
	GameState.settings.quality = "high"
	GameState.settings.show_touch_controls = "--mobile" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("debug/restoration/force_mobile_ui", GameState.settings.show_touch_controls)
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
	var mode := "mobile" if GameState.settings.show_touch_controls else "desktop"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).close()

	for weapon_id: String in WEAPONS:
		_equip(weapon_id)
		for stage: Dictionary in STAGES:
			_fire_to_ratio(float(stage.ratio))
			await _capture("%s_%s_%s" % [mode, weapon_id, str(stage.key)], str(stage.label))
		# Use each gun's recovery rate so every preview shows both the gradual
		# closing and the fully recovered state, including the shotgun.
		var profile: Dictionary = world.player.current_weapon.hip_spread
		var recovery_seconds := (float(profile.max_degrees) - float(profile.min_degrees)) / float(profile.recovery_degrees_per_second)
		_recover(_effective_recovery_delay() + recovery_seconds * 0.5)
		await _capture("%s_%s_recovering" % [mode, weapon_id], "停火後：縮回中")
		_recover(recovery_seconds)
		await _capture("%s_%s_recovered" % [mode, weapon_id], "恢復完成：原準星尺寸")
	# Focus aim must show the unbloomed reticle even right after a burst.
	_equip("gun17")
	_fire_to_ratio(1.0)
	world.player.touch_aim = true
	await _capture(mode + "_gun17_focus", "聚焦瞄準：不套用腰射散布")
	world.player.touch_aim = false

	var manifest := FileAccess.open(OUTPUT + mode + "_captures.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [viewport.size.x, viewport.size.y],
		"source": "WarfarePlayer._try_fire",
		"captures": captures,
	}, "\t"))
	manifest.close()
	_write_preview(mode)
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	print("HIP_FIRE_SPREAD_CAPTURE_%s %s images=%d" % ["FAIL" if failed else "PASS", mode, captures.size()])
	get_tree().quit(1 if failed else 0)


func _equip(weapon_id: String) -> void:
	world.player.touch_aim = false
	world.player.touch_fire = false
	world.player.equip_weapon(weapon_id, false)
	world.player.armor_skills = {}
	world.player.velocity = Vector3.ZERO
	world.hud._set_reticle_for_weapon(world.player.current_weapon)


func _fire_to_ratio(ratio: float) -> void:
	# equip_weapon already reset the bloom, so each stage grows from precise.
	var guard := 0
	while world.player.get_hip_spread_ratio() < ratio and guard < 400:
		guard += 1
		world.player.shot_cooldown = 0.0
		world.player.energy = world.player.max_energy
		if world.player._uses_magazine():
			world.player._set_magazine_rounds(int(world.player.current_weapon.magazine_size))
		world.player.reload_left = 0.0
		world.player._try_fire()
	if ratio >= 1.0 and world.player.get_hip_spread_ratio() < 1.0:
		failed = true
		push_error("Hip spread never reached its cap for " + world.player.current_weapon_id)


func _clear_effects() -> void:
	# Every shot spawns a tracer, muzzle flash and impact. A whole burst is
	# fired inside one frame, so none of them ever expire on their own and the
	# stack would sit across the reticle crop. The spread they produced stays.
	for effect: Node in world.effects_root.get_children():
		world.effects_root.remove_child(effect)
		effect.queue_free()


func _effective_recovery_delay() -> float:
	# A slow weapon keeps its bloom until its next possible shot, so the
	# profile's own delay is only a floor. Waiting the floor alone would
	# photograph a shotgun that has not started recovering yet.
	var profile: Dictionary = world.player.current_weapon.hip_spread
	return maxf(float(profile.recovery_delay), world.player._current_shot_interval() + 0.08)


func _recover(seconds: float) -> void:
	# The player's _physics_process is disabled for a still frame, so step the
	# same recovery function the game calls, at the same fixed timestep.
	var step := 1.0 / 60.0
	for frame in int(ceil(seconds / step)):
		world.player._update_hip_spread(step)


func _capture(stem: String, label: String) -> void:
	_clear_effects()
	await get_tree().process_frame
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
		push_error("Failed hip-fire capture: " + stem)
		return
	# A crop of the real renderer, not a separately drawn reticle mockup.
	var detail := capture.get_region(Rect2i(viewport.size / 2 - DETAIL / 2, DETAIL))
	if detail.save_png(OUTPUT + stem + "_reticle.png") != OK:
		failed = true
		push_error("Failed hip-fire reticle detail: " + stem)
		return
	var profile: Dictionary = world.player.current_weapon.hip_spread
	captures.append({
		"path": stem + ".png",
		"label": label,
		"weapon": world.player.current_weapon_id,
		"spread_degrees": snappedf(world.player.get_hip_spread_degrees(), 0.0001),
		"spread_ratio": snappedf(world.player.get_hip_spread_ratio(), 0.001),
		"reticle_scale": snappedf(world.player.get_hip_reticle_scale(), 0.001),
		"reticle_size_px": [world.hud.crosshair.size.x, world.hud.crosshair.size.y],
		"recovery_delay_seconds": _effective_recovery_delay(),
		"max_degrees": float(profile.max_degrees),
		"focus_aiming": world.player.is_focus_aiming(),
	})


func _write_preview(mode: String) -> void:
	var html := """<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>腰射連射散布對照</title>
<style>body{margin:0;padding:32px;background:#10161d;color:#e7edf2;font:16px/1.6 system-ui}main{max-width:1600px;margin:auto}h1{margin:0}p{color:#a9bbc9}section{margin:32px 0;border-top:1px solid #33424f;padding-top:16px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}figure{margin:0}img{width:100%;background:#06090c;border:1px solid #33424f}figcaption{color:#a9bbc9;font-size:14px}a{color:#8ed8e8}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:6px 12px 6px 0;border-bottom:1px solid #26323c}th{color:#8ea3b4;font-weight:500}td{font-variant-numeric:tabular-nums}</style><main><h1>腰射連射散布</h1>
<p>現在的腰射準星本身隨連射小幅擴張，停火後逐步縮回原尺寸。每把槍的準星與子彈散布同步變化，移動不增加散布。霰彈槍保留原本的多彈丸散布。</p><p>以下為 Godot Compatibility 的 1280×720 實際畫面，取中央 320×320 作比較。點圖可看原尺寸。</p>"""
	for weapon_id: String in WEAPONS:
		var profile: Dictionary = GameState.WEAPONS[weapon_id].hip_spread
		html += "<section><h2>" + str(GameState.WEAPONS[weapon_id].name).xml_escape() + " · " + weapon_id + "</h2>"
		var recovery_delay := 0.0
		for capture in captures:
			if str(capture.weapon) == weapon_id:
				recovery_delay = float(capture.recovery_delay_seconds)
				break
		html += "<p>新增腰射散布上限 %.2f°，每發 +%.2f°，最後一發後 %.2f 秒開始恢復，每秒收 %.2f°。</p>" % [
			float(profile.max_degrees), float(profile.per_shot_degrees),
			recovery_delay, float(profile.recovery_degrees_per_second)]
		html += "<div class='grid'>"
		for capture in captures:
			if str(capture.weapon) != weapon_id:
				continue
			html += _figure(str(capture.path).trim_suffix(".png") + "_reticle.png",
				"%s · %.2f° · 原準星 %.2f×" % [str(capture.label), float(capture.spread_degrees), float(capture.reticle_scale)])
		html += "</div></section>"
	html += "<section><h2>逐張數值</h2><p>準星倍率相對於該槍的起始尺寸；散布角度只計新增的連射散布。</p><table><tr><th>畫面</th><th>武器</th><th>散布</th><th>佔上限</th><th>準星倍率</th><th>聚焦中</th></tr>"
	for capture in captures:
		html += "<tr><td>%s</td><td>%s</td><td>%.3f°</td><td>%.0f%%</td><td>%.3f×</td><td>%s</td></tr>" % [
			str(capture.label).xml_escape(), str(capture.weapon),
			float(capture.spread_degrees), float(capture.spread_ratio) * 100.0,
			float(capture.reticle_scale), "是" if bool(capture.focus_aiming) else "否"]
	html += "</table></section>"
	html += "<section><h2>完整畫面</h2><div class='grid'>"
	for capture in captures:
		html += _figure(str(capture.path), str(capture.weapon) + " · " + str(capture.label))
	html += "</div></section></main></html>"
	var file := FileAccess.open(OUTPUT + mode + ".html", FileAccess.WRITE)
	file.store_string(html)
	file.close()


func _figure(path: String, caption: String) -> String:
	return "<figure><a href='" + path + "'><img loading='lazy' src='" + path + "' alt='" + caption.xml_escape() + "'></a><figcaption>" + caption.xml_escape() + "</figcaption></figure>"
