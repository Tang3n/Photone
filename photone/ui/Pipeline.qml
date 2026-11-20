import QtQuick
import "."

// The pipeline shader on a rectangle: the photo itself, and the small copies the scopes count.
// One property per uniform of pipeline.frag, by exactly that name.
ShaderEffect {
    property var source                // the first picture (an Image)
    property var sharp: source         // the full-size one, once it is there
    property var painted: source       // the photo's painted masks (PhotoView's `painted`); any picture where there are none
    // The picture of the photo's LUTs (PhotoView's `lut`), where it has any and it is there;
    // without it none is laid on, whatever the edit says.
    property var lutPicture: null
    property var lut: lutPicture || source
    property real useSharp: 0
    property real crisp: 0
    property vector4d cropBox: Qt.vector4d(0, 0, 1, 1)
    property real cropDim: 0
    property real onlyMask: 0
    property real scope: 0
    property real clipping: 0
    property real linearOut: session.linearSurface ? 1 : 0
    property real peak: session.hdr ? session.peak : 1
    // The edit, as numbers (photone/edit.py works them out).
    // Whether it takes the edit's new numbers in: not while it is out of sight, since each
    // change of a slider costs a render some eighty values taken in, drawn or not. (One that
    // is drawn while not `visible`, into a layer, says so itself.)
    property bool follows: visible
    property var edit: follows ? session.uniforms : null
    property var used: session.uniforms   // the numbers it draws with: `edit` as last taken in
    function takeIn() { if (follows && edit) used = edit }
    onEditChanged: takeIn()
    onFollowsChanged: Qt.callLater(takeIn)   // (whichever of the two comes first; later, since at the start `edit` may not be there to read yet)
    Component.onCompleted: used = edit || session.uniforms   // (an assignment: from here on only `takeIn` sets it)
    property real gain: used.gain
    property real mid: used.mid
    property real contrast: used.contrast
    property real brightness: used.brightness
    property real highlights: used.highlights
    property real shadows: used.shadows
    property real midtones: used.midtones
    property real whites: used.whites
    property real blacks: used.blacks
    property real curveC: used.curveC
    property real curveS: used.curveS
    property real curveK: used.curveK
    property real hdrLift: used.hdrLift
    property real hdrFit: 1
    property real stripes: 0
    property real curveOn: used.curveOn
    property real pinCount: used.pinCount
    property real reach: 0
    property real look: used.look
    property real mono: used.mono
    property real saturation: used.saturation
    property real vibrance: used.vibrance
    property real chromaOn: used.chromaOn
    property real eqCount: used.eqCount
    property real showMask: 0
    property real maskTint: 1
    property vector4d wbGain: used.wbGain
    property matrix4x4 toCam: used.toCam
    property matrix4x4 fromCam: used.fromCam
    property matrix4x4 curveX: used.curveX
    property matrix4x4 curveY: used.curveY
    property matrix4x4 curveM: used.curveM
    property matrix4x4 pinsA0: used.pinsA0
    property matrix4x4 pinsA1: used.pinsA1
    property matrix4x4 pinsA2: used.pinsA2
    property matrix4x4 pinsB0: used.pinsB0
    property matrix4x4 pinsB1: used.pinsB1
    property matrix4x4 pinsB2: used.pinsB2
    property matrix4x4 pinsC0: used.pinsC0
    property matrix4x4 pinsC1: used.pinsC1
    property matrix4x4 pinsC2: used.pinsC2
    property matrix4x4 chromaX: used.chromaX
    property matrix4x4 chromaY: used.chromaY
    property matrix4x4 chromaM: used.chromaM
    property matrix4x4 eqA0: used.eqA0
    property matrix4x4 eqA1: used.eqA1
    property matrix4x4 frame: used.frame
    property matrix4x4 masksA0: used.masksA0
    property matrix4x4 masksA1: used.masksA1
    property matrix4x4 masksB0: used.masksB0
    property matrix4x4 masksB1: used.masksB1
    property real curve2On: used.curve2On
    property real chroma2On: used.chroma2On
    property real eq2Count: used.eq2Count
    property matrix4x4 curve2X: used.curve2X
    property matrix4x4 curve2Y: used.curve2Y
    property matrix4x4 curve2M: used.curve2M
    property matrix4x4 chroma2X: used.chroma2X
    property matrix4x4 chroma2Y: used.chroma2Y
    property matrix4x4 chroma2M: used.chroma2M
    property matrix4x4 eq2A0: used.eq2A0
    property matrix4x4 eq2A1: used.eq2A1
    property real grain: used.grain
    property real grainWide: used.grainWide
    property real grainHigh: used.grainHigh
    property real grainRough: used.grainRough
    property real grainColor: used.grainColor
    property matrix4x4 grainX: used.grainX
    property matrix4x4 grainY: used.grainY
    property matrix4x4 grainM: used.grainM
    property real lutCount: lutPicture ? used.lutCount : 0
    property matrix4x4 lutsA: used.lutsA
    property matrix4x4 lutsB: used.lutsB
    property matrix4x4 lutsC: used.lutsC
    property matrix4x4 lutsD: used.lutsD
    property real detailX: used.detailX
    property real detailY: used.detailY
    property real sharpen: used.sharpen
    property real sharpenRadius: used.sharpenRadius
    property real sharpenMask: used.sharpenMask
    property real denoise: used.denoise
    property real denoiseColor: used.denoiseColor
    property real denoiseFar: used.denoiseFar
    property real lensOn: used.lensOn
    property real lensShape: used.lensShape
    property matrix4x4 lensGreen: used.lensGreen
    property matrix4x4 lensRed: used.lensRed
    property matrix4x4 lensBlue: used.lensBlue
    property matrix4x4 lensLight: used.lensLight
    property real defringe: used.defringe
    fragmentShader: pipelineShader
    vertexShader: pipelineVertex
}
