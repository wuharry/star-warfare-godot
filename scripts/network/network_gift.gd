extends StaticBody3D
var network_id := 0
var kind := 0
var health := 5.0
var respawn_left := 0.0
var visual: MeshInstance3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 1.4
	shape.shape = box
	shape.position.y = 0.7
	add_child(shape)
	visual = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	visual.position.y = 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = [Color.GREEN, Color.SKY_BLUE, Color.ORANGE, Color.PURPLE, Color.PURPLE][kind]
	visual.material_override = material
	add_child(visual)
	var label := Label3D.new()
	label.text = ["+5", "+10", "+25", "?", "?"][kind]
	label.position.y = 1.8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func take_damage(amount: float, _at := Vector3.ZERO, source: Node = null) -> void:
	if not NetworkSession.is_host() or respawn_left > 0.0 or not is_instance_valid(source) or not "peer_id" in source:
		return
	health = maxf(0.0, health - maxf(0.0, amount))
	if health <= 0.0:
		get_parent().rules.gift_destroyed(int(source.peer_id), kind)
		respawn_left = 8.0
		set_active(false)

func set_active(active: bool) -> void:
	visible = active
	collision_layer = 2 if active else 0

func host_tick(delta: float) -> void:
	if respawn_left > 0.0:
		respawn_left = maxf(0.0, respawn_left - delta)
		if respawn_left == 0.0:
			health = MatchRules.GIFT_HP[kind]
			set_active(true)

func network_state() -> Dictionary:
	return {"position": position, "kind": kind, "health": health, "respawn": respawn_left}
