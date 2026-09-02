extends Node

# Pins the level-select thumbnails to the table recovered from the shipped UI
# resource.
#
# The original menu built icon i from vUI[3] frame 8 module i, and those modules
# point at rectangles scattered across the atlas pages in no useful order --
# Level 7 is the top-left cell, Level 1 is in the middle row, Level 8 is not
# even on the same page. An earlier build derived them from a tidy grid instead,
# which paired almost every sector with someone else's picture. These are golden
# values: they come out of the binary, not out of a pattern, so a future tidy-up
# that re-derives them has to fail here.
#
# Regenerate with:
#   python tools/ui_extractor/extract_stage_icons.py --assets-root <Assets>

const RECOVERED := {
	1: [15, Rect2(337, 182, 336, 181)],
	2: [15, Rect2(0, 364, 336, 181)],
	3: [15, Rect2(674, 0, 336, 181)],
	4: [15, Rect2(0, 182, 336, 181)],
	5: [15, Rect2(337, 364, 336, 181)],
	6: [15, Rect2(674, 182, 336, 181)],
	7: [15, Rect2(0, 0, 336, 181)],
	8: [20, Rect2(676, 0, 336, 180)],
	13: [14, Rect2(674, 182, 336, 181)],
	14: [14, Rect2(337, 364, 336, 181)],
	15: [14, Rect2(337, 182, 336, 181)],
	16: [14, Rect2(0, 364, 336, 181)],
	17: [14, Rect2(674, 364, 336, 181)],
	18: [15, Rect2(674, 364, 336, 181)],
	19: [20, Rect2(0, 0, 336, 181)],
	20: [20, Rect2(338, 0, 336, 180)],
	21: [20, Rect2(2, 388, 336, 180)],
}

# The names live only in the artwork -- each icon carries its own name plate, and
# no data table or string file in the original holds them. Pinning them here
# keeps the card text and the picture it sits next to telling the same story.
const RECOVERED_NAMES := {
	1: "FRONT LINE", 2: "ENERGY CORE", 3: "SPACE STATION", 4: "LAIR",
	5: "TRAINING BASE", 6: "FIRE IN THE HOLE", 7: "STADIUM ARCADIUM", 8: "CRAZY CARNIVAL",
	13: "ANCIENT VISION", 14: "REACTOR", 15: "AIR CRASH", 16: "GARAGE",
	17: "KILL HOUSE", 18: "Y8 FACTORY", 19: "MICROWAVE", 20: "GOLDEN FALL", 21: "BUNKER PARTY",
}

# The pages are 1024x1024 in the coordinates the UI resource uses; the recovered
# PNGs hold twice that on each axis.
const LOGICAL_PAGE_SIZE := 1024.0
const SOURCE_SCALE := 2.0

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("LEVEL ICON TEST: " + message)

func _run() -> void:
	GameState.save_path = GameState.TEST_SAVE_PATH
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame

	_test_table(menu)
	_test_regions(menu)
	_test_names()
	_test_pages_are_the_right_textures()

	menu.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("LEVEL_ICON_TEST_PASS icons=%d" % RECOVERED.size())
		get_tree().quit(0)
	else:
		print("LEVEL_ICON_TEST_FAIL: %s" % ", ".join(failures))
		get_tree().quit(1)

func _test_table(menu: Node) -> void:
	var shipped: Dictionary = menu.CAMPAIGN_STAGE_ICONS
	_check(
		shipped.size() == RECOVERED.size(),
		"the shipped table has %d entries, the recovered one has %d" % [shipped.size(), RECOVERED.size()]
	)
	for level_number: int in RECOVERED:
		_check(shipped.has(level_number), "sector %d has no thumbnail" % level_number)
		if not shipped.has(level_number):
			continue
		var expected: Array = RECOVERED[level_number]
		var actual: Array = shipped[level_number]
		_check(
			int(actual[0]) == int(expected[0]),
			"sector %d reads page %d, the resource says page %d" % [level_number, int(actual[0]), int(expected[0])]
		)
		_check(
			(actual[1] as Rect2).is_equal_approx(expected[1]),
			"sector %d uses %s, the resource says %s" % [level_number, actual[1], expected[1]]
		)

	# Two sectors sharing a crop would mean the table collapsed back onto a
	# pattern somewhere.
	var seen: Array[String] = []
	for level_number: int in shipped:
		var record: Array = shipped[level_number]
		var key := "%d:%s" % [int(record[0]), record[1]]
		_check(not seen.has(key), "sector %d reuses another sector's thumbnail (%s)" % [level_number, key])
		seen.append(key)

	# ... and every rectangle has to actually be on the page.
	for level_number: int in shipped:
		var rect: Rect2 = (shipped[level_number] as Array)[1]
		_check(
			rect.position.x >= 0.0 and rect.position.y >= 0.0
				and rect.end.x <= LOGICAL_PAGE_SIZE and rect.end.y <= LOGICAL_PAGE_SIZE,
			"sector %d thumbnail %s falls outside the atlas page" % [level_number, rect]
		)

func _test_regions(menu: Node) -> void:
	for level_number: int in RECOVERED:
		var texture: AtlasTexture = menu._level_preview(level_number)
		_check(texture != null, "sector %d produced no thumbnail texture" % level_number)
		if texture == null:
			continue
		var expected: Rect2 = (RECOVERED[level_number] as Array)[1]
		var wanted := Rect2(expected.position * SOURCE_SCALE, expected.size * SOURCE_SCALE)
		_check(
			texture.region.is_equal_approx(wanted),
			"sector %d samples %s, expected %s" % [level_number, texture.region, wanted]
		)
		_check(texture.atlas != null, "sector %d thumbnail has no atlas page loaded" % level_number)
		if texture.atlas != null:
			var size := texture.atlas.get_size()
			_check(
				texture.region.end.x <= size.x and texture.region.end.y <= size.y,
				"sector %d samples past the end of its page (%s of %s)" % [level_number, texture.region, size]
			)

func _test_names() -> void:
	for level_number: int in RECOVERED_NAMES:
		var actual := str(GameState.get_level_data(level_number).get("name", ""))
		_check(
			actual == RECOVERED_NAMES[level_number],
			"sector %d is called %s, the artwork says %s" % [level_number, actual, RECOVERED_NAMES[level_number]]
		)
	# Every sector that has a thumbnail must also have its name, or a card would
	# again show one map's picture beside another map's title.
	for level_number: int in RECOVERED:
		_check(RECOVERED_NAMES.has(level_number), "sector %d has a thumbnail but no recovered name" % level_number)

func _test_pages_are_the_right_textures() -> void:
	# The PvP icons live on page 14, which was originally extracted from the
	# wrong file: Resources/ui/14.mat points at Texture2D/0/14.png (1024x1024),
	# not the 256x256 Texture2D/14.png that shipped here. At the wrong size the
	# recovered rectangles fall off the end of the image.
	for level_number: int in RECOVERED:
		var page := int((RECOVERED[level_number] as Array)[0])
		var path := "res://assets/original/ui/pages/%d.png" % page
		_check(ResourceLoader.exists(path), "atlas page %d is missing" % page)
		if not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = load(path)
		var rect: Rect2 = (RECOVERED[level_number] as Array)[1]
		var needed := Vector2(rect.end.x, rect.end.y) * SOURCE_SCALE
		_check(
			texture.get_width() >= needed.x and texture.get_height() >= needed.y,
			"page %d is %s, too small for sector %d which needs %s" % [page, texture.get_size(), level_number, needed]
		)
