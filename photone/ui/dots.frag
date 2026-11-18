#version 440
// A dot of the wheel (dots.vert): a disc of its color. The dots lie thick, so they are drawn
// twice: first all of them a little larger and dark (`ink`), then all of them in color; what
// shows of the dark ones is an outline round the cloud and round each dot that stands alone.
// (The owner likes it so, 2026-11-17. On the test chart, whose colors lie in rows, the dark
// shows between the rows as rings: that is the chart. A rim on each dot in one layer was
// tried: where dots lie thick, the sliver that shows of each is its rim, and the cloud is black.)
layout(location = 0) in vec2 corner;
layout(location = 1) in vec2 which;
layout(location = 2) in vec3 color;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {  // must match dots.vert exactly
    mat4 qt_Matrix;
    float qt_Opacity;
    float linearOut;
    float count;
    float span;
    float radius;
    float low;
    float high;
    float ink;
    vec2 middle;
    vec2 across;
};
layout(binding = 1) uniform sampler2D colors;

void main() {
    vec2 between = abs(which - floor(which + 0.5));
    float far = length(corner);
    if (max(between.x, between.y) > 0.001 || far > 1.0) discard;  // not a dot, or beyond its edge
    float cover = (1.0 - smoothstep(1.0 - 1.5 / radius, 1.0, far)) * qt_Opacity;
    fragColor = ink > 0.5 ? vec4(0.0, 0.0, 0.0, 0.7) * cover : vec4(color, 1.0) * cover;
}
