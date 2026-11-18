#version 440
// The color wheel's disc: OKLab's a across (red to the right), b upward (yellow at the top), at
// one lightness, so hue is the angle and chroma the distance from the gray middle. Colors a
// display cannot show are cut to what it can.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float linearOut;  // as in pipeline.frag
    float lightness;  // of every color on the disc
    float span;       // how much chroma the item is across
    float rim;        // the chroma at which the disc ends
    vec2 middle;      // the a, b in the middle of the item
    float aspect;     // the item's width over its height: `span` is the chroma across its height
};
#include "oklab.glsl"

void main() {
    vec2 ab = middle + (qt_TexCoord0 - 0.5) * span * vec2(aspect, -1.0);
    float chroma = length(ab);
    vec3 c = clamp(TO_SRGB * fromRoots(LAB_TO_ROOTS * vec3(lightness, ab)), 0.0, 1.0);
    float inside = 1.0 - smoothstep(rim - fwidth(chroma), rim, chroma);
    fragColor = vec4(linearOut > 0.5 ? c : encode(c), 1.0) * inside * qt_Opacity;
}
