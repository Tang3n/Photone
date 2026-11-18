#version 440
// A pixel of the photo, counted (tally.vert): added to its bin. (No alpha: with none, what is
// drawn is added to what is there.)
layout(location = 0) in vec2 which;
layout(location = 1) in float weight;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {  // must match tally.vert exactly
    mat4 qt_Matrix;
    float qt_Opacity;
    float count;
    float what;
    float masked;
    float fine;
    vec2 shift;
    vec4 into;
};
layout(binding = 1) uniform sampler2D values;
layout(binding = 2) uniform sampler2D inside;

void main() {
    vec2 between = abs(which - floor(which + 0.5));
    if (max(between.x, between.y) > 0.001) discard;  // not a pixel: what ties two together
    fragColor = vec4(into.rgb * weight, 0.0);
}
