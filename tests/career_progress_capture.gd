extends Node
## Run with -- --test-profile=career_capture_unique. Only in-memory fixture data.

const CareerData = preload("res://scripts/core/career_progress.gd")
const PanelScript = preload("res://scripts/ui/career_panel.gd")


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if not str(GameState.save_path).begins_with("user://star_warfare_test_"):
		push_error("CAREER_CAPTURE requires isolated --test-profile= argument")
		get_tree().quit(1)
		return
	var compact := OS.get_cmdline_user_args().has("--career-compact")
	var target_size := Vector2i(720, 480) if compact else Vector2i(1280, 720)
	get_tree().root.size = target_size
	get_tree().root.content_scale_size = target_size
	var career := CareerData.new()
	career.load_data({"stats": {"enemy_kills": 248, "team_kills": 82, "max_combo": 14,
		"credits_spent": 458000, "full_upgrades": 2, "suits_collected": 3,
		"multiplayer_sessions": 6, "revivals": 4, "wins": 12, "losses": 3,
		"flawless_wins": 2, "high_score": 18420, "high_kills": 92, "campaign_first": 1},
		"boss_kills": [6, 10, 1], "best_scores": {"CAMPAIGN 1": 18420, "CAMPAIGN 2": 13580, "SURVIVAL 1": 9210}})
	var panel := PanelScript.new()
	add_child(panel)
	panel.show_progress(career)
	for index in range(2):
		panel.tabs.current_tab = index
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picture := get_viewport().get_texture().get_image()
		var path := "res://tests/career_progress_%s%s_preview.png" % ["stats" if index == 0 else "achievements", "_compact" if compact else ""]
		var result := picture.save_png(path)
		if result != OK:
			push_error("CAREER_CAPTURE failed: " + error_string(result))
			get_tree().quit(1)
			return
		print("CAREER_CAPTURE: %s %s" % [path, target_size])
	get_tree().quit()
