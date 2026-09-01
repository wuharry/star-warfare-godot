class_name UnityColliderBuilder

# Rebuilds the Box/Sphere/Capsule colliders recorded by the Unity level
# exporter. The campaign sectors and THE EXPANSE both plant the same recovered
# geometry, so the transform maths lives here once rather than in each of them.

static func add_primitive(parent: StaticBody3D, record: Dictionary, offset := Vector3.ZERO) -> bool:
	var transform_values: Variant = record.get("transform", [])
	if not transform_values is Array or transform_values.size() < 16:
		return false
	var source_transform := transform_from_json(transform_values)
	var source_scale := source_transform.basis.get_scale().abs()
	var normalized_basis := source_transform.basis.orthonormalized()
	var collision := CollisionShape3D.new()
	collision.name = str(record.get("name", "Collider"))
	collision.transform = Transform3D(normalized_basis, source_transform.origin + offset)
	var collider_type := str(record.get("type", "box"))
	if collider_type == "box":
		var size := vector3_from_json(record.get("size", [1.0, 1.0, 1.0]))
		var shape := BoxShape3D.new()
		shape.size = size * source_scale
		collision.shape = shape
	elif collider_type == "sphere":
		var shape := SphereShape3D.new()
		shape.radius = float(record.get("radius", 0.5)) * maxf(source_scale.x, maxf(source_scale.y, source_scale.z))
		collision.shape = shape
	elif collider_type == "capsule":
		var direction := int(record.get("direction", 1))
		var axis_scale := source_scale.y
		var radius_scale := maxf(source_scale.x, source_scale.z)
		var axis_rotation := Basis.IDENTITY
		if direction == 0:
			axis_scale = source_scale.x
			radius_scale = maxf(source_scale.y, source_scale.z)
			axis_rotation = Basis(Vector3.FORWARD, -PI * 0.5)
		elif direction == 2:
			axis_scale = source_scale.z
			radius_scale = maxf(source_scale.x, source_scale.y)
			axis_rotation = Basis(Vector3.RIGHT, PI * 0.5)
		collision.transform.basis = normalized_basis * axis_rotation
		var shape := CapsuleShape3D.new()
		shape.radius = float(record.get("radius", 0.5)) * radius_scale
		shape.height = maxf(shape.radius * 2.0, float(record.get("height", 2.0)) * axis_scale)
		collision.shape = shape
	if collision.shape == null:
		collision.free()
		return false
	parent.add_child(collision)
	return true

static func collider_origin(record: Dictionary) -> Vector3:
	var transform_values: Variant = record.get("transform", [])
	if not transform_values is Array or transform_values.size() < 16:
		return Vector3.INF
	return transform_from_json(transform_values).origin

static func transform_from_json(values: Array) -> Transform3D:
	var basis := Basis(
		Vector3(float(values[0]), float(values[4]), float(values[8])),
		Vector3(float(values[1]), float(values[5]), float(values[9])),
		Vector3(float(values[2]), float(values[6]), float(values[10]))
	)
	return Transform3D(basis, Vector3(float(values[3]), float(values[7]), float(values[11])))

static func vector3_from_json(values: Variant) -> Vector3:
	if values is Array and values.size() >= 3:
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ONE
