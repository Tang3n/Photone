#version 440
// One tile of the HDR test picture: white at `level` times SDR white, with a smaller square of
// exactly SDR white (1.0) in its middle. The inner square can only be seen if the tile around
// it really is brighter (or darker) than SDR white.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float level;  // the tile's light, in multiples of SDR white
    float inset;  // 1: an inner square at 1.0; 2: fine black/white stripes (half the light of white)
    float hdr;    // 1: light above SDR white goes to the screen; 0: clipped at SDR white
    float linear; // 1: the surface takes linear light; 0: sRGB-encoded values (see hdr_test.py)
};
void main() {
    vec2 d = abs(qt_TexCoord0 - 0.5);
    float v = level;
    if (inset > 1.5) v = mod(floor(gl_FragCoord.y), 2.0);
    else if (inset > 0.5 && max(d.x, d.y) < 0.2) v = 1.0;
    if (hdr < 0.5) v = min(v, 1.0);
    if (linear < 0.5) v = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055;
    fragColor = vec4(vec3(v), 1.0) * qt_Opacity;
}
