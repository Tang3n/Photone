#version 440
// As pipeline.vert: our own vertex stage so that both stages share their GLSL versions.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(std140, binding = 0) uniform buf {  // must match brushed.frag exactly
    mat4 qt_Matrix;
    float qt_Opacity;
    float channel;
    float erase;
    float based;
};
void main() {
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
