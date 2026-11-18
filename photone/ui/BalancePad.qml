import QtQuick
import "."

// White balance as a place on a square: up warmer, down cooler, left greener, right more
// magenta, the middle as the camera shot it. It moves the same two settings as Temperature
// and Tint: one octave of kelvin each way up and down, 100 of tint each way across.
Item {
    id: root
    signal done()                     // a gesture is over
    signal pick()                     // "Pick neutral" was pressed
    property bool picking: false
    // As large as the column lets it be beside its button: its size is how fine it is.
    readonly property real size: Math.max(150, Math.min(230, width - 176))
    height: size + 44
    readonly property real up: Math.log(session.edit.temperature / session.shot.temperature) / Math.LN2
    readonly property real across: (session.edit.tint - session.shot.tint) / 100
    function held(v) { return Math.max(-1, Math.min(1, v)) }
    function words() {
        const parts = [], v = Math.round(up * 100), u = Math.round(across * 100)
        if (v) parts.push((v > 0 ? "Warm " : "Cool ") + Math.abs(v))
        if (u) parts.push((u > 0 ? "Magenta " : "Green ") + Math.abs(u))
        return parts.length ? parts.join("  ·  ") : "As shot"
    }

    Label { text: "Warm"; font.pixelSize: Theme.smallSize; x: pad.x + (pad.width - width) / 2; y: 2 }
    Label { text: "Cool"; font.pixelSize: Theme.smallSize; x: pad.x + (pad.width - width) / 2; y: pad.y + pad.height + 4 }
    Label { text: "Green"; font.pixelSize: Theme.smallSize; rotation: -90; x: pad.x - 11 - width / 2; y: pad.y + (pad.height - height) / 2 }
    Label { text: "Magenta"; font.pixelSize: Theme.smallSize; rotation: 90; x: pad.x + pad.width + 11 - width / 2; y: pad.y + (pad.height - height) / 2 }
    Rectangle {
        id: pad
        objectName: "balance-pad"
        x: 22; y: 20; width: root.size; height: root.size; radius: 6
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.padWarm }
            GradientStop { position: 1; color: Theme.padCool }
        }
        Accessible.role: Accessible.Slider; Accessible.name: "White balance: " + root.words()
        // With the keys, once Tab has brought the focus here: the arrows move the dot.
        activeFocusOnTab: true
        border { width: activeFocus ? 1 : 0; color: Theme.text }
        function nudge(across, up) {
            session.setEdits({ temperature: session.shot.temperature * Math.pow(2, root.held(root.up + up)),
                               tint: session.shot.tint + 100 * root.held(root.across + across) })
            session.commitEdit()
        }
        Keys.onUpPressed: nudge(0, 0.02)
        Keys.onDownPressed: nudge(0, -0.02)
        Keys.onLeftPressed: nudge(-0.02, 0)
        Keys.onRightPressed: nudge(0.02, 0)
        Rectangle {
            anchors.fill: parent; radius: parent.radius; opacity: 0.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.padGreen }
                GradientStop { position: 1; color: Theme.padMagenta }
            }
        }
        Rectangle { x: parent.width / 2; width: 1; height: parent.height; color: Theme.bg; opacity: 0.35 }
        Rectangle { y: parent.height / 2; height: 1; width: parent.width; color: Theme.bg; opacity: 0.35 }
        Rectangle {
            objectName: "balance-mark"
            x: (0.5 + root.held(root.across) / 2) * parent.width - 6; y: (0.5 - root.held(root.up) / 2) * parent.height - 6
            width: 12; height: 12; radius: 6; color: Theme.text; border { width: 2; color: Theme.bg }
        }
        MouseArea {
            anchors.fill: parent
            property var start
            // As on a slider: a drag moves the mark from where it is (Shift: a tenth as far).
            // (Shift pressed or let go on the way: on from where the mark is, at the other pace.)
            function begin(mouse) { start = { x: mouse.x, y: mouse.y, up: root.held(root.up), across: root.held(root.across), shift: !!(mouse.modifiers & Qt.ShiftModifier) } }
            onPressed: (mouse) => begin(mouse)
            onPositionChanged: (mouse) => {
                if (!!(mouse.modifiers & Qt.ShiftModifier) !== start.shift) begin(mouse)
                const fine = (start.shift ? 0.1 : 1) / (pad.width / 2)
                session.setEdits({
                    temperature: session.shot.temperature * Math.pow(2, root.held(start.up - (mouse.y - start.y) * fine)),
                    tint: session.shot.tint + 100 * root.held(start.across + (mouse.x - start.x) * fine) })
            }
            onReleased: { session.commitEdit(); root.done() }
            onDoubleClicked: session.resetTool("balance")
        }
    }
    // Beside the pad, two things, each with its own line of help directly under it: what
    // the pad is set to (top), and the tool that sets it from the photo (bottom). (One dim
    // line under both spoke now of the pad and now of the tool; the owner: it "acts as a
    // guide for the color square, and at another as a guide for a tool that is one element
    // over".)
    Column {
        anchors { left: pad.right; leftMargin: 30; right: parent.right; top: pad.top }
        spacing: 4
        Label { objectName: "balance-words"; width: parent.width; text: root.words(); color: Theme.text; wrapMode: Text.WordWrap }
        Label {
            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Theme.faint
            text: "Drag the dot. A double click puts it back."
        }
    }
    Column {
        anchors { left: pad.right; leftMargin: 30; right: parent.right; bottom: pad.bottom }
        spacing: 6
        // (While it is on, the button says how to end it: the owner's wish.)
        PushButton { objectName: "pick-neutral"; label: root.picking ? "Done" : "Pick neutral"; on: root.picking; onPressed: root.pick() }
        Label {
            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; color: root.picking ? Theme.dim : Theme.faint
            text: root.picking ? "Click what should be gray in the photo, or slide over it. Esc ends." : "Takes the white balance from a gray in the photo."
        }
    }
}
