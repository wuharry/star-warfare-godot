class_name EnemyHitGeometry
extends StaticBody3D

# Weapon collision is separate from the capsule used to walk on the level.
# Bind-space hulls follow the same bone transforms as the rendered skin.
var parts: Array[Dictionary] = []
static var mesh_parts: Dictionary = {}

static func resolve(collider: Node) -> Node:
	return collider.get_parent() if collider is EnemyHitGeometry else collider

static func _bone_index(mesh: MeshInstance3D, skeleton: Skeleton3D, bind: int) -> int:
	var bone := mesh.skin.get_bind_bone(bind)
	return bone if bone >= 0 else skeleton.find_bone(mesh.skin.get_bind_name(bind))

static func posed_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton == null or mesh.skin == null:
			continue
		skeleton.force_update_all_bone_transforms()
		var to_root := root.global_transform.affine_inverse() * skeleton.global_transform
		var poses: Array[Transform3D] = []
		for bind in range(mesh.skin.get_bind_count()):
			poses.append(skeleton.get_bone_global_pose(_bone_index(mesh, skeleton, bind)) * mesh.skin.get_bind_pose(bind))
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vertices.size()
			for i in range(vertices.size()):
				var point := Vector3.ZERO
				for j in range(stride):
					point += (poses[bones[i * stride + j]] * vertices[i]) * weights[i * stride + j]
				point = to_root * point
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
	return bounds

func build(visual: Node3D) -> void:
	name = "AnimatedHitbox"
	collision_layer = 2
	collision_mask = 0
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton == null or mesh.skin == null:
			continue
		var cache_key := mesh.mesh.resource_path + ":" + str(mesh.skin.get_instance_id())
		if not mesh_parts.has(cache_key):
			mesh_parts[cache_key] = _build_bind_hulls(mesh)
		for entry: Dictionary in mesh_parts[cache_key]:
			var bone := _bone_index(mesh, skeleton, int(entry.bind))
			var collision := CollisionShape3D.new()
			collision.name = "Hit_" + str(skeleton.get_bone_name(bone))
			collision.shape = entry.shape
			add_child(collision)
			parts.append({"skeleton": skeleton, "bone": bone, "collision": collision})
		if not skeleton.skeleton_updated.is_connected(sync_pose):
			skeleton.skeleton_updated.connect(sync_pose)
	sync_pose()

func _build_bind_hulls(mesh: MeshInstance3D) -> Array[Dictionary]:
	var clouds: Dictionary = {}
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var stride := bones.size() / vertices.size()
		# Include complete triangles at joints, not just the vertices assigned to
		# each bone. Blended skin spans between bones and otherwise leaves gaps.
		for face in range(0, indices.size(), 3):
			var face_binds: Dictionary = {}
			for corner in range(3):
				var i := indices[face + corner]
				for j in range(stride):
					if weights[i * stride + j] >= 0.1:
						face_binds[bones[i * stride + j]] = true
			for bind: int in face_binds:
				if not clouds.has(bind):
					clouds[bind] = PackedVector3Array()
				for corner in range(3):
					clouds[bind].append(mesh.skin.get_bind_pose(bind) * vertices[indices[face + corner]])
	var result: Array[Dictionary] = []
	for bind: int in clouds:
		if clouds[bind].size() < 4:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = clouds[bind]
		result.append({"bind": bind, "shape": shape})
	return result

func sync_pose() -> void:
	if not is_inside_tree():
		return
	for part in parts:
		var skeleton: Skeleton3D = part.skeleton
		var collision: CollisionShape3D = part.collision
		collision.transform = global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(int(part.bone))
