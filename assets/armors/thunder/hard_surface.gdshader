shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.11, 0.29, 0.40, 1.0);
uniform float metalness : hint_range(0.0, 1.0) = 0.42;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.38;
uniform float readability_fill : hint_range(0.0, 1.0) = 0.20;
uniform float glow_strength : hint_range(0.0, 4.0) = 0.0;
uniform float visor_finish : hint_range(0.0, 1.0) = 0.0;
uniform vec4 visor_face_color : source_color = vec4(1.0, 0.80, 0.32, 1.0);

void fragment() {
	// No painted fake bevels: the mesh carries the plate thickness and facets.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	vec3 surface_color = mix(paint_color.rgb, visor_face_color.rgb,
		visor_finish * smoothstep(0.25, 0.95, facing) * 0.45);
	ALBEDO = surface_color;
	METALLIC = metalness;
	ROUGHNESS = surface_roughness;
	SPECULAR = mix(0.22, 0.45, visor_finish);
	// A small fill keeps the blue shell legible in the game's dim arenas.
	// Only visor material uses an actual glow contribution.
	EMISSION = surface_color * (readability_fill + glow_strength);
}
