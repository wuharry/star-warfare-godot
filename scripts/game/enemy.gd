class_name WarfareEnemy
extends CharacterBody3D

signal died(enemy: WarfareEnemy, death_position: Vector3, reward: int, score_value: int)
signal health_reported(current: float, maximum: float, is_boss: bool)

const ProjectileScript = preload("res://scripts/game/projectile.gd")

var target: WarfarePlayer
var enemy_kind := "crawler"
var max_health := 60.0
var health := 60.0
var speed := 4.1
var attack_damage := 10.0
var attack_range := 1.6
var attack_interval := 1.0
var attack_cooldown := 0.0
var reward := 18
var score_value := 100
var dead := false
var elite := false
var gravity := 24.0
var model: Node3D
var body_material: StandardMaterial3D
var eye_material: StandardMaterial3D
var hit_tween: Tween
var locomotion_clock := 0.0
var charge_timer := 0.0
var voice: AudioStreamPlayer3D
var navigation_target := Vector3.INF
var navigation_refresh := 0.0
var recovered_enemy: Node3D
var recovered_animation_player: AnimationPlayer
var recovered_animation_name := ""
var spawn_left := 0.82
var spawn_depth := 1.35

func configure(player: WarfarePlayer, kind: String, health_value: float, is_elite := false) -> void:
	target = player
	enemy_kind = kind
	elite = is_elite
	max_health = health_value
	if kind == "spitter":
		max_health *= 0.82
		speed = 3.3
		attack_damage = 12.0
		attack_range = 15.5
		attack_interval = 2.0
		reward = 24
		score_value = 140
	elif kind == "brute":
		max_health *= 2.25
		speed = 2.7
		attack_damage = 24.0
		attack_range = 2.25
		attack_interval = 1.35
		reward = 42
		score_value = 260
	elif kind == "boss":
		max_health *= 12.0
		speed = 3.0
		attack_damage = 28.0
		attack_range = 5.0
		attack_interval = 1.05
		reward = 650
		score_value = 5000
	if elite:
		max_health *= 1.65
		speed *= 1.16
		attack_damage *= 1.35
		reward *= 2
		score_value *= 2
	health = max_health

func _ready() -> void:
	name = "Enemy_%s" % enemy_kind
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1
	_build_collision()
	_build_visual()
	_build_audio()
	# Choose the first recovered waypoint before the grave-rise animation locks
	# movement. The enemy emerges already oriented toward a valid route.
	if is_instance_valid(target):
		var world := get_parent()
		if world and world.has_method("get_enemy_navigation_target"):
			navigation_target = world.get_enemy_navigation_target(global_position, target.global_position)
		else:
			navigation_target = target.global_position
		_face_planar_direction(navigation_target - global_position)
	_begin_grave_spawn()
	health_reported.emit(health, max_health, enemy_kind == "boss")

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var scale_factor := 2.45 if enemy_kind == "boss" else (1.45 if enemy_kind == "brute" else 1.0)
	capsule.radius = 0.62 * scale_factor
	capsule.height = 1.35 * scale_factor
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	add_child(collision)

func _build_visual() -> void:
	model = Node3D.new()
	model.name = "AlienModel"
	add_child(model)
	var base_color := Color(0.22, 0.66, 0.25)
	if enemy_kind == "spitter":
		base_color = Color(0.48, 0.22, 0.74)
	elif enemy_kind == "brute":
		base_color = Color(0.68, 0.2, 0.12)
	elif enemy_kind == "boss":
		base_color = Color(0.18, 0.08, 0.04)
	if elite:
		base_color = Color(0.78, 0.56, 0.1)
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = base_color
	body_material.roughness = 0.64
	body_material.metallic = 0.08
	eye_material = StandardMaterial3D.new()
	eye_material.albedo_color = Color(1.0, 0.12, 0.02)
	eye_material.emission_enabled = true
	eye_material.emission = Color(1.0, 0.025, 0.005)
	eye_material.emission_energy_multiplier = 4.0

	var scale_factor := 2.35 if enemy_kind == "boss" else (1.42 if enemy_kind == "brute" else 1.0)
	var animated_name: String = str({
		"crawler": "bug01", "spitter": "bug03", "brute": "bug04", "boss": "boss01"
	}.get(enemy_kind, "bug01"))
	var animated_path := "res://assets/models/enemies/animated/%s/%s.gltf" % [animated_name, animated_name]
	if ResourceLoader.exists(animated_path):
		var packed := load(animated_path) as PackedScene
		if packed:
			recovered_enemy = packed.instantiate() as Node3D
			if recovered_enemy:
				recovered_enemy.name = "RecoveredAnimated_%s" % animated_name
				model.add_child(recovered_enemy)
				recovered_animation_player = _find_animation_player(recovered_enemy)
				_normalize_recovered_enemy()
				_prepare_recovered_animations()
	if not recovered_enemy:
		_add_sphere(Vector3(1.35, 0.62, 1.72) * scale_factor, Vector3(0, 0.85, 0) * scale_factor, body_material, "Abdomen")
		_add_sphere(Vector3(0.78, 0.5, 0.72) * scale_factor, Vector3(0, 0.93, -0.86) * scale_factor, body_material, "Head")
		for side in [-1.0, 1.0]:
			for leg_index in range(3):
				var leg := _add_box(Vector3(0.1, 0.11, 1.05) * scale_factor, Vector3(side * (0.58 + leg_index * 0.09), 0.49, -0.15 + leg_index * 0.42) * scale_factor, body_material, "Leg")
				leg.rotation.y = side * (0.62 + leg_index * 0.18)
				leg.rotation.z = side * 0.18
			_add_sphere(Vector3(0.13, 0.13, 0.08) * scale_factor, Vector3(side * 0.25, 1.05, -1.2) * scale_factor, eye_material, "Eye")
	if enemy_kind == "spitter":
		_add_sphere(Vector3(0.46, 0.46, 0.46), Vector3(0, 1.3, 0.42), eye_material, "AcidSac")
	if enemy_kind == "boss":
		for side in [-1.0, 1.0]:
			var horn := _add_box(Vector3(0.28, 1.3, 0.28), Vector3(side * 1.25, 2.6, -1.2), eye_material, "Horn")
			horn.rotation.z = side * 0.35

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _combined_mesh_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if not instance.mesh:
			continue
		var relative := root.global_transform.affine_inverse() * instance.global_transform
		var bounds := relative * instance.mesh.get_aabb()
		result = result.merge(bounds) if has_bounds else bounds
		has_bounds = true
	return result

func _normalize_recovered_enemy() -> void:
	if not recovered_enemy:
		return
	var bounds := _combined_mesh_aabb(recovered_enemy)
	if bounds.size.y <= 0.001:
		return
	var target_height: float = float({
		"crawler": 1.7, "spitter": 1.9, "brute": 2.5, "boss": 5.0
	}.get(enemy_kind, 1.7))
	var factor: float = float(target_height) / bounds.size.y
	recovered_enemy.scale = Vector3.ONE * factor
	recovered_enemy.position = Vector3(0.0, -bounds.position.y * factor, 0.0)
	spawn_depth = minf(float(target_height) * 0.82, 2.4)

func _prepare_recovered_animations() -> void:
	if not recovered_animation_player:
		return
	for animation_name in recovered_animation_player.get_animation_list():
		if animation_name in ["idle", "run", "run01", "run02", "fly_idle", "fly_walk"]:
			recovered_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR

func _play_recovered_animation(animation_name: String, blend := 0.1) -> void:
	if not recovered_animation_player or not recovered_animation_player.has_animation(animation_name):
		return
	if recovered_animation_name == animation_name and recovered_animation_player.is_playing():
		return
	recovered_animation_name = animation_name
	recovered_animation_player.play(animation_name, blend)

func _begin_grave_spawn() -> void:
	model.position.y = -spawn_depth
	_play_recovered_animation("fly_walk" if enemy_kind == "boss" else "run", 0.0)
	var dust := GPUParticles3D.new()
	dust.name = "RecoveredGraveSmoke"
	dust.amount = 22
	dust.lifetime = 0.85
	dust.one_shot = true
	dust.explosiveness = 0.72
	dust.position.y = 0.08
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 68.0
	process.initial_velocity_min = 1.3
	process.initial_velocity_max = 3.4
	process.gravity = Vector3(0, -2.8, 0)
	process.scale_min = 0.18
	process.scale_max = 0.52
	process.color = Color(0.3, 0.27, 0.2, 0.76)
	dust.process_material = process
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.13
	particle_mesh.height = 0.18
	particle_mesh.radial_segments = 6
	particle_mesh.rings = 3
	dust.draw_pass_1 = particle_mesh
	add_child(dust)
	dust.emitting = true
	get_tree().create_timer(1.2).timeout.connect(dust.queue_free)

func _build_audio() -> void:
	voice = AudioStreamPlayer3D.new()
	voice.bus = &"SFX"
	voice.max_distance = 40.0
	voice.volume_db = -8.0
	var recovered := {
		"crawler": "res://assets/original/audio/enemy/gongchong.wav",
		"spitter": "res://assets/original/audio/enemy/xeiweichong.wav",
		"brute": "res://assets/original/audio/enemy/daxingjiachong.wav",
		"boss": "res://assets/original/audio/enemy/mantis/feixingtanglang_fly_idle.wav"
	}
	var path := str(recovered.get(enemy_kind, recovered.crawler))
	if ResourceLoader.exists(path):
		voice.stream = load(path)
	add_child(voice)
	if voice.stream and randf() < 0.35:
		voice.pitch_scale = randf_range(0.75, 1.15)
		voice.play()

func _physics_process(delta: float) -> void:
	if dead:
		return
	if spawn_left > 0.0:
		spawn_left = maxf(0.0, spawn_left - delta)
		var ratio := 1.0 - spawn_left / 0.82
		model.position.y = lerpf(-spawn_depth, 0.0, smoothstep(0.0, 1.0, ratio))
		velocity = Vector3.ZERO
		if spawn_left <= 0.0:
			_play_recovered_animation("fly_idle" if enemy_kind == "boss" else "idle")
		return
	if not is_instance_valid(target) or target.dead:
		velocity = Vector3.ZERO
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	charge_timer = maxf(0.0, charge_timer - delta)
	navigation_refresh -= delta
	if navigation_refresh <= 0.0 or navigation_target == Vector3.INF or global_position.distance_squared_to(navigation_target) < 1.7:
		navigation_refresh = randf_range(0.42, 0.68)
		var world := get_parent()
		if world and world.has_method("get_enemy_navigation_target"):
			navigation_target = world.get_enemy_navigation_target(global_position, target.global_position)
		else:
			navigation_target = target.global_position
	var target_offset := target.global_position - global_position
	var distance := target_offset.length()
	var movement_offset := navigation_target - global_position
	var planar := Vector3(movement_offset.x, 0.0, movement_offset.z)
	_face_planar_direction(planar)
	var desired := Vector3.ZERO
	if enemy_kind == "spitter":
		if distance > attack_range * 0.82:
			desired = planar.normalized() * speed
		elif distance < 7.0:
			desired = -planar.normalized() * speed * 0.65
		elif attack_cooldown <= 0.0:
			_ranged_attack()
	elif enemy_kind == "boss":
		if distance > attack_range:
			desired = planar.normalized() * speed * (2.1 if charge_timer > 0.0 else 1.0)
		elif attack_cooldown <= 0.0:
			_boss_attack(distance)
	else:
		if distance > attack_range:
			desired = planar.normalized() * speed
		elif attack_cooldown <= 0.0:
			_melee_attack()
	velocity.x = move_toward(velocity.x, desired.x, 16.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 16.0 * delta)
	if is_on_floor():
		velocity.y = -0.4
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_update_animation(delta, desired.length())

func _face_planar_direction(direction: Vector3) -> void:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() <= 0.001:
		return
	# Unity meshes author +Z as forward. Handedness conversion maps that to
	# Godot's conventional -Z, so use the default look_at model front. Passing
	# use_model_front=true here made every recovered monster face backwards.
	look_at(global_position + planar.normalized(), Vector3.UP)

func _melee_attack() -> void:
	attack_cooldown = attack_interval
	_play_recovered_animation("fly_attack" if enemy_kind == "boss" else "attack", 0.04)
	if is_instance_valid(target):
		target.take_damage(attack_damage, target.global_position, self)
	AudioDirector.play_3d("enemy/mantis/tanglang_attack_01.wav" if enemy_kind == "boss" else "enemies_smash1.wav", global_position, -7.0, randf_range(0.92, 1.07))
	var tween := create_tween()
	tween.tween_property(model, "position:z", -0.55, 0.1)
	tween.tween_property(model, "position:z", 0.0, 0.18)

func _ranged_attack() -> void:
	attack_cooldown = attack_interval
	_play_recovered_animation("attack", 0.04)
	if not is_instance_valid(target):
		return
	AudioDirector.play_3d("enemy/feixingchong.wav", global_position, -8.0, randf_range(0.94, 1.05))
	var projectile := ProjectileScript.new()
	var origin := global_position + Vector3.UP * 1.15
	var travel := (target.global_position + Vector3.UP * 0.9 - origin).normalized()
	projectile.configure(self, travel, 16.0, attack_damage, 0.75, Color(0.6, 0.15, 0.9), true)
	get_parent().add_child(projectile)
	projectile.global_position = origin

func _boss_attack(distance: float) -> void:
	if randf() < 0.55 or distance > 3.0:
		attack_cooldown = attack_interval * 1.8
		for angle in [-0.22, 0.0, 0.22]:
			var projectile := ProjectileScript.new()
			var origin := global_position + Vector3.UP * 2.5
			var travel := (target.global_position + Vector3.UP - origin).normalized().rotated(Vector3.UP, angle)
			projectile.configure(self, travel, 18.0, attack_damage * 0.72, 1.6, Color(1.0, 0.13, 0.03), true)
			get_parent().add_child(projectile)
			projectile.global_position = origin
	else:
		charge_timer = 0.72
		attack_cooldown = attack_interval * 1.4
		_melee_attack()

func take_damage(amount: float, _hit_position := Vector3.ZERO, _source: Node = null) -> void:
	if dead:
		return
	health = maxf(0.0, health - amount)
	_play_recovered_animation("fly_attacked" if enemy_kind == "boss" else "attacked", 0.03)
	health_reported.emit(health, max_health, enemy_kind == "boss")
	if randf() < 0.34:
		AudioDirector.play_3d("enemy/mantis/tanglang_attacked.wav" if enemy_kind == "boss" else "enemies_smash2.wav", global_position, -10.0, randf_range(0.9, 1.08))
	if is_instance_valid(hit_tween):
		hit_tween.kill()
	body_material.emission_enabled = true
	body_material.emission = Color(1.0, 0.35, 0.1)
	body_material.emission_energy_multiplier = 3.5
	hit_tween = create_tween()
	hit_tween.tween_interval(0.055)
	hit_tween.tween_callback(func():
		if is_instance_valid(body_material): body_material.emission_enabled = false
	)
	if health <= 0.0:
		_die()

func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	var death_sound := "enemy/mantis/tanglang_dead.wav" if enemy_kind == "boss" else ("enemy/zibaochong.wav" if enemy_kind == "spitter" else "enemies_smash2.wav")
	AudioDirector.play_3d(death_sound, global_position, -4.0, randf_range(0.86, 1.08))
	_play_recovered_animation("dead", 0.04)
	died.emit(self, global_position, reward, score_value)
	var tween := create_tween()
	tween.tween_interval(1.15 if recovered_animation_player else 0.18)
	tween.tween_property(model, "position:y", -0.65, 0.42).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(queue_free)

func _update_animation(delta: float, movement: float) -> void:
	if recovered_animation_player:
		var animation_name := ""
		if attack_cooldown > attack_interval * 0.7:
			animation_name = "fly_attack" if enemy_kind == "boss" else "attack"
		else:
			animation_name = ("fly_walk" if movement > 0.1 else "fly_idle") if enemy_kind == "boss" else ("run" if movement > 0.1 else "idle")
		_play_recovered_animation(animation_name)
		return
	locomotion_clock += delta * (7.0 + movement)
	model.position.y = sin(locomotion_clock) * (0.06 if movement > 0.1 else 0.025)
	model.rotation.z = sin(locomotion_clock * 0.5) * 0.035

func _add_box(size: Vector3, position_value: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position_value
	model.add_child(instance)
	return instance

func _add_sphere(scale_value: Vector3, position_value: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 7
	mesh.material = material
	instance.mesh = mesh
	instance.scale = scale_value
	instance.position = position_value
	model.add_child(instance)
	return instance
