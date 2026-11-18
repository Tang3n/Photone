import QtQuick
import "."

// How many pixels of the picture, as displayed, are how bright: red, green and blue laid over
// each other, dark on the left. A corner lights up when pixels sit at that end (black on the
// left, white on the right), which is where detail is lost.
Rectangle {
    id: root
    readonly property var counts: session.bars
    width: 244; height: 112; radius: 8
    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.88)
    border { width: 1; color: Theme.line }
    Accessible.role: Accessible.Graphic; Accessible.name: "Histogram"
    // Drawn only while on show: a graph nobody sees must not cost a frame at every count.
    function paint() { if (visible) plot.requestPaint() }
    onVisibleChanged: paint()
    onCountsChanged: paint()
    Canvas {
        id: plot
        anchors { fill: parent; margins: 8; topMargin: 14 }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.counts.r) return
            ctx.globalCompositeOperation = "lighter"   // where all three overlap it reads gray
            for (const [name, color] of [["r", Theme.red], ["g", Theme.green], ["b", Theme.blue]]) {
                const bars = root.counts[name]
                ctx.fillStyle = color
                ctx.beginPath()
                ctx.moveTo(0, height)
                for (let i = 0; i < 256; i++) ctx.lineTo(i / 255 * width, height - bars[i] / 255 * height)
                ctx.lineTo(width, height)
                ctx.fill()
            }
        }
    }
    component Corner: Rectangle {
        property real share
        property string what
        readonly property bool lit: share > 0.0005   // more than a pixel in two thousand
        objectName: "clip:" + what
        y: 5; width: 6; height: 6; radius: 3
        color: lit ? Theme.mark : Theme.faint
        Accessible.name: what + (lit ? ": pixels are cut off" : ": nothing cut off")
    }
    Corner { x: 8; share: root.counts.under || 0; what: "black" }
    Corner { x: parent.width - 14; share: root.counts.over || 0; what: "white" }
}
