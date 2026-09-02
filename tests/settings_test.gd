extends Node

# Guards the graphics-quality presets and the runtime localization framework:
# both are pure settings systems that must behave identically headless and in
# the shipped menu, so they are cheap and valuable to assert directly.

const REQUIRED_QUALITY_KEYS := ["render_scale", "msaa", "shadows", "glow", "fog", "sky"]
const SAMPLE_TRANSLATIONS := {
	"START": "開始",
	"OPTIONS": "設定",
	"GRAPHICS QUALITY": "畫質",
	"LANGUAGE": "語言",
	# A recovered level name, read off the level-select artwork.
	"FRONT LINE": "前線",
	"WAVE CLEAR": "波次清除",
}

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SETTINGS TEST: " + message)

func _run() -> void:
	_test_quality_profiles()
	_test_localization()

	if failures.is_empty():
		print("SETTINGS_TEST_PASS")
		get_tree().quit(0)
	else:
		print("SETTINGS_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _test_quality_profiles() -> void:
	_check(GameState.QUALITY_ORDER == ["low", "medium", "high"], "quality order changed unexpectedly")
	for quality_key: String in GameState.QUALITY_ORDER:
		_check(GameState.QUALITY_PROFILES.has(quality_key), "missing quality profile: " + quality_key)
		var profile: Dictionary = GameState.QUALITY_PROFILES[quality_key]
		for required_key: String in REQUIRED_QUALITY_KEYS:
			_check(profile.has(required_key), "%s profile is missing %s" % [quality_key, required_key])

	# Low must genuinely lighten the load relative to high, or the option is
	# cosmetic. Render scale and effect toggles are the levers we ship.
	var low: Dictionary = GameState.QUALITY_PROFILES["low"]
	var high: Dictionary = GameState.QUALITY_PROFILES["high"]
	_check(float(low.render_scale) < float(high.render_scale), "low render scale does not undercut high")
	_check(not bool(low.shadows) and bool(high.shadows), "shadow toggle does not vary across presets")
	_check(not bool(low.sky) and bool(high.sky), "sky toggle does not vary across presets")
	_check(float(high.render_scale) == 1.0, "high preset should render at native resolution")

	var restore := str(GameState.settings.quality)
	GameState.set_setting("quality", "low")
	_check(GameState.get_quality_profile() == GameState.QUALITY_PROFILES["low"], "selected profile did not switch to low")
	GameState.apply_viewport_quality()
	var viewport := get_viewport()
	_check(is_equal_approx(viewport.scaling_3d_scale, float(low.render_scale)), "viewport render scale was not applied")
	_check(int(viewport.msaa_3d) == int(low.msaa), "viewport MSAA was not applied")
	GameState.set_setting("quality", restore)

	# An unknown stored value must fall back to the highest preset, never crash.
	GameState.settings.quality = "ultra_nightmare"
	_check(GameState.get_quality_profile() == GameState.QUALITY_PROFILES["high"], "unknown quality did not fall back to high")
	GameState.settings.quality = restore

func _test_localization() -> void:
	_check(Localization.SUPPORTED_LOCALES.has("en"), "English locale is not supported")
	_check(Localization.SUPPORTED_LOCALES.has("zh_TW"), "Traditional Chinese locale is not supported")
	_check(Localization.resolve_locale("zh_TW") == "zh_TW", "explicit locale request was not honoured")
	_check(Localization.resolve_locale("") in Localization.SUPPORTED_LOCALES, "auto locale did not resolve to a supported locale")

	var previous := TranslationServer.get_locale()

	Localization.apply_locale("zh_TW")
	for source_key: String in SAMPLE_TRANSLATIONS:
		_check(
			tr(source_key) == SAMPLE_TRANSLATIONS[source_key],
			"zh_TW translation missing/incorrect for '%s' -> '%s'" % [source_key, tr(source_key)]
		)

	# English is the source language: an unmapped key renders as its own text.
	Localization.apply_locale("en")
	_check(tr("START") == "START", "English source text should pass through unchanged")

	TranslationServer.set_locale(previous)
