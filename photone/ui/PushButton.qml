import QtQuick
import "."

Rectangle {
    property string label
    property bool on: false   // for a button that stays in while something is going on
    property color tint: "transparent"   // a button that stands out: its ground in this color, darkened under the text
    signal pressed()
    width: buttonText.implicitWidth + 28; height: 30; radius: 6
    color: tint.a > 0 ? Qt.darker(tint, buttonArea.containsMouse ? 1.3 : 1.6) : on || buttonArea.containsMouse ? Theme.selected : Theme.raised
    activeFocusOnTab: true
    Accessible.role: Accessible.Button; Accessible.name: label
    Keys.onSpacePressed: pressed()
    Keys.onReturnPressed: pressed()
    border { width: activeFocus ? 1 : 0; color: Theme.text }
    Label { id: buttonText; anchors.centerIn: parent; text: parent.label; color: Theme.text }
    MouseArea { id: buttonArea; anchors.fill: parent; hoverEnabled: true; onClicked: parent.pressed() }
}
