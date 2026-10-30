extends Node

func _ready() -> void:
	NetworkSession.auto_change_scene = false
	Localization.apply_locale("zh_TW")
	GameState.settings.show_touch_controls = false
	var menu := preload("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	menu._show_multiplayer()
	for frame in range(20): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	var error := shot.save_png("res://test_output/network_lobby.png")
	if error != OK:
		push_error("Network lobby capture failed")
		get_tree().quit(1)
		return
	var scrolls: Array[Node] = menu.modal_layer.find_children("*", "ScrollContainer", true, false)
	if not scrolls.is_empty():
		scrolls[0].scroll_vertical = 10000
		for frame in range(8): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://test_output/network_lobby_bottom.png")
		var lobby: Node = menu.modal_layer.find_child("DirectConnectLobby", true, false)
		var bounds: Rect2 = lobby.start_button.get_global_rect()
		if not get_viewport().get_visible_rect().intersects(bounds):
			push_error("Scrolled lobby start button is outside the viewport")
			get_tree().quit(1)
			return
	menu._close_modal()
	menu._show_solo_missions(1)
	for frame in range(8): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	shot = get_viewport().get_texture().get_image()
	error = shot.save_png("res://test_output/network_solo_menu.png")
	menu.queue_free()
	await get_tree().process_frame
	print("NETWORK_VISUAL_CAPTURE_%s viewport=1280x720 renderer=GL Compatibility" % ("PASS" if error == OK else "FAIL"))
	get_tree().quit(0 if error == OK else 1)
