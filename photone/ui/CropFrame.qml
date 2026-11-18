import QtQuick
import "."

// The photo's frame, drawn while the Crop tool is open: the tool shows all of the picture,
// turned by the straightening angle, and the frame lies level on it, to drag by its corners,
// its edges or its middle. What lies outside is dimmed. The frame cannot leave the picture:
// the session takes a drag as far as it can go (session.setFrame).
Item {
    id: root
    readonly property var framing: session.framing
    readonly property var frame: framing.frame        // left, top, right, bottom, 0..1 of this item
    property real ratio: 0                            // width over height in pixels to keep; 0: free
    signal done()                                     // a gesture is over
    readonly property real shape: framing.shape       // this item's own width over its height

    // The frame that a drag asks for: not too small, and of the shape that is to be kept,
    // about the corner or edge that is not being dragged.
    function fitted(box, grip) {
        let [l, t, r, b] = box
        const least = 0.04
        l = Math.max(0, Math.min(l, r - least)); r = Math.min(1, Math.max(r, l + least))
        t = Math.max(0, Math.min(t, b - least)); b = Math.min(1, Math.max(b, t + least))
        if (ratio <= 0 || grip === "move") return [l, t, r, b]
        const keep = ratio / shape   // the shape in this item's own 0..1
        let w = r - l, h = b - t
        if (grip === "top" || grip === "bottom") w = h * keep; else h = w / keep
        const fit = Math.min(1, 1 / w, 1 / h)
        w *= fit; h *= fit
        // Hold what is not dragged: the opposite corner, or the middle of an edge's run.
        const x = grip.includes("left") ? r - w : grip.includes("right") ? l : (l + r - w) / 2
        const y = grip.includes("top") ? b - h : grip.includes("bottom") ? t : (t + b - h) / 2
        const left = Math.max(0, Math.min(1 - w, x)), top = Math.max(0, Math.min(1 - h, y))
        return [left, top, left + w, top + h]
    }
    // The largest frame of a shape inside another, about its middle.
    function shaped(box, to) {
        const keep = to / shape, w = box[2] - box[0], h = box[3] - box[1]
        const wide = Math.min(w, h * keep), high = wide / keep
        const x = (box[0] + box[2] - wide) / 2, y = (box[1] + box[3] - high) / 2
        return [x, y, x + wide, y + high]
    }
    // Take up a shape.
    // Always from the frame as it was before a shape was first chosen, for as long as the
    // frame is still the one the last choice left: going from one shape to another and back
    // gives the first frame again. (Each shape was cut out of the one before, so every
    // change of shape made the frame smaller; the owner: "it happens when switching
    // between aspect ratios too".)
    property var shapedFrom: null   // { base, result }
    function reshape(to) {
        ratio = to
        if (to <= 0) return
        const now = [frame[0], frame[1], frame[2], frame[3]]
        const same = (a, b) => a.every((v, i) => Math.abs(v - b[i]) < 1e-6)
        const base = shapedFrom && same(now, shapedFrom.result) ? shapedFrom.base : now
        const wanted = shaped(base, to)
        session.setFrame(wanted, wanted, true)
        session.commitEdit()
        shapedFrom = { base: base, result: [frame[0], frame[1], frame[2], frame[3]] }
    }

    // Stand the frame on end (Portrait, and back): as wide as it was high and as high as it
    // was wide, about its middle, smaller only if the picture has no room for that. Stood
    // back, it is the frame it was before, to the pixel. (It took the largest frame of the
    // other shape inside itself each time, so every flip made it smaller; the owner:
    // "keeps shrinking the crop rectangle".)
    property var stoodFrom: null   // { from, to }: the frame before the last flip and after it
    function flip() {
        const now = [frame[0], frame[1], frame[2], frame[3]]
        const same = (a, b) => a.every((v, i) => Math.abs(v - b[i]) < 1e-6)
        let to
        if (stoodFrom && same(now, stoodFrom.to)) to = stoodFrom.from
        else {
            let wide = (now[3] - now[1]) / shape, high = (now[2] - now[0]) * shape
            const fit = Math.min(1, 1 / wide, 1 / high)
            wide *= fit; high *= fit
            const x = Math.max(0, Math.min(1 - wide, (now[0] + now[2] - wide) / 2)), y = Math.max(0, Math.min(1 - high, (now[1] + now[3] - high) / 2))
            to = [x, y, x + wide, y + high]
        }
        if (ratio > 0) ratio = 1 / ratio
        session.setFrame(to, to, true)
        session.commitEdit()
        stoodFrom = { from: now, to: [frame[0], frame[1], frame[2], frame[3]] }
    }

    Rectangle {   // the frame, with its thirds
        id: box
        objectName: "crop-box"
        x: root.frame[0] * root.width; y: root.frame[1] * root.height
        width: (root.frame[2] - root.frame[0]) * root.width; height: (root.frame[3] - root.frame[1]) * root.height
        color: "transparent"; border { width: 1.5; color: Theme.text }
        Repeater {
            model: 2
            Item {
                required property int index
                anchors.fill: parent
                Rectangle { x: parent.width * (index + 1) / 3; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.22) }
                Rectangle { y: parent.height * (index + 1) / 3; height: 1; width: parent.width; color: Qt.rgba(1, 1, 1, 0.22) }
            }
        }
    }
    // What the frame leaves out is dimmed by the photo's own shader (pipeline.frag, cropDim):
    // drawn over it here, the dimming cut its own edge round the turned picture, beside the
    // picture's, and left bright pixels between them.
    // Outside the frame, as far as `rim` from it, a drag turns the picture under the frame: it
    // follows the pointer round the frame's middle, as far as straightening goes. (Under the
    // frame's own grips, which lie over its inner part and its edges.) The pointer there is
    // an arc with arrows (the owner: "cursor icon changing when i hover and while dragging").
    readonly property real rim: 44
    MouseArea {
        id: turning
        objectName: "crop:turn"
        x: box.x - root.rim; y: box.y - root.rim; width: box.width + 2 * root.rim; height: box.height + 2 * root.rim
        // (Only its rim is left uncovered by the frame's own grips: there its pointer is the
        // turning one, `cursors`. Hover is a handler's: this area's own went stale once the
        // frame had shrunk under the pointer, as turning makes it do.)
        HoverHandler { id: rimHover }
        property real from     // the pointer's direction from the frame's middle at the press, degrees
        property real start    // the angle then
        property point spot    // the pointer, in the frame's item
        function direction(mouse) {
            const p = mapToItem(root, mouse.x, mouse.y)
            return Math.atan2(p.y - (box.y + box.height / 2), p.x - (box.x + box.width / 2)) * 180 / Math.PI
        }
        onPressed: (mouse) => { from = direction(mouse); start = root.framing.angle }
        onPositionChanged: (mouse) => {
            spot = mapToItem(root, mouse.x, mouse.y)
            const by = ((direction(mouse) - from + 540) % 360) - 180
            session.setEdit("angle", Math.max(-15, Math.min(15, Math.round((start + by) * 10) / 10)))
        }
        onReleased: { session.commitEdit(); root.done() }
    }
    // (Only on the rim: over the frame's own grips this area still counts the pointer as its
    // own, and the arc showed everywhere; the owner: "appears at all times now which is a bug".)
    readonly property point hovering: turning.mapToItem(root, rimHover.point.position.x, rimHover.point.position.y)
    readonly property bool atRim: {
        const p = hovering, far = 12   // (that far out the frame's own grips reach)
        if (!rimHover.hovered) return false
        return p.x < box.x - far || p.x > box.x + box.width + far || p.y < box.y - far || p.y > box.y + box.height + far
    }
    // Which way the turning pointer bulges (away from the frame's middle), or -1000: none.
    readonly property real turnAt: {
        if (!visible || !(turning.pressed || atRim)) return -1000
        const p = turning.pressed ? turning.spot : hovering
        return Math.atan2(p.y - (box.y + box.height / 2), p.x - (box.x + box.width / 2)) * 180 / Math.PI + 90
    }
    onTurnAtChanged: turnAt < -999 ? cursors.plain(turning) : cursors.turn(turning, turnAt)
    // What can be taken hold of: the middle, four edges, four corners (the later ones on top).
    Repeater {
        model: ["move", "top", "bottom", "left", "right", "top left", "top right", "bottom left", "bottom right"]
        MouseArea {
            id: grip
            required property string modelData
            readonly property bool wide: modelData === "top" || modelData === "bottom"
            readonly property bool tall: modelData === "left" || modelData === "right"
            readonly property bool corner: modelData.includes(" ")
            objectName: "crop:" + modelData
            x: modelData === "move" || wide ? box.x + 12 : modelData.includes("left") ? box.x - 12 : box.x + box.width - 12
            y: modelData === "move" || tall ? box.y + 12 : modelData.includes("top") ? box.y - 12 : box.y + box.height - 12
            width: modelData === "move" || wide ? Math.max(0, box.width - 24) : 24
            height: modelData === "move" || tall ? Math.max(0, box.height - 24) : 24
            cursorShape: modelData === "move" ? Qt.SizeAllCursor : wide ? Qt.SizeVerCursor : tall ? Qt.SizeHorCursor
                       : modelData === "top left" || modelData === "bottom right" ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
            property point from
            property var start
            onPressed: (mouse) => {
                from = mapToItem(root, mouse.x, mouse.y)
                // (A frame that is not of the shape to be kept, after a reset or an undo, takes
                // it up first: a drag is then from one frame of that shape to another.)
                const now = [root.frame[0], root.frame[1], root.frame[2], root.frame[3]]
                start = root.ratio > 0 && modelData !== "move" ? root.shaped(now, root.ratio) : now
            }
            onPositionChanged: (mouse) => {
                const at = mapToItem(root, mouse.x, mouse.y)
                const dx = (at.x - from.x) / root.width, dy = (at.y - from.y) / root.height
                let [l, t, r, b] = start
                if (modelData === "move") { l += dx; r += dx; t += dy; b += dy }
                else {
                    if (modelData.includes("left")) l += dx
                    if (modelData.includes("right")) r += dx
                    if (modelData.includes("top")) t += dy
                    if (modelData.includes("bottom")) b += dy
                }
                // (A frame that keeps its shape goes both ways at one pace; any other slides
                // along the picture's edge when it meets it.)
                session.setFrame(start, modelData === "move" ? [l, t, r, b] : root.fitted([l, t, r, b], modelData), root.ratio > 0 && modelData !== "move")
            }
            onReleased: { session.commitEdit(); root.done() }
            Rectangle {   // the corner's mark
                visible: grip.corner
                anchors.centerIn: parent; width: 9; height: 9; color: Theme.text; border { width: 1; color: Theme.bg }
            }
        }
    }
}
