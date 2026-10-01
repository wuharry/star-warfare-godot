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
    ALBEDO = COLOR.rgb * finish;
    ROUGHNESS = cloth ? 0.92 : (glass ? 0.22 : 0.55);
    METALLIC = cloth ? 0.0 : (glass ? 0.45 : 0.12);
    SPECULAR = glass ? 0.65 : 0.32;
    // Small neutral fill keeps paint readable under the game's indoor lights.
    EMISSION = COLOR.rgb * (lamp ? 0.8 : (cloth ? 0.03 : 0.08));
}
