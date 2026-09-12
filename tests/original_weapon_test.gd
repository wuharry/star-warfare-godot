extends Node3D
var failures: Array[String]=[]
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
func _ready() -> void:
	var expected := {
		"gun11":"Effect/Projectile","gun12":"Effect/Projectile","gun13":"Effect/Projectile",
		"gun30":"Effect/BlackStar/DAN","gun14":"Effect/GrenadeShot","gun15":"Effect/GrenadeShot","gun16":"Effect/GrenadeShot",
		"gun41":"Effect/GrenadeShot","gun45":"SW2_Effect/HotWing_Bullet","gun22":"Effect/LightBow_Shot",
		"gun29":"Effect/Trinity/Bow_Shot","gun44":"Effect/update_effect/effect_thearrow_attack","gun23":"Effect/update_effect/effect_fist_attack_002",
		"gun33":"Effect/update_effect/effect_sword_flying_001","gun36":"Effect/update_effect/effect_arrow_t","gun42":"Effect/update_effect/effect_arrow_t_purple","gun37":"Effect/PingPongShot"}
	for key: String in expected:
		var profile: Dictionary=GameState.WEAPONS[key]
		var projectile:=WarfareProjectile.new()
		projectile.configure(null,Vector3.FORWARD,profile.speed,10,profile.splash,profile.color,false,"windblade" if key=="gun33" else profile.kind,profile.explosion_sound,key)
		add_child(projectile)
		projectile.set_physics_process(false)
		var originals:=projectile.visual_root.get_children().filter(func(n):return n is OriginalWeaponEffect)
		check(originals.size()==1,key+" still uses fallback projectile")
		if originals.size()==1:
			check(originals[0].source_prefab==expected[key],key+" wrong source projectile")
		var meshes:=projectile.find_children("SourceMesh","MeshInstance3D",true,false)
		check(not meshes.is_empty(),key+" has no original mesh")
		for mesh: MeshInstance3D in meshes:
			for surface in mesh.mesh.get_surface_count():
				var material:=mesh.get_active_material(surface) as ShaderMaterial
				check(material!=null,key+" missing shader")
				if material!=null:check(material.get_shader_parameter("tex")!=null,key+" missing texture")
		var count_before:=get_child_count()
		projectile._impact(Vector3.ZERO,null)
		check(get_child_count()>count_before,key+" missing original impact")
		var impact:=get_child(get_child_count()-1) as OriginalWeaponEffect
		check(impact!=null,key+" spawned generic explosion")
		if impact!=null:
			check(impact.source_prefab==OriginalWeaponEffect.catalog()[key][1],key+" wrong impact prefab")
			impact.free()
		await get_tree().process_frame
		print("ORIGINAL_WEAPON_RUNTIME ",key)
	AudioDirector.stop_all_sfx()
	# Exercise actual player firing, including multi-shot variants and the blade.
	var player := WarfarePlayer.new()
	add_child(player)
	player.set_physics_process(false)
	for key in ["gun22","gun23","gun29","gun33","gun42","gun45"]:
		player.equip_weapon(key,false)
		await get_tree().process_frame
		if key=="gun33": player._fire_melee()
		else: player._fire_projectile(str(player.current_weapon.kind))
		var shots := get_children().filter(func(n): return n is WarfareProjectile)
		var count := 3 if key=="gun29" else (5 if key=="gun42" else 1)
		check(shots.size()==count,key+" wrong projectile count from player")
		for shot: WarfareProjectile in shots:
			check(shot.global_position.is_equal_approx(player.muzzle.global_position),key+" projectile did not start at muzzle")
			shot.queue_free()
		await get_tree().process_frame
	player.queue_free()
	await get_tree().process_frame
	for special: String in ["Effect/TrackingGrenadeShot","Effect/TrackingRobot","Effect/SatanMachine/joke_force"]:
		var effect := OriginalWeaponEffect.create(special)
		add_child(effect)
		await get_tree().process_frame
		check(not effect.get_children().is_empty(),special+" missing original nodes")
		if special=="Effect/TrackingRobot": check(not effect.skeleton_links.is_empty(),"J.O.K.E robot lost animated skin")
		effect.free()
	AudioDirector.stop_all_sfx()
	print("ORIGINAL_WEAPON_TEST_PASS weapons=17" if failures.is_empty() else failures)
	get_tree().quit(0 if failures.is_empty() else 1)
