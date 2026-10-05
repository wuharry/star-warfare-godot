shader_type spatial;
render_mode cull_back;

float grain(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Vertex RGB stores the original art palette in linear color. Vertex alpha is
// a material role, never transparency; the visor is an opaque reflective shell.
void fragment() {
    float role = COLOR.a;
    bool cloth = role < 0.2;
    bool glass = role > 0.65 && role < 0.8;
    bool lamp = role > 0.85;
    // Fixed, subtle painted grain; UV addressing avoids motion-dependent noise.
    float wear = grain(floor(UV * 256.0));
    float finish = 0.975 + wear * 0.025;
    // Harmonize lighting ratio and suppress specular glare.
    ALBEDO = COLOR.rgb * 0.25 * finish;
    ROUGHNESS = cloth ? 0.95 : (glass ? 0.45 : 0.85);
    METALLIC = cloth ? 0.0 : (glass ? 0.04 : 0.0);
    SPECULAR = glass ? 0.18 : 0.06;
    EMISSION = COLOR.rgb * (lamp ? 0.85 : (cloth ? 0.72 : 0.75));
}
