shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 energy_color : source_color = vec4(0.06, 0.65, 1.0, 1.0);
uniform float opacity = 1.0;
uniform float age = 0.0;
uniform float flow_scale = 8.0;
uniform float core_strength = 0.65;

void fragment() {
	float edge = abs(UV.y * 2.0 - 1.0);
	float halo = exp(-edge * edge * 5.5) * (1.0 - smoothstep(0.75, 1.0, edge));
	float core = exp(-edge * edge * 180.0);
	float flow = 0.72 + 0.28 * sin(UV.x * flow_scale * 6.283185 - age * 45.0);
	float filament = exp(-pow((UV.y - 0.5 - sin(UV.x * 35.0 - age * 28.0) * 0.06) * 32.0, 2.0));
	float ends = smoothstep(0.0, 0.04, UV.x) * smoothstep(0.0, 0.06, 1.0 - UV.x);
	ALBEDO = energy_color.rgb * (0.7 + flow * 0.4) + vec3(core * core_strength);
	ALPHA = (halo * 0.24 + core * core_strength + filament * 0.14) * opacity * COLOR.a * ends;
}
