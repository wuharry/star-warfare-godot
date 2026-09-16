shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D source_albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear, repeat_disable;
uniform sampler2D emission_texture : source_color, filter_linear, repeat_disable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float shell_palette_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shell_blue : source_color = vec4(0.208, 0.373, 0.533, 1.0);
uniform vec4 shell_navy : source_color = vec4(0.125, 0.216, 0.314, 1.0);

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
	// Use the body's blue/navy paints only on blue shell texels. Retain the
	// atlas's panel shading, scratches and normal detail; gold is untouched.
	vec3 perceptual = OUTPUT_IS_SRGB ? surface : pow(max(surface, vec3(0.0)), vec3(1.0 / 2.2));
	float tone = dot(perceptual, vec3(0.2126, 0.7152, 0.0722));
	float panel = smoothstep(0.12, 0.40, tone);
	vec3 palette = mix(shell_navy.rgb, shell_blue.rgb, panel);
	float detail = clamp(tone / 0.30, 0.40, 1.40);
	palette *= OUTPUT_IS_SRGB ? detail : pow(detail, 2.2);
	surface = mix(surface, palette, blue * (1.0 - amber) * shell_palette_strength);
	ALBEDO = surface * 0.72;
	EMISSION = surface * (0.28 + amber * 0.13) + emitted * 0.025;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(0.72, 0.48, amber);
	METALLIC = 0.06;
	SPECULAR = 0.18;
}
