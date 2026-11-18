#version 440
// A radial mask's outline on the photo (MaskFrame.qml): an ellipse as a dark line with a light
// one in it, and inside that, dashed, where the mask begins to fade. Worked out for each pixel
// from how far it is from the ellipse, so the line is as smooth at any size and turn. (It was
// 72 straight strokes, whose ends showed as small bright joints; the owner saw them.)
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float rx;       // half the ellipse along its axis, in pixels
    float ry;       // and across it
    float inner;    // the dashed one's size as a share of the outline's; 0 or less: none
    float turn;     // the axis' direction, radians
    vec2 span;      // this item, in pixels
    vec2 middle;    // the ellipse's middle in it
    vec4 ink;       // the light line's color
};

// How much of a pixel a line of that half width along the ellipse covers. The distance to an
// ellipse has no simple form: this is how far its equation is off, over how fast that grows,
// which is the distance for a line as thin as these.
float ring(vec2 p, vec2 r, float halfWidth) {
    vec2 q = p / r;
    float f = length(q);
    float grows = length(q / r) / max(f, 1e-6);
    return clamp(halfWidth + 0.5 - abs(f - 1.0) / max(grows, 1e-9), 0.0, 1.0);
}

void main() {
    vec2 p = qt_TexCoord0 * span - middle;
    p = vec2(cos(turn) * p.x + sin(turn) * p.y, cos(turn) * p.y - sin(turn) * p.x);
    vec2 r = max(vec2(rx, ry), vec2(0.5));
    float dark = 0.5 * ring(p, r, 1.75), light = ring(p, r, 0.75), dash = 0.0;
    if (inner > 0.0) {
        float around = atan(p.y / r.y, p.x / r.x) / 6.2831853;
        dash = 0.6 * ring(p, r * inner, 0.75) * step(0.5, fract(around * 36.0));
    }
    vec4 c = vec4(0.0, 0.0, 0.0, dark);
    c = c * (1.0 - light) + vec4(ink.rgb, 1.0) * light;
    c = c * (1.0 - dash) + vec4(1.0) * dash;
    fragColor = c * qt_Opacity;
}
