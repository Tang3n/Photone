#version 440
// The pipeline: every adjustment is a uniform here, so a change costs one draw and nothing is
// computed on the CPU. Input: scene-linear Rec.2020 (decode.py). Output: sRGB-encoded, as
// every surface measured so far expects; on an HDR surface the same encoding simply continues
// above 1.0 (white), up to `peak`.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) in vec2 place;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float linearOut;  // 1 only for a surface that takes linear light (session.linearSurface)
    float peak;       // the brightest light let through, in multiples of SDR white (1 in SDR)
    float useSharp;   // 1: draw from the full-size picture (the view is close enough to need it)
    float crisp;      // 1: the photo's own pixels as squares (seen from closer than twice their size)
    float scope;      // not the picture but, to be counted: 1 its lightness before the tone curve,
                      // 2 its OKLab a and lightness, 3 its OKLab b, both before the pins;
                      // 4 and 5 the same after everything done to colors;
                      // 6 and 7: the picture itself in sixteen bits a color, for an export:
                      // red's high and low byte and green's high one, then the rest
    float clipping;   // 1: paint what is cut off at white red, and what is black blue
    // The edit, as photone/edit.py works it out (uniforms):
    float gain;       // 2^exposure
    float mid;        // where mid gray lies: for a sensor, for a finished picture
    float contrast;   // stops from mid gray are stretched by 1 + this
    float brightness; // a power on the finished picture's luminance, less one
    float highlights; // stops added at the sensor's white, fading out toward mid gray
    float shadows;    // stops added in the deep shadows, fading out toward mid gray
    float midtones;   // stops added at mid gray, fading out to both sides
    float whites;     // stops added to what is shown at white, fading out toward mid gray
    float blacks;     // light taken from what is shown at black, fading out toward mid gray
    float curveC;     // the profile's tone curve y = k x^c / (x^c + s); c = 0: none
    float curveS;
    float curveK;
    float hdrLift;    // HDR: how far above white the sensor's white is shown (0 in SDR)
    float curveOn;    // 1: the user's tone curve is not the straight line
    float pinCount;   // how many color pins there are (edit.pins_uniforms)
    float reach;      // 1 + the pin whose reach is shown instead of the picture (H held); 0: none
    float look;       // 1: something is done to colors after the tone curve (edit.look_uniforms)
    float saturation; // chroma times this (not where a pin protects)
    float vibrance;   // chroma of the muted colors times 1 + this, of the vivid ones left alone
    float chromaOn;   // 1: the chroma curve is not the straight line
    float eqCount;    // how many points the color EQ has
    float showMask;   // 1 + the mask that is shown instead of the picture (H held); 0: none;
                      // below zero: that mask laid over the picture in red (while it is painted)
    vec4 wbGain;      // white balance: a gain on each of the camera's channels; a = their ceiling
    mat4 toCam;       // Rec.2020 -> the camera's own colors (upper 3x3)
    mat4 fromCam;     // and back
    mat4 curveX;      // the tone curve: 16 points' lightness in,
    mat4 curveY;      // lightness out,
    mat4 curveM;      // and the slope there (edit.curve_uniforms)
    mat4 pinsA0;      // the color pins, four to a matrix, one column each:
    mat4 pinsA1;      // A: from (a, b), to (a, b)
    mat4 pinsA2;
    mat4 pinsB0;      // B: range, core, lightness shift, variance
    mat4 pinsB1;
    mat4 pinsB2;
    mat4 pinsC0;      // C: least and most lightness, kind (0 offset, 1 rotate, 2 protect)
    mat4 pinsC1;
    mat4 pinsC2;
    mat4 chromaX;     // the chroma curve, as the tone curve: 16 points' chroma in (a share of 0.4),
    mat4 chromaY;     // chroma out,
    mat4 chromaM;     // and the slope there
    mat4 eqA0;        // the color EQ, four points to a matrix, one column each:
    mat4 eqA1;        // hue (degrees), gain less one, width (degrees)
    mat4 frame;       // the photo's frame: used by the vertex stage (pipeline.vert)
    mat4 masksA0;     // the masks, four to a matrix, one column each (edit.masks_uniforms):
    mat4 masksA1;     // x, y, z for how far along its axis a place is, and its kind
    mat4 masksB0;     // x, y, z for how far across it, and its feather
    mat4 masksB1;
    vec4 cropBox;     // the crop frame in the item's own 0..1: left, top, right, bottom
    float cropDim;    // 1 while the Crop tool is open: what lies outside the frame is dimmed
    float onlyMask;   // 1, 2, …: this is the picture inside that mask, drawn by the mask's weight
    float hdrFit;     // what is shown is multiplied by this after the HDR climb (1; less: a trial for exports)
    float stripes;    // how far the stripes of the clipping paint have run, in stripes (it moves)
};
layout(binding = 1) uniform sampler2D source;  // the first picture, with mipmaps
// The full-size picture. Bound from the moment it arrives, used or not, so that the GPU
// has it before the view first needs it: sending 264 MB there takes a tenth of a second,
// which must not happen at the moment of zooming in.
layout(binding = 2) uniform sampler2D sharp;
// The photo's painted masks, one in each of red, green and blue (edit.painted).
layout(binding = 3) uniform sampler2D painted;

#include "oklab.glsl"

// In HDR, ease into the display's peak instead of running into it, so the brightest
// highlights keep some shape: unchanged up to the knee, then an exponential approach.
vec3 shoulder(vec3 c) {
    float knee = 0.9 * peak, room = peak - knee;
    return min(c, vec3(knee)) + room * (1.0 - exp(-max(c - knee, 0.0) / room));
}

const vec3 LUMA = vec3(0.2627, 0.6780, 0.0593);  // of Rec.2020

// A curve the user draws, through 16 points with their slopes (edit.curve_at is the same
// arithmetic): flat outside its end points, a cubic between two neighbors. x is 0..1.
float curveAt(mat4 X, mat4 Y, mat4 M, float x) {
    float y = x <= X[0][0] ? Y[0][0] : Y[3][3];
    for (int i = 0; i < 15; i++) {
        int j = i + 1;
        float x0 = X[i >> 2][i & 3], x1 = X[j >> 2][j & 3];
        if (x > x0 && x <= x1) {
            float h = x1 - x0, t = (x - x0) / h, t2 = t * t, t3 = t2 * t;
            y = (2.0 * t3 - 3.0 * t2 + 1.0) * Y[i >> 2][i & 3] + (t3 - 2.0 * t2 + t) * h * M[i >> 2][i & 3]
              + (3.0 * t2 - 2.0 * t3) * Y[j >> 2][j & 3] + (t3 - t2) * h * M[j >> 2][j & 3];
        }
    }
    return y;
}

// The tone curve: lightness in, lightness out. Above white, which only HDR has, it carries
// on at the pace of the picture.
float toneCurve(float lightness) {
    float x = clamp(lightness, 0.0, 1.0);
    return curveAt(curveX, curveY, curveM, x) + lightness - x;
}

// What the color EQ makes of the chroma of a color of that hue (degrees): times this
// (edit.eq_at).
float eqGain(float hue) {
    float gain = 1.0;
    for (int i = 0; i < 8; i++) {
        if (float(i) >= eqCount) break;
        vec4 point = i < 4 ? eqA0[i] : eqA1[i - 4];
        float apart = abs(mod(hue - point.x + 180.0, 360.0) - 180.0);
        gain += (1.0 - smoothstep(point.z * 0.5, point.z, apart)) * point.y;
    }
    return max(gain, 0.0);
}

// Develop: from what the sensor measured to a picture. All of it on scene-linear light.
vec3 develop(vec3 c) {
    // White balance, where it belongs: as a gain on the camera's own channels.
    c = mat3(fromCam) * min((mat3(toCam) * c) * wbGain.rgb, vec3(wbGain.a));
    c = max(c, vec3(0.0)) * gain;
    // Contrast, highlights and shadows: a gain that depends on how bright the pixel is, in
    // stops from mid gray, so hue and saturation stay as they are.
    float stops = log2(max(dot(c, LUMA), 1e-6) / mid);
    c *= exp2(contrast * stops + shadows * (1.0 - smoothstep(-4.5, 0.5, stops))
              + highlights * smoothstep(-0.5, 3.0, stops));
    // Midtones (edit.tone_at): the same kind of gain, most within half a stop of mid gray
    // and none two and a half stops from it either way. A step of its own, on what the
    // gains above have made: each step keeps a lighter tone lighter, so both together do.
    if (midtones != 0.0) {
        float away = abs(log2(max(dot(c, LUMA), 1e-6) / mid));
        c *= exp2(midtones * (1.0 - smoothstep(0.5, 2.5, away)));
    }
    float gray = mid;  // where mid gray is shown: by the profile's curve, if there is one
    if (curveC > 0.0) {
        vec3 p = pow(c, vec3(curveC));
        c = curveK * p / (p + curveS);
        gray = curveK * pow(mid, curveC) / (pow(mid, curveC) + curveS);
    }
    // Blacks and Whites (edit.tone_at): the two ends of what is shown, mid gray staying where
    // it is. Blacks takes light away below it (more, the nearer black: what is left of black
    // is cut off) or adds some; Whites is a gain in stops above it (most at white). On what
    // is shown and not on what the sensor recorded: the curve squeezes the top two stops of
    // the sensor into the last few steps under white, where a gain shows as nothing.
    if (blacks != 0.0 || whites != 0.0) {
        c = max(c - blacks * (1.0 - smoothstep(0.0, gray, dot(c, LUMA))), 0.0);
        c *= exp2(whites * smoothstep(gray, 1.0, dot(c, LUMA)));
    }
    // Brightness: lifts or lowers the middle and leaves black and white where they are.
    return c * pow(clamp(dot(c, LUMA), 1e-6, 1.0), brightness);
}

// The color pins (the same arithmetic as edit.pins_at): each moves the color as it was, the
// moves add up, and what a protecting pin covers is moved that much less.
const float TURN = 6.2831853;
const float BAND = 0.05;      // as in photone/edit.py
vec4 pinA(int i) { return i < 4 ? pinsA0[i] : i < 8 ? pinsA1[i - 4] : pinsA2[i - 8]; }
vec4 pinB(int i) { return i < 4 ? pinsB0[i] : i < 8 ? pinsB1[i - 4] : pinsB2[i - 8]; }
vec4 pinC(int i) { return i < 4 ? pinsC0[i] : i < 8 ? pinsC1[i - 4] : pinsC2[i - 8]; }
float between(float angle) { return angle - TURN * floor(angle / TURN + 0.5); }
vec2 turned(vec2 c, float angle) { return vec2(cos(angle) * c.x - sin(angle) * c.y, sin(angle) * c.x + cos(angle) * c.y); }

// How much of mask m (0, 1, …) this pixel is in, by its place in the stored picture
// (edit.mask_weight is the same arithmetic). Kind: 0 radial, 1 linear, 2 painted (A.x is then
// its channel of `painted`), 4 more when inverted.
float maskWeight(int m) {
    vec4 A = m < 4 ? masksA0[m] : masksA1[m - 4], B = m < 4 ? masksB0[m] : masksB1[m - 4];
    float along = dot(qt_TexCoord0, A.xy) + A.z, weight, kind = mod(A.w, 4.0);
    if (kind > 1.5) {
        vec3 all = texture(painted, qt_TexCoord0).rgb;
        weight = A.x < 0.5 ? all.r : A.x < 1.5 ? all.g : all.b;
    } else if (kind > 0.5) weight = 1.0 - smoothstep(-1.0, 1.0, along);
    else weight = 1.0 - smoothstep(1.0 - B.w, 1.0, length(vec2(along, dot(qt_TexCoord0, B.xy) + B.z)));
    return A.w > 3.5 ? 1.0 - weight : weight;
}

float pinWeight(int i, vec3 lab) {
    vec4 A = pinA(i), B = pinB(i), C = pinC(i);
    float weight = 1.0 - smoothstep(B.y, B.x, distance(lab.yz, A.xy));
    if (C.x > 0.0) weight *= smoothstep(C.x - BAND, C.x + BAND, lab.x);
    if (C.y < 1.0) weight *= 1.0 - smoothstep(C.y - BAND, C.y + BAND, lab.x);
    if (C.w > 0.5) weight *= maskWeight(int(C.w) - 1);  // kept to a part of the picture
    return weight;
}

vec3 pinned(vec3 lab, out float shield) {
    vec3 moved = vec3(0.0);
    shield = 0.0;
    for (int i = 0; i < 12; i++) {
        if (float(i) >= pinCount) break;
        vec4 A = pinA(i), B = pinB(i), C = pinC(i);
        float weight = pinWeight(i, lab);
        if (C.z > 1.5) { shield = max(shield, weight); continue; }
        vec2 color = lab.yz;
        bool hue = length(A.xy) >= 0.02;  // the source has one
        if (hue && B.w != 0.0 && length(color) > 1e-6) {
            float apart = between(atan(color.y, color.x) - atan(A.y, A.x));
            moved.yz += turned(color, weight * B.w * apart) - color;
        }
        if (C.z > 0.5 && hue) {
            float turn = between(atan(A.w, A.z) - atan(A.y, A.x));
            float grown = 1.0 + weight * (length(A.zw) / length(A.xy) - 1.0);
            moved.yz += turned(color, weight * turn) * grown - color;
        } else {
            moved.yz += weight * (A.zw - A.xy);
        }
        moved.x += weight * B.z;
    }
    return lab + (1.0 - shield) * moved;
}

// A color for the wheel, to be read back: a (or b) from -0.5 to 0.5 in sixteen bits (one byte
// would show as a grid), and the lightness.
vec4 packed(vec3 lab, bool second) {
    float wide = clamp((second ? lab.z : lab.y) + 0.5, 0.0, 1.0) * 65535.0;
    float high = floor(wide / 256.0);
    return vec4(high / 255.0, floor(wide - high * 256.0) / 255.0, clamp(lab.x, 0.0, 1.0), 1.0);
}

// Where to read a picture so that each of its pixels shows as a square of its own color, with
// an edge one pixel of the screen soft: the middle of the pixel the place lies in, moving to
// the next one only across the last pixel of the screen before it. (Read where the place
// itself is, a picture seen from close up is a blur between its pixels; the owner: "Past
// enough zoom ... I would like to see the actual pixels".)
vec2 squarely(sampler2D picture, vec2 place) {
    vec2 size = vec2(textureSize(picture, 0));
    vec2 at = place * size - 0.5, first = floor(at);
    vec2 across = clamp((at - first - 0.5) / fwidth(at) + 0.5, 0.0, 1.0);
    return (first + 0.5 + across) / size;
}

void main() {
    // Beyond the picture (the Crop tool shows it turned, in a rectangle larger than it is):
    // nothing; on its edge, as much as the pixel covers, so that a turned edge is smooth and
    // not a staircase. (A pixel's centre half a pixel inside the picture is wholly in it.)
    vec2 inside = min(qt_TexCoord0, 1.0 - qt_TexCoord0) / max(fwidth(qt_TexCoord0), vec2(1e-6));
    float cover = clamp(min(inside.x, inside.y) + 0.5, 0.0, 1.0);
    if (cover <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    if (onlyMask < -0.5) {  // how much that mask weighs here, as a gray (a 16-bit export mixes by it)
        fragColor = vec4(vec3(maskWeight(int(-onlyMask) - 1)), 1.0);
        return;
    }
    vec3 pixel;
    if (useSharp > 0.5) pixel = texture(sharp, crisp > 0.5 ? squarely(sharp, qt_TexCoord0) : qt_TexCoord0).rgb;
    else pixel = texture(source, crisp > 0.5 ? squarely(source, qt_TexCoord0) : qt_TexCoord0).rgb;
    vec3 c = develop(pixel);
    if (showMask > 0.5 && scope < 0.5) {  // a mask: white where it is, on a dim gray of the picture
        float shown = mix(0.04 + 0.22 * clamp(dot(c, LUMA), 0.0, 1.0), 1.0, maskWeight(int(showMask) - 1));
        fragColor = vec4(vec3(linearOut > 0.5 ? pow(shown, 2.2) : shown), 1.0) * qt_Opacity;
        return;
    }
    if (curveOn > 0.5 || (scope > 0.5 && scope < 5.5) || look > 0.5 || scope > 7.5) {
        vec3 roots = rootsOf(c);
        float lightness = dot(LIGHTNESS, roots);
        if (scope > 0.5 && scope < 1.5) {
            fragColor = vec4(vec3(clamp(lightness, 0.0, 1.0)), 1.0);
            return;
        }
        roots += toneCurve(lightness) - lightness;
        if (look > 0.5 || scope > 1.5) {
            // Look: on the color as OKLab has it. The pins, then saturation (not where a pin
            // protects), the chroma curve, the color EQ: edit.colors_at is the same arithmetic.
            vec3 lab = ROOTS_TO_LAB * roots;
            if (scope > 1.5 && scope < 3.5) { fragColor = packed(lab, scope > 2.5); return; }
            // For the wheel's dots, which are drawn from it (dots.vert): the color itself, as
            // numbers of a float picture; before the pins (8) or after everything (9).
            if (scope > 7.5 && scope < 8.5) { fragColor = vec4(lab, 1.0); return; }
            float shield = 0.0;
            if (pinCount > 0.5) {
                if (reach > 0.5 && scope < 0.5) {  // what one pin reaches: white on a dim gray of the picture
                    float shown = mix(0.04 + 0.22 * clamp(lab.x, 0.0, 1.0), 1.0, pinWeight(int(reach) - 1, lab));
                    fragColor = vec4(vec3(linearOut > 0.5 ? pow(shown, 2.2) : shown), 1.0) * qt_Opacity;
                    return;
                }
                lab = pinned(lab, shield);
            }
            float chroma = length(lab.yz);
            if (chroma > 1e-6) {
                float after = chroma * mix(saturation, 1.0, shield);
                float hue = degrees(atan(lab.z, lab.y));
                if (vibrance != 0.0) {  // the muted colors, and skin less (edit.vibrance_at)
                    float skin = 1.0 - 0.7 * (1.0 - smoothstep(15.0, 35.0, abs(mod(hue - 55.0 + 180.0, 360.0) - 180.0)));
                    after *= 1.0 + vibrance * (1.0 - shield) * skin * (1.0 - smoothstep(0.0, 0.25, after));
                }
                if (chromaOn > 0.5) {
                    float x = after / 0.4;
                    after = (curveAt(chromaX, chromaY, chromaM, min(x, 1.0)) + max(x - 1.0, 0.0)) * 0.4;
                }
                if (eqCount > 0.5) after *= eqGain(hue);
                lab.yz *= after / chroma;
            }
            if (scope > 3.5 && scope < 5.5) { fragColor = packed(lab, scope > 4.5); return; }
            if (scope > 8.5) { fragColor = vec4(lab, 1.0); return; }
            roots = LAB_TO_ROOTS * lab;
        }
        c = fromRoots(roots);
    }
    if (hdrLift > 0.0) {
        // HDR (edit.tone_at), last of all: what is shown climbs on by the square of how light
        // it is, until the sensor's white is at the display's peak: a little in the shadows,
        // the whole headroom at white, so that all of the picture is deeper. (The owner chose
        // this from a trial of three, 2026-11-18. After the curve and the colors' tools, which
        // must be handed the same picture as in SDR: lifted before them, a pin took hold of
        // other colors than the wheel showed; "the tone wheel pins are completely broken".)
        vec3 over = max(c, 0.0);
        c += hdrLift * over * over;
    }
    c *= hdrFit;
    c = max(TO_SRGB * c, vec3(0.0));
    float top = max(c.r, max(c.g, c.b));
    c = peak > 1.0 ? shoulder(c) : min(c, vec3(1.0));
    c = linearOut > 0.5 ? c : encode(c);
    if (scope > 5.5) {  // sixteen bits a color over two renders (photone/export.py, deep_of)
        vec3 wide = floor(clamp(c, 0.0, 1.0) * 65535.0 + 0.5);
        vec3 high = floor(wide / 256.0), low = wide - high * 256.0;
        fragColor = vec4((scope < 6.5 ? vec3(high.r, low.r, high.g) : vec3(low.g, high.b, low.b)) / 255.0, 1.0);
        return;
    }
    if (clipping > 0.5) {  // at the display's limit: one 8-bit step from white, from black
        // As stripes that run, like a camera's zebra: a still patch of red in a red flower
        // is easy to miss, a moving one is not (the owner's wish).
        float band = step(0.5, fract((gl_FragCoord.x + gl_FragCoord.y) / 14.0 - stripes));
        if (top >= 0.996 * peak) c = mix(vec3(1.0, 0.16, 0.14), vec3(0.16, 0.0, 0.0), band);
        else if (top < 0.0003) c = mix(vec3(0.14, 0.33, 1.0), vec3(0.72, 0.84, 1.0), band);
    }
    // Cropping: outside the frame, dimmed here and not by something laid over the picture,
    // which cut its own edge and left a bright pixel wherever the two edges disagreed (the
    // owner: "those bright pixels around those jagged edges"). As a black at 60 % over it.
    if (showMask < -0.5 && scope < 0.5) c = mix(c, vec3(1.0, 0.12, 0.1), 0.42 * maskWeight(int(-showMask) - 1));
    if (cropDim > 0.5 && (place.x < cropBox.x || place.y < cropBox.y || place.x > cropBox.z || place.y > cropBox.w))
        c *= linearOut > 0.5 ? 0.133 : 0.4;
    // A mask's own picture (developed with the mask's amounts added, Local.qml lays it over
    // the whole image's): as much of it as the mask weighs here.
    // SDR is eight bits a color, also on a surface that could show more: each color rounded
    // to one of 256 steps, so that SDR here bands exactly as an SDR screen or an 8-bit file
    // does (the owner's wish; without it SDR on the HDR surface was smoother than any SDR is).
    if (peak <= 1.0 && linearOut < 0.5) c = floor(clamp(c, 0.0, 1.0) * 255.0 + 0.5) / 255.0;
    float part = onlyMask > 0.5 ? maskWeight(int(onlyMask) - 1) : 1.0;
    fragColor = vec4(c, 1.0) * qt_Opacity * cover * part;
}
