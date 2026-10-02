extends "res://tools/armor_concept_runtime/compile.gd"

const CYGNI_OUT := "res://assets/armors/cygni_v2/"
const CYGNI_WORK := "res://docs/art/cygni_runtime_v2/build/"

func _build() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CYGNI_WORK + "game_meshes.json"))
	if not data is Dictionary or data.get("revision", "") != "cygni_runtime_v2" or data.get("id", -1) != 11:
		_fail("Missing current Cygni mesh export")
		return
	var original := (load(SOURCE) as PackedScene).instantiate()
	root.add_child(original)
	var skeleton := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skin := Skin.new()
	var bones := {}
	for i: int in skeleton.get_bone_count():
		var key := skeleton.get_bone_name(i)
		bones[key] = i
		skin.add_named_bind(key, skeleton.get_bone_global_rest(i).affine_inverse())
	var error := _validate(data.parts, 11, bones)
	if not error.is_empty():
		original.free()
		_fail(error)
		return
	var container := Node3D.new()
	container.name = "CygniRuntimeV2"
	var triangles := 0
	for part: Dictionary in data.parts:
		var old := original.find_child(str(part.name),true,false) as MeshInstance3D
		# Legacy cages retain their per-mesh binds, including repeated named binds
		# in the boot. Newly authored plates use appended inverse-rest binds.
		var use_source := bool(part.source_cage.has(true))
		var part_skin := old.skin.duplicate() as Skin if use_source else skin
		var new_offset := part_skin.get_bind_count() if use_source else 0
		if use_source and part.source_cage.has(false):
			for i: int in skeleton.get_bone_count():
				part_skin.add_named_bind(skeleton.get_bone_name(i),skeleton.get_bone_global_rest(i).affine_inverse())
		var source_lookup := _source_lookup(old,skeleton) if use_source else {}
		var label := str(part.name).trim_prefix("Armor").trim_suffix("_11").to_lower()
		var path := CYGNI_OUT + label + "_diffuse.png"
		if not ResourceLoader.exists(path):
			container.free()
			original.free()
			_fail("Missing generated diffuse " + path)
			return
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		var weights := PackedFloat32Array()
		var corners: int = part.positions.size() / 3
		triangles += corners / 3
		for triangle: int in corners / 3:
			for corner: int in [2, 1, 0]:
				var i := triangle * 3 + corner
				var point := Vector3(part.positions[i*3],part.positions[i*3+1],part.positions[i*3+2])
				var normal := Vector3(part.normals[i*3],part.normals[i*3+1],part.normals[i*3+2])
				var raw := {}
				if part.source_cage[i]:
					var uv_old := Vector2(part.source_uv[i*2],1.0-float(part.source_uv[i*2+1]))
					var source_point := Vector3(part.source_positions[i*3],part.source_positions[i*3+1],part.source_positions[i*3+2])
					raw=_source_corner(source_lookup,uv_old,source_point)
					if raw.is_empty():
						_fail("Cannot match original UV corner at "+str(part.name))
						return
					var delta := point-source_point
					point=raw.point+raw.rest_basis.inverse()*delta
					normal=raw.normal
				positions.append(point)
				normals.append(normal)
				uvs.append(Vector2(part.uv[i*2],1.0-float(part.uv[i*2+1])))
				for j: int in 4:
					if not raw.is_empty():
						indices.append(raw.bones[j])
						weights.append(raw.weights[j])
					else:
						indices.append(new_offset+int(bones[part.bones[i][j]]) if j < part.bones[i].size() else 0)
						weights.append(float(part.weights[i][j]) if j < part.weights[i].size() else 0.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=positions
		arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_TEX_UV]=uvs
		arrays[Mesh.ARRAY_BONES]=indices
		arrays[Mesh.ARRAY_WEIGHTS]=weights
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := StandardMaterial3D.new()
		material.resource_name="Cygni_"+label+"_painted"
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture=load(path) as Texture2D
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mesh.surface_set_material(0,material)
		var instance := MeshInstance3D.new()
		instance.name=str(part.name)
		instance.mesh=mesh
		instance.skin=part_skin
		instance.skeleton=NodePath("..")
		instance.extra_cull_margin=1.0
		instance.set_meta("armor_rework","cygni_runtime_v2")
		container.add_child(instance)
		instance.owner=container
	var scene := PackedScene.new()
	var saved := scene.pack(container)
	if saved==OK:
		saved=ResourceSaver.save(scene,CYGNI_OUT+"cygni.scn")
	if saved==OK:
		# Export the engine's validated skin representation. Blender's ordinary
		# inverse-rest exporter cannot express the legacy boot's repeated binds.
		for replacement: MeshInstance3D in container.get_children():
			var existing:=original.find_child(str(replacement.name),true,false) as MeshInstance3D
			existing.mesh=replacement.mesh
			existing.skin=replacement.skin
			existing.transform=replacement.transform
			existing.visible=true
		for mesh: MeshInstance3D in original.find_children("*","MeshInstance3D",true,false):
			if str(mesh.name) not in ["ArmorHead_11","ArmorBody_11","ArmorHand_11","ArmorFoot_11"]:mesh.free()
		for animation: AnimationPlayer in original.find_children("*","AnimationPlayer",true,false):animation.free()
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
		var document:=GLTFDocument.new()
		var state:=GLTFState.new()
		saved=document.append_from_scene(original,state)
		if saved==OK:saved=document.write_to_filesystem(state,CYGNI_OUT+"cygni.glb")
	container.free()
	original.free()
	if saved!=OK:
		_fail("Cygni scene save failed: "+error_string(saved))
		return
	print("CYGNI_COMPILE_PASS parts=4 triangles=%d named_binds=%d" % [triangles,bones.size()])
	quit()

func _uv_key(uv: Vector2) -> String:
	return "%d,%d"%[roundi(uv.x*100000),roundi(uv.y*100000)]

func _source_lookup(part: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var lookup := {}
	for sid: int in part.mesh.get_surface_count():
		var a:=part.mesh.surface_get_arrays(sid)
		for i: int in a[Mesh.ARRAY_VERTEX].size():
			var point: Vector3=a[Mesh.ARRAY_VERTEX][i]
			var rest:=Vector3.ZERO
			var basis:=Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
			var ids: Array[int]=[]
			var ws: Array[float]=[]
			for j: int in 4:
				var bind: int=a[Mesh.ARRAY_BONES][i*4+j]
				var weight: float=a[Mesh.ARRAY_WEIGHTS][i*4+j]
				ids.append(bind);ws.append(weight)
				var bone:=skeleton.find_bone(part.skin.get_bind_name(bind))
				var transform:=skeleton.get_bone_global_rest(bone)*part.skin.get_bind_pose(bind)
				rest+=(transform*point)*weight
				basis.x+=transform.basis.x*weight
				basis.y+=transform.basis.y*weight
				basis.z+=transform.basis.z*weight
			var key:=_uv_key(a[Mesh.ARRAY_TEX_UV][i])
			if not lookup.has(key):lookup[key]=[]
			lookup[key].append({"point":point,"normal":a[Mesh.ARRAY_NORMAL][i],"rest":rest,"rest_basis":basis,"bones":ids,"weights":ws})
	return lookup

func _source_corner(lookup: Dictionary, uv: Vector2, point: Vector3) -> Dictionary:
	var candidates: Array=lookup.get(_uv_key(uv),[])
	var best:={}
	var distance:=INF
	for row: Dictionary in candidates:
		var d: float=row.rest.distance_squared_to(point)
		if d<distance:
			distance=d
			best=row
	return best
