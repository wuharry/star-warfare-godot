shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.11, 0.29, 0.40, 1.0);
uniform float metalness : hint_range(0.0, 1.0) = 0.42;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.38;
uniform float readability_fill : hint_range(0.0, 1.0) = 0.20;
uniform float glow_strength : hint_range(0.0, 4.0) = 0.0;
uniform float visor_finish : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D shell_detail_texture : source_color, filter_linear, repeat_enable;
uniform sampler2D visor_paint_texture : source_color, filter_linear, repeat_disable;
uniform float paint_detail : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// The generated swatch supplies paint grain; actual shells carry the bevels.
	vec3 surface_color = paint_color.rgb;
	float grain_luma = dot(texture(shell_detail_texture, UV).rgb, vec3(0.2126, 0.7152, 0.0722));
	// Compatibility shades in sRGB; Forward+ shades in linear space. Normalize
	// in a common perceptual space so the tile never clamps to one flat value.
	grain_luma = OUTPUT_IS_SRGB ? grain_luma : pow(grain_luma, 1.0 / 2.2);
	float grain = clamp(grain_luma / 0.32, 0.70, 1.35);
	surface_color *= mix(1.0, grain, paint_detail * 0.60);
	// Explicit visor UVs carry its painted amber border and warm yellow center.
	surface_color = mix(surface_color, texture(visor_paint_texture, UV).rgb, visor_finish);
	ALBEDO = surface_color * (1.0 - readability_fill);
	METALLIC = metalness;
	ROUGHNESS = surface_roughness;
	SPECULAR = mix(0.18, 0.32, visor_finish);
	// A small fill keeps the blue shell legible in the game's dim arenas.
	// Only visor material uses an actual glow contribution.
	EMISSION = surface_color * (readability_fill + glow_strength);
}
