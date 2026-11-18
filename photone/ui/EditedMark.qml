import QtQuick
import "."

// "This photo has been edited", on its thumbnail in the library and the filmstrip: two small
// sliders in the accent color on a dark disc (the owner: "some sort of a mark signifying that
// it's been edited in both the Library AND in the filmstrip"). The same disc as the
// filmstrip's Pick and Reject (Filmstrip.qml, Sign), so the three read as one set.
Rectangle {
    objectName: "edited-mark"
    width: 22; height: 22; radius: 11
    color: Qt.rgba(0.05, 0.05, 0.06, 0.66); border { width: 1.5; color: Qt.rgba(1, 1, 1, 0.78) }
    Accessible.role: Accessible.StaticText; Accessible.name: "Edited"
    Icon {
        anchors.centerIn: parent; width: 14; height: 14; color: Theme.mark; stroke: 2.2
        path: "M3 6 H8.5 M12.5 6 H17 M3 14 H6.5 M10.5 14 H17 M8.5 6 a2 2 0 1 0 4 0 a2 2 0 1 0 -4 0 M6.5 14 a2 2 0 1 0 4 0 a2 2 0 1 0 -4 0"
    }
}
