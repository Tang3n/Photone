import QtQuick
import "."

Rectangle {
    property string label
    property bool on: false   // for a button that stays in while something is going on
    signal pressed()
    width: buttonText.implicitWidth + 28; height: 30; radius: 6
    color: on || buttonArea.containsMouse ? Theme.selected : Theme.raised
    activeFocusOnTab: true
    Accessible.role: Accessible.Button; Accessible.name: label
    Keys.onSpacePressed: pressed()
    Keys.onReturnPressed: pressed()
    border { width: activeFocus ? 1 : 0; color: Theme.text }
    Label { id: buttonText; anchors.centerIn: parent; text: parent.label; color: Theme.text }
    MouseArea { id: buttonArea; anchors.fill: parent; hoverEnabled: true; onClicked: parent.pressed() }
}
