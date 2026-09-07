shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D effect_texture : source_color;
uniform vec4 effect_tint : source_color = vec4(1.0);

void fragment() {
	vec4 effect = texture(effect_texture, UV) * effect_tint;
	float coverage = max(effect.r, max(effect.g, effect.b));
	// Legacy additive textures use black as empty space, including opaque PNGs.
	// Give those pixels zero coverage when compositing the transparent preview.
	ALPHA = clamp(coverage * effect.a, 0.0, 1.0);
	ALBEDO = effect.rgb / max(coverage, 0.00001);
}
