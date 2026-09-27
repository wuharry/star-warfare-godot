@tool
extends EditorScenePostImport

const CHITIN_SHADER := preload("res://assets/models/enemies/concept/warrior/chitin_palette.gdshader")

func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null or source.resource_name != "warrior_chitin_palette_v3":
				continue
			var painted := ShaderMaterial.new()
			painted.resource_name = "warrior_chitin_palette_v3"
			painted.shader = CHITIN_SHADER
			painted.set_shader_parameter("chitin_texture", source.albedo_texture)
			mesh.mesh.surface_set_material(surface, painted)
	return scene
