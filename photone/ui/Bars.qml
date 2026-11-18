import QtQuick
import "."

// A graph of counts, drawn by the GPU from what it counted (Counts.qml: `tally`), smoothed,
// at every frame the photo changes: `kind` says of what. Filled in `color`, from its foot up;
// "rgb" is red, green and blue over each other.
ShaderEffect {
    id: bars
    property Item tally
    property string kind: "light"
    property color color: Theme.faint   // (it was `raised`: the owner found that "very hard to see")
    readonly property var how: ({
        rgb:    { row: "shown",  pick: Qt.vector4d(1, 0, 0, 0), soft: 1.6, first: 1, last: 254, ends: 1, wrap: 0, centered: 0 },
        light:  { row: "light",  pick: Qt.vector4d(1, 0, 0, 0), soft: 2.0, first: 1, last: 254, ends: 1, wrap: 0, centered: 0 },
        // (The grays, at the foot, are left out: they would dwarf the rest.)
        chroma: { row: "spread", pick: Qt.vector4d(1, 0, 0, 0), soft: 2.5, first: 4, last: 255, ends: 0, wrap: 0, centered: 0 },
        hue:    { row: "spread", pick: Qt.vector4d(0, 1, 0, 0), soft: 2.5, first: 0, last: 255, ends: 0, wrap: 1, centered: 1 },
        strip:  { row: "strip",  pick: Qt.vector4d(1, 0, 0, 0), soft: 2.5, first: 0, last: 255, ends: 0, wrap: 0, centered: 1 }
    })[kind]
    // Counted only while this is on show and in sight.
    readonly property bool looked: visible && tally !== null && tally.inSight(bars)
    onLookedChanged: tally.look(how.row, looked ? 1 : -1)
    Component.onDestruction: if (looked) tally.look(how.row, -1)
    property var counts: tally ? tally[how.row] : null
    property real linearOut: session.linearSurface ? 1 : 0
    property real soft: how.soft
    property real first: how.first
    property real last: how.last
    property real ends: how.ends
    property real wrap: how.wrap
    property real centered: how.centered
    property real three: kind === "rgb" ? 1 : 0
    property vector4d pick: how.pick
    property color red: Theme.red
    property color green: Theme.green
    property color blue: Theme.blue
    vertexShader: barsVertex
    fragmentShader: barsShader
}
