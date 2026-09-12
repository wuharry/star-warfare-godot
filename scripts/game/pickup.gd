class_name WarfarePickup
extends Area3D

const OriginalVisual = preload("res://scripts/game/original_pickup_visual.gd")

var pickup_kind := "credits"
var amount := 10.0
var clock := 0.0
var collected := false
var moving_up := true
var visual: Node3D
var model: OriginalPickupVisual
var halo: OriginalPickupVisual
var collision: CollisionShape3D

func configure(kind: String, value: float) -> void:
	# Legacy "ammo" drops restore the same pool; original LootType has only two kinds.
	pickup_kind = "energy" if kind == "ammo" else kind
	amount = value

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	collision = CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8 # Original SphereCollider radius 2 * prefab scale 0.4.
	collision.shape = shape
	add_child(collision)
	visual = Node3D.new()
	add_child(visual)
	model = OriginalVisual.create("Money" if pickup_kind == "credits" else "Enegy", true)
	visual.add_child(model)
	halo = OriginalVisual.create("Halo", true)
	# LootManagerScript replaces Halo's authored 0.01 scale with world scale 0.4.
	(halo.get_child(0) as Node3D).scale = Vector3.ONE * 0.4
	visual.add_child(halo)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	clock += delta
	model.rotation.y -= deg_to_rad(45.0) * delta
	# Spawn at floor + 1, then move between floor + 1.2 and floor + 1.5.
	visual.position.y = move_toward(visual.position.y, 0.5 if moving_up else 0.2, delta * 0.2)
	collision.position.y = visual.position.y
	if visual.position.y >= 0.5:
		moving_up = false
	elif visual.position.y <= 0.2 and not moving_up:
		moving_up = true
	var camera := get_viewport().get_camera_3d()
	if camera != null and halo.global_position.distance_squared_to(camera.global_position) > 0.001:
		halo.look_at(camera.global_position)
	if clock >= 60.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if collected or not body is WarfarePlayer:
		return
	collected = true
	if pickup_kind == "credits":
		var world := get_parent()
		if world.has_method("add_battle_credits"):
			world.add_battle_credits(int(amount))
	else:
		body.restore(pickup_kind, amount)
	var effect := OriginalVisual.create("effect_pick_gold_001" if pickup_kind == "credits" else "effect_pick_energy_001", true)
	# Outlive the consumed drop, following the player at the original +1 height.
	body.add_child(effect)
	effect.position = Vector3.UP
	var sound := "pickup/pickup_money%02d.wav" % randi_range(1, 2) if pickup_kind == "credits" else "pickup/pickup_energy.wav"
	AudioDirector.play_3d(sound, body.global_position, -2.0)
	queue_free()
