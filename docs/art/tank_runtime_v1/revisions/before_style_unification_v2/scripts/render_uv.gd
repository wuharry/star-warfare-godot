extends SceneTree

func _initialize() -> void:
    for label: String in ["head","body","shoulder","hand","foot"]:
        var path := "res://docs/art/tank_runtime_v1/guides/"+label+"_authored_uv"
        var image := Image.new()
        assert(image.load_svg_from_string(FileAccess.get_file_as_string(path+".svg")) == OK)
        assert(image.save_png(path+".png") == OK)
    print("TANK_UV_GUIDES_PASS authored layout / original generation guides preserved")
    quit()
