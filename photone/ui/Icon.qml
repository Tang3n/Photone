import QtQuick
import QtQuick.Shapes
import "."

// An icon: a few strokes along a path of 20 units a side (`path`, as SVG writes paths), drawn
// by the scene graph itself at whatever size it is shown, each line's edge worked out for the
// screen's own pixels. (As a small picture made from SVG text and scaled, the lines came out
// soft, and made at the very size, rough: the owner saw the first, the renders the second. And
// Qt's curve renderer drew nothing once the window's graphics had been made anew.)
//
// The shape is made anew whenever its color is another: a shape whose stroke color changed
// kept the color it was first drawn in (PySide 6.12; seen on a card's Reset, which stayed dim
// when it could be pressed, and on the filmstrip's Reject).
Item {
    id: icon
    property string path
    property color color: Theme.dim
    property real stroke: 1.7
    property real units: 20       // how many units the path is drawn in, a side
    property bool filled: false   // the path's inside in the color, and no line round it
    width: Theme.railIcon; height: Theme.railIcon
    Repeater {
        model: [String(icon.color)]
        Shape {
            required property string modelData
            anchors.fill: parent
            layer.enabled: true; layer.samples: 8   // each line's edge from eight samples a pixel
            // A half-clear color is drawn solid and the whole icon made that clear: drawn
            // half-clear, strokes that cross or meet showed darker where they lay on each
            // other (the owner, of a dimmed Reset: "separate segments that compound").
            opacity: icon.color.a
            ShapePath {
                strokeColor: icon.filled ? "transparent" : Qt.rgba(icon.color.r, icon.color.g, icon.color.b, 1)
                strokeWidth: icon.filled ? 0 : icon.stroke
                fillColor: icon.filled ? Qt.rgba(icon.color.r, icon.color.g, icon.color.b, 1) : "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(icon.width / icon.units, icon.height / icon.units)
                PathSvg { path: icon.path }
            }
        }
    }
}
