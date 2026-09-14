shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float amber_visor : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 paint = texture(albedo_texture, UV).rgb;
	// Color-select the warm aperture while preserving its authored border.
	float amber = amber_visor * smoothstep(0.05, 0.20, paint.r - paint.b)
		* smoothstep(0.04, 0.14, paint.g) * (1.0 - smoothstep(0.35, 0.65, paint.b));
	paint = mix(paint, min(paint * vec3(1.22, 1.52, 1.1), vec3(1.0)), amber * 0.8);
	// Original atlases contain their own painted lighting. Preserve that read
	// while the new raised shells supply real highlights and silhouette.
	ALBEDO = paint * 0.30;
	EMISSION = paint * 0.70;
	ROUGHNESS = 0.72;
	METALLIC = 0.05;
	SPECULAR = 0.16;
}
