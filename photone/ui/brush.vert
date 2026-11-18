#version 440
// As pipeline.vert: our own vertex stage so that both stages share their GLSL versions.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(std140, binding = 0) uniform buf {  // must match brush.frag exactly
    mat4 qt_Matrix;
    float qt_Opacity;
    float begin;
    float channel;
    float count;
    float radius;
    float core;
    float erase;
    float erased;
    vec2 size;
    mat4 s0;
    mat4 s1;
    mat4 s2;
    mat4 s3;
    mat4 turns;
};
void main() {
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
