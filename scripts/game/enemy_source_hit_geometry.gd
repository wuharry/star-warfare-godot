extends "res://scripts/game/enemy_hit_geometry.gd"

# boss06 switches Christmas/jester parts using authored zero bone scale.
# A zero-scale skin part is valid rendering data, but cannot be inverted by
# the physics server. Disable only that hull until the part unfolds again.
func sync_pose() -> void:
	if not is_inside_tree(): return
	var to_local := global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	var transforms: Dictionary = {}
	for part in parts:
		var skeleton: Skeleton3D = part.skeleton
		if not transforms.has(skeleton): transforms[skeleton] = to_local * skeleton.global_transform
		var pose: Transform3D = transforms[skeleton] * skeleton.get_bone_global_pose(int(part.bone))
		var collision: CollisionShape3D = part.collision
		var collapsed := absf(pose.basis.determinant()) < 0.0000001
		collision.set_deferred("disabled", coarse or collapsed)
		if collapsed: continue
		if coarse:
			var posed: AABB = pose * (part.bounds as AABB)
			bounds = posed if first else bounds.merge(posed)
			first = false
		else: collision.transform = pose
	if coarse and not first:
		coarse_shape.size = bounds.size.max(Vector3.ONE * 0.01)
		coarse_collision.position = bounds.get_center()
