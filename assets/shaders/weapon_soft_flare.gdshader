shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 energy_color : source_color = vec4(0.08, 0.65, 1.0, 1.0);
uniform float opacity = 1.0;
uniform bool particle_billboard = false;
uniform bool ring = false;

void vertex() {
	if (particle_billboard) {
		vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s.x, INV_VIEW_MATRIX[1] * s.y, INV_VIEW_MATRIX[2] * s.z, MODEL_MATRIX[3]);
	}
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float glow = exp(-r * r * 5.0) * (1.0 - smoothstep(0.75, 1.0, r));
	float hot = exp(-r * r * 95.0);
	if (ring) {
		glow = exp(-pow((r - 0.67) * 18.0, 2.0));
		hot = 0.0;
	}
	ALBEDO = energy_color.rgb + vec3(hot * 0.8);
	ALPHA = (glow * 0.55 + hot * 0.45) * opacity * COLOR.a;
}
