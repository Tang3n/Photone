import QtQuick
import "."

// What the photo's masks change inside them, laid over a Pipeline: put inside it, this draws
// the picture once more for each mask that has an edit of its own (`layers`: the mask's
// number and the shader's numbers for the edit inside it, session.maskLayers), and the
// shader lets through as much of each as its mask weighs. So a mask can change whatever the
// whole image's settings can, with nothing of them doubled in the shader.
// ponytail: the two pictures are mixed as they are shown (after the tone curve), not in
// linear light, and each such mask costs one more pass over the photo. The upgrade is a
// second set of settings inside the shader, mixed before the curve.
Repeater {
    id: local
    property Item over        // the Pipeline these lie on (its parent, by rule)
    property var layers: []
    // As many pictures as there are such masks, kept from one change to the next and given
    // the new numbers: with the list itself for a model every change of a slider made them all
    // anew, which cost a millisecond a mask and left 200 kB behind each time (the owner:
    // "the memory usage is crazy there.. it keeps climbing up").
    model: over && over.scope === 0 && over.onlyMask === 0 && over.showMask <= 0 && over.reach === 0 ? layers.length : 0
    Pipeline {
        required property int index
        readonly property var mine: index < local.layers.length ? local.layers[index] : null   // (null: on its way out)
        visible: mine !== null
        anchors.fill: parent
        source: local.over.source; sharp: local.over.sharp; painted: local.over.painted; showMask: local.over.showMask; useSharp: local.over.useSharp; crisp: local.over.crisp
        peak: local.over.peak; linearOut: local.over.linearOut; clipping: local.over.clipping
        cropDim: local.over.cropDim; cropBox: local.over.cropBox
        edit: mine ? mine.numbers : local.over.edit
        hdrLift: Math.min(edit.hdrLift, local.over.hdrLift)   // (none where the picture under it has none)
        hdrFit: local.over.hdrFit; stripes: local.over.stripes
        onlyMask: mine ? mine.mask : 0
    }
}
