import QtQuick
import "."

// The color wheel: OKLab's a across and b upward, so hue is the angle and chroma the distance
// from the gray middle. On it, the photo's colors as dots (drawn by the GPU from the photo
// itself, at every frame: dots.vert), and a cross at the color under the pointer on the photo.
//
// The view is `span` (how much chroma the square is across) and `middle` (the a, b in its
// middle). All shows the whole wheel; Fit frames the dots.
//
// And the pins (session.edit.pins, photone/edit.py): a click on the wheel, or on the photo,
// marks a color; dragging that mark makes it a pin and moves the color. A pin is a white disc
// where the color goes, a dashed ring where it came from, a line between. With the pointer on
// a pin the mouse wheel sets its range (Shift: feather, Alt: variance); a double click or
// Delete removes it.
Rectangle {
    id: root
    property point hover: Qt.point(-1, -1)        // where the pointer is on the photo (0..1), or off it
    readonly property real rim: 0.32              // the chroma at which the disc ends
    readonly property real whole: 2 * rim * 1.1   // the span that shows all of it
    property real span: whole
    property point middle: Qt.point(0, 0)
    property bool framed: false                   // Fit has been applied to this photo's colors
    readonly property real zoom: whole / span
    readonly property bool all: Math.abs(span - whole) < 1e-9
    // [a, b, lightness] under the pointer on the photo; asked again whenever the colors are counted.
    // The photo's colors. Read once per count: the list is long, and every reading of it
    // from the session copies it.
    readonly property var cloud: session.dots   // what was counted of them: for Fit and the strip
    readonly property var probe: cloud && hover.x >= 0 ? session.colorAt(hover.x, hover.y) : []

    function px(a) { return width / 2 + (a - middle.x) / span * unit }
    function py(b) { return height / 2 - (b - middle.y) / span * unit }
    function held(v) { return Math.max(-rim, Math.min(rim, v)) }   // the middle stays on the disc
    function showAll() { still(); span = whole; middle = Qt.point(0, 0) }
    // The view may be wider than it is high (it spans its card): `span` is the chroma across
    // its height, and `unit` the pixels that is.
    readonly property real unit: height
    function fitted() {   // the view that frames the dots: [span, middle]
        const box = cloud.box
        if (!box || box.length < 4) return [whole, Qt.point(0, 0)]
        const wide = Math.max(whole / 12, Math.min(whole, Math.max(box[1] - box[0], box[3] - box[2]) * 1.2 + 0.03))
        return [wide, wide >= whole ? Qt.point(0, 0) : Qt.point((box[0] + box[1]) / 2, (box[2] + box[3]) / 2)]
    }
    function fit() { still(); const to = fitted(); span = to[0]; middle = to[1] }
    // The mouse wheel, Fit and All glide to their view, as the photo's zoom does: very
    // short, toward what was asked for last (the owner: "the same tween treatment the canvas
    // did"). Everything else (another photo, a drag) is at once and ends a glide.
    property var going: null   // the glide under way
    property real glide: 1
    NumberAnimation { id: zooming; target: root; property: "glide"; from: 0; to: 1; duration: 85; easing.type: Easing.OutCubic; onFinished: root.step(1, true) }
    function still() { zooming.stop(); going = null }
    function land() { if (zooming.running) zooming.complete() }   // (for the audits: there at once)
    function step(t, last) {
        const g = going
        if (!g) return
        const s = g.s0 * Math.pow(g.s1 / g.s0, t)
        // About a color that stays under the pointer, or from one middle to another.
        middle = g.about ? Qt.point(held(g.about[0] - g.off[0] * s), held(g.about[1] + g.off[1] * s))
                         : Qt.point(g.m0.x + (g.m1.x - g.m0.x) * t, g.m0.y + (g.m1.y - g.m0.y) * t)
        span = s
        if (last) going = null
    }
    onGlideChanged: if (zooming.running) step(glide, false)
    function glideTo(to) { zooming.stop(); going = { s0: span, s1: to[0], m0: middle, m1: to[1] }; zooming.start() }
    function glideFit() { glideTo(fitted()) }
    function glideAll() { glideTo([whole, Qt.point(0, 0)]) }
    // Zoom so that the color under (x, y) stays under it. (From the view it is going to, if
    // it is on its way: two notches are two steps.)
    function zoomAt(factor, x, y) {
        const aim = going ? going.s1 : span
        const next = Math.max(whole / 24, Math.min(whole, aim / factor))
        const off = [(x - width / 2) / unit, (y - height / 2) / unit]
        zooming.stop()
        going = { s0: span, s1: next, about: [middle.x + off[0] * span, middle.y - off[1] * span], off: off }
        zooming.start()
    }
    function panBy(dx, dy) { still(); middle = Qt.point(held(middle.x - dx / unit * span), held(middle.y + dy / unit * span)) }

    // ---- the pins --------------------------------------------------------------------------
    readonly property var pins: session.pins
    property bool yields: false        // the mouse wheel is not this one's for the moment (a scroll is passing over it)
    property int selected: -1          // the pin that is being worked on
    property var fresh: null           // a color just clicked ({ from: [a, b] }): a pin once it is dragged
    signal done()                      // a gesture is over
    // The mask whose pins are being worked on (1, 2, …; session.masks), or 0: those of the
    // whole image. Only these can be taken hold of; the others are small and faint.
    property int mask: 0
    function ours(pin) { return (pin.mask || 0) === mask }
    // And of those, the ones made for the tones the wheel is showing: a pin of the shadows is
    // small and faint while the wheel shows the highlights (the owner: "they all appear in all
    // tabs", "very confusing"). That is: the middle of the pin's span of lightness lies in the
    // working range, so Full shows them all. The pin being worked on is always at hand.
    readonly property var range: session.range
    // Which pins are at hand. All tones is the overview: every pin, whatever tones it was
    // made for. Highlights, Midtones and Shadows each have their own: a pin made in another
    // of them, or in All tones, is small and faint there. (Two rules before this one each
    // hid something: with every pin in every tab "they all appear in all tabs"; with All
    // tones showing only its own, a pin of another tab pulled the colors about in All tones
    // as a faint ring that could not be taken hold of: "something is still very wrong".)
    // A pin whose span is no tab's (set by its sliders, or made after Pick) is at hand
    // wherever its middle lies in what the wheel shows.
    readonly property var tabs: [[0, 1, "all tones"], [0.7, 1, "highlights"], [0.35, 0.75, "midtones"], [0, 0.4, "shadows"]]   // (scopes.RANGES)
    function spans(pin, low, high) { return Math.abs(pin.low - low) < 0.005 && Math.abs(pin.high - high) < 0.005 }
    function tonesOf(pin) {   // in words: which tones a pin works on
        const tab = tabs.find(t => spans(pin, t[0], t[1]))
        return tab ? tab[2] : "tones " + Math.round(pin.low * 100) + " to " + Math.round(pin.high * 100) + " %"
    }
    function here(pin, index) {
        if (!ours(pin)) return false
        if (index === selected || range.name === "full" || spans(pin, range.low, range.high)) return true
        if (tabs.some(tab => spans(pin, tab[0], tab[1]))) return false
        const middle = (pin.low + pin.high) / 2
        return middle >= range.low - 1e-6 && middle <= range.high + 1e-6
    }
    // (Asked as if it were not the chosen one, and let go of only if it is then not at hand.
    // Never let go of for a moment and taken up again: the range is told anew at every count
    // of the photo's colors, and a pin slider being dragged lost its hold; the owner: "unable
    // to drag the sliders in the Tone Wheel card".)
    property string rangeWas: ""
    onRangeChanged: {
        const now = range.name + " " + range.low + " " + range.high
        if (now === rangeWas) return
        rangeWas = now
        if (selected >= 0 && !(selected < pins.length && here(pins[selected], -2))) selected = -1
        plot.requestPaint()
    }
    onMaskChanged: { deselect(); plot.requestPaint() }
    onPinsChanged: { if (selected >= pins.length || (selected >= 0 && !ours(pins[selected]))) selected = -1; plot.requestPaint() }
    onSelectedChanged: plot.requestPaint()
    onFreshChanged: plot.requestPaint()
    function colorAt(x, y) { return [middle.x + (x - width / 2) / unit * span, middle.y - (y - height / 2) / unit * span] }
    function hit(x, y) {   // what of a pin is under that point: { what, pin }, or nothing
        const near = (color, reach) => Math.hypot(px(color[0]) - x, py(color[1]) - y) < reach
        for (let i = pins.length - 1; i >= 0; i--) if (here(pins[i], i) && near(pins[i].to, 10)) return { what: "to", pin: i }
        if (selected >= 0 && near(pins[selected].from, 9)) return { what: "from", pin: selected }
        return fresh && near(fresh.from, 10) ? { what: "fresh", pin: -1 } : null
    }
    // Mark a color (from a click on the wheel or on the photo) and bring it into view.
    function mark(color) {
        if (color.length < 2) return
        fresh = { from: [color[0], color[1]] }
        selected = -1
        if (Math.abs(px(color[0]) - width / 2) > width / 2 - 12 || Math.abs(py(color[1]) - height / 2) > height / 2 - 12)
            middle = Qt.point(held(color[0]), held(color[1]))
    }
    function copies() { return pins.map(pin => Object.assign({}, pin)) }
    // The mark becomes a pin, within the working range the wheel is showing: when it is
    // dragged, and as soon as anything else is done to it (the wheel turned on it, a slider
    // of the Pin section moved; the owner: "i cannot scroll to edit the range until i move it
    // around"). Until then it moves nothing, so a click alone leaves no pin behind. Gives the
    // pin's place in the list, or -1.
    function place(to) {
        if (!fresh) return selected
        if (pins.length >= 12) { session.say("A photo can have twelve pins. Remove one to make another."); return -1 }
        const list = copies()
        list.push({ from: fresh.from, to: to || fresh.from, low: session.range.low, high: session.range.high, mask: mask })
        session.setEdit("pins", list)
        selected = list.length - 1
        fresh = null
        return selected
    }
    function change(index, values) {
        if (index < 0 || index >= pins.length) return
        const list = copies()
        Object.assign(list[index], values)
        session.setEdit("pins", list)
    }
    function remove(index) {
        if (index < 0 || index >= pins.length) return
        const list = copies()
        list.splice(index, 1)
        selected = -1
        session.setEdit("pins", list)
        session.commitEdit()
    }
    function duplicate(index) {
        if (index < 0 || index >= pins.length) return
        if (pins.length >= 12) return session.say("A photo can have twelve pins. Remove one to make another.")
        const list = copies()
        list.push(Object.assign({}, pins[index]))
        session.setEdit("pins", list)
        session.commitEdit()
        selected = list.length - 1
    }
    function deselect() { selected = -1; fresh = null }
    function shift(pin) {   // how far a pin moves its color, in words: "+16°  -0.01"
        const hue = (c) => Math.atan2(c[1], c[0]) * 180 / Math.PI, chroma = (c) => Math.hypot(c[0], c[1])
        const signed = (v, digits) => (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(digits)
        let turn = hue(pin.to) - hue(pin.from)
        turn -= 360 * Math.round(turn / 360)
        return (chroma(pin.from) < 0.02 ? "" : signed(turn, 0) + "°  ") + signed(chroma(pin.to) - chroma(pin.from), 2)
    }

    radius: 5; color: Theme.bg; clip: true
    Accessible.role: Accessible.Graphic; Accessible.name: "Color wheel"
    Connections {
        target: session
        function onPhotoChanged() { root.framed = false; root.showAll() }
    }
    onCloudChanged: if (!framed && cloud.count) { fit(); framed = true }
    onSpanChanged: plot.requestPaint()
    onMiddleChanged: plot.requestPaint()
    onProbeChanged: plot.requestPaint()
    onWidthChanged: plot.requestPaint()

    ShaderEffect {
        objectName: "wheel-disc"
        anchors.fill: parent
        opacity: 0.6   // over the dark ground: calm enough for the photo's own colors to stand out
        property real linearOut: session.linearSurface ? 1 : 0
        property real lightness: 0.75
        property real span: root.span
        property real rim: root.rim
        property point middle: root.middle
        property real aspect: root.width / Math.max(1, root.height)
        fragmentShader: wheelShader
        vertexShader: wheelVertex
    }
    // The photo's colors, as dots, drawn by the GPU from the photo itself at every frame
    // (dots.vert): a small render of the photo that carries each pixel's color as numbers,
    // and a mesh that puts a dot where each of those colors lies on the wheel. A slider that
    // moves the photo's colors moves the dots in the same frame.
    property var picture                    // the photo's first picture (an Image)
    property var painted                    // and its painted masks' (PhotoView.painted)
    readonly property int side: 127         // dots across and down: one for each pixel of that render
    Pipeline {
        id: numbers
        objectName: "wheel-colors"
        width: root.side; height: root.side; visible: false
        source: root.picture; sharp: root.picture; useSharp: 0; painted: root.painted || root.picture
        edit: session.inFrame
        scope: session.panels.live ? 9 : 8   // after everything, or before the pins
        peak: 1; hdrLift: 0; linearOut: 0; clipping: 0
        layer.enabled: true; layer.format: ShaderEffectSource.RGBA16F; layer.smooth: false
    }
    component Dots: ShaderEffect {
        anchors.fill: parent
        visible: root.picture !== undefined && root.picture !== null && session.source !== ""
        mesh: GridMesh { resolution: Qt.size(2 * root.side - 1, 2 * root.side - 1) }
        property var colors: numbers
        property real linearOut: session.linearSurface ? 1 : 0
        property real count: root.side
        property real span: root.span
        property real radius: 3.2
        property real low: session.range.low
        property real high: session.range.high
        property real ink: 0
        property point middle: root.middle
        property point across: Qt.point(width, height)
        vertexShader: dotsVertex
        fragmentShader: dotsShader
    }
    Dots { objectName: "wheel-ink"; ink: 1; radius: 4.6 }   // the dark ground under them: their outline
    Dots { objectName: "wheel-dots" }
    Canvas {   // what lies over them: the rings, the pins, the cross. Little, and drawn at once.
        id: plot
        objectName: "wheel-plot"
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            const x0 = root.px(0), y0 = root.py(0), unit = root.unit / root.span
            ctx.reset()
            // Rings of equal chroma, closer together the closer the view; twelve spokes of hue.
            const step = root.zoom < 2.5 ? 0.08 : root.zoom < 5 ? 0.04 : root.zoom < 10 ? 0.02 : 0.01
            ctx.strokeStyle = Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.13)
            ctx.lineWidth = 1
            ctx.beginPath()
            for (let r = step; r <= root.rim + 1e-6; r += step) { ctx.moveTo(x0 + r * unit, y0); ctx.arc(x0, y0, r * unit, 0, 2 * Math.PI) }
            for (let k = 0; k < 12; k++) {
                const c = Math.cos(k * Math.PI / 6), s = Math.sin(k * Math.PI / 6)
                ctx.moveTo(x0 + step * unit * c, y0 - step * unit * s); ctx.lineTo(x0 + root.rim * unit * c, y0 - root.rim * unit * s)
            }
            ctx.stroke()
            // Their chroma, written along the line from the gray middle toward what is in view.
            const far = Math.hypot(root.middle.x, root.middle.y)
            const dx = far > 0.01 ? root.middle.x / far : 0, dy = far > 0.01 ? root.middle.y / far : 1
            ctx.fillStyle = Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.45)
            ctx.font = "10px sans-serif"   // (a canvas refuses a family that is not installed)
            for (let r = step; r <= root.rim + 1e-6; r += step)
                ctx.fillText(r.toFixed(2), x0 + r * unit * dx + 4, y0 - r * unit * dy - 4)
            // The pins. Under the one being worked on: how far it reaches (dotted), and where
            // it reaches in full (fainter).
            const ring = (color, reach, stroke, wide, dash) => {
                ctx.beginPath()
                ctx.setLineDash(dash)
                ctx.arc(root.px(color[0]), root.py(color[1]), reach, 0, 2 * Math.PI)
                ctx.strokeStyle = stroke; ctx.lineWidth = wide
                ctx.stroke()
                ctx.setLineDash([])
            }
            const dark = Qt.rgba(0, 0, 0, 0.7), marks = root.pins.map(pin => pin)
            if (root.fresh) marks.push({ from: root.fresh.from, to: root.fresh.from, range: 0.08, feather: 70, fresh: true })
            for (let i = 0; i < marks.length; i++) {
                const pin = marks[i], on = pin.fresh || i === root.selected
                const fx = root.px(pin.from[0]), fy = root.py(pin.from[1]), tx = root.px(pin.to[0]), ty = root.py(pin.to[1])
                if (!pin.fresh && !root.here(pin, i)) { ring(pin.to, 3.5, dark, 3, []); ring(pin.to, 3.5, Qt.rgba(1, 1, 1, 0.55), 1.2, []); continue }
                if (on) {
                    ring(pin.from, pin.range * unit, Qt.rgba(1, 1, 1, 0.75), 1, [2, 4])
                    ring(pin.from, pin.range * (1 - pin.feather / 100) * unit, Qt.rgba(1, 1, 1, 0.35), 1, [2, 4])
                }
                if (Math.hypot(tx - fx, ty - fy) > 1) {
                    for (const [color, wide] of [[dark, 4], [Theme.text, 1.6]]) {
                        ctx.strokeStyle = color; ctx.lineWidth = wide
                        ctx.beginPath(); ctx.moveTo(fx, fy); ctx.lineTo(tx, ty); ctx.stroke()
                    }
                    ring(pin.from, 5.5, dark, 3, [])
                    ring(pin.from, 5.5, Theme.text, 1.4, [3, 2])
                    // An arrowhead at the disc: which way the color goes (the owner: "an arrow
                    // ... toward the target offset point"). Not on a line too short for one.
                    const far = Math.hypot(tx - fx, ty - fy), ux = (tx - fx) / far, uy = (ty - fy) / far, tip = (on ? 7.5 : 6) + 2
                    if (far > tip + 16) {
                        const hx = tx - ux * tip, hy = ty - uy * tip, bx = hx - ux * 9, by = hy - uy * 9
                        ctx.beginPath(); ctx.moveTo(hx, hy); ctx.lineTo(bx - uy * 4.5, by + ux * 4.5); ctx.lineTo(bx + uy * 4.5, by - ux * 4.5); ctx.closePath()
                        ctx.strokeStyle = dark; ctx.lineWidth = 2; ctx.stroke()
                        ctx.fillStyle = Theme.text; ctx.fill()
                    }
                }
                ctx.beginPath()
                ctx.arc(tx, ty, on ? 7.5 : 6, 0, 2 * Math.PI)
                ctx.fillStyle = pin.mode === "protect" ? Theme.panel : Theme.white
                ctx.fill()
                ctx.strokeStyle = dark; ctx.lineWidth = on ? 2.5 : 1.5
                ctx.stroke()
                if (on && !pin.fresh) {
                    const words = root.shift(pin)
                    ctx.font = "11px sans-serif"
                    const wide = ctx.measureText(words).width + 12
                    const lx = Math.min(width - wide - 4, tx + 13), ly = Math.max(4, Math.min(height - 24, ty - 10))
                    ctx.fillStyle = Qt.rgba(0, 0, 0, 0.6)
                    ctx.fillRect(lx, ly, wide, 20)
                    ctx.fillStyle = Theme.text
                    ctx.fillText(words, lx + 6, ly + 14)
                }
            }
            // The color under the pointer on the photo.
            if (root.probe.length === 3) {
                const x = Math.round(root.px(root.probe[0])) + 0.5, y = Math.round(root.py(root.probe[1])) + 0.5
                for (const [color, wide] of [[Qt.rgba(0, 0, 0, 0.6), 3], [Theme.text, 1]]) {
                    ctx.strokeStyle = color; ctx.lineWidth = wide
                    ctx.beginPath()
                    ctx.moveTo(x - 14, y); ctx.lineTo(x - 5, y); ctx.moveTo(x + 5, y); ctx.lineTo(x + 14, y)
                    ctx.moveTo(x, y - 14); ctx.lineTo(x, y - 5); ctx.moveTo(x, y + 5); ctx.lineTo(x, y + 14)
                    ctx.stroke()
                }
            }
        }
    }
    Timer { id: settled; interval: 500; onTriggered: session.commitEdit() }   // after the last notch of a wheel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: pressed && !grab ? Qt.ClosedHandCursor : Qt.ArrowCursor
        property point last
        property bool twice: false     // this press is the second of a double click
        property bool onMark: false    // this press was on the mark (the color just clicked)
        property bool wasOnMark: false // and so was the press before it
        property real travelled        // since the press: a click is a press that went nowhere
        property var grab: null        // what of a pin is being dragged: { what, pin, x, y, start }
        onPressed: (mouse) => {
            // (Another button pressed while one is held, a right click in the middle of a drag:
            // nothing. It took the pin being dragged away.)
            if (mouse.buttons !== mouse.button) return
            last = Qt.point(mouse.x, mouse.y)
            travelled = 0
            grab = null
            twice = false
            // A right click on a pin takes it away (Ctrl+Z brings it back), on a mark likewise.
            if (mouse.button === Qt.RightButton) return takeAway(mouse)
            const found = mouse.button === Qt.LeftButton ? root.hit(mouse.x, mouse.y) : null
            wasOnMark = onMark
            onMark = found !== null && found.what === "fresh"
            if (!found) return
            if (found.pin >= 0) root.selected = found.pin
            const start = found.what === "fresh" ? root.fresh.from : root.pins[found.pin][found.what]
            grab = { what: found.what, pin: found.pin, x: mouse.x, y: mouse.y, start: [start[0], start[1]], slow: !!(mouse.modifiers & Qt.ShiftModifier) }
        }
        onPositionChanged: (mouse) => {
            travelled += Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y)
            if (!grab) root.panBy(mouse.x - last.x, mouse.y - last.y)
            last = Qt.point(mouse.x, mouse.y)
            if (!grab) return
            // As everywhere: the thing moves from where it is, by how far the pointer goes.
            // (Shift on the way: on from where the pin is, at the other pace.)
            const slow = !!(mouse.modifiers & Qt.ShiftModifier)
            if (slow !== grab.slow) {
                const now = grab.what === "fresh" ? grab.start : root.pins[grab.pin][grab.what]
                grab = { what: grab.what, pin: grab.pin, x: mouse.x, y: mouse.y, start: [now[0], now[1]], slow: slow }
            }
            const fine = (slow ? 0.1 : 1) / root.unit * root.span
            const to = [grab.start[0] + (mouse.x - grab.x) * fine, grab.start[1] - (mouse.y - grab.y) * fine]
            if (grab.what !== "fresh") return root.change(grab.pin, grab.what === "to" ? { to: to } : { from: to })
            if (travelled < 4) return
            const made = root.place(to)
            if (made < 0) { grab = null; return }
            grab.what = "to"
            grab.pin = made
        }
        onReleased: (mouse) => {
            // (Only the last button let go ends what was begun: a right click in the middle of
            // a drag ended the drag, and the pointer then moved the wheel's view instead.)
            if (mouse.buttons !== Qt.NoButton) return
            // (Not after a double click: that one took a pin away, and its second release
            // marked the color again on the spot; the owner: "probably a bug".)
            if (grab) { grab = null; session.commitEdit(); root.done() }
            else if (travelled < 4 && mouse.button === Qt.LeftButton && !twice) root.mark(root.colorAt(mouse.x, mouse.y))
        }
        function takeAway(mouse) {
            const found = root.hit(mouse.x, mouse.y)
            if (found && found.what === "to") root.remove(found.pin)
            else if (found && found.what === "fresh") root.fresh = null
        }
        onDoubleClicked: (mouse) => {
            if (mouse.button !== Qt.LeftButton) return
            grab = null
            twice = true
            // A pin goes; and a mark too, if both clicks were on it. (Not the mark this very
            // double click's first click made: placing one and clicking again quickly took it
            // away at once, which the owner saw; then no double click took a mark away at all,
            // which he saw too: "i cant double click it to remove it".)
            const found = root.hit(mouse.x, mouse.y)
            if (found && found.what === "to") root.remove(found.pin)
            else if (found && found.what === "fresh" && wasOnMark) root.fresh = null
        }
        onWheel: (wheel) => {
            if (root.yields) { wheel.accepted = false; return }
            const turned = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : wheel.pixelDelta.y * 2
            const found = root.hit(wheel.x, wheel.y)
            if (!found) return root.zoomAt(Math.pow(1.0015, turned), wheel.x, wheel.y)
            // On a pin the wheel is that pin's: its range, with Shift its feather, with Alt its
            // variance. On a mark too, which is a pin from then on.
            if (found.pin < 0) found.pin = root.place()
            if (found.pin < 0) return
            const pin = root.pins[found.pin], within = (v, low, high) => Math.max(low, Math.min(high, v))
            root.selected = found.pin
            if (wheel.modifiers & Qt.AltModifier) root.change(found.pin, { variance: within(pin.variance + turned / 12, -100, 100) })
            else if (wheel.modifiers & Qt.ShiftModifier) root.change(found.pin, { feather: within(pin.feather + turned / 24, 0, 100) })
            else root.change(found.pin, { range: within(pin.range * Math.pow(1.001, turned), 0.01, 0.5) })
            settled.restart()
        }
    }
    // Which colors the dots are: the photo's before the pins (where a pin takes hold) or after
    // them (what the pins have made of it). Only a question once there is a pin.
    Rectangle {
        objectName: "wheel-live"
        visible: root.pins.length > 0
        x: 8; y: 8; width: sides.width + 6; height: 30; radius: 7; color: Theme.raised
        Row {
            id: sides
            anchors.centerIn: parent
            Segment { objectName: "wheel-before"; label: "Before"; on: !session.panels.live; onChosen: session.setPanel("live", false) }
            Segment { objectName: "wheel-after"; label: "After"; on: session.panels.live; onChosen: session.setPanel("live", true) }
        }
    }
    // Fit, All, and how far in the view is, as on the photo.
    Rectangle {
        objectName: "wheel-zoom"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
        width: buttons.width + 6; height: 30; radius: 7; color: Theme.raised
        Row {
            id: buttons
            anchors.centerIn: parent
            Segment { objectName: "wheel-fit"; label: "Fit"; onChosen: root.glideFit() }
            Segment { objectName: "wheel-all"; label: "All"; on: root.all; onChosen: root.glideAll() }
            Item {
                width: 52; height: 26
                Rectangle { x: 5; y: 5; width: 1; height: 16; color: Theme.line }
                Label {
                    anchors { fill: parent; leftMargin: 6 }
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    color: Theme.faint; font.pixelSize: 12; font.features: { "tnum": 1 }
                    text: root.zoom.toFixed(1) + "×"
                }
            }
        }
    }
    // A shadow along its edges, falling inward: the view reads as set into its card (the
    // owner's wish). Drawn over everything in it; it takes no clicks.
    component Shade: Rectangle {
        property bool flat: true   // along a top or bottom edge
        property bool far: false   // the bottom or the right one
        z: 20
        readonly property real deep: 24
        width: flat ? parent.width : deep; height: flat ? deep : parent.height
        x: !flat && far ? parent.width - width : 0; y: flat && far ? parent.height - height : 0
        // (Falling off as a curve, in five steps: a straight fall from one dark value showed
        // its end as an edge, and the corners, where two lie on each other, as squares.)
        function at(t) { return Qt.rgba(0, 0, 0, 0.34 * (1 - t) * (1 - t) * (1 - t)) }
        gradient: Gradient {
            orientation: flat ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: far ? 1 : 0; color: at(0) }
            GradientStop { position: far ? 0.85 : 0.15; color: at(0.15) }
            GradientStop { position: far ? 0.7 : 0.3; color: at(0.3) }
            GradientStop { position: far ? 0.5 : 0.5; color: at(0.5) }
            GradientStop { position: far ? 0.25 : 0.75; color: at(0.75) }
            GradientStop { position: far ? 0 : 1; color: at(1) }
        }
    }
    Shade {} Shade { far: true } Shade { flat: false } Shade { flat: false; far: true }
    // Its corners are rounded as the lightness strip's under it are, with the same thin
    // outline: what is drawn in it is cut square, so the corners are laid over in the card's
    // color (a ring just outside the view, whose inner edge is the rounded one).
    Rectangle {
        z: 21; x: -8; y: -8; width: parent.width + 16; height: parent.height + 16
        radius: 13; color: "transparent"; border { width: 8; color: Theme.card }
    }
    Rectangle { z: 22; anchors.fill: parent; radius: 5; color: "transparent"; border { width: 1; color: Theme.line } }
}
