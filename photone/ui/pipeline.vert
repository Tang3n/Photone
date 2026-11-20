#version 440
// Our own vertex stage (it does what Qt's default does) so that both stages are compiled for the
// same GLSL versions: Qt's default one is GLSL ES 1.00, which would hold the pipeline to that.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(location = 1) out vec2 place;  // where on the item, 0..1: the crop frame is given so
layout(std140, binding = 0) uniform buf {  // must match pipeline.frag exactly
    mat4 qt_Matrix;
    float qt_Opacity;
    float linearOut;
    float peak;
    float useSharp;
    float crisp;
    float scope;
    float clipping;
    float gain;
    float mid;
    float contrast;
    float brightness;
    float highlights;
    float shadows;
    float midtones;
    float whites;
    float blacks;
    float curveC;
    float curveS;
    float curveK;
    float hdrLift;
    float curveOn;
    float pinCount;
    float reach;
    float look;
    float mono;
    float saturation;
    float vibrance;
    float chromaOn;
    float eqCount;
    float showMask;
    float maskTint;
    vec4 wbGain;
    mat4 toCam;
    mat4 fromCam;
    mat4 curveX;
    mat4 curveY;
    mat4 curveM;
    mat4 pinsA0;
    mat4 pinsA1;
    mat4 pinsA2;
    mat4 pinsB0;
    mat4 pinsB1;
    mat4 pinsB2;
    mat4 pinsC0;
    mat4 pinsC1;
    mat4 pinsC2;
    mat4 chromaX;
    mat4 chromaY;
    mat4 chromaM;
    mat4 eqA0;
    mat4 eqA1;
    mat4 frame;
    mat4 masksA0;
    mat4 masksA1;
    mat4 masksB0;
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
    float denoiseFar;    // How much the color is also taken from further out, 0..1.
    float lensOn;     // Lens corrections (photone/lens.py, tables): 1 if any is anything.
    float lensShape;  // The stored picture's width over its height.
    mat4 lensGreen;   // Sixteen numbers each, from the picture's middle (the first) to its corner:
    mat4 lensRed;     // how many times further out the stored picture is read, for green, red
    mat4 lensBlue;    // and blue (distortion, chromatic aberration),
    mat4 lensLight;   // and how many times lighter a pixel is made (vignetting).
    float defringe;   // Fringes of color at edges taken off (`defringed`): how much, 0 to 1.
    float detailKept; // 0: sharpening and noise reduction are done here; 1: the picture read has them
                      // done already (PhotoView's `detailed`); 2: this draws that picture.
};
void main() {
    // Which part of the stored picture this corner of the item shows: the photo's frame
    // (its turns, its straightening, its crop), worked out by edit.frame.
    qt_TexCoord0 = (frame * vec4(qt_MultiTexCoord0, 0.0, 1.0)).xy;
    place = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
