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
    float saturation;
    float vibrance;
    float chromaOn;
    float eqCount;
    float showMask;
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
};
void main() {
    // Which part of the stored picture this corner of the item shows: the photo's frame
    // (its turns, its straightening, its crop), worked out by edit.frame.
    qt_TexCoord0 = (frame * vec4(qt_MultiTexCoord0, 0.0, 1.0)).xy;
    place = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
