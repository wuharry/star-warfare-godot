@tool
extends EditorScenePostImport

const CHITIN_SHADER := preload("res://assets/models/enemies/concept/warrior/chitin_palette.gdshader")

func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null or source.resource_name not in ["warrior_chitin_painted_v4", "warrior_recess"]:
				continue
			var painted := ShaderMaterial.new()
			painted.resource_name = source.resource_name
			painted.shader = CHITIN_SHADER
			painted.set_shader_parameter("chitin_texture", source.albedo_texture)
			if source.resource_name == "warrior_recess":
				painted.set_shader_parameter("palette_weight", 0.0)
				painted.set_shader_parameter("painted_fill", 0.30)
			mesh.mesh.surface_set_material(surface, painted)
	return scene
