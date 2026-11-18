import QtQuick
import "."

// A button that is only its word, or only a sign (`sign`: an icon's path, Icon.qml; `says`
// is then its name for a screen reader). `held` is true for as long as it is pressed.
Label {
    id: button
    property bool available: true
    property string sign: ""
    property string says: text
    readonly property bool containsPointer: press.containsMouse
    readonly property bool held: press.pressed && available
    signal pressed()
    // `strong` (a card's Compare and Reset; the owner: "bright white if enabled,
    // half/transparent if disabled"): white when it can be pressed, a third of that when not.
    property bool strong: false
    property bool danger: false   // it takes something away (Delete): red, the owner's wish
    property color glow: "transparent"   // a sign's color under the pointer (a row's pencil, its bin)
    color: glow.a > 0 ? (press.containsMouse ? glow : Theme.dim) : danger && available ? (press.containsMouse ? Qt.lighter(Theme.red, 1.35) : Theme.red) : strong ? (available ? (press.containsMouse ? Theme.white : Theme.text) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.3))
                  : !available ? Theme.faint : press.containsMouse ? Theme.text : Theme.dim
    font.pixelSize: 12
    width: sign !== "" ? 18 : implicitWidth; height: sign !== "" ? 18 : implicitHeight
    Accessible.role: Accessible.Button; Accessible.name: says
    Icon { visible: button.sign !== ""; anchors.fill: parent; path: button.sign; color: button.color; stroke: 1.9 }
    MouseArea { id: press; anchors { fill: parent; margins: -6 } hoverEnabled: true; onClicked: if (parent.available) parent.pressed() }
}
