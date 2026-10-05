shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D chitin_texture : source_color, filter_linear_mipmap, repeat_enable;
// Painted occlusion and edge accents come from the anatomical atlas itself.
// Keep that RGB information intact in the recovered baked-light arenas.
uniform float painted_fill : hint_range(0.0, 2.0) = 0.65;
uniform float palette_weight : hint_range(0.0, 1.0) = 0.06;
varying vec3 plate_tint;

vec3 linear_to_srgb(vec3 value) {
	return mix(1.055 * pow(max(value, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
		value * 12.92, lessThanEqual(value, vec3(0.0031308)));
}

vec3 srgb_to_linear(vec3 value) {
	return mix(pow((value + 0.055) / 1.055, vec3(2.4)),
		value / 12.92, lessThanEqual(value, vec3(0.04045)));
}

void vertex() {
	plate_tint = COLOR.rgb;
}

void fragment() {
	vec3 grain = texture(chitin_texture, UV).rgb;
	// glTF COLOR_0 is linear. Compatibility shades in sRGB, unlike Forward+.
	// Blend in linear space, then convert the final painted colour.
	if (OUTPUT_IS_SRGB) {
		grain = srgb_to_linear(grain);
	}
	vec3 painted_chitin = mix(grain, plate_tint, palette_weight);
	if (OUTPUT_IS_SRGB) {
		painted_chitin = linear_to_srgb(painted_chitin);
	}
	ALBEDO = painted_chitin * 0.40;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = painted_chitin * painted_fill;
}
