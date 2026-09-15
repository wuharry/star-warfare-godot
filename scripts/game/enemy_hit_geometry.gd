class_name EnemyHitGeometry
extends StaticBody3D

# Weapon collision is separate from the capsule used to walk on the level.
# Bind-space hulls follow the same bone transforms as the rendered skin.
var parts: Array[Dictionary] = []
static var mesh_parts: Dictionary = {}
var coarse := false
var coarse_collision: CollisionShape3D
var coarse_shape: BoxShape3D

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
			parts.append({"skeleton": skeleton, "bone": bone, "collision": collision, "bounds": entry.bounds})
		if not skeleton.skeleton_updated.is_connected(sync_pose):
			skeleton.skeleton_updated.connect(sync_pose)
	if not parts.is_empty():
		coarse_shape = BoxShape3D.new()
		coarse_collision = CollisionShape3D.new()
		coarse_collision.name = "CoarseHitbox"
		coarse_collision.shape = coarse_shape
		coarse_collision.disabled = true
		add_child(coarse_collision)
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
		var points: PackedVector3Array = clouds[bind]
		var bounds := AABB(points[0], Vector3.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		result.append({"bind": bind, "shape": shape, "bounds": bounds})
	return result

func set_coarse(enabled: bool) -> void:
	if coarse_collision == null or coarse == enabled:
		return
	coarse = enabled
	# Both tiers belong to the same damage body. Keep its layer active and
	# switch shapes together after the physics callback has finished.
	sync_pose()
	for part in parts:
		var collision: CollisionShape3D = part.collision
		collision.set_deferred("disabled", enabled)
	coarse_collision.set_deferred("disabled", not enabled)

func release() -> void:
	# skeleton_updated is the only automatic driver of sync_pose, so dropping it
	# is the only thing that actually stops the per-bone transform writes --
	# zeroing collision_layer leaves the body in the space still paying for them.
	for part in parts:
		var skeleton: Skeleton3D = part.skeleton
		if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(sync_pose):
			skeleton.skeleton_updated.disconnect(sync_pose)

func sync_pose() -> void:
	if not is_inside_tree():
		return
	# Both the inverse and the skeleton's own transform are constant across the
	# loop -- nothing in the body moves this node or the skeleton mid-sync -- so
	# each update needs one affine_inverse() instead of one per hull.
	var to_local := global_transform.affine_inverse()
	var cached_skeleton: Skeleton3D = null
	var skeleton_to_local := Transform3D.IDENTITY
	var bounds := AABB()
	var first := true
	for part in parts:
		var skeleton: Skeleton3D = part.skeleton
		if skeleton != cached_skeleton:
			cached_skeleton = skeleton
			skeleton_to_local = to_local * skeleton.global_transform
		var pose := skeleton_to_local * skeleton.get_bone_global_pose(int(part.bone))
		if coarse:
			# Merge cached bone-local bounds in the CURRENT pose. A fixed walking
			# capsule cannot cover a brute raising its torso or a boss unfolding.
			var posed: AABB = pose * (part.bounds as AABB)
			bounds = posed if first else bounds.merge(posed)
			first = false
		else:
			var collision: CollisionShape3D = part.collision
			collision.transform = pose
	if coarse and not first:
		coarse_shape.size = bounds.size.max(Vector3.ONE * 0.01)
		coarse_collision.position = bounds.get_center()
