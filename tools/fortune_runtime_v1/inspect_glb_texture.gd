extends SceneTree

func _initialize() -> void:
    var scene := (load("res://assets/armors/fortune_v1/fortune.glb") as PackedScene).instantiate()
    var head := scene.find_child("ArmorHead_01", true, false) as MeshInstance3D
    var material := head.get_active_material(0) as BaseMaterial3D
    var actual := material.albedo_texture.get_image()
    var expected := Image.load_from_file(ProjectSettings.globalize_path("res://assets/armors/fortune_v1/head_diffuse.png"))
    if actual.is_compressed():assert(actual.decompress() == OK)
    var maximum := 0.0
    var points: Array[Vector2] = []
    for u: float in [.555, .58, .62]:
        for v: float in [.735, .79, .87, .93, .967]:points.append(Vector2(u,v))
    for u: float in [.69, .80, .93]:
        for v: float in [.75, .84]:points.append(Vector2(u,v))
    for u: float in [.09, .20, .32, .40]:
        for v: float in [.865, .90, .94]:points.append(Vector2(u,v))
    points.append(Vector2(.6225,.0816))
    for uv: Vector2 in points:
        var pixel := Vector2i(roundi(uv.x*(expected.get_width()-1)),roundi(uv.y*(expected.get_height()-1)))
        var a := actual.get_pixelv(pixel)
        var b := expected.get_pixelv(pixel)
        var error := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
        if error > maximum:print("max sample ",uv," pixel ",pixel," error ",error)
        maximum=maxf(maximum,error)
    print("FORTUNE_GLB_TEXTURE_DIAGNOSTIC ", actual.get_size(), " logical=",material.albedo_texture.get_size()," canonical=",expected.get_size()," max_rgb_error=",maximum)
    scene.free()
    quit()
