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
    float mono;       // 1: black and white in the color tools' place, the B&W EQ in eqA0 and eqA1 (edit.mono_at)
    float saturation; // chroma times this (not where a pin protects)
    float vibrance;   // chroma of the muted colors times 1 + this, of the vivid ones left alone
    float chromaOn;   // 1: the chroma curve is not the straight line
    float eqCount;    // how many points the color EQ has
    float showMask;   // 1 + the mask that is shown instead of the picture (H held); 0: none;
                      // below zero: that mask laid over the picture in red (while it is painted).
                      // For what is counted (scope 2 to 5, 8, 9): only what is in that mask counts
    float maskTint;   // how much of that red there is, 0..1 (it fades in and out)
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
    float curve2On;   // A mask's own tone curve, chroma curve and color EQ (edit.over_uniforms):
    float chroma2On;  // a second pass on top of the whole image's, each straight after it.
    float eq2Count;   // Nothing of it outside a mask's picture (onlyMask).
    mat4 curve2X;
    mat4 curve2Y;
    mat4 curve2M;
    mat4 chroma2X;
    mat4 chroma2Y;
    mat4 chroma2M;
    mat4 eq2A0;
    mat4 eq2A1;
    float grain;      // Film grain (edit.grain_uniforms): how far a grain is from the picture's lightness,
    float grainWide;  // how many grains lie across the stored picture,
    float grainHigh;  // and down it,
    float grainRough; // how much of it is clumps three grains wide,
    float grainColor; // and how colored it is.
    mat4 grainX;      // How strong it is from black to white: a curve, as the tone curve is one.
    mat4 grainY;
    mat4 grainM;
    float lutCount;   // The photo's LUTs (edit.luts_uniforms): how many, and one column each:
    mat4 lutsA;       // points a side, how much of it is laid on, the row its slices begin at.
    mat4 lutsB;       // (Four to a matrix: sixteen in all.)
    mat4 lutsC;
    mat4 lutsD;
    float detailX;    // Sharpening and noise reduction (edit.detail_uniforms): one pixel of the stored
    float detailY;    // picture as a share of it, across and down;
    float sharpen;    // how much of a pixel's difference from its neighbors is added,
    float sharpenRadius; // how far those neighbors are, in pixels,
    float sharpenMask;   // and the difference below which nothing is;
    float denoise;    // how far apart two pixels' lightness may be and count as one surface,
    float denoiseColor;  // and how far for their color.
    float lensOn;     // Lens corrections (photone/lens.py, tables): 1 if any is anything.
    float lensShape;  // The stored picture's width over its height.
    mat4 lensGreen;   // Sixteen numbers each, from the picture's middle (the first) to its corner:
    mat4 lensRed;     // how many times further out the stored picture is read, for green, red
    mat4 lensBlue;    // and blue (distortion, chromatic aberration),
    mat4 lensLight;   // and how many times lighter a pixel is made (vignetting).
    float defringePurple; // Fringes at edges taken out by their color (`defringed`): how much of the
    float defringeGreen;  // purple ones, and of the green ones.
};
layout(binding = 1) uniform sampler2D source;  // the first picture, with mipmaps
// The full-size picture. Bound from the moment it arrives, used or not, so that the GPU
// has it before the view first needs it: sending 264 MB there takes a tenth of a second,
// which must not happen at the moment of zooming in.
layout(binding = 2) uniform sampler2D sharp;
// The photo's painted masks, one in each of red, green and blue (edit.painted).
layout(binding = 3) uniform sampler2D painted;
// The photo's LUTs as one picture: each one's slices of one blue side by side, red across and
// green down, in a band of its own, one under the other (photone/lut.py, stacked). Any
// picture where there are none: it is then not read.
layout(binding = 4) uniform sampler2D lut;

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
float toneCurve(mat4 X, mat4 Y, mat4 M, float lightness) {
    float x = clamp(lightness, 0.0, 1.0);
    return curveAt(X, Y, M, x) + lightness - x;
}

// The chroma curve: chroma in, chroma out, 0.4 being the curve's right end; beyond it, on at
// the pace of the picture.
float chromaCurve(mat4 X, mat4 Y, mat4 M, float chroma) {
    float x = chroma / 0.4;
    return (curveAt(X, Y, M, min(x, 1.0)) + max(x - 1.0, 0.0)) * 0.4;
}

// What the color EQ makes of the chroma of a color of that hue (degrees): times this
// (edit.eq_at).
float eqGain(mat4 A0, mat4 A1, float count, float hue) {
    float gain = 1.0;
    for (int i = 0; i < 8; i++) {
        if (float(i) >= count) break;
        vec4 point = i < 4 ? A0[i] : A1[i - 4];
        float apart = abs(mod(hue - point.x + 180.0, 360.0) - 180.0);
        gain += (0.5 + 0.5 * cos(3.14159265 * min(apart / point.z, 1.0))) * point.y;  // a bell (edit._bell)
    }
    return max(gain, 0.0);
}

// A LUT (`of`: its points a side, how much of it, the row its band begins at), laid on the
// developed picture before the tone curve and the color tools. It is a table from one
// screen color to another (sRGB, encoded), so the picture goes there and back; what is
// brighter than the screen's white (HDR) is carried past it unchanged.
vec3 lutAt(vec3 v, vec4 of) {
    vec2 whole = vec2(textureSize(lut, 0));
    float last = of.x - 1.0, blue = v.b * last, under = floor(blue);
    vec2 within = vec2(0.5 + v.r * last, of.z + 0.5 + v.g * last);
    return mix(texture(lut, (within + vec2(under * of.x, 0.0)) / whole).rgb,
               texture(lut, (within + vec2(min(under + 1.0, last) * of.x, 0.0)) / whole).rgb, blue - under);
}
vec3 decoded(vec3 v) {
    return mix(v / 12.92, pow((v + 0.055) / 1.055, vec3(2.4)), step(0.04045, v));
}
vec3 graded(vec3 c, vec4 of) {
    vec3 shown = TO_SRGB * c, kept = clamp(shown, 0.0, 1.0);
    return inverse(TO_SRGB) * (decoded(clamp(lutAt(encode(kept), of), 0.0, 1.0)) + shown - kept);
}

// Film grain: a number for every place of a lattice of grains, the same whenever that place
// is drawn (the pattern is the picture's, not the screen's), from -0.5 to 0.5.
float grainSeed(vec2 cell) {
    vec3 p = fract(vec3(cell.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float grainLattice(vec2 at) {
    vec2 cell = floor(at), part = fract(at);
    part = part * part * (3.0 - 2.0 * part);
    return mix(mix(grainSeed(cell), grainSeed(cell + vec2(1.0, 0.0)), part.x),
               mix(grainSeed(cell + vec2(0.0, 1.0)), grainSeed(cell + vec2(1.0, 1.0)), part.x), part.y) - 0.5;
}
// (Two lattices turned against each other, 30 and 71 degrees: one alone shows its rows and
// columns as little squares, which no film has.)
float grainField(vec2 at) {
    return (grainLattice(mat2(0.866, 0.5, -0.5, 0.866) * at) + grainLattice(mat2(0.326, 0.945, -0.945, 0.326) * at + 19.7)) * 0.7071;
}
// The grain at a place counted in grains: the fine grain, and with roughness clumps two
// grains wide on top. Where a pixel of the screen covers several grains it shows their
// average, which is as much weaker as it covers grains across.
float grainAt(vec2 at, float shift) {
    float fine = grainField(at + shift) + grainRough * 0.8 * grainField(at / 2.1 + shift + 57.0);
    vec2 covered = fwidth(at);
    return fine / max(1.0, max(covered.x, covered.y));
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
// would show as a grid), and with a the lightness, with b whether the pixel counts (`counts`).
vec4 packed(vec3 lab, bool second, float counts) {
    float wide = clamp((second ? lab.z : lab.y) + 0.5, 0.0, 1.0) * 65535.0;
    float high = floor(wide / 256.0);
    return vec4(high / 255.0, floor(wide - high * 256.0) / 255.0, second ? counts : clamp(lab.x, 0.0, 1.0), 1.0);
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

const vec3 THIRD = vec3(1.0 / 3.0);

// Fringes: the purple (or green) seam a lens draws along an edge between dark and light.
// Where the pixels three away differ much in lightness (an edge), what the pixel has of
// purple (red and blue both above green) or of green (green above both) is taken out, as
// much as asked; a purple or green thing that is no edge keeps its color. In the square
// root of the light, as `detailed`.
vec3 defringed(sampler2D tex, vec2 at, vec3 centre, float much) {
    vec2 px = vec2(detailX, detailY);
    vec3 s = sqrt(max(centre, 0.0));
    float y0 = dot(s, THIRD), low = y0, high = y0;
    for (int i = 0; i < 8; i++) {
        float turn = float(i) * 0.7853982;
        float y = dot(sqrt(max(texture(tex, at + 3.0 * vec2(cos(turn), sin(turn)) * px).rgb, 0.0)), THIRD);
        low = min(low, y); high = max(high, y);
    }
    float edge = smoothstep(0.08, 0.25, high - low) * much;
    float purple = max(min(s.r, s.b) - s.g, 0.0), green = max(s.g - max(s.r, s.b), 0.0);
    s.rb -= defringePurple * edge * purple;
    s.g -= defringeGreen * edge * green;
    return s * s;
}

// A lens correction's number for a place that far from the picture's middle (1: its corner):
// sixteen of them, the first at the middle, a straight line between two.
float lensAt(mat4 table, float r) {
    float x = clamp(r, 0.0, 1.0) * 15.0, low = min(floor(x), 14.0);
    int i = int(low), j = i + 1;
    return mix(table[i >> 2][i & 3], table[j >> 2][j & 3], x - low);
}

// Sharpening and noise reduction, first of all: the pixel at `at` of that picture, read with
// its neighbors (counted in pixels of the stored picture, whichever of its two pictures is
// read). In the square root of its light, where a sensor's noise is as strong in the dark as
// in the light, a pixel is a lightness (the mean of the three) and a color (what each of the
// three differs from it by). Noise reduction is the weighted mean of the neighbors', each
// counting the more the nearer its lightness is to this pixel's (an edge is not blurred
// across): of the lightness over the eight around and eight a little further, of the color
// over those and sixteen further out, since a sensor's color noise comes in larger blotches.
// Sharpening adds what the pixel's lightness differs by from the mean of the eight around it
// (at `sharpenRadius`), unless that is less than `sharpenMask` (noise, not an edge).
// `much`: how much of all this is done (none where the photo is seen from far: there is
// nothing of a pixel's size to see, and the neighbors read would be no neighbors).
vec3 detailed(sampler2D tex, vec2 at, vec3 centre, float much) {
    vec2 px = vec2(detailX, detailY);
    vec3 s0 = sqrt(max(centre, 0.0));
    float y0 = dot(s0, THIRD), near = max(sharpen > 0.0 ? sharpenRadius : 1.0, 0.5);
    float nearSum = 0.0, lightSum = y0, lightWeight = 1.0, colorWeight = 1.0;
    vec3 colorSum = s0 - y0;
    float keepLight = 1.0 / max(denoise * denoise, 1e-8), keepColor = 1.0 / max(denoiseColor * denoiseColor, 1e-8);
    for (int i = 0; i < 16; i++) {
        // The eight around (at `near` pixels), then eight at knight's moves from it.
        vec2 step = i < 8 ? near * vec2(float((i < 3 ? i : i < 5 ? (i - 3) * 2 : i - 5) - 1), float(i < 3 ? -1 : i < 5 ? 0 : 1))
                          : vec2(float((i - 8) / 4 == 0 ? 2 : 1) * ((i & 1) == 0 ? 1.0 : -1.0), float((i - 8) / 4 == 0 ? 1 : 2) * ((i & 2) == 0 ? 1.0 : -1.0));
        if (i >= 8 && denoise <= 0.0 && denoiseColor <= 0.0) break;
        vec3 s = sqrt(max(texture(tex, at + step * px).rgb, 0.0));
        float y = dot(s, THIRD), apart = (y - y0) * (y - y0);
        if (i < 8) nearSum += y;
        if (denoise > 0.0) { float w = exp(-apart * keepLight); lightSum += w * y; lightWeight += w; }
        if (denoiseColor > 0.0) { float w = exp(-apart * keepColor); colorSum += w * (s - y); colorWeight += w; }
    }
    if (denoiseColor > 0.0) {
        for (int i = 0; i < 16; i++) {  // two rings, four and seven pixels out, the second turned against the first
            float turn = (float(i & 7) + (i < 8 ? 0.0 : 0.5)) * 0.7853982;
            vec3 s = sqrt(max(texture(tex, at + (i < 8 ? 4.0 : 7.0) * vec2(cos(turn), sin(turn)) * px).rgb, 0.0));
            float y = dot(s, THIRD), w = exp(-(y - y0) * (y - y0) * keepColor);
            colorSum += w * (s - y); colorWeight += w;
        }
    }
    float light = denoise > 0.0 ? lightSum / lightWeight : y0;
    vec3 color = denoiseColor > 0.0 ? colorSum / colorWeight : s0 - y0;
    if (sharpen > 0.0) {
        float edge = y0 - nearSum / 8.0, floor_ = sharpenMask + denoise * 0.5;
        light += sharpen * edge * smoothstep(floor_, 2.0 * floor_ + 1e-5, abs(edge));
    }
    vec3 s = mix(s0, max(light + color, 0.0), much);
    return s * s;
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
    vec2 here = qt_TexCoord0;   // where in the stored picture this pixel is read
    float lighter = 1.0;
    if (lensOn > 0.5) {
        // Lens corrections: the picture is read a little further out or in than where the
        // pixel is (distortion), red and blue each a little apart from green (chromatic
        // aberration), and made lighter toward the corners (vignetting); by how far the
        // pixel is from the picture's middle, its corner being 1.
        vec2 out_ = (qt_TexCoord0 - 0.5) * vec2(lensShape, 1.0);
        float r = length(out_) / length(vec2(lensShape, 1.0) * 0.5);
        float green = lensAt(lensGreen, r);
        here = 0.5 + (qt_TexCoord0 - 0.5) * green;
        lighter = lensAt(lensLight, r);
        vec2 red = 0.5 + (qt_TexCoord0 - 0.5) * lensAt(lensRed, r), blue = 0.5 + (qt_TexCoord0 - 0.5) * lensAt(lensBlue, r);
        // (Seen from close, the photo's own pixels as squares here too: each of the three
        // places is the middle of the pixel it lies in. Left out, a corrected photo was
        // smooth at any zoom; the owner: "i can no longer see pixels at 200%+ zoom".)
        if (crisp > 0.5) {
            if (useSharp > 0.5) { red = squarely(sharp, red); here = squarely(sharp, here); blue = squarely(sharp, blue); }
            else { red = squarely(source, red); here = squarely(source, here); blue = squarely(source, blue); }
        }
        if (useSharp > 0.5) pixel = vec3(texture(sharp, red).r, texture(sharp, here).g, texture(sharp, blue).b);
        else pixel = vec3(texture(source, red).r, texture(source, here).g, texture(source, blue).b);
    } else {
        // (`here` is then the place sharpening and noise reduction read the neighbors from:
        // the pixel's middle, so that all of a square is one color.)
        if (crisp > 0.5) here = useSharp > 0.5 ? squarely(sharp, here) : squarely(source, here);
        pixel = useSharp > 0.5 ? texture(sharp, here).rgb : texture(source, here).rgb;
    }
    bool fringes = defringePurple > 0.0 || defringeGreen > 0.0;
    if (fringes || sharpen > 0.0 || denoise > 0.0 || denoiseColor > 0.0) {
        // (All of it where a pixel of the photo is a pixel of the screen or larger; none
        // where two or more of them go into one.)
        vec2 covered = fwidth(qt_TexCoord0) / vec2(detailX, detailY);
        float much = clamp(2.0 - max(covered.x, covered.y), 0.0, 1.0);
        if (much > 0.0 && fringes) {
            if (useSharp > 0.5) pixel = defringed(sharp, here, pixel, much);
            else pixel = defringed(source, here, pixel, much);
        }
        if (much > 0.0 && (sharpen > 0.0 || denoise > 0.0 || denoiseColor > 0.0)) {
            if (useSharp > 0.5) pixel = detailed(sharp, here, pixel, much);
            else pixel = detailed(source, here, pixel, much);
        }
    }
    pixel *= lighter;
    vec3 c = develop(pixel);
    for (int i = 0; i < 16; i++) {  // the photo's LUTs, one after the other
        if (float(i) >= lutCount) break;
        vec4 of = i < 4 ? lutsA[i] : i < 8 ? lutsB[i - 4] : i < 12 ? lutsC[i - 8] : lutsD[i - 12];
        if (of.y > 0.0) c = mix(c, graded(c, of), of.y);
    }
    if (showMask > 0.5 && scope < 0.5) {  // a mask: white where it is, on a dim gray of the picture
        float shown = mix(0.04 + 0.22 * clamp(dot(c, LUMA), 0.0, 1.0), 1.0, maskWeight(int(showMask) - 1));
        fragColor = vec4(vec3(linearOut > 0.5 ? pow(shown, 2.2) : shown), 1.0) * qt_Opacity;
        return;
    }
    if (curveOn > 0.5 || curve2On > 0.5 || (scope > 0.5 && scope < 5.5) || look > 0.5 || scope > 7.5) {
        vec3 roots = rootsOf(c);
        float lightness = dot(LIGHTNESS, roots);
        if (scope > 0.5 && scope < 1.5) {
            fragColor = vec4(vec3(clamp(lightness, 0.0, 1.0)), 1.0);
            return;
        }
        float lit = curveOn > 0.5 ? toneCurve(curveX, curveY, curveM, lightness) : lightness;
        if (curve2On > 0.5) lit = toneCurve(curve2X, curve2Y, curve2M, lit);  // a mask's own, on top
        roots += lit - lightness;
        if (look > 0.5 || scope > 1.5) {
            // Look: on the color as OKLab has it. The pins, then saturation (not where a pin
            // protects), the chroma curve, the color EQ: edit.colors_at is the same arithmetic.
            vec3 lab = ROOTS_TO_LAB * roots;
            // Whether this pixel counts for the wheel: all of the photo, or, while a mask's
            // pins are worked on, what that mask reaches (0.02 of it or more: what it can
            // change so that it shows). The owner: "ONLY what the mask actually sees".
            float counts = showMask > 0.5 ? step(0.02, maskWeight(int(showMask) - 1)) : 1.0;
            if (scope > 1.5 && scope < 3.5) { fragColor = packed(lab, scope > 2.5, counts); return; }
            // For the wheel's dots, which are drawn from it (dots.vert): the color itself, as
            // numbers of a float picture; before the pins (8) or after everything (9).
            if (scope > 7.5 && scope < 8.5) { fragColor = vec4(lab, counts); return; }
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
            if (mono > 0.5) {
                // Black and white, in the color tools' place: the color's own lightness, made
                // lighter or darker for its hue, the less the nearer it is to gray (0.04:
                // edit.TINTED).
                float lighter = chroma > 1e-6 ? eqGain(eqA0, eqA1, eqCount, degrees(atan(lab.z, lab.y))) - 1.0 : 0.0;
                lab = vec3(lab.x * (1.0 + lighter * chroma / (chroma + 0.04)), 0.0, 0.0);
            } else if (chroma > 1e-6) {
                float after = chroma * mix(saturation, 1.0, shield);
                float hue = degrees(atan(lab.z, lab.y));
                if (vibrance != 0.0) {  // the muted colors, and skin less (edit.vibrance_at)
                    float skin = 1.0 - 0.7 * (1.0 - smoothstep(15.0, 35.0, abs(mod(hue - 55.0 + 180.0, 360.0) - 180.0)));
                    after *= 1.0 + vibrance * (1.0 - shield) * skin * (1.0 - smoothstep(0.0, 0.25, after));
                }
                if (chromaOn > 0.5) after = chromaCurve(chromaX, chromaY, chromaM, after);
                if (eqCount > 0.5) after *= eqGain(eqA0, eqA1, eqCount, hue);
                // A mask's own chroma curve and EQ, on top of the whole image's.
                if (chroma2On > 0.5) after = chromaCurve(chroma2X, chroma2Y, chroma2M, after);
                if (eq2Count > 0.5) after *= eqGain(eq2A0, eq2A1, eq2Count, hue);
                lab.yz *= after / chroma;
            }
            if (scope > 3.5 && scope < 5.5) { fragColor = packed(lab, scope > 4.5, counts); return; }
            if (scope > 8.5) { fragColor = vec4(lab, counts); return; }
            if (grain > 0.0) {
                // Film grain, last of all (not in what the scopes count, which returned
                // above): lighter and darker by the grain at this place of the stored
                // picture, as strong as the response curve says for this lightness.
                vec2 at = qt_TexCoord0 * vec2(grainWide, grainHigh);
                float strength = grain * max(curveAt(grainX, grainY, grainM, clamp(lab.x, 0.0, 1.0)), 0.0);
                lab.x = max(lab.x + strength * grainAt(at, 0.0), 0.0);
                if (grainColor > 0.0) lab.yz += strength * grainColor * 0.5 * vec2(grainAt(at, 211.0), grainAt(at, 467.0));
            }
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
    if (showMask < -0.5 && scope < 0.5) c = mix(c, vec3(1.0, 0.12, 0.1), 0.42 * maskTint * maskWeight(int(-showMask) - 1));
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
