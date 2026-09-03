extends SceneTree

## Finishes an AI-restored UV atlas without letting the generated image change
## the model's transparency mask. The original atlas remains the authority for
## alpha and contributes enough colour to keep each legacy armor set recognisable.


func _initialize() -> void:
	var source_path := _argument("source")
	var generated_path := _argument("generated")
	var output_path := _argument("output")
	var output_size := int(_argument("size", "1024"))
	var generated_weight := float(_argument("blend", "0.72"))

	if source_path.is_empty() or output_path.is_empty():
		_fail("Usage: --source=<png> [--generated=<png>] --output=<png> [--size=1024] [--blend=0.72]")
		return
	if output_size <= 0:
		_fail("Output size must be positive")
		return
	if not FileAccess.file_exists(source_path):
		_fail("Source texture does not exist: " + source_path)
		return
	if not generated_path.is_empty() and not FileAccess.file_exists(generated_path):
		_fail("Generated texture does not exist: " + generated_path)
		return

	var source := Image.load_from_file(source_path)
	if source.is_empty():
		_fail("Could not decode source texture: " + source_path)
		return
	source.convert(Image.FORMAT_RGBA8)
	source.resize(output_size, output_size, Image.INTERPOLATE_LANCZOS)

	var result := source.duplicate()
	if not generated_path.is_empty() and generated_weight > 0.0:
		var generated := Image.load_from_file(generated_path)
		if generated.is_empty():
			_fail("Could not decode generated texture: " + generated_path)
			return
		generated.convert(Image.FORMAT_RGBA8)
		generated.resize(output_size, output_size, Image.INTERPOLATE_LANCZOS)
		result = _blend_preserving_source_alpha(source, generated, clampf(generated_weight, 0.0, 1.0))

	var output_directory := output_path.get_base_dir()
	if not output_directory.is_empty():
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			_fail("Could not create output directory: %s (%s)" % [output_directory, error_string(directory_error)])
			return
	var save_error: Error = result.save_png(output_path)
	if save_error != OK:
		_fail("Could not save output texture: %s (%s)" % [output_path, error_string(save_error)])
		return

	print("CALLOFMINI_TEXTURE_READY source=%s generated=%s output=%s size=%dx%d blend=%.2f" % [
		source_path,
		generated_path if not generated_path.is_empty() else "none",
		output_path,
		output_size,
		output_size,
		generated_weight if not generated_path.is_empty() else 0.0,
	])
	quit(0)


func _blend_preserving_source_alpha(source: Image, generated: Image, generated_weight: float) -> Image:
	var source_bytes := source.get_data()
	var generated_bytes := generated.get_data()
	var output_bytes := source_bytes.duplicate()
	var source_weight := 1.0 - generated_weight

	for byte_index in range(0, output_bytes.size(), 4):
		# Blend colour only. The original alpha channel is deliberately untouched,
		# keeping UV-island edges and transparent padding deterministic.
		output_bytes[byte_index] = roundi(
			float(source_bytes[byte_index]) * source_weight
			+ float(generated_bytes[byte_index]) * generated_weight
		)
		output_bytes[byte_index + 1] = roundi(
			float(source_bytes[byte_index + 1]) * source_weight
			+ float(generated_bytes[byte_index + 1]) * generated_weight
		)
		output_bytes[byte_index + 2] = roundi(
			float(source_bytes[byte_index + 2]) * source_weight
			+ float(generated_bytes[byte_index + 2]) * generated_weight
		)

	return Image.create_from_data(
		source.get_width(),
		source.get_height(),
		false,
		Image.FORMAT_RGBA8,
		output_bytes
	)


func _argument(key: String, fallback := "") -> String:
	var prefix := "--%s=" % key
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _fail(message: String) -> void:
	push_error("CALLOFMINI ENHANCER: " + message)
	quit(1)
