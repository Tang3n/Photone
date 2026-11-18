import QtQuick
import "."

// A curve of the edit (`key`: the tone curve, the chroma curve): what goes in on the left to
// what comes out, upward, through points that are dragged. Behind it (`bars`), how much of the
// picture has how much of what goes in. Press on the line to make a point, drag it,
// double-click it to take it away; the two end points can only be put back, not removed.
Item {
    id: root
    signal done()                              // a gesture is over
    property string key: "curve"               // the setting in the photo's edit
    property var line: []                      // the curve as heights, left to right (edit.LINE of them)
    property var bars: []                      // what lies behind it, heights 0..255
    property string low: "shadows"             // what the left end is called,
    property string high: "highlights"         // and the right
    // For a mask (`mask`: its number): its own curve, on top of the whole image's; straight
    // until it is changed (session.setMaskWhole).
    property bool local: false   // a mask's card: named apart from the whole image's editor
    property int mask: 0
    readonly property var points: mask > 0 ? (session.masks, session.localWhole(mask, key)) : session[key]
    function put(list) { if (mask > 0) session.setMaskWhole(mask, key, list); else session.setEdit(key, list) }
    // Drawn only while on show: a graph nobody sees must not cost a frame at every count.
    function paint() { if (visible) plot.requestPaint() }
    onVisibleChanged: paint()
    onLineChanged: paint()
    onBarsChanged: paint()
    property int held: -1                      // the point being dragged
    property int hot: -1                       // the point under the pointer
    property var base: null                    // the points as they were when the drag began
    readonly property real inset: 8
    readonly property real w: plot.width - 2 * inset
    readonly property real h: plot.height - 2 * inset
    function px(x) { return inset + x * w }
    function py(y) { return inset + (1 - y) * h }
    function held01(v, low, high) { return Math.max(low, Math.min(high, v)) }
    function near(x, y) {
        for (let i = 0; i < points.length; i++)
            if (Math.abs(px(points[i][0]) - x) < 10 && Math.abs(py(points[i][1]) - y) < 10) return i
        return -1
    }
    function lineAt(x) {   // the curve's height there, from the line as drawn
        const last = line.length - 1, f = held01(x, 0, 1) * last, i = Math.min(last - 1, Math.floor(f))
        return line[i] + (line[i + 1] - line[i]) * (f - i)
    }
    readonly property int shown: held >= 0 ? held : hot
    onShownChanged: paint()
    onPointsChanged: paint()

    Canvas {
        id: plot
        objectName: (root.local ? "local-" : "") + root.key + "-plot"
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; bottomMargin: 18 }
        onPaint: {
            const ctx = getContext("2d"), light = root.bars, line = root.line
            ctx.reset()
            if (line.length < 2) return
            if (light.length) {
                ctx.fillStyle = Theme.raised
                ctx.beginPath()
                ctx.moveTo(root.px(0), root.py(0))
                for (let i = 0; i < light.length; i++) ctx.lineTo(root.px(i / (light.length - 1)), root.py(light[i] / 255 * 0.92))
                ctx.lineTo(root.px(1), root.py(0))
                ctx.fill()
            }
            ctx.lineWidth = 1
            ctx.strokeStyle = Theme.line
            ctx.beginPath()
            for (let q = 0; q <= 4; q++) {
                ctx.moveTo(Math.round(root.px(q / 4)) + 0.5, root.py(1)); ctx.lineTo(Math.round(root.px(q / 4)) + 0.5, root.py(0))
                ctx.moveTo(root.px(0), Math.round(root.py(q / 4)) + 0.5); ctx.lineTo(root.px(1), Math.round(root.py(q / 4)) + 0.5)
            }
            ctx.stroke()
            ctx.strokeStyle = Theme.faint   // the straight line: no change
            ctx.setLineDash([2, 4])
            ctx.beginPath(); ctx.moveTo(root.px(0), root.py(0)); ctx.lineTo(root.px(1), root.py(1)); ctx.stroke()
            ctx.setLineDash([])
            ctx.strokeStyle = Theme.text
            ctx.lineWidth = 1.6
            ctx.beginPath()
            // (Through the points themselves too: a peak between two heights is not cut off.)
            const run = Array.from(line, (y, i) => [i / (line.length - 1), y]).concat(root.points.map(p => [p[0], p[1]])).sort((a, b) => a[0] - b[0])
            for (let i = 0; i < run.length; i++) ctx[i ? "lineTo" : "moveTo"](root.px(run[i][0]), root.py(run[i][1]))
            ctx.stroke()
            for (let i = 0; i < root.points.length; i++) {
                const end = i === 0 || i === root.points.length - 1
                ctx.beginPath()
                ctx.arc(root.px(root.points[i][0]), root.py(root.points[i][1]), i === root.shown ? 5.5 : 4, 0, 2 * Math.PI)
                ctx.fillStyle = end && i !== root.shown ? Theme.dim : Theme.text
                ctx.fill()
                ctx.lineWidth = 1.5
                ctx.strokeStyle = Theme.panel
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
                const list = root.points.map(p => [p[0], p[1]])
                let at = root.near(mouse.x, mouse.y)
                if (at < 0 && list.length < 16) {
                    // A new point, on the line where it runs now: the press itself changes nothing.
                    const x = (mouse.x - root.inset) / root.w, next = list.findIndex(p => p[0] > x)
                    if (next > 0 && x - list[next - 1][0] >= 0.03 && list[next][0] - x >= 0.03) {
                        list.splice(next, 0, [x, root.lineAt(x)])
                        at = next
                    }
                }
                root.held = at
                root.base = list
                from = Qt.point(mouse.x, mouse.y)
                pace = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1
            }
            onPositionChanged: (mouse) => {
                if (!pressed) { root.hot = root.near(mouse.x, mouse.y); return }
                if (root.held < 0) return
                const fine = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1, i = root.held
                if (fine !== pace) { pace = fine; from = Qt.point(mouse.x, mouse.y); root.base = root.points.map(p => [p[0], p[1]]) }
                const list = root.base.map(p => [p[0], p[1]])
                const low = i > 0 ? list[i - 1][0] + 0.02 : 0, high = i < list.length - 1 ? list[i + 1][0] - 0.02 : 1
                list[i] = [root.held01(list[i][0] + (mouse.x - from.x) / root.w * fine, low, high),
                           root.held01(list[i][1] - (mouse.y - from.y) / root.h * fine, 0, 1)]
                root.put(list)
            }
            onReleased: (mouse) => {
                root.held = -1
                root.hot = root.near(mouse.x, mouse.y)
                session.commitEdit()
                root.done()
            }
            onDoubleClicked: (mouse) => {
                const at = root.near(mouse.x, mouse.y), list = root.points.map(p => [p[0], p[1]])
                root.held = -1
                if (at < 0) return
                if (at === 0) list[0] = [0, 0]
                else if (at === list.length - 1) list[at] = [1, 1]
                else list.splice(at, 1)
                root.put(list)
                session.commitEdit()
            }
        }
    }
    Label { anchors { left: parent.left; leftMargin: root.inset; bottom: parent.bottom }  text: root.low; font.pixelSize: Theme.smallSize; color: Theme.faint }
    Label { anchors { right: parent.right; rightMargin: root.inset; bottom: parent.bottom } text: root.high; font.pixelSize: Theme.smallSize; color: Theme.faint }
    Label {
        objectName: (root.local ? "local-" : "") + root.key + "-readout"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        visible: root.shown >= 0 && root.shown < root.points.length
        font.pixelSize: Theme.smallSize; font.features: { "tnum": 1 }; color: Theme.text
        text: visible ? Math.round(root.points[root.shown][0] * 100) + " %  →  " + Math.round(root.points[root.shown][1] * 100) + " %" : ""
    }
}
