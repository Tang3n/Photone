import QtQuick
import "."

// The color EQ: more or less color, hue by hue. Across: the hues, as the strip underneath
// shows them. Upward: how much of its chroma a color of that hue keeps, 100 % in the middle.
// Behind the line, how much of the photo has which hue. Press on the line to make a point, drag
// it up or down (and along), scroll on it to make it reach more or fewer hues, double-click it
// to take it away. Up to eight.
Item {
    id: root
    signal done()                              // a gesture is over
    // For a mask (`mask`: its number): its own EQ, or until it has one the whole image's.
    property bool local: false   // a mask's card: named apart from the whole image's editor
    property int mask: 0
    readonly property var points: mask > 0 ? (session.masks, session.localWhole(mask, "eq")) : session.eq
    readonly property var line: mask > 0 ? (session.masks, session.localLine(mask, "eq")) : session.eqLine   // the gain at every other degree, 0..2
    function put(list) { if (mask > 0) session.setMaskWhole(mask, "eq", list); else session.setEdit("eq", list) }
    readonly property var bars: (session.bars.hue || [])   // heights 0..255
    readonly property var hues: session.hues             // the strip's colors, hue 0 to 360
    property int held: -1                      // the point being dragged
    property int hot: -1                       // the point under the pointer
    property var base: null                    // the points as they were when the drag began
    readonly property real inset: 8
    readonly property real w: plot.width - 2 * inset
    readonly property real h: plot.height - 2 * inset
    readonly property int shown: held >= 0 ? held : hot
    function px(hue) { return inset + hue / 360 * w }
    function py(gain) { return inset + (1 - gain / 200) * h }
    function within(v, low, high) { return Math.max(low, Math.min(high, v)) }
    function near(x, y) {
        for (let i = points.length - 1; i >= 0; i--)
            if (Math.abs(px(points[i].hue) - x) < 10 && Math.abs(py(points[i].gain) - y) < 10) return i
        return -1
    }
    function copies() { return points.map(point => Object.assign({}, point)) }
    // Drawn only while on show: a graph nobody sees must not cost a frame at every count.
    function paint() { if (visible) plot.requestPaint() }
    onVisibleChanged: paint()
    onPointsChanged: paint()
    onLineChanged: paint()
    onBarsChanged: paint()
    onShownChanged: paint()
    onHuesChanged: strip.requestPaint()
    Timer { id: settled; interval: 500; onTriggered: session.commitEdit() }   // after the last notch of a wheel

    Canvas {
        id: plot
        objectName: (root.local ? "local-" : "") + "eq-plot"
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; bottomMargin: 34 }
        onPaint: {
            const ctx = getContext("2d"), bars = root.bars, line = root.line
            ctx.reset()
            if (bars.length) {
                ctx.fillStyle = Theme.raised
                ctx.beginPath()
                ctx.moveTo(root.px(0), root.py(0))
                for (let i = 0; i < bars.length; i++) ctx.lineTo(root.px((i + 0.5) / bars.length * 360), root.py(bars[i] / 255 * 184))
                ctx.lineTo(root.px(360), root.py(0))
                ctx.fill()
            }
            ctx.lineWidth = 1
            ctx.strokeStyle = Theme.line
            ctx.beginPath()
            for (let q = 0; q <= 4; q++) { ctx.moveTo(root.px(0), Math.round(root.py(q * 50)) + 0.5); ctx.lineTo(root.px(360), Math.round(root.py(q * 50)) + 0.5) }
            for (let q = 0; q <= 6; q++) { ctx.moveTo(Math.round(root.px(q * 60)) + 0.5, root.py(0)); ctx.lineTo(Math.round(root.px(q * 60)) + 0.5, root.py(200)) }
            ctx.stroke()
            ctx.strokeStyle = Theme.text
            ctx.lineWidth = 1.6
            ctx.beginPath()
            for (let i = 0; i < line.length; i++) ctx[i ? "lineTo" : "moveTo"](root.px(i * 360 / (line.length - 1)), root.py(line[i] * 100))
            ctx.stroke()
            for (let i = 0; i < root.points.length; i++) {
                const point = root.points[i]
                ctx.beginPath()
                ctx.arc(root.px(point.hue), root.py(point.gain), i === root.shown ? 6.5 : 5, 0, 2 * Math.PI)
                ctx.fillStyle = root.hues.length ? root.hues[Math.round(point.hue / 360 * (root.hues.length - 1))] : Theme.text
                ctx.fill()
                ctx.lineWidth = 1.5
                ctx.strokeStyle = Theme.text
                ctx.stroke()
            }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            property point from
            property real pace: 1   // (Shift on the way: on from where the point is, at the other pace)
            onExited: root.hot = -1
            onPressed: (mouse) => {
                const list = root.copies()
                let at = root.near(mouse.x, mouse.y)
                if (at < 0 && list.length < 8) {
                    // A new point at that hue, changing nothing yet: it is a point once dragged.
                    list.push({ hue: root.within((mouse.x - root.inset) / root.w * 360, 0, 359.9), gain: 100, width: 40 })
                    at = list.length - 1
                }
                root.held = at
                root.base = list
                from = Qt.point(mouse.x, mouse.y)
                pace = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1
            }
            onPositionChanged: (mouse) => {
                if (!pressed) { root.hot = root.near(mouse.x, mouse.y); return }
                if (root.held < 0) return
                const fine = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1
                if (fine !== pace) { pace = fine; from = Qt.point(mouse.x, mouse.y); if (root.held < root.points.length) root.base = root.copies() }
                const list = root.base.map(point => Object.assign({}, point))
                const point = list[root.held]
                point.hue = (point.hue + (mouse.x - from.x) / root.w * 360 * fine + 360) % 360
                point.gain = root.within(point.gain - (mouse.y - from.y) / root.h * 200 * fine, 0, 200)
                root.put(list)
            }
            onReleased: (mouse) => {
                root.held = -1
                root.hot = root.near(mouse.x, mouse.y)
                session.commitEdit()
                root.done()
            }
            onDoubleClicked: (mouse) => {
                const at = root.near(mouse.x, mouse.y), list = root.copies()
                root.held = -1
                if (at < 0) return
                list.splice(at, 1)
                root.put(list)
                session.commitEdit()
            }
            onWheel: (wheel) => {
                const at = root.near(wheel.x, wheel.y), turned = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y * 2
                if (at < 0) { wheel.accepted = false; return }
                const list = root.copies()
                list[at].width = root.within(list[at].width * Math.pow(1.001, turned), 8, 120)
                root.put(list)
                settled.restart()
            }
        }
    }
    // The hues the line runs over: a band as the Tone Wheel's lightness band is (low, with
    // rounded ends and a thin outline; the owner: "the same style as the one in tone wheel").
    Canvas {
        id: strip
        objectName: (root.local ? "local-" : "") + "eq-strip"
        x: root.inset; y: plot.height + 4; width: root.w; height: 6
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.hues.length) return
            const run = ctx.createLinearGradient(0, 0, width, 0)
            for (let i = 0; i < root.hues.length; i++) run.addColorStop(i / (root.hues.length - 1), root.hues[i])
            ctx.fillStyle = run
            ctx.beginPath()
            ctx.roundedRect(0, 0, width, height, height / 2, height / 2)
            ctx.fill()
            ctx.lineWidth = 1; ctx.strokeStyle = Theme.line
            ctx.stroke()
        }
    }
    // (What to do, not what the graph means: it said "less color below the middle, more
    // above", which the owner found "terrible".)
    Label {
        anchors { left: parent.left; leftMargin: root.inset; right: parent.right; rightMargin: 120; bottom: parent.bottom }
        elide: Text.ElideRight; font.pixelSize: Theme.smallSize; color: Theme.faint
        text: "Drag the line at a color: up strengthens it, down mutes it"
    }
    Label {
        objectName: (root.local ? "local-" : "") + "eq-readout"
        anchors { right: parent.right; rightMargin: root.inset; bottom: parent.bottom }
        visible: root.shown >= 0 && root.shown < root.points.length
        font.pixelSize: Theme.smallSize; font.features: { "tnum": 1 }; color: Theme.text
        text: visible ? Math.round(root.points[root.shown].hue) + "°   " + Math.round(root.points[root.shown].gain) + " %   ±" + Math.round(root.points[root.shown].width) + "°" : ""
    }
}
