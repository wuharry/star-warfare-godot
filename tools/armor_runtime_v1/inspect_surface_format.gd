extends SceneTree
func _initialize() -> void:
	var original:=(load("res://assets/models/player/animated/player.gltf") as PackedScene).instantiate()
	for name_key: String in ["ArmorHead_03","ArmorBody_03"]:
		var part:=original.find_child(name_key,true,false) as MeshInstance3D
		var surface:=RenderingServer.mesh_get_surface(part.mesh.get_rid(),0)
		print(name_key," keys=",surface.keys()," format=",surface.format," vertex_count=",surface.vertex_count)
		for property: Dictionary in part.mesh.get_property_list():
			if str(property.name).contains("surfaces"):
				var value: Variant=part.mesh.get(property.name)
				print("property=",property.name," type=",typeof(value)," firstkeys=",value[0].keys() if value is Array and not value.is_empty() and value[0] is Dictionary else "")
		print("vertex stride=",RenderingServer.mesh_surface_get_format_vertex_stride(surface.format,surface.vertex_count)," offsets=",RenderingServer.mesh_surface_get_format_offset(surface.format,surface.vertex_count,Mesh.ARRAY_VERTEX),",",RenderingServer.mesh_surface_get_format_offset(surface.format,surface.vertex_count,Mesh.ARRAY_NORMAL),",",RenderingServer.mesh_surface_get_format_offset(surface.format,surface.vertex_count,Mesh.ARRAY_TANGENT))
		for method: Dictionary in ClassDB.class_get_method_list("RenderingServer"):
			if method.name in ["mesh_add_surface","mesh_get_surface","mesh_surface_get_format_offset","mesh_surface_get_format_vertex_stride","mesh_surface_get_format_attribute_stride","mesh_surface_get_format_skin_stride"]:print(method)
		print("first source normal=",part.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]," tangent=",part.mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT].slice(0,4))
	original.free();quit()
