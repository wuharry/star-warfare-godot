extends Node3D

# SatanMachineLaser.prefab: 10,000 every 0.3s, 1.3s lifetime. Direction is
# captured before the animation fires, so a player can dodge the tell.
var source: Node
var direction := Vector3.FORWARD
var reach := 40.0
var radius := 0.65
var lifetime := 1.3
var damage := 10000.0
var tick_left := 0.0


func _ready() -> void:
	add_to_group("enemy_source_effects")
	set_meta("visual_provenance", "procedural beam; source damage and lifetime")
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = reach
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.15, 0.1, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	visual.mesh = mesh
	visual.position = direction * reach * 0.5
	visual.quaternion = Quaternion(Vector3.UP, direction.normalized())
	add_child(visual)


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0 or not is_instance_valid(source):
		queue_free()
		return
	tick_left -= delta
	if tick_left > 0.0: return
	for player in source.source_damage_receivers():
		var offset: Vector3 = player.global_position + Vector3.UP - global_position
		var along := offset.dot(direction)
		if along > 0.0 and along < reach and (offset - direction * along).length() < radius + 0.46:
			player.take_damage(damage, global_position, source)
	tick_left = 0.3
