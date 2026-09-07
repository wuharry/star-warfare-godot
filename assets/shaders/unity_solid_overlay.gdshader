shader_type spatial;
render_mode unshaded, specular_disabled;

// Original iPhone/SolidAndAlphaTexture: _tex2 * tint + _texBase.
// Bright doubles the first stage and binds the second stage to Unity UV1.
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D overlay_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 overlay_color : source_color = vec4(1.0);
uniform float overlay_multiplier = 1.0;
uniform bool base_uses_uv2 = false;

vec3 to_srgb(vec3 value) {
	return mix(1.055 * pow(max(value, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, value * 12.92, lessThanEqual(value, vec3(0.0031308)));
}

vec3 to_linear(vec3 value) {
	return mix(pow((max(value, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), value / 12.92, lessThanEqual(value, vec3(0.04045)));
}

void fragment() {
	vec3 base = texture(base_texture, base_uses_uv2 ? UV2 : UV).rgb;
	vec3 overlay = texture(overlay_texture, UV).rgb;
	ALBEDO = OUTPUT_IS_SRGB
		? base + overlay * overlay_color.rgb * overlay_multiplier
		: to_linear(to_srgb(base) + to_srgb(overlay) * to_srgb(overlay_color.rgb) * overlay_multiplier);
}
