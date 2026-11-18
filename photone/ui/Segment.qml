import QtQuick
import "."

// One choice of several that sit side by side.
Rectangle {
    property string label
    property bool on: false
    property bool available: true
    property bool bright: false   // on glass over the photo: its word is light also when not chosen
    signal chosen()
    width: 52; height: 26; radius: 5
    color: on ? (bright ? Qt.rgba(1, 1, 1, 0.2) : Theme.selected) : "transparent"
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton; Accessible.name: label; Accessible.checked: on
    Keys.onSpacePressed: chosen()
    border { width: activeFocus ? 1 : 0; color: Theme.text }
    Label { anchors.centerIn: parent; text: parent.label; font.pixelSize: 12
            color: parent.on ? Theme.text : parent.available ? (parent.bright ? Qt.rgba(1, 1, 1, 0.82) : Theme.dim) : Theme.faint }
    MouseArea { anchors.fill: parent; onClicked: parent.chosen() }
}
