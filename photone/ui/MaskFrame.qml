import QtQuick
import "."

// The mask that is being worked on (session.masks, photone/edit.py), drawn on the photo to be
// dragged. Radial: its outline and, fainter and dashed, where it starts to fade; a handle in
// its middle moves it, the one at the end of its axis sizes and turns it, the one at its side
// makes it wider or narrower. Linear: a line where it is at half, fainter lines where it is
// full and where it is gone; the handle in the middle moves it, the one on the far line (where
// it is gone) turns it and sets how fast it fades. Only the handles take the mouse: a click
// anywhere else is still a click on the photo.
Item {
    id: root
    property int number: 0   // the mask on show (1, 2, …); 0: none
    readonly property var mask: number > 0 && number <= session.masks.length ? session.masks[number - 1] : null
    signal done()            // a gesture is over
    // In this item's pixels: the middle, the end of the axis, how long and which way it is.
    readonly property bool brush: mask !== null && mask.kind === "brush"   // painted: it has no shape to drag
    readonly property bool shaped: mask !== null && !brush
    readonly property point at: shaped ? Qt.point(mask.at[0] * width, mask.at[1] * height) : Qt.point(0, 0)
    readonly property point to: shaped ? Qt.point(mask.to[0] * width, mask.to[1] * height) : Qt.point(1, 0)
    readonly property real reach: Math.max(1e-6, Math.hypot(to.x - at.x, to.y - at.y))
    readonly property point along: Qt.point((to.x - at.x) / reach, (to.y - at.y) / reach)
    readonly property real turn: Math.atan2(along.y, along.x) * 180 / Math.PI
    readonly property bool radial: mask !== null && mask.kind === "radial"
    readonly property color dark: Qt.rgba(0, 0, 0, 0.5)

    // An ellipse about the mask's middle, along its axis: drawn by a shader (oval.frag), for
    // each pixel by its distance from the ellipse.
    // A line across the mask's axis, as long as it takes to cross the photo.
    component Across: Item {
        id: line
        property real far: 0           // along the axis: 0 its middle, 1 its end
        property real strength: 1
        visible: root.shaped && !root.radial
        x: root.at.x + root.along.x * root.reach * far; y: root.at.y + root.along.y * root.reach * far
        rotation: root.turn + 90
        readonly property real span: 2 * (root.width + root.height)
        Rectangle { x: -line.span / 2; y: -1.75; width: line.span; height: 3.5; color: root.dark; antialiasing: true }
        Rectangle { x: -line.span / 2; y: -0.75; width: line.span; height: 1.5; color: Theme.text; opacity: line.strength; antialiasing: true }
    }
    Item {   // the shape, only where the photo is (the handles may lie outside it)
        anchors.fill: parent
        clip: true
        ShaderEffect {
            objectName: "mask-edge"
            anchors.fill: parent
            visible: root.radial
            property real rx: root.reach
            property real ry: root.reach * (root.mask ? root.mask.ratio : 1)
            property real inner: root.mask && root.mask.feather > 0.001 ? 1 - root.mask.feather : 0
            property real turn: root.turn * Math.PI / 180
            property vector2d span: Qt.vector2d(width, height)
            property vector2d middle: Qt.vector2d(root.at.x, root.at.y)
            property color ink: Theme.text
            fragmentShader: ovalShader; vertexShader: ovalVertex
        }
        Across { objectName: "mask-middle" }
        Across { far: 1; strength: 0.45 }
        Across { far: -1; strength: 0.45 }
    }

    // Outside the mask, as far as `rim` from it, a drag turns it about its middle (the owner:
    // "i want to be able to rotate them if i drag ... outside the bounds"). A radial mask's
    // outside is beyond its outline; a linear one's, beyond its two outer lines. Anywhere
    // else a press here is not taken: it is still a click or a drag on the photo.
    readonly property real rim: 44
    function turnable(x, y) {
        if (!shaped) return false
        const dx = x - at.x, dy = y - at.y
        const u = dx * along.x + dy * along.y, v = dy * along.x - dx * along.y   // along the axis, across it
        if (!radial) return Math.abs(u) > reach && Math.abs(u) <= reach + rim
        const across = reach * mask.ratio
        return Math.hypot(u / reach, v / across) > 1 && Math.hypot(u / (reach + rim), v / (across + rim)) <= 1
    }
    // Is that point away from the mask altogether: not in it, nor on the rim it is turned by?
    // (A click there lets go of the mask; the owner: "deselect masks by clicking away".)
    function away(x, y) {
        if (!shaped) return false
        const dx = x - at.x, dy = y - at.y
        const u = dx * along.x + dy * along.y, v = dy * along.x - dx * along.y
        if (!radial) return Math.abs(u) > reach + rim
        return Math.hypot(u / (reach + rim), v / (reach * mask.ratio + rim)) > 1
    }
    Item {   // (as far out as a mask can be turned from: the photo and a rim round it)
        id: around
        anchors { fill: parent; margins: -2 * root.rim }
        readonly property point spot: mapToItem(root, pointer.point.position.x, pointer.point.position.y)
        readonly property bool atRim: pointer.hovered && root.turnable(spot.x, spot.y)
        HoverHandler { id: pointer }
    }
    MouseArea {
        id: turner
        objectName: "mask:turn"
        anchors { fill: parent; margins: -2 * root.rim - Math.max(root.width, root.height) }   // (a mask may lie partly off the photo)
        visible: root.shaped
        property real from      // the pointer's direction from the mask's middle at the press, radians
        property point start    // where the axis ended then, from the middle, in pixels
        function place(mouse) { return mapToItem(root, mouse.x, mouse.y) }
        onPressed: (mouse) => {
            const p = place(mouse)
            if (!root.turnable(p.x, p.y)) { mouse.accepted = false; return }
            from = Math.atan2(p.y - root.at.y, p.x - root.at.x)
            start = Qt.point(root.to.x - root.at.x, root.to.y - root.at.y)
        }
        onPositionChanged: (mouse) => {
            const p = place(mouse), by = Math.atan2(p.y - root.at.y, p.x - root.at.x) - from
            const x = root.at.x + start.x * Math.cos(by) - start.y * Math.sin(by), y = root.at.y + start.x * Math.sin(by) + start.y * Math.cos(by)
            session.setMask(root.number, { to: [x / root.width, y / root.height] })
        }
        onReleased: { session.commitEdit(); root.done() }
    }
    // Which way the turning pointer bulges (away from the mask's middle), or -1000: none.
    // (A real cursor, set on the turning area only while the pointer is on the rim.)
    readonly property real turnAt: {
        if (!visible || !shaped || !(turner.pressed || around.atRim)) return -1000
        const p = turner.pressed ? turner.mapToItem(root, turner.mouseX, turner.mouseY) : around.spot
        return Math.atan2(p.y - at.y, p.x - at.x) * 180 / Math.PI + 90
    }
    onTurnAtChanged: turnAt < -999 ? cursors.plain(turner) : cursors.turn(turner, turnAt)

    // What can be taken hold of.
    component Grip: MouseArea {
        id: grip
        property point spot
        property bool hollow: false
        property bool main: false        // the handle that sizes and turns: a blue square
        signal dragged(real x, real y)   // where the handle is wanted, in the frame's pixels
        x: spot.x - 13; y: spot.y - 13; width: 26; height: 26
        visible: root.shaped
        cursorShape: Qt.SizeAllCursor
        property point off               // from the handle's middle to where it was taken hold of
        onPressed: (mouse) => { const p = mapToItem(root, mouse.x, mouse.y); off = Qt.point(p.x - spot.x, p.y - spot.y) }
        onPositionChanged: (mouse) => { const p = mapToItem(root, mouse.x, mouse.y); dragged(p.x - off.x, p.y - off.y) }
        onReleased: { session.commitEdit(); root.done() }
        Rectangle {
            visible: grip.main
            anchors.centerIn: parent; width: 17; height: 17; radius: 3; color: Theme.bg; rotation: root.turn
        }
        Rectangle {
            anchors.centerIn: parent; width: grip.main ? 13 : 12; height: width; radius: grip.main ? 2 : 6
            rotation: grip.main ? root.turn : 0
            // (The owner's choice: the middle and the side white dots outlined in black, the
            // one that sizes and turns a blue square outlined in white.)
            color: grip.main ? Theme.blue : Theme.text
            border { width: grip.main ? 2 : 1.5; color: grip.main ? Theme.text : Theme.bg }
        }
    }
    Grip {
        id: sideGrip
        objectName: "mask:side"; hollow: true
        visible: root.radial
        spot: Qt.point(root.at.x - root.along.y * root.reach * (root.mask ? root.mask.ratio : 1),
                       root.at.y + root.along.x * root.reach * (root.mask ? root.mask.ratio : 1))
        // How far from the axis the pointer is, in axis lengths.
        onDragged: (x, y) => session.setMask(root.number, {
            ratio: Math.abs((y - root.at.y) * root.along.x - (x - root.at.x) * root.along.y) / root.reach })
    }
    Grip {
        id: toGrip
        objectName: "mask:to"; main: true; spot: root.to
        onDragged: (x, y) => session.setMask(root.number, { to: [x / root.width, y / root.height] })
    }
    Grip {
        id: atGrip
        objectName: "mask:at"; spot: root.at
        onDragged: (x, y) => session.setMask(root.number, { at: [x / root.width, y / root.height] })
    }

    // Not pointed at, the shape is faint, so that what a slider does to the picture under it
    // can be seen (the owner: "dim/become transparent if im not hovering over it (or its
    // invisible outside hitbox)"): whole while the pointer is in the mask or on the rim it is
    // turned by, and while any of it is being dragged.
    readonly property bool engaged: turner.pressed || sideGrip.pressed || toGrip.pressed || atGrip.pressed
                                    || (pointer.hovered && shaped && !away(around.spot.x, around.spot.y))
    opacity: engaged || brush ? 1 : 0.22
    Behavior on opacity { NumberAnimation { duration: 140 } }

    // A painted mask: the left button paints on the photo with a round brush, or rubs out.
    // The brush is drawn round the pointer: its edge, and inside it where it begins to fade.
    // While the pointer is on the photo the mask lies over it in red (`tinting`: the photo's
    // shader does that), and not while it is elsewhere, on a slider.
    property real brushSize: 0.05      // the brush's radius as a share of the photo's width
    property real brushFeather: 0.5    // how much of that radius fades out
    property bool erasing: false
    signal sized(real size)            // Ctrl and the wheel: the brush larger or smaller
    readonly property bool tinting: brush && visible && (painter.containsMouse || painter.pressed)
    MouseArea {
        id: painter
        objectName: "mask:paint"
        anchors.fill: parent
        visible: root.brush
        hoverEnabled: true; cursorShape: Qt.CrossCursor
        property point last
        readonly property real radius: root.brushSize * width
        // Where the pointer is in the view the frame lies in: the brush's ring is drawn there,
        // and stays there when the photo is zoomed under a still pointer. (Drawn by this
        // area's own last place, it went off with the photo; the owner: "fly away".)
        property point spot
        function seen(mouse) { spot = mapToItem(root.parent, mouse.x, mouse.y) }
        // The way since the last place kept, with the places the pointer went through between
        // two frames (pointer.skipped), each kept once it is 2 px, or a twentieth of the
        // brush, from the one before: a fast curve is a curve.
        function put(mouse, begin) {
            const far = Math.max(2, radius / 10), places = []
            const through = begin ? [] : perFrame.skipped().map(at => mapFromItem(null, at.x, at.y))
            for (const at of through.concat([Qt.point(mouse.x, mouse.y)])) {
                if (!begin && Math.hypot(at.x - last.x, at.y - last.y) < far) continue
                last = at
                places.push([at.x / width, at.y / height])
            }
            if (begin) { last = Qt.point(mouse.x, mouse.y); places.push([mouse.x / width, mouse.y / height]) }
            if (places.length) session.paint(root.number, places, root.brushSize, root.brushFeather, root.erasing, begin)
        }
        onPressed: (mouse) => { seen(mouse); put(mouse, true) }
        onPositionChanged: (mouse) => { seen(mouse); if (pressed) put(mouse, false) }
        onReleased: (mouse) => { put(mouse, false); session.commitEdit(); root.done() }
        onWheel: (wheel) => {
            if (!(wheel.modifiers & Qt.ControlModifier)) { wheel.accepted = false; return }
            root.sized(root.brushSize * Math.pow(1.1, (wheel.angleDelta.y || wheel.pixelDelta.y * 2) / 120))
        }
        Rectangle {
            objectName: "brush-edge"
            visible: painter.containsMouse || painter.pressed
            x: painter.spot.x - root.x - width / 2; y: painter.spot.y - root.y - height / 2
            width: 2 * painter.radius; height: width; radius: width / 2
            color: "transparent"; border { width: 1.5; color: root.erasing ? Theme.red : Theme.text }
            Rectangle { anchors { fill: parent; margins: -1.5 } radius: width / 2; color: "transparent"; border { width: 1; color: root.dark } }
            Rectangle {
                visible: root.brushFeather > 0.02
                anchors.centerIn: parent; width: parent.width * (1 - root.brushFeather); height: width; radius: width / 2
                color: "transparent"; border { width: 1; color: Qt.rgba(1, 1, 1, 0.45) }
            }
        }
    }
}
