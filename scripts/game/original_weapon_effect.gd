class_name OriginalWeaponEffect
extends Node3D

const ROOT := "res://assets/weapon_effects/"
static var data: Dictionary = {}
static var meshes: Dictionary = {}
static var shaders: Dictionary = {}
static var hd_textures: Dictionary = {}
var elapsed := 0.0
var lifetime := 0.0
var source_prefab := ""
var tracks: Array[Dictionary] = []
var behaviours: Array[Dictionary] = []
var skeleton_links: Array[Dictionary] = []

static func catalog() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "effects.json"))
		hd_textures = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "hd.json"))
	return data.weapons

static func create(path: String, one_shot := false) -> OriginalWeaponEffect:
	catalog()
	if not data.prefabs.has(path):
		return null
	var effect := OriginalWeaponEffect.new()
	effect.source_prefab = path
	effect.name = "Original_" + path.get_file()
	effect.lifetime = 3.0 if one_shot else 0.0
	var nodes: Dictionary = {}
	var particle_ids: Dictionary = {}
	var records: Array = data.prefabs[path].nodes
	for record: Dictionary in records:
		var node := Node3D.new()
		node.name = str(record.name) if not str(record.name).is_empty() else "SourceNode"
		node.position = vector(record.position, true)
		node.quaternion = source_rotation(record.rotation)
		node.scale = vector(record.scale)
		node.visible = bool(record.active)
		if record.parent == "0":
			node.position = Vector3.ZERO
			node.quaternion = Quaternion.IDENTITY
		nodes[record.id] = node
	for record: Dictionary in records:
		var node: Node3D = nodes[record.id]
		var parent: Node3D = effect if record.parent == "0" else nodes[record.parent]
		parent.add_child(node)
		var c: Dictionary = record.components
		var mesh_record: Dictionary = c.get("MeshFilter", c.get("SkinnedMeshRenderer", [{}]))[0]
		if mesh_record.has("m_Mesh") and mesh_record.m_Mesh.has("guid"):
			var instance := MeshInstance3D.new()
			instance.name = "SourceMesh"
			instance.mesh = mesh_resource(mesh_record.m_Mesh.guid)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var renderer: Dictionary = c.get("MeshRenderer", c.get("SkinnedMeshRenderer", [{}]))[0]
			instance.visible = bool(renderer.get("m_Enabled", 1))
			for i in instance.mesh.get_surface_count():
				var refs: Array = renderer.get("m_Materials", [])
				if not refs.is_empty():
					instance.set_surface_override_material(i, material_resource(refs[mini(i, refs.size()-1)].guid))
			node.add_child(instance)
			if c.has("SkinnedMeshRenderer") and not data.meshes[mesh_record.m_Mesh.guid].skin.is_empty():
				var skeleton := Skeleton3D.new()
				skeleton.name = "SourceSkeleton"
				node.add_child(skeleton)
				instance.skeleton = NodePath("../SourceSkeleton")
				var skin := Skin.new()
				var bone_nodes := []
				for bone_ref: Dictionary in mesh_record.m_Bones:
					var bone_node: Node3D = nodes[str(bone_ref.fileID)]
					var index := skeleton.get_bone_count()
					skeleton.add_bone("SourceBone%d" % index)
					bone_nodes.append(bone_node)
					skin.add_bind(index, source_matrix(data.meshes[mesh_record.m_Mesh.guid].bindposes[index]))
				instance.skin = skin
				effect.skeleton_links.append({"skeleton":skeleton,"bones":bone_nodes})
		if c.has("ParticleSystem") or c.has("EllipsoidParticleEmitter"):
			var emitter := OriginalWeaponParticles.new()
			emitter.configure(c)
			node.add_child(emitter)
			for id_value in record.get("component_ids",{}).get("ParticleSystem",[]): particle_ids[str(id_value)] = emitter
		if c.has("TrailRenderer"):
			var trail := OriginalWeaponTrail.new()
			trail.record = c.TrailRenderer[0]
			node.add_child(trail)
		for b: Dictionary in c.get("MonoBehaviour", []):
			if b.script_name == "AutoDestroyScript":
				if record.parent == "0" and one_shot:
					effect.lifetime = float(b.life)
				elif record.parent != "0":
					effect.behaviours.append({"node": node, "record": b})
			elif b.script_name in ["RotateScript", "AlphaAnimationScript", "LookAtCameraScript"]:
				effect.behaviours.append({"node": node, "record": b})
	for emitter: OriginalWeaponParticles in particle_ids.values():
		var sub: Dictionary = emitter.source.get("SubModule",{})
		if not bool(sub.get("enabled",0)): continue
		var death_id := str(sub.get("subEmitterDeath",{}).get("fileID",0))
		if particle_ids.has(death_id):
			emitter.death_emitter = particle_ids[death_id]
			emitter.death_emitter.sub_only = true
			emitter.death_emitter.local_space = false
	# Animation paths are relative to the component's transform, after hierarchy exists.
	for record: Dictionary in records:
		for component: Dictionary in record.components.get("Animation", []):
			var ref: Dictionary = component.get("m_Animation", {})
			if not ref.has("guid") or not data.animations.has(ref.guid):
				continue
			var clip: Dictionary = data.animations[ref.guid]
			if path == "Effect/TrackingRobot":
				for candidate: Dictionary in component.get("m_Animations",[]):
					if candidate.has("guid") and str(data.animations[candidate.guid].m_Name) == "move": clip = data.animations[candidate.guid]
			for kind in ["m_RotationCurves", "m_PositionCurves", "m_ScaleCurves", "m_FloatCurves"]:
				for channel: Dictionary in clip.get(kind, []):
					var target: Node3D = nodes[record.id]
					if channel.get("path") != null and not str(channel.path).is_empty():
						target = target.get_node_or_null(str(channel.path))
					if target != null:
						effect.tracks.append({"node": target, "kind": kind, "channel": channel, "loop": path == "Effect/TrackingRobot" or int(clip.get("m_WrapMode", 0)) == 2 or bool(clip.get("m_AnimationClipSettings", {}).get("m_LoopTime", false))})
	return effect

static func vector(v: Variant, reflect := false) -> Vector3:
	var a: Array = v.values() if v is Dictionary else v
	return Vector3(float(a[0]), float(a[1]), -float(a[2]) if reflect else float(a[2]))

static func source_rotation(v: Variant) -> Quaternion:
	var a: Array = v.values() if v is Dictionary else v
	return Quaternion(-float(a[0]), -float(a[1]), float(a[2]), float(a[3])).normalized()

static func source_matrix(m: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3(m.e00,m.e10,-m.e20),Vector3(m.e01,m.e11,-m.e21),Vector3(-m.e02,-m.e12,m.e22)),Vector3(m.e03,m.e13,-m.e23))

static func mesh_resource(guid: String) -> ArrayMesh:
	if meshes.has(guid):
		return meshes[guid]
	var r: Dictionary = data.meshes[guid]
	var mesh := ArrayMesh.new()
	for indices: Array in r.surfaces:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		# Mirror Z and preserve Unity's clockwise face order.
		for index: int in indices:
			vertices.append(vector(r.positions[index], true))
			if r.normals != null and not r.normals.is_empty(): normals.append(vector(r.normals[index], true))
			if r.uv != null and not r.uv.is_empty(): uv.append(Vector2(r.uv[index][0], 1.0-r.uv[index][1]))
			if r.uv2 != null and not r.uv2.is_empty(): uv2.append(Vector2(r.uv2[index][0], 1.0-r.uv2[index][1]))
			if not r.get("skin",[]).is_empty():
				for slot in 4:
					bones.append(int(r.skin[index]["boneIndex[%d]"%slot]))
					weights.append(float(r.skin[index]["weight[%d]"%slot]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if not normals.is_empty(): arrays[Mesh.ARRAY_NORMAL] = normals
		if not uv.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uv
		if not uv2.is_empty(): arrays[Mesh.ARRAY_TEX_UV2] = uv2
		if not bones.is_empty():
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	meshes[guid] = mesh
	return mesh

static func material_resource(guid: String, particle := false) -> ShaderMaterial:
	var r: Dictionary = data.materials[guid]
	var blend := str(r.blend)
	var key := str(r.shader) + str(particle)
	if not shaders.has(key):
		var shader := Shader.new()
		var modes := "unshaded"
		if r.cull_disabled or particle: modes += ", cull_disabled"
		if blend != "opaque": modes += ", depth_draw_never"
		if blend == "additive": modes += ", blend_add"
		var color_expr := "COLOR" if particle or "VertexColor" in str(r.shader) else "vec4(1.0)"
		var multiplier := "2.0" if "Bright" in str(r.shader) or "VertexColor_Color" in str(r.shader) or str(r.shader).begins_with("Particles/") else "1.0"
		var base_expr := "texture(tex, coords) * tint * " + color_expr + " * " + multiplier
		if not str(r.overlay).is_empty(): base_expr = "texture(tex, coords) + texture(overlay_tex, UV) * tint"
		shader.code = "shader_type spatial;\nrender_mode %s;\nuniform sampler2D tex:source_color,repeat_enable;\nuniform sampler2D overlay_tex:source_color,repeat_enable;\nuniform vec4 tint:source_color=vec4(1.0);\nuniform vec2 uv_offset=vec2(0.0);\nuniform vec2 uv_scale=vec2(1.0);\nuniform vec2 tiles=vec2(1.0);\nvarying float frame;\nvoid vertex(){frame=INSTANCE_CUSTOM.r;}\nvoid fragment(){vec2 coords=UV*uv_scale+uv_offset;coords=(coords+vec2(mod(frame,tiles.x),floor(frame/tiles.x)))/tiles;vec4 c=%s;ALBEDO=c.rgb;%s}\n" % [modes, base_expr, "ALPHA=clamp(c.a,0.0,1.0);" if blend != "opaque" else ""]
		shaders[key] = shader
		shader.code = shader.code.replace("repeat_enable", "filter_linear_mipmap_anisotropic,repeat_enable")
		shader.code = shader.code.replace("void fragment()", "#include \"res://assets/shaders/original_weapon_hd.gdshaderinc\"\nvoid fragment()")
		shader.code = shader.code.replace("texture(tex, coords)", "original_hd_sample(tex, coords)")
	var material := ShaderMaterial.new()
	material.resource_name = str(r.source)
	material.shader = shaders[key]
	if not str(r.texture).is_empty(): material.set_shader_parameter("tex", load(str(hd_textures.get(str(r.texture),{}).get("path",ROOT + str(r.texture)))))
	if not str(r.overlay).is_empty(): material.set_shader_parameter("overlay_tex", load(str(hd_textures.get(str(r.overlay),{}).get("path",ROOT + str(r.overlay)))))
	material.set_shader_parameter("tint", Color(r.color[0], r.color[1], r.color[2], r.color[3]))
	return material

static func scalar_curve(curve: Dictionary, t: float, fallback := 0.0) -> float:
	var keys: Array = curve.get("m_Curve", [])
	if keys.is_empty(): return fallback
	if t <= float(keys[0].time): return float(keys[0].value)
	for i in range(1, keys.size()):
		var a: Dictionary = keys[i-1]
		var b: Dictionary = keys[i]
		if t <= float(b.time):
			var length := float(b.time)-float(a.time)
			if length <= 0: return float(b.value)
			var f := (t-float(a.time))/length
			return (2*f*f*f-3*f*f+1)*float(a.value)+(f*f*f-2*f*f+f)*length*float(a.outSlope)+(-2*f*f*f+3*f*f)*float(b.value)+(f*f*f-f*f)*length*float(b.inSlope)
	return float(keys[-1].value)

static func minmax(c: Variant, t: float, random: float, fallback := 0.0) -> float:
	if c is float or c is int: return float(c)
	if c.is_empty(): return fallback
	var scalar := float(c.get("scalar", 1.0))
	var mode := int(c.get("minMaxState", 0))
	if mode == 0: return scalar
	var maximum := scalar * scalar_curve(c.get("maxCurve", {}), t, 1.0)
	if mode == 1: return maximum
	var minimum := float(c.get("minScalar", scalar)) * scalar_curve(c.get("minCurve", {}), t, 1.0)
	return lerpf(minimum, maximum, random)

func _process(delta: float) -> void:
	elapsed += delta
	for track: Dictionary in tracks:
		var channel: Dictionary = track.channel
		var curve: Dictionary = channel.curve
		var keys: Array = curve.get("m_Curve", [])
		if keys.is_empty(): continue
		var t := elapsed
		if track.loop and float(keys[-1].time) > 0: t = fmod(t, float(keys[-1].time))
		var node: Node3D = track.node
		if track.kind == "m_FloatCurves":
			var value := scalar_curve(curve, t)
			var attribute := str(channel.attribute)
			if attribute.begins_with("m_LocalEulerAnglesHint."):
				var axis := "xyz".find(attribute.right(1))
				var angles := node.rotation_degrees
				angles[axis] = value if axis == 2 else -value
				node.rotation_degrees = angles
			elif node.has_node("SourceMesh"):
				var mesh: MeshInstance3D = node.get_node("SourceMesh")
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as ShaderMaterial
					if attribute.begins_with("_TintColor.") and attribute.right(1) in ["r","g","b","a"]:
						var tint: Color = material.get_shader_parameter("tint")
						tint["rgba".find(attribute.right(1))] = value
						material.set_shader_parameter("tint", tint)
					elif "offset.y" in attribute: material.set_shader_parameter("uv_offset", Vector2(0,-value))
		else:
			var components: Array = keys[0].value.keys()
			var values := []
			for component: String in components:
				var scalar_keys := []
				for k: Dictionary in keys:
					scalar_keys.append({"time": k.time, "value": k.value[component], "inSlope": k.inSlope[component], "outSlope": k.outSlope[component]})
				values.append(scalar_curve({"m_Curve": scalar_keys}, t))
			match track.kind:
				"m_RotationCurves": node.quaternion = source_rotation(values)
				"m_PositionCurves": node.position = vector(values, true)
				"m_ScaleCurves": node.scale = vector(values).max(Vector3.ONE*0.00001)
	for b: Dictionary in behaviours:
		var node: Node3D = b.node
		var r: Dictionary = b.record
		match r.script_name:
			"AutoDestroyScript": node.visible = elapsed < float(r.life)
			"RotateScript": node.rotation_degrees += vector(r.rotationSpeed) * Vector3(-1,-1,1)*delta
			"LookAtCameraScript":
				var camera := get_viewport().get_camera_3d()
				if camera != null and node.global_position.distance_squared_to(camera.global_position) > 0.001: node.look_at(camera.global_position)
			"AlphaAnimationScript":
				if node.has_node("SourceMesh"):
					var mesh: MeshInstance3D = node.get_node("SourceMesh")
					for surface in mesh.mesh.get_surface_count():
						var material := mesh.get_active_material(surface) as ShaderMaterial
						var tint: Color = material.get_shader_parameter("tint")
						if bool(r.enableAlphaAnimation): tint.a = float(r.minAlpha) + pingpong(elapsed*float(r.animationSpeed), float(r.maxAlpha)-float(r.minAlpha))
						if bool(r.enableBrightAnimation):
							var bright := float(r.minBright)+pingpong(elapsed*float(r.animationSpeed),float(r.maxBright)-float(r.minBright))
							tint = Color(bright,bright,bright,tint.a)
						material.set_shader_parameter("tint",tint)
	for link: Dictionary in skeleton_links:
		var skeleton: Skeleton3D = link.skeleton
		for i in link.bones.size():
			skeleton.set_bone_pose(i, skeleton.global_transform.affine_inverse()*link.bones[i].global_transform)
	if lifetime > 0 and elapsed >= lifetime: queue_free()

