import QtQuick

// A yes/no test, because judging "which white is brighter" is unreliable: each tile has a
// smaller square of plain SDR white inside it. Seeing the inner square means the tile is
// brighter than SDR white. Small tiles on black: a display dims itself when much of the screen
// is white, which would hide exactly this.
Rectangle {
    id: root
    color: "black"
    focus: true
    property bool hdr: true
    property bool linear: false
    property string swapchain: ""
    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_H || e.key === Qt.Key_Space) { blink.running = false; hdr = !hdr }
        if (e.key === Qt.Key_B) blink.running = !blink.running
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Q) Qt.quit()
    }
    Timer { id: blink; interval: 600; repeat: true; onTriggered: root.hdr = !root.hdr }

    component Tile: ShaderEffect {
        property real level: 1
        property real inset: 1
        property real hdr: root.hdr ? 1 : 0
        property real linear: root.linear ? 1 : 0
        fragmentShader: Qt.resolvedUrl(shaderFile)
    }
    component Note: Text { color: "#8d8d93"; font.pixelSize: 13 }

    Column {
        anchors { left: parent.left; leftMargin: 32; top: parent.top; topMargin: 22 }
        spacing: 18
        Text { color: "#e4e4e6"; font.pixelSize: 16; text: "Photone HDR test  ·  output: " + root.swapchain + (root.hdr ? "  ·  showing HDR" : "  ·  showing SDR (clipped at white)") }
        Note { text: "In which tiles can you see a smaller square in the middle? The first tile (0.5×) is the example: it always shows one." }
        Row {
            spacing: 40
            Repeater {
                model: [0.5, 1, 1.1, 1.25, 1.5, 2, 3, 4]
                Column {
                    spacing: 8
                    Tile { width: 96; height: 96; level: modelData }
                    Note { width: 96; horizontalAlignment: Text.AlignHCenter; text: modelData + "×" }
                }
            }
        }
        Note { text: "One bar, eight steps from 1× to 4× with nothing between them. Count the edges you can see." }
        Row {
            Repeater {
                model: [1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]
                Tile { width: 100; height: 44; level: modelData; inset: 0 }
            }
        }
        Note { text: "Encoding check. From a step back the striped square is half the light of white: it should match the gray beside it." }
        Row {
            Tile { width: 96; height: 64; level: 0; inset: 2 }
            Tile { width: 96; height: 64; level: 0.5; inset: 0 }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 56; color: "#18181a"
        Row {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 32 }
            spacing: 2
            Repeater {
                model: [{ label: "SDR", on: false }, { label: "HDR", on: true }]
                Rectangle {
                    width: 72; height: 32; radius: 6
                    color: root.hdr === modelData.on ? "#3a3a3f" : "#232326"
                    Text { anchors.centerIn: parent; text: modelData.label; font.pixelSize: 13
                           color: root.hdr === modelData.on ? "#e4e4e6" : "#8d8d93" }
                    MouseArea { anchors.fill: parent; onClicked: { blink.running = false; root.hdr = modelData.on } }
                }
            }
        }
        Note {
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 32 }
            text: "Space: SDR / HDR  ·  B: blink between them (anything that flickers is above white)  ·  Esc closes"
        }
    }
}
