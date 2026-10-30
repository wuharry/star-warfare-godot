shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec3 paint = texture(albedo_texture, UV).rgb;
	ALBEDO = paint;
	EMISSION = paint * vec3(0.84, 0.80, 0.91);
	ROUGHNESS = 1.0;
}

void light() {
	float illumination = dot(NORMAL, LIGHT) * ATTENUATION;
	float band = smoothstep(0.06, 0.09, illumination) * 0.18 + smoothstep(0.60, 0.63, illumination) * 0.22;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * vec3(1.0, 0.94, 0.83) * band;
}
