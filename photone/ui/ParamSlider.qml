import QtQuick
import "."

// One slider: its name and its value on one line, the track below across the whole width. The
// track is as long as the panel allows because its length is the fineness of the control (the
// owner: "the sliders definitely need to be longer"). Names sit on one left edge, numbers on
// one right edge, tracks start and end on the same lines. The track fills from the neutral
// value to the thumb, so how far and which way a setting has moved shows without the number.
//
// The slider never changes `value` itself: it says what the user wants (`moved`), when the
// gesture is over (`released`, one undo step) and when the setting should rest (`reset`), and
// whoever owns the value binds it back in.
Item {
    id: root
    property string name
    property string unit: ""
    property real from: -1
    property real to: 1
    property real neutral: 0
    property real step: 0.01
    property int digits: 2
    property bool logarithmic: false   // equal travel for equal ratios (a temperature)
    property bool signed: neutral === 0  // +0.50 and -0.50 line up; not for what cannot go below zero
    property real value: neutral
    // Changed since the last checkpoint: name, number and track in yellow (the owner's wish).
    property bool unsaved: false
    readonly property color ink: unsaved ? Theme.yellow : Theme.text
    signal moved(real value)
    signal released()
    signal reset()

    function fractionOf(v) {
        return logarithmic ? Math.log(v / from) / Math.log(to / from) : (v - from) / (to - from)
    }
    function valueAt(f) {
        f = Math.max(0, Math.min(1, f))
        return logarithmic ? from * Math.pow(to / from, f) : from + f * (to - from)
    }
    function ask(v) { moved(Math.max(from, Math.min(to, Math.round(v / step) * step))) }
    readonly property real fraction: fractionOf(Math.max(from, Math.min(to, value)))
    readonly property real neutralFraction: fractionOf(neutral)
    readonly property bool adjusted: Math.abs(value - neutral) > step / 2

    implicitHeight: Theme.slider
    height: Theme.slider
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: name
    // The keys step it once Tab has brought the focus here; pressing it with the mouse does
    // not take the keys away from the photo.
    Keys.onLeftPressed: (event) => { ask(value - step * (event.modifiers & Qt.ShiftModifier ? 1 : 10)); released() }
    Keys.onRightPressed: (event) => { ask(value + step * (event.modifiers & Qt.ShiftModifier ? 1 : 10)); released() }

    Text {
        id: label
        objectName: "text:" + root.name
        y: 4; anchors { left: parent.left; right: readout.left; rightMargin: 8 }
        text: root.name; elide: Text.ElideRight
        color: root.unsaved ? Theme.yellow : root.adjusted ? Theme.text : Theme.dim
        font.family: Theme.font; font.pixelSize: Theme.fontSize
    }
    Item {
        id: track
        objectName: "track"
        readonly property int thumb: 12
        readonly property real travel: width - thumb
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 24

        Rectangle { y: parent.height / 2 - 1; width: parent.width; height: 2; radius: 1; color: Theme.line }
        Rectangle {  // the fill, from neutral to the thumb
            objectName: "fill"
            readonly property real a: Math.min(root.fraction, root.neutralFraction)
            readonly property real b: Math.max(root.fraction, root.neutralFraction)
            x: track.thumb / 2 + a * track.travel; width: (b - a) * track.travel
            y: parent.height / 2 - 1; height: 2; color: root.ink
        }
        Rectangle {  // the tick at neutral
            objectName: "tick"
            x: Math.round(track.thumb / 2 + root.neutralFraction * track.travel); y: parent.height / 2 - 4
            width: 1; height: 8; color: Theme.faint
        }
        Rectangle {
            objectName: "thumb"
            x: root.fraction * track.travel; y: parent.height / 2 - track.thumb / 2
            width: track.thumb; height: track.thumb; radius: track.thumb / 2
            color: root.ink
            border { width: 1; color: area.containsMouse || area.pressed || root.activeFocus ? root.ink : Theme.faint }
            Rectangle { anchors { fill: parent; margins: 1 } radius: width / 2; color: "transparent"; border { width: 2; color: Theme.panel } }
        }
        MouseArea {
            id: area
            anchors.fill: parent; hoverEnabled: true
            property real startX
            property real startFraction
            // A drag that begins on the thumb moves the value from where it is, by how far the
            // pointer goes (Shift: a tenth of that). A press elsewhere on the track brings the
            // thumb there at once, as the first move of the drag (the owner: "register
            // mouseDown as a first movement of the slider"), and the drag goes on from there.
            // (Shift pressed or let go in the middle of a drag: the drag goes on from where the
            // value is, at the other pace. Measured from the press it jumped; the owner saw it.)
            property real pace: 1
            onPressed: (mouse) => {
                const center = root.fraction * track.travel + track.thumb / 2
                const onThumb = Math.abs(mouse.x - center) <= track.thumb / 2 + 3
                startX = mouse.x; pace = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1
                startFraction = onThumb ? root.fraction : (mouse.x - track.thumb / 2) / track.travel
                if (!onThumb) root.ask(root.valueAt(startFraction))
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return
                const fine = mouse.modifiers & Qt.ShiftModifier ? 0.1 : 1
                if (fine !== pace) { pace = fine; startX = mouse.x; startFraction = root.fraction }
                root.ask(root.valueAt(startFraction + (mouse.x - startX) / track.travel * fine))
            }
            onReleased: root.released()
            onDoubleClicked: root.reset()
        }
    }
    Item {
        id: readout
        width: 68; height: 20; y: 2
        anchors.right: parent.right
        Text {
            id: unitText
            text: root.unit; color: Theme.dim
            anchors { right: parent.right; baseline: number.baseline }
            font.family: Theme.font; font.pixelSize: Theme.smallSize
        }
        Text {
            id: number
            objectName: "value"
            visible: !entry.visible
            anchors { right: unitText.left; rightMargin: root.unit === "" ? 0 : 4; verticalCenter: parent.verticalCenter }
            // A signed number wherever neutral is zero, so +0.50 and -0.50 line up.
            text: (root.signed && root.value >= 0 ? "+" : "") + root.value.toFixed(root.digits)
            color: root.ink
            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.features: { "tnum": 1 }
        }
        // Click the number to type one. Enter or leaving the field takes it; Escape does not.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: { entry.text = root.value.toFixed(root.digits); entry.visible = true; entry.forceActiveFocus(); entry.selectAll() }
        }
        TextInput {
            id: entry
            objectName: "entry"
            visible: false
            anchors { right: number.right; verticalCenter: parent.verticalCenter }
            width: 46; horizontalAlignment: TextInput.AlignRight
            color: Theme.text; selectionColor: Theme.faint; selectedTextColor: Theme.text
            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.features: { "tnum": 1 }
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            function done() { visible = false; root.typed() }
            function take() {
                const v = Number(text.replace(",", "."))
                if (text.trim() !== "" && isFinite(v)) { root.ask(v); root.released() }
            }
            onAccepted: { take(); done() }
            Keys.onEscapePressed: done()   // (the one way to leave without the value)
            // Left any other way (a click elsewhere, Tab): what was typed is kept, as Enter
            // would (docs/PLAN.md §5: a text field takes its value when it is left).
            onActiveFocusChanged: if (!activeFocus && visible) { take(); visible = false }
        }
    }
    signal typed()   // typing is over: the keys can go back to the photo
}
