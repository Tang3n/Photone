import QtQuick
import "."

// How much of the photo is how light, in a box, over a band from black to white. What lies outside the
// wheel's working range is dimmed; a tick marks the lightness under the pointer on the photo.
// While a pin is being worked on (`held`) the strip has a handle: to the right of the middle
// the pin makes its colors lighter, to the left darker, by `shift` (the strip's whole width is
// one whole step from black to white).
Item {
    id: root
    property real probe: -1          // the lightness under the pointer (0..1), or none
    readonly property var range: session.range
    property var bars: []            // how much of the photo is how light, dark first: heights 0..255
    property bool held: false        // a pin is being worked on
    property real shift: 0           // how much lighter (or, below zero, darker) it makes its colors
    signal moved(real shift)
    signal released()
    signal reset()
    height: 44
    Accessible.role: Accessible.Graphic; Accessible.name: "Lightness of the photo"
    onBarsChanged: plot.requestPaint()
    // One box: how much of the photo is how light, standing on a band that runs from black to
    // white, so that each bar stands over the gray it counts. Its name and the pin's shift in
    // the corners, as on a card. (It was a row of bars with a separate strip under them that
    // had its name written on its black end; the owner: "a little awkward in design".)
    // (The band is a track of its own under the bars, with a gap and its own rounded ends:
    // flush under them it read as the foot of the graph; the owner "mistook the gradient bar
    // for part of the graph".)
    readonly property real band: 6   // the black-to-white band at the foot
    readonly property real gap: 5    // between the bars and the band
    Rectangle {
        id: box
        anchors.fill: parent; radius: 5; color: Theme.bg; border { width: 1; color: Theme.line }
    }
    Canvas {
        id: plot
        x: 6; y: 3; width: parent.width - 12; height: parent.height - root.band - root.gap - 8
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.bars.length) return
            ctx.fillStyle = Theme.faint
            ctx.beginPath()
            ctx.moveTo(0, height)
            // (A line through the middle of each count, not a step for each: as steps, a photo
            // with much of one gray showed square blocks; the owner: "random squares".)
            for (let i = 0; i < root.bars.length; i++)
                ctx.lineTo((i + 0.5) / root.bars.length * width, height - root.bars[i] / 255 * (height - 2))
            ctx.lineTo(width, height)
            ctx.fill()
        }
    }
    Rectangle {
        id: strip
        objectName: "lightness-strip"
        x: 6; y: parent.height - root.band - 5; width: parent.width - 12; height: root.band
        radius: root.band / 2; border { width: 1; color: Theme.line }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.black }
            GradientStop { position: 1; color: Theme.white }
        }
    }
    Label {
        x: 8; y: 4; text: "LIGHTNESS"; color: Theme.dim
        font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.9
    }
    // Outside the working range: dimmed, over the bars and the band alike.
    Rectangle { objectName: "range-below"; x: 1; y: 1; width: Math.max(0, root.range.low * parent.width - 1); height: parent.height - 2; color: Theme.bg; opacity: 0.8; topLeftRadius: 4; bottomLeftRadius: 4 }
    Rectangle { objectName: "range-above"; x: root.range.high * parent.width; y: 1; width: Math.max(0, parent.width - x - 1); height: parent.height - 2; color: Theme.bg; opacity: 0.8; topRightRadius: 4; bottomRightRadius: 4 }
    Rectangle {  // the middle: no change
        visible: root.held
        x: Math.round(parent.width / 2); y: parent.height - root.band - 8; width: 1; height: root.band + 6; color: Theme.dim
    }
    Item {   // the pin's lightness: a thumb on the band, as a slider has, and a line up from it
        objectName: "lightness-handle"
        visible: root.held
        x: (0.5 + root.shift) * parent.width - width / 2; y: parent.height - root.band - 8
        width: 12; height: 12
        Rectangle {
            anchors.centerIn: parent
            width: 12; height: 12; radius: 6; color: Theme.text; border { width: 2; color: Theme.bg }
        }
    }
    Label {
        objectName: "lightness-shift"
        visible: root.held
        anchors { right: parent.right; rightMargin: 8 } y: 4
        font.pixelSize: 10; font.features: { "tnum": 1 }; color: root.shift ? Theme.text : Theme.dim
        text: (root.shift >= 0 ? "+" : "−") + Math.abs(root.shift).toFixed(2)
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.held
        property real from
        property real start
        // As a slider: the handle moves from where it is (Shift: a tenth as far).
        property real pace: 1   // (Shift on the way: on from where it is, at the other pace)
        onPressed: (mouse) => { from = mouse.x; start = root.shift; pace = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1 }
        onPositionChanged: (mouse) => {
            const fine = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1
            if (fine !== pace) { pace = fine; from = mouse.x; start = root.shift }
            root.moved(Math.max(-0.5, Math.min(0.5, start + (mouse.x - from) / width * fine)))
        }
        onReleased: root.released()
        onDoubleClicked: root.reset()
    }
    Rectangle {
        objectName: "lightness-tick"
        visible: root.probe >= 0
        x: Math.round(root.probe * (parent.width - 1)); y: 1; width: 1; height: parent.height - 2; color: Theme.mark
    }
}
