extends RefCounted
## Read-only acceptance of a small, explicit visor subdivision.

static func verify(actual: Array, original: Array, authored: Dictionary, budget: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var original_count: int = original[Mesh.ARRAY_VERTEX].size()
	var count: int = actual[Mesh.ARRAY_VERTEX].size()
	var triangles: int = actual[Mesh.ARRAY_INDEX].size() / 3
	if count != int(budget.vertices) or triangles != int(budget.triangles):
		errors.append("Refined head differs from explicit vertex/triangle budget")
	if float(count) / original_count > 1.10 or float(triangles) / (original[Mesh.ARRAY_INDEX].size() / 3) > 1.10:
		errors.append("Refined head exceeds this iteration's 10% count growth ceiling")
	if actual[Mesh.ARRAY_INDEX] != PackedInt32Array(authored.indices):
		errors.append("Refined head indices differ from authored subdivision")
	if actual[Mesh.ARRAY_BONES].slice(0, original_count * 4) != original[Mesh.ARRAY_BONES] or actual[Mesh.ARRAY_WEIGHTS].slice(0, original_count * 4) != original[Mesh.ARRAY_WEIGHTS]:
		errors.append("Original head bind/weight prefix changed")
	for added: Dictionary in authored.added_vertices:
		var index: int = added.index
		var a: int = added.parents[0]
		var b: int = added.parents[1]
		for channel: int in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			for j: int in 4:
				if actual[channel][index * 4 + j] != original[channel][a * 4 + j] or original[channel][a * 4 + j] != original[channel][b * 4 + j]:
					errors.append("Arc vertex changed its parent bind/weight")
	for index: int in count:
		var uv: Array = authored.uv[index]
		if actual[Mesh.ARRAY_TEX_UV][index].distance_to(Vector2(uv[0], uv[1])) > .000001:
			errors.append("Refined head UV differs from authored target")
	return errors
