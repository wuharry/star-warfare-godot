class_name WarfareEnemy
extends CharacterBody3D

signal died(enemy: WarfareEnemy, death_position: Vector3, reward: int, score_value: int)
signal health_reported(current: float, maximum: float, is_boss: bool)
signal source_effect_spawned(effect: Node3D, description: Dictionary)
signal source_loot_requested(position: Vector3, kind: String, amount: int)
signal source_knockback_requested(player: Node3D, signed_source_step: float)

const ProjectileScript = preload("res://scripts/game/projectile.gd")
const MonsterCatalog = preload("res://scripts/core/monster_catalog.gd")
const SourceBrain = preload("res://scripts/game/enemy_source_brain.gd")
const DragonBrain = preload("res://scripts/game/enemy_dragon_brain.gd")
const SourceProjectile = preload("res://scripts/game/enemy_source_projectile.gd")
const MantisBrain = preload("res://scripts/game/enemy_mantis_brain.gd")
const GroundBossBrain = preload("res://scripts/game/enemy_ground_boss_brain.gd")
const MachineBrain = preload("res://scripts/game/enemy_machine_brain.gd")
const SourceHazard = preload("res://scripts/game/enemy_source_hazard.gd")
const SourceBeam = preload("res://scripts/game/enemy_source_beam.gd")
const SourceHitGeometry = preload("res://scripts/game/enemy_source_hit_geometry.gd")
const SourcePickup = preload("res://scripts/game/pickup.gd")
const FLESH_HIT_LIGHT := "res://assets/audio/non_original/enemy_hit_light.wav"
const FLESH_HIT_HEAVY := "res://assets/audio/non_original/enemy_hit_heavy_or_lethal.wav"
const HITBOX_PROFILES := {
	"crawler": Vector2(0.95, 2.00),
	"spitter": Vector2(1.00, 2.00),
	"brute": Vector2(1.00, 2.00),
	"boss": Vector2(1.80, 3.60),
}

# Visible height in metres, measured on the posed skin rather than the mesh AABB
# (see _normalize_recovered_enemy for why those two disagree). The player capsule
# is 1.82m tall, so a warrior reads as marginally taller than the player.
const TARGET_HEIGHTS := {
	"crawler": 2.00,
	"spitter": 2.05,
	"brute": 2.10,
	"boss": 3.20,
}

# Far enemies use one damage box enclosing their animated bone bounds instead
# of updating each limb's physics shape. The walking capsule remains separate.
# Two thresholds keep an enemy pacing the boundary from flipping every frame.
const HULL_NEAR_DISTANCE := 26.0
const HULL_FAR_DISTANCE := 32.0

var target: WarfarePlayer
var enemy_kind := "crawler"
var max_health := 60.0
var health := 60.0
var speed := 4.1
var attack_damage := 10.0
# Crawler default. Measured from body centre, so it tracks TARGET_HEIGHTS: a
# 2.0 m warrior reaches roughly 1.5 m forward and the player capsule adds 0.46,
# leaving the same small gap the 1.24 m warrior used to strike from.
var attack_range := 2.2
var attack_interval := 1.0
var attack_cooldown := 0.0
var reward := 18
var score_value := 100
var source_monster_id := -1
var source_monster_name := ""
var experience_value := 0
var projectile_speed := 16.0
var projectile_splash := 0.75
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
var hulls_active := true
var recovered_enemy: Node3D
var animated_hitbox: EnemyHitGeometry
var recovered_animation_player: AnimationPlayer
var recovered_animation_name := ""
var hit_reaction_left := 0.0
var flesh_hit_cooldown := 0.0
var spawn_left := 0.82
var spawn_depth := 1.35
var original_runtime := false
var configuration_error := ""
var source_spec: Dictionary = {}
var source_brain: RefCounted
var source_flame: MeshInstance3D
var source_ground_y := 0.0
var source_ground_refresh := 0.0
var source_beam: MeshInstance3D
var source_sockets: Dictionary = {}

# --- Tactical brain (veteran / elite difficulty only) -----------------------
# On "recruit" every field below stays zeroed and _physics_process falls through
# to _legacy_step, which is the original beeline behaviour byte for byte.
var tactical := false
var reaction_time := 0.0
var aim_lead := 0.0
var aim_spread := 0.0
var melee_windup := 0.0
var flank_spread := 0.0
var separation_radius := 0.0
var strafe_strength := 0.0
var suppression_strength := 0.0
var sight_check := false
var reaction_left := 0.0
var windup_left := 0.0
var flank_angle := 0.0
var flank_refresh := 0.0
var strafe_sign := 1.0
var suppressed_left := 0.0
var separation_vector := Vector3.ZERO
var separation_refresh := 0.0
var token_hold_left := 0.0
var holds_attack_token := false
var target_velocity := Vector3.ZERO
var last_target_position := Vector3.INF

func configure(player: WarfarePlayer, kind: String, health_value: float, is_elite := false) -> void:
	original_runtime = false
	configuration_error = ""
	source_brain = null
	source_spec = {}
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
	_apply_difficulty_profile()

func configure_recovered(player: WarfarePlayer, kind: String, health_scale := 1.0, is_elite := false) -> void:
	# Keep the explicit-health configure API for diagnostic fixtures. Live worlds
	# use the model-matched source HP, attack, movement and reward fields here.
	if not MonsterCatalog.RUNTIME_IDS.has(kind):
		configure_original(player, MonsterCatalog.id_for_kind(kind), health_scale, is_elite)
		return
	configure(player, kind, 1.0, false)
	var data := MonsterCatalog.for_kind(kind)
	if data.is_empty():
		configuration_error = "unknown_enemy_kind:" + kind
		return
	source_monster_id = int(data.id)
	source_monster_name = str(data.name)
	var attack: Array = data.attacks[0]
	max_health = float(data.hp) * maxf(0.01, health_scale)
	if float(data.speed) > 0.0:
		speed = float(data.speed)
	# Boss movement and zero-range melee actions are controlled by their state
	# machines in Unity. Keep the restoration's movement/reach for those zeros.
	attack_damage = float(attack[1])
	if float(attack[2]) > 0.0:
		attack_interval = float(attack[2]) * float(GameState.get_difficulty_profile().get("attack_speed", 1.0))
	if kind == "spitter":
		attack_range = float(attack[3])
		projectile_speed = maxf(1.0, float(attack[8]))
		projectile_splash = float(attack[4])
	reward = int(data.credits)
	experience_value = int(data.experience)
	elite = is_elite
	if elite:
		max_health *= 1.65
		speed *= 1.16
		attack_damage *= 1.35
		reward *= 2
		experience_value *= 2
		score_value *= 2
	health = max_health


## Numeric EnemyType entry point for campaign/survival. Call before add_child;
## false means no spawn and configuration_error explains why. The caller must
## surface the missing-content error, not consume a wave slot or award a kill.
func configure_original(player: WarfarePlayer, monster_id: int, health_scale := 1.0, is_elite := false, difficulty_level := 0) -> bool:
	if is_inside_tree():
		configuration_error = "configure_original_requires_unparented_enemy"
		return false
	var spec := MonsterCatalog.runtime_spec(monster_id, difficulty_level, is_elite)
	if spec.is_empty():
		configuration_error = "unknown_enemy_id:%d" % monster_id
		return false
	if not bool(spec.spawnable):
		configuration_error = ";".join(PackedStringArray(spec.blockers))
		return false
	if not is_finite(health_scale) or health_scale <= 0.0:
		configuration_error = "invalid_health_scale"
		return false
	configure(player, str(spec.kind), 1.0, false)
	original_runtime = true
	tactical = false # Source states own attack timing, steering and immunity.
	source_spec = spec
	source_monster_id = monster_id
	source_monster_name = str(spec.name)
	max_health = float(spec.hp) * health_scale
	health = max_health
	speed = float(spec.speed)
	attack_damage = float(spec.damage)
	attack_range = float(spec.attack_range)
	attack_interval = float(spec.get("attack_interval", 0.9))
	reward = int(spec.credits)
	experience_value = int(spec.experience)
	score_value = maxi(100, experience_value)
	elite = bool(spec.elite)
	match monster_id:
		8, 13: source_brain = GroundBossBrain.new()
		9, 11, 12: source_brain = MantisBrain.new()
		10: source_brain = DragonBrain.new()
		14: source_brain = MachineBrain.new()
		_: source_brain = SourceBrain.new()
	source_brain.configure(spec)
	return true


func is_boss_enemy() -> bool:
	return bool(source_spec.get("is_boss", false)) if original_runtime else enemy_kind == "boss"


func get_source_spec() -> Dictionary:
	return source_spec.duplicate(true) if original_runtime else MonsterCatalog.runtime_spec(source_monster_id)


## Pair once both numeric 11/12 actors exist. No world-global singleton.
func link_source_partner(other: WarfareEnemy) -> bool:
	if not original_runtime or source_monster_id not in [11, 12] or not is_instance_valid(other): return false
	if not other.original_runtime or other.source_monster_id != (12 if source_monster_id == 11 else 11): return false
	source_brain.link_partner(other)
	other.source_brain.link_partner(self)
	return true


func _presentation_kind() -> String:
	if original_runtime:
		return str({0: "crawler", 2: "spitter", 3: "brute", 10: "boss"}.get(source_monster_id, enemy_kind))
	return enemy_kind

func _apply_difficulty_profile() -> void:
	var profile := GameState.get_difficulty_profile()
	tactical = bool(profile.get("tactical", false))
	attack_interval *= float(profile.get("attack_speed", 1.0))
	if not tactical:
		return
	reaction_time = float(profile.get("reaction", 0.0))
	aim_lead = float(profile.get("aim_lead", 0.0))
	aim_spread = float(profile.get("aim_spread", 0.0))
	melee_windup = float(profile.get("melee_windup", 0.0))
	flank_spread = float(profile.get("flank_spread", 0.0))
	separation_radius = float(profile.get("separation", 0.0))
	strafe_strength = float(profile.get("strafe", 0.0))
	suppression_strength = float(profile.get("suppression", 0.0))
	sight_check = bool(profile.get("sight_check", false))
	# Stagger the first decision so a wave does not think in lockstep.
	reaction_left = reaction_time * randf_range(0.6, 1.4)
	flank_angle = randf_range(-1.0, 1.0) * flank_spread * PI * 0.55
	flank_refresh = randf_range(1.2, 3.0)
	separation_refresh = randf_range(0.0, 0.2)
	strafe_sign = 1.0 if randf() < 0.5 else -1.0

func _ready() -> void:
	if not configuration_error.is_empty():
		push_warning("Enemy spawn rejected: " + configuration_error)
		queue_free()
		return
	name = "Enemy_%s" % enemy_kind
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	_build_collision()
	_build_visual()
	if original_runtime and not recovered_enemy:
		configuration_error = "unable_to_load_source_model:" + str(source_spec.model_path)
		push_warning(configuration_error)
		remove_from_group("enemies")
		queue_free()
		return
	if recovered_enemy:
		animated_hitbox = SourceHitGeometry.new() if original_runtime else EnemyHitGeometry.new()
		add_child(animated_hitbox)
		animated_hitbox.build(model)
		if not animated_hitbox.parts.is_empty():
			collision_layer = 0
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
	if original_runtime and is_boss_enemy():
		spawn_left = 0.0
		source_ground_y = global_position.y
		source_brain.start_action(self, "init")
	elif spawn_left > 0.0:
		_begin_grave_spawn()
	health_reported.emit(health, max_health, is_boss_enemy())

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "EnemyHitbox"
	var capsule := CapsuleShape3D.new()
	var profile: Vector2 = HITBOX_PROFILES.get(_presentation_kind(), HITBOX_PROFILES.crawler)
	capsule.radius = profile.x
	capsule.height = profile.y
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
	var animated_name: String = str(source_spec.model) if original_runtime else str(MonsterCatalog.RUNTIME_MODELS.get(enemy_kind, "bug01"))
	var animated_path := str(source_spec.model_path) if original_runtime else "res://assets/models/enemies/animated/%s/%s.gltf" % [animated_name, animated_name]
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
	if not recovered_enemy and not original_runtime:
		push_warning("Legacy enemy uses procedural body: missing " + animated_path)
		_add_sphere(Vector3(1.35, 0.62, 1.72) * scale_factor, Vector3(0, 0.85, 0) * scale_factor, body_material, "Abdomen")
		_add_sphere(Vector3(0.78, 0.5, 0.72) * scale_factor, Vector3(0, 0.93, -0.86) * scale_factor, body_material, "Head")
		for side in [-1.0, 1.0]:
			for leg_index in range(3):
				var leg := _add_box(Vector3(0.1, 0.11, 1.05) * scale_factor, Vector3(side * (0.58 + leg_index * 0.09), 0.49, -0.15 + leg_index * 0.42) * scale_factor, body_material, "Leg")
				leg.rotation.y = side * (0.62 + leg_index * 0.18)
				leg.rotation.z = side * 0.18
			_add_sphere(Vector3(0.13, 0.13, 0.08) * scale_factor, Vector3(side * 0.25, 1.05, -1.2) * scale_factor, eye_material, "Eye")
	if enemy_kind == "spitter" and not original_runtime:
		_add_sphere(Vector3(0.46, 0.46, 0.46), Vector3(0, 1.3, 0.42), eye_material, "AcidSac")
	if enemy_kind == "boss" and not original_runtime:
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
	var bind_bounds := _combined_mesh_aabb(recovered_enemy)
	# Mesh.get_aabb() is the unskinned bind pose, not the visible idle body.
	# Sample the actual skin before scaling or grounding it.
	if recovered_animation_player and recovered_animation_player.has_animation("idle"):
		recovered_animation_player.play("idle")
		recovered_animation_player.advance(0.0)
		recovered_animation_player.seek(0.0, true)
	var bounds := EnemyHitGeometry.posed_bounds(recovered_enemy)
	if bounds.size.y <= 0.001:
		bounds = bind_bounds
	if bounds.size.y <= 0.001:
		return
	if original_runtime:
		# Numeric API keeps the source prefab's authored scale. Attack ranges in
		# Spider/Mantis/Earthworm are metres, so normalising every boss to 2m
		# would disconnect its claws/tail from the sourced hit distances.
		recovered_enemy.position = Vector3(0.0, -bounds.position.y * recovered_enemy.scale.y, 0.0)
		spawn_depth = minf(bounds.size.y * recovered_enemy.scale.y * 0.82, 2.4)
		return
	# Scale against the posed skin, not the mesh AABB. The AABB reads like the
	# authored size but measures the unposed bind layout, which runs 1.4x tall
	# for a warrior and 3x for the folded-up boss -- so every TARGET_HEIGHTS
	# entry landed short. Measured in tests/enemy_scale_probe.tscn: the boss
	# stood 1.68 m beside a 1.82 m player while its table entry said 5.0.
	var target_height: float = float(TARGET_HEIGHTS.get(_presentation_kind(), TARGET_HEIGHTS.crawler))
	var factor: float = target_height / bounds.size.y
	recovered_enemy.scale = Vector3.ONE * factor
	recovered_enemy.position = Vector3(0.0, -bounds.position.y * factor, 0.0)
	spawn_depth = minf(target_height * 0.82, 2.4)

func _prepare_recovered_animations() -> void:
	if not recovered_animation_player:
		return
	for animation_name in recovered_animation_player.get_animation_list():
		if animation_name in ["idle", "run", "run01", "run02", "fly_idle", "fly_walk", "fly_Sprint", "fly_Sprint02", "chong", "fuchong02", "jump02", "attack_dash_idle", "attack_dash_fastidle", "attack_joky"]:
			recovered_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR

func _play_recovered_animation(animation_name: String, blend := 0.1, restart := false) -> void:
	if not recovered_animation_player or not recovered_animation_player.has_animation(animation_name):
		return
	if not restart and recovered_animation_name == animation_name:
		return
	recovered_animation_name = animation_name
	recovered_animation_player.play(animation_name, blend)
	if restart:
		recovered_animation_player.seek(0.0, true)

func _begin_grave_spawn() -> void:
	model.position.y = -spawn_depth
	_play_recovered_animation("run", 0.0)
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
	if original_runtime:
		path = str(source_spec.get("voice", ""))
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
		if is_instance_valid(animated_hitbox):
			animated_hitbox.sync_pose()
		velocity = Vector3.ZERO
		if spawn_left <= 0.0:
			_play_recovered_animation("idle")
		return
	if not is_instance_valid(target) or target.dead:
		_release_attack_token()
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = -0.4
		else:
			velocity.y -= gravity * delta
		move_and_slide()
		_play_recovered_animation("idle")
		if original_runtime: source_set_flame(false)
		return
	if original_runtime:
		_source_physics_step(delta)
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	hit_reaction_left = maxf(0.0, hit_reaction_left - delta)
	flesh_hit_cooldown = maxf(0.0, flesh_hit_cooldown - delta)
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
	_update_hull_detail(distance)
	var movement_offset := navigation_target - global_position
	var planar := Vector3(movement_offset.x, 0.0, movement_offset.z)
	var desired := Vector3.ZERO
	if tactical:
		_track_target_velocity(delta)
		desired = _tactical_step(delta, target_offset, distance, planar)
	else:
		_face_planar_direction(planar)
		desired = _legacy_step(distance, planar)
	velocity.x = move_toward(velocity.x, desired.x, 16.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 16.0 * delta)
	if is_on_floor():
		velocity.y = -0.4
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_update_animation(delta, desired.length())

func _update_hull_detail(distance: float) -> void:
	if dead or not is_instance_valid(animated_hitbox) or animated_hitbox.parts.is_empty():
		return
	var want_hulls := distance <= HULL_FAR_DISTANCE if hulls_active else distance < HULL_NEAR_DISTANCE
	if want_hulls == hulls_active:
		return
	hulls_active = want_hulls
	animated_hitbox.set_coarse(not want_hulls)

func _legacy_step(distance: float, planar: Vector3) -> Vector3:
	# Original "recruit" behaviour: walk the path straight at the player and
	# swing the moment the range check passes. Left untouched on purpose.
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
	return desired

func _tactical_step(delta: float, offset: Vector3, distance: float, planar: Vector3) -> Vector3:
	var los := _has_sight_to_target()
	# Track the player while engaged; only steer by the waypoint heading when
	# the path is blocked and we are navigating around geometry.
	if los:
		_face_planar_direction(Vector3(offset.x, 0.0, offset.z))
	else:
		_face_planar_direction(planar)

	if reaction_left > 0.0:
		reaction_left = maxf(0.0, reaction_left - delta)
		return Vector3.ZERO

	# A committed strike roots the enemy for its telegraph, which is the window
	# the player dashes out of.
	if windup_left > 0.0:
		windup_left = maxf(0.0, windup_left - delta)
		if windup_left <= 0.0:
			_resolve_melee_windup()
		return Vector3.ZERO

	if token_hold_left > 0.0:
		token_hold_left = maxf(0.0, token_hold_left - delta)
		if token_hold_left <= 0.0:
			_release_attack_token()

	suppressed_left = maxf(0.0, suppressed_left - delta)
	_refresh_separation(delta)
	_refresh_flank(delta)

	if enemy_kind == "boss":
		return _tactical_boss(distance, planar, los)
	if enemy_kind == "spitter":
		return _tactical_ranged(distance, planar, los)
	return _tactical_melee(distance, planar, los)

func _tactical_melee(distance: float, planar: Vector3, los: bool) -> Vector3:
	if distance <= attack_range and attack_cooldown <= 0.0 and los:
		if _claim_attack_token():
			_begin_melee_windup()
			return Vector3.ZERO
	# Not our turn to strike, so take an approach lane around the player rather
	# than queueing up behind whoever is already swinging.
	return _approach_velocity(planar, los, attack_range * 0.85)

func _tactical_ranged(distance: float, planar: Vector3, los: bool) -> Vector3:
	var band := attack_range * 0.72
	var can_fire := los and attack_cooldown <= 0.0 and distance <= attack_range
	if can_fire and distance > attack_range * 0.28 and _claim_attack_token():
		_ranged_attack()
		token_hold_left = attack_interval * 0.5
		return Vector3.ZERO
	if not los:
		return _approach_velocity(planar, los, band)
	# Hold the firing band and keep sidestepping so the spitter is never a
	# stationary silhouette while its acid sac recharges.
	var to_player := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z)
	if to_player.length_squared() < 0.001:
		return Vector3.ZERO
	var forward := to_player.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x) * strafe_sign
	var direction := side * maxf(strafe_strength, 0.35)
	if distance > band * 1.15:
		direction += forward
	elif distance < band * 0.7:
		direction -= forward
	direction += separation_vector * 0.35
	if direction.length_squared() <= 0.001:
		return Vector3.ZERO
	return direction.normalized() * speed * 0.9

func _tactical_boss(distance: float, planar: Vector3, los: bool) -> Vector3:
	# The boss never queues for a token; it is the fight.
	if distance <= attack_range and attack_cooldown <= 0.0:
		_boss_attack(distance)
		return Vector3.ZERO
	if distance <= attack_range:
		return Vector3.ZERO
	var direction := _approach_velocity(planar, los, attack_range * 0.8)
	return direction * (2.1 if charge_timer > 0.0 else 1.0)

func _approach_velocity(planar: Vector3, los: bool, band: float) -> Vector3:
	var direction := Vector3.ZERO
	if los and is_instance_valid(target):
		var slot := _flank_position(maxf(band, 1.2))
		direction = Vector3(slot.x - global_position.x, 0.0, slot.z - global_position.z)
		if direction.length_squared() < 0.04:
			direction = Vector3.ZERO
		else:
			direction = direction.normalized()
			var side := Vector3(-direction.z, 0.0, direction.x) * strafe_sign
			direction += side * strafe_strength * (1.0 + suppressed_left)
	elif planar.length_squared() > 0.001:
		direction = planar.normalized()
	direction += separation_vector * 0.35
	if direction.length_squared() <= 0.001:
		return Vector3.ZERO
	return direction.normalized() * speed

func _flank_position(radius: float) -> Vector3:
	# Offset the enemy's own bearing to the player by its assigned lane, so the
	# pack fans out across the ring instead of stacking on one approach.
	var to_enemy := Vector3(global_position.x - target.global_position.x, 0.0,
		global_position.z - target.global_position.z)
	if to_enemy.length_squared() < 0.01:
		to_enemy = Vector3.FORWARD
	var angle := atan2(to_enemy.x, to_enemy.z) + flank_angle
	return target.global_position + Vector3(sin(angle), 0.0, cos(angle)) * radius

func _refresh_flank(delta: float) -> void:
	flank_refresh -= delta
	if flank_refresh > 0.0:
		return
	flank_refresh = randf_range(2.4, 4.2)
	flank_angle = randf_range(-1.0, 1.0) * flank_spread * PI * 0.55
	if randf() < 0.5:
		strafe_sign = -strafe_sign

func _refresh_separation(delta: float) -> void:
	separation_refresh -= delta
	if separation_refresh > 0.0:
		return
	separation_refresh = randf_range(0.16, 0.26)
	separation_vector = Vector3.ZERO
	if separation_radius <= 0.0:
		return
	var radius_squared := separation_radius * separation_radius
	var origin := global_position
	for other_node in get_tree().get_nodes_in_group("enemies"):
		var other := other_node as Node3D
		if other == self or not is_instance_valid(other):
			continue
		var other_origin := other.global_position
		var dx := origin.x - other_origin.x
		var dz := origin.z - other_origin.z
		var gap_squared := dx * dx + dz * dz
		# Reject on the squared gap first. Past a handful of enemies almost every
		# pair is out of range, and this skips the square root for all of them.
		if gap_squared <= 0.000001 or gap_squared >= radius_squared:
			continue
		var gap := sqrt(gap_squared)
		separation_vector += Vector3(dx, 0.0, dz) / gap * (1.0 - gap / separation_radius)

func _has_sight_to_target() -> bool:
	if not sight_check or not is_instance_valid(target):
		return true
	var world := get_parent()
	if world and world.has_method("has_line_of_sight"):
		return bool(world.has_line_of_sight(global_position, target.global_position))
	return true

func _claim_attack_token() -> bool:
	if holds_attack_token:
		return true
	var world := get_parent()
	if world and world.has_method("request_attack_token"):
		holds_attack_token = bool(world.request_attack_token(self))
		return holds_attack_token
	holds_attack_token = true
	return true

func _release_attack_token() -> void:
	if not holds_attack_token:
		return
	holds_attack_token = false
	token_hold_left = 0.0
	var world := get_parent()
	if world and world.has_method("release_attack_token"):
		world.release_attack_token(self)

func _track_target_velocity(delta: float) -> void:
	if not is_instance_valid(target) or delta <= 0.0:
		return
	var current := target.global_position
	if last_target_position == Vector3.INF:
		last_target_position = current
		return
	var sample := (current - last_target_position) / delta
	sample.y = 0.0
	target_velocity = target_velocity.lerp(sample, clampf(delta * 8.0, 0.0, 1.0))
	last_target_position = current

func _begin_melee_windup() -> void:
	attack_cooldown = attack_interval
	windup_left = melee_windup
	_play_recovered_animation("attack", 0.04)
	# Growl on the wind-up, not the impact: that is the audio tell.
	AudioDirector.play_3d(
		"enemy/mantis/tanglang_attack_01.wav" if enemy_kind == "boss" else "enemies_smash1.wav",
		global_position, -11.0, randf_range(0.66, 0.78)
	)
	var tween := create_tween()
	tween.tween_property(model, "position:z", -0.55, maxf(melee_windup, 0.06))

func _resolve_melee_windup() -> void:
	_release_attack_token()
	var tween := create_tween()
	tween.tween_property(model, "position:z", 0.0, 0.18)
	if not is_instance_valid(target) or target.dead:
		return
	# The strike only lands if the player is still inside the lunge when the
	# telegraph ends, so dashing out of it is a real dodge.
	if global_position.distance_to(target.global_position) > attack_range * 1.35:
		return
	target.take_damage(attack_damage, target.global_position, self)
	AudioDirector.play_3d("enemies_smash1.wav", global_position, -7.0, randf_range(0.92, 1.07))

func _predicted_aim_point(projectile_speed: float) -> Vector3:
	var aim := target.global_position + Vector3.UP * 0.9
	if not tactical:
		return aim
	var range_to_target := global_position.distance_to(aim)
	if aim_lead > 0.0 and projectile_speed > 0.01:
		aim += target_velocity * (range_to_target / projectile_speed) * aim_lead
	if aim_spread > 0.0:
		var spread := aim_spread * range_to_target
		aim += Vector3(
			randf_range(-spread, spread),
			randf_range(-spread, spread) * 0.4,
			randf_range(-spread, spread)
		)
	return aim

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
	_play_recovered_animation("attack", 0.04)
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
	var travel := (_predicted_aim_point(projectile_speed) - origin).normalized()
	projectile.configure(self, travel, projectile_speed, attack_damage, projectile_splash, Color(0.6, 0.15, 0.9), true)
	get_parent().add_child(projectile)
	projectile.global_position = origin

func _boss_attack(distance: float) -> void:
	if randf() < 0.55 or distance > 3.0:
		attack_cooldown = attack_interval * 1.8
		for angle in [-0.22, 0.0, 0.22]:
			var projectile := ProjectileScript.new()
			var origin := global_position + Vector3.UP * 2.5
			var aim := _predicted_aim_point(18.0)
			var travel := (aim - origin).normalized().rotated(Vector3.UP, angle)
			projectile.configure(self, travel, 18.0, attack_damage * 0.72, 1.6, Color(1.0, 0.13, 0.03), true)
			get_parent().add_child(projectile)
			projectile.global_position = origin
	else:
		charge_timer = 0.72
		_melee_attack()
		# _melee_attack sets the normal cooldown; the boss charge has its own
		# longer authored recovery and must override it after the shared call.
		attack_cooldown = attack_interval * 1.4

func take_damage(amount: float, _hit_position := Vector3.ZERO, _source: Node = null) -> void:
	if dead:
		return
	if original_runtime and source_monster_id < 8:
		amount = source_brain.damage_received(amount, spawn_left > 0.0)
	elif original_runtime and source_brain.has_method("damage_received"):
		amount = source_brain.damage_received(amount)
	if amount <= 0.0:
		return
	var health_before := health
	health = maxf(0.0, health - amount)
	var actual_damage := maxf(0.0, health_before - health)
	# Player hits are sounded by local hit/kill confirmation, without a
	# duplicate positional copy. Other damage sources retain world impacts.
	if actual_damage > 0.0 and not (_source is WarfarePlayer):
		_play_flesh_impact(_hit_position)
	# Armor powers such as HEALTH STEAL must use damage that actually reached
	# this enemy (excluding overkill), not the weapon's requested raw damage.
	if actual_damage > 0.0 and is_instance_valid(_source) and _source.has_method("on_damage_dealt"):
		_source.on_damage_dealt(actual_damage)
	if tactical and suppression_strength > 0.0 and enemy_kind != "boss":
		# Taking fire breaks the current lane: sidestep and pick a new approach
		# instead of walking up the barrel like the original AI did.
		suppressed_left = suppression_strength
		flank_refresh = minf(flank_refresh, 0.2)
		if randf() < 0.5:
			strafe_sign = -strafe_sign
	if original_runtime:
		if is_boss_enemy():
			source_brain.on_damage(self)
		elif health > 0.0 and source_brain.stagger(source_clip_length("attacked", 0.22)):
			_play_recovered_animation("attacked", 0.03, true)
	else:
		var attacked_animation := "attacked"
		hit_reaction_left = 0.22
		if recovered_animation_player and recovered_animation_player.has_animation(attacked_animation):
			hit_reaction_left = clampf(recovered_animation_player.get_animation(attacked_animation).length, 0.16, 0.38)
		_play_recovered_animation(attacked_animation, 0.03, true)
	health_reported.emit(health, max_health, is_boss_enemy())
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
		_die(_source)

func _play_flesh_impact(hit_position: Vector3) -> void:
	# Shotguns report several pellets in the same physics frame. Keep one solid
	# transient per enemy instead of stacking identical samples into clipping.
	# A lethal pellet must still replace the preceding light impact.
	if flesh_hit_cooldown > 0.0 and health > 0.0:
		return
	var lethal := health <= 0.0
	var sound_path := FLESH_HIT_HEAVY if lethal else FLESH_HIT_LIGHT
	var impact_position := hit_position
	if impact_position == Vector3.ZERO:
		impact_position = global_position + Vector3.UP * 0.85
	AudioDirector.play_3d(
		sound_path,
		impact_position,
		-2.5 if lethal else -4.5,
		randf_range(0.92, 1.06),
		"enemy_flesh_hit_%d" % get_instance_id()
	)
	flesh_hit_cooldown = 0.045

func _die(killer: Node = null) -> void:
	if dead:
		return
	dead = true
	source_set_flame(false)
	source_set_beam(false)
	if original_runtime and source_brain.has_method("on_death"): source_brain.on_death(self)
	if is_instance_valid(animated_hitbox):
		animated_hitbox.collision_layer = 0
		# The corpse plays its death clip for another 1.15 s and used to keep
		# every hull in step with it -- work nothing can hit any more.
		animated_hitbox.release()
	if is_instance_valid(killer) and killer.has_method("on_enemy_defeated"):
		killer.on_enemy_defeated()
	_release_attack_token()
	collision_layer = 0
	collision_mask = 0
	# Death audio comes from the player's HUD or the non-player world impact.
	var death_clip: String = source_brain.death_animation() if original_runtime and source_brain.has_method("death_animation") else "dead"
	_play_recovered_animation(death_clip, 0.04)
	died.emit(self, global_position, reward, score_value)
	var tween := create_tween()
	tween.tween_interval(source_clip_length(death_clip, 1.15) if original_runtime else (1.15 if recovered_animation_player else 0.18))
	tween.tween_property(model, "position:y", -0.65, 0.42).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(queue_free)


func _source_physics_step(delta: float) -> void:
	flesh_hit_cooldown = maxf(0.0, flesh_hit_cooldown - delta)
	source_ground_refresh -= delta
	navigation_refresh -= delta
	if navigation_refresh <= 0.0 or navigation_target == Vector3.INF or global_position.distance_squared_to(navigation_target) < 1.7:
		navigation_refresh = 0.5
		var world := get_parent()
		navigation_target = world.get_enemy_navigation_target(global_position, target.global_position) if world and world.has_method("get_enemy_navigation_target") else target.global_position
	var planar := navigation_target - global_position
	planar.y = 0.0
	var distance := source_planar_distance()
	_update_hull_detail(distance)
	var desired: Vector3 = source_brain.step(self, delta, distance, planar, source_has_sight())
	if dead:
		return
	velocity.x = desired.x
	velocity.z = desired.z
	if is_boss_enemy() and source_brain.vertical_control:
		velocity.y = desired.y
	elif source_monster_id == 6:
		velocity.y = clampf((source_floor_height() + 2.4 - global_position.y) / maxf(delta, 0.001), -10.0, 10.0)
	else:
		velocity.y = -0.4 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	_play_recovered_animation(source_brain.animation_name())
	if recovered_animation_player and "animation_speed" in source_brain:
		recovered_animation_player.speed_scale = source_brain.animation_speed


func source_clip_length(clip: String, fallback: float) -> float:
	if recovered_animation_player and recovered_animation_player.has_animation(clip):
		return recovered_animation_player.get_animation(clip).length
	return fallback


func source_target_direction() -> Vector3:
	if not is_instance_valid(target): return Vector3.ZERO
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset.normalized()


func source_planar_distance() -> float:
	if not is_instance_valid(target): return INF
	var offset := target.global_position - global_position
	return Vector2(offset.x, offset.z).length()


func source_forward() -> Vector3:
	return -global_transform.basis.z.normalized()


func source_target_angle() -> float:
	# Unity's +Z -> Godot's -Z handedness conversion reverses signed yaw.
	return -rad_to_deg(source_forward().signed_angle_to(source_target_direction(), Vector3.UP))


func source_target_in_cone(reach: float, half_angle: float) -> bool:
	return is_instance_valid(target) and source_planar_distance() < reach and absf(source_target_angle()) < half_angle and source_has_sight()


func source_has_sight(offset := Vector3.ZERO) -> bool:
	if not is_instance_valid(target): return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5 + offset,
		target.global_position + Vector3.UP * 0.5, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func source_has_rush_clearance() -> bool:
	return source_has_sight(global_transform.basis.x) and source_has_sight(-global_transform.basis.x)


func source_floor_height() -> float:
	if source_ground_refresh <= 0.0:
		source_ground_refresh = 0.2
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, global_position + Vector3.DOWN * 30.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and Vector3(hit.normal).y > 0.5:
			source_ground_y = Vector3(hit.position).y
	return source_ground_y


func source_damage_target(damage: float, knock_step := 0.0) -> void:
	if not dead and is_instance_valid(target) and not target.dead:
		target.take_damage(damage, target.global_position, self)
		source_knock_player(target, knock_step)


func source_knock_player(player: Node3D, knock_step: float) -> void:
	if knock_step <= 0.0 or not is_instance_valid(player) or player.dead: return
	# Enemy.CheckKnocked signs the original per-Update displacement using the
	# victim's facing. The player owns animation, interruption and delta scaling.
	var facing := -player.global_basis.z
	if player.has_method("get_enemy_knockback_forward"):
		facing = player.get_enemy_knockback_forward()
	facing.y = 0.0
	var toward_enemy := global_position - player.global_position
	toward_enemy.y = 0.0
	var signed_step := -knock_step if facing.dot(toward_enemy) < 0.0 else knock_step
	if player.has_method("apply_enemy_knockback"):
		player.apply_enemy_knockback(signed_step)
	else:
		source_knockback_requested.emit(player, signed_step)


func source_sound(path: String) -> void:
	AudioDirector.play_3d(path, global_position, -8.0)


func source_normal_shot(attack: Dictionary, monster_id: int) -> void:
	if not is_instance_valid(target): return
	var origin := global_position + Vector3.UP * (0.8 if monster_id == 6 else 2.0)
	var aim := target.global_position + Vector3.UP * (0.6 if monster_id == 6 else 1.5)
	var travel: Vector3
	var gravity_value := 0.0
	if monster_id == 6:
		travel = (aim - origin).normalized() * 12.0 # Mutalisk.cs overrides table speed 17.
	else:
		gravity_value = 9.81
		var flight_time := (aim - global_position).length() / 12.0
		travel = SourceProjectile.ballistic_velocity(origin, aim, flight_time)
	var direct := 0.0 if monster_id == 5 else float(attack.damage)
	var splash := float(attack.damage) if monster_id == 5 else float(attack.splash_damage)
	var radius := float(attack.bomb_radius) if monster_id == 5 else float(attack.splash_radius)
	_source_projectile(origin, travel, gravity_value, direct, splash, radius, false)


func source_dragon_shot(flying: bool) -> void:
	if not is_instance_valid(target): return
	var origin := source_muzzle()
	if flying:
		var aim := target.global_position + Vector3.UP * 0.1
		_source_projectile(origin, (aim - origin).normalized() * 30.0, 0.0, 1400.0, 3200.0, 4.0, true)
	else:
		for degrees: float in [45.0, 22.5, 0.0, -22.5, -45.0]:
			_source_projectile(origin, source_forward().rotated(Vector3.UP, deg_to_rad(degrees)) * 22.0, 0.0, 700.0, 2100.0, 5.0, true)
	source_sound("enemy/dragon/long_fly_attack.wav" if flying else "enemy/dragon/long_tuxi_1.wav")


func _source_projectile(origin: Vector3, travel: Vector3, gravity_value: float, direct: float, splash: float, radius: float, through_walls: bool) -> void:
	var projectile := SourceProjectile.new()
	projectile.source = self
	projectile.target = target
	projectile.travel_velocity = travel
	projectile.gravity_strength = gravity_value
	projectile.direct_damage = direct
	projectile.area_damage = splash
	projectile.area_radius = radius
	projectile.ignore_blast_walls = through_walls
	# Resources/effect/Dragonball.prefab SphereCollider has radius 0.5.
	projectile.collision_radius = 0.5 if source_monster_id == 10 else 0.0
	projectile.tint = Color(1.0, 0.25, 0.03) if source_monster_id == 10 else Color(0.5, 0.85, 0.15)
	get_parent().add_child(projectile)
	projectile.global_position = origin


func source_damage_receivers() -> Array[Node3D]:
	var receivers: Array[Node3D] = []
	for candidate in get_tree().get_nodes_in_group("player"):
		if candidate is Node3D and candidate.has_method("take_damage") and not candidate.dead:
			receivers.append(candidate)
	if is_instance_valid(target) and not target.dead and not receivers.has(target): receivers.append(target)
	return receivers


func source_muzzle() -> Vector3:
	var fallback := global_position + Vector3.UP * 2.5 + source_forward() * 1.5
	match source_monster_id:
		8: return (source_socket("Bone L ya", fallback).origin + source_socket("Bone R ya", fallback).origin) * 0.5
		9, 11, 12: return source_socket("Bone mouth02", fallback).origin
		10: return source_socket("Bone mouth 02", fallback).origin
		13: return source_socket("Bone01", fallback).origin
		14: return source_socket("Dummy_Laser_F", fallback).origin
	return fallback


func source_socket(bone_name: String, fallback: Vector3) -> Transform3D:
	if not source_sockets.has(bone_name) and is_instance_valid(recovered_enemy):
		for node in recovered_enemy.find_children("*", "Skeleton3D", true, false):
			var skeleton := node as Skeleton3D
			var index := skeleton.find_bone(bone_name)
			if index >= 0:
				source_sockets[bone_name] = [skeleton, index]
				break
		if not source_sockets.has(bone_name):
			var socket := recovered_enemy.find_child(bone_name, true, false) as Node3D
			if socket: source_sockets[bone_name] = [socket, -1]
	if source_sockets.has(bone_name):
		var binding: Array = source_sockets[bone_name]
		if int(binding[1]) >= 0: return binding[0].global_transform * binding[0].get_bone_global_pose(binding[1])
		return binding[0].global_transform
	return Transform3D(Basis.IDENTITY, fallback)


func source_boss_sound(action: String) -> void:
	var sound := ""
	match source_monster_id:
		8:
			sound = str({"attack": "juxingjiachong_attack_04", "double": "juxingjiachong_attack_04", "shot": "juxingjiachong_duye", "continuous": "juxingjiachong_taunt", "jump_up": "juxingjiachong_jump1", "jump_end": "juxingjiachong_jump03", "stagger": "juxingjiachong_hurt", "rage": "juxingjiachong_rage"}.get(action, ""))
			if not sound.is_empty(): sound = "spider/" + sound
		9, 11, 12:
			sound = str({"takeoff": "feixingtanglang_qifei", "coop_join": "feixingtanglang_qifei", "slash": "tanglang_attack_01", "critical": "tanglang_attack_01", "shot": "tanglang_fly_attack01", "laser": "tanglang_jiguang", "coop_laser": "tanglang_jiguang", "boomerang": "feixingtanglang_fly_attack_03", "landing": "feixingtanglang_luodi", "dive": "feixingtanglang_fuchong2", "stagger": "tanglang_attacked", "rage": "feixingtanglang_gongjiqian"}.get(action, ""))
			if not sound.is_empty(): sound = "mantis/" + sound
		13:
			sound = str({"shot": "attack_spit1", "continuous": "attack_spit2", "attack": "attack_tail1", "drill_in": "ground_in", "drill_out": "ground_out1", "stagger": "hit", "rage": "rage", "rush_start": "attack_dash_start"}.get(action, ""))
			if not sound.is_empty(): sound = "earthworm/" + sound
		14:
			sound = str({"stomp": "jixiebichuidigongji", "laser": "laser", "gift": "kongqipaofashe", "ball": "kongqipaofashe", "rage": "xiaochouxiaosheng", "whirl": "xiaochouxiaosheng"}.get(action, ""))
			if not sound.is_empty(): sound = "satanmachine/" + sound
	if not sound.is_empty() and ResourceLoader.exists("res://assets/original/audio/enemy/" + sound + ".wav"):
		source_sound("enemy/" + sound + ".wav")


func source_emit_projectile(description: Dictionary) -> Node3D:
	var shot := SourceProjectile.new()
	shot.source = self
	shot.target = target
	shot.collision_radius = 0.5 if source_monster_id == 10 else 0.0
	for key: String in description:
		if key != "position": shot.set(key, description[key])
	get_parent().add_child(shot)
	shot.global_position = description.get("position", source_muzzle())
	source_effect_spawned.emit(shot, description.duplicate(true))
	return shot


func source_mantis_shot(damage: float) -> void:
	var origin := source_muzzle()
	var aim := (target.global_position + Vector3.UP - origin).normalized()
	for angle: float in [-22.0, 0.0, 22.0]:
		source_emit_projectile({"position": origin, "travel_velocity": aim.rotated(Vector3.UP, deg_to_rad(angle)) * 22.0,
			"direct_damage": damage, "tint": Color(0.6, 0.15, 1.0)})


func source_mantis_boomerang(damage: float) -> void:
	for values: Array in [[55.0, 25.0, 9.0, 1.2, 24.0], [-40.0, 30.0, 11.0, 1.0, 30.0]]:
		var initial := source_forward().rotated(Vector3.UP, -deg_to_rad(values[0]))
		initial = (initial * cos(deg_to_rad(values[1])) + Vector3.UP * sin(deg_to_rad(values[1]))).normalized()
		source_emit_projectile({"position": source_muzzle(), "travel_velocity": initial * float(values[2]),
			"direct_damage": damage, "homing_delay": values[3], "homing_turn_rate": 7.0,
			"homing_speed": values[4], "lock_target_once": true, "tint": Color(0.6, 0.15, 1.0)})


func source_boss_spit(earthworm: bool, yaw: float, pitch: float, slime_scale: float) -> void:
	var origin := source_muzzle()
	var aim := target.global_position + Vector3.UP * 0.5
	var time := maxf(0.1, source_planar_distance() / (24.0 if earthworm else 20.0))
	var travel := SourceProjectile.ballistic_velocity(origin, aim, time)
	travel = travel.rotated(Vector3.UP, deg_to_rad(yaw)).rotated(global_transform.basis.x, deg_to_rad(pitch))
	source_emit_projectile({"position": origin, "travel_velocity": travel, "gravity_strength": 9.81,
		"direct_damage": 5560.0 if earthworm else 1760.0,
		"hazard": {"radius": (1.7 if earthworm else 3.0) * slime_scale,
			"damage": 660.0 if earthworm else 440.0, "lifetime": 20.0 if earthworm else 12.0,
			"interval": 0.6, "shared_timer": true, "growth_time": slime_scale / 5.0,
			"slow_multiplier": 0.3 if earthworm else 1.0}})


func source_spawn_hazard(at: Vector3, description: Dictionary) -> Node3D:
	var hazard := SourceHazard.new()
	hazard.source = self
	hazard.target = target
	for key: String in description: hazard.set(key, description[key])
	get_parent().add_child(hazard)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 35.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	hazard.global_position = Vector3(at.x, float(hit.position.y) + 0.06 if not hit.is_empty() else source_floor_height() + 0.06, at.z)
	var data := description.duplicate(true)
	data["effect_type"] = "hazard"
	data["position"] = hazard.global_position
	source_effect_spawned.emit(hazard, data)
	return hazard


func source_damage_near(at: Vector3, radius: float, damage: float, knock_step := 0.0) -> bool:
	var hit := false
	for player in source_damage_receivers():
		if player.global_position.distance_squared_to(at) < radius * radius:
			player.take_damage(damage, at, self)
			source_knock_player(player, knock_step)
			hit = true
	return hit


func source_shockwave(inner: float, outer: float, inner_damage: float, outer_damage: float, inner_knock := 0.0, outer_knock := 0.0) -> void:
	for player in source_damage_receivers():
		var distance := player.global_position.distance_to(global_position)
		if distance < outer:
			player.take_damage(inner_damage if distance < inner else outer_damage, global_position, self)
			source_knock_player(player, inner_knock if distance < inner else outer_knock)
	source_telegraph(global_position, outer, 0.5)


func source_telegraph(at: Vector3, radius: float, lifetime: float) -> void:
	var ring := MeshInstance3D.new()
	ring.set_meta("visual_provenance", "procedural source attack warning")
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - 0.15)
	mesh.outer_radius = radius
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.05, 0.6)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	ring.mesh = mesh
	get_parent().add_child(ring)
	ring.global_position = at + Vector3.UP * 0.1
	var fade := ring.create_tween()
	fade.tween_interval(lifetime * 0.75)
	fade.tween_property(material, "albedo_color:a", 0.0, lifetime * 0.25)
	fade.tween_callback(ring.queue_free)


func source_set_hidden(hidden: bool) -> void:
	model.visible = not hidden
	if is_instance_valid(animated_hitbox): animated_hitbox.collision_layer = 0 if hidden else 2
	else: collision_layer = 0 if hidden else 2


func source_relocate_drill(random: RandomNumberGenerator) -> void:
	# Earthworm.DrillIdle: intersect the far wall from a random arena point;
	# emerge at the target, keeping ten metres of wall clearance when required.
	var from := Vector3(random.randf_range(-16.0, 20.0), source_floor_height() + 1.0, random.randf_range(-14.5, 9.5))
	var aim := target.global_position
	aim.y = from.y
	var direction := (aim - from).normalized()
	var ray := PhysicsRayQueryParameters3D.create(from, from + direction * 100.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var position_value := aim
	if not hit.is_empty() and Vector3(hit.position).distance_to(aim) < 10.0:
		position_value = Vector3(hit.position) - direction * 10.0
	position_value.y = source_floor_height()
	global_position = position_value
	_face_planar_direction(direction)
	source_ground_refresh = 0.0


func source_tail_center() -> Vector3:
	var socket := source_socket("Bip01 Tail12", global_position - source_forward() * 7.0)
	var point := socket.origin - socket.basis.x.normalized() * 2.0
	return Vector3(point.x, source_floor_height() + 0.02, point.z)


func source_wall_point(from: Vector3, direction: Vector3) -> Dictionary:
	from.y = source_floor_height() + 1.0
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * 100.0, 1))


func source_relocate_super_rush(random: RandomNumberGenerator) -> void:
	var inside := Vector3(random.randf_range(-16.0, 20.0), source_floor_height() + 1.0, random.randf_range(-14.5, 9.5))
	var away := (inside - Vector3(target.global_position.x, inside.y, target.global_position.z)).normalized()
	var wall := source_wall_point(inside, away)
	# Missing walls are possible in isolated test arenas; keep a bounded path
	# there. Real Boss5 uses the source wall intersection + 80m entry offset.
	var boundary: Vector3 = wall.position if not wall.is_empty() else inside + away * 20.0
	global_position = Vector3(boundary.x, source_ground_y, boundary.z) + away * 80.0
	source_telegraph(boundary, 3.0, 1.5)


func source_beam_hits(direction: Vector3, reach: float, radius: float) -> bool:
	if not is_instance_valid(target): return false
	var offset := target.global_position + Vector3.UP * 0.6 - source_laser_origin()
	var along := offset.dot(direction)
	return along > 0.0 and along < reach and (offset - direction * along).length() < radius + 0.46


func source_laser_origin() -> Vector3:
	# Mantis laser follows the animated mouth, with its source -0.1m offset.
	return source_muzzle() - Vector3.UP * 0.1


func source_set_beam(active: bool, direction := Vector3.FORWARD, reach := 45.0, tint := Color.PURPLE, radius := 0.3) -> void:
	if not active:
		if is_instance_valid(source_beam): source_beam.visible = false
		return
	if not is_instance_valid(source_beam):
		source_beam = MeshInstance3D.new()
		source_beam.set_meta("visual_provenance", "procedural source laser")
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = reach
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		source_beam.mesh = mesh
		add_child(source_beam)
	source_beam.visible = true
	source_beam.global_position = source_laser_origin() + direction * reach * 0.5
	source_beam.global_basis = Basis(Quaternion(Vector3.UP, direction.normalized()))


func source_machine_missiles() -> void:
	for side: float in [-1.0, 1.0]:
		var front := source_socket("Dummy_fire_R_F01" if side < 0.0 else "Dummy_fire_L_F", source_muzzle() + global_transform.basis.x * side * 2.5).origin
		var back := source_socket("Dummy_fire_R_B01" if side < 0.0 else "Dummy_fire_L_B", front - source_forward()).origin
		source_emit_projectile({"position": front,
			"travel_velocity": (front - back).normalized() * 18.0, "area_damage": 4000.0, "area_radius": 1.0,
			"ignore_blast_walls": true, "homing_delay": 0.0, "homing_turn_rate": 2.0,
			"homing_speed": 18.0, "lifetime": 10.0, "tint": Color.ORANGE})


func source_machine_laser(direction: Vector3) -> void:
	var beam := SourceBeam.new()
	beam.source = self
	beam.direction = direction
	get_parent().add_child(beam)
	beam.global_position = source_muzzle()
	source_effect_spawned.emit(beam, {"effect_type": "beam", "position": beam.global_position, "direction": direction})


func source_machine_bombs(poison: bool, random: RandomNumberGenerator) -> void:
	for index in range(8):
		var side := -1.0 if random.randi_range(1, 2) == 1 else 1.0
		var force := Vector3(random.randi_range(6, 11) * side, 4.0, random.randi_range(-12, 11))
		if random.randi_range(1, 2) == 2: force = Vector3(force.z, force.y, force.x)
		force.x *= source_forward().x
		force.z *= source_forward().z
		var description := {"position": source_socket("Dummy_Bag_F", global_position + Vector3.UP * 4.0).origin,
			"travel_velocity": force, "gravity_strength": 9.81, "ground_fuse": float(random.randi_range(1, 2)),
			"area_damage": 5000.0 if poison else 3000.0, "area_radius": 4.0,
			"ignore_blast_walls": true, "lifetime": 10.0 if poison else 6.0,
			"tint": Color(0.3, 0.8, 0.1) if poison else Color.RED}
		if poison:
			description["hazard"] = {"radius": 2.8, "damage": 1000.0, "interval": 0.2,
				"lifetime": 5.0, "shared_timer": false, "ground_only": false, "growth_time": 0.01}
		elif random.randf() < 0.5:
			# Four actual gift prefabs: money 50/100, energy 50/100.
			var variant := random.randi_range(0, 3)
			description["loot"] = {"kind": "credits" if variant < 2 else "energy", "amount": 50 if variant % 2 == 0 else 100}
		source_emit_projectile(description)


func source_drop_gift(at: Vector3, description: Dictionary) -> void:
	if source_loot_requested.has_connections():
		source_loot_requested.emit(at, str(description.kind), int(description.amount))
		return
	var pickup := SourcePickup.new()
	pickup.configure(str(description.kind), float(description.amount))
	get_parent().add_child(pickup)
	pickup.global_position = at + Vector3.UP


func source_explode(damage: float, radius: float) -> void:
	if dead: return
	if is_instance_valid(target) and global_position.distance_squared_to(target.global_position) < radius * radius:
		source_damage_target(damage)
	health = 0.0
	health_reported.emit(health, max_health, false)
	source_sound("rpg/rpg-21_boom.wav")
	var flash := MeshInstance3D.new()
	flash.set_meta("visual_provenance", "procedural explosion")
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.55, 0.08, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	flash.mesh = mesh
	get_parent().add_child(flash)
	flash.global_position = global_position
	flash.scale = Vector3.ONE * 0.1
	var burst := flash.create_tween()
	burst.tween_property(flash, "scale", Vector3.ONE, 0.16)
	burst.tween_property(material, "albedo_color:a", 0.0, 0.2)
	burst.tween_callback(flash.queue_free)
	model.visible = false
	_die()


func source_set_flame(active: bool) -> void:
	if not active:
		if is_instance_valid(source_flame): source_flame.visible = false
		return
	if not is_instance_valid(source_flame):
		source_flame = MeshInstance3D.new()
		source_flame.set_meta("visual_provenance", "procedural flame; Unity mouth effect is not exported")
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.15
		mesh.bottom_radius = 2.0
		mesh.height = 12.0
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.3, 0.02, 0.4)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		source_flame.mesh = mesh
		source_flame.position = Vector3(0.0, 2.0, -7.0)
		source_flame.rotation.x = PI * 0.5
		add_child(source_flame)
	source_flame.visible = true

func _update_animation(delta: float, movement: float) -> void:
	if recovered_animation_player:
		var animation_name := ""
		if hit_reaction_left > 0.0:
			animation_name = "attacked"
		elif attack_cooldown > attack_interval * 0.7:
			animation_name = "attack"
		else:
			animation_name = "run" if movement > 0.1 else "idle"
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
