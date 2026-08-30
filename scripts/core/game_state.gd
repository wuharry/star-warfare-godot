extends Node

signal settings_changed
signal loadout_changed

const SAVE_PATH := "user://star_warfare_save.json"
const CAMPAIGN_LEVELS := [1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21]

# Recovered verbatim from Resources/UI/resDataSets.bytes, table 13.  The old
# game used one shared energy pool rather than conventional magazines.
# id, name, damage, cooldown seconds, energy, type, bomb radius, splash damage,
# unlock level, aim id, display order, price, mithril.
const WEAPON_ROWS := [
	[0, "FR28a", 20.0, 0.24, 5, 1, 0.0, 0.0, 0, 0, 1, 15000, 0],
	[1, "MA72", 30.0, 0.23, 7, 1, 0.0, 0.0, 0, 0, 2, 25000, 0],
	[2, "MS06", 36.0, 0.20, 8, 1, 0.0, 0.0, 0, 0, 3, 40000, 6],
	[3, "FR43C", 48.0, 0.23, 11, 1, 0.0, 0.0, 1, 0, 4, 70000, 0],
	[4, "FL334AR", 68.0, 0.25, 14, 1, 0.0, 0.0, 2, 0, 5, 150000, 0],
	[5, "TB10-LW", 100.0, 0.24, 18, 1, 0.0, 0.0, 3, 0, 6, 280000, 30],
	[6, "TSG-03", 90.0, 0.85, 18, 2, 5.0, 0.0, 0, 2, 11, 20000, 0],
	[7, "SD58", 130.0, 0.95, 22, 2, 7.0, 0.0, 0, 11, 12, 45000, 0],
	[8, "WD03S", 170.0, 0.75, 26, 2, 4.0, 0.0, 1, 10, 13, 85000, 7],
	[9, "S92M", 260.0, 1.05, 32, 2, 9.0, 0.0, 2, 12, 14, 150000, 0],
	[10, "T740", 320.0, 0.90, 50, 2, 7.0, 0.0, 3, 2, 15, 260000, 23],
	[11, "RPG-21", 250.0, 1.40, 120, 3, 7.0, 0.0, 3, 1, 21, 300000, 0],
	[12, "RPG-24", 450.0, 1.70, 220, 3, 9.0, 0.0, 4, 1, 22, 1100000, 0],
	[13, "RPG-31", 750.0, 1.20, 350, 3, 8.5, 0.0, 5, 1, 23, 3500000, 280],
	[14, "Vox-07", 80.0, 0.50, 20, 4, 3.0, 0.0, 1, 3, 31, 150000, 0],
	[15, "M347", 192.0, 0.45, 50, 4, 3.0, 0.0, 2, 3, 32, 600000, 0],
	[16, "Ge09x", 220.0, 0.45, 60, 4, 3.5, 0.0, 4, 3, 33, 950000, 80],
	[17, "LG002B", 50.0, 0.30, 22, 5, 0.0, 0.0, 2, 6, 41, 85000, 8],
	[18, "M2456s", 90.0, 0.30, 30, 5, 0.0, 0.0, 3, 6, 42, 320000, 0],
	[19, "NOVA27", 140.0, 0.25, 45, 5, 0.0, 0.0, 4, 6, 43, 750000, 0],
	[20, "Plasma Neo", 90.0, 0.35, 35, 7, 0.0, 20.0, 1, 4, 51, 400000, 0],
	[21, "Laser Cannon", 300.0, 0.20, 100, 8, 0.0, 0.0, 5, 7, 61, 4000000, 320],
	[22, "Light Bow", 100.0, 0.50, 40, 9, 3.0, 0.0, 1, 9, 71, 300000, 28],
	[23, "Energy Glove", 250.0, 0.50, 60, 10, 4.0, 0.0, 3, 8, 76, 2300000, 180],
	[24, "MCP76", 120.0, 0.20, 15, 11, 0.0, 0.0, 2, 5, 81, 400000, 0],
	[25, "M-27B1", 200.0, 0.17, 40, 11, 0.0, 0.0, 4, 5, 82, 1400000, 0],
	[26, "LIT07", 190.0, 0.28, 65, 5, 0.0, 0.0, 6, 6, 44, 1350000, 95],
	[27, "Cutter", 60.0, 0.30, 0, 12, 0.0, 0.0, 0, 0, 91, 25000, 0],
	[28, "Passer", 200.0, 0.30, 0, 12, 0.0, 0.0, 3, 0, 92, 450000, 35],
	[29, "Trinity", 150.0, 0.65, 130, 13, 2.5, 0.0, 4, 9, 72, 2500000, 200],
	[30, "BLACK STARS", 240.0, 1.80, 280, 14, 7.0, 0.0, 5, 1, 24, 2700000, 220],
	[31, "Crab", 200.0, 0.30, 90, 7, 0.0, 40.0, 6, 4, 52, 3600000, 0],
	[32, "Morpheus", 800.0, 1.00, 100, 15, 0.0, 100.0, 6, 2, 101, 2200000, 0],
	[33, "WINDBLADE", 250.0, 0.30, 0, 16, 0.0, 0.0, 4, 0, 93, 800000, 65],
	[34, "R100-RAILGUN", 1000.0, 1.50, 120, 17, 0.0, 0.0, 4, 13, 110, 2000000, 0],
	[35, "R700-AA", 1400.0, 1.40, 150, 18, 0.0, 0.0, 5, 13, 111, 2500000, 190],
	[36, "WHITE DRILL", 180.0, 0.50, 45, 19, 2.0, 0.0, 8, 14, 121, 160000, 166],
	[37, "BLACK DISK", 760.0, 1.50, 280, 20, 4.0, 0.0, 8, 15, 126, 2200000, 0],
	[38, "XMAX-TREE", 176.0, 0.20, 16, 8, 0.0, 20.0, 5, 7, 127, 2800000, 210],
	[39, "M-Z7B2", 275.0, 0.17, 80, 21, 0.0, 0.0, 6, 5, 83, 4400000, 320],
	[40, "AST-KK", 150.0, 0.15, 55, 23, 0.0, 0.0, 5, 0, 7, 1800000, 0],
	[41, "J.O.K.E", 270.0, 0.40, 120, 24, 4.0, 0.0, 6, 3, 34, 4200000, 238],
	[42, "Spring", 30.0, 0.60, 180, 40, 2.0, 0.0, 6, 10, 122, 1600000, 77],
	[43, "Reflection", 1200.0, 1.50, 220, 41, 0.0, 0.0, 7, 13, 112, 2700000, 230],
	[44, "TheArrow", 210.0, 0.50, 200, 42, 3.5, 20.0, 0, 9, 73, 2200000, 0],
	[45, "U.F.O", 300.0, 1.50, 330, 43, 4.0, 0.0, 7, 3, 35, 4200000, 228],
	[46, "Spreader", 850.0, 1.00, 100, 15, 0.0, 100.0, 6, 2, 102, 3300000, 0]
]

var WEAPONS: Dictionary = {}
var battle_weapons: Array[String] = ["gun00", "gun06", "gun11", "gun14", "gun17", "gun20", "gun24", "gun27"]

var selected_level := 1
var selected_weapon := "gun00"
var unlocked_level := 1
var credits := 0
var best_scores: Dictionary = {}
var settings := {
	"music": 0.72,
	"sfx": 0.85,
	"look_sensitivity": 0.24,
	"invert_y": false,
	"show_touch_controls": false
}

func _ready() -> void:
	_build_weapon_database()
	_configure_input_map()
	_load_save()
	settings.show_touch_controls = bool(settings.show_touch_controls) or _device_prefers_touch()
	_apply_audio_settings()

func _build_weapon_database() -> void:
	WEAPONS.clear()
	for row: Array in WEAPON_ROWS:
		var weapon_id := "gun%02d" % int(row[0])
		var type_id := int(row[5])
		var profile := _weapon_profile(type_id, int(row[0]), str(row[1]))
		var cooldown := maxf(0.05, float(row[3]))
		WEAPONS[weapon_id] = {
			"id": int(row[0]), "name": str(row[1]), "damage": float(row[2]),
			"cooldown": cooldown, "fire_rate": 1.0 / cooldown,
			"energy": int(row[4]), "type": type_id,
			"splash": float(row[6]), "splash_damage": float(row[7]),
			"unlock": int(row[8]), "aim_id": int(row[9]), "display_order": int(row[10]),
			"price": int(row[11]), "mithril": int(row[12]),
			"pellets": profile.pellets, "range": profile.range,
			"spread": profile.spread, "automatic": profile.automatic,
			"kind": profile.kind, "speed": profile.speed,
			"animation": profile.animation, "sound": profile.sound,
			"sound_variants": profile.sound_variants,
			"swing_sounds": profile.swing_sounds, "hit_sounds": profile.hit_sounds,
			"blank_sound": profile.blank_sound,
			"loop_sound": profile.loop_sound, "stop_sound": profile.stop_sound,
			"explosion_sound": profile.explosion_sound, "color": profile.color,
			"model": weapon_id
		}

func _weapon_profile(type_id: int, gun_id: int, weapon_name: String) -> Dictionary:
	var profile := {
		"pellets": 1, "range": 105.0, "spread": 0.012, "automatic": false,
		"kind": "hitscan", "speed": 24.0, "animation": "rifle",
		"sound": "", "sound_variants": [], "swing_sounds": [], "hit_sounds": [],
		"blank_sound": "blank/blank_shot01.wav",
		"loop_sound": "", "stop_sound": "",
		"explosion_sound": "", "color": Color(0.16, 0.82, 1.0)
	}
	match type_id:
		1, 23:
			profile.automatic = true
			profile.sound = "assault_rifle/%s_FiringSound.wav" % weapon_name
		5:
			profile.automatic = true
			profile.kind = "laser"
			profile.spread = 0.004
			profile.sound = "lasergun/laser_rifle_fire.wav"
			profile.color = Color(0.12, 0.72, 1.0)
		7:
			profile.automatic = true
			profile.kind = "plasma"
			profile.sound = "specialweapon/plasma_gun.wav"
			profile.color = Color(0.18, 1.0, 0.62)
		8:
			profile.automatic = true
			profile.kind = "snow" if gun_id == 38 else "beam"
			profile.animation = "rifle" if gun_id == 38 else "laser"
			profile.sound = ""
			profile.loop_sound = "snowgun/Snow_Start.wav" if gun_id == 38 else "lasergun/laser_fire.wav"
			profile.color = Color(0.55, 0.9, 1.0) if gun_id == 38 else Color(1.0, 0.12, 0.08)
		2:
			profile.pellets = 8
			profile.range = 42.0
			profile.spread = 0.055
			profile.animation = "shotgun"
			profile.sound = "shotgun/%s_FiringSound.wav" % weapon_name
			profile.blank_sound = "blank/blank_shot02.wav"
			profile.stop_sound = "shotgun/ShotgunCock01.wav"
			profile.color = Color(1.0, 0.54, 0.12)
		15:
			profile.pellets = 12
			profile.range = 48.0
			profile.spread = 0.075
			profile.kind = "shockwave"
			profile.animation = "shotgun"
			profile.sound = "shotgun/MORPHEUS.wav"
			profile.blank_sound = "blank/blank_shot02.wav"
			profile.color = Color(0.75, 0.2, 1.0)
		3, 14:
			profile.kind = "rocket"
			profile.speed = 16.0
			profile.animation = "BLACKSTARS" if type_id == 14 else "bazinga"
			profile.sound = "rpg/rpg-31_FiringSound.wav" if type_id == 14 else "rpg/%s_FiringSound.wav" % weapon_name.to_lower()
			profile.explosion_sound = "rpg/rpg-31_boom.wav" if type_id == 14 else "rpg/%s_boom.wav" % weapon_name.to_lower()
			profile.color = Color(1.0, 0.18, 0.04)
		4, 24, 43:
			profile.kind = "fly_grenade" if type_id == 43 else "grenade"
			profile.speed = 20.0
			profile.animation = "grenade_launcher"
			profile.sound = "gl/grenade_launcher_fire.wav"
			profile.explosion_sound = "gl/grenade_launcher_boom.wav"
			profile.color = Color(0.55, 1.0, 0.16)
		9, 13, 42:
			profile.kind = "arrow"
			profile.speed = 22.0
			profile.animation = "bow"
			profile.sound = "specialweapon/lightbow_shot.wav"
			profile.color = Color(0.18, 1.0, 0.86)
		10:
			profile.kind = "energy_fist"
			profile.speed = 22.0
			profile.animation = "fist"
			profile.sound = "specialweapon/energy_glove_fire.wav"
			profile.color = Color(0.25, 0.62, 1.0)
		11, 21:
			profile.kind = "machinegun"
			profile.automatic = true
			profile.animation = "machinegun"
			profile.sound = "machinegun/%s_FiringSound_01.wav" % weapon_name
			profile.loop_sound = "machinegun/%s_FiringSound_02.wav" % weapon_name
			profile.stop_sound = "machinegun/%s_FiringSound_03.wav" % weapon_name
			profile.color = Color(1.0, 0.72, 0.08)
		12, 16:
			profile.kind = "sword"
			profile.range = 3.1
			profile.animation = "jian"
			if type_id == 16:
				profile.sound = "light_sword/windblade.wav"
			else:
				profile.swing_sounds = ["light_sword/light_sword_swing01.wav", "light_sword/light_sword_swing02.wav"]
				profile.hit_sounds = ["light_sword/light_sword01.wav", "light_sword/light_sword02.wav", "light_sword/light_sword03.wav"]
			profile.color = Color(0.25, 0.9, 1.0)
		17, 18, 41:
			profile.kind = "reflection" if type_id == 41 else "sniper"
			profile.range = 180.0
			profile.spread = 0.0
			profile.animation = "Sniper"
			profile.sound = "sniper/r100_railgun.wav"
			profile.color = Color(0.75, 0.2, 1.0)
		19:
			profile.kind = "tracking"
			profile.speed = 11.0
			profile.animation = "fist"
			profile.sound = "diablo/nailgun_fire.wav"
			profile.color = Color(1.0, 0.18, 0.7)
		20:
			profile.kind = "ricochet"
			profile.speed = 12.0
			profile.animation = "grenade_launcher"
			profile.sound_variants = ["diablo/black_disk_fire01.wav", "diablo/black_disk_fire02.wav"]
			profile.explosion_sound = "rpg/rpg-31_boom.wav"
			profile.color = Color(0.85, 0.12, 1.0)
		40:
			profile.kind = "spring"
			profile.speed = 11.0
			profile.animation = "fist"
			profile.sound = "diablo/nailgun_fire.wav"
			profile.color = Color(0.2, 1.0, 0.35)
	return profile

func _device_prefers_touch() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

func _configure_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("reload", KEY_R)
	_add_key_action("dash", KEY_SHIFT)
	_add_key_action("pause", KEY_ESCAPE)
	_add_key_action("weapon_1", KEY_1)
	_add_key_action("weapon_2", KEY_2)
	_add_key_action("weapon_3", KEY_3)
	_add_key_action("weapon_4", KEY_4)
	_add_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_add_mouse_action("aim", MOUSE_BUTTON_RIGHT)
	_add_mouse_action("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_action("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_button("fire", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("aim", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("reload", JOY_BUTTON_X)
	_add_joy_button("dash", JOY_BUTTON_LEFT_STICK)
	_add_joy_button("pause", JOY_BUTTON_START)

func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

func _add_key_action(action: StringName, keycode: Key) -> void:
	_ensure_action(action)
	for old_event in InputMap.action_get_events(action):
		if old_event is InputEventKey and old_event.physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)

func _add_mouse_action(action: StringName, button: MouseButton) -> void:
	_ensure_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure_action(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)

func _add_joy_button(action: StringName, button: JoyButton) -> void:
	_ensure_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func start_level(level_number: int) -> void:
	selected_level = level_number
	_save()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func return_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func set_weapon(weapon_id: String) -> void:
	if WEAPONS.has(weapon_id):
		selected_weapon = weapon_id
		_save()
		loadout_changed.emit()

func get_weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for weapon_id: String in WEAPONS:
		ids.append(weapon_id)
	ids.sort_custom(func(a: String, b: String): return int(WEAPONS[a].display_order) < int(WEAPONS[b].display_order))
	return ids

func complete_level(level_number: int, score: int, earned_credits: int) -> void:
	credits += max(0, earned_credits)
	best_scores[str(level_number)] = max(score, int(best_scores.get(str(level_number), 0)))
	var index := CAMPAIGN_LEVELS.find(level_number)
	if index >= 0 and index + 1 < CAMPAIGN_LEVELS.size():
		unlocked_level = max(unlocked_level, int(CAMPAIGN_LEVELS[index + 1]))
	_save()

func get_level_data(level_number: int) -> Dictionary:
	var index: int = maxi(0, CAMPAIGN_LEVELS.find(level_number))
	var boss_level := level_number in [8, 13, 16, 19, 21]
	var palettes := [
		[Color("17283c"), Color("42647b"), Color("8ed1e8")],
		[Color("33231d"), Color("89543b"), Color("e4a96b")],
		[Color("172d26"), Color("406a4c"), Color("a4d77f")],
		[Color("262039"), Color("62507d"), Color("c39ce5")],
		[Color("152b35"), Color("356e7d"), Color("72d6d1")]
	]
	var names := {
		1: "OUTPOST ZERO", 2: "DUST LINE", 3: "INFESTED DEPOT", 4: "FROZEN ARRAY",
		5: "ACID TRENCH", 6: "BROKEN CAUSEWAY", 7: "ALIEN HIVE", 8: "MANTIS NEST",
		13: "IRON WASTELAND", 14: "CRIMSON DOCK", 15: "FALLEN CITY", 16: "EARTHWORM PIT",
		17: "SKY FORT", 18: "BLACK ICE", 19: "DRAGON RUINS", 20: "SATAN WORKSHOP", 21: "FINAL BREACH"
	}
	return {
		"number": level_number,
		"name": names.get(level_number, "UNKNOWN SECTOR"),
		"waves": 3 + int(index / 3) + (1 if boss_level else 0),
		"base_enemies": 4 + index,
		"enemy_health": 52.0 + index * 9.0,
		"boss": boss_level,
		"palette": palettes[index % palettes.size()],
		"arena_size": 29.0 + min(index * 0.55, 8.0)
	}

func set_setting(key: String, value: Variant) -> void:
	if settings.has(key):
		settings[key] = value
		_apply_audio_settings()
		_save()
		settings_changed.emit()

func _apply_audio_settings() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_volume_db(master, 0.0)
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(clampf(float(settings.music), 0.001, 1.0)))
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(clampf(float(settings.sfx), 0.001, 1.0)))

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	selected_level = int(parsed.get("selected_level", selected_level))
	selected_weapon = str(parsed.get("selected_weapon", selected_weapon))
	if not WEAPONS.has(selected_weapon):
		selected_weapon = "gun00"
	unlocked_level = int(parsed.get("unlocked_level", unlocked_level))
	credits = int(parsed.get("credits", credits))
	best_scores = parsed.get("best_scores", best_scores)
	var stored_settings = parsed.get("settings", {})
	if stored_settings is Dictionary:
		for key in stored_settings:
			if settings.has(key):
				settings[key] = stored_settings[key]

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var data := {
		"selected_level": selected_level,
		"selected_weapon": selected_weapon,
		"unlocked_level": unlocked_level,
		"credits": credits,
		"best_scores": best_scores,
		"settings": settings
	}
	file.store_string(JSON.stringify(data, "\t"))
