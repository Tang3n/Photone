#version 440
// A graph of counts (Bars.qml), filled from its foot up to the counts, with a soft edge.
layout(location = 0) in vec2 uv;
layout(location = 1) flat in float tallest;
layout(location = 0) out vec4 fragColor;
#include "bars.glsl"

void main() {
    float p = centered > 0.5 ? uv.x * 256.0 - 0.5 : uv.x * 255.0;
    vec4 v = ends > 0.5 && p < 1.0 ? texelFetch(counts, ivec2(0, 0), 0)
           : ends > 0.5 && p > 254.0 ? texelFetch(counts, ivec2(255, 0), 0)
           : wrap > 0.5 || (p >= first - 0.5 && p <= last + 0.5) ? smoothed(p) : vec4(0.0);
    vec3 over = min(v.rgb / max(tallest, 1e-6), 1.0) - (1.0 - uv.y);  // how far under the graph's edge
    if (three < 0.5) over = vec3(min(dot(v, pick) / max(tallest, 1e-6), 1.0) - (1.0 - uv.y));
    vec3 cover = tallest > 0.0 ? clamp(0.5 + over / max(fwidth(over), 1e-5), 0.0, 1.0) : vec3(0.0);
    // (Red, green and blue add up: where all three lie it reads gray.)
    vec4 c = three > 0.5 ? min(red * cover.r + green * cover.g + blue * cover.b, 1.0) : color * cover.r;
    fragColor = vec4(linearOut > 0.5 ? pow(c.rgb, vec3(2.2)) : c.rgb, c.a) * qt_Opacity;
}
