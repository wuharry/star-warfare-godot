extends RefCounted
## Read-only acceptance of a small, explicit visor subdivision.

static func verify(actual: Array, original: Array, authored: Dictionary, budget: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var original_count: int = original[Mesh.ARRAY_VERTEX].size()
	var count: int = actual[Mesh.ARRAY_VERTEX].size()
	var triangles: int = actual[Mesh.ARRAY_INDEX].size() / 3
	if count != int(budget.vertices) or triangles != int(budget.triangles):
		errors.append("Refined head differs from explicit vertex/triangle budget")
		return errors
	if authored.positions.size()!=count or authored.uv.size()!=count or authored.triangle_parents.size()!=triangles:
		errors.append("Refined head metadata length mismatch")
		return errors
	var ceiling := float(budget.get("count_growth_ceiling", 0.10))
	if ceiling not in [0.10, 0.35] or (ceiling == 0.35 and budget.get("revision") not in ["helmet_refinement_v4", "helmet_refinement_v5"]):
		errors.append("Unknown head subdivision count budget")
	if budget.get("revision") == "helmet_refinement_v5" and (ceiling != 0.35 or count != 334 or triangles != 164):
		errors.append("Titan v5 must preserve its reviewed v4 head vertex and triangle counts")
	if float(count) / original_count > 1.0 + ceiling or float(triangles) / (original[Mesh.ARRAY_INDEX].size() / 3) > 1.0 + ceiling:
		errors.append("Refined head exceeds its explicit original-count growth ceiling")
	if actual[Mesh.ARRAY_INDEX] != PackedInt32Array(authored.indices):
		errors.append("Refined head indices differ from authored subdivision")
	if actual[Mesh.ARRAY_BONES].slice(0, original_count * 4) != original[Mesh.ARRAY_BONES] or actual[Mesh.ARRAY_WEIGHTS].slice(0, original_count * 4) != original[Mesh.ARRAY_WEIGHTS]:
		errors.append("Original head bind/weight prefix changed")
	var baseline_uv: PackedVector2Array = original[Mesh.ARRAY_TEX_UV].duplicate()
	for added: Dictionary in authored.added_vertices:
		var index: int = added.index
		var a: int = added.parents[0]
		var b: int = added.parents[1]
		if index!=baseline_uv.size() or a<0 or b<0 or a>=original_count or b>=original_count:
			errors.append("Arc vertex has invalid original edge parents")
			return errors
		baseline_uv.append((baseline_uv[a]+baseline_uv[b])*.5)
		for channel: int in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			for j: int in 4:
				if actual[channel][index * 4 + j] != original[channel][a * 4 + j] or original[channel][a * 4 + j] != original[channel][b * 4 + j]:
					errors.append("Arc vertex changed its parent bind/weight")
	for index: int in count:
		var uv: Array = authored.uv[index]
		if actual[Mesh.ARRAY_TEX_UV][index].distance_to(Vector2(uv[0], uv[1])) > .000001:
			errors.append("Refined head UV differs from authored target")
	var moved := 0
	for index: int in original_count:
		if actual[Mesh.ARRAY_TEX_UV][index].distance_to(original[Mesh.ARRAY_TEX_UV][index])>.000001:moved+=1
	if float(moved)/original_count>.20:errors.append("Original head UV edits exceed per-surface 20% budget")
	# Independently check subdivision coverage on the ORIGINAL UV triangles.
	# This catches lost/duplicated faces even if actual indices equal the target.
	var parent_count: int = original[Mesh.ARRAY_INDEX].size()/3
	var covered: PackedFloat64Array = []
	covered.resize(parent_count)
	var seen := {}
	for tri: int in triangles:
		var parent: int = authored.triangle_parents[tri]
		if parent<0 or parent>=parent_count:
			errors.append("Arc triangle has invalid original parent")
			return errors
		var old: PackedInt32Array = original[Mesh.ARRAY_INDEX].slice(parent*3,parent*3+3)
		var ids: PackedInt32Array = actual[Mesh.ARRAY_INDEX].slice(tri*3,tri*3+3)
		for vertex: int in ids:
			if vertex<0 or vertex>=count:
				errors.append("Arc triangle index outside vertex buffer")
				return errors
		var area := _area(baseline_uv[ids[0]],baseline_uv[ids[1]],baseline_uv[ids[2]])
		var expected := _area(baseline_uv[old[0]],baseline_uv[old[1]],baseline_uv[old[2]])
		if area*expected < -1e-10:errors.append("Subdivision reversed an original triangle")
		var sorted_ids := ids.duplicate()
		sorted_ids.sort()
		var key := "%d:%s"%[parent,str(sorted_ids)]
		if seen.has(key):errors.append("Subdivision duplicated a triangle")
		seen[key]=true
		covered[parent]+=area
	for parent: int in parent_count:
		var ids: PackedInt32Array=original[Mesh.ARRAY_INDEX].slice(parent*3,parent*3+3)
		var expected:=_area(baseline_uv[ids[0]],baseline_uv[ids[1]],baseline_uv[ids[2]])
		if absf(covered[parent]-expected)>1e-7:errors.append("Subdivision does not cover its original triangle")
	return errors

static func _area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
