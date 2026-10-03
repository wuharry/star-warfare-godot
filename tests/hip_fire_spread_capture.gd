extends Node

# Photograph the real HUD reticle at each stage of the hip-fire bloom.
# The spread is accumulated by calling the same _try_fire() branch the game
# uses, not by writing the value in; a mocked reticle would prove nothing.
# godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/hip_fire_spread_capture.tscn

const OUTPUT := "res://test_output/hip_fire_spread/"
const DETAIL := Vector2i(320, 320)
const Atlas = preload("res://scripts/ui/original_atlas.gd")
const HipReticle = preload("res://scripts/ui/hip_reticle.gd")
const SHAPE_VIEWPORT_SIZE := Vector2i(320, 320)
const SHAPE_OPEN_OFFSET := Vector2(12, 12)
# Inspect the original sight mark, including the off-centre marks in the
# recovered atlas. Circles exclude the outer arcs that are meant to move.
const SHAPE_SIGHT_REGIONS := {
	0: {"center": Vector2i(160, 160), "radius": 4},
	2: {"center": Vector2i(160, 160), "radius": 10},
	4: {"center": Vector2i(160, 160), "radius": 12},
	5: {"center": Vector2i(160, 160), "radius": 4},
	7: {"center": Vector2i(160, 160), "radius": 24},
	8: {"center": Vector2i(160, 160), "radius": 18},
	9: {"center": Vector2i(159, 146), "radius": 4},
	10: {"center": Vector2i(160, 160), "radius": 10},
	11: {"center": Vector2i(157, 160), "radius": 10},
	12: {"center": Vector2i(160, 159), "radius": 10},
	13: {"center": Vector2i(161, 161), "radius": 17},
}
const WEAPONS := ["gun00", "gun17", "gun06", "gun40"]
const STAGES := [
	{"key": "precise", "ratio": 0.0, "label": "起始：原準心"},
	{"key": "single", "ratio": 0.12, "label": "單發：略微展開"},
	{"key": "half", "ratio": 0.5, "label": "短連射：逐發累積"},
	{"key": "capped", "ratio": 1.0, "label": "持續連射：展開上限"},
]
var viewport: SubViewport
var world: WarfareGameWorld
var captures: Array[Dictionary] = []
var failed := false
var captured_shapes := 0


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
	# Advance visual recovery explicitly so capture speed does not alter the
	# photographed state; the live HUD uses the same function each frame.
	world.hud.set_process(false)
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
			var label := str(stage.label) if world.hud._uses_rifle_reticle_bloom() or str(stage.key) == "precise" else ("單發：準心維持原圖" if str(stage.key) == "single" else "連射：準心維持原圖")
			await _capture("%s_%s_%s" % [mode, weapon_id, str(stage.key)], label)
		# Equal 0.12-second intervals after the hold reveal accelerating return.
		_recover(HipReticle.Bloom.RECOVERY_DELAY + 0.12)
		await _capture("%s_%s_recovering_slow" % [mode, weapon_id], "停火初期：慢速收回" if world.hud._uses_rifle_reticle_bloom() else "停火初期：原準心")
		_recover(0.12)
		await _capture("%s_%s_recovering_fast" % [mode, weapon_id], "相同時間後：收回加快" if world.hud._uses_rifle_reticle_bloom() else "停火後：原準心")
		_recover(1.0)
		await _capture("%s_%s_recovered" % [mode, weapon_id], "恢復完成：原線段間距")
	# Focus aim must show the unbloomed reticle even right after a burst.
	_equip("gun00")
	_fire_to_ratio(1.0)
	world.player.touch_aim = true
	await _capture(mode + "_gun00_focus", "聚焦瞄準：原準心")
	world.player.touch_aim = false

	var manifest := FileAccess.open(OUTPUT + mode + "_captures.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [viewport.size.x, viewport.size.y],
		"source": "WarfarePlayer._try_fire",
		"reticle_effect": "rifle-only image pieces translate outward; successful shots accumulate; recovery accelerates; source strokes keep their scale",
		"captures": captures,
	}, "\t"))
	manifest.close()
	_write_preview(mode)
	world.free()
	AudioDirector.stop_all_sfx()
	await get_tree().process_frame
	await _capture_segment_shapes(mode)
	if captures.size() != WEAPONS.size() * (STAGES.size() + 3) + 1 or captured_shapes != 14:
		failed = true
		push_error("Reticle capture did not complete all game stages and AimIDs")
	print("HIP_FIRE_SPREAD_CAPTURE_%s %s images=%d shapes=%d" % ["FAIL" if failed else "PASS", mode, captures.size(), captured_shapes])
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
	while _capture_driver_ratio() < ratio and guard < 400:
		guard += 1
		world.player.shot_cooldown = 0.0
		world.player.energy = world.player.max_energy
		if world.player._uses_magazine():
			world.player._set_magazine_rounds(int(world.player.current_weapon.magazine_size))
		world.player.reload_left = 0.0
		world.player._try_fire()
	if ratio >= 1.0 and _capture_driver_ratio() < 1.0:
		failed = true
		push_error("Hip spread never reached its cap for " + world.player.current_weapon_id)

func _capture_driver_ratio() -> float:
	# Non-rifles deliberately stay at zero visual bloom, so still shoot their
	# real firing branch to verify they retain the original art during a burst.
	return world.hud._hip_reticle_spread_ratio() if world.hud._uses_rifle_reticle_bloom() else world.player.get_hip_spread_ratio()


func _clear_effects() -> void:
	# Every shot spawns a tracer, muzzle flash and impact. A whole burst is
	# fired inside one frame, so none of them ever expire on their own and the
	# stack would sit across the reticle crop. The spread they produced stays.
	for effect: Node in world.effects_root.get_children():
		world.effects_root.remove_child(effect)
		effect.queue_free()


func _effective_recovery_delay() -> float:
	return HipReticle.Bloom.RECOVERY_DELAY if world.hud._uses_rifle_reticle_bloom() else 0.0


func _recover(seconds: float) -> void:
	# The player's _physics_process is disabled for a still frame, so step the
	# same recovery function the game calls, at the same fixed timestep.
	var step := 1.0 / 60.0
	var remaining := maxf(0.0, seconds)
	while remaining > 0.000001:
		var elapsed := minf(step, remaining)
		world.player._update_hip_spread(elapsed)
		world.hud._advance_hip_reticle(elapsed)
		remaining -= elapsed


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
		# Drawing extent is independent of ballistic spread and is not source
		# magnification. Capture the actual geometry, rather than a player helper.
		"extent_ratio": snappedf(world.hud.crosshair.size.x / (world.hud.crosshair.texture.get_size().x * world.hud.crosshair.source_scale), 0.001),
		"visual_spread_ratio": snappedf(world.hud._hip_reticle_spread_ratio(), 0.001),
		"rifle_reticle_enabled": world.hud._uses_rifle_reticle_bloom(),
		"reticle_size_px": [world.hud.crosshair.size.x, world.hud.crosshair.size.y],
		"segment_offset_px": [world.hud.crosshair.segment_offset.x, world.hud.crosshair.segment_offset.y],
		"source_scale": world.hud.crosshair.source_scale,
		"recovery_delay_seconds": _effective_recovery_delay(),
		"max_degrees": float(profile.max_degrees),
		"recovery_acceleration_ratio_per_second_squared": HipReticle.Bloom.RECOVERY_ACCELERATION if world.hud._uses_rifle_reticle_bloom() else 0.0,
		"focus_aiming": world.player.is_focus_aiming(),
	})


func _capture_segment_shapes(mode: String) -> void:
	# Isolate every AimID from the world and HUD tint. Compare the production
	# segmented renderer with the previous native TextureRect at 1:1 source
	# pixels, including alpha; controlled integer gaps expose clipping or
	# duplicated source pieces without conflating them with gameplay mapping.
	var shape_viewport := SubViewport.new()
	shape_viewport.size = SHAPE_VIEWPORT_SIZE
	shape_viewport.disable_3d = true
	shape_viewport.transparent_bg = true
	shape_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(shape_viewport)
	var native := TextureRect.new()
	native.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	native.stretch_mode = TextureRect.STRETCH_SCALE
	native.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shape_viewport.add_child(native)
	var segmented := HipReticle.new()
	segmented.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shape_viewport.add_child(segmented)
	var results: Array[Dictionary] = []
	for aim_id in 14:
		var texture := Atlas.hud("hud%d" % aim_id)
		if texture == null:
			failed = true
			push_error("Missing native reticle for AimID %d" % aim_id)
			continue
		var stem := "%s_shape_hud%d" % [mode, aim_id]
		native.texture = texture
		native.size = texture.get_size()
		native.position = (Vector2(shape_viewport.size) - native.size) * 0.5
		native.visible = true
		segmented.visible = false
		var reference := await _read_shape_viewport(shape_viewport, stem + "_native")
		native.visible = false
		segmented.visible = true
		segmented.configure(texture, aim_id)
		segmented.update_spread(2.0, 0.0, 1.25)
		segmented.position = (Vector2(shape_viewport.size) - segmented.size) * 0.5
		var idle := await _read_shape_viewport(shape_viewport, stem + "_idle")
		segmented.update_spread(2.0, 1.0, 1.25)
		segmented.segment_offset = SHAPE_OPEN_OFFSET
		segmented.custom_minimum_size = texture.get_size() + SHAPE_OPEN_OFFSET * 2.0
		segmented.size = segmented.custom_minimum_size
		segmented.position = (Vector2(shape_viewport.size) - segmented.size) * 0.5
		segmented.queue_redraw()
		var opened := await _read_shape_viewport(shape_viewport, stem + "_open")
		segmented.update_spread(2.0, 0.0, 1.25)
		segmented.position = (Vector2(shape_viewport.size) - segmented.size) * 0.5
		var recovered := await _read_shape_viewport(shape_viewport, stem + "_recovered")
		if reference.is_empty() or idle.is_empty() or opened.is_empty() or recovered.is_empty():
			continue
		var idle_equal := reference.get_data() == idle.get_data()
		var recovered_equal := reference.get_data() == recovered.get_data()
		var native_alpha := _alpha_mass(reference)
		var open_alpha := _alpha_mass(opened)
		var alpha_error := absf(float(open_alpha - native_alpha)) / maxf(float(native_alpha), 1.0)
		var moved := reference.get_data() != opened.get_data()
		var sight_region: Dictionary = SHAPE_SIGHT_REGIONS.get(aim_id, {})
		var centre_pixels_stable := true
		if not sight_region.is_empty():
			centre_pixels_stable = _sight_pixels_match(reference, opened, Vector2i(sight_region.center), int(sight_region.radius))
		if not idle_equal or not recovered_equal or native_alpha <= 0 or alpha_error >= 0.02 or not moved or not centre_pixels_stable:
			failed = true
			push_error("AimID %d shape regression: idle_equal=%s restored_equal=%s alpha_error=%.4f moved=%s centre_stable=%s" % [aim_id, idle_equal, recovered_equal, alpha_error, moved, centre_pixels_stable])
		results.append({
			"aim_id": aim_id,
			"stem": stem,
			"idle_rgba_equals_native": idle_equal,
			"restored_rgba_equals_native": recovered_equal,
			"native_alpha_sum": native_alpha,
			"open_alpha_sum": open_alpha,
			"alpha_relative_error": alpha_error,
			"open_pixels_differ": moved,
			"centre_pixels_stable": centre_pixels_stable if not sight_region.is_empty() else null,
			"tested_sight_region": {"center": [sight_region.center.x, sight_region.center.y], "radius": sight_region.radius} if not sight_region.is_empty() else {},
			"source_scale": segmented.source_scale,
			"tested_open_offset_px": [SHAPE_OPEN_OFFSET.x, SHAPE_OPEN_OFFSET.y],
		})
		captured_shapes += 1
	shape_viewport.free()
	var manifest := FileAccess.open(OUTPUT + mode + "_segment_shapes.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [SHAPE_VIEWPORT_SIZE.x, SHAPE_VIEWPORT_SIZE.y],
		"reference": "native TextureRect at 1:1 source pixels",
		"alpha_relative_error_limit": 0.02,
		"shapes": results,
	}, "\t"))
	manifest.close()
	var html := """<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>準心線段：十四種原圖比對</title><style>body{margin:0;padding:32px;background:#10161d;color:#e7edf2;font:16px/1.6 system-ui}main{max-width:1440px;margin:auto}section{margin:32px 0;border-top:1px solid #33424f}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}figure{margin:0}img{width:100%;background:#1b2733;border:1px solid #33424f}figcaption,p{color:#a9bbc9}a{color:#8ed8e8}</style><main><h1>十四種準心的線段外移</h1><p>使用遊戲的原準心貼圖與正式分段程式，於透明的 320×320 Godot Compatibility 畫布擷取。貼圖像素與螢幕像素維持 1:1，外側片段固定向外移動 12 px，方便檢查形狀；實際遊戲的位移依武器與連射散布決定。</p><p>靜止與恢復畫面逐像素比對原 TextureRect，包含透明度。外移前後的透明度總量誤差必須小於 2%，檢查裁切、遺失或重複線段。</p>"""
	for result in results:
		html += "<section><h2>AimID %d</h2><p>靜止：%s · 恢復：%s · 透明度總量誤差：%.3f%% · 中央瞄準點：%s</p><div class='grid'>" % [
			int(result.aim_id), "逐像素一致" if bool(result.idle_rgba_equals_native) else "FAIL",
			"逐像素一致" if bool(result.restored_rgba_equals_native) else "FAIL", float(result.alpha_relative_error) * 100.0,
			"未設定檢查區域" if result.centre_pixels_stable == null else ("位置與像素一致" if bool(result.centre_pixels_stable) else "FAIL")]
		for stage in [{"suffix": "native", "label": "原版 TextureRect"}, {"suffix": "idle", "label": "新版靜止"}, {"suffix": "open", "label": "線段向外移 12 px"}, {"suffix": "recovered", "label": "恢復原間距"}]:
			html += _figure(str(result.stem) + "_" + str(stage.suffix) + ".png", str(stage.label))
		html += "</div></section>"
	html += "</main></html>"
	var file := FileAccess.open(OUTPUT + mode + "_segment_shapes.html", FileAccess.WRITE)
	file.store_string(html)
	file.close()
	print("HIP_RETICLE_SHAPES_%s mode=%s aim_ids=%d" % ["FAIL" if failed else "PASS", mode, results.size()])


func _read_shape_viewport(shape_viewport: SubViewport, stem: String) -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := shape_viewport.get_texture().get_image()
	if image.is_empty() or image.get_size() != shape_viewport.size:
		failed = true
		push_error("Failed shape capture: " + stem)
		return Image.new()
	image.convert(Image.FORMAT_RGBA8)
	if image.save_png(OUTPUT + stem + ".png") != OK:
		failed = true
		push_error("Failed to save shape capture: " + stem)
	return image


func _alpha_mass(image: Image) -> int:
	var pixels := image.get_data()
	var total := 0
	for index in range(3, pixels.size(), 4):
		total += int(pixels[index])
	return total


func _sight_pixels_match(reference: Image, opened: Image, center: Vector2i, radius: int) -> bool:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if Vector2i(x, y).distance_squared_to(center) <= radius * radius and reference.get_pixel(x, y) != opened.get_pixel(x, y):
				return false
	return true


func _write_preview(mode: String) -> void:
	var html := """<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>腰射連射散布對照</title>
<style>body{margin:0;padding:32px;background:#10161d;color:#e7edf2;font:16px/1.6 system-ui}main{max-width:1600px;margin:auto}h1{margin:0}p{color:#a9bbc9}section{margin:32px 0;border-top:1px solid #33424f;padding-top:16px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}figure{margin:0}img{width:100%;background:#06090c;border:1px solid #33424f}figcaption{color:#a9bbc9;font-size:14px}a{color:#8ed8e8}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:6px 12px 6px 0;border-bottom:1px solid #26323c}th{color:#8ea3b4;font-weight:500}td{font-variant-numeric:tabular-nums}</style><main><h1>腰射連射散布</h1>
<p>只有步槍的準心線段會展開：單發略微拉開，連射逐發累積；停火後先慢速收回，再逐漸加快。線條長度、厚度與中央瞄準點保持原樣。TSG-03 霰彈槍與 LG002B 雷射機槍即使連射，也維持原準心圖案。</p><p>以下為 Godot Compatibility 的 1280×720 實際畫面，取中央 320×320 作比較。兩張收回中的照片相隔同樣的 0.12 秒，方便比較收回速度。點圖可看原尺寸。</p>"""
	html += "<p><a href='" + mode + "_segment_shapes.html'>查看全部十四種準心的原圖、外移與恢復比對</a></p>"
	for weapon_id: String in WEAPONS:
		html += "<section><h2>" + str(GameState.WEAPONS[weapon_id].name).xml_escape() + " · " + weapon_id + "</h2>"
		html += "<p>" + ("步槍：每次成功射擊增加 12% 展開量，停火 0.08 秒後逐漸加快收回。" if int(GameState.WEAPONS[weapon_id].type) in [1, 23] else "此武器不啟用準心展開；射擊與停火期間沿用原圖。") + "</p>"
		html += "<div class='grid'>"
		for capture in captures:
			if str(capture.weapon) != weapon_id:
				continue
			html += _figure(str(capture.path).trim_suffix(".png") + "_reticle.png",
				"%s · 展開 %.0f%% · 線段向外 %.1f / %.1f px" % [str(capture.label), float(capture.visual_spread_ratio) * 100.0, float(capture.segment_offset_px[0]), float(capture.segment_offset_px[1])])
		html += "</div></section>"
	html += "<section><h2>逐張數值</h2><p>線段位移為各外側片段相對起始位置的水平／垂直距離；貼圖像素比例固定。準心視覺展開與既有彈道散布分別記錄，停火收回不會改變武器的彈丸設定。</p><table><tr><th>畫面</th><th>武器</th><th>彈道散布</th><th>準心展開</th><th>線段向外位移</th><th>貼圖像素比例</th><th>聚焦中</th></tr>"
	for capture in captures:
		html += "<tr><td>%s</td><td>%s</td><td>%.3f°</td><td>%.0f%%</td><td>%.2f / %.2f px</td><td>%.4f</td><td>%s</td></tr>" % [
			str(capture.label).xml_escape(), str(capture.weapon),
			float(capture.spread_degrees), float(capture.visual_spread_ratio) * 100.0,
			float(capture.segment_offset_px[0]), float(capture.segment_offset_px[1]),
			float(capture.source_scale), "是" if bool(capture.focus_aiming) else "否"]
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
