import QtQuick
import "."

// What the graphs show, counted on the GPU at every frame (tally.vert): small renders of the
// pipeline (the picture as displayed, its lightness before the tone curve, its colors), and
// for each a row of 256 bins that every pixel of the render is added to. A graph (Bars.qml)
// draws itself from a row. Nothing comes back to the processor, so a slider that moves the
// photo moves its graphs in the same frame. (They were counted by numpy from a render read
// back, 25 times a second, and drawn on a Canvas: the owner, dragging a mask, saw 50 frames
// a second.) Scopes.qml still counts what nothing draws, once a change is over.
// Only what a graph that is on show and in sight looks at is rendered and counted (`look`).
Item {
    id: counts
    property var source            // the photo's first picture (an Image)
    property var painted           // its painted masks' picture (PhotoView.painted)
    property var lut: null         // its LUT's picture (PhotoView.lut), or none
    property Item colors           // the wheel's colors (Wheel.qml, `numbers`): the lightness strip counts those
    property int mask: 0           // the mask being worked on: only what it reaches is counted
    property Flickable port        // what the graphs scroll in: one scrolled out of it is not looked at
    visible: false
    // The edit as the shader's numbers, taken in once for all the renders, and only while any is looked at.
    readonly property var numbers: shownLooks + lightLooks + spreadLooks > 0 ? session.inFrame : null
    // The rows, and how many graphs look at each now.
    property int shownLooks: 0
    property int lightLooks: 0
    property int spreadLooks: 0
    property int stripLooks: 0
    function look(row, by) { counts[row + "Looks"] += by }
    function inSight(item) {
        if (!port) return true
        const top = (port.contentY, port.contentHeight, item.mapToItem(port, 0, 0).y)
        return top < port.height + 60 && top + item.height > -60
    }
    readonly property Item shown: shownRow
    readonly property Item light: lightRow
    readonly property Item spread: spreadRow
    readonly property Item strip: stripRow

    // A render follows the edit only while its row is looked at.
    component Render: Pipeline {
        id: render
        property bool looked: false
        width: 256; height: 256; visible: false
        source: counts.source; painted: counts.painted || counts.source; lutPicture: counts.lut
        peak: 1; hdrLift: 0; linearOut: 0; clipping: 0
        follows: looked; edit: counts.numbers
        layer.enabled: true; layer.smooth: false; layer.textureSize: Qt.size(256, 256)
    }
    Render { id: picture; scope: 0; looked: counts.shownLooks > 0 }
    Render { id: lightness; scope: 1; looked: counts.lightLooks > 0 }
    Render {   // (also what says which pixels a mask reaches, for the two above)
        id: lab; scope: 8; showMask: counts.mask; layer.format: ShaderEffectSource.RGBA16F
        looked: counts.spreadLooks > 0 || (counts.mask > 0 && counts.shownLooks + counts.lightLooks > 0)
    }
    component Tally: ShaderEffect {
        property var values
        property var inside: counts.mask > 0 ? lab : values
        property real masked: counts.mask > 0 ? 1 : 0
        property real count: 128   // (the most a mesh holds: tally.vert)
        property real fine: 1
        property point shift: Qt.point(0, 0)
        property real what: 0
        property vector4d into: Qt.vector4d(1, 0, 0, 0)
        anchors.fill: parent
        mesh: GridMesh { resolution: Qt.size(2 * count - 1, 2 * count - 1) }
        vertexShader: tallyVertex
        fragmentShader: tallyShader
    }
    // (Floats of 32 bits: of 16, a bin stops counting at 2048.)
    component Bins: Item {
        width: 256; height: 1
        layer.enabled: true; layer.smooth: false; layer.format: ShaderEffectSource.RGBA32F; layer.textureSize: Qt.size(256, 1)
    }
    Bins {   // red, green and blue of the picture as displayed
        id: shownRow
        Repeater {   // (each color four times over: every pixel of the 256 a side)
            model: 12
            Tally {
                required property int index
                values: picture; fine: 2; shift: Qt.point(index % 2, (index >> 1) % 2); what: index >> 2
                into: Qt.vector4d(what === 0 ? 1 : 0, what === 1 ? 1 : 0, what === 2 ? 1 : 0, 0)
            }
        }
    }
    Bins {   // its lightness before the tone curve
        id: lightRow
        Repeater { model: 4; Tally { required property int index; values: lightness; fine: 2; shift: Qt.point(index % 2, index >> 1) } }
    }
    Bins {   // how vivid (red) and of which hue (green) its colors are before the pins
        id: spreadRow
        Tally { values: lab; what: 3; fine: 2 }
        Tally { values: lab; what: 4; fine: 2; into: Qt.vector4d(0, 1, 0, 0) }
    }
    Bins {   // how light the wheel's colors are
        id: stripRow
        Tally { values: counts.colors; inside: counts.colors; what: 5; count: 127 }
    }
}
