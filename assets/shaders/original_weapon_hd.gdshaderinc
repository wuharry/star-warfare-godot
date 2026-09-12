// Four bilinear samples reconstruct a cubic B-spline footprint for magnified
// original atlases. No UV islands or animation-frame layout are changed.
vec4 original_hd_sample(sampler2D image, vec2 uv) {
    vec2 image_size = vec2(textureSize(image, 0));
    vec2 pixel = uv * image_size - 0.5;
    vec2 cell = floor(pixel);
    vec2 f = fract(pixel);
    vec2 one_minus = 1.0 - f;
    vec2 w0 = one_minus * one_minus * one_minus / 6.0;
    vec2 w1 = (3.0*f*f*f - 6.0*f*f + 4.0) / 6.0;
    vec2 w2 = (-3.0*f*f*f + 3.0*f*f + 3.0*f + 1.0) / 6.0;
    vec2 w3 = f*f*f / 6.0;
    vec2 left = w0 + w1;
    vec2 right = w2 + w3;
    vec2 a = (cell - 0.5 + w1 / left) / image_size;
    vec2 b = (cell + 1.5 + w3 / right) / image_size;
    return mix(mix(texture(image, a), texture(image, vec2(b.x,a.y)), right.x),
               mix(texture(image, vec2(a.x,b.y)), texture(image, b), right.x), right.y);
}
