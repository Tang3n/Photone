#version 440
// The photo's painted masks with the stroke being made in its mask's place (PhotoView.qml,
// `painted`): what pipeline.frag reads until the stroke is over and its picture has come.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float channel;
    float erase;
    float based;      // whether `base` holds masks at all (where there are none yet it is some other picture)
};
layout(binding = 1) uniform sampler2D state;
layout(binding = 2) uniform sampler2D base;
#include "brush.glsl"

void main() {
    vec3 all = based > 0.5 ? texture(base, qt_TexCoord0).rgb : vec3(0.0);
    float now = laid(texture(state, qt_TexCoord0).xyz, erase);
    fragColor = vec4(channel < 0.5 ? now : all.r, channel > 0.5 && channel < 1.5 ? now : all.g, channel > 1.5 ? now : all.b, 1.0);
}
