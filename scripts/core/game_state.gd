extends Node

signal settings_changed
signal loadout_changed
signal store_changed
signal armor_changed(part_key: String, armor_key: String)

const SAVE_PATH := "user://star_warfare_save.json"
const SAVE_VERSION := 3
const ArmorCatalogData = preload("res://scripts/core/armor_catalog.gd")
const PropsCatalogData = preload("res://scripts/core/props_catalog.gd")
const SINGLEPLAYER_LEVELS := [1, 2, 3, 4, 5, 6, 7, 8]
const MULTIPLAYER_LEVELS := [13, 14, 15, 16, 17, 18, 19, 20, 21]
const CAMPAIGN_LEVELS := [1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21]
const LOADOUT_MAX_SLOTS := 8

# Testing switch: every singleplayer sector is selectable regardless of
# progress, so any map can be jumped into directly. unlocked_level is still
# tracked and still advances on completion, so flipping this back to false
# restores the real progression without losing anyone's place.
const CAMPAIGN_FULLY_UNLOCKED := true

# Tests and portable builds may point an instance at an isolated save without
# changing the production user:// location. Anything that mutates settings and
# then lets the game save — the visual captures pin the clock to shoot a
# reproducible sunset — must redirect here first, or it freezes the real
# player's sky for good.
const TEST_SAVE_PATH := "user://star_warfare_test_profile.json"
var save_path := SAVE_PATH

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
var battle_weapons: Array[String] = ["gun00"]
var owned_weapons: Array[String] = ["gun00"]
var ARMOR_ITEMS: Dictionary = {}
var ARMOR_SET_BONUSES: Dictionary = {}
var owned_armor: Array[String] = []
var equipped_armor: Dictionary = {}
var PROPS: Dictionary = {}
var owned_props: Dictionary = {}

# Three graphics presets. render_scale drives the root viewport's 3D
# resolution (the biggest lever after the 2x texture upscale), while shadows,
# glow and fog are read by the level when it builds its environment.
const QUALITY_PROFILES := {
	"low": {"render_scale": 0.7, "msaa": Viewport.MSAA_DISABLED, "shadows": false, "glow": false, "fog": false, "sky": false},
	"medium": {"render_scale": 0.85, "msaa": Viewport.MSAA_2X, "shadows": true, "glow": true, "fog": true, "sky": true},
	"high": {"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "shadows": true, "glow": true, "fog": true, "sky": true},
}
const QUALITY_ORDER := ["low", "medium", "high"]


# Three combat tiers. "recruit" is the original beeline AI kept untouched so the
# old balance stays playable; "veteran" and "elite" switch enemies over to the
# tactical brain in enemy.gd (flanking, attack tokens, telegraphed strikes,
# predictive fire). Every field is a behaviour knob, not a stat multiplier —
# the difficulty comes from how the pack fights, not from inflated numbers.
const DIFFICULTY_PROFILES := {
	"recruit": {
		"tactical": false,
		"reaction": 0.0,
		"aim_lead": 0.0,
		"aim_spread": 0.0,
		"melee_windup": 0.0,
		"attack_slots": 99,
		"flank_spread": 0.0,
		"separation": 0.0,
		"strafe": 0.0,
		"suppression": 0.0,
		"sight_check": false,
		"attack_speed": 1.0,
	},
	"veteran": {
		"tactical": true,
		"reaction": 0.42,
		"aim_lead": 0.7,
		"aim_spread": 0.055,
		"melee_windup": 0.34,
		"attack_slots": 2,
		"flank_spread": 0.7,
		"separation": 1.9,
		"strafe": 0.55,
		"suppression": 0.5,
		"sight_check": true,
		"attack_speed": 0.92,
	},
	"elite": {
		"tactical": true,
		"reaction": 0.18,
		"aim_lead": 1.0,
		"aim_spread": 0.018,
		"melee_windup": 0.24,
		"attack_slots": 3,
		"flank_spread": 1.0,
		"separation": 2.4,
		"strafe": 0.95,
		"suppression": 0.8,
		"sight_check": true,
		"attack_speed": 0.82,
	},
}
const DIFFICULTY_ORDER := ["recruit", "veteran", "elite"]

var selected_level := 1
var selected_weapon := "gun00"
var selected_game_mode := "singleplayer"
var unlocked_level := 1
var credits := 0
var mithril := 0
var best_scores: Dictionary = {}

var settings := {
	"music": 0.72,
	"sfx": 0.85,
	"look_sensitivity": 0.24,
	"invert_y": false,
	"show_touch_controls": false,
	"quality": "high",
	"difficulty": "veteran",
	"language": "",
	"nickname": "PLAYER"
}

func _ready() -> void:
	_build_weapon_database()
	_build_armor_database()
	_build_props_database()
	_configure_input_map()
	_load_save()
	settings.show_touch_controls = bool(settings.show_touch_controls) or _device_prefers_touch()
	_apply_audio_settings()
	apply_viewport_quality()

func _build_armor_database() -> void:
	ARMOR_ITEMS = ArmorCatalogData.build_items()
	ARMOR_SET_BONUSES = ArmorCatalogData.build_set_bonuses()
	if equipped_armor.is_empty():
		equipped_armor = _default_armor_equipment()
	if owned_armor.is_empty():
		owned_armor = _default_owned_armor()

func _build_props_database() -> void:
	PROPS = PropsCatalogData.build_items()

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
			"tracer_style": profile.tracer_style, "tracer_every": profile.tracer_every,
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
		# The original rifle/laser/machine-gun families fire through the exact
		# camera-centre ray. Enemy collision volumes provide the mobile-friendly
		# tolerance; a generic random cone made an apparently centred shot miss.
		"pellets": 1, "range": 105.0, "spread": 0.0, "automatic": false,
		"kind": "hitscan", "speed": 24.0, "animation": "rifle",
		"tracer_style": "legacy", "tracer_every": 1,
		"sound": "", "sound_variants": [], "swing_sounds": [], "hit_sounds": [],
		"blank_sound": "blank/blank_shot01.wav",
		"loop_sound": "", "stop_sound": "",
		"explosion_sound": "", "color": Color(0.16, 0.82, 1.0)
	}
	match type_id:
		1, 23:
			profile.automatic = true
			profile.sound = "assault_rifle/%s_FiringSound.wav" % weapon_name
			profile.tracer_style = "rifle"
			profile.tracer_every = 3
			profile.color = Color(1.0, 0.64, 0.08)
		5:
			profile.automatic = true
			profile.kind = "laser"
			profile.sound = "lasergun/laser_rifle_fire.wav"
			profile.tracer_style = "laser"
			profile.tracer_every = 1
			profile.color = Color(0.08, 0.78, 1.0)
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
			profile.tracer_style = "machinegun"
			profile.tracer_every = 5
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
			profile.tracer_style = "sniper_legacy_hd"
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
	_add_mouse_action("weapon_previous", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_action("weapon_next", MOUSE_BUTTON_WHEEL_DOWN)
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

func start_level(level_number: int, game_mode: String = "") -> void:
	if game_mode in ["singleplayer", "multiplayer"]:
		selected_game_mode = game_mode
	var available_levels := get_levels_for_mode(selected_game_mode)
	if not available_levels.has(level_number):
		return
	if not is_level_unlocked(level_number, selected_game_mode):
		return
	selected_level = level_number
	_save()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func start_expanse() -> void:
	# THE EXPANSE is not a campaign sector, so selected_game_mode is left alone:
	# the armoury, the store and the level select all keep working off whichever
	# campaign mode the player was last in.
	_save()
	get_tree().change_scene_to_file("res://scenes/expanse.tscn")

func complete_expanse_run(run_score: int, earned_credits: int) -> void:
	# An expedition has no victory condition, so this banks whatever the run
	# earned whenever it ends: death, or walking out through the pause menu.
	var money_multiplier := 1.0 + float(get_armor_skills().get("money_boost", 0.0))
	credits += maxi(0, roundi(float(earned_credits) * maxf(0.0, money_multiplier)))
	best_scores["expanse"] = max(run_score, int(best_scores.get("expanse", 0)))
	store_changed.emit()
	_save()

func is_level_unlocked(level_number: int, game_mode: String = "") -> bool:
	# Multiplayer maps were never gated; only the campaign runs on progress.
	var mode := game_mode if not game_mode.is_empty() else selected_game_mode
	if mode != "singleplayer":
		return true
	return CAMPAIGN_FULLY_UNLOCKED or level_number <= unlocked_level

func get_levels_for_mode(game_mode: String) -> Array:
	return MULTIPLAYER_LEVELS if game_mode == "multiplayer" else SINGLEPLAYER_LEVELS

func return_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func set_weapon(weapon_id: String) -> void:
	if WEAPONS.has(weapon_id):
		selected_weapon = weapon_id
		_save()
		loadout_changed.emit()

func set_loadout_weapon(slot: int, weapon_id: String) -> bool:
	if slot < 0 or slot >= LOADOUT_MAX_SLOTS or slot > battle_weapons.size() or not is_weapon_owned(weapon_id):
		return false
	# Unity bags define how many new weapon slots may be filled. Existing saves
	# that predate armor can keep their larger loadout; equipping a smaller bag
	# must never discard weapons the player already earned.
	if slot == battle_weapons.size() and slot >= get_bag_capacity():
		return false
	var old_index := battle_weapons.find(weapon_id)
	if old_index == slot:
		selected_weapon = weapon_id
		_save()
		loadout_changed.emit()
		return true
	if old_index >= 0 and slot < battle_weapons.size():
		# Moving an equipped weapon to another occupied Unity bag slot swaps the
		# two positions, so the displaced weapon is not silently lost.
		var displaced_weapon := battle_weapons[slot]
		battle_weapons[slot] = weapon_id
		battle_weapons[old_index] = displaced_weapon
	elif old_index >= 0:
		battle_weapons.remove_at(old_index)
		battle_weapons.append(weapon_id)
	elif slot < battle_weapons.size():
		battle_weapons[slot] = weapon_id
	else:
		battle_weapons.append(weapon_id)
	_normalize_store_state()
	selected_weapon = weapon_id
	_save()
	loadout_changed.emit()
	store_changed.emit()
	return true

func is_weapon_owned(weapon_id: String) -> bool:
	return owned_weapons.has(weapon_id)

func get_rank_id() -> int:
	# The Unity store exposes weapon UnlockLevel as a zero-based rank. The
	# restoration advances one local rank with each unlocked solo sector. Rank
	# 8 is awarded when the final solo sector is completed, not merely opened.
	var rank_id := clampi(unlocked_level - 1, 0, 8)
	if best_scores.has(str(SINGLEPLAYER_LEVELS[-1])):
		rank_id = maxi(rank_id, 8)
	return rank_id

func is_weapon_rank_unlocked(weapon_id: String) -> bool:
	if not WEAPONS.has(weapon_id):
		return false
	return int(WEAPONS[weapon_id].unlock) <= get_rank_id()

func purchase_weapon(weapon_id: String) -> String:
	if not WEAPONS.has(weapon_id):
		return "invalid"
	if is_weapon_owned(weapon_id):
		return "owned"
	if not is_weapon_rank_unlocked(weapon_id):
		return "rank_locked"
	var weapon: Dictionary = WEAPONS[weapon_id]
	var mithril_price := int(weapon.mithril)
	if mithril_price > 0:
		if mithril < mithril_price:
			return "not_enough_mithril"
		mithril -= mithril_price
	else:
		var credit_price := int(weapon.price)
		if credits < credit_price:
			return "not_enough_credits"
		credits -= credit_price
	owned_weapons.append(weapon_id)
	# Unity's store mounts a newly purchased gun immediately in bag slot zero.
	# Ownership of the displaced gun is retained, so this is safe for migrated
	# saves and makes the Store and combat loadout agree without another screen.
	if battle_weapons.is_empty():
		battle_weapons.append(weapon_id)
	else:
		battle_weapons[0] = weapon_id
	selected_weapon = weapon_id
	_normalize_store_state()
	_save()
	loadout_changed.emit()
	store_changed.emit()
	return "purchased"

func get_weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for weapon_id: String in WEAPONS:
		ids.append(weapon_id)
	ids.sort_custom(func(a: String, b: String): return int(WEAPONS[a].display_order) < int(WEAPONS[b].display_order))
	return ids

func get_armor_ids(part: Variant) -> Array[String]:
	var part_key := _armor_part_key(part)
	var ids: Array[String] = []
	if part_key.is_empty():
		return ids
	for armor_key: String in ARMOR_ITEMS:
		if str(ARMOR_ITEMS[armor_key].part_key) == part_key:
			ids.append(armor_key)
	ids.sort_custom(func(a: String, b: String): return int(ARMOR_ITEMS[a].id) < int(ARMOR_ITEMS[b].id))
	return ids

func get_armor_item(armor_key: String) -> Dictionary:
	return ARMOR_ITEMS.get(armor_key, {})

func get_equipped_armor_key(part: Variant) -> String:
	var part_key := _armor_part_key(part)
	return str(equipped_armor.get(part_key, ""))

func is_armor_owned(armor_key: String) -> bool:
	return owned_armor.has(armor_key)

func is_armor_rank_unlocked(armor_key: String) -> bool:
	if not ARMOR_ITEMS.has(armor_key):
		return false
	return int(ARMOR_ITEMS[armor_key].unlock) <= get_rank_id()

func purchase_armor(armor_key: String) -> String:
	if not ARMOR_ITEMS.has(armor_key):
		return "invalid"
	if is_armor_owned(armor_key):
		return "owned"
	if not is_armor_rank_unlocked(armor_key):
		return "rank_locked"
	var item: Dictionary = ARMOR_ITEMS[armor_key]
	var mithril_price := int(item.mithril)
	if mithril_price > 0:
		if mithril < mithril_price:
			return "not_enough_mithril"
		mithril -= mithril_price
	else:
		var credit_price := int(item.price)
		if credits < credit_price:
			return "not_enough_credits"
		credits -= credit_price
	owned_armor.append(armor_key)
	var part_key := str(item.part_key)
	equipped_armor[part_key] = armor_key
	_normalize_armor_state()
	_save()
	armor_changed.emit(part_key, armor_key)
	if part_key == "bag":
		loadout_changed.emit()
	store_changed.emit()
	return "purchased"

func equip_armor(armor_key: String) -> bool:
	if not ARMOR_ITEMS.has(armor_key) or not is_armor_owned(armor_key):
		return false
	var part_key := str(ARMOR_ITEMS[armor_key].part_key)
	if str(equipped_armor.get(part_key, "")) == armor_key:
		return true
	equipped_armor[part_key] = armor_key
	_save()
	armor_changed.emit(part_key, armor_key)
	if part_key == "bag":
		loadout_changed.emit()
	store_changed.emit()
	return true

func get_prop_ids(category_key: String) -> Array[String]:
	return PropsCatalogData.get_ids(category_key)

func get_prop_count(prop_key: String) -> int:
	return maxi(0, int(owned_props.get(prop_key, 0)))

func purchase_prop(prop_key: String) -> String:
	if not PROPS.has(prop_key):
		return "invalid"
	if get_prop_count(prop_key) >= 99:
		return "full"
	var item: Dictionary = PROPS[prop_key]
	var mithril_price := int(item.mithril)
	if mithril_price > 0:
		if mithril < mithril_price:
			return "not_enough_mithril"
		mithril -= mithril_price
	else:
		var credit_price := int(item.price)
		if credits < credit_price:
			return "not_enough_credits"
		credits -= credit_price
	owned_props[prop_key] = get_prop_count(prop_key) + 1
	_normalize_props_state()
	_save()
	store_changed.emit()
	return "purchased"

func equip_armor_set(set_id: int) -> bool:
	if set_id < 0 or set_id >= ArmorCatalogData.SET_NAMES.size():
		return false
	var keys: Array[String] = []
	for part in range(4):
		var armor_key := ArmorCatalogData.item_key(part, set_id)
		if not is_armor_owned(armor_key):
			return false
		keys.append(armor_key)
	for part in range(4):
		var part_key := str(ArmorCatalogData.PART_KEYS[part])
		equipped_armor[part_key] = keys[part]
		armor_changed.emit(part_key, keys[part])
	_save()
	store_changed.emit()
	return true

func get_equipped_set_id() -> int:
	var equipped_set := -1
	for part in range(4):
		var armor_key := get_equipped_armor_key(part)
		if not ARMOR_ITEMS.has(armor_key):
			return -1
		var item_set := int(ARMOR_ITEMS[armor_key].set_id)
		if equipped_set < 0:
			equipped_set = item_set
		elif equipped_set != item_set:
			return -1
	return equipped_set

func get_armor_skills() -> Dictionary:
	var skills: Dictionary = ArmorCatalogData.empty_skills()
	for part_key: String in ArmorCatalogData.PART_KEYS:
		var armor_key := str(equipped_armor.get(part_key, ""))
		if ARMOR_ITEMS.has(armor_key):
			ArmorCatalogData.merge_skills(skills, ARMOR_ITEMS[armor_key].skills)
	var set_id := get_equipped_set_id()
	if set_id >= 0 and ARMOR_SET_BONUSES.has(set_id):
		ArmorCatalogData.merge_skills(skills, ARMOR_SET_BONUSES[set_id].skills)
	return skills

func get_armor_summary() -> Dictionary:
	var set_id := get_equipped_set_id()
	return {
		"skills": get_armor_skills(),
		"full_set_id": set_id,
		"full_set_name": str(ARMOR_SET_BONUSES[set_id].name) if set_id >= 0 else "",
		"bag_slots": get_bag_capacity()
	}

func get_bag_capacity() -> int:
	var bag_key := get_equipped_armor_key("bag")
	if not ARMOR_ITEMS.has(bag_key):
		return 1
	return clampi(int(ARMOR_ITEMS[bag_key].bag_slots), 1, LOADOUT_MAX_SLOTS)

func is_loadout_slot_active(slot: int) -> bool:
	return slot >= 0 and slot < get_bag_capacity()

func _armor_part_key(part: Variant) -> String:
	if part is int:
		var index := int(part)
		return str(ArmorCatalogData.PART_KEYS[index]) if index >= 0 and index < ArmorCatalogData.PART_KEYS.size() else ""
	var part_key := str(part).to_lower()
	return part_key if ArmorCatalogData.PART_KEYS.has(part_key) else ""

func complete_level(level_number: int, score: int, earned_credits: int) -> void:
	var money_multiplier := 1.0 + float(get_armor_skills().get("money_boost", 0.0))
	credits += maxi(0, roundi(float(earned_credits) * maxf(0.0, money_multiplier)))
	best_scores[str(level_number)] = max(score, int(best_scores.get(str(level_number), 0)))
	if selected_game_mode == "singleplayer":
		var index := SINGLEPLAYER_LEVELS.find(level_number)
		if index >= 0 and index + 1 < SINGLEPLAYER_LEVELS.size():
			unlocked_level = max(unlocked_level, int(SINGLEPLAYER_LEVELS[index + 1]))
	store_changed.emit()
	_save()

func get_level_data(level_number: int) -> Dictionary:
	var index: int = maxi(0, CAMPAIGN_LEVELS.find(level_number))
	var is_pvp := level_number in MULTIPLAYER_LEVELS
	var boss_level := level_number == 8
	var palettes := [
		[Color("17283c"), Color("42647b"), Color("8ed1e8")],
		[Color("33231d"), Color("89543b"), Color("e4a96b")],
		[Color("172d26"), Color("406a4c"), Color("a4d77f")],
		[Color("262039"), Color("62507d"), Color("c39ce5")],
		[Color("152b35"), Color("356e7d"), Color("72d6d1")]
	]
	var names := {
		# The original names, read off the level-select thumbnails. They are not in
		# any data table or string file -- the artwork is the only place they
		# survive, baked into each icon's name plate. The solo set is corroborated
		# by the difficulty stars printed beside it, which run 1 to 8 in exactly
		# this order.
		1: "FRONT LINE", 2: "ENERGY CORE", 3: "SPACE STATION", 4: "LAIR",
		5: "TRAINING BASE", 6: "FIRE IN THE HOLE", 7: "STADIUM ARCADIUM", 8: "CRAZY CARNIVAL",
		13: "ANCIENT VISION", 14: "REACTOR", 15: "AIR CRASH", 16: "GARAGE",
		17: "KILL HOUSE", 18: "Y8 FACTORY", 19: "MICROWAVE", 20: "GOLDEN FALL", 21: "BUNKER PARTY"
	}
	return {
		"number": level_number,
		"name": names.get(level_number, "UNKNOWN SECTOR"),
		"mode": "pvp" if is_pvp else "pve",
		"pvp": is_pvp,
		# Maps 13-21 are the original competitive arenas. Keep their recovered
		# geometry available in this offline build, but never reinterpret them as
		# alien-wave missions while networking is still being restored.
		"waves": 0 if is_pvp else 3 + int(index / 3) + (1 if boss_level else 0),
		"base_enemies": 0 if is_pvp else 4 + index,
		"enemy_health": 52.0 + index * 9.0,
		"boss": false if is_pvp else boss_level,
		"score_limit": 20 if is_pvp else 0,
		"time_limit": 600.0 if is_pvp else 0.0,
		"palette": palettes[index % palettes.size()],
		"arena_size": 29.0 + min(index * 0.55, 8.0)
	}

func set_setting(key: String, value: Variant) -> void:
	if settings.has(key):
		settings[key] = value
		_apply_audio_settings()
		if key == "quality":
			apply_viewport_quality()
		elif key == "language":
			# Resolve the autoload dynamically to avoid a compile-time dependency
			# cycle (Localization reads GameState during its own _ready()).
			var localization := get_node_or_null("/root/Localization")
			if localization != null and localization.has_method("apply_locale"):
				localization.call("apply_locale", str(value))
		_save()
		settings_changed.emit()

func get_difficulty_profile() -> Dictionary:
	var key := str(settings.get("difficulty", "veteran"))
	return DIFFICULTY_PROFILES.get(key, DIFFICULTY_PROFILES["veteran"])

func get_quality_profile() -> Dictionary:
	var key := str(settings.get("quality", "high"))
	return QUALITY_PROFILES.get(key, QUALITY_PROFILES["high"])

func apply_viewport_quality() -> void:
	# Render scale and MSAA live on the root window viewport, which survives
	# scene changes, so the menu selection carries straight into the level.
	var viewport := get_viewport()
	if viewport == null:
		return
	var profile := get_quality_profile()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = float(profile.render_scale)
	viewport.msaa_3d = int(profile.msaa)

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
	var parsed: Variant = _read_save_dictionary(save_path)
	if not parsed is Dictionary:
		var backup_path := save_path + ".bak"
		parsed = _read_save_dictionary(backup_path)
		if parsed is Dictionary:
			push_warning("Recovered Star Warfare save from backup: %s" % backup_path)
	if not parsed is Dictionary:
		return
	selected_level = int(parsed.get("selected_level", selected_level))
	if selected_level not in CAMPAIGN_LEVELS:
		selected_level = 1
	selected_weapon = str(parsed.get("selected_weapon", selected_weapon))
	if not WEAPONS.has(selected_weapon):
		selected_weapon = "gun00"
	selected_game_mode = str(parsed.get("selected_game_mode", selected_game_mode))
	if selected_game_mode not in ["singleplayer", "multiplayer"]:
		selected_game_mode = "singleplayer"
	unlocked_level = clampi(int(parsed.get("unlocked_level", unlocked_level)), 1, SINGLEPLAYER_LEVELS[-1])
	credits = maxi(0, int(parsed.get("credits", credits)))
	mithril = maxi(0, int(parsed.get("mithril", mithril)))
	var stored_best_scores: Variant = parsed.get("best_scores", {})
	if stored_best_scores is Dictionary:
		best_scores.clear()
		for level_key in stored_best_scores:
			var normalized_key := str(level_key)
			if normalized_key.is_valid_int() and int(normalized_key) in CAMPAIGN_LEVELS:
				best_scores[normalized_key] = maxi(0, int(stored_best_scores[level_key]))
	var stored_owned: Variant = parsed.get("owned_weapons")
	if stored_owned is Array:
		owned_weapons.clear()
		for weapon_id_value in stored_owned:
			owned_weapons.append(str(weapon_id_value))
	else:
		# Saves from builds before the Unity shop restoration exposed every gun
		# without ownership. Preserve that access during migration.
		owned_weapons = get_weapon_ids()
	var stored_loadout: Variant = parsed.get("battle_weapons")
	if stored_loadout is Array:
		battle_weapons.clear()
		for weapon_id_value in stored_loadout:
			battle_weapons.append(str(weapon_id_value))
	else:
		battle_weapons = ["gun00", "gun06", "gun11", "gun14", "gun17", "gun20", "gun24", "gun27"]
		if not battle_weapons.has(selected_weapon):
			battle_weapons[0] = selected_weapon
	var stored_owned_armor: Variant = parsed.get("owned_armor")
	if stored_owned_armor is Array:
		owned_armor.clear()
		for armor_key_value in stored_owned_armor:
			owned_armor.append(str(armor_key_value))
	elif stored_owned_armor is Dictionary:
		# Accept the per-part schema used by early development builds as well as
		# the compact flat array written by the current restoration.
		owned_armor.clear()
		for part_index in range(ArmorCatalogData.PART_KEYS.size()):
			var part_key := str(ArmorCatalogData.PART_KEYS[part_index])
			var values: Variant = stored_owned_armor.get(part_key, [])
			if values is Array:
				for item_value in values:
					var candidate := _coerce_armor_key(part_index, item_value)
					owned_armor.append(candidate)
	else:
		owned_armor = _default_owned_armor()
	var stored_equipped_armor: Variant = parsed.get("equipped_armor")
	if stored_equipped_armor is Dictionary:
		equipped_armor.clear()
		for part_index in range(ArmorCatalogData.PART_KEYS.size()):
			var part_key := str(ArmorCatalogData.PART_KEYS[part_index])
			var equipped_value: Variant = stored_equipped_armor.get(part_key, 0)
			var armor_key := _coerce_armor_key(part_index, equipped_value)
			equipped_armor[part_key] = armor_key
	else:
		equipped_armor = _default_armor_equipment()
	var stored_props: Variant = parsed.get("owned_props", {})
	owned_props.clear()
	if stored_props is Dictionary:
		for prop_key_value in stored_props:
			var prop_key := str(prop_key_value)
			if PROPS.has(prop_key):
				owned_props[prop_key] = clampi(int(stored_props[prop_key_value]), 0, 99)
	_normalize_armor_state()
	_normalize_store_state()
	_normalize_props_state()
	var stored_settings = parsed.get("settings", {})
	if stored_settings is Dictionary:
		for key in stored_settings:
			if settings.has(key):
				settings[key] = stored_settings[key]

func _read_save_dictionary(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var contents := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(contents) != OK:
		push_warning("Ignoring invalid Star Warfare save JSON: %s" % path)
		return null
	var parsed: Variant = json.data
	return parsed if parsed is Dictionary else null

func _coerce_armor_key(part_index: int, stored_value: Variant) -> String:
	# JSON has a single numeric representation, so a legacy integer armor id
	# commonly arrives as `1.0`. String.is_valid_int() rejects that spelling and
	# used to silently migrate every such part back to the starter equipment.
	if typeof(stored_value) in [TYPE_INT, TYPE_FLOAT]:
		var numeric_value := float(stored_value)
		var item_id := roundi(numeric_value)
		if is_equal_approx(numeric_value, float(item_id)):
			return ArmorCatalogData.item_key(part_index, item_id)
	var candidate := str(stored_value)
	if candidate.is_valid_int():
		return ArmorCatalogData.item_key(part_index, int(candidate))
	return candidate

func _save() -> void:
	var temporary_path := save_path + ".tmp"
	var backup_path := save_path + ".bak"
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var primary_absolute := ProjectSettings.globalize_path(save_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_absolute)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to create temporary Star Warfare save: %s" % temporary_path)
		return
	var data := {
		"save_version": SAVE_VERSION,
		"selected_level": selected_level,
		"selected_weapon": selected_weapon,
		"selected_game_mode": selected_game_mode,
		"unlocked_level": unlocked_level,
		"credits": credits,
		"mithril": mithril,
		"owned_weapons": owned_weapons,
		"battle_weapons": battle_weapons,
		"owned_armor": owned_armor,
		"equipped_armor": equipped_armor,
		"owned_props": owned_props,
		"best_scores": best_scores,
		"settings": settings
	}
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()

	# Never truncate the only good copy. Move the current primary aside first,
	# then publish the fully flushed temporary file. If publishing fails, restore
	# the backup so the next boot can still recover progress.
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_absolute)
		var backup_error := DirAccess.rename_absolute(primary_absolute, backup_absolute)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_absolute)
			push_warning("Unable to preserve previous Star Warfare save (error %d)" % backup_error)
			return
	var publish_error := DirAccess.rename_absolute(temporary_absolute, primary_absolute)
	if publish_error != OK:
		if not FileAccess.file_exists(save_path) and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_absolute, primary_absolute)
		push_warning("Unable to publish Star Warfare save (error %d)" % publish_error)

func _normalize_store_state() -> void:
	var normalized_owned: Array[String] = []
	for weapon_id in owned_weapons:
		if WEAPONS.has(weapon_id) and not normalized_owned.has(weapon_id):
			normalized_owned.append(weapon_id)
	if normalized_owned.is_empty():
		normalized_owned.append("gun00")
	owned_weapons = normalized_owned

	var normalized_loadout: Array[String] = []
	for weapon_id in battle_weapons:
		if normalized_loadout.size() >= LOADOUT_MAX_SLOTS:
			break
		if is_weapon_owned(weapon_id) and not normalized_loadout.has(weapon_id):
			normalized_loadout.append(weapon_id)
	if normalized_loadout.is_empty():
		normalized_loadout.append("gun00")
	battle_weapons = normalized_loadout
	if not battle_weapons.has(selected_weapon):
		selected_weapon = battle_weapons[0]

func _normalize_props_state() -> void:
	var normalized := {}
	for prop_key_value in owned_props:
		var prop_key := str(prop_key_value)
		if not PROPS.has(prop_key):
			continue
		var count := clampi(int(owned_props[prop_key_value]), 0, 99)
		if count > 0:
			normalized[prop_key] = count
	owned_props = normalized

func _default_owned_armor() -> Array[String]:
	var defaults: Array[String] = []
	for part in range(ArmorCatalogData.PART_KEYS.size()):
		defaults.append(ArmorCatalogData.item_key(part, 0))
	return defaults

func _default_armor_equipment() -> Dictionary:
	var defaults := {}
	for part in range(ArmorCatalogData.PART_KEYS.size()):
		defaults[str(ArmorCatalogData.PART_KEYS[part])] = ArmorCatalogData.item_key(part, 0)
	return defaults

func _normalize_armor_state() -> void:
	var normalized_owned: Array[String] = []
	for armor_key in owned_armor:
		var candidate := str(armor_key)
		if ARMOR_ITEMS.has(candidate) and not normalized_owned.has(candidate):
			normalized_owned.append(candidate)
	for part in range(ArmorCatalogData.PART_KEYS.size()):
		var part_key := str(ArmorCatalogData.PART_KEYS[part])
		var has_owned_part := false
		for armor_key in normalized_owned:
			if str(ARMOR_ITEMS[armor_key].part_key) == part_key:
				has_owned_part = true
				break
		if not has_owned_part:
			normalized_owned.append(ArmorCatalogData.item_key(part, 0))
	owned_armor = normalized_owned

	var normalized_equipped := {}
	for part in range(ArmorCatalogData.PART_KEYS.size()):
		var part_key := str(ArmorCatalogData.PART_KEYS[part])
		var equipped_key := str(equipped_armor.get(part_key, ""))
		if not is_armor_owned(equipped_key) or str(ARMOR_ITEMS.get(equipped_key, {}).get("part_key", "")) != part_key:
			equipped_key = ""
			for owned_key in owned_armor:
				if str(ARMOR_ITEMS[owned_key].part_key) == part_key:
					equipped_key = owned_key
					break
		normalized_equipped[part_key] = equipped_key
	equipped_armor = normalized_equipped
