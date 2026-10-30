shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform float width_pixels : hint_range(0.0, 5.0) = 1.8;
uniform vec4 ink_color : source_color = vec4(0.055, 0.028, 0.060, 1.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = MODELVIEW_NORMAL_MATRIX * NORMAL;
	vec2 direction = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	direction /= max(length(direction), 0.001);
	clip.xy += direction * width_pixels * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
