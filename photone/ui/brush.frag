#version 440
// The brush, painting: one step of a stroke (PhotoView.qml, `brush`), drawn onto what the
// steps before left (`was`: this shader's own last picture). Up to sixteen stretches of the
// way, each a straight band with round ends, put together as edit.Painter does: the larger
// along a piece, and a piece that is over laid onto what is under it as paint onto paint.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float begin;      // a stroke begins: 1 on what `base` holds, 2 on what was painted here; 0: one goes on
    float channel;    // which color of `base` the mask is
    float count;      // how many stretches
    float radius;     // the brush's, in pixels of the raster
    float core;       // the share of it that is whole
    float erase;
    float erased;     // and of the stroke before this one (`begin` 2 puts that one together)
    vec2 size;        // the raster's, in pixels
    mat4 s0;          // the stretches, one a column: from (x, y) to (z, w), in pixels
    mat4 s1;
    mat4 s2;
    mat4 s3;
    mat4 turns;       // for each, whether a piece ends with it
};
layout(binding = 1) uniform sampler2D was;
layout(binding = 2) uniform sampler2D base;
#include "brush.glsl"

void main() {
    vec3 state = texture(was, qt_TexCoord0).xyz;
    if (begin > 1.5) state = vec3(laid(state, erased), 0.0, 0.0);
    else if (begin > 0.5) {
        vec3 all = texture(base, qt_TexCoord0).rgb;
        state = vec3(channel < 0.5 ? all.r : channel < 1.5 ? all.g : all.b, 0.0, 0.0);
    }
    vec2 at = qt_TexCoord0 * size;   // (a pixel is its middle, as in edit._band)
    for (int i = 0; i < 16; i++) {
        if (float(i) >= count) break;
        vec4 s = i < 4 ? s0[i] : i < 8 ? s1[i - 4] : i < 12 ? s2[i - 8] : s3[i - 12];
        vec2 along = s.zw - s.xy, from = at - s.xy;
        float whole = dot(along, along);
        float t = whole > 0.0 ? clamp(dot(from, along) / whole, 0.0, 1.0) : 0.0;
        float far = clamp(length(from - t * along) / (radius * (1.0 - core)) - core / (1.0 - core), 0.0, 1.0);
        state.z = max(state.z, 1.0 - far * far * (3.0 - 2.0 * far));
        if (turns[i / 4][i % 4] > 0.5) state = vec3(laid(state, erase), state.z, 0.0);
    }
    fragColor = vec4(state, 1.0);
}
