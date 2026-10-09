shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform float amber_visor : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 paint = texture(albedo_texture, UV).rgb;
	// Color-select the warm aperture while preserving its authored border.
	float amber = amber_visor * smoothstep(0.05, 0.20, paint.r - paint.b)
		* smoothstep(0.04, 0.14, paint.g) * (1.0 - smoothstep(0.35, 0.65, paint.b));
	paint = mix(paint, min(paint * vec3(1.22, 1.52, 1.1), vec3(1.0)), amber * 0.8);
	// Harmonize lighting ratio and suppress specular noise to match the legacy hand-painted aesthetic.
	ALBEDO = paint * 0.25;
	EMISSION = paint * 0.75;
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
	SPECULAR = 0.06;
}
