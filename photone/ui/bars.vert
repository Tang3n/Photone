#version 440
// A graph of counts (Bars.qml). Here: the tallest of its bars, which the graph is as high as,
// found once for the whole item and not at every pixel.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 uv;
layout(location = 1) flat out float tallest;
#include "bars.glsl"

void main() {
    uv = qt_MultiTexCoord0;
    float most = 0.0;
    for (int i = int(first); i <= int(last); i++) {
        vec4 v = smoothed(float(i));
        most = max(most, three > 0.5 ? max(v.r, max(v.g, v.b)) : dot(v, pick));
    }
    tallest = most;
    gl_Position = qt_Matrix * qt_Vertex;
}
