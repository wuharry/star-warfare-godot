shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform float readable_fill : hint_range(0.0, 0.3) = 0.20;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.64;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec3 paint = albedo_tint.rgb * COLOR.rgb;
	if (use_texture) {
		paint *= texture(albedo_texture, UV).rgb;
	}
	// Real bevel normals now provide most of the armor's light response.
	ALBEDO = paint * (1.0 - readable_fill);
	EMISSION = paint * readable_fill;
	float brightness = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	ROUGHNESS = clamp(surface_roughness + (1.0 - brightness) * 0.12, 0.45, 0.86);
	METALLIC = 0.08;
	SPECULAR = surface_specular;
}
