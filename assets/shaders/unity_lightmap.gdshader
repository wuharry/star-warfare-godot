shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

// Unity iPhone/LightMap: base * lightmap; Optimized/LightMap: twice that.
// UV2 comes from the authored UV1, not a new Godot unwrap.
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec2 lightmap_scale = vec2(1.0);
uniform vec2 lightmap_offset = vec2(0.0);
uniform float lightmap_multiplier = 1.0;
uniform float dynamic_light_strength = 0.0;

vec3 to_srgb(vec3 value) {
	return mix(1.055 * pow(max(value, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, value * 12.92, lessThanEqual(value, vec3(0.0031308)));
}

vec3 to_linear(vec3 value) {
	return mix(pow((max(value, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), value / 12.92, lessThanEqual(value, vec3(0.04045)));
}

void fragment() {
	vec4 texel = texture(base_texture, UV);
	vec4 base = texel * base_color;
	// glTF and Godot use top-down texture coordinates; Unity uses bottom-up.
	vec2 atlas_uv = vec2(UV2.x, 1.0 - UV2.y) * lightmap_scale + lightmap_offset;
	vec4 baked = texture(lightmap_texture, vec2(atlas_uv.x, 1.0 - atlas_uv.y));
	ALBEDO = base.rgb;
	// The Unity project has m_ActiveColorSpace = 0 (Gamma). Compatibility
	// already calculates in sRGB; linear renderers must perform this source
	// multiplication in sRGB first, especially the Optimized shader's x2.
	EMISSION = OUTPUT_IS_SRGB
		? base.rgb * baked.rgb * lightmap_multiplier
		: to_linear(to_srgb(texel.rgb) * to_srgb(base_color.rgb) * to_srgb(baked.rgb) * lightmap_multiplier);
	ROUGHNESS = 1.0;
#ifdef USE_ALPHA
	ALPHA = base.a * baked.a;
#endif
}

void light() {
	// Baked illumination remains the floor. Quality adds a restrained light
	// response for moving shadows and weapon flashes without re-lighting it.
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) * dynamic_light_strength;
}
