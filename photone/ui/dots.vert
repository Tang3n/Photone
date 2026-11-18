#version 440
// The wheel's dots: one for every pixel of a small render of the photo that carries each
// pixel's color as numbers (pipeline.frag, scope 8 and 9). The mesh is a grid of twice as many
// points across and down as there are dots: every other square of it is a dot, moved here to
// where its color lies on the wheel; the squares in between tie neighbors together and are
// not drawn (dots.frag). Nothing is read back and nothing is counted: the dots are the
// photo's colors of this very frame.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 corner;  // within the dot: -1..1 both ways
layout(location = 1) out vec2 which;   // which dot: whole numbers inside one, not in between
layout(location = 2) out vec3 color;
layout(std140, binding = 0) uniform buf {  // must match dots.frag exactly
    mat4 qt_Matrix;
    float qt_Opacity;
    float linearOut;  // as in pipeline.frag
    float count;      // dots a side
    float span;       // how much chroma the item is across (wheel.frag)
    float radius;     // of a dot, in pixels
    float low;        // the working range: only colors this light
    float high;
    float ink;        // 1: the dot is drawn dark and see-through: the ground the colored ones lie on
    vec2 middle;      // the a, b in the middle of the item
    vec2 across;      // the item's size in pixels
};
layout(binding = 1) uniform sampler2D colors;
#include "oklab.glsl"

void main() {
    vec2 point = floor(qt_MultiTexCoord0 * (2.0 * count - 1.0) + 0.5);
    which = floor(point * 0.5);
    corner = (point - 2.0 * which) * 2.0 - 1.0;
    vec4 texel = textureLod(colors, (which + 0.5) / count, 0.0);
    // (a and b as they are, below zero too: with a half added, as it was until 2026-11-17,
    // half floats kept them only to 0.0005, and seen closely the dots stood in a grid.)
    vec3 lab = texel.rgb;
    // Not of the photo (beyond its frame) or not of the working range: a dot of no size.
    bool shown = texel.a > 0.5 && lab.x >= low && lab.x <= high;
    vec2 place = across * 0.5 + (lab.yz - middle) * vec2(1.0, -1.0) / span * across.y;
    vec3 c = clamp(TO_SRGB * fromRoots(LAB_TO_ROOTS * lab), 0.0, 1.0);
    color = linearOut > 0.5 ? c : encode(c);
    gl_Position = qt_Matrix * vec4(place + corner * (shown ? radius : 0.0), 0.0, 1.0);
}
