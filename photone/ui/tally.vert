#version 440
// What the graphs show is counted here, on the GPU (Counts.qml): one small square for every
// pixel of a small render of the photo, moved to the bin its value falls in, in a row of 256
// bins one pixel high, and the squares add up there (tally.frag). The mesh is dots.vert's:
// every other square of a grid is a pixel's, those in between tie neighbors and are not drawn.
// (A mesh holds 65536 points at most, which is 128 pixels a side.)
// Nothing is read back: the row is a texture the graphs are drawn from (bars.frag).
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 which;    // which pixel: whole numbers inside one, not in between
layout(location = 1) out float weight;  // what it counts for
layout(std140, binding = 0) uniform buf {  // must match tally.frag exactly
    mat4 qt_Matrix;
    float qt_Opacity;
    float count;   // pixels a side
    float what;    // 0, 1, 2: red, green, blue of `values`, as bytes; 3: OKLab chroma (to 0.4);
                   // 4: OKLab hue, each pixel counting for as much as it has color; 5: OKLab lightness
    float masked;  // 1: only pixels a mask reaches count (`inside`, its alpha)
    float fine;    // 2: the render has twice as many pixels a side, and this counts every other one,
    vec2 shift;    // from this one on (0 or 1 across and down): four of these count them all
    vec4 into;     // the channel of the row it is added to
};
layout(binding = 1) uniform sampler2D values;
layout(binding = 2) uniform sampler2D inside;

void main() {
    vec2 point = floor(qt_MultiTexCoord0 * (2.0 * count - 1.0) + 0.5);
    which = floor(point * 0.5);
    vec2 corner = point - 2.0 * which;
    vec2 at = (which * fine + shift + 0.5) / (count * fine);
    vec4 v = textureLod(values, at, 0.0);
    weight = masked > 0.5 ? step(0.5, textureLod(inside, at, 0.0).a) : 1.0;
    float bin;
    if (what < 2.5) bin = floor((what < 0.5 ? v.r : what < 1.5 ? v.g : v.b) * 255.0 + 0.5);
    else if (what < 3.5) bin = floor(length(v.yz) / 0.4 * 256.0);
    else if (what < 4.5) { bin = floor(fract(atan(v.z, v.y) / 6.2831853) * 256.0); weight *= length(v.yz) * 16.0; }
    else bin = floor(v.x * 256.0);
    gl_Position = qt_Matrix * vec4(clamp(bin, 0.0, 255.0) + corner.x, corner.y, 0.0, 1.0);
}
