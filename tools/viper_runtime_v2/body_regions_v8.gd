extends SceneTree

## Technical UV placement guide derived from the original game triangles.
## This annotates a guide only; no diffuse texture, mesh or UV is edited.
const SOURCE := "res://docs/art/viper_runtime_v2/build/source.json"
const OUT := "res://docs/art/viper_runtime_v2/guides/body_regions_v8"
const COLORS := {
	"front_chest": "#ed4747", "front_abdomen": "#ff8274",
	"front_pelvis": "#b261cc", "back_torso": "#397db4",
	"front_thigh": "#64b883", "back_thigh": "#ceab57",
	"side": "#586374", "upper_arm": "#303642", "endcap": "#74697a",
}
# SVG text is not consistently rendered by engine SVG importers. These tiny
# vector glyphs make the labels visible in both the SVG and its engine PNG.
const GLYPHS := {
	"A": [14,17,17,31,17,17,17], "B": [30,17,17,30,17,17,30],
	"C": [14,17,16,16,16,17,14], "D": [30,17,17,17,17,17,30],
	"E": [31,16,16,30,16,16,31], "F": [31,16,16,30,16,16,16],
	"G": [14,17,16,23,17,17,15], "H": [17,17,17,31,17,17,17],
	"I": [31,4,4,4,4,4,31], "J": [7,2,2,2,18,18,12],
	"K": [17,18,20,24,20,18,17], "L": [16,16,16,16,16,16,31],
	"M": [17,27,21,21,17,17,17], "N": [17,25,21,19,17,17,17],
	"O": [14,17,17,17,17,17,14], "P": [30,17,17,30,16,16,16],
	"Q": [14,17,17,17,21,18,13], "R": [30,17,17,30,20,18,17],
	"S": [15,16,16,14,1,1,30], "T": [31,4,4,4,4,4,4],
	"U": [17,17,17,17,17,17,14], "V": [17,17,17,17,17,10,4],
	"W": [17,17,17,21,21,21,10], "X": [17,17,10,4,10,17,17],
	"Y": [17,17,10,4,4,4,4], "Z": [31,1,2,4,8,16,31],
	"0": [14,17,19,21,25,17,14], "1": [4,12,4,4,4,4,14],
	"2": [14,17,1,2,4,8,31], "3": [30,1,1,14,1,1,30],
	"4": [2,6,10,18,31,2,2], "5": [31,16,16,30,1,1,30],
	"6": [14,16,16,30,17,17,14], "7": [31,1,2,4,8,8,8],
	"8": [14,17,17,14,17,17,14], "9": [14,17,17,15,1,1,14],
	".": [0,0,0,0,0,6,6], "=": [0,0,31,0,31,0,0],
	"/": [1,2,2,4,8,8,16], "-": [0,0,0,31,0,0,0],
}

func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var row: Dictionary = source.parts.ArmorBody_00.surfaces[0]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#17222d"/>'
	var seen: Dictionary = {}
	var counts: Dictionary = {}
	for offset: int in range(0, row.indices.size(), 3):
		var points: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		var key_points: Array[String] = []
		for step: int in 3:
			var index: int = row.indices[offset + step]
			var p: Array = row.positions[index]
			var uv: Array = row.uv[index]
			points.append(Vector3(p[0], p[1], p[2]))
			uvs.append(Vector2(uv[0], uv[1]))
			key_points.append("%.4f,%.4f" % [uv[0], uv[1]])
		key_points.sort()
		var key := ";".join(key_points)
		if seen.has(key):
			continue
		seen[key] = true
		var center := (points[0] + points[1] + points[2]) / 3.0
		var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
		var uv_center := (uvs[0] + uvs[1] + uvs[2]) / 3.0
		var kind := _region(center, normal, uv_center)
		counts[kind] = int(counts.get(kind, 0)) + 1
		var polygon: Array[String] = []
		for uv: Vector2 in uvs:
			polygon.append("%.3f,%.3f" % [uv.x * 1024.0, uv.y * 1024.0])
		svg += '<polygon points="%s" fill="%s" fill-opacity=".86" stroke="#bed7e2" stroke-width="1"/>' % [" ".join(polygon), COLORS[kind]]
	# The front center is a mirrored edge, not the middle of the atlas or chart.
	svg += '<path d="M 30 385 L 30 897" stroke="#fff058" stroke-width="4" fill="none"/>'
	svg += _arrow(Vector2(223, 390), Vector2(112, 540), "#ed4747")
	svg += _label("FRONT CHEST HALF", Vector2(211, 365), 1.7, "#ffffff")
	svg += _arrow(Vector2(205, 738), Vector2(78, 779), "#ff8274")
	svg += _label("FRONT ABDOMEN HALF", Vector2(212, 718), 1.7, "#ffffff")
	svg += _label("BACK", Vector2(429, 454), 2.3, "#ffffff")
	svg += _label("NO CHEST WINDOWS", Vector2(357, 489), 1.45, "#ffffff")
	svg += _label("NO FRONT BUCKLES", Vector2(357, 515), 1.45, "#ffffff")
	svg += _label("THIGH FRONT", Vector2(575, 145), 1.65, "#ffffff")
	svg += _label("THIGH BACK", Vector2(790, 470), 1.65, "#ffffff")
	svg += _label("UPPER ARM", Vector2(585, 924), 1.2, "#ffffff")
	svg += _label("ENDCAP", Vector2(850, 824), 1.6, "#ffffff")
	svg += _label("YELLOW = MIRROR CENTER U .029", Vector2(33, 991), 1.65, "#fff058")
	svg += _label("ONE HALF ONLY - ORIGINAL UV", Vector2(708, 991), 1.4, "#d8e5eb")
	svg += '</svg>'
	var file := FileAccess.open(OUT + ".svg", FileAccess.WRITE)
	assert(file != null)
	file.store_string(svg)
	file.close()
	var image := Image.new()
	assert(image.load_svg_from_string(svg) == OK)
	assert(image.get_size() == Vector2i(1024, 1024))
	assert(image.save_png(OUT + ".png") == OK)
	print("VIPER_BODY_UV_REGIONS_PASS original_uv_unmodified triangles=%d classes=%s" % [seen.size(), counts])
	quit()

func _region(center: Vector3, normal: Vector3, uv_center: Vector2) -> String:
	if uv_center.x > .57 and uv_center.x < .67 and uv_center.y > .46:
		return "upper_arm"
	if uv_center.x > .80 and uv_center.y > .68:
		return "endcap"
	var torso := uv_center.x < .57 and uv_center.y > .21 and center.y > .62
	if torso:
		# The source triangle winding points inward: positive normal Z is front.
		if center.z < -.09 and normal.z > .30:
			if center.y >= 1.0:
				return "front_chest"
			if center.y >= .74:
				return "front_abdomen"
			return "front_pelvis"
		if center.z > .08 and normal.z < -.30:
			return "back_torso"
		return "side"
	if center.y < .86:
		if center.z < -.055 and normal.z > .30:
			return "front_thigh"
		if center.z > .04 and normal.z < -.30:
			return "back_thigh"
	return "side"

func _arrow(start: Vector2, end: Vector2, color: String) -> String:
	var direction := (end - start).normalized()
	var side := Vector2(-direction.y, direction.x)
	var a := end - direction * 15.0 + side * 6.0
	var b := end - direction * 15.0 - side * 6.0
	return '<path d="M %.2f %.2f L %.2f %.2f" stroke="%s" stroke-width="4"/><polygon points="%.2f,%.2f %.2f,%.2f %.2f,%.2f" fill="%s"/>' % [start.x, start.y, end.x, end.y, color, end.x, end.y, a.x, a.y, b.x, b.y, color]

func _label(value: String, position: Vector2, scale: float, color: String) -> String:
	var svg := '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="3" fill="#101820" fill-opacity=".88"/>' % [position.x - 4, position.y - 4, value.length() * 6 * scale + 8, 7 * scale + 8]
	for character_index: int in value.length():
		var letter := value.substr(character_index, 1)
		if not GLYPHS.has(letter):
			continue
		var glyph: Array = GLYPHS[letter]
		for y: int in 7:
			for x: int in 5:
				if (int(glyph[y]) & (1 << (4 - x))) != 0:
					svg += '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>' % [position.x + (character_index * 6 + x) * scale, position.y + y * scale, scale, scale, color]
	return svg
