extends Node

## Runtime internationalisation framework.
##
## English is the source language: every UI call passes its English text to
## tr(), so an unmapped key simply renders in English. Only the non-English
## tables in assets/i18n/strings.json need entries. Translations are built as
## Translation objects and registered with the TranslationServer at startup, so
## exported builds require no per-locale .translation import step.

const STRINGS_PATH := "res://assets/i18n/strings.json"
const SOURCE_LOCALE := "en"
const SUPPORTED_LOCALES := ["en", "zh_TW"]

var _tables: Dictionary = {}

func _ready() -> void:
	_load_tables()
	_register_translations()
	apply_locale(str(GameState.settings.get("language", "")))

func _load_tables() -> void:
	if not FileAccess.file_exists(STRINGS_PATH):
		push_warning("Localization table missing: %s" % STRINGS_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_PATH))
	if parsed is Dictionary:
		_tables = parsed
	else:
		push_warning("Localization table is not a dictionary: %s" % STRINGS_PATH)

func _register_translations() -> void:
	for locale: String in _tables:
		var entries: Variant = _tables[locale]
		if not entries is Dictionary:
			continue
		var translation := Translation.new()
		translation.locale = locale
		for key: String in entries:
			translation.add_message(key, str(entries[key]))
		TranslationServer.add_translation(translation)

## Turns a stored preference ("", "en", "zh_TW") into a concrete supported
## locale. An empty preference means "auto": follow the device language.
func resolve_locale(requested: String) -> String:
	if requested in SUPPORTED_LOCALES:
		return requested
	if OS.get_locale().to_lower().begins_with("zh"):
		return "zh_TW"
	return SOURCE_LOCALE

func apply_locale(requested: String) -> void:
	TranslationServer.set_locale(resolve_locale(requested))

func current_locale() -> String:
	return TranslationServer.get_locale()

func locale_display_name(locale: String) -> String:
	match locale:
		"en":
			return "ENGLISH"
		"zh_TW":
			return "繁體中文"
	return locale
