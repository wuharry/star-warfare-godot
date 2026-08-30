class_name WarfarePickup
extends Area3D

var pickup_kind := "credits"
var amount := 10.0
var clock := 0.0
var base_y := 0.0
var visual: MeshInstance3D

func configure(kind: String, value: float) -> void:
	pickup_kind = kind
	amount = value

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.72
	collision.shape = shape
	add_child(collision)
	visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 12
	mesh.rings = 6
	var material := StandardMaterial3D.new()
	var color := Color(1.0, 0.75, 0.1) if pickup_kind == "credits" else Color(0.1, 0.82, 1.0)
	if pickup_kind == "ammo":
		color = Color(0.92, 0.28, 0.12)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	visual.mesh = mesh
	add_child(visual)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.1
	light.omni_range = 2.2
	add_child(light)
	body_entered.connect(_on_body_entered)
	base_y = position.y

func _process(delta: float) -> void:
	clock += delta
	visual.rotation.y += delta * 2.2
	visual.position.y = sin(clock * 2.8) * 0.16

func _on_body_entered(body: Node3D) -> void:
	if not body is WarfarePlayer:
		return
	if pickup_kind == "credits":
		var world := get_parent()
		if world.has_method("add_battle_credits"):
			world.add_battle_credits(int(amount))
	else:
		body.restore(pickup_kind, amount)
	var sound := "pickup/moneyup.wav" if pickup_kind == "credits" else "pickup/pickup_energy.wav"
	AudioDirector.play_3d(sound, global_position, -2.0)
	queue_free()
