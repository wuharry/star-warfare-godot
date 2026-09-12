extends Node3D
var failures: Array[String] = []
func _ready() -> void:
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0.08,0.09,0.12)
	add_child(env)
	var camera:=Camera3D.new()
	camera.position=Vector3(3,2,4)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	DirAccess.make_dir_recursive_absolute("res://test_output/weapon_restoration/captures")
	for key: String in OriginalWeaponEffect.catalog():
		var record: Array=OriginalWeaponEffect.catalog()[key]
		for slot in [0,1]:
			var effect:=OriginalWeaponEffect.create(record[slot])
			if effect==null:
				failures.append(key+" missing prefab");continue
			add_child(effect)
			camera.size=4 if slot==0 else 12
			if key=="gun45" and slot==1:
				camera.size=20
				camera.position=Vector3(10,7,12)
				camera.look_at(Vector3(0,4,0))
			else:
				camera.position=Vector3(3,2,4)
				camera.look_at(Vector3.ZERO)
			for i in 15: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://test_output/weapon_restoration/captures/%s_%d.png"%[key,slot])
			effect.free()
		print("ORIGINAL_WEAPON_CAPTURE ",key)
	print("ORIGINAL_WEAPON_CAPTURE_PASS" if failures.is_empty() else failures)
	get_tree().quit(0 if failures.is_empty() else 1)
