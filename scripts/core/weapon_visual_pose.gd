extends RefCounted

const Refinement = preload("res://scripts/core/equipment_refinement.gd")


static func uses_left_hand(weapon: Dictionary) -> bool:
	return str(weapon.get("kind", "")) == "arrow"


static func rotation(weapon: Dictionary) -> Vector3:
	if weapon.has("model_rotation"):
		return Vector3(weapon.model_rotation)
	match str(weapon.get("kind", "")):
		"arrow":
			# Bows are held horizontally: +Y limbs follow the helper's -Z,
			# and the -Z arrow axis follows -Y. Prefab rotations are baked.
			return Vector3(-90, 0, 0)
		"sword":
			# The blade grows along +Y; the right sword helper's +X is up.
			return Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP).get_euler() * (180.0 / PI)
		"machinegun", "energy_fist", "tracking", "spring":
			return Vector3(-90, 0, 0)
	if int(weapon.get("id", 0)) in [31, 32, 41, 45, 46]:
		return Vector3.ZERO
	return Vector3(-90, 0, 0)


static func target_length(weapon: Dictionary) -> float:
	match str(weapon.get("kind", "")):
		"arrow": return 1.45
		"sword": return 1.15
		"energy_fist", "tracking", "spring": return 0.48
		"shotgun", "shockwave": return 1.3
		"rocket", "grenade", "fly_grenade": return 1.42
		"sniper", "reflection": return 1.62
	return 1.25


static func scale_factor(weapon: Dictionary, mesh: Mesh) -> float:
	var bounds := Refinement.authored_bounds(mesh)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	return target_length(weapon) / longest if longest > 0.001 else 1.0


static func grip_offset(weapon: Dictionary, mesh: Mesh) -> Vector3:
	var bounds := Refinement.authored_bounds(mesh)
	match str(weapon.get("kind", "")):
		"arrow":
			# Light Bow retains the source avatar's lateral T-pose offset.
			# Keep the authored limb/arrow coordinates; only recenter its grip.
			return Vector3(-bounds.get_center().x, 0, 0)
		"sword":
			return Vector3(-bounds.get_center().x, 0, 0)
		"energy_fist", "tracking", "spring":
			# Fit the cuff around the hand, with the knuckles/drill in front.
			return Vector3(-bounds.get_center().x, -bounds.get_center().y, -bounds.end.z + 0.08)
	return Vector3(weapon.get("reload_model_offset", Vector3.ZERO))


static func muzzle_position(weapon: Dictionary, mesh: Mesh) -> Vector3:
	var bounds := Refinement.authored_bounds(mesh)
	var point := Vector3(0, 0, bounds.position.z)
	var kind := str(weapon.get("kind", ""))
	if kind == "arrow":
		point.x = bounds.get_center().x
	elif kind in ["energy_fist", "tracking", "spring"]:
		point.x = bounds.get_center().x
		point.y = bounds.get_center().y
	elif kind == "sword":
		point = Vector3(bounds.get_center().x, bounds.end.y, 0)
	return (point + grip_offset(weapon, mesh)) * scale_factor(weapon, mesh)


static func refresh_scabbard(avatar: Node3D, weapon: Dictionary) -> void:
	var previous := avatar.find_child("WeaponScabbard", true, false)
	if previous != null:
		previous.get_parent().remove_child(previous)
		previous.queue_free()
	if str(weapon.get("kind", "")) != "sword":
		return
	var skeletons := avatar.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var bone := skeleton.find_bone("Bip01 Spine1")
	if bone < 0:
		return
	var socket := BoneAttachment3D.new()
	socket.name = "WeaponScabbard"
	socket.bone_name = "Bip01 Spine1"
	skeleton.add_child(socket)
	var rest_basis := skeleton.get_bone_global_rest(bone).basis
	var sheath := MeshInstance3D.new()
	sheath.name = "Sheath"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.085, 0.95, 0.07)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.15, 0.2)
	material.metallic = 0.5
	material.roughness = 0.5
	mesh.material = material
	sheath.mesh = mesh
	sheath.transform = Transform3D(rest_basis.inverse() * Basis.from_euler(Vector3(0, 0, deg_to_rad(-25))), rest_basis.inverse() * Vector3(0.36, -0.15, 0.26))
	socket.add_child(sheath)
	var mouth := MeshInstance3D.new()
	mouth.name = "SheathMouth"
	var rim := BoxMesh.new()
	rim.size = Vector3(0.12, 0.045, 0.1)
	var accent := material.duplicate() as StandardMaterial3D
	accent.albedo_color = Color(weapon.get("color", Color.CYAN)).darkened(0.35)
	rim.material = accent
	mouth.mesh = rim
	mouth.position.y = 0.47
	sheath.add_child(mouth)
