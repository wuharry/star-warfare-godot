shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D source_albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear, repeat_disable;
uniform sampler2D emission_texture : source_color, filter_linear, repeat_disable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;

void fragment() {
	vec4 paint = texture(albedo_texture, UV);
	vec3 original = texture(source_albedo_texture, UV).rgb;
	// Keep unused/padded atlas texels opaque. Alpha is an artwork mask, never
	// a cutout of the underlying watertight mesh or the dark original rear.
	float blue = smoothstep(0.03, 0.13, original.b - original.r);
	vec3 fallback = mix(original * 0.75, original * vec3(1.0, 0.64, 0.70), blue);
	vec3 surface = mix(fallback, paint.rgb, smoothstep(0.1, 0.9, paint.a));
	vec3 emitted = texture(emission_texture, UV).rgb;
	float amber = smoothstep(0.06, 0.28, original.r - original.b);
	ALBEDO = surface * 0.72;
	EMISSION = surface * (0.28 + amber * 0.13) + emitted * 0.025;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(0.72, 0.48, amber);
	METALLIC = 0.06;
	SPECULAR = 0.18;
}
