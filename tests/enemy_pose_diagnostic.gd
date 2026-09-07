extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node3D.new()
	add_child(host)
	for kind in ["crawler", "spitter", "brute", "boss"]:
		var enemy := WarfareEnemy.new()
		enemy.configure(null, kind, 100.0)
		host.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.spawn_left = 0.0
		enemy.model.position.y = 0.0
		for clip in ["idle", "run", "attack"]:
			var animator := enemy.recovered_animation_player
			if not animator.has_animation(clip):
				continue
			animator.play(clip)
			animator.advance(0.0)
			animator.seek(animator.get_animation(clip).length * 0.4, true)
			for child in enemy.model.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
				if skeleton == null or mesh.skin == null:
					continue
				skeleton.force_update_all_bone_transforms()
				var bounds := AABB()
				var first := true
				for surface in range(mesh.mesh.get_surface_count()):
					var arrays := mesh.mesh.surface_get_arrays(surface)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
					var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
					if bones.is_empty():
						continue
					var stride := bones.size() / vertices.size()
					for i in range(vertices.size()):
						var point := Vector3.ZERO
						for j in range(stride):
							var bind := bones[i * stride + j]
							var bone := mesh.skin.get_bind_bone(bind)
							if bone < 0:
								bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
							point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[i]) * weights[i * stride + j]
						point = enemy.global_transform.affine_inverse() * skeleton.global_transform * point
						bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
						first = false
				print("POSE %s %s mesh=%s bounds=%s" % [kind, clip, mesh.name, bounds])
		enemy.free()
	host.free()
	get_tree().quit()
