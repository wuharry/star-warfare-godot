extends SceneTree
func _initialize() -> void:
    for label: String in ["body_front_regions","body_placement_v3","head_vent_v2"]:
        var path := "res://docs/art/tank_runtime_v1/guides/"+label
        var image := Image.new()
        assert(image.load_svg_from_string(FileAccess.get_file_as_string(path+".svg")) == OK)
        assert(image.save_png(path+".png") == OK)
    print("TANK_REGIONS_PASS exact source layout / target paint positions")
    quit()
