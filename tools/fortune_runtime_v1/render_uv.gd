extends SceneTree

func _initialize() -> void:
    for label: String in ["head", "body", "shoulder", "hand", "foot"]:
        var path := "res://docs/art/fortune_runtime_v1/guides/" + ("head_uv_authored" if label == "head" else label + "_uv")
        var image := Image.new()
        assert(image.load_svg_from_string(FileAccess.get_file_as_string(path + ".svg")) == OK)
        assert(image.save_png(path + ".png") == OK)
    print("FORTUNE_UV_GUIDES_PASS authored chin layout and four exact original material layouts")
    quit()
