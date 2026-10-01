shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_vertex_color = true;

void fragment() {
	// Original armor atlases contain painted light, seams and cloth volume.
	// Match the existing refined armor's response, including shaded layer walls.
	vec3 paint = texture(albedo_texture, UV).rgb * albedo_tint.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	ALBEDO = paint * 0.25;
	EMISSION = paint * 0.75;
	ROUGHNESS = 0.78;
	METALLIC = 0.0;
	SPECULAR = 0.08;
}
