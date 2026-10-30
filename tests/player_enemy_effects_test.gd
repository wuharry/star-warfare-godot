extends Node3D

const Hazard = preload("res://scripts/game/enemy_source_hazard.gd")
var failures: Array[String] = []
var actor: WarfarePlayer

class QuietEnemy extends WarfareEnemy:
	func _ready() -> void:
		set_physics_process(false)

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _box(at: Vector3, size_value: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_value
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = at
	return body

func _step(frames: int) -> void:
	for frame in frames:
		await get_tree().physics_frame
		actor._physics_process(1.0 / 60.0)

func _run() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	actor = WarfarePlayer.new()
	add_child(actor)
	actor.set_physics_process(false)
	actor.armor_skills = {}
	actor.move_speed = 8.0
	actor.current_weapon.speed_drag = 0.0
	actor.current_weapon.move_speed_multiplier = 1.0
	actor.set_touch_move(Vector2(0, -1))
	await _step(25)
	check(is_equal_approx(actor.velocity.z, -8.0), "Source slow fixture did not reach normal movement speed")
	var pool := Hazard.new()
	pool.slow_multiplier = 0.5
	pool.radius = 50.0
	pool.damage = 0.0
	pool.target = actor
	add_child(pool)
	pool.set_physics_process(false)
	pool._physics_process(0.25)
	await _step(20)
	check(is_equal_approx(actor.velocity.z, -4.0), "Single-player ignored the source hazard slow")
	pool.free()
	await _step(20)
	check(is_equal_approx(actor.velocity.z, -8.0), "Leaving a source hazard kept the slow")
	actor.set_touch_move(Vector2.ZERO)
	actor.position = Vector3(0, 0.1, 0)
	actor.velocity = Vector3.ZERO
	actor.body_yaw = PI / 2.0
	actor.model.rotation.y = actor.body_yaw
	var enemy := QuietEnemy.new()
	add_child(enemy)
	enemy.position = Vector3(-2, 0, 0)
	enemy.source_knock_player(actor, 0.16)
	check(actor.enemy_knockback_velocity.x > 9.5 and absf(actor.enemy_knockback_velocity.z) < 0.01, "Frontal hit did not push away using avatar facing")
	check(actor.enemy_knockback_animation == "attacked" and actor.enemy_knockback_left > 0.0, "Front hit omitted its authored animation")
	var rounds := actor._magazine_rounds()
	actor.shot_cooldown = 0.0
	actor._try_fire()
	check(actor._magazine_rounds() == rounds, "Knocked player could fire")
	var wall := _box(Vector3(1.0, 2, 0), Vector3(0.2, 4, 10))
	await _step(ceili(actor.enemy_knockback_left * 60.0) + 2)
	check(actor.position.x > 0.05 and actor.position.x < 0.9, "Knockback failed to move or passed through solid wall")
	check(actor.enemy_knockback_left == 0.0, "Knockback never released control")
	wall.free()
	actor.position = Vector3(0, 0.1, 0)
	actor.velocity = Vector3.ZERO
	enemy.position = Vector3(2, 0, 0)
	enemy.source_knock_player(actor, 0.16)
	check(actor.enemy_knockback_velocity.x < -9.5 and actor.enemy_knockback_animation == "attacked_back", "Rear hit lost its signed direction/animation")
	actor.dead = true
	actor.health = 0.0
	check(actor.revive(1.0) and actor.enemy_knockback_left == 0.0, "Revival kept stale knockback")
	actor.free()
	enemy.free()
	AudioDirector.stop_all_sfx()
	await get_tree().create_timer(0.2).timeout
	print("PLAYER_ENEMY_EFFECTS_%s slow=exit=facing=collision=interrupt=revival" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
