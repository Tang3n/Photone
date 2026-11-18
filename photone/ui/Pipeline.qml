import QtQuick
import "."

// The pipeline shader on a rectangle: the photo itself, and the small copies the scopes count.
// One property per uniform of pipeline.frag, by exactly that name.
ShaderEffect {
    property var source                // the first picture (an Image)
    property var sharp: source         // the full-size one, once it is there
    property var painted: source       // the photo's painted masks (PhotoView's `painted`); any picture where there are none
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
    property var edit: session.uniforms
    property real gain: edit.gain
    property real mid: edit.mid
    property real contrast: edit.contrast
    property real brightness: edit.brightness
    property real highlights: edit.highlights
    property real shadows: edit.shadows
    property real midtones: edit.midtones
    property real whites: edit.whites
    property real blacks: edit.blacks
    property real curveC: edit.curveC
    property real curveS: edit.curveS
    property real curveK: edit.curveK
    property real hdrLift: edit.hdrLift
    property real hdrFit: 1
    property real stripes: 0
    property real curveOn: edit.curveOn
    property real pinCount: edit.pinCount
    property real reach: 0
    property real look: edit.look
    property real saturation: edit.saturation
    property real vibrance: edit.vibrance
    property real chromaOn: edit.chromaOn
    property real eqCount: edit.eqCount
    property real showMask: 0
    property vector4d wbGain: edit.wbGain
    property matrix4x4 toCam: edit.toCam
    property matrix4x4 fromCam: edit.fromCam
    property matrix4x4 curveX: edit.curveX
    property matrix4x4 curveY: edit.curveY
    property matrix4x4 curveM: edit.curveM
    property matrix4x4 pinsA0: edit.pinsA0
    property matrix4x4 pinsA1: edit.pinsA1
    property matrix4x4 pinsA2: edit.pinsA2
    property matrix4x4 pinsB0: edit.pinsB0
    property matrix4x4 pinsB1: edit.pinsB1
    property matrix4x4 pinsB2: edit.pinsB2
    property matrix4x4 pinsC0: edit.pinsC0
    property matrix4x4 pinsC1: edit.pinsC1
    property matrix4x4 pinsC2: edit.pinsC2
    property matrix4x4 chromaX: edit.chromaX
    property matrix4x4 chromaY: edit.chromaY
    property matrix4x4 chromaM: edit.chromaM
    property matrix4x4 eqA0: edit.eqA0
    property matrix4x4 eqA1: edit.eqA1
    property matrix4x4 frame: edit.frame
    property matrix4x4 masksA0: edit.masksA0
    property matrix4x4 masksA1: edit.masksA1
    property matrix4x4 masksB0: edit.masksB0
    property matrix4x4 masksB1: edit.masksB1
    property real curve2On: edit.curve2On
    property real chroma2On: edit.chroma2On
    property real eq2Count: edit.eq2Count
    property matrix4x4 curve2X: edit.curve2X
    property matrix4x4 curve2Y: edit.curve2Y
    property matrix4x4 curve2M: edit.curve2M
    property matrix4x4 chroma2X: edit.chroma2X
    property matrix4x4 chroma2Y: edit.chroma2Y
    property matrix4x4 chroma2M: edit.chroma2M
    property matrix4x4 eq2A0: edit.eq2A0
    property matrix4x4 eq2A1: edit.eq2A1
    fragmentShader: pipelineShader
    vertexShader: pipelineVertex
}
