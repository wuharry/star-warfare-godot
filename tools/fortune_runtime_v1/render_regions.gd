extends SceneTree

func _initialize() -> void:
    var labels := ["body_front_regions", "head_front_regions", "head_chin_regions"]
    var revision := "v4c"
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--head-semantic="):
            revision = argument.trim_prefix("--head-semantic=")
            assert(revision.is_valid_filename())
    labels.append_array(["head_semantic_authored_" + revision, "head_semantic_front_" + revision])
    if "--visor-neck-v5" in OS.get_cmdline_user_args():
        labels.append("head_visor_neck_semantic_v5")
    if "--visor-neck-v6" in OS.get_cmdline_user_args():
        labels.append("head_visor_neck_semantic_v6")
    for label: String in labels:
        var path := "res://docs/art/fortune_runtime_v1/guides/" + label
        var image := Image.new()
        assert(image.load_svg_from_string(FileAccess.get_file_as_string(path + ".svg")) == OK)
        assert(image.save_png(path + ".png") == OK)
    print("FORTUNE_BODY_FRONT_REGIONS_PASS")
    quit()
